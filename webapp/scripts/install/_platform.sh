#!/usr/bin/env bash
# Shared helpers for OS / architecture detection.
# Sourced by other install/*.sh scripts.
# shellcheck shell=bash

if [[ -n "${EMP_PLATFORM_LOADED:-}" ]]; then
  return 0 2>/dev/null || true
fi
EMP_PLATFORM_LOADED=1

emp_log()  { printf "\033[1;34m[emp-install]\033[0m %s\n" "$*"; }
emp_warn() { printf "\033[1;33m[emp-warn]\033[0m %s\n" "$*" >&2; }
emp_err()  { printf "\033[1;31m[emp-error]\033[0m %s\n" "$*" >&2; }
emp_ok()   { printf "\033[1;32m[emp-ok]\033[0m %s\n" "$*"; }

# Detect the host operating system.
# Outputs one of: macos | linux | windows-cygwin | windows-mingw | bsd | unknown
emp_detect_os() {
  case "$(uname -s 2>/dev/null || echo unknown)" in
    Darwin) echo "macos" ;;
    Linux)
      if   [[ -f /etc/os-release ]]; then . /etc/os-release; echo "${ID:-linux}"
      elif [[ -f /etc/redhat-release ]]; then echo "rhel"
      elif [[ -f /etc/debian_version ]]; then echo "debian"
      else echo "linux"
      fi
      ;;
    FreeBSD|OpenBSD|NetBSD) echo "bsd" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows-posix" ;;
    *) echo "unknown" ;;
  esac
}

# Detect CPU architecture.
# Outputs one of: arm64 | x86_64 | other
emp_detect_arch() {
  case "$(uname -m 2>/dev/null || echo unknown)" in
    arm64|aarch64) echo "arm64" ;;
    x86_64|amd64)  echo "x86_64" ;;
    i386|i686)     echo "i386" ;;
    *) echo "other" ;;
  esac
}

# Return the minimum supported R major.minor (e.g. "4.3.3").
emp_min_r_version() {
  echo "4.3.3"
}

# Decide whether we need to install git.
emp_need_git_install() {
  command -v git >/dev/null 2>&1 && return 1 || return 0
}

# Decide whether we need to install python3.
emp_need_python_install() {
  ! bash "$(dirname "${BASH_SOURCE[0]}")/../resolve_python.sh" >/dev/null 2>&1
}

# Print "Y" to allow emp_install_r to run with elevated privileges when needed.
# Respects EMP_AUTO_INSTALL=0 (skip auto-install, only warn).
emp_should_auto_install() {
  [[ "${EMP_AUTO_INSTALL:-1}" == "1" ]] && return 0 || return 1
}

# Check whether we already have root/admin. If not, and AUTO_INSTALL=1, prompt for sudo.
emp_require_sudo_or_die() {
  if [[ $EUID -eq 0 ]]; then return 0; fi
  if ! emp_should_auto_install; then
    emp_err "Refusing to elevate: EMP_AUTO_INSTALL=0. Re-run without that env var, or run as root."
    return 1
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    emp_err "Need root privileges to install system packages. Re-run as root or install sudo."
    return 1
  fi
  emp_log "Requesting sudo to install system packages…"
  sudo -v || return 1
}

# Persist a flag file so the rest of the install pipeline can detect "we just
# installed R / python / git" and re-scan PATH.
emp_mark_installed() {
  local key="$1"
  local ts; ts="$(date +%s)"
  mkdir -p "${EMP_INSTALL_STATE_DIR:-${TMPDIR:-/tmp}/emp_install_state}"
  printf "%s %s\n" "$ts" "$key" >> "${EMP_INSTALL_STATE_DIR:-${TMPDIR:-/tmp}/emp_install_state}/installed.log"
}