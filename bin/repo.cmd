@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "APP_ROOT=%%~fI"
set "PYTHON_EXE=%APP_ROOT%\runtime\python\python.exe"
set "REPO_SCRIPT=%APP_ROOT%\runtime\repo\repo"

if exist "%REPO_SCRIPT%\" (
    echo repo: "%REPO_SCRIPT%" is a directory, not the repo bootstrap script.
    echo Expected file: "%APP_ROOT%\runtime\repo\repo".
    exit /b 1
)

if not exist "%PYTHON_EXE%" (
    echo repo: embedded Python runtime not found at "%PYTHON_EXE%".
    echo Prepare the runtime using scripts\prepare_assets.ps1 or reinstall repo.
    exit /b 1
)

if not exist "%REPO_SCRIPT%" (
    echo repo: bootstrap script not found at "%REPO_SCRIPT%".
    echo Prepare the runtime using scripts\prepare_assets.ps1 or reinstall repo.
    exit /b 1
)

"%PYTHON_EXE%" "%REPO_SCRIPT%" %*
