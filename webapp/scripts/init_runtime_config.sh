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
