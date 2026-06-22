# One-click clone + bootstrap for Windows PowerShell.
# Usage: irm .../install_from_github.ps1 | iex
#    or: powershell -ExecutionPolicy Bypass -File install_from_github.ps1
param(
  [string]$RepoUrl = "https://github.com/xielab2017/EasyMultiProfiler-Web.git",
  [string]$TargetDir = "EasyMultiProfiler-Web",
  [string]$Branch = "v5.0.2"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Write-Error "Git is required. Run: winget install Git.Git"
}

if (Test-Path (Join-Path $TargetDir ".git")) {
  Write-Host "Updating existing repo at $TargetDir ..."
  git -C $TargetDir fetch --all --tags
  git -C $TargetDir checkout $Branch
  git -C $TargetDir pull --ff-only origin $Branch
} else {
  Write-Host "Cloning $RepoUrl -> $TargetDir"
  git clone --branch $Branch $RepoUrl $TargetDir
}

$Root = Resolve-Path $TargetDir
Set-Location $Root

Write-Host "Checking prerequisites ..."
& "$Root\webapp\scripts\check_prerequisites.ps1"

Write-Host "Repair + start (install R packages if needed) ..."
& "$Root\webapp\scripts\repair_and_start_windows.ps1"

Write-Host "Done. Open http://127.0.0.1:8080"
