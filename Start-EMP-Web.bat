@echo off
setlocal
set ROOT=%~dp0
if exist "%ROOT%webapp\scripts\create_windows_shortcut.ps1" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%webapp\scripts\create_windows_shortcut.ps1" -Root "%ROOT%" >nul 2>nul
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%webapp\scripts\start_local_windows.ps1"
endlocal
