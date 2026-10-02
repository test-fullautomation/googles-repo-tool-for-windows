# Invoked by Inno Setup with ExecAsOriginalUser, before any privileged changes.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputFile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
try {
    if (-not $identity.User -or $identity.IsSystem -or $identity.IsAnonymous) {
        throw 'Setup must be started by a Windows user, not a system or anonymous account.'
    }
    [System.IO.File]::WriteAllText(
        $OutputFile, $identity.User.Value, [System.Text.Encoding]::ASCII)
} finally {
    $identity.Dispose()
}