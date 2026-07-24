#!/usr/bin/env bash
# V9.0.1_Education one-line installer (preview).
#
#   curl -fsSL https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/V9.0.1_Education/webapp/scripts/install_from_github.sh | bash
#
# Steps:
#   1. Verify / install git (needed for the clone).
#   2. Clone the repo at the requested branch (default V9.0.1_Education).
#   3. Hand off to bootstrap_and_start.sh — which will:
#        - install git + python3 if missing
#        - install R if missing
#        - install EMP + R dependencies
#        - start the API + frontend
set -euo pipefail

REPO_URL="${1:-${EMP_REPO_URL:-https://github.com/xielab2017/EasyMultiProfiler-Web.git}}"
TARGET_DIR="${2:-${EMP_TARGET_DIR:-EasyMultiProfiler-Web}}"
BRANCH="${BRANCH:-${EMP_BRANCH:-V9.0.1_Education}}"

# Bootstrap git itself so even a barebones box can run this script.
if ! command -v git >/dev/null 2>&1; then
  echo "git is not installed."
  case "$(uname -s 2>/dev/null)" in
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        brew install git
      else
        echo "Install Homebrew first (https://brew.sh) and re-run, or install Xcode Command Line Tools:"
        echo "    xcode-select --install"
        exit 1
      fi
      ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y git
      elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y git
      else
        echo "Please install git using your package manager and re-run."
        exit 1
      fi
      ;;
    *)
      echo "Please install git and re-run."
      exit 1
      ;;
  esac
fi

if [[ -d "${TARGET_DIR}/.git" ]]; then
  echo "Repository already exists at ${TARGET_DIR}, pulling latest ${BRANCH}..."
  git -C "${TARGET_DIR}" fetch --all --tags
  git -C "${TARGET_DIR}" checkout "${BRANCH}"
  git -C "${TARGET_DIR}" pull --ff-only origin "${BRANCH}"
else
  echo "Cloning ${REPO_URL} (branch ${BRANCH}) -> ${TARGET_DIR}"
  git clone --branch "${BRANCH}" --depth 1 "${REPO_URL}" "${TARGET_DIR}"
fi

cd "${TARGET_DIR}"
echo "Running V7 bootstrap (auto-installs R, git, python3, EMP)…"
export EMP_CRAN_MIRROR="${EMP_CRAN_MIRROR:-https://cloud.r-project.org}"
bash "webapp/scripts/bootstrap_and_start.sh"
