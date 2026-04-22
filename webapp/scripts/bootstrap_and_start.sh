#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

"${ROOT_DIR}/webapp/scripts/install_runtime.sh" "$@"
"${ROOT_DIR}/webapp/scripts/start_local.sh"

WEB_PORT="${WEB_PORT:-8080}"
URL="http://127.0.0.1:${WEB_PORT}"

if command -v open >/dev/null 2>&1; then
  open "${URL}" >/dev/null 2>&1 || true
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "${URL}" >/dev/null 2>&1 || true
fi

echo "Open ${URL}"
