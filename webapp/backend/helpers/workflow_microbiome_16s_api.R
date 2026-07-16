# 16S workflow orchestrators for plumber routes.

m16s_profile <- function(session_id, experiment, tax_sep = ";") {
  m16s_validate_session_experiment(session_id, experiment)
  empt <- load_empt(session_id, experiment)
  ad <- SummarizedExperiment::assays(empt)[[1]]
  taxa_parts <- m16s_taxonomy_parts(empt, tax_sep = tax_sep)
  if (!length(taxa_parts)) stop("No taxonomy feature names were found.")

  tax_depth <- vapply(taxa_parts, function(parts) {
    max(which(!is.na(parts) & nzchar(parts)), 0L)
  }, integer(1))
  top_levels <- stats::setNames(rep(0L, length(.m16s_tax_levels)), .m16s_tax_levels)
  for (i in seq_along(.m16s_tax_levels)) {
    top_levels[[i]] <- sum(tax_depth >= i, na.rm = TRUE)
  }

  list(
    experiment = experiment,
    n_samples = ncol(ad),
    n_features = nrow(ad),
    taxonomy_separator = tax_sep,
    max_taxonomy_depth = max(tax_depth, na.rm = TRUE),
    observed_levels = top_levels
  )
}

m16s_validate <- function(session_id, experiment, tax_sep = ";") {
  p <- m16s_profile(session_id, experiment, tax_sep = tax_sep)
  list(
    success = TRUE,
    checks = list(
      has_features = p$n_features > 0,
      has_samples = p$n_samples > 1,
      taxonomy_depth_ok = isTRUE(p$max_taxonomy_depth >= 2)
    ),
    profile = p
  )
}

m16s_prepare_taxonomy_step <- function(session_id, experiment, collapse_level = "Genus",
                                       min_total_abundance = 0, drop_unassigned = TRUE,
                                       keep_top_n = 0L, tax_sep = ";",
                                       normalize_method = NULL) {
  m16s_validate_session_experiment(session_id, experiment)
  empt <- load_empt(session_id, experiment)
  before_n <- nrow(SummarizedExperiment::assays(empt)[[1]])

  prepared <- m16s_prepare_taxonomy(
    empt = empt,
    tax_sep = tax_sep,
    collapse_level = collapse_level,
    min_total_abundance = min_total_abundance,
    drop_unassigned = drop_unassigned,
    keep_top_n = keep_top_n
  )
  if (!is.null(normalize_method) && nzchar(as.character(normalize_method))) {
    nm <- tolower(trimws(as.character(normalize_method)))
    if (!identical(nm, "none")) {
      prepared <- prepared |> EasyMultiProfiler::EMP_decostand(method = nm)
    }
  }

  mae <- load_mae(session_id)
  mae[[experiment]] <- prepared
  save_mae(session_id, mae)
  # Re-promote through MAE -> EMPT so the object stored on disk has the
  # `experiment` slot + history that EMP_alpha_analysis etc. expect.
  promoted <- tryCatch(.promote_to_empt(mae, experiment),
                       error = function(e) prepared)
  save_empt(session_id, experiment, promoted)
  snap_id <- save_prepare_snapshot(session_id, experiment, promoted, label = paste0("m16s_taxonomy_", collapse_level))

  after_n <- nrow(SummarizedExperiment::assays(prepared)[[1]])
  list(
    success = TRUE,
    collapse_level = collapse_level,
    n_features_before = before_n,
    n_features_after = after_n,
    removed = before_n - after_n,
    normalize_method = normalize_method %||% "none",
    snapshot_id = snap_id,
    preview_data = emp_prepare_preview_rows(promoted)
  )
}

m16s_visualize_sankey <- function(session_id, experiment, from_level = "Phylum", to_level = "Genus",
                                  top_n = 25L, width = 10, height = 6, tax_sep = ";",
                                  color_panel = NULL, custom_colors = NULL) {
  m16s_validate_session_experiment(session_id, experiment)
  empt <- load_empt(session_id, experiment)
  m16s_make_sankey(
    empt = empt,
    tax_sep = tax_sep,
    from_level = from_level,
    to_level = to_level,
    top_n = top_n,
    width = width,
    height = height,
    color_panel = color_panel,
    custom_colors = custom_colors,
    session_id = session_id,
    experiment = experiment
  )
}

m16s_visualize_network <- function(session_id, experiment, method = "spearman", cutoff = 0.6,
                                   top_n = 40L, width = 8, height = 8) {
  m16s_validate_session_experiment(session_id, experiment)
  empt <- load_empt(session_id, experiment)
  m16s_make_network(
    empt = empt,
    method = method,
    cutoff = cutoff,
    top_n = top_n,
    width = width,
    height = height,
    session_id = session_id,
    experiment = experiment
  )
}
