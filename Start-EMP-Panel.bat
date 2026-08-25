@echo off
REM Windows click-to-start panel: one button starts API (:8000) + frontend (:8080).
setlocal EnableExtensions
cd /d "%~dp0"
title EasyMultiProfiler Web - Start Panel
echo.
echo  Opening start panel (button: start frontend + backend together)...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0webapp\scripts\emp_control_panel.ps1"
set "EC=%ERRORLEVEL%"
if not "%EC%"=="0" (
  echo.
  echo  Panel exited with error %EC%. Falling back to direct start...
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0webapp\scripts\launch_emp_web.ps1"
  set "EC=%ERRORLEVEL%"
  if not "%EC%"=="0" pause
)
endlocal & exit /b %EC%
