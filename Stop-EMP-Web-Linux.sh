#!/usr/bin/env bash
# Stop-EMP-Web-Linux.sh — Linux stopper, mirroring Stop-EMP-Web-Mac.command.
# Delegates to webapp/scripts/stop_local.sh.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT_DIR}"

echo "Stopping EasyMultiProfiler Web v9.1.0 (Linux)..."
bash "${ROOT_DIR}/webapp/scripts/stop_local.sh" "$@"
exit $?
