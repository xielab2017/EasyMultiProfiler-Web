#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
API_PORT="${API_PORT:-8000}"
WEB_PORT="${WEB_PORT:-8080}"
PIDS_DIR="${ROOT_DIR}/.local_run"
API_PID_FILE="${PIDS_DIR}/api.pid"
WEB_PID_FILE="${PIDS_DIR}/web.pid"
API_LOG="${PIDS_DIR}/api.log"
WEB_LOG="${PIDS_DIR}/web.log"

mkdir -p "${PIDS_DIR}"

kill_if_running() {
  local pid_file="$1"
  if [[ -f "${pid_file}" ]]; then
    local pid
    pid="$(cat "${pid_file}" 2>/dev/null || true)"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" || true
    fi
    rm -f "${pid_file}"
  fi
}

kill_if_running "${API_PID_FILE}"
kill_if_running "${WEB_PID_FILE}"

kill_port_if_running() {
  local port="$1"
  local attempt pids
  for attempt in 1 2 3; do
    pids="$(lsof -t -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true)"
    if [[ -z "${pids}" ]]; then
      return 0
    fi
    # shellcheck disable=SC2086
    kill ${pids} 2>/dev/null || true
    sleep 1
    pids="$(lsof -t -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true)"
    if [[ -n "${pids}" ]]; then
      # shellcheck disable=SC2086
      kill -9 ${pids} 2>/dev/null || true
      sleep 1
    fi
  done
  if lsof -t -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Port ${port} is still in use after cleanup. Try: lsof -iTCP:${port} -sTCP:LISTEN" >&2
    return 1
  fi
}

# Ensure stale listeners do not block new instances.
kill_port_if_running "${API_PORT}"
kill_port_if_running "${WEB_PORT}"

start_detached() {
  local pid_file="$1"
  local log_file="$2"
  shift 2
  if command -v setsid >/dev/null 2>&1; then
    setsid "$@" >"${log_file}" 2>&1 < /dev/null &
  else
    nohup "$@" >"${log_file}" 2>&1 < /dev/null &
  fi
  echo $! > "${pid_file}"
}

echo "Starting API on :${API_PORT} ..."
cd "${ROOT_DIR}"
start_detached "${API_PID_FILE}" "${API_LOG}" \
  env API_PORT="${API_PORT}" NO_PROXY='*' no_proxy='*' Rscript "webapp/backend/run_api.R"

echo "Starting frontend on :${WEB_PORT} ..."
PY=""
for _py in python3 python; do
  if command -v "${_py}" >/dev/null 2>&1; then
    PY="${_py}"
    break
  fi
done
if [[ -z "${PY}" ]]; then
  echo "Python 3 not found. Mac: brew install python@3.12" >&2
  exit 1
fi
start_detached "${WEB_PID_FILE}" "${WEB_LOG}" \
  "${PY}" webapp/scripts/static_server.py "${WEB_PORT}" "webapp/frontend"

web_pid="$(cat "${WEB_PID_FILE}" 2>/dev/null || true)"
if [[ -z "${web_pid}" ]] || ! kill -0 "${web_pid}" 2>/dev/null; then
  echo "Frontend process exited immediately. Recent log:" >&2
  tail -n 40 "${WEB_LOG}" >&2 || true
  exit 1
fi

curl_ok() {
  curl --noproxy '*' -fsS --retry 2 --retry-connrefused --retry-delay 1 --max-time 5 "$1" >/dev/null 2>&1
}

api_failed_in_log() {
  [[ -f "${API_LOG}" ]] && grep -Eiq '(^|[^a-z])(error in|execution halted|cannot open|failed to start)' "${API_LOG}"
}

wait_for_services() {
  local max_attempts="${1:-120}"
  local attempt api_ok web_ok
  for attempt in $(seq 1 "${max_attempts}"); do
    api_ok=1
    web_ok=1
    curl_ok "http://127.0.0.1:${API_PORT}/api/health" && api_ok=0
    curl_ok "http://127.0.0.1:${WEB_PORT}/" && web_ok=0
    if [[ "${api_ok}" -eq 0 && "${web_ok}" -eq 0 ]]; then
      return 0
    fi
    if api_failed_in_log; then
      echo "API failed while starting. Recent log:"
      tail -n 80 "${API_LOG}" || true
      return 1
    fi
    web_pid="$(cat "${WEB_PID_FILE}" 2>/dev/null || true)"
    if [[ -z "${web_pid}" ]] || ! kill -0 "${web_pid}" 2>/dev/null; then
      echo "Frontend process exited while starting. Recent log:"
      tail -n 80 "${WEB_LOG}" || true
      return 1
    fi
    sleep 1
  done
  if [[ "${api_ok}" -ne 0 ]]; then
    echo "API did not become ready after ${max_attempts}s. Recent log:"
    tail -n 80 "${API_LOG}" || true
  fi
  if [[ "${web_ok}" -ne 0 ]]; then
    echo "Frontend did not become ready after ${max_attempts}s. Recent log:"
    tail -n 80 "${WEB_LOG}" || true
  fi
  return 1
}

wait_for_services 120

echo "Local services started."
echo "- Frontend: http://127.0.0.1:${WEB_PORT}"
echo "- API:      http://127.0.0.1:${API_PORT}/api/health"
echo "- Logs:     ${API_LOG}, ${WEB_LOG}"
