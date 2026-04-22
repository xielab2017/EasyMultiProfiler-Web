#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
API_BASE="${EMP_API_BASE:-http://127.0.0.1:8000}"

echo "Running smoke tests against ${API_BASE}"
cd "${ROOT_DIR}"

for attempt in $(seq 1 120); do
  if curl --noproxy '*' -fsS "${API_BASE}/api/health" >/dev/null 2>&1; then
    break
  fi
  if [[ "${attempt}" == "120" ]]; then
    echo "API did not become ready after 120s: ${API_BASE}/api/health" >&2
    exit 1
  fi
  sleep 1
done

NO_PROXY='*' no_proxy='*' EMP_API_BASE="${API_BASE}" \
python "webapp/tests/smoke_workflows.py"
