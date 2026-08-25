param(
  [string]$Root = ""
)
$ErrorActionPreference = "Stop"

if (-not $Root -or -not (Test-Path -LiteralPath $Root)) {
  $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

$desktop = [Environment]::GetFolderPath("Desktop")
if (-not $desktop -or -not (Test-Path -LiteralPath $desktop)) {
  Write-Host "[shortcut] Desktop folder not found; skip."
  exit 0
}

# Prefer panel (visible Start/Stop buttons); fall back to direct start bat.
$panelBat = Join-Path $Root "Start-EMP-Panel.bat"
$startBat = Join-Path $Root "Start-EMP-Web.bat"
$stopBat = Join-Path $Root "Stop-EMP-Web-Windows.bat"
$targetBat = if (Test-Path -LiteralPath $panelBat) { $panelBat } elseif (Test-Path -LiteralPath $startBat) { $startBat } else { $null }
if (-not $targetBat) {
  Write-Host "[shortcut] Start bat not found under $Root"
  exit 0
}

$shell = New-Object -ComObject WScript.Shell

function New-EmpShortcut([string]$LnkPath, [string]$Target, [string]$Desc) {
  $shortcut = $shell.CreateShortcut($LnkPath)
  $shortcut.TargetPath = $Target
  $shortcut.WorkingDirectory = $Root
  $shortcut.WindowStyle = 1
  $shortcut.Description = $Desc
  $shortcut.IconLocation = "$env:SystemRoot\System32\SHELL32.dll,25"
  $shortcut.Save()
  Write-Host "[shortcut] Created: $LnkPath"
}

New-EmpShortcut `
  (Join-Path $desktop "启动 EasyMultiProfiler.lnk") `
  $targetBat `
  "Click to start EasyMultiProfiler Web (API + frontend)"

if (Test-Path -LiteralPath $stopBat) {
  New-EmpShortcut `
    (Join-Path $desktop "停止 EasyMultiProfiler.lnk") `
    $stopBat `
    "Stop EasyMultiProfiler Web API + frontend"
}

# Also keep English alias used by older docs.
New-EmpShortcut `
  (Join-Path $desktop "EasyMultiProfiler-Web.lnk") `
  $targetBat `
  "One-click start EasyMultiProfiler Web (API + frontend)"
