# Invoked by Inno Setup with ExecAsOriginalUser (so the user's proxy settings apply)
# before anything is changed. Downloads the current repo bootstrap loader.
# Exit codes: 0 = ok, 1 = failed, 2 = the proxy requires credentials.
# On failure the reason is written to "<OutputFile>.error".
# -CredentialFile: optional file (line 1 user name, line 2 password); read and deleted at once.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputFile,
    [string]$Url = 'https://storage.googleapis.com/git-repo-downloads/repo',
    [string]$CredentialFile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'proxy_support.ps1')
$errorFile = $OutputFile + '.error'
Remove-Item -LiteralPath $OutputFile, $errorFile -ErrorAction SilentlyContinue

try {
    $credential = $null
    if ($CredentialFile -and (Test-Path -LiteralPath $CredentialFile)) {
        $lines = [IO.File]::ReadAllLines($CredentialFile, [Text.Encoding]::Default)
        Remove-Item -LiteralPath $CredentialFile -Force
        if ($lines.Count -gt 0 -and $lines[0]) {
            $password = if ($lines.Count -gt 1) { $lines[1] } else { '' }
            $credential = New-Object pscredential($lines[0], (ConvertTo-SecureString $password -AsPlainText -Force))
        }
    }
    if ($credential) {
        Invoke-ProxyDownload -Url $Url -OutFile $OutputFile -Credential $credential
    } else {
        Invoke-ProxyDownload -Url $Url -OutFile $OutputFile
    }

    # Sanity check: a Python script of plausible size, not an HTML error or login page.
    $firstLine = [IO.File]::ReadLines($OutputFile) | Select-Object -First 1
    if ((Get-Item -LiteralPath $OutputFile).Length -lt 10000 -or $firstLine -notmatch '^#!.*python') {
        throw 'The downloaded file is not the repo bootstrap loader (proxy or login page?).'
    }
} catch {
    $failure = $_
    Remove-Item -LiteralPath $OutputFile -ErrorAction SilentlyContinue
    $message = "Download from $Url failed " + ($failure.Exception.Message -replace '\s+', ' ')
    [IO.File]::WriteAllText($errorFile, $message, [Text.Encoding]::Default)
    if (Test-ProxyAuthRequired $failure) { exit 2 }
    exit 1
}
