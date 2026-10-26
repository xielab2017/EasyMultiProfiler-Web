#!/usr/bin/env bash
# Install-EMP-Web-Mac.command - EasyMultiProfiler Web v9.1.0 one-click
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

echo "============================================================"
echo "  EasyMultiProfiler Web v9.1.0 - macOS one-click installer"
echo "  EasyMultiProfiler Web v9.1.0 - macOS 一键安装"
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
  else
    echo ""
    echo "============================================================"
    echo "  Installation finished. The web server runs in the background."
    echo "  安装完成，网页服务已在后台运行。"
    echo "  Open: http://127.0.0.1:8080"
    echo "  Stop: double-click Stop-EMP-Web-Mac.command"
    echo "  停止: 双击 Stop-EMP-Web-Mac.command"
    echo "============================================================"
  fi
  echo ""
  read -r -p "Press Enter to close this window... / 按回车键关闭此窗口... " _ || sleep 8
  exit "${ec}"
}
trap _on_exit EXIT

if [[ -f "${ROOT_DIR}/webapp/scripts/bootstrap_and_start.sh" ]]; then
  echo "[install] Local project copy found - running the local installer."
  echo "[安装] 检测到本地项目副本 - 运行本地安装流程 (bash install.sh)。"
  echo ""
  bash "${ROOT_DIR}/install.sh"
else
  echo "[install] No local project copy - downloading the installer from GitHub."
  echo "[安装] 未检测到本地项目副本 - 从 GitHub 下载安装脚本。"
  echo ""
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/main/webapp/scripts/install_from_github.sh)"
fi
