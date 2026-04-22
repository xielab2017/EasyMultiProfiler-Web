@echo off
setlocal
set ROOT=%~dp0
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%webapp\scripts\start_local_windows.ps1"
endlocal
