#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_NAME="EasyMultiProfiler-main"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${ROOT_DIR}/webapp/dist"
PKG_DIR="${OUT_DIR}/${PROJECT_NAME}-${STAMP}"
ZIP_FILE="${OUT_DIR}/${PROJECT_NAME}-${STAMP}.zip"

mkdir -p "${OUT_DIR}"
rm -rf "${PKG_DIR}"
mkdir -p "${PKG_DIR}"

echo "Packaging project into ${ZIP_FILE}"

rsync -a \
  --exclude ".git" \
  --exclude ".local_run" \
  --exclude "webapp/dist" \
  --exclude "__pycache__" \
  --exclude "*.Rproj.user" \
  "${ROOT_DIR}/" "${PKG_DIR}/"

(cd "${OUT_DIR}" && zip -qr "${ZIP_FILE}" "$(basename "${PKG_DIR}")")

echo "Package ready: ${ZIP_FILE}"
