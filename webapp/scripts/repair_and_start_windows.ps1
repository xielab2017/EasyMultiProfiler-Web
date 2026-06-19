# Repair R runtime (CRAN/Bioc + EasyMultiProfiler), then start API + static frontend.
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\windows_r_utils.ps1"
Initialize-EMPPaths $PSScriptRoot
$Root = Get-EMPRepoRoot

$RscriptExe = Resolve-EMPRscriptExe
if (-not $RscriptExe) {
  Write-Error @"
Rscript.exe not found.
  Install R, add its bin folder to PATH, or set one of:
    `$env:EMPI_RSCRIPT = 'D:\path\to\Rscript.exe'
    `$env:R_HOME      = 'D:\path\to\R-4.x.x'
  Or place R under: $(Join-Path (Split-Path -Parent $Root) 'R\R-4.x.x')
"@
}

Write-Host "=== [1/2] Repair: install_runtime.R ==="
Write-Host "Using Rscript: $RscriptExe"
$installR = Join-Path $Root "webapp\scripts\install_runtime.R"
& $RscriptExe $installR
if ($LASTEXITCODE -ne 0) {
  Write-Error "install_runtime.R exited with code $LASTEXITCODE. Fix errors above, then retry."
}

Write-Host ""
Write-Host "=== [2/2] Start: API + web UI ==="
& "$PSScriptRoot\start_local_windows.ps1"
