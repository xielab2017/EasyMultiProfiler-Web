# qc_rigor.R - EMP Web v9.1.0 analysis upgrade A: rigor QC (base R only).
#
# emp_qc_rigor() inspects a feature x sample numeric matrix and REPORTS
# rigor risks: missingness, zero / near-zero variance features, and
# batch-group confounding. It never drops, imputes or otherwise modifies
# data (the project rigor rule): the caller decides what to do with the
# warnings, and the warnings belong in the analysis report.

#' Run rigor QC checks on a numeric matrix (features x samples).
#'
#' @param mat Numeric matrix or data.frame, features in rows, samples in
#'   columns (column names are sample ids).
#' @param meta Optional sample metadata data.frame with one row per
#'   sample, in column order of `mat`.
#' @param group_col Optional metadata column name for the study group.
#' @param batch_col Optional metadata column name for the batch.
#' @return list(checks, warnings, summary). `warnings` is a character
#'   vector of stable codes: "HIGH_MISSINGNESS",
#'   "BATCH_GROUP_CONFOUNDING", "BATCH_PC_ASSOCIATION".
emp_qc_rigor <- function(mat, meta = NULL, group_col = NULL,
                         batch_col = NULL) {
  if (is.data.frame(mat)) mat <- as.matrix(mat)
  if (!is.matrix(mat) || !is.numeric(mat)) {
    stop("emp_qc_rigor: `mat` must be a numeric matrix (features x samples)")
  }
  n_features <- nrow(mat)
  n_samples <- ncol(mat)
  warnings_out <- character(0)
  checks <- list()

  ## Missingness -------------------------------------------------------
  missing_overall <- if (length(mat) > 0) mean(is.na(mat)) else 0
  per_sample_missing <- if (n_samples > 0) colMeans(is.na(mat)) else numeric(0)
  per_feature_missing <- if (n_features > 0) rowMeans(is.na(mat)) else numeric(0)
  checks$missingness <- list(
    overall = missing_overall,
    max_per_sample = if (length(per_sample_missing)) max(per_sample_missing) else 0,
    max_per_feature = if (length(per_feature_missing)) max(per_feature_missing) else 0,
    n_samples_over_50pct_missing = sum(per_sample_missing > 0.5),
    # Full vectors (v9.1.0 Round 2): consumed by emp_plot_qc_dashboard().
    per_sample = per_sample_missing,
    per_feature = per_feature_missing
  )
  if (isTRUE(missing_overall > 0.2)) {
    warnings_out <- c(warnings_out, "HIGH_MISSINGNESS")
  }

  ## Variance ----------------------------------------------------------
  row_vars <- tryCatch(
    apply(mat, 1, function(x) {
      x <- x[!is.na(x)]
      if (length(x) < 2) return(NA_real_)
      stats::var(x)
    }),
    error = function(e) rep(NA_real_, n_features)
  )
  zero_var <- sum(row_vars == 0, na.rm = TRUE)
  near_zero_var <- sum(row_vars > 0 & row_vars <= 1e-8, na.rm = TRUE)
  checks$variance <- list(
    zero_variance_features = zero_var,
    near_zero_variance_features = near_zero_var,
    unmeasurable_features = sum(is.na(row_vars))
  )

  ## Batch x group confounding ----------------------------------------
  has_meta <- !is.null(meta) && is.data.frame(meta) && nrow(meta) == n_samples
  batch <- NULL
  group <- NULL
  if (has_meta && !is.null(batch_col) && batch_col %in% names(meta)) {
    batch <- as.factor(meta[[batch_col]])
  }
  if (has_meta && !is.null(group_col) && group_col %in% names(meta)) {
    group <- as.factor(meta[[group_col]])
  }
  if (!is.null(batch) && !is.null(group) &&
      nlevels(batch) > 1 && nlevels(group) > 1) {
    conf <- tryCatch({
      tab <- table(batch, group)
      test <- suppressWarnings(stats::chisq.test(tab))
      n <- sum(tab)
      k <- min(nrow(tab), ncol(tab)) - 1
      cramers_v <- if (k > 0 && n > 0) {
        sqrt(as.numeric(test$statistic) / (n * k))
      } else {
        NA_real_
      }
      list(chisq = as.numeric(test$statistic),
           df = as.numeric(test$parameter),
           p_value = as.numeric(test$p.value),
           cramers_v = cramers_v)
    }, error = function(e) NULL)
    if (!is.null(conf)) {
      checks$batch_group_confounding <- conf
      if (isTRUE(conf$cramers_v > 0.3) && isTRUE(conf$p_value < 0.05)) {
        warnings_out <- c(warnings_out, "BATCH_GROUP_CONFOUNDING")
      }
    }
  }

  ## PCA association with batch / group --------------------------------
  pc_assoc <- tryCatch({
    keep <- stats::complete.cases(mat) & !is.na(row_vars) & row_vars > 0
    if (sum(keep) < 2 || n_samples < 3) return(NULL)
    x <- t(mat[keep, , drop = FALSE])
    pc <- stats::prcomp(x, center = TRUE, scale. = TRUE)
    n_pc <- min(3L, ncol(pc$x))
    rows <- list()
    batch_pc_hit <- FALSE
    for (i in seq_len(n_pc)) {
      score <- pc$x[, i]
      entry <- list(pc = paste0("PC", i),
                    variance_explained = summary(pc)$importance[2, i])
      if (!is.null(batch) && nlevels(batch) > 1) {
        r2 <- tryCatch(summary(stats::lm(score ~ batch))$r.squared,
                       error = function(e) NA_real_)
        entry$batch_r2 <- r2
        if (i <= 2 && isTRUE(r2 > 0.3)) batch_pc_hit <- TRUE
      }
      if (!is.null(group) && nlevels(group) > 1) {
        r2 <- tryCatch(summary(stats::lm(score ~ group))$r.squared,
                       error = function(e) NA_real_)
        entry$group_r2 <- r2
      }
      rows[[length(rows) + 1]] <- entry
    }
    attr(rows, "batch_hit") <- batch_pc_hit
    attr(rows, "features_used") <- sum(keep)
    rows
  }, error = function(e) NULL)
  if (!is.null(pc_assoc)) {
    checks$pca <- list(
      features_used = attr(pc_assoc, "features_used"),
      note = "PCA used complete, non-constant features only; no imputation was performed.",
      pcs = pc_assoc
    )
    if (isTRUE(attr(pc_assoc, "batch_hit"))) {
      warnings_out <- c(warnings_out, "BATCH_PC_ASSOCIATION")
    }
  }

  summary_out <- list(
    n_features = n_features,
    n_samples = n_samples,
    missing_overall = missing_overall,
    zero_variance_features = zero_var,
    near_zero_variance_features = near_zero_var,
    n_warnings = length(warnings_out),
    note = "Report only: no data were dropped or imputed by this QC."
  )
  list(checks = checks, warnings = warnings_out, summary = summary_out)
}
