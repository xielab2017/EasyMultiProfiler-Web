#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Finder launches may omit Homebrew and ~/.local/bin from PATH.
for py in "${EMPI_PYTHON:-}" python3 python python3.14 python3.13 python3.12 python3.11 python3.10 \
  "$HOME/.local/bin/python3.14" "$HOME/.local/bin/python3.13" "$HOME/.local/bin/python3.12" \
  "$HOME/.local/bin/python3.11" "$HOME/.local/bin/python3.10" \
  /opt/homebrew/bin/python3 /usr/local/bin/python3; do
  [[ -n "$py" ]] || continue
  if command -v "$py" >/dev/null 2>&1 && "$py" -c 'import sys; sys.exit(sys.version_info < (3, 10))' >/dev/null 2>&1; then
    exec "$py" "$ROOT_DIR/webapp/scripts/launch_metadata.py" "$@"
  fi
done
echo 'Python >= 3.10 required. Install Python or set EMPI_PYTHON to its executable. R is not required for metadata.' >&2
exit 1
