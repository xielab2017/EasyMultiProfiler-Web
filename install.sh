#!/usr/bin/env bash
# install.sh — macOS / Linux / WSL / Git-Bash entry point.
# Auto-detects host OS and delegates to the proper V7 bootstrap.
#
# Run this from the repo root (after `git clone`):
#   bash install.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${SCRIPT_DIR}/webapp/scripts/bootstrap_and_start.sh" "$@"