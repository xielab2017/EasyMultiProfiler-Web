#!/usr/bin/env bash
# install_system_deps.sh — Install OS-level packages required by EMP Web.
# Idempotent: skips anything that is already present.
#
# macOS  : git + python3 via Homebrew (auto-installed if missing).
# Linux  : git + python3 via apt (Debian/Ubuntu) or dnf (Fedora/RHEL).
#         Use EMP_USE_BREW=1 to force Homebrew on Linux.
#
# Exit codes:
#   0  success
#   1  missing prerequisites we couldn't auto-install
#   2  user cancelled
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_platform.sh
source "${SCRIPT_DIR}/_platform.sh"

os="$(emp_detect_os)"
arch="$(emp_detect_arch)"
emp_log "Detected OS=${os} arch=${arch}"

install_brew_if_missing_macos() {
  if command -v brew >/dev/null 2>&1; then return 0; fi
  if ! emp_should_auto_install; then
    emp_err "Homebrew is required. Install from https://brew.sh first."
    return 1
  fi
  emp_log "Homebrew not found — installing…"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Make brew visible in this shell session
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

install_with_brew() {
  install_brew_if_missing_macos
  local pkgs=("$@")
  local missing=()
  for p in "${pkgs[@]}"; do
    if brew list --formula >/dev/null 2>&1 && brew list --formula 2>/dev/null | grep -qx "${p}"; then
      emp_ok "brew ${p} already installed"
    else
      missing+=("${p}")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    emp_log "brew install ${missing[*]}"
    brew install "${missing[@]}"
  fi
}

apt_update_once() {
  if [[ -f /var/lib/apt/periodic/update-success-stamp ]]; then
    local age=$(( $(date +%s) - $(stat -c %Y /var/lib/apt/periodic/update-success-stamp 2>/dev/null || echo 0) ))
    (( age < 86400 )) && return 0
  fi
  emp_log "apt-get update"
  sudo apt-get update
}

install_with_apt() {
  emp_require_sudo_or_die
  apt_update_once
  local pkgs=("$@")
  local missing=()
  for p in "${pkgs[@]}"; do
    if dpkg -s "${p}" >/dev/null 2>&1; then
      emp_ok "apt ${p} already installed"
    else
      missing+=("${p}")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    emp_log "apt-get install -y ${missing[*]}"
    sudo apt-get install -y --no-install-recommends "${missing[@]}"
  fi
}

dnf_install() {
  emp_require_sudo_or_die
  local pkgs=("$@")
  local missing=()
  for p in "${pkgs[@]}"; do
    if rpm -q "${p}" >/dev/null 2>&1; then
      emp_ok "dnf ${p} already installed"
    else
      missing+=("${p}")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    emp_log "dnf install -y ${missing[*]}"
    sudo dnf install -y "${missing[@]}"
  fi
}

case "${os}" in
  macos)
    install_with_brew git python@3.12
    ;;
  debian|ubuntu|linuxmint|pop)
    install_with_apt git python3 python3-pip python3-venv curl ca-certificates
    ;;
  rhel|fedora|centos|rocky|almalinux)
    install_with_dnf git python3 python3-pip curl ca-certificates
    ;;
  arch|manjaro)
    emp_require_sudo_or_die
    sudo pacman -Sy --noconfirm --needed git python python-pip curl ca-certificates
    ;;
  *)
    emp_warn "Unknown OS '${os}'. We only verified git + python3 here; install them manually if missing."
    ;;
esac

# Final verification
if emp_need_git_install; then
  emp_err "git is still missing after install. Aborting."
  exit 1
fi
if emp_need_python_install; then
  emp_err "python3 (>= 3.8) is still missing after install. Aborting."
  exit 1
fi

emp_ok "git + python3 verified."
emp_mark_installed system-deps