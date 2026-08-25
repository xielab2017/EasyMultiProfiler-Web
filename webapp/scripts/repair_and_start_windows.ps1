# Repair R runtime (CRAN/Bioc + EasyMultiProfiler), then start API + static frontend.
# V7: also auto-installs R + python3 + git if missing.
param([switch]$NoBrowser)

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
  Write-Host "[emp-install] Handing off to launch_emp_web.sh --repair"
  & bash -c "bash '$PSScriptRoot/launch_emp_web.sh' --repair"
  exit $LASTEXITCODE
}

Write-Host "=== [0/3] V7 auto-install: R + python3 + git if missing ==="
$RscriptExe = Resolve-EMPRscriptExe
if (-not $RscriptExe) {
  Write-Host "[repair] R not found — running V7 installers."
  & "$InstallDir\install_system_deps.ps1"
  if ($LASTEXITCODE -ne 0) { throw "install_system_deps.ps1 failed." }
  & "$InstallDir\install_r.ps1"
  if ($LASTEXITCODE -ne 0) { throw "install_r.ps1 failed." }
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
  $RscriptExe = Resolve-EMPRscriptExe
  if (-not $RscriptExe) { throw "Rscript still missing after auto-install." }
}
Write-Host "[repair] Rscript: $RscriptExe"

Write-Host "=== [1/3] Prerequisites ==="
& "$PSScriptRoot\check_prerequisites.ps1"

Write-Host "=== [2/3] Repair: install_runtime.R ==="
$installR = Join-Path $Root "webapp\scripts\install_runtime.R"
$savedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $RscriptExe $installR
$installExit = $LASTEXITCODE
$ErrorActionPreference = $savedErrorActionPreference
if ($installExit -ne 0) {
  throw "install_runtime.R exited with code $installExit. Fix errors above, then retry."
}

Write-Host ""
Write-Host "=== [3/3] Start: API + web UI ==="
if ($NoBrowser) {
  & "$PSScriptRoot\start_local_windows.ps1" -NoBrowser
} else {
  & "$PSScriptRoot\start_local_windows.ps1"
}
