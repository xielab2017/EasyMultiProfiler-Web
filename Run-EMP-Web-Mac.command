#!/usr/bin/env bash
# Double-click launcher (macOS only). Keeps Terminal open so errors are visible.
# V7: will auto-install R + python3 + EMP if missing.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT_DIR}"

echo "════════════════════════════════════════════════════════"
echo "  EasyMultiProfiler Web v7  (macOS launcher)"
echo "  Folder: ${ROOT_DIR}"
echo "  Windows users: use Run-EMP-Web-Windows.bat instead"
echo "════════════════════════════════════════════════════════"
echo ""

_on_exit() {
  local ec=$?
  if [[ "${ec}" -ne 0 ]]; then
    echo ""
    echo "════════════════════════════════════════════════════════"
    echo "  启动失败 (exit ${ec})。请阅读上方错误信息。"
    echo "  V7 已自动尝试安装 R / python3 / EMP；若失败,"
    echo "  可手动: xcode-select --install"
    echo "  或: bash webapp/scripts/launch_emp_web.sh --repair"
    echo "════════════════════════════════════════════════════════"
  else
    echo ""
    echo "服务已在后台运行。关闭本窗口不会停止服务。"
    echo "停止: bash webapp/scripts/stop_local.sh"
  fi
  echo ""
  read -r -p "按回车键关闭此窗口… " _ || sleep 8
}
trap _on_exit EXIT

bash "${ROOT_DIR}/webapp/scripts/launch_emp_web.sh" "$@"