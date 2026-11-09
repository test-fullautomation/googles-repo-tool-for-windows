@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Resolve all paths relative to this script, not the caller's directory.
pushd "%~dp0"
if errorlevel 1 exit /b 1

if not exist "tools\InnoSetup5.5.1\ISCC.exe" (
    echo ERROR: Missing tools\InnoSetup5.5.1\ISCC.exe. 1>&2
    popd
    exit /b 1
)

rem Default: delete and download the runtime (Python) again.
rem --keep-runtime (first argument only, not passed to ISCC): keep existing runtime
rem data and download only what is missing. All other arguments go to ISCC unchanged.
set "KEEP_RUNTIME="
set ISCC_ARGS=%*
if /i not "%~1"=="--keep-runtime" goto args_done
set "KEEP_RUNTIME=-Keep"
set ISCC_ARGS=%ISCC_ARGS:~14%
:args_done

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\prepare_assets.ps1" %KEEP_RUNTIME%
if errorlevel 1 (
    echo ERROR: Preparing the runtime assets failed. 1>&2
    popd
    exit /b 1
)

"tools\InnoSetup5.5.1\ISCC.exe" %ISCC_ARGS% "installer\repo_installer.iss"
set "BUILD_EXIT_CODE=%ERRORLEVEL%"
popd
exit /b %BUILD_EXIT_CODE%