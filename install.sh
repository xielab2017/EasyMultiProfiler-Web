#!/usr/bin/env bash
# install.sh — macOS / Linux / WSL / Git-Bash entry point.
# Auto-detects host OS and delegates to the proper V7 bootstrap.
#
# Run this from the repo root (after `git clone`):
#   bash install.sh
#
# When invoked from a double-clickable shell (Terminal .app, Git-Bash
# shortcut, etc.) the script pauses before closing so the log is readable.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_pause_on_exit() {
  local ec=$?
  if [[ "${ec}" -ne 0 ]]; then
    echo ""
    echo "════════════════════════════════════════════════════════"
    echo "  启动失败 (exit ${ec})。请阅读上方错误信息。"
    echo "  常见原因: 网络受限 / R 下载失败 / EMP 依赖缺失。"
    echo "  可重试: bash webapp/scripts/launch_emp_web.sh --repair"
    echo "════════════════════════════════════════════════════════"
  else
    echo ""
    echo "════════════════════════════════════════════════════════"
    echo "  EasyMultiProfiler Web 已在后台运行。"
    echo "  打开: http://127.0.0.1:8080"
    echo "  停止: 双击 Stop-EMP-Web-Mac.command"
    echo "    或: bash webapp/scripts/stop_local.sh"
    echo "════════════════════════════════════════════════════════"
  fi
  # Keep the window open when we *look* like a double-clicked Terminal
  # shell (no controlling TTY parent or TERM=dumb).
  if [[ ! -t 1 || "${TERM:-}" == "dumb" ]]; then
    read -r -p "按回车键关闭此窗口… " _ || sleep 5
  fi
  exit "${ec}"
}
trap _pause_on_exit EXIT

exec bash "${SCRIPT_DIR}/webapp/scripts/bootstrap_and_start.sh" "$@"
