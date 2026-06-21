# Stop local API (Plumber) and static web (python http.server) started by start_local_windows.ps1.
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\windows_r_utils.ps1"
Initialize-EMPPaths $PSScriptRoot
$Root = Get-EMPRepoRoot
$RunDir = Join-Path $Root ".local_run"
$ApiPid = Join-Path $RunDir "api.pid"
$WebPid = Join-Path $RunDir "web.pid"

function Stop-PidFile($pidFile) {
  if (Test-Path $pidFile) {
    $pidValue = Get-Content $pidFile -ErrorAction SilentlyContinue
    if ($pidValue) {
      try {
        Stop-Process -Id ([int]$pidValue) -Force -ErrorAction SilentlyContinue
        Write-Host "Stopped process $pidValue ($pidFile)"
      } catch {}
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
  }
}

Stop-PidFile $ApiPid
Stop-PidFile $WebPid

$apiP = if ($env:API_PORT) { [int]$env:API_PORT } else { 8000 }
$webP = if ($env:WEB_PORT) { [int]$env:WEB_PORT } else { 8080 }
Stop-EMPListenersOnPorts -Ports @($apiP, $webP)

Write-Host "Local EMP web services stopped (or were not running)."
