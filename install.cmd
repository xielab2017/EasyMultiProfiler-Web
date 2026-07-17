@echo off
REM ───────────────────────────────────────────────────────────────────────
REM install.cmd — Windows CMD / PowerShell double-click entry point.
REM Auto-detects whether PowerShell is available, then delegates to the
REM proper V7 bootstrap.
REM
REM You can run this from:
REM   • Windows CMD          : install.cmd
REM   • PowerShell           : .\install.cmd
REM   • File Explorer double-click : just install.cmd
REM ───────────────────────────────────────────────────────────────────────
setlocal
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

where powershell.exe >nul 2>&1
if %ERRORLEVEL% == 0 (
  echo [install.cmd] Detected PowerShell — handing off to bootstrap_and_start.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\webapp\scripts\bootstrap_and_start.ps1"
) else (
  echo [install.cmd][ERROR] PowerShell is required but not on PATH.
  echo   Install it from https://aka.ms/powershell and re-run.
  exit /b 1
)
endlocal