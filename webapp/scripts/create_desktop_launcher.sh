#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OS_NAME="$(uname -s || true)"

if [[ "${OS_NAME}" == "Darwin" ]]; then
  DESKTOP="${HOME}/Desktop"
  TARGET="${DESKTOP}/EasyMultiProfiler-Web.command"
  cat > "${TARGET}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT_DIR}"
cd "\${ROOT}"
echo "EasyMultiProfiler Web — starting from Desktop shortcut…"
bash "\${ROOT}/webapp/scripts/launch_emp_web.sh" "\$@"
echo ""
read -r -p "按回车键关闭… " _ || sleep 8
EOF
  chmod +x "${TARGET}"
  echo "Created desktop launcher: ${TARGET}"
  exit 0
fi

if [[ -n "${USERPROFILE:-}" ]] && [[ -d "${USERPROFILE}/Desktop" ]]; then
  # Prefer creating .lnk via PowerShell (Chinese Start/Stop buttons on Desktop).
  if command -v powershell.exe >/dev/null 2>&1 || command -v pwsh >/dev/null 2>&1; then
    PSBIN="$(command -v powershell.exe 2>/dev/null || command -v pwsh)"
    "${PSBIN}" -NoProfile -ExecutionPolicy Bypass -File "${ROOT_DIR}/webapp/scripts/create_windows_shortcut.ps1" -Root "${ROOT_DIR}"
    exit 0
  fi
  TARGET="${USERPROFILE}/Desktop/EasyMultiProfiler-Web.bat"
  cat > "${TARGET}" <<EOF
@echo off
cd /d "${ROOT_DIR}"
call Start-EMP-Panel.bat
EOF
  echo "Created desktop launcher: ${TARGET}"
  exit 0
fi

echo "Desktop launcher skipped: unsupported OS or desktop path not found."
