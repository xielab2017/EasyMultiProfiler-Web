#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

if [[ -x "${ROOT_DIR}/webapp/scripts/check_prerequisites.sh" ]]; then
  bash "${ROOT_DIR}/webapp/scripts/check_prerequisites.sh" || exit 1
fi

if ! command -v Rscript >/dev/null 2>&1; then
  echo "Rscript not found. See docs/INSTALL_MAC.md"
  exit 1
fi

echo "Installing EasyMultiProfiler web runtime dependencies..."
Rscript "webapp/scripts/install_runtime.R" "$@"
if [[ -x "webapp/scripts/create_desktop_launcher.sh" ]]; then
  bash "webapp/scripts/create_desktop_launcher.sh" || true
fi
echo "Install completed."
