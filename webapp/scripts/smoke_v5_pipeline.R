#!/usr/bin/env Rscript
# v5 smoke: import 16S / RNA-seq / clinical demo datasets and run core steps.
# Usage: Rscript webapp/scripts/smoke_v5_pipeline.R
# Requires: EasyMultiProfiler + backend helpers (no running API needed).

args <- commandArgs(trailingOnly = TRUE)
fail_fast <- "--fail-fast" %in% args

msg <- function(...) cat(sprintf(...), "\n")
stop_on <- function(cond, label) {
  if (!isTRUE(cond)) {
    msg("[FAIL] %s", label)
    if (fail_fast) quit(status = 1)
    FALSE
  } else {
    msg("[OK] %s", label)
    TRUE
  }
}

suppressPackageStartupMessages({
  library(EasyMultiProfiler)
  library(MultiAssayExperiment)
})

backend <- "webapp/backend"
for (f in c(
  "helpers/session.R", "helpers/utils.R", "helpers/import.R",
  "helpers/demo_data.R", "helpers/analysis.R", "helpers/viz.R",
  "helpers/clinical.R", "helpers/workflow_microbiome_16s_api.R",
  "helpers/workflow_transcriptomics.R"
)) source(file.path(backend, f))

ok <- TRUE
msg("=== EMP-Web v5 smoke pipeline ===")

# --- 16S ---
sid16 <- create_session()
r16 <- import_demo_dataset(sid16, "m16s_course")
ok <- stop_on(r16$success && r16$samples >= 10, "16S demo import") && ok
ex16 <- "m16s_course"
alpha16 <- tryCatch({ run_alpha(sid16, ex16); TRUE }, error = function(e) NULL)
ok <- stop_on(isTRUE(alpha16), "16S alpha diversity") && ok

# --- RNA-seq ---
sidtx <- create_session()
rtx <- import_demo_dataset(sidtx, "rnaseq_course")
ok <- stop_on(rtx$success && rtx$features >= 100, "RNA-seq demo import") && ok
extx <- "rnaseq_course"
prof <- tryCatch(tx_profile(sidtx, extx), error = function(e) NULL)
ok <- stop_on(!is.null(prof) && prof$n_samples >= 2, "RNA-seq profile") && ok

# --- Clinical ---
sidcl <- create_session()
rcl <- import_demo_dataset(sidcl, "clinical_course")
ok <- stop_on(rcl$success && length(rcl$columns) >= 3, "Clinical demo import") && ok
vars <- tryCatch(list_clinical_vars_standalone(sidcl), error = function(e) NULL)
ok <- stop_on(!is.null(vars) && nrow(vars) >= 3, "Clinical vars list") && ok

msg("=== Summary: %s ===", if (ok) "ALL PASSED" else "SOME CHECKS FAILED")
quit(status = if (ok) 0 else 2)
