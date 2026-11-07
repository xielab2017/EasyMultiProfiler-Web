# Performance and Memory — EasyMultiProfiler Web v9.1.0

This document describes only mechanisms that exist in the code base:
the memory helpers in `webapp/backend/helpers/memory_utils.R`, the step
cache from v9.1.0 Round 1 in `webapp/backend/helpers/run_pipeline_cache.R`,
the background job system in `webapp/backend/helpers/jobs.R`, and the QC /
network figures in `webapp/backend/helpers/viz_qc.R`. No benchmark numbers
are stated here; measurements belong in the run's reproducible report
(see `docs/NAR_MANUSCRIPT_PLAN.md`, Table 3, which stays a TODO until the
benchmarks have actually been run).

---

## 1. Memory strategy

### 1.1 Inspect before you optimise

`emp_memory_info(env)` returns the R garbage-collector "used" total (Mb)
and the 10 largest objects of an environment (`name`, `size_mb`), plus
the R version. The same snapshot is exposed over HTTP:

```
GET /api/system/memory
```

Use it to find what a long-lived API session is actually holding before
changing code — in practice the assay matrices and cached step results
dominate.

### 1.2 Sparse conversion for sparse assays

Many omics matrices (16S counts, single-cell-style feature tables) are
mostly zeros. `emp_matrix_density(mat)` measures the storage density
(proportion of entries that are non-zero or NA), and

```r
mat <- emp_maybe_sparse(mat, threshold = 0.30)
```

converts the matrix to a `Matrix` sparse matrix when the density is
strictly below `threshold` (default 0.30) and the `Matrix` package is
available. The conversion changes only the storage class — values are
never modified — and the result carries the attributes
`sparse_converted = TRUE` and a human-readable `note`. When the matrix
is not sparse enough, or `Matrix` is unavailable, the original object is
returned unchanged.

### 1.3 Chunking large row-wise work

`emp_chunk_plan(n, target_mb = 512, row_bytes_estimate = 8192)` splits
`n` rows into an integer vector of chunk sizes whose sum is `n`, sized
so that each chunk fits the per-chunk memory budget
(`target_mb` / `row_bytes_estimate`). Row-wise statistics, per-feature
tests and plot-data preparation can iterate over these chunks instead of
materialising several full-size copies of a matrix.

### 1.4 Step cache reuse (Round 1)

Deterministic analysis steps are cached on disk by
`emp_run_cached_step(name, key_parts, fn, cache_dir)` with a content key
from `emp_step_key()`: re-running a pipeline with unchanged inputs and
parameters reuses the stored RDS result instead of recomputing (and
instead of keeping both the inputs and every intermediate in memory).
`emp_resume_plan(steps, manifest)` returns the steps that are not yet
marked done, so an interrupted Run All resumes where it stopped.
`emp_lapply_parallel()` runs independent steps in parallel (fork on
Unix, PSOCK cluster on Windows) when `EMP_PARALLEL_WORKERS > 1`.

### 1.5 Release intermediates explicitly

`emp_release(x, "y", env = .GlobalEnv)` removes the named objects and
runs `gc()`, returning the list of removed names and an approximate
freed-Mb estimate (the gc "used" difference — an estimate, not an exact
accounting). Workflow code should release large intermediates (raw
import tables, per-step copies) as soon as the cached step result is on
disk.

### 1.6 Practical guidance

- Prefer the cached-step path for anything recomputed interactively
  (parameter tweaks in the UI hit the cache instead of recomputing).
- Convert assay matrices once, at import time, not inside every step.
- Chunk row-wise operations on matrices that do not fit comfortably in
  RAM together with their results; keep `target_mb` conservative on
  shared teaching machines.
- Watch `GET /api/system/memory` during long sessions; a steadily
  growing top-object list usually means an intermediate was not released
  or a cache directory was bypassed.

---

## 2. Background jobs

Long analyses never block the UI. The job runner
(`webapp/backend/helpers/jobs.R`) executes work in `callr` worker
processes and persists state as JSON files on disk
(`<id>.json`, `<id>.result`, `<id>.log`), so job status survives API
restarts and is visible to every request handler.

Endpoints:

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/jobs` | List recent jobs (newest first): id, kind, status, progress, message, started/finished when present. Query parameter: `limit` (default 20). |
| GET | `/api/jobs/<job_id>` | Poll one job's status and progress. |
| GET | `/api/jobs/<job_id>/result` | Fetch the result of a finished job. |
| POST | `/api/jobs/<job_id>/cancel` | Request cancellation of a running job. |

Front end: the job tray (`webapp/frontend/js/job_tray.js`) sits at the
bottom-right of the page, polls `GET /api/jobs` every 3 seconds only
while a job is queued/running or the tray is open, shows a progress bar
per job, offers Cancel for running jobs, and raises a friendly toast
("job finished" / "job failed", localized in 11 languages) when a job
completes. Friendly hints (`friendly_hints.js`) remind users once that
long analyses keep running in the background while they switch pages.

Job states: `queued`, `running`, `done`, `error`, `cancel_requested`,
`cancelled`. Old job files are cleaned by `cleanup_old_jobs()`.

---

## 3. Visualization notes

`webapp/backend/helpers/viz_qc.R` provides the analysis figures that
pair with the memory and rigor work:

- `emp_plot_qc_dashboard(qc, locale)` — panels for per-sample
  missingness, per-feature missingness, and a batch/group association
  tile (PCA R-squared, or the batch × group Cramér's V), built from an
  `emp_qc_rigor()` result. Panels are combined with `patchwork` when
  available; otherwise the list of panels is returned.
- `emp_plot_crossomics_network(edges, locale)` — the cross-omics
  Spearman network from `emp_cross_omics_network()` on a deterministic
  circle layout (no igraph dependency); edge alpha encodes |cor| and
  colour encodes sign.
- `emp_save_plot_i18n(plot, file, locale, ...)` — saves PDF (Cairo),
  SVG (svglite when available) or PNG through `ggsave`.

### Multilingual fonts

Every figure applies `emp_pub_theme()` (when sourced) with its text
family set from `emp_plot_font_family(locale)`
(`webapp/backend/helpers/i18n_locale.R`): Japanese, Korean, Simplified
and Traditional Chinese plots use the matching Noto Sans CJK families,
Arabic uses Noto Sans Arabic, and other locales fall back to the generic
`sans`. Without this, CJK and Arabic glyphs render as boxes on most
graphics devices. Install the corresponding Noto fonts on the host for
publication output; the family names are preferences, and devices fall
back gracefully when a font is missing.
