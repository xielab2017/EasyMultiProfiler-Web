# Dot-source from scripts in this folder. Call Initialize-EMPPaths $PSScriptRoot first.
$script:EMP_RepoRoot = $null

function Initialize-EMPPaths {
  param([Parameter(Mandatory)][string]$ScriptsDir)
  $script:EMP_RepoRoot = Split-Path -Parent (Split-Path -Parent $ScriptsDir)
}

function Get-EMPRepoRoot {
  if (-not $script:EMP_RepoRoot) {
    throw "Initialize-EMPPaths was not called (EMP_RepoRoot is empty)."
  }
  return $script:EMP_RepoRoot
}

# Resolve Rscript.exe without requiring a global PATH entry:
#   1. EMPI_RSCRIPT = full path to Rscript.exe
#   2. R_HOME       = R install root (…\R-4.x.x), uses bin\Rscript.exe
#   3. <parent of repo>\R\<R-version>\bin\Rscript.exe  (e.g. D:\Coding\R\R-4.6.0)
#   4. Rscript.exe on PATH
function Resolve-EMPRscriptExe {
  $Root = Get-EMPRepoRoot
  if ($env:EMPI_RSCRIPT -and (Test-Path -LiteralPath $env:EMPI_RSCRIPT)) {
    return (Resolve-Path -LiteralPath $env:EMPI_RSCRIPT).Path
  }
  if ($env:R_HOME) {
    $rp = Join-Path $env:R_HOME "bin\Rscript.exe"
    if (Test-Path -LiteralPath $rp) { return (Resolve-Path -LiteralPath $rp).Path }
  }
  $parent = Split-Path -Parent $Root
  $rSibling = Join-Path $parent "R"
  if (Test-Path -LiteralPath $rSibling) {
    $found = @(
      Get-ChildItem -LiteralPath $rSibling -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
          $exe = Join-Path $_.FullName "bin\Rscript.exe"
          if (Test-Path -LiteralPath $exe) { (Resolve-Path -LiteralPath $exe).Path }
        }
    )
    if ($found.Count -gt 0) {
      return ($found | Sort-Object -Descending | Select-Object -First 1)
    }
  }
  $cmd = Get-Command Rscript.exe -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source) { return $cmd.Source }
  return $null
}

# Resolve a usable Python launcher for the static web server:
#   1. EMPI_PYTHON = full path to python.exe
#   2. `py -3` launcher (official python.org installer ships it)
#   3. python.exe on PATH (skips the Windows Store alias stub)
# Returns a string you can invoke, e.g. "py -3" or "C:\...\python.exe".
function Resolve-EMPPython {
  if ($env:EMPI_PYTHON -and (Test-Path -LiteralPath $env:EMPI_PYTHON)) {
    return ('"' + (Resolve-Path -LiteralPath $env:EMPI_PYTHON).Path + '"')
  }
  $py = Get-Command py.exe -ErrorAction SilentlyContinue
  if ($py -and $py.Source) {
    # Confirm a 3.x interpreter is actually registered with the launcher.
    try {
      $v = & $py.Source -3 --version 2>&1
      if ($LASTEXITCODE -eq 0 -and "$v" -match "Python 3") { return "py -3" }
    } catch {}
  }
  $python = Get-Command python.exe -ErrorAction SilentlyContinue
  if ($python -and $python.Source) {
    # The Windows Store "python.exe" alias lives under WindowsApps and only
    # opens the Store; skip it so we don't silently fail to serve the UI.
    if ($python.Source -notmatch "WindowsApps") {
      try {
        $v = & $python.Source --version 2>&1
        if ($LASTEXITCODE -eq 0 -and "$v" -match "Python 3") {
          return ('"' + $python.Source + '"')
        }
      } catch {}
    }
  }
  return $null
}

# Kill processes in Listen state on these ports (repeat: some stacks expose IPv4/IPv6 separately).
function Stop-EMPListenersOnPorts {
  param([Parameter(Mandatory)][int[]]$Ports)
  foreach ($port in ($Ports | Select-Object -Unique)) {
    for ($round = 0; $round -lt 6; $round++) {
      $conns = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
      if ($conns.Count -eq 0) { break }
      $ids = $conns | Select-Object -ExpandProperty OwningProcess -Unique
      foreach ($id in $ids) {
        try {
          $p = Get-Process -Id $id -ErrorAction SilentlyContinue
          if ($p) {
            Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
            Write-Host "Stopped listener on port $port (PID $id $($p.ProcessName))"
          }
        } catch {}
      }
      Start-Sleep -Milliseconds 400
    }
  }
}
