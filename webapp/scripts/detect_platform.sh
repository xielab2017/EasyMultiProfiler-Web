#!/usr/bin/env bash
# detect_platform.sh — EMP Web v9.1.0 platform auto-detection (macOS / Linux / WSL).
# Prints one JSON object on stdout:
#   {"os":"windows|macos|linux|unknown","arch":"...","distro":"...",
#    "r_version":"...","python_version":"...","git_version":"..."}
# Windows uses detect_platform.ps1 instead; this script reports "windows"
# when it detects WSL / Git-Bash style environments on a Windows host.
set -u

json_escape() {
  # Minimal JSON string escaping for the simple values produced here.
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

os="unknown"
distro=""
arch="$(uname -m 2>/dev/null || echo unknown)"

case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin)
    os="macos"
    distro="$(sw_vers -productVersion 2>/dev/null || echo macOS)"
    ;;
  Linux)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      os="windows"
      distro="WSL"
    else
      os="linux"
      if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        distro="$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-${ID:-Linux}}")"
      else
        distro="Linux"
      fi
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    os="windows"
    distro="Windows (Git-Bash)"
    ;;
  *)
    os="unknown"
    distro="$(uname -s 2>/dev/null || echo unknown)"
    ;;
esac

r_version=""
if command -v Rscript >/dev/null 2>&1; then
  r_version="$(Rscript -e 'cat(as.character(getRversion()))' 2>/dev/null || true)"
fi

python_version=""
if command -v python3 >/dev/null 2>&1; then
  python_version="$(python3 -c 'import platform; print(platform.python_version())' 2>/dev/null || true)"
elif command -v python >/dev/null 2>&1; then
  python_version="$(python -c 'import platform; print(platform.python_version())' 2>/dev/null || true)"
fi

git_version=""
if command -v git >/dev/null 2>&1; then
  git_version="$(git --version 2>/dev/null | sed 's/^git version //')"
fi

printf '{"os":"%s","arch":"%s","distro":"%s","r_version":"%s","python_version":"%s","git_version":"%s"}\n' \
  "$(json_escape "$os")" \
  "$(json_escape "$arch")" \
  "$(json_escape "$distro")" \
  "$(json_escape "$r_version")" \
  "$(json_escape "$python_version")" \
  "$(json_escape "$git_version")"
