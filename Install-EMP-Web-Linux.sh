#!/usr/bin/env bash
# Install-EMP-Web-Linux.sh - EasyMultiProfiler Web v9.1.0 one-click
# installer (Linux).
#
# Run from a terminal:
#   bash Install-EMP-Web-Linux.sh
# or, after `chmod +x Install-EMP-Web-Linux.sh`:
#   ./Install-EMP-Web-Linux.sh
#
# Behaviour:
#   - If this file sits in a full local copy of the project (the
#     webapp/scripts/bootstrap_and_start.sh file exists next to it), the
#     local install flow is used (bash install.sh).
#   - Otherwise the one-line installer is downloaded from GitHub and run.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"

echo "============================================================"
echo "  EasyMultiProfiler Web v9.1.0 - Linux one-click installer"
echo "  EasyMultiProfiler Web v9.1.0 - Linux 一键安装"
echo "  Folder: ${ROOT_DIR}"
echo "  Windows users: use Install-EMP-Web-Windows.bat instead"
echo "  macOS users:   use Install-EMP-Web-Mac.command instead"
echo "============================================================"
echo ""

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
