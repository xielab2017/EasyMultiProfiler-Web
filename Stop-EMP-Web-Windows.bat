@echo off
REM Double-click launcher (Windows): 终止运行 / Stop EMP Web API + frontend.
REM Companion to Run-EMP-Web-Windows.bat — stops the same PIDs/ports.
setlocal EnableExtensions
cd /d "%~dp0"

echo ========================================================
echo   EasyMultiProfiler Web — 终止运行 / Stop
echo   Stops API (:8000), Web (:8080), and gateway if running
echo ========================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0webapp\scripts\stop_local_windows.ps1"
set "EC=%ERRORLEVEL%"

echo.
if "%EC%"=="0" (
  echo   Done. Local EMP Web services stopped (or were not running).
) else (
  echo   Stop finished with exit code %EC%.
  echo   You can also run: powershell -File webapp\scripts\stop_local_windows.ps1
)
echo.
pause
endlocal & exit /b %EC%
