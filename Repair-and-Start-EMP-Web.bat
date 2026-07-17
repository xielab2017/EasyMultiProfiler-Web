@echo off
REM Repair-and-Start (V7): auto-installs R + python3 + EMP if missing, then reinstalls R packages.
setlocal EnableExtensions
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0webapp\scripts\launch_emp_web.ps1" -Repair
set "EC=%ERRORLEVEL%"
if not "%EC%"=="0" pause
endlocal & exit /b %EC%