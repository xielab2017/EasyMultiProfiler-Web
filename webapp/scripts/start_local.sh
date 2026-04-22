#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CFG_FILE="${ROOT_DIR}/webapp/config/runtime.env"
if [[ -f "${CFG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CFG_FILE}"
fi
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
  local pids
  pids="$(lsof -t -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "${pids}" ]]; then
    # shellcheck disable=SC2086
    kill ${pids} 2>/dev/null || true
    sleep 1
    pids="$(lsof -t -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true)"
    if [[ -n "${pids}" ]]; then
      # shellcheck disable=SC2086
      kill -9 ${pids} 2>/dev/null || true
    fi
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
start_detached "${WEB_PID_FILE}" "${WEB_LOG}" \
  python -m http.server "${WEB_PORT}" --directory "webapp/frontend"

wait_for_url() {
  local name="$1"
  local url="$2"
  local log_file="$3"
  local max_attempts="${4:-90}"
  local attempt
  for attempt in $(seq 1 "${max_attempts}"); do
    if curl --noproxy '*' -fsS "${url}" >/dev/null 2>&1; then
      return 0
    fi
    if [[ -f "${log_file}" ]] && grep -Eiq "error|halted|cannot|failed" "${log_file}"; then
      echo "${name} failed while starting. Recent log:"
      tail -n 80 "${log_file}" || true
      return 1
    fi
    sleep 1
  done
  echo "${name} did not become ready after ${max_attempts}s. Recent log:"
  tail -n 80 "${log_file}" || true
  return 1
}

wait_for_url "API" "http://127.0.0.1:${API_PORT}/api/health" "${API_LOG}" 120
wait_for_url "Frontend" "http://127.0.0.1:${WEB_PORT}" "${WEB_LOG}" 30

echo "Local services started."
echo "- Frontend: http://127.0.0.1:${WEB_PORT}"
echo "- API:      http://127.0.0.1:${API_PORT}/api/health"
echo "- Logs:     ${API_LOG}, ${WEB_LOG}"
