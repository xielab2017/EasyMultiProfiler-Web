#!/usr/bin/env bash
# Double-click launcher (macOS only). Keeps Terminal open so errors are visible.
# V7: will auto-install R + python3 + EMP if missing.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT_DIR}"
EMP_WEB_VERSION="$(awk '/^Version:/{print $2;exit}' "${ROOT_DIR}/DESCRIPTION")"

echo "════════════════════════════════════════════════════════"
echo "  EasyMultiProfiler Web v${EMP_WEB_VERSION}  (macOS launcher)"
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
    echo "  修复依赖: bash webapp/scripts/launch_emp_web.sh --repair"
    echo "════════════════════════════════════════════════════════"
  fi
  echo ""
  if [[ -t 0 ]]; then read -r -p "按回车键关闭此窗口… " _ || true; fi
  exit "${ec}"
}
trap _on_exit EXIT

bash "${ROOT_DIR}/webapp/scripts/launch_emp_web.sh" "$@"
