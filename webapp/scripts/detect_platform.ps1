# detect_platform.ps1 - EMP Web v9.1.0 platform auto-detection (Windows).
# Prints one JSON object on stdout with the same shape as detect_platform.sh:
#   {"os":"windows","arch":"...","distro":"...",
#    "r_version":"...","python_version":"...","git_version":"..."}
$ErrorActionPreference = "SilentlyContinue"

$arch = $env:PROCESSOR_ARCHITECTURE
if (-not $arch) { $arch = "unknown" }

$distro = ""
try {
  $osInfo = Get-CimInstance Win32_OperatingSystem
  if ($osInfo) { $distro = "$($osInfo.Caption) $($osInfo.Version)" }
} catch { $distro = "Windows" }

$rVersion = ""
$rscript = Get-Command Rscript.exe -ErrorAction SilentlyContinue
if ($rscript) {
  $rOut = & $rscript.Source -e "cat(as.character(getRversion()))" 2>$null
  if ($rOut) { $rVersion = "$rOut".Trim() }
}

$pythonVersion = ""
$py = Get-Command python.exe -ErrorAction SilentlyContinue
if ($py) {
  $pyOut = & $py.Source -c "import platform; print(platform.python_version())" 2>$null
  if ($pyOut) { $pythonVersion = "$pyOut".Trim() }
}

$gitVersion = ""
$git = Get-Command git.exe -ErrorAction SilentlyContinue
if ($git) {
  $gitOut = & $git.Source --version 2>$null
  if ($gitOut) { $gitVersion = "$gitOut".Replace("git version ", "").Trim() }
}

$result = [ordered]@{
  os             = "windows"
  arch           = $arch
  distro         = $distro
  r_version      = $rVersion
  python_version = $pythonVersion
  git_version    = $gitVersion
}
$result | ConvertTo-Json -Compress
