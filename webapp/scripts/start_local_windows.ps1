# Note: $ErrorActionPreference is intentionally NOT set to "Stop" here.
# This script is called from bootstrap_and_start.ps1 which already wraps
# each step in error handling; we want clear Write-Error messages here
# without throwing on the first hiccup.

. "$PSScriptRoot\windows_r_utils.ps1"
Initialize-EMPPaths $PSScriptRoot
$Root = Get-EMPRepoRoot

$ApiPort = if ($env:API_PORT) { $env:API_PORT } else { "8000" }
$WebPort = if ($env:WEB_PORT) { $env:WEB_PORT } else { "8080" }
$RunDir = Join-Path $Root ".local_run"

# Refresh PATH for any install that happened in a different PowerShell window
# or via winget in this session.
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path","User")

$RscriptExe = Resolve-EMPRscriptExe
if (-not $RscriptExe) {
  Write-Host "[emp-error] Rscript.exe not found." -ForegroundColor Red
  Write-Host "  Install R, add its bin folder to PATH, or set one of:"
  Write-Host "    `$env:EMPI_RSCRIPT = 'D:\path\to\Rscript.exe'"
  Write-Host "    `$env:R_HOME      = 'D:\path\to\R-4.x.x'"
  Write-Host "  Or place R under: $(Join-Path (Split-Path -Parent $Root) 'R\R-4.x.x')"
  exit 1
}
Write-Host "Using Rscript: $RscriptExe"

$PythonCmd = Resolve-EMPPython
if (-not $PythonCmd) {
  Write-Host "[emp-error] Python 3 not found (needed to serve the web UI)." -ForegroundColor Red
  Write-Host "  Install it one of these ways, then re-run:"
  Write-Host "    winget install -e --id Python.Python.3.12"
  Write-Host "    or download from https://www.python.org/downloads/ (tick 'Add python.exe to PATH')"
  Write-Host "  Or point us at an existing interpreter:"
  Write-Host "    `$env:EMPI_PYTHON = 'C:\path\to\python.exe'"
  Write-Host "  Note: the Microsoft Store 'python' stub is ignored on purpose."
  exit 1
}
Write-Host "Using Python: $PythonCmd"

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
Stop-EMPListenersOnPorts -Ports @([int]$ApiPort, [int]$WebPort)

$apiCmd = "cd `"$Root`"; `$env:API_PORT=`"$ApiPort`"; & `"$RscriptExe`" `"webapp/backend/run_api.R`" *> `"$ApiLog`""
$apiProc = Start-Process -FilePath "powershell" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-Command",$apiCmd -WindowStyle Hidden -PassThru
$apiProc.Id | Out-File -FilePath $ApiPid -Encoding ascii -Force

# Bind loopback only; avoids stray 0.0.0.0 listeners and matches browser URL 127.0.0.1
$webCmd = "cd `"$Root`"; $PythonCmd webapp/scripts/static_server.py $WebPort `"webapp/frontend`" *> `"$WebLog`""
$webProc = Start-Process -FilePath "powershell" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-Command",$webCmd -WindowStyle Hidden -PassThru
$webProc.Id | Out-File -FilePath $WebPid -Encoding ascii -Force

# R + Bioconductor load can take 30–90s on first start; wait for API before opening the browser.
$healthUrl = "http://127.0.0.1:$ApiPort/api/health"
$deadline = (Get-Date).AddSeconds(120)
$apiReady = $false
while ((Get-Date) -lt $deadline) {
  try {
    $resp = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
    if ($resp.StatusCode -eq 200) { $apiReady = $true; break }
  } catch { }
  Start-Sleep -Seconds 2
}
if (-not $apiReady) {
  $recentLog = if (Test-Path $ApiLog) {
    (Get-Content -Path $ApiLog -Tail 80 -ErrorAction SilentlyContinue) -join [Environment]::NewLine
  } else {
    "(API log was not created.)"
  }
  throw "API not ready after 120s.`nLog: $ApiLog`n$recentLog"
} else {
  Write-Host "API health OK: $healthUrl"
}
Start-Process "http://127.0.0.1:$WebPort/"
Write-Host "EasyMultiProfiler Web (static UI): http://127.0.0.1:$WebPort"
