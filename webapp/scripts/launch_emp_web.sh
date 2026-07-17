#!/usr/bin/env bash
# Daily Mac/Linux launcher: V7 aware — will auto-install R if missing.
# Usage:
#   bash webapp/scripts/launch_emp_web.sh           # smart: install only when needed
#   bash webapp/scripts/launch_emp_web.sh --repair  # force reinstall R deps
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

INSTALL_DIR="${ROOT_DIR}/webapp/scripts/install"
SCRIPTS_DIR="${ROOT_DIR}/webapp/scripts"

MODE="${1:-}"
SKIP_INSTALL="${EMP_SKIP_INSTALL:-0}"

# ── V7: if R is missing, bootstrap R + git + python3 ───────────────────
if ! command -v Rscript >/dev/null 2>&1; then
  echo "[launch] R not found on PATH — invoking V7 auto-installer."
  bash "${INSTALL_DIR}/install_system_deps.sh" || {
    echo "[launch] System deps install failed."
    exit 1
  }
  bash "${INSTALL_DIR}/install_r.sh" || {
    echo "[launch] R install failed."
    exit 1
  }
  hash -r
fi

bash "${SCRIPTS_DIR}/check_prerequisites.sh" || true   # informational

need_install=0
if [[ "${MODE}" == "--repair" ]] || [[ "${MODE}" == "repair" ]]; then
  need_install=1
elif ! Rscript -e 'quit(status=if (requireNamespace("EasyMultiProfiler", quietly=TRUE)) 0 else 1)' 2>/dev/null; then
  need_install=1
  echo "[launch] EasyMultiProfiler not found — first-time install will run (may take 15–40 min)."
fi

if [[ "${need_install}" -eq 1 ]] && [[ "${SKIP_INSTALL}" != "1" ]]; then
  bash "${SCRIPTS_DIR}/install_runtime.sh"
fi

bash "${SCRIPTS_DIR}/start_local.sh"

WEB_PORT="${WEB_PORT:-8080}"
URL="http://127.0.0.1:${WEB_PORT}"
if command -v open >/dev/null 2>&1; then
  open "${URL}" >/dev/null 2>&1 || true
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "${URL}" >/dev/null 2>&1 || true
fi
echo "EasyMultiProfiler Web is running: ${URL}"
