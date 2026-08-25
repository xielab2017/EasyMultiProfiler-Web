# Stop local API (Plumber), static web, and optional gateway started by start_local_windows.ps1 / launch_emp_web.ps1.
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\windows_r_utils.ps1"
Initialize-EMPPaths $PSScriptRoot
$Root = Get-EMPRepoRoot
Import-EMPRuntimeConfig

$RunDir = Join-Path $Root ".local_run"
$ApiPid = Join-Path $RunDir "api.pid"
$WebPid = Join-Path $RunDir "web.pid"
$GwPid = Join-Path $RunDir "gateway.pid"

function Stop-PidFile($pidFile, $label) {
  if (Test-Path $pidFile) {
    $pidValue = Get-Content $pidFile -ErrorAction SilentlyContinue
    if ($pidValue) {
      try {
        $proc = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
        if ($proc) {
          Stop-Process -Id ([int]$pidValue) -Force -ErrorAction SilentlyContinue
          Write-Host "Stopped $label process $pidValue"
        } else {
          Write-Host "No live $label for $pidFile"
        }
      } catch {}
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
  }
}

Stop-PidFile $ApiPid "API"
Stop-PidFile $WebPid "Web"
Stop-PidFile $GwPid "Gateway"

$apiP = if ($env:API_PORT) { [int]$env:API_PORT } else { 8000 }
$webP = if ($env:WEB_PORT) { [int]$env:WEB_PORT } else { 8080 }
$gwP = if ($env:GATEWAY_PORT) { [int]$env:GATEWAY_PORT } else { 8090 }
Stop-EMPListenersOnPorts -Ports @($apiP, $webP, $gwP)

Write-Host "Local EMP web services stopped (or were not running)."
