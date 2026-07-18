# bootstrap_and_start.ps1 — V7 zero-dep one-shot installer (Windows).
#
# Steps:
#   1. Install git + python3 if missing          (install_system_deps.ps1)
#   2. Install R (>= 4.3.3) if missing           (install_r.ps1)
#   3. Install CRAN + Bioc + EMP dependencies    (install_runtime.R)
#   4. Start the API + frontend                  (start_local_windows.ps1)
#
# Honours:
#   $env:EMP_AUTO_INSTALL   = "0"     abort when anything is missing
#   $env:EMP_SKIP_R_INSTALL = "1"     skip R auto-install
#   $env:EMP_SKIP_DEPS      = "1"     skip system-deps auto-install
#   $env:EMP_R_VERSION      = "x.y.z" pin a specific R release
param(
  [switch]$NoStart
)

$ErrorActionPreference = "Continue"  # do not abort on individual step errors; we want clean messages

$ScriptsDir = $PSScriptRoot
$InstallDir = Join-Path $ScriptsDir "install"
$RepoRoot   = Resolve-Path (Join-Path $ScriptsDir "..\..")
. "$ScriptsDir\windows_r_utils.ps1"
Initialize-EMPPaths $ScriptsDir

function Write-Step { param($m) Write-Host "[bootstrap] $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "[emp-ok] $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "[emp-warn] $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "[emp-error] $m" -ForegroundColor Red }

# ── Cross-OS auto-detect ────────────────────────────────────────────────
# When invoked via PowerShell 7 (pwsh) on macOS / Linux we hand off to
# the bash bootstrap script so a single script entry point covers all OSes.
$isWinPS = $IsWindows
if ($null -eq $isWinPS) {
  $isWinPS = ($env:OS -eq 'Windows_NT') -or [System.Environment]::OSVersion.Platform -eq 'Win32NT'
}
if (-not $isWinPS) {
  Write-Host "[emp-install] Detected host OS: $($IsLinux ? 'linux' : ($IsMacOS ? 'macos' : 'unknown'))"
  Write-Host "[emp-install] Handing off to bootstrap_and_start.sh"
  $bashCmd = "bash '$ScriptsDir/bootstrap_and_start.sh'"
  & bash -c $bashCmd
  exit $LASTEXITCODE
}

Write-Host "========================================================"
Write-Host "  EasyMultiProfiler Web v7 — bootstrap (Windows)"
Write-Host "  Folder: $RepoRoot"
Write-Host "========================================================"

# Reload machine PATH so we see anything installed by an earlier attempt
# (e.g. user already ran install_r.ps1 in a different PowerShell window).
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path","User")

# ── 1. system deps (git + python3) ─────────────────────────────────────
if ($env:EMP_SKIP_DEPS -ne "1") {
  Write-Step "Step 1/4: install system dependencies (git + python3)"
  & "$InstallDir\install_system_deps.ps1"
  if ($LASTEXITCODE -ne 0) {
    Write-Err "install_system_deps.ps1 failed (exit $LASTEXITCODE). See messages above."
    exit 1
  }
  # Refresh PATH for the just-installed python (winget writes to user/machine PATH).
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
              [System.Environment]::GetEnvironmentVariable("Path","User")
} else {
  Write-Step "Step 1/4: EMP_SKIP_DEPS=1 — skipping system-deps auto-install."
}

# ── 2. R interpreter ───────────────────────────────────────────────────
if ($env:EMP_SKIP_R_INSTALL -ne "1") {
  Write-Step "Step 2/4: install R (>= 4.3.3)"
  & "$InstallDir\install_r.ps1" @{
    Version = $(if ($env:EMP_R_VERSION) { $env:EMP_R_VERSION } else { "4.4.2" })
    CranMirror = $(if ($env:EMP_R_MIRROR) { $env:EMP_R_MIRROR } else { "https://cran.r-project.org" })
  }
  if ($LASTEXITCODE -ne 0) {
    Write-Err "install_r.ps1 failed (exit $LASTEXITCODE). See messages above."
    exit 1
  }
  # Re-read machine PATH so the freshly installed R\bin folder is visible.
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
              [System.Environment]::GetEnvironmentVariable("Path","User")
} else {
  Write-Step "Step 2/4: EMP_SKIP_R_INSTALL=1 — skipping R auto-install."
}

$RscriptExe = Resolve-EMPRscriptExe
if (-not $RscriptExe) {
  Write-Err "Rscript.exe not found after install. Open a new PowerShell window and try again."
  exit 1
}
Write-Ok "Using Rscript: $RscriptExe"

# ── 3. R packages + EMP ────────────────────────────────────────────────
Write-Step "Step 3/4: install CRAN + Bioconductor + EasyMultiProfiler packages (may take 10-30 min)"
$installLog = Join-Path $RepoRoot ".local_run\install_runtime.log"
New-Item -ItemType Directory -Force -Path (Split-Path $installLog) -ErrorAction SilentlyContinue | Out-Null
& $RscriptExe (Join-Path $ScriptsDir "install_runtime.R") *> $installLog
if ($LASTEXITCODE -ne 0) {
  Write-Err "install_runtime.R failed (exit $LASTEXITCODE). See log: $installLog"
  exit 1
}
Write-Ok "R packages + EMP installed."

# ── 4. Start services ──────────────────────────────────────────────────
if (-not $NoStart) {
  Write-Step "Step 4/4: start API + web UI"
  & "$ScriptsDir\start_local_windows.ps1"
  if ($LASTEXITCODE -ne 0) {
    Write-Err "start_local_windows.ps1 failed (exit $LASTEXITCODE). See log: $(Join-Path $RepoRoot '.local_run\api.log')"
    exit 1
  }
}

Write-Host ""
Write-Host "========================================================"
Write-Host "  EasyMultiProfiler Web is running."
Write-Host "  Open: http://127.0.0.1:8080"
Write-Host "  Stop: powershell -File webapp\scripts\stop_local_windows.ps1"
Write-Host "========================================================"
