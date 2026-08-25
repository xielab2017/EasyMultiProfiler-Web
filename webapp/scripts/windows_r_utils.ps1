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

# Load machine-local overrides before resolving R/Python or service settings.
# Format: NAME=value, one entry per line. Existing process variables win so
# callers can still override the file for a single launch.
function Import-EMPRuntimeConfig {
  param([string]$Path)

  if (-not $Path) {
    $Path = Join-Path (Get-EMPRepoRoot) "webapp\config\runtime.env"
  }
  if (-not (Test-Path -LiteralPath $Path)) { return }

  foreach ($rawLine in (Get-Content -LiteralPath $Path -ErrorAction Stop)) {
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith("#") -or -not $line.Contains("=")) { continue }
    $parts = $line.Split(@("="), 2, [System.StringSplitOptions]::None)
    $name = $parts[0].Trim()
    if (-not $name) { continue }
    if (-not [Environment]::GetEnvironmentVariable($name, "Process")) {
      [Environment]::SetEnvironmentVariable($name, $parts[1].Trim(), "Process")
    }
  }
}

function ConvertTo-EMPProcessArgument {
  param([Parameter(Mandatory)][string]$Value)
  if ($Value -notmatch '[\s"]') { return $Value }
  # Start-Process joins ArgumentList into one Windows command line. Quote paths
  # explicitly so repositories under folders such as "D:\My Projects" work.
  return '"' + ($Value -replace '"', '\"') + '"'
}

# Resolve Rscript.exe without requiring a global PATH entry:
#   1. EMPI_RSCRIPT = full path to Rscript.exe
#   2. R_HOME       = R install root (…\R-4.x.x), uses bin\Rscript.exe
#   3. Standard Windows R installation under Program Files
#   4. <parent of repo>\R\<R-version>\bin\Rscript.exe  (e.g. D:\Coding\R\R-4.6.0)
#   5. Rscript.exe on PATH
function Resolve-EMPRscriptExe {
  $Root = Get-EMPRepoRoot
  if ($env:EMPI_RSCRIPT -and (Test-Path -LiteralPath $env:EMPI_RSCRIPT)) {
    return (Resolve-Path -LiteralPath $env:EMPI_RSCRIPT).Path
  }
  if ($env:R_HOME) {
    $rp = Join-Path $env:R_HOME "bin\Rscript.exe"
    if (Test-Path -LiteralPath $rp) { return (Resolve-Path -LiteralPath $rp).Path }
  }
  # Prefer a portable runtime shipped beside the project. This keeps R and its
  # package ABI paired and avoids accidentally selecting a newer system R.
  $portableRoot = Join-Path $Root ".runtime"
  if (Test-Path -LiteralPath $portableRoot) {
    $portableR = @(
      Get-ChildItem -LiteralPath $portableRoot -Directory -Filter "R-*" -ErrorAction SilentlyContinue |
        ForEach-Object {
          $exe = Join-Path $_.FullName "bin\Rscript.exe"
          if (Test-Path -LiteralPath $exe) { (Resolve-Path -LiteralPath $exe).Path }
        }
    )
    if ($portableR.Count -gt 0) {
      return ($portableR | Sort-Object -Descending | Select-Object -First 1)
    }
  }
  $programRoots = @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)}) |
    Where-Object { $_ } | Select-Object -Unique
  $standardR = @(
    foreach ($programRoot in $programRoots) {
      $rDir = Join-Path $programRoot "R"
      if (Test-Path -LiteralPath $rDir) {
        Get-ChildItem -LiteralPath $rDir -Directory -Filter "R-*" -ErrorAction SilentlyContinue |
          ForEach-Object {
            $exe = Join-Path $_.FullName "bin\Rscript.exe"
            if (Test-Path -LiteralPath $exe) { (Resolve-Path -LiteralPath $exe).Path }
          }
      }
    }
  )
  if ($standardR.Count -gt 0) {
    return ($standardR | Sort-Object -Descending | Select-Object -First 1)
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
# Returns hashtable @{ Exe = '...'; PrefixArgs = @(...) } or $null.
# Never return a multi-token string like "py -3" — that breaks & "$cmd".
function Resolve-EMPPython {
  $Root = Get-EMPRepoRoot
  if ($env:EMPI_PYTHON -and (Test-Path -LiteralPath $env:EMPI_PYTHON)) {
    return @{ Exe = (Resolve-Path -LiteralPath $env:EMPI_PYTHON).Path; PrefixArgs = @() }
  }
  $portablePython = @(
    (Join-Path $Root ".runtime\python\python.exe"),
    (Join-Path $Root ".runtime\Python\python.exe")
  )
  foreach ($candidate in $portablePython) {
    if (Test-Path -LiteralPath $candidate) {
      return @{ Exe = (Resolve-Path -LiteralPath $candidate).Path; PrefixArgs = @() }
    }
  }
  $py = Get-Command py.exe -ErrorAction SilentlyContinue
  if ($py -and $py.Source) {
    try {
      $v = & $py.Source -3 --version 2>&1
      if ($LASTEXITCODE -eq 0 -and "$v" -match "Python 3") {
        return @{ Exe = $py.Source; PrefixArgs = @("-3") }
      }
    } catch {}
  }
  $python = Get-Command python.exe -ErrorAction SilentlyContinue
  if ($python -and $python.Source) {
    # Store alias under WindowsApps only opens the Store — skip it.
    if ($python.Source -notmatch "WindowsApps") {
      try {
        $v = & $python.Source --version 2>&1
        if ($LASTEXITCODE -eq 0 -and "$v" -match "Python 3") {
          return @{ Exe = $python.Source; PrefixArgs = @() }
        }
      } catch {}
    }
  }
  return $null
}

function Format-EMPPythonDisplay {
  param($PyInfo)
  if (-not $PyInfo) { return "(none)" }
  if ($PyInfo.PrefixArgs -and $PyInfo.PrefixArgs.Count -gt 0) {
    return ($PyInfo.Exe + " " + ($PyInfo.PrefixArgs -join " "))
  }
  return $PyInfo.Exe
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
    $remaining = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
    if ($remaining.Count -gt 0) {
      $owners = ($remaining | Select-Object -ExpandProperty OwningProcess -Unique) -join ", "
      throw "Port $port is still in use by PID(s) $owners. Stop that process or choose another port."
    }
  }
}
