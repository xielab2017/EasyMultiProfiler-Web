# ChIP-seq / CUT&RUN Ops Guide

Operational path verified on 2026-07-24 (`webapp/test_outputs/chip_full_ops_guide/report.md`):
**PASS=39 · FAIL=0 · SKIP=4** (joint EXPECTED_GATE).

## Data

| Asset | Path | Notes |
|-------|------|-------|
| Peak BED (tracked) | `tests/ChIP/HA_summits_0.05.bed` | Genome **mm**; E2E uses top5000 by score |
| BAMs (local only) | `tests/ChIP/HA{3,4,5}.bam`, `IgG{1,3,4}.bam` | Need ≥2T+≥2C for DiffBind/deepTools; **do not commit** |

## UI workflow

### Step1 (ChIP core)

1. Open **ChIP-seq**; set genome **mm** (or hs).
2. Upload peak BED as a sample → **select active peak**.
3. Peak QC → blacklist → merge → summit (`peaks_ops`).
4. **Annotate** (ChIPseeker) — required before joint bridges.

### Step2 (recipes / tools)

| Pack / tool | Needs BAM? | Notes |
|-------------|------------|-------|
| Core (partial) | No (DiffBind step yes) | QC → ops → annotate |
| Histone / enhancer | No | promoter / enhancer / SE / broad |
| Motif | No BAM; needs HOMER | `noknown` for smoke |
| Visualization | Yes | deepTools coverage / corr / heatmap |
| DiffBind | Yes ≥2T+≥2C | Keep narrow peaks; backend writes BED3 |
| Joint packs | No BAM; need DE/clinical | RNA / 16S / MBX / clinical on **Data** page first |

Prefer **deepTools → DiffBind → HOMER** under memory pressure (HOMER leaves plumber RSS high).

### Joint packs

1. **Data** → import `rnaseq_course` / `m16s_course` / clinical / MBX.
2. Run differential (or import DE CSV → `diff_raw`).
3. Return to ChIP Step2 → run joint recipe.
4. Without DE/clinical, API returns **EXPECTED_GATE** (dependency missing — not a bug).

## Reproduce E2E

```bash
cd EasyMultiProfiler-Web-V2
export NO_PROXY='*' http_proxy= https_proxy= HTTP_PROXY= HTTPS_PROXY=
export R_LIBS=.local_run/R_libs
export PATH="$PWD/.local_run/bin:$PATH"
# Rscript webapp/backend/run_api.R   # if API down
python3 webapp/test_outputs/chip_full_ops_guide/launch_detached.py
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| DiffBind `missing value where TRUE/FALSE needed` | Use narrow/1-bp peaks; do not pre-expand summit±N |
| deepTools / API disconnect | Restart API; coverage uses `-p 1` + bin floor; retry |
| HOMER path spaces | Backend stages under space-free temp |
| Joint gate | Import omics + DE on Data page first |

Also: in-app Guide fold card **ChIP-seq / CUT&RUN**; `docs/USER_GUIDE_V5.md` §4.4.
