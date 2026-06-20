#!/usr/bin/env bash
# macOS double-click launcher (alias). Prefer Run-EMP-Web-Mac.command on new installs.
# Windows: use Run-EMP-Web-Windows.bat — .command files do not run on Windows.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "${ROOT_DIR}/Run-EMP-Web-Mac.command" "$@"
