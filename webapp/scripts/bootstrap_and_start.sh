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

SCRIPTS_DIR="${ROOT_DIR}/webapp/scripts"
INSTALL_DIR="${SCRIPTS_DIR}/install"

echo "════════════════════════════════════════════════════════"
echo "  EasyMultiProfiler Web v7 — bootstrap"
echo "  Folder: ${ROOT_DIR}"
echo "════════════════════════════════════════════════════════"

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

# Make sure R is on PATH in this shell even if we just installed it.
hash -r
if ! command -v Rscript >/dev/null 2>&1; then
  echo "[bootstrap] Rscript still not on PATH. Open a new shell and re-run."
  exit 1
fi

# ── 3. R packages + EMP ──────────────────────────────────────────────────
echo "[bootstrap] Installing CRAN + Bioconductor + EasyMultiProfiler packages…"
bash "${SCRIPTS_DIR}/install_runtime.sh" "$@"

# ── 4. Start services ─────────────────────────────────────────────────────
echo "[bootstrap] Starting API + web UI…"
bash "${SCRIPTS_DIR}/start_local.sh"

WEB_PORT="${WEB_PORT:-8080}"
URL="http://127.0.0.1:${WEB_PORT}"
if command -v open >/dev/null 2>&1; then
  open "${URL}" >/dev/null 2>&1 || true
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "${URL}" >/dev/null 2>&1 || true
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "  EasyMultiProfiler Web is running at: ${URL}"
echo "  Stop with: bash webapp/scripts/stop_local.sh"
echo "════════════════════════════════════════════════════════"