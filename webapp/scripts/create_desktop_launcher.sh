#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OS_NAME="$(uname -s || true)"

if [[ "${OS_NAME}" == "Darwin" ]]; then
  DESKTOP="${HOME}/Desktop"
  TARGET="${DESKTOP}/EasyMultiProfiler-Web.command"
  cat > "${TARGET}" <<EOF
#!/usr/bin/env bash
cd "${ROOT_DIR}"
bash "${ROOT_DIR}/webapp/scripts/bootstrap_and_start.sh"
EOF
  chmod +x "${TARGET}"
  echo "Created desktop launcher: ${TARGET}"
  exit 0
fi

if [[ -n "${USERPROFILE:-}" ]] && [[ -d "${USERPROFILE}/Desktop" ]]; then
  TARGET="${USERPROFILE}/Desktop/EasyMultiProfiler-Web.bat"
  cat > "${TARGET}" <<EOF
@echo off
set ROOT=${ROOT_DIR}
if exist "%ROOT%\\webapp\\scripts\\create_windows_shortcut.ps1" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\\webapp\\scripts\\create_windows_shortcut.ps1" -Root "%ROOT%" >nul 2>nul
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\\webapp\\scripts\\start_local_windows.ps1"
EOF
  echo "Created desktop launcher: ${TARGET}"
  exit 0
fi

echo "Desktop launcher skipped: unsupported OS or desktop path not found."
