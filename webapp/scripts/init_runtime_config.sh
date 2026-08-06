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
# Bind all interfaces for LAN + Tailscale. Use 127.0.0.1 for loopback-only.
API_HOST=0.0.0.0
WEB_HOST=0.0.0.0
# LAN/Tailscale: reflect private/Tailscale Origins; start_local.sh auto-fills EMP_API_TOKEN.
EMP_CORS_ORIGIN=reflect-private
# EMP_API_TOKEN=
# Local path import roots. Use ':' between roots on macOS/Linux and ';' on Windows.
# Empty uses the repository tests directory so the Agent Hub smoke workflow works safely.
EMP_ALLOWED_ROOTS=
# Agent integrations must not expose arbitrary R execution.
EMP_ENABLE_USER_R=false
# Optional: custom R library path
# R_LIBS_USER=
EOF
  echo "Created runtime config: ${CFG_FILE}"
else
  echo "Runtime config exists: ${CFG_FILE}"
  # Soft-migrate older loopback-only configs toward LAN/Tailscale defaults
  # without overwriting user overrides when already set.
  if ! grep -q '^API_HOST=' "${CFG_FILE}" 2>/dev/null; then
    printf '\nAPI_HOST=0.0.0.0\n' >> "${CFG_FILE}"
    echo "Added API_HOST=0.0.0.0 to ${CFG_FILE}"
  fi
  if ! grep -q '^WEB_HOST=' "${CFG_FILE}" 2>/dev/null; then
    printf 'WEB_HOST=0.0.0.0\n' >> "${CFG_FILE}"
    echo "Added WEB_HOST=0.0.0.0 to ${CFG_FILE}"
  fi
fi

CAMPUS_EXAMPLE="${CFG_DIR}/campus_llm.json.example"
CAMPUS_FILE="${CFG_DIR}/campus_llm.json"
if [[ ! -f "${CAMPUS_EXAMPLE}" ]]; then
  cat > "${CAMPUS_EXAMPLE}" <<'EOF'
{
  "base_url": "http://10.22.18.12:9901/v1",
  "api_key": "YOUR_CAMPUS_API_KEY",
  "timeout": 120,
  "models": {
    "fast": "deepseek-v4-flash",
    "accurate": "Qwen3.6-35B-A3B",
    "vision": "Qwen3-VL-8B-Instruct",
    "embedding": "Qwen-embedding"
  }
}
EOF
  echo "Created campus LLM example: ${CAMPUS_EXAMPLE}"
fi
if [[ ! -f "${CAMPUS_FILE}" ]]; then
  echo "Tip: copy ${CAMPUS_EXAMPLE} to ${CAMPUS_FILE} and set your campus API key."
fi
