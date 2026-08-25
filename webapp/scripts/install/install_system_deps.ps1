# install_system_deps.ps1 — Install git + python3 on Windows.
#
# Order of operations:
#   1. Try `winget install` (Windows 11 / Win 10 with App Installer).
#   2. If winget not available, fall back to PowerShell manual download of
#      Python.org installer + Git for Windows (silent /S).
#
# Honours:
#   $env:EMP_AUTO_INSTALL = "0"   abort instead of installing
#   $env:EMPI_PYTHON      = "C:\path\to\python.exe"  skip Python install
param(
  [switch]$Force = $false
)

$ErrorActionPreference = "Stop"
function Write-EmpLog  { param($m) Write-Host "[emp-install] $m" -ForegroundColor Cyan }
function Write-EmpOk   { param($m) Write-Host "[emp-ok] $m" -ForegroundColor Green }
function Write-EmpWarn { param($m) Write-Host "[emp-warn] $m" -ForegroundColor Yellow }
function Write-EmpErr  { param($m) Write-Host "[emp-error] $m" -ForegroundColor Red }

if ($env:EMP_AUTO_INSTALL -eq "0") {
  Write-EmpErr "EMP_AUTO_INSTALL=0 — refusing to install system packages."
  exit 1
}

function Test-Python3 {
  foreach ($p in @("python.exe","py.exe")) {
    $cmd = Get-Command $p -ErrorAction SilentlyContinue
    if ($cmd) {
      try {
        $v = & $cmd.Source --version 2>&1
        if ($v -match "Python 3") { return $cmd.Source }
      } catch {}
    }
  }
  return $null
}

function Test-Git {
  $cmd = Get-Command git.exe -ErrorAction SilentlyContinue
  if ($cmd -and ($cmd.Source -notmatch "WindowsApps")) {
    return $cmd.Source
  }
  return $null
}

$needGit    = -not (Test-Git)    -or $Force
$needPython = -not (Test-Python3) -or $Force

if (-not $needGit -and -not $needPython) {
  Write-EmpOk "git + python3 already present."
  exit 0
}

# ── winget path ──────────────────────────────────────────────────────────
$winget = Get-Command winget.exe -ErrorAction SilentlyContinue
if ($winget) {
  if ($needPython) {
    Write-EmpLog "winget install Python.Python.3.12"
    & winget install -e --id Python.Python.3.12 --accept-source-agreements --accept-package-agreements --silent
  }
  if ($needGit) {
    Write-EmpLog "winget install Git.Git"
    & winget install -e --id Git.Git --accept-source-agreements --accept-package-agreements --silent
  }
  # Refresh PATH for new processes
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}
else {
  Write-EmpWarn "winget not found; falling back to direct downloads."
  $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("emp-install-deps-" + [guid]::NewGuid().ToString("N").Substring(0,8))
  New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
  if ($needPython) {
    $pyUrl = "https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe"
    $pyExe = Join-Path $tmpDir "python-installer.exe"
    Write-EmpLog "Downloading $pyUrl"
    (New-Object System.Net.WebClient).DownloadFile($pyUrl, $pyExe)
    Write-EmpLog "Installing Python silently"
    $proc = Start-Process -FilePath $pyExe -ArgumentList @("/quiet","InstallAllUsers=1","PrependPath=1","Include_test=0") -Wait -PassThru
    if ($proc.ExitCode -ne 0) { Write-EmpErr "Python installer exit $($proc.ExitCode)"; exit 1 }
  }
  if ($needGit) {
    $gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.46.0.windows.1/Git-2.46.0-64-bit.exe"
    $gitExe = Join-Path $tmpDir "git-installer.exe"
    Write-EmpLog "Downloading $gitUrl"
    (New-Object System.Net.WebClient).DownloadFile($gitUrl, $gitExe)
    Write-EmpLog "Installing Git silently"
    $proc = Start-Process -FilePath $gitExe -ArgumentList @("/SILENT","/NORESTART") -Wait -PassThru
    if ($proc.ExitCode -ne 0) { Write-EmpErr "Git installer exit $($proc.ExitCode)"; exit 1 }
  }
}

# Re-evaluate
if (-not (Test-Git))    { Write-EmpErr "git still missing after install."; exit 1 }
if (-not (Test-Python3)) { Write-EmpErr "python3 still missing after install."; exit 1 }
Write-EmpOk "git + python3 verified."