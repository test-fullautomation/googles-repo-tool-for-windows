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

"tools\InnoSetup5.5.1\ISCC.exe" %* "repo_installer.iss"
set "BUILD_EXIT_CODE=%ERRORLEVEL%"
popd
exit /b %BUILD_EXIT_CODE%