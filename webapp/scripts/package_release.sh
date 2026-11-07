#!/usr/bin/env bash
# package_release.sh - build the three per-OS release packages for
# EasyMultiProfiler Web v9.2.0:
#
#   webapp/dist/EasyMultiProfiler-Web-v9.2.0-windows.zip
#   webapp/dist/EasyMultiProfiler-Web-v9.2.0-macos.zip
#   webapp/dist/EasyMultiProfiler-Web-v9.2.0-linux.zip
#
# Every package contains the full project tree (same rsync excludes as
# the previous single-package build) plus a PLATFORM.txt at the package
# root that names the target OS, the one-click installer file to use,
# and the alternative one-line install command for that OS.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="9.2.0"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${ROOT_DIR}/webapp/dist"
STAGE_ROOT="${OUT_DIR}/.staging-${STAMP}"

mkdir -p "${OUT_DIR}" "${STAGE_ROOT}"

# os | installer file at package root | one-line command (alternative)
PLATFORMS=(
  "windows|Install-EMP-Web-Windows.bat|Run Start-EMP-Metadata.cmd for the new metadata features."
  "macos|Install-EMP-Web-Mac.command|Run Start-EMP-Metadata.command for the new metadata features."
  "linux|Install-EMP-Web-Linux.sh|Run bash Start-EMP-Metadata.sh for the new metadata features."
)

for entry in "${PLATFORMS[@]}"; do
  IFS="|" read -r OS_NAME INSTALLER ONE_LINE <<< "${entry}"
  PKG_NAME="EasyMultiProfiler-Web-v${VERSION}-${OS_NAME}"
  PKG_DIR="${STAGE_ROOT}/${PKG_NAME}"
  ZIP_FILE="${OUT_DIR}/${PKG_NAME}.zip"

  echo "Packaging ${OS_NAME} into ${ZIP_FILE}"

  rm -rf "${PKG_DIR}"
  mkdir -p "${PKG_DIR}"

  rsync -a \
    --exclude ".git" \
    --exclude ".local_run" \
    --exclude "webapp/dist" \
    --exclude "__pycache__" \
    --exclude "*.Rproj.user" \
    "${ROOT_DIR}/" "${PKG_DIR}/"

  # The matching one-click installer lives at the project root and is
  # already part of the tree; fail loudly if it ever goes missing.
  if [[ ! -f "${PKG_DIR}/${INSTALLER}" ]]; then
    echo "ERROR: ${INSTALLER} missing from the project tree; cannot build the ${OS_NAME} package." >&2
    exit 1
  fi

  cat > "${PKG_DIR}/PLATFORM.txt" <<EOF
EasyMultiProfiler Web v${VERSION} - ${OS_NAME} package
=====================================================

Target operating system: ${OS_NAME}

One-click install:
  1. Extract this zip.
  2. Open the extracted folder.
  3. Run the installer for this platform: ${INSTALLER}
     - Windows: double-click ${INSTALLER}
     - macOS:   double-click ${INSTALLER}
     - Linux:   run  bash ${INSTALLER}   in a terminal

New metadata features (separate service, Python >=3.10; no R required):
  ${ONE_LINE}

This is a development source package; dependencies are not bundled.
Extract into a NEW sibling directory. Do not overwrite an existing installation.
The metadata launcher prints its URL, default http://127.0.0.1:8081/public_data.html.
The separate full R application uses http://127.0.0.1:8080.
Do not use the main-branch online installer to reproduce this development build.
See README_EN.md (English) or README.md for the full documentation.
EOF

  rm -f "${ZIP_FILE}"
  (cd "${STAGE_ROOT}" && zip -qr "${ZIP_FILE}" "${PKG_NAME}")

  echo "Package ready: ${ZIP_FILE}"
done

rm -rf "${STAGE_ROOT}"

echo "All v${VERSION} packages are in ${OUT_DIR}"
