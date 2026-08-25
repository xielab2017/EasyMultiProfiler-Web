# Stop then start local API + static frontend (no install_runtime.R).
$ErrorActionPreference = "Stop"

& "$PSScriptRoot\stop_local_windows.ps1"
Start-Sleep -Seconds 1
& "$PSScriptRoot\start_local_windows.ps1"
