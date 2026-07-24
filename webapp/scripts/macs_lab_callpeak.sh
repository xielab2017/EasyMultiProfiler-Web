#!/usr/bin/env bash
# EMP lab MACS2/3 callpeak template
# Aligned with 吴丹 LIPUS Cut-Run scripts (TF / Histone Cut&Run / ATAC).
#
# Core recipe (all three primary assays share BAMPE + -p + bedGraph):
#   macs2 callpeak -t TREAT... -c CTRL... -f BAMPE -g 1.87e9 -n NAME --bdg -B -p 0.05
#
# Usage:
#   ./macs_lab_callpeak.sh tf_p05      out_dir  treat1.bam treat2.bam -- IgG1.bam IgG2.bam
#   ./macs_lab_callpeak.sh histone_p05 out_dir  His.bam -- IgG.bam
#   ./macs_lab_callpeak.sh atac_p05    out_dir  ATAC1.bam ATAC2.bam --            # no control
#   ./macs_lab_callpeak.sh atac_q05    out_dir  ATAC1.bam -- IgG.bam
#   ./macs_lab_callpeak.sh tf_p01      out_dir  HA*.bam -- IgG*.bam
#
# After success, upload to EMP (priority order):
#   1) *_peaks.narrowPeak   2) *_summits.bed   3) *_peaks.xls
# Optional: macs log, treat/control bedGraph; BAM only for deepTools/DiffBind/IGV.
set -euo pipefail

PRESET="${1:-}"
OUTDIR="${2:-}"
shift 2 || true

if [[ -z "${PRESET}" || -z "${OUTDIR}" ]]; then
  sed -n '1,25p' "$0"
  exit 1
fi

# Split treat / control at "--"
TREAT=()
CTRL=()
mode=treat
for a in "$@"; do
  if [[ "$a" == "--" ]]; then mode=ctrl; continue; fi
  if [[ "$mode" == treat ]]; then TREAT+=("$a"); else CTRL+=("$a"); fi
done

if [[ ${#TREAT[@]} -eq 0 ]]; then
  echo "ERROR: provide at least one treatment BAM before --" >&2
  exit 1
fi

# Prefer macs2 for lab parity; fall back to macs3.
MACS_BIN="${EMP_MACS:-}"
if [[ -z "$MACS_BIN" ]]; then
  if command -v macs2 >/dev/null 2>&1; then MACS_BIN=macs2
  elif command -v macs3 >/dev/null 2>&1; then MACS_BIN=macs3
  else echo "ERROR: macs2/macs3 not found" >&2; exit 1
  fi
fi

# Classic MACS2 mouse effective size (do NOT use MACS3 short-code mm=2.65e9).
GSIZE="${EMP_GSIZE:-1.87e9}"
NAME="peaks"
FMT=BAMPE
CUTOFF_ARGS=(-p 0.05)
EXTRA=(--bdg -B)

case "$PRESET" in
  tf_p05|histone_p05|cutrun_p05|atac_p05)
    NAME="${PRESET}"
    CUTOFF_ARGS=(-p 0.05)
    ;;
  tf_p01|histone_p01|cutrun_p01)
    NAME="${PRESET}"
    CUTOFF_ARGS=(-p 0.01)
    ;;
  tf_p001|cutrun_p001)
    NAME="${PRESET}"
    CUTOFF_ARGS=(-p 0.001)
    ;;
  atac_q05)
    NAME=atac_q05
    CUTOFF_ARGS=(-q 0.05)
    ;;
  histone_broad_p05)
    NAME=histone_broad_p05
    CUTOFF_ARGS=(-p 0.05 --broad --broad-cutoff 0.1)
    ;;
  *)
    echo "Unknown preset: $PRESET" >&2
    echo "Known: tf_p05 histone_p05 atac_p05 atac_q05 tf_p01 histone_p01 tf_p001 histone_broad_p05" >&2
    exit 1
    ;;
esac

mkdir -p "$OUTDIR"
LOG="$OUTDIR/${NAME}.macs.log"

CMD=("$MACS_BIN" callpeak -t "${TREAT[@]}" -f "$FMT" -g "$GSIZE" -n "$NAME" --outdir "$OUTDIR" "${CUTOFF_ARGS[@]}" "${EXTRA[@]}")
if [[ ${#CTRL[@]} -gt 0 ]]; then
  CMD+=(-c "${CTRL[@]}")
fi

echo "[macs_lab] preset=$PRESET caller=$MACS_BIN gsize=$GSIZE" | tee "$LOG"
echo "[macs_lab] treat=${TREAT[*]}" | tee -a "$LOG"
echo "[macs_lab] ctrl=${CTRL[*]:-(none)}" | tee -a "$LOG"
printf '[macs_lab] cmd='; printf '%q ' "${CMD[@]}"; echo | tee -a "$LOG"

"${CMD[@]}" 2>&1 | tee -a "$LOG"

NP=$(ls "$OUTDIR"/${NAME}_peaks.narrowPeak "$OUTDIR"/${NAME}_peaks.broadPeak 2>/dev/null | head -1 || true)
SM=$(ls "$OUTDIR"/${NAME}_summits.bed 2>/dev/null | head -1 || true)
XLS=$(ls "$OUTDIR"/${NAME}_peaks.xls 2>/dev/null | head -1 || true)
N=0
if [[ -n "$NP" ]]; then N=$(grep -cv '^#' "$NP" || true); fi

# Compact run_info for EMP upload
INFO="$OUTDIR/${NAME}.run_info.txt"
{
  echo "preset=$PRESET"
  echo "caller=$MACS_BIN"
  echo "format=$FMT"
  echo "gsize=$GSIZE"
  echo "cutoff=${CUTOFF_ARGS[*]}"
  echo "n_peaks=$N"
  echo "peak_file=${NP:-}"
  echo "summit_file=${SM:-}"
  echo "xls_file=${XLS:-}"
  echo "treat=${TREAT[*]}"
  echo "ctrl=${CTRL[*]:-}"
  echo "command=${CMD[*]}"
} > "$INFO"

echo "[macs_lab] DONE n_peaks=$N"
echo "[macs_lab] upload: $NP"
echo "[macs_lab] upload: $SM"
echo "[macs_lab] upload: $XLS"
echo "[macs_lab] meta:   $INFO"
