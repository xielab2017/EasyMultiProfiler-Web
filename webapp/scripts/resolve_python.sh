#!/usr/bin/env bash
# Print the absolute path of the interpreter used by the web services.
set -eu

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

try_python() {
  local exe="$1"
  [[ -f "$exe" && -x "$exe" ]] || return 1
  "$exe" -c 'import sys; sys.exit(sys.version_info < (3, 10))' </dev/null >/dev/null 2>&1 || return 1
  [[ "$exe" == /* ]] || exe="$PWD/$exe"
  printf '%s\n' "$exe"
}

if [[ -n "${EMPI_PYTHON:-}" ]]; then
  exe="$(type -P -- "$EMPI_PYTHON" || true)"
  if [[ -n "$exe" ]] && try_python "$exe"; then exit 0; fi
  echo "EMPI_PYTHON=$EMPI_PYTHON must point to a working Python >= 3.10." >&2
  exit 1
fi

try_python "$root/.local_run/metadata_venv/bin/python" && exit 0
for prefix in "${VIRTUAL_ENV:-}" "${CONDA_PREFIX:-}"; do
  [[ -n "$prefix" ]] && try_python "$prefix/bin/python" && exit 0
done

# Finder and non-login shells may omit python.org and Homebrew from PATH.
names=(python3 python python3.15 python3.14 python3.13 python3.12 python3.11 python3.10)
for name in "${names[@]}"; do
  while IFS= read -r exe; do
    try_python "$exe" && exit 0
  done < <(type -aP -- "$name" || true)
done
for bin in "$HOME/.local/bin" /opt/homebrew/bin /usr/local/bin /Library/Frameworks/Python.framework/Versions/Current/bin; do
  for name in "${names[@]}"; do
    try_python "$bin/$name" && exit 0
  done
done

registry="$HOME/.conda/environments.txt"
if [[ -r "$registry" ]]; then
  while IFS= read -r prefix || [[ -n "$prefix" ]]; do
    [[ "$prefix" == /* ]] && try_python "$prefix/bin/python" && exit 0
  done < "$registry"
fi
for prefix in "${MAMBA_ROOT_PREFIX:-$HOME/micromamba}" "$HOME/miniforge3" "$HOME/miniconda3" "$HOME/anaconda3"; do
  for exe in "$prefix/bin/python" "$prefix"/envs/*/bin/python; do
    try_python "$exe" && exit 0
  done
done

echo 'Python >= 3.10 not found. Install Python or set EMPI_PYTHON to its executable.' >&2
exit 1
