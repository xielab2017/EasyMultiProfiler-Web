@echo off
REM One-click daily start: API (:8000) + frontend (:8080) together, then open browser.
setlocal EnableExtensions
cd /d "%~dp0"
title EasyMultiProfiler Web - Starting...
echo ========================================================
echo   EasyMultiProfiler Web — 一键启动
echo   将同时启动：后端 API (:8000) + 前端网页 (:8080)
echo   Folder: %CD%
echo ========================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0webapp\scripts\launch_emp_web.ps1"
set "EC=%ERRORLEVEL%"
if not "%EC%"=="0" (
  echo.
  echo  Start failed. Try Repair-and-Start-EMP-Web.bat or Start-EMP-Panel.bat
  pause
)
endlocal & exit /b %EC%
