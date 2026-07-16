# Metabolomics workflow helpers for API routes under /api/workflows/metabolomics/*

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

mbx_require_string <- function(x, field) {
  if (is.null(x) || !is.character(x) || length(x) != 1 || trimws(x) == "") {
    stop(sprintf("`%s` is required and must be a non-empty string.", field))
  }
  trimws(x)
}

mbx_require_numeric <- function(x, field, min_value = -Inf, max_value = Inf) {
  if (is.null(x) || length(x) != 1) {
    stop(sprintf("`%s` is required and must be numeric.", field))
  }
  value <- suppressWarnings(as.numeric(x))
  if (is.na(value)) stop(sprintf("`%s` must be numeric.", field))
  if (value < min_value || value > max_value) {
    stop(sprintf("`%s` must be between %s and %s.", field, min_value, max_value))
  }
  value
}

mbx_detect_missingness <- function(empt) {
  ad <- SummarizedExperiment::assays(empt)[[1]]
  total <- length(ad)
  if (total == 0) return(0)
  sum(is.na(ad)) / total
}

mbx_default_impute <- function(missingness) {
  if (missingness >= 0.2) "min" else "knn"
}

mbx_default_normalize <- function(empt) {
  ad <- SummarizedExperiment::assays(empt)[[1]]
  if (any(ad < 0, na.rm = TRUE)) return("clr")
  "log"
}

mbx_default_diff_method <- function(normalization_method) {
  if (normalization_method %in% c("log", "clr", "rclr")) return("limma")
  "wilcox"
}

mbx_profile <- function(session_id, experiment) {
  session_id <- mbx_require_string(session_id, "session_id")
  experiment <- mbx_require_string(experiment, "experiment")
  empt <- load_empt(session_id, experiment)

  raw_missingness <- mbx_detect_missingness(empt)
  default_max_na <- if (raw_missingness >= 0.3) 0.4 else 0.2
  default_impute <- mbx_default_impute(raw_missingness)
  default_normalize <- mbx_default_normalize(empt)
  default_diff <- mbx_default_diff_method(default_normalize)

  list(
    success = TRUE,
    n_features = nrow(SummarizedExperiment::assays(empt)[[1]]),
    n_samples = ncol(SummarizedExperiment::assays(empt)[[1]]),
    raw_missingness = raw_missingness,
    defaults = list(
      max_na = default_max_na,
      impute_method = default_impute,
      normalize_method = default_normalize,
      differential_method = default_diff
    )
  )
}

mbx_validate <- function(session_id, experiment) {
  p <- mbx_profile(session_id, experiment)
  list(
    success = TRUE,
    checks = list(
      has_features = p$n_features > 0,
      has_samples = p$n_samples > 1,
      missingness_high = isTRUE(p$raw_missingness >= 0.3)
    ),
    profile = p
  )
}

mbx_resolve_grouping <- function(empt, group_var = NULL, ref_group = NULL, test_group = NULL) {
  cd <- as.data.frame(SummarizedExperiment::colData(empt))
  if (ncol(cd) == 0) stop("Sample metadata (colData) is empty; cannot run differential analysis.")

  if (is.null(group_var) || trimws(group_var) == "") {
    candidates <- names(cd)[vapply(cd, function(x) {
      ux <- unique(na.omit(as.character(x)))
      length(ux) >= 2 && length(ux) < nrow(cd)
    }, logical(1))]
    if (!length(candidates)) stop("No valid grouping variable found in metadata.")
    group_var <- candidates[1]
  }
  if (!group_var %in% names(cd)) stop(sprintf("Grouping variable `%s` not found in metadata.", group_var))

  groups <- unique(na.omit(as.character(cd[[group_var]])))
  if (length(groups) < 2) stop(sprintf("Grouping variable `%s` must contain at least 2 groups.", group_var))

  if (is.null(ref_group) || trimws(ref_group) == "") ref_group <- groups[1]
  if (is.null(test_group) || trimws(test_group) == "") {
    test_group <- groups[if (length(groups) >= 2) 2 else 1]
  }
  if (!ref_group %in% groups) stop(sprintf("Reference group `%s` not found in `%s`.", ref_group, group_var))
  if (!test_group %in% groups) stop(sprintf("Test group `%s` not found in `%s`.", test_group, group_var))
  if (identical(ref_group, test_group)) stop("`ref_group` and `test_group` must be different.")

  list(group_var = group_var, ref_group = ref_group, test_group = test_group, groups = groups)
}

mbx_preprocess <- function(session_id, experiment, max_na = NULL, impute_method = NULL, normalize_method = NULL) {
  session_id <- mbx_require_string(session_id, "session_id")
  experiment <- mbx_require_string(experiment, "experiment")
  empt <- load_empt(session_id, experiment)

  raw_missingness <- mbx_detect_missingness(empt)
  if (is.null(max_na)) {
    max_na <- if (raw_missingness >= 0.3) 0.4 else 0.2
  }
  max_na <- mbx_require_numeric(max_na, "max_na", 0, 1)

  if (is.null(impute_method) || trimws(impute_method) == "") {
    impute_method <- mbx_default_impute(raw_missingness)
  }
  if (is.null(normalize_method) || trimws(normalize_method) == "") {
    normalize_method <- mbx_default_normalize(empt)
  }

  ad <- SummarizedExperiment::assays(empt)[[1]]
  keep <- apply(ad, 1, function(x) sum(is.na(x)) / length(x) <= max_na)
  empt <- empt[keep, ]

  empt <- empt |> EasyMultiProfiler::EMP_impute(method = impute_method)
  empt <- empt |> EasyMultiProfiler::EMP_decostand(method = normalize_method)

  mae <- load_mae(session_id)
  mae[[experiment]] <- empt
  save_mae(session_id, mae)
  save_empt(session_id, experiment, empt)

  list(
    success = TRUE,
    max_na = max_na,
    impute_method = impute_method,
    normalize_method = normalize_method,
    raw_missingness = raw_missingness,
    kept_features = nrow(SummarizedExperiment::assays(empt)[[1]])
  )
}

mbx_run_differential <- function(session_id, experiment, method = NULL, group_var = NULL,
                                 ref_group = NULL, test_group = NULL,
                                 filter_low = TRUE, subset_two_groups = TRUE,
                                 cores = "auto", on_progress = NULL) {
  session_id <- mbx_require_string(session_id, "session_id")
  experiment <- mbx_require_string(experiment, "experiment")
  empt <- load_empt(session_id, experiment)
  if (exists("apply_merged_coldata", mode = "function", inherits = TRUE)) {
    empt <- apply_merged_coldata(session_id, empt)
  }

  default_norm <- mbx_default_normalize(empt)
  if (is.null(method) || trimws(method) == "") {
    method <- mbx_default_diff_method(default_norm)
  }

  g <- mbx_resolve_grouping(empt, group_var, ref_group, test_group)

  result <- tryCatch({
    tryCatch(
      run_diff(session_id, experiment, method, g$group_var, g$ref_group, g$test_group,
               filter_low = filter_low, subset_two_groups = subset_two_groups,
               cores = cores, on_progress = on_progress),
      error = function(e) {
        if (!identical(tolower(method), "limma")) {
          return(run_diff(session_id, experiment, "limma", g$group_var, g$ref_group, g$test_group,
                          filter_low = filter_low, subset_two_groups = subset_two_groups,
                          cores = cores, on_progress = on_progress))
        }
        stop(e)
      }
    )
  }, error = function(e) {
    msg <- conditionMessage(e)
    if (grepl("estimate_group|\\.formula", msg)) {
      stop("Differential analysis needs a valid grouping model. Please ensure metadata contains a categorical group column and choose group/ref/test accordingly.")
    }
    stop(e)
  })
  result_df <- tryCatch(as.data.frame(result), error = function(e) data.frame())

  list(
    success = TRUE,
    method = method,
    group_var = g$group_var,
    ref_group = g$ref_group,
    test_group = g$test_group,
    n_rows = nrow(result_df),
    columns = names(result_df),
    data = jsonlite::toJSON(result_df, na = "null", auto_unbox = TRUE)
  )
}

mbx_volcano_plot <- function(session_id, experiment, fc_cutoff = 1, p_cutoff = 0.05,
                             color_panel = NULL, custom_colors = NULL) {
  session_id <- mbx_require_string(session_id, "session_id")
  experiment <- mbx_require_string(experiment, "experiment")
  fc_cutoff <- mbx_require_numeric(fc_cutoff, "fc_cutoff", 0, Inf)
  p_cutoff <- mbx_require_numeric(p_cutoff, "p_cutoff", 0, 1)

  out <- make_volcano(session_id, experiment,
                      fc_cutoff = fc_cutoff, p_cutoff = p_cutoff,
                      color_panel = color_panel,
                      custom_colors = custom_colors)
  c(list(success = TRUE, fc_cutoff = fc_cutoff, p_cutoff = p_cutoff),
    if (is.list(out)) out else list(plot = out))
}

mbx_export_diff_csv <- function(session_id, experiment) {
  session_id <- mbx_require_string(session_id, "session_id")
  experiment <- mbx_require_string(experiment, "experiment")
  empt <- load_empt(session_id, experiment)
  result <- EasyMultiProfiler::EMP_result(empt, info = "diff_analysis_result")
  if (is.null(result) || nrow(as.data.frame(result)) == 0) {
    stop("No metabolomics differential result found. Run metabolomics differential analysis first.")
  }
  as.data.frame(result)
}
