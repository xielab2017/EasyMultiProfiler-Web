# Daily Windows launcher: V7 aware — auto-installs R + python3 if missing.
# Usage:
#   powershell -File webapp\scripts\launch_emp_web.ps1
#   powershell -File webapp\scripts\launch_emp_web.ps1 -Repair
param(
  [switch]$Repair,
  [switch]$NoPause,
  [switch]$NoBrowser,
  [switch]$CreateDesktopShortcut
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\windows_r_utils.ps1"
Initialize-EMPPaths $PSScriptRoot
$Root = Get-EMPRepoRoot
Import-EMPRuntimeConfig

$InstallDir = Join-Path $Root "webapp\scripts\install"

# ── Cross-OS auto-detect ────────────────────────────────────────────────
$isWinPS = $IsWindows
if ($null -eq $isWinPS) {
  $isWinPS = ($env:OS -eq 'Windows_NT') -or [System.Environment]::OSVersion.Platform -eq 'Win32NT'
}
if (-not $isWinPS) {
  $hostOsName = "unknown"
  if ($IsLinux) { $hostOsName = "linux" }
  elseif ($IsMacOS) { $hostOsName = "macos" }
  Write-Host "[emp-install] Detected host OS: $hostOsName"
  Write-Host "[emp-install] Handing off to launch_emp_web.sh"
  $argsLine = if ($Repair) { " --repair" } else { "" }
  & bash -c "bash '$PSScriptRoot/launch_emp_web.sh'$argsLine"
  exit $LASTEXITCODE
}

Write-Host "========================================================"
Write-Host "  EasyMultiProfiler Web v7 (Windows)"
Write-Host "  Folder: $Root"
Write-Host "========================================================"
Write-Host ""

try {
  # ── V7: auto-install missing system deps + R if necessary ────────────
  $RscriptExe = Resolve-EMPRscriptExe
  if (-not $RscriptExe -and $env:EMP_AUTO_INSTALL -ne "0") {
    Write-Host "[launch] R not found — invoking V7 auto-installer."
    & "$InstallDir\install_system_deps.ps1"
    if ($LASTEXITCODE -ne 0) { throw "install_system_deps.ps1 failed." }
    & "$InstallDir\install_r.ps1"
    if ($LASTEXITCODE -ne 0) { throw "install_r.ps1 failed." }
    # Refresh PATH for newly added R
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    $RscriptExe = Resolve-EMPRscriptExe
    if (-not $RscriptExe) { throw "Rscript still missing after auto-install." }
  }

  if (-not $RscriptExe) { throw "Rscript not found. Set EMPI_RSCRIPT or install R, then retry." }
  Write-Host "[launch] Rscript: $RscriptExe"

  & "$PSScriptRoot\check_prerequisites.ps1"

  $needInstall = $false
  if ($Repair) {
    $needInstall = $true
  } else {
    # Windows PowerShell 5.1 converts harmless native stderr warnings from R
    # into NativeCommandError when ErrorActionPreference is Stop.
    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $RscriptExe --vanilla -e "quit(status=if (requireNamespace('EasyMultiProfiler', quietly=TRUE)) 0 else 1)" 2>$null
    $packageCheckExit = $LASTEXITCODE
    $ErrorActionPreference = $savedErrorActionPreference
    if ($packageCheckExit -ne 0) {
      $needInstall = $true
      Write-Host "[launch] EasyMultiProfiler not found — first-time install (15–40 min)."
    }
  }

  if ($needInstall -and $env:EMP_SKIP_INSTALL -ne "1") {
    $installR = Join-Path $Root "webapp\scripts\install_runtime.R"
    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $RscriptExe $installR
    $installExit = $LASTEXITCODE
    $ErrorActionPreference = $savedErrorActionPreference
    if ($installExit -ne 0) { throw "install_runtime.R failed (exit $installExit)." }
  }

  if ($NoBrowser) {
    & "$PSScriptRoot\start_local_windows.ps1" -NoBrowser
  } else {
    & "$PSScriptRoot\start_local_windows.ps1"
  }
  Write-Host ""
  Write-Host "Frontend + backend are running in the background."
  Write-Host "You may close this window; the services will keep running."
  Write-Host "Stop: double-click Stop-EMP-Web-Windows.bat"
  Write-Host "  or: powershell -File webapp\scripts\stop_local_windows.ps1"

  # Desktop click-to-start button (idempotent).
  if ($CreateDesktopShortcut -or $env:EMP_CREATE_DESKTOP_SHORTCUT -ne "0") {
    try { & "$PSScriptRoot\create_windows_shortcut.ps1" -Root $Root } catch {}
  }
}
catch {
  $failureMessage = $_.Exception.Message
  if (-not $failureMessage) { $failureMessage = ($_ | Out-String).Trim() }
  if (-not $failureMessage) { $failureMessage = "Unknown PowerShell error." }
  Write-Host ""
  Write-Host "========================================================"
  Write-Host "  Start failed: $failureMessage"
  Write-Host "  Try: Run-EMP-Web-Windows.bat -Repair"
  Write-Host "  Or:  Repair-and-Start-EMP-Web.bat"
  Write-Host "  Or:  Start-EMP-Panel.bat  (button UI)"
  Write-Host "========================================================"
  exit 1
}

if (-not $NoPause -and $env:EMP_NO_PAUSE -ne "1") {
  Write-Host ""
  Read-Host "Press Enter to close this window"
}
