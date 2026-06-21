# Metagenomics workflow helpers (functional matrix oriented).

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

mgx_require_string <- function(x, field) {
  if (is.null(x) || !is.character(x) || length(x) != 1 || trimws(x) == "") {
    stop(sprintf("`%s` is required and must be a non-empty string.", field))
  }
  trimws(x)
}

mgx_require_numeric <- function(x, field, min_value = -Inf, max_value = Inf) {
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

mgx_stop_if_missing <- function(session_id, experiment) {
  session_id <- mgx_require_string(session_id, "session_id")
  experiment <- mgx_require_string(experiment, "experiment")
  load_empt(session_id, experiment)
}

mgx_infer_id_type <- function(features) {
  if (length(features) == 0) return("unknown")
  feat <- as.character(features)
  ko_hits <- sum(grepl("^K\\d{5}$", feat, perl = TRUE))
  ec_hits <- sum(grepl("^EC[: ]?\\d+\\.\\d+\\.\\d+\\.\\d+$|^\\d+\\.\\d+\\.\\d+\\.\\d+$", feat, perl = TRUE))
  path_hits <- sum(grepl("^(ko|map)\\d{5}$|pathway|module", feat, ignore.case = TRUE, perl = TRUE))

  scores <- c(ko = ko_hits, ec = ec_hits, pathway = path_hits)
  best <- names(scores)[which.max(scores)]
  if (max(scores) == 0) return("unknown")
  best
}

mgx_safe_top_n <- function(top_n, default = 50L) {
  value <- suppressWarnings(as.integer(top_n))
  if (is.na(value) || value < 5L) return(default)
  min(value, 500L)
}

mgx_profile <- function(session_id, experiment, declared_id_type = "auto") {
  empt <- mgx_stop_if_missing(session_id, experiment)
  ad <- SummarizedExperiment::assays(empt)[[1]]
  features <- rownames(ad)
  if (is.null(features)) features <- character()

  inferred <- mgx_infer_id_type(features)
  declared <- if (is.null(declared_id_type) || !nzchar(declared_id_type)) "auto" else tolower(declared_id_type)
  effective <- if (declared == "auto") inferred else declared

  list(
    id_type_declared = declared,
    id_type_inferred = inferred,
    id_type_effective = effective,
    n_features = nrow(ad),
    n_samples = ncol(ad),
    examples = as.character(head(features, 10))
  )
}

mgx_validate <- function(session_id, experiment, declared_id_type = "auto") {
  p <- mgx_profile(session_id, experiment, declared_id_type)
  list(
    success = TRUE,
    checks = list(
      has_features = p$n_features > 0,
      has_samples = p$n_samples > 1,
      inferred_id_type = p$id_type_inferred
    ),
    profile = p
  )
}

mgx_run_differential <- function(session_id, experiment, id_type = "auto",
                                 method = "limma", group_var = NULL,
                                 ref_group = NULL, test_group = NULL,
                                 filter_low = TRUE, subset_two_groups = TRUE,
                                 cores = "auto", on_progress = NULL) {
  mgx_profile(session_id, experiment, id_type)
  method_use <- if (is.null(method) || !nzchar(method)) "limma" else method
  run_diff(session_id, experiment, method_use, group_var, ref_group, test_group,
           filter_low = filter_low, subset_two_groups = subset_two_groups,
           cores = cores, on_progress = on_progress)
}

mgx_preprocess <- function(session_id, experiment, max_na = 0.2, normalize_method = "rclr") {
  session_id <- mgx_require_string(session_id, "session_id")
  experiment <- mgx_require_string(experiment, "experiment")
  max_na <- mgx_require_numeric(max_na, "max_na", 0, 1)
  normalize_method <- if (is.null(normalize_method) || trimws(normalize_method) == "") "rclr" else trimws(normalize_method)

  empt <- load_empt(session_id, experiment)
  ad <- SummarizedExperiment::assays(empt)[[1]]
  keep <- apply(ad, 1, function(x) sum(is.na(x)) / length(x) <= max_na)
  empt <- empt[keep, ]
  empt <- empt |> EasyMultiProfiler::EMP_decostand(method = normalize_method)

  mae <- load_mae(session_id)
  mae[[experiment]] <- empt
  save_mae(session_id, mae)
  save_empt(session_id, experiment, empt)

  list(
    success = TRUE,
    max_na = max_na,
    normalize_method = normalize_method,
    kept_features = nrow(SummarizedExperiment::assays(empt)[[1]])
  )
}

mgx_run_enrichment <- function(session_id, experiment, id_type = "auto",
                               database = NULL, organism = "hsa") {
  profile <- mgx_profile(session_id, experiment, id_type)
  db_default <- switch(
    profile$id_type_effective,
    ko = "KEGG",
    ec = "KEGG",
    pathway = "KEGG",
    "KEGG"
  )
  db_use <- if (is.null(database) || !nzchar(database)) db_default else database
  run_enrichment(session_id, experiment, database = db_use, organism = normalize_species(organism, default = "hsa"))
}

mgx_make_heatmap <- function(session_id, experiment, group = NULL, top_n = 50L,
                              features = NULL, cluster_rows = TRUE,
                              cluster_cols = TRUE, show_gene_names = NULL,
                              font_size = 11, color_panel = NULL, custom_colors = NULL) {
  mgx_stop_if_missing(session_id, experiment)
  make_heatmap(session_id, experiment, group = group,
                top_n = mgx_safe_top_n(top_n, 50L),
                features = features,
                cluster_rows = cluster_rows,
                cluster_cols = cluster_cols,
                show_gene_names = show_gene_names,
                font_size = font_size,
                color_panel = color_panel,
                custom_colors = custom_colors)
}

mgx_make_volcano <- function(session_id, experiment, fc_cutoff = 1.0, p_cutoff = 0.05,
                             color_panel = NULL, custom_colors = NULL) {
  mgx_stop_if_missing(session_id, experiment)
  fc <- suppressWarnings(as.numeric(fc_cutoff))
  pv <- suppressWarnings(as.numeric(p_cutoff))
  if (is.na(fc) || fc < 0) fc <- 1.0
  if (is.na(pv) || pv <= 0 || pv >= 1) pv <- 0.05
  make_volcano(session_id, experiment, fc_cutoff = fc, p_cutoff = pv,
               color_panel = color_panel, custom_colors = custom_colors)
}

mgx_export_diff_csv <- function(session_id, experiment) {
  session_id <- mgx_require_string(session_id, "session_id")
  experiment <- mgx_require_string(experiment, "experiment")
  empt <- load_empt(session_id, experiment)
  result <- EasyMultiProfiler::EMP_result(empt, info = "diff_analysis_result")
  if (is.null(result) || nrow(as.data.frame(result)) == 0) {
    stop("No metagenomics differential result found. Run metagenomics differential analysis first.")
  }
  as.data.frame(result)
}
