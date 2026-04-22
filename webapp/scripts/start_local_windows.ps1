$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ApiPort = if ($env:API_PORT) { $env:API_PORT } else { "8000" }
$WebPort = if ($env:WEB_PORT) { $env:WEB_PORT } else { "8080" }
$RunDir = Join-Path $Root ".local_run"
$ApiLog = Join-Path $RunDir "api.log"
$WebLog = Join-Path $RunDir "web.log"
$ApiPid = Join-Path $RunDir "api.pid"
$WebPid = Join-Path $RunDir "web.pid"

New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

function Stop-PidFile($pidFile) {
  if (Test-Path $pidFile) {
    $pidValue = Get-Content $pidFile -ErrorAction SilentlyContinue
    if ($pidValue) {
      try { Stop-Process -Id ([int]$pidValue) -Force -ErrorAction SilentlyContinue } catch {}
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
  }
}

Stop-PidFile $ApiPid
Stop-PidFile $WebPid

$apiCmd = "cd `"$Root`"; `$env:API_PORT=`"$ApiPort`"; Rscript `"webapp/backend/run_api.R`" *> `"$ApiLog`""
$apiProc = Start-Process -FilePath "powershell" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-Command",$apiCmd -WindowStyle Hidden -PassThru
$apiProc.Id | Out-File -FilePath $ApiPid -Encoding ascii -Force

$webCmd = "cd `"$Root`"; python -m http.server $WebPort --directory `"webapp/frontend`" *> `"$WebLog`""
$webProc = Start-Process -FilePath "powershell" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-Command",$webCmd -WindowStyle Hidden -PassThru
$webProc.Id | Out-File -FilePath $WebPid -Encoding ascii -Force

Start-Sleep -Seconds 2
Start-Process "http://127.0.0.1:$WebPort"
Write-Host "EasyMultiProfiler Web started: http://127.0.0.1:$WebPort"
