#!/usr/bin/env bash
# Stop local EMP Web services started by start_local.sh / launch_emp_web.sh.
# Targets EMP PID files under .local_run, then frees the configured listen ports.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIME_CONFIG="${ROOT_DIR}/webapp/config/runtime.env"
if [[ -f "${RUNTIME_CONFIG}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${RUNTIME_CONFIG}"
  set +a
fi

PIDS_DIR="${ROOT_DIR}/.local_run"
API_PID_FILE="${PIDS_DIR}/api.pid"
WEB_PID_FILE="${PIDS_DIR}/web.pid"
GW_PID_FILE="${PIDS_DIR}/gateway.pid"
API_PORT="${API_PORT:-8000}"
WEB_PORT="${WEB_PORT:-8080}"
GATEWAY_PORT="${GATEWAY_PORT:-8090}"

stop_pid_file() {
  local pid_file="$1"
  local label="${2:-process}"
  if [[ -f "${pid_file}" ]]; then
    local pid
    pid="$(cat "${pid_file}" 2>/dev/null || true)"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
      # Give graceful shutdown a moment, then force if still alive.
      sleep 0.5
      if kill -0 "${pid}" 2>/dev/null; then
        kill -9 "${pid}" 2>/dev/null || true
      fi
      echo "Stopped ${label} PID ${pid}"
    else
      echo "No live ${label} for ${pid_file}"
    fi
    rm -f "${pid_file}"
  fi
}

stop_pid_file "${API_PID_FILE}" "API"
stop_pid_file "${WEB_PID_FILE}" "Web"
stop_pid_file "${GW_PID_FILE}" "Gateway"

kill_port_if_running() {
  local port="$1"
  local pids
  pids="$(lsof -t -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "${pids}" ]]; then
    echo "Freeing port ${port} (PIDs: ${pids})"
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

kill_port_if_running "${API_PORT}"
kill_port_if_running "${WEB_PORT}"
kill_port_if_running "${GATEWAY_PORT}"

echo "Local EMP Web services stopped."
