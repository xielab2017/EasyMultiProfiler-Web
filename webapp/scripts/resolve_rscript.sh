#!/usr/bin/env bash
# Print the absolute path of an Rscript that meets the web runtime minimum.
set -eu

try_rscript() {
  local exe="$1"
  [[ -f "$exe" && -x "$exe" ]] || return 1
  if "$exe" --vanilla -e 'if (getRversion() < "4.3.3") quit(status=2)' </dev/null >/dev/null 2>&1; then
    [[ "$exe" == /* ]] || exe="$PWD/$exe"
    printf '%s\n' "$exe"
    return 0
  fi
  return 1
}

if [[ -n "${EMPI_RSCRIPT:-}" ]]; then
  exe="$(type -P -- "$EMPI_RSCRIPT" || true)"
  if [[ -n "$exe" ]] && try_rscript "$exe"; then exit 0; fi
  echo "Rscript not found or unusable at EMPI_RSCRIPT=$EMPI_RSCRIPT (requires R >= 4.3.3)." >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
try_rscript "$root/.local_run/r-runtime/bin/Rscript" && exit 0
if [[ -n "${R_HOME:-}" ]] && try_rscript "$R_HOME/bin/Rscript"; then exit 0; fi
if [[ -n "${CONDA_PREFIX:-}" ]] && try_rscript "$CONDA_PREFIX/bin/Rscript"; then exit 0; fi
while IFS= read -r exe; do
  try_rscript "$exe" && exit 0
done < <(type -aP Rscript || true)

for exe in /Library/Frameworks/R.framework/Resources/bin/Rscript \
           /opt/homebrew/bin/Rscript /usr/local/bin/Rscript /usr/bin/Rscript \
           /Library/Frameworks/R.framework/Versions/*/Resources/bin/Rscript; do
  try_rscript "$exe" && exit 0
done

# Conda and micromamba register named and custom-prefix environments here.
registry="${HOME:-}/.conda/environments.txt"
if [[ -r "$registry" ]]; then
  while IFS= read -r prefix || [[ -n "$prefix" ]]; do
    [[ "$prefix" == /* ]] && try_rscript "$prefix/bin/Rscript" && exit 0
  done < "$registry"
fi
for prefix in "${MAMBA_ROOT_PREFIX:-${HOME:-}/micromamba}" "${HOME:-}/miniforge3" "${HOME:-}/miniconda3" "${HOME:-}/anaconda3"; do
  for exe in "$prefix/bin/Rscript" "$prefix"/envs/*/bin/Rscript; do
    try_rscript "$exe" && exit 0
  done
done

echo "Rscript not found or unusable. Install R >= 4.3.3 or set EMPI_RSCRIPT to its executable." >&2
exit 1
