# Self-check: Windows Python resolver must not return multi-token strings.
# Run: powershell -NoProfile -File webapp/scripts/check_windows_python_resolve.ps1
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\windows_r_utils.ps1"
Initialize-EMPPaths $PSScriptRoot

$info = Resolve-EMPPython
if (-not $info) {
  Write-Host "SKIP: no Python on this machine (resolver returned null)."
  exit 0
}
if ($info -isnot [hashtable]) { throw "Resolve-EMPPython must return hashtable, got $($info.GetType().FullName)" }
if (-not $info.ContainsKey("Exe") -or -not $info.Exe) { throw "missing Exe" }
if (-not $info.ContainsKey("PrefixArgs")) { throw "missing PrefixArgs" }
# Guard the old bug: callers used to do & "$cmd" when cmd was "py -3".
if ("$($info.Exe)" -match '\s') { throw "Exe must be a single path, got: $($info.Exe)" }
$display = Format-EMPPythonDisplay $info
Write-Host "OK Resolve-EMPPython => $display"
exit 0
