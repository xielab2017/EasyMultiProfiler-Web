#!/usr/bin/env bash
# install_r.sh — Auto-install R for the current host.
#
# Sources (CRAN is the canonical source of truth for current + historical versions):
#   macOS    : https://cran.r-project.org/bin/macosx/
#   Windows  : delegated to install_r.ps1 (handled in the .ps1 launcher)
#   Linux    : adds CRAN apt / yum repo, then apt-get install r-base
#
# Respects:
#   EMP_AUTO_INSTALL=0   abort if anything is missing
#   EMP_R_VERSION=4.4.2  pin a specific R release
#   EMP_R_MIRROR=…       override CRAN mirror (default https://cran.r-project.org)
#
# Exit codes:
#   0 success
#   1 hard failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_platform.sh
source "${SCRIPT_DIR}/_platform.sh"

CRAN_MIRROR="${EMP_R_MIRROR:-https://cran.r-project.org}"
DEFAULT_R_VERSION="${EMP_R_VERSION:-4.4.2}"   # current stable, includes Apple Silicon native

os="$(emp_detect_os)"
arch="$(emp_detect_arch)"
want_ver="${EMP_R_VERSION:-$DEFAULT_R_VERSION}"

if ! emp_need_r_install; then
  emp_ok "R $(emp_detect_r_version) already installed and >= $(emp_min_r_version)"
  exit 0
fi

emp_log "R installation needed (target >= $(emp_min_r_version), want ${want_ver}, OS=${os}, arch=${arch})"

if ! emp_should_auto_install; then
  emp_err "EMP_AUTO_INSTALL=0 — refusing to download R. Install R manually using approved sources, then retry."
  exit 1
fi

TMPDIR_R="$(mktemp -d -t emp-install-r.XXXXXX)"
cleanup() { rm -rf "${TMPDIR_R}"; }
trap cleanup EXIT

# ─────────────────────────── macOS ───────────────────────────
install_r_macos() {
  local pkg_url
  case "${arch}" in
    arm64)
      # Apple Silicon: R 4.3+ ships an arm64 .pkg
      pkg_url="${CRAN_MIRROR}/bin/macosx/big-sur-arm64/base/R-${want_ver}-arm64.pkg"
      ;;
    x86_64)
      pkg_url="${CRAN_MIRROR}/bin/macosx/big-sur-x86_64/base/R-${want_ver}-x86_64.pkg"
      ;;
    *)
      emp_err "Unsupported macOS architecture: ${arch}"
      return 1
      ;;
  esac

  emp_log "Downloading ${pkg_url}"
  local pkg_path="${TMPDIR_R}/R-${want_ver}.pkg"
  curl -fSL --retry 3 --connect-timeout 30 -o "${pkg_path}" "${pkg_url}"

  emp_log "Installing R (admin password may be required)…"
  sudo installer -pkg "${pkg_path}" -target /

  # Detect where the installer dropped Rscript. CRAN .pkg installs to /Library/Frameworks/R.framework/Versions/<ver>/Resources/
  local r_home="/Library/Frameworks/R.framework/Versions/${want_ver}/Resources/bin"
  if [[ ! -x "${r_home}/Rscript" ]]; then
    # Fallback to "Current" symlink
    r_home="/Library/Frameworks/R.framework/Resources/bin"
  fi
  if [[ ! -x "${r_home}/Rscript" ]]; then
    emp_err "Rscript binary not found after install."
    return 1
  fi

  # Make Rscript discoverable in this shell + on PATH for future sessions.
  export PATH="${r_home}:${PATH}"
  cat > "${HOME}/.emp_r_path.sh" <<EOF
# Added by EasyMultiProfiler installer — exposes Rscript without a Homebrew install.
export PATH="${r_home}:\${PATH}"
EOF
  # Also link into /usr/local/bin so it survives shell resets.
  sudo ln -sf "${r_home}/Rscript" /usr/local/bin/Rscript 2>/dev/null || true
  sudo ln -sf "${r_home}/R"      /usr/local/bin/R      2>/dev/null || true
  emp_ok "R installed at ${r_home}"
  emp_ok "Rscript available as: $(command -v Rscript)"
}

# ─────────────────────────── Debian / Ubuntu ───────────────────────────
install_r_debian() {
  emp_err "Automatic CRAN repository configuration is disabled: distro-specific signing keys and repositories require administrator setup."
  emp_err "Install R >= $(emp_min_r_version) using your approved package sources, then retry."
  emp_err "Official instructions: https://cran.r-project.org/bin/linux/ (choose your exact distribution)."
  return 1
}

install_r_rhel() {
  emp_err "Install R >= $(emp_min_r_version) from your distribution's approved repositories, then retry."
  emp_err "A fixed Fedora RPM is not compatible with every Fedora/RHEL release or architecture."
  emp_err "Official instructions: https://cran.r-project.org/bin/linux/"
  return 1
}

# ─────────────────────────── dispatch ───────────────────────────
case "${os}" in
  macos)               install_r_macos ;;
  debian|ubuntu|linuxmint|pop) install_r_debian ;;
  rhel|fedora|centos|rocky|almalinux) install_r_rhel ;;
  windows-posix)
    # Git-Bash / MSYS / Cygwin — fall back to plain Windows installer via PowerShell.
    if command -v powershell.exe >/dev/null 2>&1; then
      emp_log "Delegating to install_r.ps1 (Windows PowerShell)"
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File \
        "$(cygpath -w "${SCRIPT_DIR}/install_r.ps1")" -Version "${want_ver}" -CranMirror "${CRAN_MIRROR}"
    else
      emp_err "PowerShell not available; install R manually from https://cran.r-project.org/bin/windows/base/."
      exit 1
    fi
    ;;
  *)
    emp_err "Automatic R install is not implemented for OS='${os}'. Install R >= $(emp_min_r_version) manually and re-run."
    exit 1
    ;;
esac

# Final verification — re-PATH because brew may have added bin dirs in this shell.
hash -r
if ! emp_need_r_install; then
  emp_ok "R $(emp_detect_r_version) verified."
  emp_mark_installed r
  exit 0
fi

emp_err "Rscript still not on PATH after install. You may need to open a new shell."
exit 1