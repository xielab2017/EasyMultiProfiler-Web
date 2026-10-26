#!/usr/bin/env bash
# Start-EMP-Web-Linux.sh — Linux launcher, mirroring Run-EMP-Web-Mac.command.
# Delegates to webapp/scripts/start_local.sh.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT_DIR}"

echo "================================================================"
echo "  EasyMultiProfiler Web v9.1.0  (Linux launcher)"
echo "  Folder: ${ROOT_DIR}"
echo "  Windows users: use Run-EMP-Web-Windows.bat instead"
echo "  macOS users:   use Run-EMP-Web-Mac.command instead"
echo "================================================================"
echo ""

bash "${ROOT_DIR}/webapp/scripts/start_local.sh" "$@"
ec=$?

if [ "${ec}" -ne 0 ]; then
  echo ""
  echo "Startup failed (exit ${ec}). See the messages above."
  echo "Retry with repair: bash webapp/scripts/launch_emp_web.sh --repair"
fi
exit "${ec}"
