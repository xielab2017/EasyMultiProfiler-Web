#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

EMPI_RSCRIPT="$(bash "${ROOT_DIR}/webapp/scripts/resolve_rscript.sh")"
export EMPI_RSCRIPT
bash "${ROOT_DIR}/webapp/scripts/check_prerequisites.sh"

echo "Installing EasyMultiProfiler web runtime dependencies..."
"$EMPI_RSCRIPT" "webapp/scripts/install_runtime.R" "$@"
if [[ -x "webapp/scripts/create_desktop_launcher.sh" ]]; then
  bash "webapp/scripts/create_desktop_launcher.sh" || true
fi
echo "Install completed."
