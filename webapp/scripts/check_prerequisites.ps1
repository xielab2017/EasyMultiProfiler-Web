# Check Git, Python, R for EMP-Web on Windows.
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\windows_r_utils.ps1"
Initialize-EMPPaths $PSScriptRoot
Import-EMPRuntimeConfig

Write-Host "[check] EasyMultiProfiler Web — prerequisite check (Windows)"

$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) { Write-Host "[check] Git: $(git --version)" }
else {
  Write-Host "[FAIL] Git not found. Install: winget install Git.Git"
  exit 1
}

$PythonInfo = Resolve-EMPPython
if ($PythonInfo) {
  $pyVer = & $PythonInfo.Exe @($PythonInfo.PrefixArgs + @("--version")) 2>&1
  Write-Host "[check] Python: $(Format-EMPPythonDisplay $PythonInfo) ($pyVer)"
} else {
  Write-Host "[FAIL] Python 3 not found (the Microsoft Store 'python' stub doesn't count)."
  Write-Host "       Install: winget install -e --id Python.Python.3.12"
  Write-Host "       or set: `$env:EMPI_PYTHON = 'C:\path\to\python.exe'"
  exit 1
}

$RscriptExe = Resolve-EMPRscriptExe
if (-not $RscriptExe) {
  Write-Host ""
  Write-Host "════════════════════════════════════════════════════════"
  Write-Host "  Rscript not found. Install R >= 4.3.3 first:"
  Write-Host "    winget install --id RProject.R -e"
  Write-Host "  Then reopen PowerShell and run Repair-and-Start-EMP-Web.bat"
  Write-Host "  Details: docs/INSTALL_WINDOWS.md"
  Write-Host "════════════════════════════════════════════════════════"
  exit 1
}
Write-Host "[check] Rscript: $RscriptExe"
$savedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $RscriptExe -e "if (getRversion() < '4.3.3') stop('R >= 4.3.3 required')"
$rVersionExit = $LASTEXITCODE
$ErrorActionPreference = $savedErrorActionPreference
if ($rVersionExit -ne 0) {
  Write-Host "[FAIL] R version check failed (exit $rVersionExit)."
  exit 1
}
Write-Host "[check] All prerequisites OK."
