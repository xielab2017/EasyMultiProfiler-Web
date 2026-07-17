# install_from_github.ps1 — V7 one-line installer for Windows.
#
#   irm https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/v7.0.0/webapp/scripts/install_from_github.ps1 | iex
#
# What it does:
#   1. Detects host OS (Windows / macOS / Linux).
#      - If user runs this .ps1 on macOS / Linux (e.g. PowerShell Core),
#        we transparently hand off to the .sh equivalent so the same oneliner
#        works everywhere.
#   2. Verifies / installs git (so we can clone).
#   3. Clones the repo at -Branch (default v7.0.0).
#   4. Runs the V7 bootstrap — installs python3 + R + EMP if missing,
#      then starts the API + frontend.
param(
  [string]$RepoUrl   = "https://github.com/xielab2017/EasyMultiProfiler-Web.git",
  [string]$TargetDir = "EasyMultiProfiler-Web",
  [string]$Branch    = "v7.0.0"
)

$ErrorActionPreference = "Stop"

function Write-EmpLog  { param($m) Write-Host "[emp-install] $m" -ForegroundColor Cyan }
function Write-EmpOk   { param($m) Write-Host "[emp-ok] $m" -ForegroundColor Green }
function Write-EmpWarn { param($m) Write-Host "[emp-warn] $m" -ForegroundColor Yellow }
function Write-EmpErr  { param($m) Write-Host "[emp-error] $m" -ForegroundColor Red }

# ───────────────────────────────────────────────────────────────────────
# OS auto-detect
# ───────────────────────────────────────────────────────────────────────
# Powershell 5.x (Windows PowerShell) is always Windows. PowerShell 7+
# (pwsh) can run on Windows / macOS / Linux — use RuntimeInformation.
$isWin  = $IsWindows
if ($null -eq $isWin) {
  $isWin = ($env:OS -eq 'Windows_NT') -or [System.Environment]::OSVersion.Platform -eq 'Win32NT'
}
$osName = if ($IsLinux)  { 'linux' }
          elseif ($IsMacOS) { 'macos' }
          elseif ($isWin)   { 'windows' }
          else { 'unknown' }
Write-EmpLog "Detected host OS: $osName"

# ───────────────────────────────────────────────────────────────────────
# On macOS / Linux we forward to the bash equivalent. Same oneliner works
# in any shell.
# ───────────────────────────────────────────────────────────────────────
if (-not $isWin) {
  # Make sure curl + bash are present (they are on every macOS / Linux
  # out of the box, but we double-check so the user gets a clear error).
  if (-not (Get-Command curl -ErrorAction SilentlyContinue)) {
    Write-EmpErr "curl not found. Install it and re-run."
    exit 1
  }
  if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
    Write-EmpErr "bash not found. Install it (brew install bash) and re-run."
    exit 1
  }
  Write-EmpLog "Handing off to install_from_github.sh on $osName"
  # Use environment variables to pass parameters — PowerShell-quoted
  # argument passthrough through `bash -s` is unreliable across pwsh
  # versions, so we avoid positional args entirely.
  $env:EMP_REPO_URL   = $RepoUrl
  $env:EMP_TARGET_DIR = $TargetDir
  $env:EMP_BRANCH     = $Branch
  $url = "https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/$Branch/webapp/scripts/install_from_github.sh"
  Write-EmpLog "Fetching: $url"
  & curl -fsSL "$url" | & bash
  exit $LASTEXITCODE
}

# ───────────────────────────────────────────────────────────────────────
# Windows branch — original logic.
# ───────────────────────────────────────────────────────────────────────

# ── 1. Make sure git exists ────────────────────────────────────────────────
$git = Get-Command git.exe -ErrorAction SilentlyContinue
if (-not $git -or $git.Source -match "WindowsApps") {
  Write-EmpWarn "git not found — installing."
  $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
  if ($winget) {
    & winget install -e --id Git.Git --accept-source-agreements --accept-package-agreements --silent
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
  } else {
    Write-EmpErr "Neither git nor winget is available. Install git manually from https://git-scm.com/download/win and re-run."
    exit 1
  }
}

# ── 2. Clone or refresh the repo ───────────────────────────────────────────
if (Test-Path (Join-Path $TargetDir ".git")) {
  Write-EmpLog "Updating existing repo at $TargetDir ..."
  git -C $TargetDir fetch --all --tags
  git -C $TargetDir checkout $Branch
  git -C $TargetDir pull --ff-only origin $Branch
} else {
  Write-EmpLog "Cloning $RepoUrl (branch $Branch) -> $TargetDir"
  git clone --branch $Branch --depth 1 $RepoUrl $TargetDir
}

# ── 3. Hand off to the V7 bootstrap ────────────────────────────────────────
$Root = Resolve-Path $TargetDir
Set-Location $Root

Write-EmpLog "Running V7 bootstrap (auto-installs R, python3, EMP)…"
& "$Root\webapp\scripts\bootstrap_and_start.ps1"
if ($LASTEXITCODE -ne 0) { throw "bootstrap_and_start.ps1 failed." }