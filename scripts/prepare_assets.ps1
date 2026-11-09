# Prepares runtime\python without requiring a system Python installation.
# (The repo bootstrap loader is not part of the build: Setup downloads the current one.)
# Default: runtime\python is deleted and downloaded again (always current, e.g. for CI).
# -Keep: retain existing runtime data and download only what is missing.
[CmdletBinding()]
param([switch]$Keep)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'proxy_support.ps1')
$root = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $root 'runtime'
$pythonDir = Join-Path $runtime 'python'
# Full CPython from the official NuGet package (a plain ZIP, no installer, no registry entries).
$pythonUrl = 'https://api.nuget.org/v3-flatcontainer/python/3.12.9/python.3.12.9.nupkg'
$pythonSha256 = 'B7240E3117D94DC2446C4B1250E31306ADC817934706937D0992C78F937487BA'
# Parts that are not needed at run time (C headers, import libraries, bundled pip).
$pythonPrune = @('include', 'libs', 'Lib\site-packages\*')
$requiredPythonFiles = @('python.exe', 'python312.dll', 'vcruntime140.dll', 'Lib\os.py', 'DLLs\_ssl.pyd')

function Write-Step([string]$Message) { Write-Output "[prepare_assets] $Message" }

$keepData = $Keep
if ($Keep) {
    Write-Step "Mode 'keep' (-Keep): existing runtime data is kept, only missing parts are downloaded."
} else {
    Write-Step "Mode 'default': existing runtime data is replaced, downloading Python... (use -Keep to retain existing data)"
}

$pythonReady = $true
foreach ($name in $requiredPythonFiles) {
    if (-not (Test-Path (Join-Path $pythonDir $name) -PathType Leaf)) {
        $pythonReady = $false
    }
}
if (-not $keepData) {
    $pythonReady = $false
}
if ($pythonReady) {
    Write-Step "Keeping existing: $pythonDir"
    Write-Output 'Runtime assets are complete; no download or duplicate files required.'
    return
}
if (-not $pythonReady -and $keepData -and (Test-Path $pythonDir)) {
    throw 'runtime/python is incomplete or still uses the old embeddable layout. Run without -Keep to replace it.'
}

New-Item -ItemType Directory -Path $runtime -Force | Out-Null
$staging = Join-Path $runtime ('.prepare-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging | Out-Null
$previousTls = [Net.ServicePointManager]::SecurityProtocol
try {
    if (-not $pythonReady) {
        $archive = Join-Path $staging 'python.nupkg'
        $extracted = Join-Path $staging 'python'
        Write-Step "Downloading Python package: $pythonUrl"
        Save-Download -Url $pythonUrl -OutFile $archive -Interactive ([Environment]::UserInteractive -and -not $env:CI)
        Write-Step ('Downloaded {0:N1} MB to temporary file {1}' -f ((Get-Item $archive).Length / 1MB), $archive)
        if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $pythonSha256) {
            throw 'Downloaded Python package does not match the expected SHA-256.'
        }
        Write-Step "SHA-256 verified: $pythonSha256"

        # Extract only the tools\ folder (the interpreter); reject paths that escape the target.
        Write-Step "Extracting tools\ from the package to $extracted"
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $target = [IO.Path]::GetFullPath($extracted) + [IO.Path]::DirectorySeparatorChar
        $zip = [IO.Compression.ZipFile]::OpenRead($archive)
        try {
            foreach ($entry in $zip.Entries) {
                if ($entry.FullName -notlike 'tools/*' -or -not $entry.Name) { continue }
                $dest = [IO.Path]::GetFullPath((Join-Path $extracted $entry.FullName.Substring(6)))
                if (-not $dest.StartsWith($target, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Unsafe path in Python package: $($entry.FullName)"
                }
                New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $true)
            }
        } finally {
            $zip.Dispose()
        }

        foreach ($item in $pythonPrune) {
            Write-Step "Removing unneeded: $item"
            Remove-Item -Path (Join-Path $extracted $item) -Recurse -Force -ErrorAction SilentlyContinue
        }
        foreach ($name in $requiredPythonFiles) {
            if (-not (Test-Path (Join-Path $extracted $name) -PathType Leaf)) {
                throw "Python package is missing $name."
            }
        }

        # Precompile the standard library: Program Files is read-only for normal users, so
        # without cached bytecode every start would recompile it (about 5x slower).
        # unchecked-hash keeps the cache valid regardless of file timestamps.
        $python = Join-Path $extracted 'python.exe'
        Write-Step 'Precompiling the standard library (unchecked-hash .pyc)'
        & $python -I -m compileall -q -j 0 --invalidation-mode unchecked-hash (Join-Path $extracted 'Lib')
        if ($LASTEXITCODE -ne 0) { throw 'Precompiling the Python standard library failed.' }
        & $python -I -c 'import ssl, ctypes, sqlite3'
        if ($LASTEXITCODE -ne 0) { throw 'The prepared Python runtime does not start correctly.' }
        # Replace the old runtime only now, after download, hash check and smoke test succeeded.
        if (Test-Path $pythonDir) {
            Write-Step "Replacing existing $pythonDir"
            Remove-Item -LiteralPath $pythonDir -Recurse -Force
        }
        Move-Item -LiteralPath $extracted -Destination $pythonDir
        $size = Get-ChildItem -LiteralPath $pythonDir -Recurse -File | Measure-Object Length -Sum
        Write-Step ('Installed Python ({0} files, {1:N1} MB) -> {2}' -f $size.Count, ($size.Sum / 1MB), $pythonDir)
    }
    Write-Step 'Removing temporary download folder.'
    Write-Output 'Runtime assets prepared; ZIP download is temporary and will be removed.'
} finally {
    [Net.ServicePointManager]::SecurityProtocol = $previousTls
    Remove-Item -LiteralPath $staging -Recurse -Force
}