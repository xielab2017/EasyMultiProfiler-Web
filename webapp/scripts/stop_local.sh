#!/usr/bin/env bash
# Stop local EMP Web services started by start_local.sh / launch_emp_web.sh.
# Targets only recognized processes from this checkout recorded under .local_run.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "${ROOT_DIR}/webapp/scripts/process_identity.sh"
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

emp_stop_recorded_process "${API_PID_FILE}" "$ROOT_DIR"
emp_stop_recorded_process "${WEB_PID_FILE}" "$ROOT_DIR"
emp_stop_recorded_process "${GW_PID_FILE}" "$ROOT_DIR"
emp_stop_recorded_process "${PIDS_DIR}/metadata.pid" "$ROOT_DIR"
for service in api web metadata; do
  emp_stop_recorded_process "${PIDS_DIR}/workbench_runtime/${service}.pid" "$ROOT_DIR"
done

echo "Recorded EMP services stopped; unrelated port listeners were not touched."
