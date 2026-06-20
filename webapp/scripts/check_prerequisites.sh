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

PY=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1; then
    PY="$c"
    break
  fi
done
if [[ -n "$PY" ]]; then
  say "Python: $($PY --version 2>&1)"
else
  fail "Python 3 not found (required for web UI on port 8080)."
  hint "Mac: brew install python@3.12"
fi

if command -v Rscript >/dev/null 2>&1; then
  RV=$(Rscript -e 'cat(as.character(getRversion()))' 2>/dev/null || echo "?")
  say "R: ${RV}"
  Rscript -e 'if (getRversion() < "4.3.3") quit(status=2)' 2>/dev/null || {
    fail "R version must be >= 4.3.3 (found ${RV})."
    hint "Mac: brew install --cask r   |   https://cran.r-project.org/"
  }
else
  fail "Rscript not found."
  echo ""
  echo "════════════════════════════════════════════════════════"
  echo "  请先安装 R（>= 4.3.3），然后重新运行本脚本或 bootstrap。"
  echo "  Mac 推荐:  brew install --cask r"
  echo "  详细步骤:  docs/INSTALL_MAC.md"
  echo "════════════════════════════════════════════════════════"
  exit 1
fi

if [[ "$OK" -ne 0 ]]; then
  echo ""
  echo "Fix the items above, then run: bash webapp/scripts/bootstrap_and_start.sh"
  exit 1
fi

say "All prerequisites OK."
exit 0
