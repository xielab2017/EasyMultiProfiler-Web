@echo off
REM Quick restart: stop existing services and re-launch.
setlocal EnableExtensions
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0webapp\scripts\stop_local_windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0webapp\scripts\launch_emp_web.ps1"
set "EC=%ERRORLEVEL%"
if not "%EC%"=="0" pause
endlocal & exit /b %EC%