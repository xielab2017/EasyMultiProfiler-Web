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

echo "Local services stopped."
