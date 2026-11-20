#!/usr/bin/env bash
# Double-click launcher (macOS): 终止运行 / Stop EMP Web API + frontend.
# Companion to Run-EMP-Web-Mac.command — stops the same PIDs/ports.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT_DIR}"

echo "════════════════════════════════════════════════════════"
echo "  EasyMultiProfiler Web — 终止运行 / Stop"
echo "  Folder: ${ROOT_DIR}"
echo "  Stops API (:8000), Web (:8080), and gateway if running"
echo "════════════════════════════════════════════════════════"
echo ""

_on_exit() {
  local ec=$?
  echo ""
  if [[ "${ec}" -ne 0 ]]; then
    echo "停止未完全成功 (exit ${ec})。也可手动: bash webapp/scripts/stop_local.sh"
  else
    echo "已终止本地 EMP Web 服务（若原本未运行则无操作）。"
  fi
  echo ""
  read -r -p "按回车键关闭此窗口… " _ || sleep 8
}
trap _on_exit EXIT

bash "${ROOT_DIR}/webapp/scripts/stop_local.sh"
