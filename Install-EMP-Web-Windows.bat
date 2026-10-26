@echo off
REM Install-EMP-Web-Windows.bat - EasyMultiProfiler Web v9.1.0 one-click installer (Windows).
REM Double-click this file in File Explorer.
REM
REM Behaviour:
REM   - If this file sits in a full local copy of the project (the
REM     webapp\scripts\bootstrap_and_start.ps1 file exists next to it),
REM     the local install flow is used (same bootstrap as install.cmd).
REM   - Otherwise the one-line installer is downloaded from GitHub and run.
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

echo.
echo  ============================================================
echo   EasyMultiProfiler Web v9.1.0 - Windows one-click installer
echo   EasyMultiProfiler Web v9.1.0 - Windows 一键安装
echo  ============================================================
echo   This installer checks for Git / Python 3 / R, installs what
echo   is missing, installs EasyMultiProfiler, and starts the web
echo   app at http://127.0.0.1:8080
echo   本安装程序会检查 Git / Python 3 / R，补齐缺失组件，安装
echo   EasyMultiProfiler，并启动网页（http://127.0.0.1:8080）。
echo  ============================================================
echo.

where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo  [ERROR] PowerShell is required but was not found on PATH.
  echo  [错误] 未找到 PowerShell，请先从 https://aka.ms/powershell 安装。
  echo.
  pause
  exit /b 1
)

if exist "%SCRIPT_DIR%\webapp\scripts\bootstrap_and_start.ps1" (
  echo  [install] Local project copy found - running the local installer.
  echo  [安装] 检测到本地项目副本 - 运行本地安装流程。
  echo.
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\webapp\scripts\bootstrap_and_start.ps1"
  set "PS_EXIT=%ERRORLEVEL%"
) else (
  echo  [install] No local project copy - downloading the installer from GitHub.
  echo  [安装] 未检测到本地项目副本 - 从 GitHub 下载安装脚本。
  echo.
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/main/webapp/scripts/install_from_github.ps1 | iex"
  set "PS_EXIT=%ERRORLEVEL%"
)

echo.
if %PS_EXIT% NEQ 0 (
  echo  [ERROR] The installer exited with code %PS_EXIT%. See the messages above.
  echo  [错误] 安装程序以代码 %PS_EXIT% 退出，请查看上方信息。
) else (
  echo  [install] Done. The web server is running in the background.
  echo  [安装] 完成。网页服务已在后台运行。
  echo    Open http://127.0.0.1:8080 in your browser if it did not open.
  echo    如未自动打开，请在浏览器访问 http://127.0.0.1:8080
  echo    Stop: double-click Stop-EMP-Web-Windows.bat
  echo    停止: 双击 Stop-EMP-Web-Windows.bat
)
echo.
echo  Press any key to close this window...
echo  按任意键关闭此窗口...
pause >nul
endlocal
exit /b %PS_EXIT%
