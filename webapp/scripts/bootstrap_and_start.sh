#!/usr/bin/env bash
# bootstrap_and_start.sh — V7 zero-dep one-shot installer.
#
# From a fresh `git clone` of EasyMultiProfiler-Web:
#   1. Install git + python3 if missing              (install_system_deps.sh)
#   2. Install R (>= 4.3.3) if missing               (install_r.sh)
#   3. Install CRAN + Bioc + EMP dependencies        (install_runtime.sh)
#   4. Start the API + frontend                      (start_local.sh)
#
# Honours:
#   EMP_AUTO_INSTALL=0     – skip auto-install steps; treat as prerequisite fail
#   EMP_SKIP_R_INSTALL=1   – don't try to install R
#   EMP_SKIP_DEPS=1        – don't try to install git/python3
#   EMP_R_VERSION=x.y.z    – pin a specific R release (default 4.4.2)
#   EMP_R_MIRROR=URL       – override CRAN mirror
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"
if [[ -d "${ROOT_DIR}/.local_run/R_libs" ]]; then
  export R_LIBS_USER="${ROOT_DIR}/.local_run/R_libs${R_LIBS_USER:+:${R_LIBS_USER}}"
fi

SCRIPTS_DIR="${ROOT_DIR}/webapp/scripts"
INSTALL_DIR="${SCRIPTS_DIR}/install"

echo "════════════════════════════════════════════════════════"
echo "  EasyMultiProfiler Web — bootstrap"
echo "  Folder: ${ROOT_DIR}"
echo "════════════════════════════════════════════════════════"

for option in "$@"; do
  if [[ "$option" == "--dry-run" ]]; then export EMP_DRY_RUN=1; fi
done
if [[ "${EMP_DRY_RUN:-0}" == "1" ]]; then
  bash "${SCRIPTS_DIR}/check_prerequisites.sh"
  exec bash "${SCRIPTS_DIR}/start_local.sh" --dry-run
fi

# ── 1. OS-level deps (git, python3) ───────────────────────────────────────
if [[ "${EMP_SKIP_DEPS:-0}" != "1" ]]; then
  if bash "${INSTALL_DIR}/install_system_deps.sh"; then
    :
  else
    echo "[bootstrap] system-deps install failed. See messages above."
    exit 1
  fi
else
  echo "[bootstrap] EMP_SKIP_DEPS=1 — skipping system-deps auto-install."
fi

# ── 2. R interpreter ──────────────────────────────────────────────────────
if [[ "${EMP_SKIP_R_INSTALL:-0}" != "1" ]]; then
  if bash "${INSTALL_DIR}/install_r.sh"; then
    :
  else
    echo "[bootstrap] R install failed. See messages above."
    exit 1
  fi
else
  echo "[bootstrap] EMP_SKIP_R_INSTALL=1 — skipping R auto-install."
fi

EMPI_RSCRIPT="$(bash "${SCRIPTS_DIR}/resolve_rscript.sh")"
export EMPI_RSCRIPT

# ── 3. R packages + EMP ──────────────────────────────────────────────────
echo "[bootstrap] Installing CRAN + Bioconductor + EasyMultiProfiler packages…"
bash "${SCRIPTS_DIR}/install_runtime.sh" "$@"

# ── 4. Start services ─────────────────────────────────────────────────────
echo "[bootstrap] Starting API + web UI…"
exec bash "${SCRIPTS_DIR}/start_local.sh" --open-browser
