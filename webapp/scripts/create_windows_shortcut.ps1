$ErrorActionPreference = "SilentlyContinue"
param(
  [string]$Root = ""
)

if (-not $Root -or -not (Test-Path $Root)) {
  $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

$desktop = [Environment]::GetFolderPath("Desktop")
if (-not $desktop -or -not (Test-Path $desktop)) { exit 0 }

$targetBat = Join-Path $Root "Start-EMP-Web.bat"
if (-not (Test-Path $targetBat)) { exit 0 }

$lnk = Join-Path $desktop "EasyMultiProfiler-Web.lnk"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($lnk)
$shortcut.TargetPath = $targetBat
$shortcut.WorkingDirectory = $Root
$shortcut.WindowStyle = 1
$shortcut.Description = "One-click start EasyMultiProfiler Web"
$shortcut.IconLocation = "$env:SystemRoot\System32\SHELL32.dll,13"
$shortcut.Save()
