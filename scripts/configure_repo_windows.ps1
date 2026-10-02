[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^S-1-\d+(-\d+)+$')]
    [string]$InstallerUserSid
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$installRoot = Split-Path -Parent $PSScriptRoot
$toolRoot = Join-Path $installRoot 'runtime\repo\repo'
$pythonDir = Join-Path $installRoot 'runtime\python'
$logFile = Join-Path $env:ProgramData 'repo-installer.log'

function Write-Log {
    param([string]$Message)
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logFile -Value "[$stamp] $Message"
}

Write-Log 'Starting repo Windows setup.'

# Resolve the original installer's SID before making any system changes.
# Never fall back to the elevated process identity or a hard-coded account.
$sid = New-Object System.Security.Principal.SecurityIdentifier($InstallerUserSid)
$resolvedAccount = $sid.Translate([System.Security.Principal.NTAccount]).Value
Write-Log "Installation initiated by $resolvedAccount ($($sid.Value))."

# 1) Enable Developer Mode for symbolic link creation support.
$registryView = [Microsoft.Win32.RegistryView]::Registry32
if ([Environment]::Is64BitOperatingSystem) {
    $registryView = [Microsoft.Win32.RegistryView]::Registry64
}
$baseKey = $null
$policyKey = $null
$devKey = $null
try {
    # Explicit view: this must also work when called by 32-bit PowerShell.
    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine, $registryView)
    $policyKey = $baseKey.OpenSubKey('SOFTWARE\Policies\Microsoft\Windows\Appx')
    if ($policyKey -and $policyKey.GetValue('AllowDevelopmentWithoutDevLicense') -eq 0) {
        throw 'Developer Mode is disabled by policy. Contact your administrator; setup does not override policies.'
    }
    $devKey = $baseKey.CreateSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock')
    $devKey.SetValue('AllowDevelopmentWithoutDevLicense', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
    $devKey.Dispose()
    $devKey = $baseKey.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock')
    if ($devKey.GetValue('AllowDevelopmentWithoutDevLicense') -ne 1 -or
        $devKey.GetValueKind('AllowDevelopmentWithoutDevLicense') -ne [Microsoft.Win32.RegistryValueKind]::DWord) {
        throw "Developer Mode registry verification failed ($registryView)."
    }
    Write-Log "Developer Mode registry setting verified: $registryView, AllowDevelopmentWithoutDevLicense=1 (DWORD)."
} catch {
    Write-Log "Developer Mode update failed: $($_.Exception.Message)"
    throw
} finally {
    if ($devKey) { $devKey.Dispose() }
    if ($policyKey) { $policyKey.Dispose() }
    if ($baseKey) { $baseKey.Dispose() }
}

# 2) Assign the original installer user directly, not the UAC admin account.
$privilege = 'SeCreateSymbolicLinkPrivilege'
try {
    Write-Log "Assigning $privilege directly to $resolvedAccount ($($sid.Value))."
    Add-Type -Path (Join-Path $PSScriptRoot 'SymlinkPrivilege.cs')
    [RepoInstaller.SymlinkPrivilege]::Grant($sid.Value)
    Write-Log "Verified $privilege directly for $resolvedAccount ($($sid.Value)). Sign out and back in to refresh the user token."
} catch {
    Write-Log "SeCreateSymbolicLinkPrivilege assignment failed: $($_.Exception.Message)"
    throw
}

# 3) The installer copies the already extracted, private Python runtime.
if (-not (Test-Path (Join-Path $pythonDir 'python.exe') -PathType Leaf)) {
    Write-Log "Embedded Python runtime missing in $pythonDir."
    throw 'Embedded Python runtime was not installed.'
}

# 4) Ensure repo bootstrap script is accessible by the wrapper.
if (-not (Test-Path $toolRoot -PathType Leaf)) {
    Write-Log 'repo bootstrap script is missing in the installation directory.'
    throw 'Repo bootstrap script was not installed.'
}

Write-Log 'repo setup finished.'
