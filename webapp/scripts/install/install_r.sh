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
  emp_err "EMP_AUTO_INSTALL=0 — refusing to download R. Unset it or run with elevated privileges."
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
  # -pkg chooses the .pkg, -target / picks the boot volume, -allowUntrusted accepts the
  # developer cert (R binaries are signed by the R Foundation, but the certificate
  # is not always recognised by Gatekeeper on first install).
  sudo installer -pkg "${pkg_path}" -target / -allowUntrusted

  # Detect where the installer dropped Rscript. CRAN .pkg installs to /Library/Frameworks/R.framework/Versions/<ver>/Resources/
  local r_home="/Library/Frameworks/R.framework/Versions/${want_ver}/Resources"
  if [[ ! -x "${r_home}/Rscript" ]]; then
    # Fallback to "Current" symlink
    r_home="/Library/Frameworks/R.framework/Resources"
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
  emp_require_sudo_or_die
  local codename
  codename="$(. /etc/os-release 2>/dev/null && echo "${VERSION_CODENAME:-}")"
  if [[ -z "${codename}" ]]; then
    emp_err "Cannot detect Debian/Ubuntu codename (no /etc/os-release)."
    return 1
  fi

  local keyring="${TMPDIR_R}/cran-keyring.gpg"
  local keyring_deb="${TMPDIR_R}/cran-keyring.deb"
  emp_log "Fetching CRAN GPG key"
  curl -fSL --retry 3 -o "${keyring}" "${CRAN_MIRROR}/bin/linux/ubuntu/Release.gpg"
  emp_log "Fetching CRAN keyring package"
  # We try the modern .deb first; older Ubuntu (jammy) ships a keyring .deb too.
  if ! curl -fSL --retry 3 -o "${keyring_deb}" \
        "${CRAN_MIRROR}/bin/linux/ubuntu/jammy/cran-keyring_1.0-1_all.deb"; then
    # fall back to focal keyring name
    curl -fSL --retry 3 -o "${keyring_deb}" \
      "${CRAN_MIRROR}/bin/linux/ubuntu/focal/cran-keyring_1.0-1_all.deb"
  fi
  sudo apt-get install -y --no-install-recommends "${keyring_deb}" || true
  sudo mkdir -p /etc/apt/keyrings
  sudo gpg --no-default-keyring --keyring /usr/share/keyrings/cran.gpg \
       --import "${keyring}" 2>/dev/null || true

  local repo_line="deb [signed-by=/usr/share/keyrings/cran.gpg] ${CRAN_MIRROR}/bin/linux/ubuntu ${codename}-cran40/"
  echo "${repo_line}" | sudo tee /etc/apt/sources.list.d/cran.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends r-base-core r-base-dev

  # Provide a stable /usr/local/bin/Rscript symlink
  sudo ln -sf /usr/bin/Rscript /usr/local/bin/Rscript 2>/dev/null || true
  sudo ln -sf /usr/bin/R      /usr/local/bin/R      2>/dev/null || true
  emp_ok "R installed via apt"
}

# ─────────────────────────── Fedora / RHEL ───────────────────────────
install_r_rhel() {
  emp_require_sudo_or_die
  local repo_url
  case "${arch}" in
    x86_64) repo_url="${CRAN_MIRROR}/bin/linux/fedora/38/x86_64/" ;;
    arm64)  repo_url="${CRAN_MIRROR}/bin/linux/fedora/38/aarch64/" ;;
    *)
      emp_err "Unsupported Fedora/RHEL architecture: ${arch}"
      return 1
      ;;
  esac
  sudo dnf install -y "${repo_url}/R-${want_ver}-1.fc38.x86_64.rpm" || \
  sudo dnf install -y "https://mirror.linux.iastate.edu/pub/CRAN/bin/linux/fedora/38/x86_64/R-${want_ver}-1.fc38.x86_64.rpm"
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