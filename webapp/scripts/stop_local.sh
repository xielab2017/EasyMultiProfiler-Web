#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIDS_DIR="${ROOT_DIR}/.local_run"
API_PID_FILE="${PIDS_DIR}/api.pid"
WEB_PID_FILE="${PIDS_DIR}/web.pid"

stop_pid_file() {
  local pid_file="$1"
  if [[ -f "${pid_file}" ]]; then
    local pid
    pid="$(cat "${pid_file}" 2>/dev/null || true)"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" || true
      echo "Stopped PID ${pid}"
    fi
    rm -f "${pid_file}"
  fi
}

stop_pid_file "${API_PID_FILE}"
stop_pid_file "${WEB_PID_FILE}"

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

API_PORT="${API_PORT:-8000}"
WEB_PORT="${WEB_PORT:-8080}"
kill_port_if_running "${API_PORT}"
kill_port_if_running "${WEB_PORT}"

echo "Local services stopped."
