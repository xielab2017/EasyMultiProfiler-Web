# Daily Windows launcher: check prerequisites, install EMP if missing, start services.
# Usage:
#   powershell -File webapp\scripts\launch_emp_web.ps1
#   powershell -File webapp\scripts\launch_emp_web.ps1 -Repair
param(
  [switch]$Repair
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\windows_r_utils.ps1"
Initialize-EMPPaths $PSScriptRoot
$Root = Get-EMPRepoRoot

Write-Host "========================================================"
Write-Host "  EasyMultiProfiler Web (Windows)"
Write-Host "  Folder: $Root"
Write-Host "========================================================"
Write-Host ""

try {
  & "$PSScriptRoot\check_prerequisites.ps1"

  $RscriptExe = Resolve-EMPRscriptExe
  if (-not $RscriptExe) { throw "Rscript not found." }

  $needInstall = $false
  if ($Repair) {
    $needInstall = $true
  } else {
    & $RscriptExe -e "quit(status=if (requireNamespace('EasyMultiProfiler', quietly=TRUE)) 0 else 1)" 2>$null
    if ($LASTEXITCODE -ne 0) {
      $needInstall = $true
      Write-Host "[launch] EasyMultiProfiler not found — first-time install (15–40 min)."
    }
  }

  if ($needInstall -and $env:EMP_SKIP_INSTALL -ne "1") {
    $installR = Join-Path $Root "webapp\scripts\install_runtime.R"
    & $RscriptExe $installR
    if ($LASTEXITCODE -ne 0) { throw "install_runtime.R failed (exit $LASTEXITCODE)." }
  }

  & "$PSScriptRoot\start_local_windows.ps1"
  Write-Host ""
  Write-Host "Service is running in the background. Close this window to keep it running."
  Write-Host "Stop: powershell -File webapp\scripts\stop_local_windows.ps1"
}
catch {
  Write-Host ""
  Write-Host "========================================================"
  Write-Host "  Start failed: $($_.Exception.Message)"
  Write-Host "  Try: Run-EMP-Web-Windows.bat -Repair"
  Write-Host "  Or:  Repair-and-Start-EMP-Web.bat"
  Write-Host "========================================================"
  exit 1
}

Write-Host ""
Read-Host "Press Enter to close this window"
