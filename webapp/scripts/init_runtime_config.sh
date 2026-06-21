#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CFG_DIR="${ROOT_DIR}/webapp/config"
CFG_FILE="${CFG_DIR}/runtime.env"

mkdir -p "${CFG_DIR}"

if [[ ! -f "${CFG_FILE}" ]]; then
  cat > "${CFG_FILE}" <<'EOF'
# EasyMultiProfiler runtime configuration
API_PORT=8000
WEB_PORT=8080
# Optional: custom R library path
# R_LIBS_USER=
EOF
  echo "Created runtime config: ${CFG_FILE}"
else
  echo "Runtime config exists: ${CFG_FILE}"
fi
