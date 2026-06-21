#!/usr/bin/env Rscript
# Test DESeq2 / edgeR multi-group differential modes (pairwise, all_pairwise, multi_lrt).
# Usage: Rscript webapp/scripts/test_diff_multi_group.R [--fail-fast]

args <- commandArgs(trailingOnly = TRUE)
fail_fast <- "--fail-fast" %in% args

msg <- function(...) cat(sprintf(...), "\n")
assert_ok <- function(label, expr) {
  out <- tryCatch(force(expr), error = function(e) e)
  if (inherits(out, "error")) {
    msg("[FAIL] %s — %s", label, conditionMessage(out))
    if (fail_fast) quit(status = 1)
    return(FALSE)
  }
  msg("[OK] %s", label)
  TRUE
}

suppressPackageStartupMessages({
  library(EasyMultiProfiler)
  library(MultiAssayExperiment)
})

backend <- "webapp/backend"
for (f in c(
  "helpers/session.R", "helpers/utils.R", "helpers/import.R",
  "helpers/demo_data.R", "helpers/clinical.R", "helpers/analysis.R", "helpers/jobs.R"
)) source(file.path(backend, f))

sid <- create_session()
imp <- import_demo_dataset(sid, "rnaseq_course")
if (!isTRUE(imp$success)) stop("Demo import failed: ", imp$error %||% "unknown")
exp <- "rnaseq_course"

cd <- as.data.frame(SummarizedExperiment::colData(get_empt_fresh(sid, exp)))
grp_col <- if ("Group" %in% names(cd)) "Group" else names(cd)[1]
groups <- unique(na.omit(as.character(cd[[grp_col]])))
msg("Groups (%d): %s", length(groups), paste(groups, collapse = ", "))

ok <- TRUE
ok <- assert_ok("DESeq2 pairwise", {
  r <- run_diff(sid, exp, "DESeq2", grp_col, groups[1], groups[2],
                filter_low = TRUE, subset_two_groups = TRUE, comparison_mode = "pairwise")
  stopifnot(is.data.frame(r), nrow(r) > 0, any(is.finite(r$log2FC)))
}) && ok

ok <- assert_ok("DESeq2 all_pairwise", {
  r <- run_diff(sid, exp, "DESeq2", grp_col, filter_low = TRUE,
                subset_two_groups = FALSE, comparison_mode = "all_pairwise")
  stopifnot(is.data.frame(r), nrow(r) > 0)
  stopifnot(length(unique(r$vs)) >= 2)
  stopifnot(any(is.finite(r$log2FC)))
}) && ok

ok <- assert_ok("DESeq2 multi_lrt + pairwise merge", {
  r <- run_diff(sid, exp, "DESeq2", grp_col, filter_low = TRUE,
                subset_two_groups = FALSE, comparison_mode = "multi_lrt")
  stopifnot(is.data.frame(r), nrow(r) > 0)
  stopifnot(length(unique(r$vs)) >= 2)
  stopifnot(any(is.finite(r$log2FC)))
  if ("lrt_pvalue" %in% names(r)) stopifnot(any(is.finite(r$lrt_pvalue)))
}) && ok

if (requireNamespace("edgeR", quietly = TRUE)) {
  ok <- assert_ok("edgeR all_pairwise", {
    r <- run_diff(sid, exp, "edgeR", grp_col, filter_low = TRUE,
                  subset_two_groups = FALSE, comparison_mode = "all_pairwise")
    stopifnot(is.data.frame(r), nrow(r) > 0, any(is.finite(r$log2FC)))
  }) && ok

  ok <- assert_ok("edgeR multi_lrt + pairwise merge", {
    r <- run_diff(sid, exp, "edgeR", grp_col, filter_low = TRUE,
                  subset_two_groups = FALSE, comparison_mode = "multi_lrt")
    stopifnot(is.data.frame(r), nrow(r) > 0, any(is.finite(r$log2FC)))
  }) && ok
} else {
  msg("[SKIP] edgeR not installed")
}

msg("=== Summary: %s ===", if (ok) "ALL PASSED" else "FAILED")
quit(status = if (ok) 0 else 2)
