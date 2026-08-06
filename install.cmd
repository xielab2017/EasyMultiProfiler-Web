@echo off
REM install.cmd - Windows CMD / PowerShell double-click entry point.
REM Auto-detects whether PowerShell is available, then delegates to the
REM proper V7 bootstrap.
REM
REM Run this from:
REM   - Windows CMD          : install.cmd
REM   - PowerShell           : .\install.cmd
REM   - File Explorer double-click : install.cmd
REM
REM The CMD window stays open after the bootstrap finishes (or fails) so
REM you can see the log. Press any key to close it.
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo.
  echo  [install.cmd][ERROR] PowerShell is required but not on PATH.
  echo    Install it from https://aka.ms/powershell and re-run.
  echo.
  pause
  exit /b 1
)

echo.
echo  [install.cmd] EasyMultiProfiler Web v7 - one-line installer
echo  [install.cmd] Repo: %SCRIPT_DIR%
echo  [install.cmd] Detected PowerShell - handing off to bootstrap_and_start.ps1
echo  [install.cmd] (CMD window will stay open after the bootstrap finishes.)
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\webapp\scripts\bootstrap_and_start.ps1"
set "PS_EXIT=%ERRORLEVEL%"

echo.
if %PS_EXIT% NEQ 0 (
  echo  [install.cmd][ERROR] bootstrap_and_start.ps1 exited with code %PS_EXIT%.
  echo    See the messages above for what went wrong.
) else (
  echo  [install.cmd] bootstrap finished. The web server is running in the background.
  echo    Open http://127.0.0.1:8080 in the browser if it did not open automatically.
  echo    Stop: double-click Stop-EMP-Web-Windows.bat
)
echo.
echo  Press any key to close this window...
pause >nul
endlocal
exit /b %PS_EXIT%
