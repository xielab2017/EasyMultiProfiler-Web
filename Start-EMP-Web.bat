@echo off
REM Quick restart (already installed). First-time / repair: Run-EMP-Web-Windows.bat
setlocal
set ROOT=%~dp0
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%webapp\scripts\start_local_windows.ps1"
endlocal
