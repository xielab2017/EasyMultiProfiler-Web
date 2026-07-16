@echo off
REM Smart daily start: validates prerequisites and repairs a missing EMP package.
setlocal EnableExtensions
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0webapp\scripts\launch_emp_web.ps1"
set "EC=%ERRORLEVEL%"
if not "%EC%"=="0" pause
endlocal & exit /b %EC%
