@echo off
setlocal
set ROOT=%~dp0
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%webapp\scripts\restart_local_windows.ps1"
endlocal
