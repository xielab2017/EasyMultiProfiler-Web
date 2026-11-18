#!/usr/bin/env bash
# Daily Mac/Linux launcher: V7 aware — will auto-install R if missing.
# Usage:
#   bash webapp/scripts/launch_emp_web.sh           # smart: install only when needed
#   bash webapp/scripts/launch_emp_web.sh --repair  # force reinstall R deps
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"
if [[ -d "${ROOT_DIR}/.local_run/R_libs" ]]; then
  export R_LIBS_USER="${ROOT_DIR}/.local_run/R_libs${R_LIBS_USER:+:${R_LIBS_USER}}"
fi

INSTALL_DIR="${ROOT_DIR}/webapp/scripts/install"
SCRIPTS_DIR="${ROOT_DIR}/webapp/scripts"

MODE="${1:-}"
SKIP_INSTALL="${EMP_SKIP_INSTALL:-0}"

for option in "$@"; do
  if [[ "$option" == "--dry-run" ]]; then export EMP_DRY_RUN=1; fi
done
if [[ "${EMP_DRY_RUN:-0}" == "1" ]]; then
  bash "${SCRIPTS_DIR}/check_prerequisites.sh"
  exec bash "${SCRIPTS_DIR}/start_local.sh" --dry-run
fi

# ── V7: if R is missing, bootstrap R + git + python3 ───────────────────
if ! RSCRIPT="$(bash "${SCRIPTS_DIR}/resolve_rscript.sh")"; then
  [[ -z "${EMPI_RSCRIPT:-}" ]] || exit 1
  echo "[launch] No compatible R installation found — invoking auto-installer."
  bash "${INSTALL_DIR}/install_system_deps.sh" || {
    echo "[launch] System deps install failed."
    exit 1
  }
  bash "${INSTALL_DIR}/install_r.sh" || {
    echo "[launch] R install failed."
    exit 1
  }
  RSCRIPT="$(bash "${SCRIPTS_DIR}/resolve_rscript.sh")"
fi
export EMPI_RSCRIPT="$RSCRIPT"

bash "${SCRIPTS_DIR}/check_prerequisites.sh"

need_install=0
if [[ "${MODE}" == "--repair" ]] || [[ "${MODE}" == "repair" ]]; then
  need_install=1
elif ! "$RSCRIPT" --vanilla "${SCRIPTS_DIR}/check_runtime.R" "${ROOT_DIR}"; then
  need_install=1
fi

if [[ "${need_install}" -eq 1 ]]; then
  if [[ "${SKIP_INSTALL}" == "1" ]]; then
    echo "[launch] EMP_SKIP_INSTALL=1 — skipping R package installation."
  else
    echo "[launch] Installing R runtime packages."
    bash "${SCRIPTS_DIR}/install_runtime.sh"
  fi
fi

exec bash "${SCRIPTS_DIR}/start_local.sh" --open-browser
