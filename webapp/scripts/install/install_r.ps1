# install_r.ps1 — Download + silently install R for Windows from CRAN.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File install_r.ps1
#   powershell -ExecutionPolicy Bypass -File install_r.ps1 -Version 4.4.2 -CranMirror https://cran.r-project.org
#
# Exit codes:
#   0  success
#   1  hard failure (e.g. R still missing afterwards)
param(
  [string]$Version     = "4.4.2",
  [string]$CranMirror  = "https://cran.r-project.org",
  [switch]$Force       = $false
)

$ErrorActionPreference = "Stop"

function Write-EmpLog  { param($m) Write-Host "[emp-install] $m" -ForegroundColor Cyan }
function Write-EmpOk   { param($m) Write-Host "[emp-ok] $m" -ForegroundColor Green }
function Write-EmpWarn { param($m) Write-Host "[emp-warn] $m" -ForegroundColor Yellow }
function Write-EmpErr  { param($m) Write-Host "[emp-error] $m" -ForegroundColor Red }

# ── Locate any existing Rscript ──────────────────────────────────────────
function Find-Rscript {
  $cmd = Get-Command Rscript.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $candidates = @(
    (Join-Path $env:ProgramFiles "R"),
    (Join-Path ${env:ProgramFiles(x86)} "R")
  ) | Where-Object { $_ }
  foreach ($root in $candidates) {
    if (Test-Path -LiteralPath $root) {
      $exe = Get-ChildItem -LiteralPath $root -Recurse -Filter Rscript.exe -ErrorAction SilentlyContinue |
             Select-Object -First 1
      if ($exe) { return $exe.FullName }
    }
  }
  return $null
}

$rscript = Find-Rscript
if ($rscript -and -not $Force) {
  $cur = (& $rscript -e "cat(as.character(getRversion()))" 2>$null)
  if ($cur -and ([Version]$cur) -ge [Version]"4.3.3") {
    Write-EmpOk "R $cur already installed at $rscript"
    exit 0
  }
  Write-EmpWarn "R $cur present but < 4.3.3; will install R $Version."
}

# ── Pick a CRAN .exe URL ─────────────────────────────────────────────────
# CRAN keeps a redirect at /bin/windows/base/release which always points to the
# current stable release. We honour -Version by stitching the URL ourselves
# (deterministic + offline-resumable).
$arch = (Get-CimInstance Win32_Processor).Architecture
# 9 = x64, 12 = arm64
$archTag = if ($arch -eq 12) { "arm64" } else { "x64" }
$installerName = "R-${Version}-win.exe"
$installerUrl = "${CranMirror}/bin/windows/base/${installerName}"

Write-EmpLog "Downloading $installerUrl"
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("emp-install-r-" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$exePath = Join-Path $tmpDir $installerName

try {
  $wc = New-Object System.Net.WebClient
  $wc.DownloadFile($installerUrl, $exePath)
} catch {
  Write-EmpErr "Download failed: $_"
  Write-EmpErr "Falling back to current-stable: ${CranMirror}/bin/windows/base/release"
  $release = Invoke-WebRequest -Uri "${CranMirror}/bin/windows/base/release" -UseBasicParsing
  $filename = ($release.Content | Select-String -Pattern 'href="(R-[0-9.]+-win\.exe)"' |
               ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1)
  if (-not $filename) {
    Write-EmpErr "Could not derive current R installer name from CRAN."
    exit 1
  }
  $exePath = Join-Path $tmpDir $filename
  $wc.DownloadFile("${CranMirror}/bin/windows/base/${filename}", $exePath)
}

if (-not (Test-Path -LiteralPath $exePath)) {
  Write-EmpErr "Installer missing: $exePath"
  exit 1
}

# ── Silent install ───────────────────────────────────────────────────────
# R for Windows .exe supports /SILENT (Inno Setup) for unattended install.
# /NORESTART avoids an unexpected reboot; /ALLUSERS makes PATH registration
# machine-wide; /DIR pins the install directory.
$installDir = "${env:ProgramFiles}\R\R-${Version}"
$argList = @(
  "/SILENT", "/NORESTART", "/ALLUSERS", "/SP-",
  "/DIR=`"$installDir`""
)

Write-EmpLog "Running installer (this may take a minute)…"
$proc = Start-Process -FilePath $exePath -ArgumentList $argList -Wait -PassThru
if ($proc.ExitCode -ne 0) {
  Write-EmpErr "Installer exited with code $($proc.ExitCode)."
  exit 1
}

# ── Register Rscript on PATH for the current + future sessions ───────────
$binDir = Join-Path $installDir "bin"
if (-not (Test-Path -LiteralPath (Join-Path $binDir "Rscript.exe"))) {
  Write-EmpErr "Rscript.exe not found at ${binDir} after install."
  exit 1
}

$currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($currentPath -notlike "*${binDir}*") {
  [Environment]::SetEnvironmentVariable("Path", "$currentPath;$binDir", "Machine")
  $env:Path = "$env:Path;$binDir"
}
Write-EmpOk "R $Version installed at $installDir (added to machine PATH)."

# Sanity check
$post = Find-Rscript
if (-not $post) {
  Write-EmpErr "Rscript still missing after install."
  exit 1
}
Write-EmpOk "Rscript available: $post"
Write-EmpOk "R $($post | Split-Path | Split-Path -Leaf) version: $((& $post -e 'cat(as.character(getRversion()))' 2>$null))"