#!/usr/bin/env bash
# Install-EMP-Web-Mac.command - EasyMultiProfiler Web one-click
# installer (macOS). Double-click this file in Finder.
#
# Behaviour:
#   - If this file sits in a full local copy of the project (the
#     webapp/scripts/bootstrap_and_start.sh file exists next to it), the
#     local install flow is used (bash install.sh).
#   - Otherwise the one-line installer is downloaded from GitHub and run.
# The Terminal window stays open at the end (and on error) so the log
# remains readable, mirroring Run-EMP-Web-Mac.command.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT_DIR}"
EMP_WEB_RELEASE=""
if [[ -f "${ROOT_DIR}/DESCRIPTION" ]]; then EMP_WEB_RELEASE=" v$(awk '/^Version:/{print $2;exit}' "${ROOT_DIR}/DESCRIPTION")"; fi

echo "============================================================"
echo "  EasyMultiProfiler Web${EMP_WEB_RELEASE} - macOS one-click installer"
echo "  EasyMultiProfiler Web${EMP_WEB_RELEASE} - macOS 一键安装"
echo "  Folder: ${ROOT_DIR}"
echo "  Windows users: use Install-EMP-Web-Windows.bat instead"
echo "============================================================"
echo ""

_on_exit() {
  local ec=$?
  if [[ "${ec}" -ne 0 ]]; then
    echo ""
    echo "============================================================"
    echo "  Installation failed (exit ${ec}). Please read the log above."
    echo "  安装失败 (exit ${ec})，请阅读上方错误信息。"
    echo "  Common causes: network limits / R download failed / missing"
    echo "  Xcode Command Line Tools (try: xcode-select --install)."
    echo "  常见原因: 网络受限 / R 下载失败 / 缺少 Xcode 命令行工具"
    echo "  (可先运行: xcode-select --install)。"
    echo "============================================================"
  fi
  echo ""
  if [[ -t 0 ]]; then read -r -p "Press Enter to close this window... / 按回车键关闭此窗口... " _ || true; fi
  exit "${ec}"
}
trap _on_exit EXIT

if [[ -f "${ROOT_DIR}/webapp/scripts/bootstrap_and_start.sh" ]]; then
  echo "[install] Local project copy found - running the local installer."
  echo "[安装] 检测到本地项目副本 - 运行本地安装流程 (bash install.sh)。"
  echo ""
  bash "${ROOT_DIR}/install.sh" "$@"
else
  if [[ "${EMP_DRY_RUN:-0}" == "1" || " $* " == *" --dry-run "* ]]; then
    echo "Dry run requires a local project copy." >&2
    exit 1
  fi
  echo "[install] No local project copy - downloading the installer from GitHub."
  echo "[安装] 未检测到本地项目副本 - 从 GitHub 下载安装脚本。"
  echo ""
  installer="$(curl -fsSL https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/main/webapp/scripts/install_from_github.sh)" || exit $?
  [[ -n "$installer" ]] || { echo "Downloaded installer is empty." >&2; exit 1; }
  bash -c "$installer"
fi
