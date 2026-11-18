#!/usr/bin/env bash
# Check / guide installation of Git, Python 3, and R for EMP-Web.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OK=0
WARN=0

say() { echo "[check] $*"; }
fail() { echo "[FAIL] $*"; OK=1; }
hint() { echo "        → $*"; WARN=1; }

say "EasyMultiProfiler Web — prerequisite check (macOS / Linux)"
say "Repo: ${ROOT_DIR}"

if command -v git >/dev/null 2>&1; then
  say "Git: $(git --version | head -1)"
else
  fail "Git not found."
  hint "Mac: brew install git   |   Ubuntu: sudo apt install git"
fi

if PY="$(bash "$ROOT_DIR/webapp/scripts/resolve_python.sh")"; then
  say "Python: $("$PY" --version 2>&1) ($PY)"
else
  fail "Python >= 3.10 not found (required for web UI on port 8080)."
  hint "Mac: brew install python@3.12"
fi

if RSCRIPT="$(bash "${ROOT_DIR}/webapp/scripts/resolve_rscript.sh")"; then
  say "R: $("$RSCRIPT" --vanilla -e 'cat(as.character(getRversion()))') ($RSCRIPT)"
else
  fail "A working R >= 4.3.3 is required."
fi

if [[ "$OK" -ne 0 ]]; then
  echo ""
  echo "Fix the items above, then run: bash webapp/scripts/bootstrap_and_start.sh"
  exit 1
fi

say "All prerequisites OK."
exit 0
