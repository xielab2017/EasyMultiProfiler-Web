@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ========================================================
echo   EasyMultiProfiler Web v7  (Windows launcher)
echo   Double-click this file on Windows — NOT the .command file
echo ========================================================
echo.

set "MODE=%~1"
if /I "%MODE%"=="-Repair" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0webapp\scripts\launch_emp_web.ps1" -Repair
) else if /I "%MODE%"=="--repair" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0webapp\scripts\launch_emp_web.ps1" -Repair
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0webapp\scripts\launch_emp_web.ps1"
)

set "EC=%ERRORLEVEL%"
if not "%EC%"=="0" pause
endlocal & exit /b %EC%