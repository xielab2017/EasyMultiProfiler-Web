# Transcriptomics workflow helpers.

tx_stop_if_missing <- function(session_id, experiment) {
  if (is.null(session_id) || length(session_id) != 1 || !is.character(session_id) || !nzchar(session_id)) {
    stop("session_id is required.")
  }
  if (is.null(experiment) || length(experiment) != 1 || !is.character(experiment) || !nzchar(experiment)) {
    stop("experiment is required.")
  }
  load_empt(session_id, experiment)
}

tx_safe_top_n <- function(top_n, default = 50L) {
  value <- suppressWarnings(as.integer(top_n))
  if (is.na(value) || value < 5L) return(default)
  min(value, 500L)
}

tx_profile <- function(session_id, experiment, assay_hint = "counts") {
  empt <- tx_stop_if_missing(session_id, experiment)
  ad <- SummarizedExperiment::assays(empt)[[1]]
  feat <- rownames(ad)
  if (is.null(feat)) feat <- character()
  list(
    assay_hint = assay_hint %||% "counts",
    n_features = nrow(ad),
    n_samples = ncol(ad),
    feature_examples = as.character(head(feat, 10))
  )
}

tx_validate <- function(session_id, experiment) {
  empt <- tx_stop_if_missing(session_id, experiment)
  cd_df <- as.data.frame(SummarizedExperiment::colData(empt))
  group_candidates <- names(cd_df)[vapply(cd_df, function(x) {
    ux <- unique(na.omit(as.character(x)))
    length(ux) > 1 && length(ux) < nrow(cd_df)
  }, logical(1))]
  list(
    success = TRUE,
    checks = list(
      has_assay = nrow(SummarizedExperiment::assays(empt)[[1]]) > 0 && ncol(SummarizedExperiment::assays(empt)[[1]]) > 0,
      has_metadata = ncol(cd_df) > 0,
      has_group_candidates = length(group_candidates) > 0
    ),
    group_candidates = group_candidates
  )
}

tx_preprocess <- function(session_id, experiment, method = "deseq2") {
  profile <- tx_profile(session_id, experiment, assay_hint = "counts")
  method_use <- tolower(trimws(as.character(method %||% "deseq2")[1]))
  if (!method_use %in% c("deseq2", "tmm", "log2")) {
    stop("Unsupported transcriptomics preprocessing method.")
  }
  list(
    success = TRUE,
    method = method_use,
    applied_by = if (method_use %in% c("deseq2", "tmm")) "differential_model" else "workflow",
    counts_preserved = TRUE,
    profile = profile
  )
}

tx_run_differential <- function(session_id, experiment, method = "DESeq2",
                                group_var = NULL, ref_group = NULL, test_group = NULL,
                                filter_low = TRUE, subset_two_groups = TRUE,
                                cores = "auto", on_progress = NULL) {
  tx_stop_if_missing(session_id, experiment)
  method_use <- if (is.null(method) || !nzchar(method)) "DESeq2" else method
  tryCatch({
    tryCatch(
      run_diff(session_id, experiment, method_use, group_var, ref_group, test_group,
               filter_low = filter_low, subset_two_groups = subset_two_groups,
               cores = cores, on_progress = on_progress),
      error = function(e) {
        if (!identical(tolower(method_use), "limma")) {
          return(run_diff(session_id, experiment, "limma", group_var, ref_group, test_group,
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
}

tx_run_gsea <- function(session_id, experiment, database = "KEGG", organism = "hsa") {
  tx_stop_if_missing(session_id, experiment)
  db_use <- toupper(trimws(as.character(database %||% "KEGG")[1]))
  org_use <- normalize_species(organism, default = "hsa")

  if (!requireNamespace("clusterProfiler", quietly = TRUE)) {
    stop("Package 'clusterProfiler' is required for GSEA.")
  }
  raw_cache <- ensure_diff_raw(session_id, experiment)
  raw <- if (is.list(raw_cache) && !is.null(raw_cache$data)) raw_cache$data else raw_cache
  raw <- tryCatch(as.data.frame(raw, stringsAsFactors = FALSE), error = function(e) NULL)
  if (is.null(raw) || !nrow(raw)) {
    stop("No differential table found for GSEA. Run differential analysis first.")
  }

  fcol <- intersect(c("avg_log2FC", "log2FoldChange", "logFC", "effect"), names(raw))
  gcol <- intersect(c("symbol", "gene", "SYMBOL", "feature", "id"), names(raw))
  if (!length(fcol) || !length(gcol)) {
    stop("GSEA requires gene symbol/id and log fold-change columns in differential results.")
  }
  rank_df <- data.frame(
    gene = as.character(raw[[gcol[1]]]),
    stat = suppressWarnings(as.numeric(raw[[fcol[1]]])),
    stringsAsFactors = FALSE
  )
  rank_df <- rank_df[is.finite(rank_df$stat) & nzchar(rank_df$gene), , drop = FALSE]
  if (!nrow(rank_df)) stop("No finite ranking scores found for GSEA.")

  orgdb <- .enrich_orgdb(org_use)
  keytype <- .enrich_keytype(org_use)
  if (is.na(orgdb) || !requireNamespace(orgdb, quietly = TRUE)) {
    stop(sprintf("OrgDb package for '%s' is missing (%s).", org_use, orgdb))
  }

  mapped <- tryCatch(
    clusterProfiler::bitr(
      unique(rank_df$gene),
      fromType = "SYMBOL",
      toType = keytype,
      OrgDb = get(orgdb, envir = asNamespace(orgdb))
    ),
    error = function(e) data.frame()
  )
  if (!nrow(mapped)) stop("Failed to map symbols for GSEA.")
  colnames(mapped)[colnames(mapped) == keytype] <- "ID"
  rank_df <- merge(rank_df, mapped[, c("SYMBOL", "ID"), drop = FALSE],
                   by.x = "gene", by.y = "SYMBOL", all.x = FALSE, all.y = FALSE)
  rank_df <- rank_df[!duplicated(rank_df$ID), , drop = FALSE]
  gene_list <- rank_df$stat
  names(gene_list) <- rank_df$ID
  gene_list <- sort(gene_list, decreasing = TRUE)
  if (length(gene_list) < 20) stop("Too few ranked genes for GSEA (need >= 20).")

  res <- if (db_use %in% c("GO", "GO_BP", "GO_CC", "GO_MF")) {
    ont <- switch(db_use, GO_CC = "CC", GO_MF = "MF", GO_BP = "BP", "BP")
    clusterProfiler::gseGO(
      geneList = gene_list,
      OrgDb = get(orgdb, envir = asNamespace(orgdb)),
      keyType = keytype,
      ont = ont,
      pAdjustMethod = "BH",
      verbose = FALSE
    )
  } else if (db_use == "REACTOME") {
    if (!requireNamespace("ReactomePA", quietly = TRUE)) {
      stop("ReactomePA is required for Reactome GSEA.")
    }
    ReactomePA::gsePathway(
      geneList = gene_list,
      organism = switch(org_use, hsa = "human", mmu = "mouse", rno = "rat", "human"),
      pAdjustMethod = "BH",
      verbose = FALSE
    )
  } else {
    clusterProfiler::gseKEGG(
      geneList = gene_list,
      organism = org_use,
      pAdjustMethod = "BH",
      verbose = FALSE
    )
  }

  df <- as.data.frame(res)
  if (!nrow(df)) return(data.frame())
  utils::head(df, 200)
}

tx_run_wgcna <- function(session_id, experiment, method = "spearman", cutoff = 0.7) {
  tx_stop_if_missing(session_id, experiment)
  method_use <- if (is.null(method) || !nzchar(method)) "spearman" else method
  cutoff_use <- suppressWarnings(as.numeric(cutoff))
  if (is.na(cutoff_use) || cutoff_use <= 0 || cutoff_use > 1) cutoff_use <- 0.7
  run_correlation(session_id, experiment, use = method_use)
}

tx_make_heatmap <- function(session_id, experiment, group = NULL, top_n = 50L,
                             features = NULL, cluster_rows = TRUE,
                             cluster_cols = TRUE, show_gene_names = NULL,
                             font_size = 11, color_panel = NULL, custom_colors = NULL) {
  tx_stop_if_missing(session_id, experiment)
  make_heatmap(session_id, experiment, group = group,
                top_n = tx_safe_top_n(top_n, 50L),
                features = features,
                cluster_rows = cluster_rows,
                cluster_cols = cluster_cols,
                show_gene_names = show_gene_names,
                font_size = font_size,
                color_panel = color_panel,
                custom_colors = custom_colors)
}

tx_make_volcano <- function(session_id, experiment, fc_cutoff = 1.0, p_cutoff = 0.05,
                            color_panel = NULL, custom_colors = NULL) {
  tx_stop_if_missing(session_id, experiment)
  fc <- suppressWarnings(as.numeric(fc_cutoff))
  pv <- suppressWarnings(as.numeric(p_cutoff))
  if (is.na(fc) || fc < 0) fc <- 1.0
  if (is.na(pv) || pv <= 0 || pv >= 1) pv <- 0.05
  make_volcano(session_id, experiment, fc_cutoff = fc, p_cutoff = pv,
               color_panel = color_panel, custom_colors = custom_colors)
}
