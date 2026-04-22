#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

if ! command -v Rscript >/dev/null 2>&1; then
  echo "Rscript not found. Please install R (>= 4.3.3) first."
  exit 1
fi

echo "Installing EasyMultiProfiler web runtime dependencies..."
Rscript "webapp/scripts/install_runtime.R" "$@"
bash "webapp/scripts/init_runtime_config.sh"
if [[ -x "webapp/scripts/create_desktop_launcher.sh" ]]; then
  bash "webapp/scripts/create_desktop_launcher.sh" || true
fi
echo "Install completed."
