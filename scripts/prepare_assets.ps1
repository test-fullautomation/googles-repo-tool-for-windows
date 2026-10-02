# Download missing assets without requiring a system Python installation.
[CmdletBinding()]
param([switch]$Offline)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $root 'runtime'
$bootstrap = Join-Path $runtime 'repo\repo'
$pythonDir = Join-Path $runtime 'python'
$repoUrl = 'https://storage.googleapis.com/git-repo-downloads/repo'
$pythonUrl = 'https://www.python.org/ftp/python/3.12.9/python-3.12.9-embed-amd64.zip'
$requiredPythonFiles = @('python.exe', 'python312.dll', 'python312.zip', 'python312._pth', 'vcruntime140.dll')

$pythonReady = $true
foreach ($name in $requiredPythonFiles) {
    if (-not (Test-Path (Join-Path $pythonDir $name) -PathType Leaf)) {
        $pythonReady = $false
    }
}
$repoReady = (Test-Path $bootstrap -PathType Leaf) -and ((Get-Item $bootstrap).Length -gt 0)
if ($pythonReady -and $repoReady) {
    Write-Output 'Runtime assets are complete; no download or duplicate files required.'
    return
}
if ($Offline) {
    throw 'Offline runtime incomplete. Run scripts/prepare_assets.ps1 once with internet access.'
}
if (-not $pythonReady -and (Test-Path $pythonDir)) {
    throw 'runtime/python is incomplete. Move it aside before preparing a fresh runtime.'
}

New-Item -ItemType Directory -Path $runtime -Force | Out-Null
$staging = Join-Path $runtime ('.prepare-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging | Out-Null
$previousTls = [Net.ServicePointManager]::SecurityProtocol
try {
    [Net.ServicePointManager]::SecurityProtocol = $previousTls -bor [Net.SecurityProtocolType]::Tls12
    if (-not $repoReady) {
        $download = Join-Path $staging 'repo'
        Invoke-WebRequest -UseBasicParsing -Uri $repoUrl -OutFile $download
        if ((Get-Item $download).Length -eq 0) { throw 'Downloaded repo bootstrap is empty.' }
        New-Item -ItemType Directory -Path (Split-Path -Parent $bootstrap) -Force | Out-Null
        Move-Item -LiteralPath $download -Destination $bootstrap -Force
    }
    if (-not $pythonReady) {
        $archive = Join-Path $staging 'python-embed.zip'
        $extracted = Join-Path $staging 'python'
        Invoke-WebRequest -UseBasicParsing -Uri $pythonUrl -OutFile $archive
        Expand-Archive -LiteralPath $archive -DestinationPath $extracted
        foreach ($name in $requiredPythonFiles) {
            if (-not (Test-Path (Join-Path $extracted $name) -PathType Leaf)) {
                throw "Python archive is missing $name."
            }
        }
        Move-Item -LiteralPath $extracted -Destination $pythonDir
    }
    Write-Output 'Runtime assets prepared; ZIP download is temporary and will be removed.'
} finally {
    [Net.ServicePointManager]::SecurityProtocol = $previousTls
    Remove-Item -LiteralPath $staging -Recurse -Force
}