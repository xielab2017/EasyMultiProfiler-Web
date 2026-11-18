#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
py="$(bash "$ROOT_DIR/webapp/scripts/resolve_python.sh")"
exec "$py" "$ROOT_DIR/webapp/scripts/launch_metadata.py" "$@"
