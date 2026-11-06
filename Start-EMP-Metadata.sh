#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for py in "${EMPI_PYTHON:-}" python3 python; do
  [[ -n "$py" ]] || continue
  if command -v "$py" >/dev/null 2>&1 && "$py" -c 'import sys; sys.exit(sys.version_info < (3, 10))' >/dev/null 2>&1; then
    exec "$py" "$ROOT_DIR/webapp/scripts/launch_metadata.py" "$@"
  fi
done
echo 'Python >= 3.10 required. Install Python or set EMPI_PYTHON to its executable. R is not required for metadata.' >&2
exit 1
