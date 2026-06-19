@echo off
setlocal
set ROOT=%~dp0
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%webapp\scripts\repair_and_start_windows.ps1"
endlocal
