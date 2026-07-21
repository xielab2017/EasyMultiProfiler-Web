#!/usr/bin/env bash
# Point Tailscale Funnel at EMP (phone / 外网浏览器可直接打开 HTTPS).
# NOTE: This replaces whatever Funnel currently serves (e.g. Agent Hub :8765).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIME_CONFIG="${ROOT_DIR}/webapp/config/runtime.env"
if [[ -f "${RUNTIME_CONFIG}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${RUNTIME_CONFIG}"
  set +a
fi

API_PORT="${API_PORT:-8000}"
WEB_PORT="${WEB_PORT:-8080}"
GATEWAY_PORT="${GATEWAY_PORT:-8090}"
PIDS_DIR="${ROOT_DIR}/.local_run"
GW_PID_FILE="${PIDS_DIR}/gateway.pid"
GW_LOG="${PIDS_DIR}/gateway.log"

mkdir -p "${PIDS_DIR}"

if ! command -v tailscale >/dev/null 2>&1; then
  echo "tailscale 未安装。请先安装: https://tailscale.com/download" >&2
  exit 1
fi

if ! curl --noproxy '*' -fsS --max-time 3 "http://127.0.0.1:${WEB_PORT}/" >/dev/null; then
  echo "EMP 前端未在 :${WEB_PORT} 运行。请先: bash webapp/scripts/start_local.sh" >&2
  exit 1
fi
if ! curl --noproxy '*' -fsS --max-time 3 "http://127.0.0.1:${API_PORT}/api/health" >/dev/null; then
  echo "EMP API 未在 :${API_PORT} 运行。请先: bash webapp/scripts/start_local.sh" >&2
  exit 1
fi

# Restart local gateway
if [[ -f "${GW_PID_FILE}" ]]; then
  old="$(cat "${GW_PID_FILE}" 2>/dev/null || true)"
  if [[ -n "${old}" ]] && kill -0 "${old}" 2>/dev/null; then
    kill "${old}" 2>/dev/null || true
  fi
  rm -f "${GW_PID_FILE}"
fi
# Free gateway port if occupied
pids="$(lsof -t -iTCP:"${GATEWAY_PORT}" -sTCP:LISTEN 2>/dev/null || true)"
if [[ -n "${pids}" ]]; then
  # shellcheck disable=SC2086
  kill ${pids} 2>/dev/null || true
  sleep 1
fi

PY=""
for _py in python3 python; do
  if command -v "${_py}" >/dev/null 2>&1; then
    PY="${_py}"
    break
  fi
done
[[ -n "${PY}" ]] || { echo "Python 3 not found" >&2; exit 1; }

cd "${ROOT_DIR}"
nohup env API_PORT="${API_PORT}" WEB_PORT="${WEB_PORT}" GATEWAY_PORT="${GATEWAY_PORT}" GATEWAY_HOST=127.0.0.1 \
  "${PY}" webapp/scripts/emp_gateway.py >"${GW_LOG}" 2>&1 < /dev/null &
echo $! > "${GW_PID_FILE}"
sleep 1
if ! curl --noproxy '*' -fsS --max-time 3 "http://127.0.0.1:${GATEWAY_PORT}/api/health" >/dev/null; then
  echo "Gateway failed to start. Log:" >&2
  tail -n 40 "${GW_LOG}" >&2 || true
  exit 1
fi

echo "Switching Tailscale Funnel HTTPS:443 -> EMP gateway :${GATEWAY_PORT} ..."
echo "(Keeps other Funnel ports such as :8443. Use --https=10000 for a third service.)"
# Avoid full reset so Agent Hub on :8443 can coexist.
tailscale funnel --bg --yes --https=443 "${GATEWAY_PORT}"

# Optionally keep / restore Agent Hub Funnel on allowed port 8443
if curl --noproxy '*' -fsS --max-time 2 "http://127.0.0.1:8765/" >/dev/null 2>&1; then
  echo "Also publishing Agent Hub on Funnel :8443 -> :8765"
  tailscale funnel --bg --yes --https=8443 8765 >/dev/null 2>&1 || true
fi

sleep 1
FUNNEL_URL="$(tailscale status --json 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin)
name=(d.get("Self",{}) or {}).get("DNSName","").rstrip(".")
print(f"https://{name}" if name else "")' 2>/dev/null || true)"

echo
echo "EMP Funnel ready."
echo "- EMP 外网:     ${FUNNEL_URL:-https://<machine>.ts.net}/   (Funnel :443)"
echo "- Agent Hub 外网: ${FUNNEL_URL:-https://<machine>.ts.net}:8443/  (Funnel :8443)"
echo "- Local gateway: http://127.0.0.1:${GATEWAY_PORT}"
echo "- Note: Funnel 公网端口只能是 443 / 8443 / 10000，不能用 8080"
echo "- Funnel status:  tailscale funnel status"
