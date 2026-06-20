#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${1:-https://github.com/xielab2017/EasyMultiProfiler-Web.git}"
TARGET_DIR="${2:-EasyMultiProfiler-Web}"
BRANCH="${BRANCH:-v5.0.0}"

if ! command -v git >/dev/null 2>&1; then
  echo "git is required but not found. Please install git first."
  exit 1
fi

if [[ -d "${TARGET_DIR}/.git" ]]; then
  echo "Repository already exists at ${TARGET_DIR}, pulling latest ${BRANCH}..."
  git -C "${TARGET_DIR}" fetch --all --tags
  git -C "${TARGET_DIR}" checkout "${BRANCH}"
  git -C "${TARGET_DIR}" pull --ff-only origin "${BRANCH}"
else
  echo "Cloning ${REPO_URL} -> ${TARGET_DIR}"
  git clone --branch "${BRANCH}" "${REPO_URL}" "${TARGET_DIR}"
fi

cd "${TARGET_DIR}"
echo "Checking prerequisites..."
bash "webapp/scripts/check_prerequisites.sh"
echo "Running one-step installer and launcher..."
export EMP_CRAN_MIRROR="${EMP_CRAN_MIRROR:-https://cloud.r-project.org}"
bash "webapp/scripts/bootstrap_and_start.sh"
