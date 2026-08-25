@echo off
REM Create Desktop click-to-start / stop shortcuts for EasyMultiProfiler Web.
setlocal EnableExtensions
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0webapp\scripts\create_windows_shortcut.ps1"
echo.
echo  Desktop shortcuts created:
echo    - 启动 EasyMultiProfiler.lnk   (Start panel / one-click start)
echo    - 停止 EasyMultiProfiler.lnk
echo.
pause
endlocal
