@echo off
setlocal
if defined EMPI_PYTHON (
  "%EMPI_PYTHON%" "%~dp0webapp\scripts\launch_metadata.py" %*
  exit /b
)
where py >nul 2>nul
if not errorlevel 1 (
  py -3 "%~dp0webapp\scripts\launch_metadata.py" %*
  exit /b
)
python "%~dp0webapp\scripts\launch_metadata.py" %*
exit /b
