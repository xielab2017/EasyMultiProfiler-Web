# Analysis helpers - wraps EasyMultiProfiler analysis functions

get_empt <- function(session_id, experiment) {
  load_empt(session_id, experiment)
}

# Return a *pristine* EMPT reconstructed from the MAE.  Use this when the
# analysis must not be contaminated by state attached by an earlier step
# (e.g. DESeq2 after PCA saw the EMPT as class "EMP_dimension_analysis",
# which broke EMP's two-group check).  This intentionally does NOT cache –
# callers that want to persist side-effects should still go through
# save_empt() afterwards.
get_empt_fresh <- function(session_id, experiment) {
  mae <- load_mae(session_id)
  .promote_to_empt(mae, experiment)
}

normalize_species <- function(organism, default = "hsa") {
  if (is.null(organism) || length(organism) == 0) return(default)
  org_raw <- tolower(trimws(as.character(organism[[1]])))
  if (!nzchar(org_raw)) return(default)
  org_map <- c(
    "hsa" = "hsa", "human" = "hsa", "hs" = "hsa",
    "mmu" = "mmu", "mouse" = "mmu", "mus_musculus" = "mmu",
    "rno" = "rno", "rat" = "rno", "rattus_norvegicus" = "rno",
    "all" = "hsa"
  )
  org_use <- unname(org_map[org_raw])
  if (is.na(org_use) || !nzchar(org_use)) default else org_use
}

run_alpha <- function(session_id, experiment, method = "shannon", source = "current") {
  source_key <- tolower(trimws(as.character(source %||% "current")))
  empt <- if (identical(source_key, "raw")) {
    load_raw_empt(session_id, experiment) %||% get_empt(session_id, experiment)
  } else {
    get_empt(session_id, experiment)
  }
  # EMP_alpha_analysis computes all supported alpha metrics in one pass.
  empt <- empt |> EasyMultiProfiler::EMP_alpha_analysis()
  if (!identical(source_key, "raw")) {
    save_empt(session_id, experiment, empt)
  }

  result <- tryCatch(
    EasyMultiProfiler::EMP_result(empt, info = "EMP_alpha_analysis"),
    error = function(e) NULL
  )
  if (is.null(result)) {
    result <- tryCatch(
      as.data.frame(SummarizedExperiment::colData(empt)),
      error = function(e) data.frame()
    )
  }
  # Ensure all common alpha metrics are available for downstream tables/plots.
  result <- as.data.frame(result, stringsAsFactors = FALSE)
  ad <- SummarizedExperiment::assays(empt)[[1]]
  X <- t(as.matrix(ad))
  X[!is.finite(X)] <- 0
  if (!nrow(result) && nrow(X)) result <- data.frame(primary = rownames(X), stringsAsFactors = FALSE)
  if (!"primary" %in% names(result)) result$primary <- rownames(result)
  rownames(result) <- as.character(result$primary)
  .need_fill <- function(df, pat) {
    hits <- grep(pat, names(df), ignore.case = TRUE, value = TRUE)
    if (!length(hits)) return(TRUE)
    vals <- suppressWarnings(as.numeric(df[[hits[1]]]))
    sum(is.finite(vals)) == 0
  }
  if (nrow(X) && requireNamespace("vegan", quietly = TRUE)) {
    .est_pick <- function(est, row_key, sample_ids) {
      out <- rep(NA_real_, length(sample_ids))
      if (is.null(est) || !is.matrix(est) || !(row_key %in% rownames(est))) return(out)
      cn <- colnames(est)
      if (is.null(cn) || !length(cn)) return(out)
      idx <- match(sample_ids, cn)
      ok <- which(!is.na(idx))
      if (length(ok)) out[ok] <- suppressWarnings(as.numeric(est[row_key, idx[ok], drop = TRUE]))
      out
    }
    if (!any(grepl("shannon", names(result), ignore.case = TRUE))) {
      result$shannon <- vegan::diversity(X, index = "shannon")
    }
    if (!any(grepl("^simpson", names(result), ignore.case = TRUE))) {
      result$simpson <- vegan::diversity(X, index = "simpson")
    }
    if (!any(grepl("invsimpson", names(result), ignore.case = TRUE))) {
      result$invsimpson <- vegan::diversity(X, index = "invsimpson")
    }
    # estimateR requires integer-like counts; after normalization the matrix can
    # be continuous proportions/log-values. In that case we skip count-only
    # richness estimators and keep robust metrics (Shannon/Simpson/InvSimpson).
    is_count_like <- all(X >= 0, na.rm = TRUE) &&
      max(abs(X - round(X)), na.rm = TRUE) < 1e-8
    est <- if (is_count_like) suppressWarnings(vegan::estimateR(t(X))) else NULL
    sid <- rownames(result)
    if (.need_fill(result, "chao1")) {
      result$chao1 <- .est_pick(est, "S.chao1", sid)
    }
    if (.need_fill(result, "^ace$")) {
      result$ACE <- .est_pick(est, "S.ACE", sid)
    }
    if (!any(grepl("observed|observerd", names(result), ignore.case = TRUE))) {
      result$observed <- if (is_count_like) .est_pick(est, "S.obs", sid) else rowSums(X > 0, na.rm = TRUE)
    }
    if (!any(grepl("pielou", names(result), ignore.case = TRUE))) {
      sh <- if ("shannon" %in% names(result)) result$shannon else suppressWarnings(vegan::diversity(X, index = "shannon"))
      sobs <- if ("observed" %in% names(result)) {
        result$observed
      } else if (is_count_like) {
        .est_pick(est, "S.obs", sid)
      } else {
        rowSums(X > 0, na.rm = TRUE)
      }
      result$pielou <- sh / log(pmax(2, sobs))
    }
  }
  # Always expose the same alpha columns to the frontend, even when some
  # metrics are unavailable in the current R environment.
  required_cols <- c("shannon", "simpson", "invsimpson", "chao1", "ACE", "observed", "pielou")
  for (nm in required_cols) {
    if (!nm %in% names(result)) result[[nm]] <- NA_real_
  }
  result
}

.diff_detect_cores <- function(requested = NULL) {
  # Parallelise wilcox/t/etc. using all-but-one physical core by default.
  phys <- tryCatch(parallel::detectCores(logical = FALSE), error = function(e) NA_integer_)
  if (is.na(phys) || phys < 1) phys <- tryCatch(parallel::detectCores(), error = function(e) 2L)
  cap <- max(1L, min(8L, phys - 1L))
  if (is.null(requested) || identical(requested, "auto")) return(cap)
  n <- suppressWarnings(as.integer(requested))
  if (is.na(n) || n < 1) return(cap)
  min(n, cap)
}

# Sanitise column-data groups for tidybulk back-ends that require
# syntactically valid R names (e.g. limma_voom, edgeR_quasi_likelihood
# fail when a level contains '+', '-', ' ').
.diff_sanitize_groups <- function(empt, group_var, ref_group, test_group) {
  if (is.null(group_var) || !nzchar(group_var)) return(list(empt = empt, group_var = group_var,
                                                             ref = ref_group, test = test_group, map = NULL))
  cd <- SummarizedExperiment::colData(empt)
  vals <- as.character(cd[[group_var]])
  vals_valid <- make.names(vals, unique = FALSE)
  if (identical(vals, vals_valid)) {
    return(list(empt = empt, group_var = group_var, ref = ref_group, test = test_group, map = NULL))
  }
  map <- stats::setNames(vals_valid, vals)
  map <- map[!duplicated(names(map))]
  new_col <- paste0(group_var, "_safe")
  cd[[new_col]] <- vals_valid
  SummarizedExperiment::colData(empt) <- cd
  list(
    empt      = empt,
    group_var = new_col,
    ref       = unname(map[ref_group]),
    test      = unname(map[test_group]),
    map       = map
  )
}

# S4Vectors owns DataFrame; newer SummarizedExperiment no longer re-exports it.
.diff_as_coldata <- function(cd) {
  if (requireNamespace("S4Vectors", quietly = TRUE)) {
    return(S4Vectors::DataFrame(cd, check.names = FALSE))
  }
  as.data.frame(cd, stringsAsFactors = FALSE)
}

.diff_filter_counts <- function(empt, group_col, filter_low = TRUE) {
  ad <- SummarizedExperiment::assays(empt)[[1]]
  if (is.null(ad)) stop("Assay matrix is missing.")
  cd <- as.data.frame(SummarizedExperiment::colData(empt))
  if (!group_col %in% names(cd)) stop("Grouping variable not found in sample metadata.")
  counts <- round(as.matrix(ad))
  storage.mode(counts) <- "integer"
  if (isTRUE(filter_low)) {
    min_present <- max(3L, ceiling(ncol(counts) * 0.1))
    keep_f <- rowSums(!is.na(counts) & counts > 0) >= min_present
    if (sum(keep_f) >= 50) counts <- counts[keep_f, , drop = FALSE]
  }
  list(counts = counts, coldata = cd)
}

.diff_prepare_group_column <- function(empt, group_var) {
  cd <- as.data.frame(SummarizedExperiment::colData(empt))
  if (!group_var %in% names(cd)) stop("Grouping variable not found in sample metadata.")
  raw <- as.character(cd[[group_var]])
  if (any(is.na(raw) | !nzchar(raw))) {
    stop("Grouping variable contains missing or empty labels.")
  }
  uniq <- sort(unique(raw))
  safe <- make.names(uniq, unique = TRUE)
  if (any(duplicated(safe))) safe <- paste0("G", seq_along(uniq))
  mapped <- stats::setNames(safe, uniq)[raw]
  col_use <- paste0(group_var, "__emp")
  cd[[col_use]] <- factor(mapped, levels = safe)
  SummarizedExperiment::colData(empt) <- .diff_as_coldata(cd)
  list(
    empt = empt,
    group_col = col_use,
    group_var_orig = group_var,
    n_groups = length(uniq),
    label_display = paste(uniq, collapse = " | "),
    safe_to_orig = stats::setNames(uniq, safe)
  )
}

.diff_format_native_result <- function(feature, group_var, method, vs, pvalue, log2fc = NA_real_,
                                        sign_group = NA_character_, padj = NULL,
                                        comparison_mode = NA_character_, n_groups = NA_integer_) {
  pvalue <- suppressWarnings(as.numeric(pvalue))
  log2fc <- suppressWarnings(as.numeric(log2fc))
  n <- max(length(feature), length(pvalue), length(log2fc), 1L)
  if (is.null(padj)) {
    padj <- stats::p.adjust(pvalue, method = "fdr")
  } else {
    padj <- suppressWarnings(as.numeric(padj))
    miss <- is.na(padj) & is.finite(pvalue)
    if (any(miss)) padj[miss] <- stats::p.adjust(pvalue[miss], method = "fdr")
  }
  fc <- ifelse(is.finite(log2fc), 2^log2fc, NA_real_)
  if (length(sign_group) == 1L && (is.na(sign_group) || !nzchar(sign_group))) {
    sign_group <- rep(NA_character_, n)
    up <- is.finite(log2fc) & log2fc >= 0
    down <- is.finite(log2fc) & log2fc < 0
    if (any(up)) sign_group[up] <- sub(" vs .*", "", vs)
    if (any(down)) sign_group[down] <- sub(".* vs ", "", vs)
  }
  data.frame(
    feature = feature,
    Estimate_group = group_var,
    pvalue = pvalue,
    fdr = padj,
    sign_group = sign_group,
    method = method,
    vs = vs,
    fold_change = fc,
    log2FC = log2fc,
    comparison_mode = comparison_mode,
    n_groups = n_groups,
    stringsAsFactors = FALSE
  )
}

.diff_native_deseq2_pairwise <- function(empt, group_var, ref_group, test_group, filter_low = TRUE) {
  if (!requireNamespace("DESeq2", quietly = TRUE)) stop("DESeq2 package is required.")
  prep_g <- .diff_prepare_group_column(empt, group_var)
  empt <- prep_g$empt
  prep <- .diff_filter_counts(empt, prep_g$group_col, filter_low = filter_low)
  orig_to_safe <- stats::setNames(names(prep_g$safe_to_orig), prep_g$safe_to_orig)
  ref_safe <- unname(orig_to_safe[ref_group])
  test_safe <- unname(orig_to_safe[test_group])
  if (length(ref_safe) != 1L || length(test_safe) != 1L ||
      any(is.na(c(ref_safe, test_safe)))) {
    stop("Reference or test group not found in sample metadata.")
  }
  sub_idx <- which(as.character(prep$coldata[[prep_g$group_col]]) %in% c(ref_safe, test_safe))
  if (length(sub_idx) < 2) stop("Not enough samples for DESeq2 pairwise comparison.")
  counts <- prep$counts[, sub_idx, drop = FALSE]
  coldat <- prep$coldata[sub_idx, , drop = FALSE]
  coldat[[prep_g$group_col]] <- factor(as.character(coldat[[prep_g$group_col]]),
                                       levels = c(ref_safe, test_safe))
  keep_r <- rowSums(counts > 0) >= max(3L, ceiling(ncol(counts) * 0.1))
  if (!any(keep_r)) stop("All features filtered out for DESeq2 run.")
  counts <- counts[keep_r, , drop = FALSE]
  dds <- DESeq2::DESeqDataSetFromMatrix(
    countData = counts, colData = coldat,
    design = stats::as.formula(paste0("~", prep_g$group_col))
  )
  dds <- DESeq2::DESeq(dds, parallel = FALSE, quiet = TRUE)
  res <- DESeq2::results(dds, contrast = c(prep_g$group_col, test_safe, ref_safe))
  vs <- paste0(test_group, " vs ", ref_group)
  .diff_format_native_result(
    feature = rownames(res),
    group_var = group_var,
    method = "DESeq2",
    vs = vs,
    pvalue = res$pvalue,
    log2fc = res$log2FoldChange,
    padj = res$padj,
    comparison_mode = "pairwise",
    n_groups = 2L
  )
}

.diff_native_deseq2_lrt <- function(empt, group_var, filter_low = TRUE) {
  if (!requireNamespace("DESeq2", quietly = TRUE)) stop("DESeq2 package is required.")
  prep_g <- .diff_prepare_group_column(empt, group_var)
  if (prep_g$n_groups < 3L) {
    stop("Multi-group LRT requires at least 3 groups. Use pairwise or all-pairwise mode for fewer groups.")
  }
  prep <- .diff_filter_counts(prep_g$empt, prep_g$group_col, filter_low = filter_low)
  counts <- prep$counts
  coldat <- prep$coldata
  keep_r <- rowSums(counts > 0) >= max(3L, ceiling(ncol(counts) * 0.1))
  if (!any(keep_r)) stop("All features filtered out for DESeq2 LRT.")
  counts <- counts[keep_r, , drop = FALSE]
  dds <- DESeq2::DESeqDataSetFromMatrix(
    countData = counts, colData = coldat,
    design = stats::as.formula(paste0("~", prep_g$group_col))
  )
  reduced_form <- stats::as.formula("~1")
  dds <- DESeq2::DESeq(
    dds, test = "LRT", reduced = reduced_form,
    parallel = FALSE, quiet = TRUE
  )
  res <- DESeq2::results(dds)
  .diff_format_native_result(
    feature = rownames(res),
    group_var = group_var,
    method = "DESeq2",
    vs = prep_g$label_display,
    pvalue = res$pvalue,
    log2fc = NA_real_,
    padj = res$padj,
    sign_group = "multi-group LRT",
    comparison_mode = "multi_lrt",
    n_groups = prep_g$n_groups
  )
}

.diff_native_edger_pairwise <- function(empt, group_var, ref_group, test_group, filter_low = TRUE) {
  if (!requireNamespace("edgeR", quietly = TRUE)) stop("edgeR package is required.")
  prep_g <- .diff_prepare_group_column(empt, group_var)
  prep <- .diff_filter_counts(prep_g$empt, prep_g$group_col, filter_low = filter_low)
  orig_to_safe <- stats::setNames(names(prep_g$safe_to_orig), prep_g$safe_to_orig)
  ref_safe <- unname(orig_to_safe[ref_group])
  test_safe <- unname(orig_to_safe[test_group])
  if (length(ref_safe) != 1L || length(test_safe) != 1L ||
      any(is.na(c(ref_safe, test_safe)))) {
    stop("Reference or test group not found in sample metadata.")
  }
  sub_idx <- which(as.character(prep$coldata[[prep_g$group_col]]) %in% c(ref_safe, test_safe))
  if (length(sub_idx) < 2) stop("Not enough samples for edgeR pairwise comparison.")
  counts <- prep$counts[, sub_idx, drop = FALSE]
  grp <- factor(as.character(prep$coldata[[prep_g$group_col]][sub_idx]), levels = c(ref_safe, test_safe))
  y <- edgeR::DGEList(counts = counts, group = grp)
  y <- edgeR::calcNormFactors(y)
  y <- edgeR::estimateDisp(y)
  if (is.na(y$common.dispersion)) {
    stop("Cannot estimate edgeR dispersion for this pair — need at least 2 replicates per group.")
  }
  et <- edgeR::exactTest(y, pair = c(2L, 1L))
  tt <- edgeR::topTags(et, n = Inf, sort.by = "none")$table
  vs <- paste0(test_group, " vs ", ref_group)
  .diff_format_native_result(
    feature = rownames(tt),
    group_var = group_var,
    method = "edgeR",
    vs = vs,
    pvalue = tt$PValue,
    log2fc = tt$logFC,
    padj = tt$FDR,
    comparison_mode = "pairwise",
    n_groups = 2L
  )
}

.diff_native_edger_lrt <- function(empt, group_var, filter_low = TRUE) {
  if (!requireNamespace("edgeR", quietly = TRUE)) stop("edgeR package is required.")
  prep_g <- .diff_prepare_group_column(empt, group_var)
  if (prep_g$n_groups < 3L) {
    stop("Multi-group LRT requires at least 3 groups. Use pairwise or all-pairwise mode for fewer groups.")
  }
  prep <- .diff_filter_counts(prep_g$empt, prep_g$group_col, filter_low = filter_low)
  grp <- prep$coldata[[prep_g$group_col]]
  y <- edgeR::DGEList(counts = prep$counts, group = grp)
  y <- edgeR::calcNormFactors(y)
  design <- stats::model.matrix(~ grp)
  y <- edgeR::estimateDisp(y, design)
  if (is.na(y$common.dispersion) || all(is.na(y$tagwise.dispersion))) {
    stop("Cannot estimate edgeR dispersion for multi-group LRT — need more replicates per group.")
  }
  fit <- edgeR::glmFit(y, design)
  coef_cols <- seq(2L, ncol(design))
  if (length(coef_cols) < 1L) {
    stop("Not enough group coefficients for edgeR multi-group LRT.")
  }
  lrt <- edgeR::glmLRT(fit, coef = coef_cols)
  tt <- edgeR::topTags(lrt, n = Inf, sort.by = "none")$table
  .diff_format_native_result(
    feature = rownames(tt),
    group_var = group_var,
    method = "edgeR",
    vs = prep_g$label_display,
    pvalue = tt$PValue,
    log2fc = NA_real_,
    padj = tt$FDR,
    sign_group = "multi-group LRT",
    comparison_mode = "multi_lrt",
    n_groups = prep_g$n_groups
  )
}

.diff_all_pairwise_native <- function(empt, group_var, method = "DESeq2", filter_low = TRUE,
                                      on_progress = NULL) {
  prep_g <- .diff_prepare_group_column(empt, group_var)
  groups_orig <- sort(unique(prep_g$safe_to_orig))
  if (length(groups_orig) < 2) stop("Need at least 2 groups for all-pairwise comparisons.")
  pairs <- utils::combn(groups_orig, 2, simplify = FALSE)
  chunks <- vector("list", length(pairs))
  for (i in seq_along(pairs)) {
    if (!is.null(on_progress) && is.function(on_progress)) {
      pct <- 20 + floor(70 * (i - 1) / max(1L, length(pairs)))
      tryCatch(on_progress(pct, paste0("Pair ", i, "/", length(pairs), ": ",
                                       pairs[[i]][2], " vs ", pairs[[i]][1])),
               error = function(e) NULL)
    }
    ref_g <- pairs[[i]][1]
    test_g <- pairs[[i]][2]
    chunks[[i]] <- if (identical(method, "edgeR")) {
      .diff_native_edger_pairwise(prep_g$empt, group_var, ref_g, test_g, filter_low)
    } else {
      .diff_native_deseq2_pairwise(prep_g$empt, group_var, ref_g, test_g, filter_low)
    }
    chunks[[i]]$comparison_mode <- "all_pairwise"
    chunks[[i]]$n_groups <- prep_g$n_groups
  }
  out <- do.call(rbind, chunks)
  rownames(out) <- NULL
  out
}

.diff_run_native_multi <- function(session_id, experiment, empt, group_var, method_raw,
                                   comparison_mode, filter_low, on_progress) {
  bump <- function(pct, msg = NULL) {
    if (!is.null(on_progress) && is.function(on_progress)) {
      tryCatch(on_progress(pct, msg), error = function(e) NULL)
    }
  }
  native_method <- if (tolower(method_raw) %in% c("edger")) "edgeR" else "DESeq2"
  already_filtered <- isTRUE(filter_low)
  fl <- if (already_filtered) FALSE else filter_low
  if (comparison_mode == "multi_lrt") {
    bump(12, paste0("Running ", native_method, " multi-group LRT (overall)"))
    lrt_df <- tryCatch(
      if (native_method == "edgeR") {
        .diff_native_edger_lrt(empt, group_var, filter_low = fl)
      } else {
        .diff_native_deseq2_lrt(empt, group_var, filter_low = fl)
      },
      error = function(e) {
        bump(16, paste0("LRT skipped: ", conditionMessage(e)))
        NULL
      }
    )
    bump(22, paste0("Running ", native_method, " all-pairwise comparisons (log2FC)"))
    pair_df <- .diff_all_pairwise_native(
      empt, group_var, method = native_method, filter_low = fl, on_progress = on_progress
    )
    if (is.null(lrt_df)) {
      result <- pair_df
      result$comparison_mode <- "multi_lrt"
    } else {
      lrt_cols <- lrt_df[, c("feature", "pvalue", "fdr"), drop = FALSE]
      names(lrt_cols) <- c("feature", "lrt_pvalue", "lrt_fdr")
      result <- merge(pair_df, lrt_cols, by = "feature", all.x = TRUE, sort = FALSE)
      result$comparison_mode <- "multi_lrt"
      rownames(result) <- NULL
    }
  } else {
    bump(20, paste0("Running ", native_method, " all-pairwise comparisons"))
    result <- .diff_all_pairwise_native(
      empt, group_var, method = native_method, filter_low = fl, on_progress = on_progress
    )
  }
  empt <- .diff_store_result(empt, result, group_var, native_method)
  bump(90, "Saving results")
  save_empt(session_id, experiment, empt)
  bump(100, "Done")
  result
}

.diff_strip_internal_group_cols <- function(empt) {
  cd <- as.data.frame(SummarizedExperiment::colData(empt))
  drop <- grep("(_safe|__emp)$", names(cd), ignore.case = TRUE, value = TRUE)
  if (length(drop)) {
    cd <- cd[, setdiff(names(cd), drop), drop = FALSE]
    SummarizedExperiment::colData(empt) <- .diff_as_coldata(cd)
  }
  empt
}

.diff_store_result <- function(empt, result, group_var, method_label) {
  empt <- .diff_strip_internal_group_cols(empt)
  empt@deposit[["diff_analysis_result"]] <- result
  if (!is.null(empt@metadata)) {
    tryCatch({
      empt@metadata$estimate_group <- group_var
      empt@metadata$method <- method_label
    }, error = function(e) NULL)
  }
  empt
}

run_diff <- function(session_id, experiment, method = "DESeq2",
                     group_var = NULL, ref_group = NULL, test_group = NULL,
                     filter_low = TRUE, subset_two_groups = TRUE,
                     comparison_mode = "pairwise",
                     cores = "auto", on_progress = NULL) {
  bump <- function(pct, msg = NULL) {
    if (!is.null(on_progress) && is.function(on_progress)) {
      tryCatch(on_progress(pct, msg), error = function(e) NULL)
    }
  }
  bump(1, "Loading experiment")
  # Start from a pristine EMPT – otherwise earlier PCA/cluster calls may
  # have attached state (e.g. class "EMP_dimension_analysis") that makes
  # EMP_diff_analysis mis-interpret the sample matrix.
  empt <- get_empt_fresh(session_id, experiment)
  empt <- apply_merged_coldata(session_id, empt)
  cd_df <- as.data.frame(SummarizedExperiment::colData(empt))

  if (is.null(group_var) || group_var == "") {
    group_var <- .clinical_preferred_group_var(cd_df)
  }
  if (is.null(group_var) || group_var == "") {
    cats <- names(cd_df)[sapply(cd_df, function(x) {
      ux <- unique(na.omit(as.character(x)))
      length(ux) > 1 && length(ux) < nrow(cd_df)
    })]
    if (length(cats) == 0) stop("No grouping variable available in sample metadata.")
    group_var <- cats[1]
  }
  if (!group_var %in% names(cd_df)) {
    hit <- names(cd_df)[tolower(names(cd_df)) == tolower(group_var)]
    if (length(hit)) group_var <- hit[1]
  }
  if (!group_var %in% names(cd_df)) {
    stop("Selected grouping variable is not present in sample metadata.")
  }
  group_vals <- unique(na.omit(as.character(cd_df[[group_var]])))
  if (length(group_vals) < 2) {
    stop("Grouping variable must contain at least two categories.")
  }

  method_raw <- if (is.null(method) || method == "") "wilcox.test" else as.character(method)[1]
  comparison_mode <- tolower(trimws(as.character(comparison_mode %||% "pairwise")))
  if (!comparison_mode %in% c("pairwise", "all_pairwise", "multi_lrt")) {
    comparison_mode <- "pairwise"
  }
  multi_capable <- tolower(method_raw) %in% c("deseq2", "edger")
  if (comparison_mode != "pairwise" && !multi_capable) {
    stop("All-pairwise and multi-group LRT are only supported for DESeq2 and edgeR.")
  }
  if (comparison_mode %in% c("all_pairwise", "multi_lrt")) {
    subset_two_groups <- FALSE
  }
  # Safety: UI may send subset=false with 3+ groups while comparison_mode was lost in transit.
  if (comparison_mode == "pairwise" && multi_capable && !isTRUE(subset_two_groups) &&
      length(group_vals) >= 3L) {
    comparison_mode <- "all_pairwise"
    bump(4, paste0("Using all-pairwise (", length(group_vals), " groups, with log2FC)"))
  } else {
    bump(4, paste0("Comparison mode: ", comparison_mode))
  }

  if (comparison_mode == "pairwise") {
    if (is.null(ref_group) || ref_group == "") ref_group <- group_vals[1]
    if (is.null(test_group) || test_group == "") test_group <- group_vals[2]
    if (identical(ref_group, test_group)) stop("Reference and test groups must be different.")
  }

  method_use <- method_raw
  alias_map <- c(
    "wilcox" = "wilcox.test",
    "t.test" = "t.test",
    "DESeq2" = "DESeq2",
    "edgeR" = "edgeR_quasi_likelihood",
    "limma" = "limma_voom"
  )
  if (method_use %in% names(alias_map)) method_use <- alias_map[[method_use]]

  # 1. Subset samples to only ref + test groups (huge speed-up for bulk RNAseq).
  if (isTRUE(subset_two_groups)) {
    bump(8, "Subsetting samples to selected groups")
    keep_s <- as.character(cd_df[[group_var]]) %in% c(ref_group, test_group)
    keep_s[is.na(keep_s)] <- FALSE
    if (sum(keep_s) < 2) {
      stop("Fewer than 2 samples remain after restricting to the selected groups.")
    }
    empt <- empt[, keep_s]
    # EMP / tidybulk / DESeq2 complain when the group column is a factor
    # that still carries the dropped levels of un-selected groups.  Coerce
    # the column back to character with exactly two levels so downstream
    # "two-category" checks pass.
    cd <- SummarizedExperiment::colData(empt)
    cd[[group_var]] <- as.character(cd[[group_var]])
    SummarizedExperiment::colData(empt) <- cd
  }

  # 2. Filter low-abundance/all-zero features so per-feature tests finish faster.
  if (isTRUE(filter_low)) {
    bump(14, "Filtering low-abundance features")
    ad <- SummarizedExperiment::assays(empt)[[1]]
    if (is.null(ad)) stop("Assay matrix is missing.")
    n_samp <- ncol(ad)
    min_present <- max(3L, ceiling(n_samp * 0.1))
    keep_f <- rowSums(!is.na(ad) & ad > 0) >= min_present
    if (sum(keep_f) >= 50) {
      empt <- empt[keep_f, ]
    }
  }

  # 3. Sanitise groups for tidybulk back-ends (limma_voom / edgeR / DESeq2).
  tidybulk_methods <- c(
    "edgeR_quasi_likelihood",
    "edgeR_likelihood_ratio",
    "edger_robust_likelihood_ratio",
    "DESeq2",
    "limma_voom",
    "limma_voom_sample_weights"
  )
  using_tidybulk <- method_use %in% tidybulk_methods
  gv_eff <- group_var
  ref_eff <- ref_group
  test_eff <- test_group

  if (comparison_mode %in% c("multi_lrt", "all_pairwise") && multi_capable) {
    return(.diff_run_native_multi(
      session_id, experiment, empt, group_var, method_raw,
      comparison_mode, filter_low, on_progress
    ))
  }

  if (using_tidybulk) {
    san <- .diff_sanitize_groups(empt, group_var, ref_group, test_group)
    empt <- san$empt
    gv_eff <- san$group_var
    ref_eff <- san$ref
    test_eff <- san$test
  }

  formula_obj <- stats::as.formula(paste0("~", gv_eff))
  group_level <- c(ref_eff, test_eff)
  cores_use <- .diff_detect_cores(cores)

  run_selected <- function(m) {
    bump(25, paste0("Running ", m, " (cores=", cores_use, ")"))
    if (m %in% tidybulk_methods) {
      empt |> EasyMultiProfiler::EMP_diff_analysis(
        .formula = formula_obj,
        method = m,
        group_level = group_level
      )
    } else {
      empt |> EasyMultiProfiler::EMP_diff_analysis(
        method = m,
        estimate_group = gv_eff,
        group_level = group_level,
        core = cores_use
      )
    }
  }

  no_fallback <- c(
    "DESeq2", "edgeR_quasi_likelihood", "edgeR_likelihood_ratio",
    "edger_robust_likelihood_ratio", "limma_voom", "limma_voom_sample_weights"
  )

  empt <- tryCatch(
    run_selected(method_use),
    error = function(e) {
      if (method_use %in% no_fallback) {
        msg <- conditionMessage(e)
        if (length(group_vals) >= 3L && !isTRUE(subset_two_groups) &&
            tolower(method_raw) %in% c("deseq2", "edger")) {
          stop(msg, " Select Comparison mode = Multi-group LRT or All pairwise.", call. = FALSE)
        }
        stop("Differential analysis failed for '", method_use, "': ", msg, call. = FALSE)
      }
      if (!identical(method_use, "wilcox.test")) {
        bump(60, "Falling back to wilcox.test")
        tryCatch(run_selected("wilcox.test"),
                 error = function(e2) stop("Differential analysis failed for '",
                                           method_use, "' and fallback 'wilcox.test'. ",
                                           conditionMessage(e)))
      } else {
        stop("Differential analysis failed: ", conditionMessage(e))
      }
    }
  )

  bump(90, "Saving results")
  empt <- .diff_strip_internal_group_cols(empt)
  save_empt(session_id, experiment, empt)

  result <- tryCatch(
    EasyMultiProfiler::EMP_result(empt, info = "diff_analysis_result"),
    error = function(e) data.frame()
  )
  if (is.null(result)) result <- data.frame()

  # Also compute and cache a "raw" DESeq2-style diff table
  # (baseMean / log2FoldChange / lfcSE / stat / pvalue / padj + symbol).
  # This is what the sample scripts use for volcano + DEG heatmap + KEGG/GO.
  tryCatch({
    raw_df <- .compute_diff_raw(session_id, experiment,
                                method = method_use,
                                group_var = gv_eff, group_var_orig = group_var,
                                ref_group = ref_eff, test_group = test_eff,
                                compact = result)
    saveRDS(list(
      method = method_use, group_var = group_var,
      ref_group = ref_group, test_group = test_group,
      created = Sys.time(), data = raw_df
    ), diff_raw_path(session_id, experiment))
  }, error = function(e) {
    message("[diff] raw result cache skipped: ", conditionMessage(e))
  })

  bump(100, "Done")
  result
}

# ---------------------------------------------------------------------------
# .compute_diff_raw: return a data.frame matching the classic DESeq2 export:
#   feature, symbol, baseMean, log2FoldChange, lfcSE, stat, pvalue, padj
# For DESeq2 method we run DESeq2::DESeq() on the filtered count matrix so the
# downstream tools (volcano, DEG heatmap, clusterProfiler) can use exactly the
# same columns as stand-alone R scripts.  For other methods we fall back to
# the EMP compact result and rename its columns.
# ---------------------------------------------------------------------------
.compute_diff_raw <- function(session_id, experiment,
                              method, group_var, group_var_orig,
                              ref_group, test_group, compact = NULL) {
  empt <- load_empt(session_id, experiment)
  ad <- SummarizedExperiment::assays(empt)[[1]]
  cd <- as.data.frame(SummarizedExperiment::colData(empt))

  is_deseq2 <- identical(tolower(method), "deseq2")
  if (is_deseq2 && requireNamespace("DESeq2", quietly = TRUE)) {
    sub_idx <- which(as.character(cd[[group_var]]) %in% c(ref_group, test_group))
    if (length(sub_idx) < 2) stop("Not enough samples for native DESeq2 run.")
    counts <- round(as.matrix(ad[, sub_idx, drop = FALSE]))
    storage.mode(counts) <- "integer"
    coldat <- cd[sub_idx, , drop = FALSE]
    coldat[[group_var]] <- factor(as.character(coldat[[group_var]]),
                                   levels = c(ref_group, test_group))
    keep_r <- rowSums(counts > 0) >= max(3L, ceiling(ncol(counts) * 0.1))
    if (!any(keep_r)) stop("All features filtered out for native DESeq2 run.")
    counts <- counts[keep_r, , drop = FALSE]

    dds <- DESeq2::DESeqDataSetFromMatrix(countData = counts,
                                          colData   = coldat,
                                          design    = as.formula(paste0("~", group_var)))
    dds <- DESeq2::DESeq(dds, parallel = FALSE, quiet = TRUE)
    res <- DESeq2::results(dds, contrast = c(group_var, test_group, ref_group))
    raw <- data.frame(
      feature        = rownames(res),
      symbol         = rownames(res),
      baseMean       = as.numeric(res$baseMean),
      log2FoldChange = as.numeric(res$log2FoldChange),
      lfcSE          = as.numeric(res$lfcSE),
      stat           = as.numeric(res$stat),
      pvalue         = as.numeric(res$pvalue),
      padj           = as.numeric(res$padj),
      stringsAsFactors = FALSE
    )
    raw <- raw[!is.na(raw$pvalue), , drop = FALSE]
    return(raw)
  }

  # Fall-back: derive from the EMP compact result (works for wilcox/edgeR/limma)
  if (is.null(compact) || !nrow(compact)) {
    compact <- tryCatch(
      as.data.frame(EasyMultiProfiler::EMP_result(empt, info = "diff_analysis_result")),
      error = function(e) data.frame()
    )
  }
  if (!nrow(compact)) stop("No differential result available to build raw table.")
  pick <- function(df, patterns) {
    for (pat in patterns) {
      h <- grep(pat, names(df), ignore.case = TRUE, value = TRUE)
      if (length(h)) return(h[1])
    }
    NA_character_
  }
  fc_col <- pick(compact, c("^log2fc$", "^log2foldchange$", "^lfc$"))
  p_col  <- pick(compact, c("^pvalue$", "^p_value$", "^p\\.value$"))
  q_col  <- pick(compact, c("^padj$",   "^fdr$",     "^q[._]?value$", "^adj[._]?p"))
  feats  <- if ("feature" %in% names(compact)) as.character(compact$feature) else rownames(compact)

  baseMean <- tryCatch({
    common <- intersect(feats, rownames(ad))
    bm <- rep(NA_real_, length(feats))
    if (length(common)) bm[match(common, feats)] <- rowMeans(ad[common, , drop = FALSE], na.rm = TRUE)
    bm
  }, error = function(e) rep(NA_real_, length(feats)))

  data.frame(
    feature        = feats,
    symbol         = feats,
    baseMean       = baseMean,
    log2FoldChange = if (!is.na(fc_col)) suppressWarnings(as.numeric(compact[[fc_col]])) else NA_real_,
    lfcSE          = NA_real_,
    stat           = NA_real_,
    pvalue         = if (!is.na(p_col)) suppressWarnings(as.numeric(compact[[p_col]])) else NA_real_,
    padj           = if (!is.na(q_col)) suppressWarnings(as.numeric(compact[[q_col]])) else NA_real_,
    stringsAsFactors = FALSE
  )
}

# Helper used by volcano / heatmap / enrichment: return the cached raw diff
# result (or NULL if none).
load_diff_raw <- function(session_id, experiment) {
  p <- diff_raw_path(session_id, experiment)
  if (!file.exists(p)) return(NULL)
  tryCatch(readRDS(p), error = function(e) NULL)
}

run_dimension <- function(session_id, experiment, method = "PCA") {
  empt <- get_empt(session_id, experiment)
  method_raw <- if (is.null(method) || !nzchar(method)) "pca" else tolower(method)
  method_map <- c(
    "pca" = "pca",
    "umap" = "umap",
    "mds" = "pcoa",
    "pcoa" = "pcoa",
    "pls" = "pls",
    "opls" = "opls",
    "tsne" = "umap",
    "t-sne" = "umap"
  )
  method_use <- method_map[[method_raw]]
  if (is.null(method_use) || !nzchar(method_use)) method_use <- "pca"

  ## PCoA in EMP_dimension_analysis requires a `distance =` argument.
  ## Default to Bray-Curtis which is the convention for compositional
  ## microbiome data; all other methods don't take the arg so we only
  ## set it when needed to keep the call site tidy.
  if (identical(method_use, "pcoa")) {
    empt <- empt |> EasyMultiProfiler::EMP_dimension_analysis(
      method   = method_use,
      distance = "bray"
    )
  } else {
    empt <- empt |> EasyMultiProfiler::EMP_dimension_analysis(method = method_use)
  }
  save_empt(session_id, experiment, empt)

  ## Table returned to the web UI: ordination coordinates (not the whole colData).
  result <- tryCatch({
    dr <- EasyMultiProfiler::EMP_result(empt, info = "EMP_dimension_analysis")
    if (is.list(dr) && !is.null(dr$dimension_coordinate)) {
      as.data.frame(dr$dimension_coordinate, stringsAsFactors = FALSE)
    } else NULL
  }, error = function(e) NULL)
  if (is.null(result) || !nrow(result)) {
    result <- tryCatch(
      as.data.frame(SummarizedExperiment::colData(empt)),
      error = function(e) data.frame()
    )
  }
  result
}

run_correlation <- function(session_id, experiment, use = "spearman") {
  empt <- get_empt(session_id, experiment)
  result <- tryCatch({
    empt <- empt |> EasyMultiProfiler::EMP_cor_analysis(method = use)
    save_empt(session_id, experiment, empt)
    EasyMultiProfiler::EMP_result(empt, info = "cor_analysis_result")
  }, error = function(e) {
    ad <- SummarizedExperiment::assays(empt)[[1]]
    if (nrow(ad) < 2 || ncol(ad) < 2) stop("Correlation needs at least 2 features and 2 samples.")
    cor_mat <- suppressWarnings(stats::cor(t(ad), method = use, use = "pairwise.complete.obs"))
    if (all(is.na(cor_mat))) stop("Could not compute correlation matrix.")
    idx <- which(upper.tri(cor_mat), arr.ind = TRUE)
    data.frame(
      feature_1 = rownames(cor_mat)[idx[, 1]],
      feature_2 = colnames(cor_mat)[idx[, 2]],
      coefficient = as.numeric(cor_mat[idx]),
      stringsAsFactors = FALSE
    )
  })

  if (is.null(result)) result <- data.frame()
  result
}

run_cluster <- function(session_id, experiment, method = "hclust", k = 3) {
  empt <- get_empt(session_id, experiment)
  empt <- apply_merged_coldata(session_id, empt)

  k <- suppressWarnings(as.integer(k))
  if (is.na(k) || k < 2L) k <- 2L

  mat <- tryCatch(as.matrix(SummarizedExperiment::assays(empt)[[1]]), error = function(e) NULL)
  if (is.null(mat) || ncol(mat) < 2L) stop("Need at least 2 samples to cluster.")
  # Samples as rows for sample-level clustering.
  x <- t(mat)
  x[!is.finite(x)] <- 0
  # Drop zero-variance features to stabilise distances.
  v <- apply(x, 2, stats::var)
  if (any(v > 0)) x <- x[, v > 0, drop = FALSE]
  k <- min(k, nrow(x) - 1L)
  if (k < 2L) k <- 2L

  meth <- tolower(trimws(as.character(method %||% "hclust")))
  labels <- if (meth %in% c("kmeans", "km")) {
    set.seed(42)
    stats::kmeans(x, centers = k, nstart = 10)$cluster
  } else if (meth %in% c("pam", "kmedoids") && requireNamespace("cluster", quietly = TRUE)) {
    cluster::pam(stats::dist(x), k = k, cluster.only = TRUE)
  } else {
    hc <- stats::hclust(stats::dist(x), method = "ward.D2")
    stats::cutree(hc, k = k)
  }

  cd <- as.data.frame(SummarizedExperiment::colData(empt))
  lab <- labels
  if (!is.null(names(lab)) && all(rownames(cd) %in% names(lab))) {
    lab <- lab[rownames(cd)]
  }
  cluster_col <- factor(paste0("C", as.integer(lab)))
  cd$cluster <- cluster_col
  SummarizedExperiment::colData(empt)$cluster <- cluster_col
  save_empt(session_id, experiment, empt)
  cd
}

run_marker <- function(session_id, experiment, method = "randomForest", group_var = NULL,
                       ref_group = NULL, test_group = NULL) {
  empt <- get_empt(session_id, experiment)
  empt <- apply_merged_coldata(session_id, empt)
  cd_df <- as.data.frame(SummarizedExperiment::colData(empt))

  if (!is.null(group_var) && nzchar(group_var) && !(group_var %in% names(cd_df))) {
    hit <- names(cd_df)[tolower(names(cd_df)) == tolower(group_var)]
    if (length(hit)) group_var <- hit[1] else group_var <- NULL
  }
  if (is.null(group_var) || group_var == "") {
    group_var <- .clinical_preferred_group_var(cd_df)
  }
  if (is.null(group_var) || group_var == "") {
    cats <- names(cd_df)[sapply(cd_df, function(x) {
      ux <- unique(stats::na.omit(as.character(x)))
      length(ux) > 1 && length(ux) < nrow(cd_df)
    })]
    if (length(cats) == 0) stop("No grouping variable available.")
    group_var <- cats[1]
  }

  method_map <- c(
    "randomforest" = "randomForest",
    "rf" = "randomForest",
    "lefse" = "randomForest",
    "ancom" = "randomForest",
    "lasso" = "lasso",
    "xgboost" = "xgboost",
    "xgb" = "xgboost"
  )
  method_key <- tolower(trimws(as.character(method %||% "randomForest")))
  method_use <- method_map[[method_key]]
  if (is.null(method_use) || !nzchar(method_use)) method_use <- "randomForest"

  if (method_use %in% c("lasso", "xgboost")) {
    ad <- SummarizedExperiment::assays(empt)[[1]]
    cd <- as.data.frame(SummarizedExperiment::colData(empt))
    y_all <- as.character(cd[[group_var]])
    if (is.null(ref_group) || !nzchar(ref_group)) {
      lv <- unique(stats::na.omit(y_all))
      ref_group <- if (length(lv)) lv[1] else NULL
    }
    if (is.null(test_group) || !nzchar(test_group)) {
      lv <- unique(stats::na.omit(y_all))
      test_group <- if (length(lv) >= 2) lv[2] else NULL
    }
    if (!is.null(ref_group) && nzchar(ref_group) && !is.null(test_group) && nzchar(test_group) && !identical(ref_group, test_group)) {
      keep_pair <- y_all %in% c(ref_group, test_group)
      ad <- ad[, keep_pair, drop = FALSE]
      y_all <- y_all[keep_pair]
    }
    y <- as.factor(y_all)
    ok <- !is.na(y)
    X <- t(as.matrix(ad[, ok, drop = FALSE]))
    y <- droplevels(y[ok])
    if (length(levels(y)) != 2) stop("LASSO/XGBoost marker currently supports 2-group classification.")
    n_per_class <- table(y)
    if (any(n_per_class < 2)) {
      stop("LASSO/XGBoost requires at least 2 samples in each selected group.")
    }
    X[!is.finite(X)] <- 0
    if (identical(method_use, "lasso")) {
      if (!requireNamespace("glmnet", quietly = TRUE)) stop("Package 'glmnet' is required for LASSO markers.")
      nfolds <- max(2L, min(5L, as.integer(nrow(X)), as.integer(min(n_per_class))))
      fit <- glmnet::cv.glmnet(X, y, family = "binomial", alpha = 1, nfolds = nfolds)
      cf <- as.matrix(stats::coef(fit, s = "lambda.min"))
      tbl <- data.frame(
        feature = rownames(cf),
        importance = as.numeric(abs(cf[, 1])),
        stringsAsFactors = FALSE
      )
      tbl <- tbl[tbl$feature != "(Intercept)" & tbl$importance > 0, , drop = FALSE]
      tbl <- tbl[order(-tbl$importance), , drop = FALSE]
      return(tbl)
    } else {
      if (!requireNamespace("xgboost", quietly = TRUE)) stop("Package 'xgboost' is required for XGBoost markers.")
      y_num <- as.integer(y) - 1L
      dtrain <- xgboost::xgb.DMatrix(data = X, label = y_num)
      fit <- xgboost::xgb.train(
        params = list(
          objective = "binary:logistic",
          eval_metric = "auc",
          eta = 0.1,
          max_depth = 4
        ),
        data = dtrain,
        nrounds = 100,
        verbose = 0
      )
      imp <- xgboost::xgb.importance(model = fit, feature_names = colnames(X))
      if (is.null(imp) || !nrow(imp)) return(data.frame())
      return(data.frame(feature = imp$Feature, importance = imp$Gain, stringsAsFactors = FALSE))
    }
  }

  .rf_fallback <- function(obj, group_name) {
    if (!requireNamespace("randomForest", quietly = TRUE)) {
      stop("Package 'randomForest' is required for marker fallback.")
    }
    ad <- SummarizedExperiment::assays(obj)[[1]]
    cd <- as.data.frame(SummarizedExperiment::colData(obj))
    y <- as.factor(as.character(cd[[group_name]]))
    ok <- !is.na(y)
    y <- droplevels(y[ok])
    if (length(levels(y)) < 2) stop("Marker grouping variable must contain >=2 groups.")
    X <- t(as.matrix(ad[, ok, drop = FALSE]))
    X[!is.finite(X)] <- 0
    fit <- randomForest::randomForest(x = X, y = y, importance = TRUE)
    imp <- randomForest::importance(fit, type = 1)
    if (is.null(dim(imp))) {
      tbl <- data.frame(feature = names(imp), importance = as.numeric(imp), stringsAsFactors = FALSE)
    } else {
      tbl <- data.frame(feature = rownames(imp), importance = as.numeric(imp[, 1]), stringsAsFactors = FALSE)
    }
    tbl <- tbl[order(-tbl$importance), , drop = FALSE]
    rownames(tbl) <- NULL
    tbl
  }

  marker_tbl <- NULL
  marker_err <- NULL
  if (identical(method_use, "randomForest")) {
    # EMP has changed argument names across versions; try all common variants.
    arg_variants <- list(
      list(method = method_use, estimate_group = group_var),
      list(method = method_use, .group = group_var),
      list(method = method_use, group = group_var),
      list(method = method_use, group_var = group_var)
    )
    for (av in arg_variants) {
      empt_try <- tryCatch(do.call(EasyMultiProfiler::EMP_marker_analysis, c(list(empt), av)),
                           error = function(e) e)
      if (!inherits(empt_try, "error")) {
        empt <- empt_try
        save_empt(session_id, experiment, empt)
        infos <- c("marker_result", "EMP_marker_analysis", "rf_feature_importance", "feature_importance")
        for (info in infos) {
          marker_tbl <- tryCatch(EasyMultiProfiler::EMP_result(empt, info = info), error = function(e) NULL)
          if (!is.null(marker_tbl)) break
        }
        if (!is.null(marker_tbl)) {
          marker_tbl <- tryCatch(as.data.frame(marker_tbl, stringsAsFactors = FALSE), error = function(e) data.frame())
          if (nrow(marker_tbl)) break
        }
      } else {
        marker_err <- conditionMessage(empt_try)
      }
    }
  } else {
    empt <- tryCatch(
      empt |> EasyMultiProfiler::EMP_marker_analysis(method = method_use, estimate_group = group_var),
      error = function(e) {
        marker_err <<- conditionMessage(e)
        empt |> EasyMultiProfiler::EMP_marker_analysis(method = method_use, .group = group_var)
      }
    )
    save_empt(session_id, experiment, empt)
  }

  result <- marker_tbl
  if (is.null(result)) {
    infos <- c("marker_result", "EMP_marker_analysis", "rf_feature_importance", "feature_importance")
    for (info in infos) {
      result <- tryCatch(EasyMultiProfiler::EMP_result(empt, info = info), error = function(e) NULL)
      if (!is.null(result)) break
    }
    if (!is.null(result)) {
      result <- tryCatch(as.data.frame(result, stringsAsFactors = FALSE), error = function(e) data.frame())
    }
  }
  if (is.null(result)) result <- data.frame()
  if (!nrow(result)) {
    # Final rescue for RF-style marker analysis
    if (identical(method_use, "randomForest")) {
      result <- .rf_fallback(empt, group_var)
    }
  }
  if (is.null(result) || !nrow(result)) {
    stop("Marker analysis finished but no marker table was returned. Please re-run Differential first and ensure group labels are valid.",
         if (!is.null(marker_err)) paste0(" (Last error: ", marker_err, ")") else "")
  }
  result
}

# --- Enrichment (GO / KEGG) --------------------------------------------------
#
# We bypass EMP_enrich_analysis() and drive clusterProfiler directly so we can:
#   1. take the *native* DESeq2 DEG list (symbols in `diff_raw_path()`),
#   2. pick the correct OrgDb for hsa/mmu/rno,
#   3. translate symbols -> ENTREZ with clusterProfiler::bitr,
#   4. run enrichGO / enrichKEGG with the right "organism" code,
#   5. return the standard clusterProfiler result table and a dotplot.

# ------------------------------------------------------------------
# Species catalogue for KEGG + GO enrichment.
#
# Each row maps one KEGG species code to (a) the Bioconductor OrgDb
# package used by clusterProfiler and (b) a display label for the UI.
# Keeping this in one place means the frontend can ask for the catalog
# and show the user which organisms are ready vs. need a one-line
# BiocManager::install().
# ------------------------------------------------------------------
.ENRICH_SPECIES <- data.frame(
  kegg_code = c("hsa",    "mmu",    "rno",    "dme",      "cel",               "dre",      "sce",              "ath",           "bta",    "ssc",  "gga",      "mcc"),
  label     = c("Human",  "Mouse",  "Rat",    "Drosophila","C. elegans",       "Zebrafish","Yeast (S. cerevisiae)","Arabidopsis thaliana","Cattle","Pig", "Chicken",  "Rhesus monkey"),
  orgdb     = c("org.Hs.eg.db","org.Mm.eg.db","org.Rn.eg.db","org.Dm.eg.db","org.Ce.eg.db","org.Dr.eg.db","org.Sc.sgd.db","org.At.tair.db","org.Bt.eg.db","org.Ss.eg.db","org.Gg.eg.db","org.Mmu.eg.db"),
  keytype   = c("ENTREZID","ENTREZID","ENTREZID","ENTREZID","ENTREZID","ENTREZID","ORF","TAIR","ENTREZID","ENTREZID","ENTREZID","ENTREZID"),
  stringsAsFactors = FALSE
)

.enrich_orgdb <- function(code) {
  idx <- match(tolower(code), tolower(.ENRICH_SPECIES$kegg_code))
  if (is.na(idx)) return(NA_character_)
  .ENRICH_SPECIES$orgdb[idx]
}

.enrich_keytype <- function(code) {
  idx <- match(tolower(code), tolower(.ENRICH_SPECIES$kegg_code))
  if (is.na(idx)) return("ENTREZID")
  .ENRICH_SPECIES$keytype[idx]
}

#' List KEGG/GO species known to the web app, annotated with whether the
#' matching OrgDb Bioconductor package is installed locally.  This is the
#' source of truth for the frontend dropdown.
list_enrichment_species <- function() {
  df <- .ENRICH_SPECIES
  df$installed <- vapply(df$orgdb,
                          function(p) requireNamespace(p, quietly = TRUE),
                          logical(1))
  df$install_cmd <- ifelse(df$installed, NA_character_,
                            sprintf('BiocManager::install("%s")', df$orgdb))
  df
}

#' Install a missing OrgDb package on the server using BiocManager.
#' Returns a list with success flag + log messages.  Intended to be
#' driven from the frontend "Install now" button.
install_orgdb <- function(orgdb, on_progress = NULL) {
  orgdb <- as.character(orgdb)
  if (!nzchar(orgdb))
    stop("install_orgdb: orgdb argument is required.")
  if (!orgdb %in% .ENRICH_SPECIES$orgdb)
    stop(sprintf("install_orgdb: '%s' is not a recognised OrgDb package.", orgdb))

  bump <- function(p, msg = NULL) {
    if (!is.null(on_progress) && is.function(on_progress)) {
      tryCatch(on_progress(as.integer(p), msg), error = function(e) NULL)
    }
  }
  bump(5L, sprintf("Preparing to install %s", orgdb))

  if (requireNamespace(orgdb, quietly = TRUE)) {
    bump(100L, "Already installed")
    return(list(success = TRUE, installed = TRUE,
                 message = sprintf("%s is already installed.", orgdb)))
  }

  if (!requireNamespace("BiocManager", quietly = TRUE)) {
    bump(10L, "Installing BiocManager")
    utils::install.packages("BiocManager", repos = "https://cloud.r-project.org")
  }
  bump(20L, sprintf("Running BiocManager::install('%s')", orgdb))
  log <- utils::capture.output(
    tryCatch(
      BiocManager::install(orgdb, ask = FALSE, update = FALSE),
      error = function(e) {
        stop(sprintf("BiocManager::install('%s') failed: %s",
                     orgdb, conditionMessage(e)))
      }
    ),
    type = "message"
  )
  bump(90L, "Verifying installation")
  ok <- requireNamespace(orgdb, quietly = TRUE)
  bump(100L, if (ok) "Done" else "Install did not take effect")
  list(success   = ok,
       installed = ok,
       message   = if (ok) sprintf("%s installed successfully.", orgdb)
                   else     sprintf("%s failed to install – check the server log.", orgdb),
       log       = paste(utils::tail(log, 80), collapse = "\n"))
}

# Select DEGs from the cached DESeq2 table.
.enrich_select_degs <- function(raw_list, fc_cutoff, p_cutoff, use_padj) {
  if (is.null(raw_list) || is.null(raw_list$data) || !nrow(raw_list$data)) {
    stop("No differential analysis result available – run diff analysis first.")
  }
  df <- as.data.frame(raw_list$data, stringsAsFactors = FALSE)
  padj_vec <- suppressWarnings(as.numeric(df$padj))
  pval_vec <- suppressWarnings(as.numeric(df$pvalue))
  # Transparent fallback: if user asks for padj but nothing passes, use raw p
  # with a message so small RNAseq runs still produce enrichment input.
  if (isTRUE(use_padj) && any(is.finite(padj_vec))) {
    n_sig <- sum(is.finite(padj_vec) & padj_vec <= p_cutoff, na.rm = TRUE)
    if (n_sig == 0 && any(is.finite(pval_vec))) {
      use_padj <- FALSE
      message("[enrichment] No padj-significant genes – using raw p-value.")
    }
  }
  p <- if (isTRUE(use_padj) && any(is.finite(padj_vec))) padj_vec else pval_vec
  df$p_plot <- p
  df$fc <- suppressWarnings(as.numeric(df$log2FoldChange))
  df <- df[is.finite(df$fc) & is.finite(df$p_plot), , drop = FALSE]
  df$direction <- ifelse(df$fc >=  fc_cutoff & df$p_plot <= p_cutoff, "Up",
                  ifelse(df$fc <= -fc_cutoff & df$p_plot <= p_cutoff, "Down", "NS"))
  deg <- df[df$direction != "NS", , drop = FALSE]
  deg <- deg[order(-abs(deg$fc)), , drop = FALSE]
  deg
}

run_enrichment <- function(session_id, experiment,
                            database = "KEGG", organism = "hsa",
                            fc_cutoff = 1.0, p_cutoff = 0.05, use_padj = TRUE,
                            direction = c("both", "up", "down"),
                            top_n = 20L, on_progress = NULL) {
  direction   <- match.arg(direction)
  method_use  <- tolower(as.character(database %||% "KEGG"))
  org_use     <- normalize_species(organism, default = "hsa")
  orgdb       <- .enrich_orgdb(org_use)
  keytype     <- .enrich_keytype(org_use)

  bump <- function(p, msg = NULL) {
    if (!is.null(on_progress) && is.function(on_progress)) {
      tryCatch(on_progress(as.integer(p), msg), error = function(e) NULL)
    }
  }

  bump(5L, "Checking packages")

  if (!requireNamespace("clusterProfiler", quietly = TRUE)) {
    stop("Package 'clusterProfiler' is required for enrichment analysis. ",
         'Install with: BiocManager::install("clusterProfiler")')
  }
  if (is.na(orgdb)) {
    stop(sprintf("Unknown organism code '%s'. Supported: %s.",
                 org_use, paste(.ENRICH_SPECIES$kegg_code, collapse = ", ")))
  }
  if (!requireNamespace(orgdb, quietly = TRUE)) {
    stop(sprintf(
      "OrgDb package '%s' for organism '%s' is not installed. Install with: BiocManager::install(\"%s\")",
      orgdb, org_use, orgdb))
  }

  bump(12L, "Loading differential analysis table")
  raw <- load_diff_raw(session_id, experiment)
  deg <- .enrich_select_degs(raw, fc_cutoff = fc_cutoff,
                              p_cutoff = p_cutoff, use_padj = use_padj)
  if (direction == "up")   deg <- deg[deg$direction == "Up",   , drop = FALSE]
  if (direction == "down") deg <- deg[deg$direction == "Down", , drop = FALSE]
  if (!nrow(deg)) {
    stop("No DEGs passed the selected cutoffs – try relaxing |log2FC| or p / padj.")
  }

  symbols <- unique(as.character(deg$symbol %||% deg$feature))
  symbols <- symbols[nzchar(symbols)]

  bump(25L, sprintf("Mapping %d genes to %s", length(symbols), keytype))
  mapped <- tryCatch(
    clusterProfiler::bitr(symbols, fromType = "SYMBOL", toType = keytype,
                           OrgDb = get(orgdb, envir = asNamespace(orgdb))),
    error = function(e) data.frame()
  )
  if (!nrow(mapped)) {
    # Already in target keytype?
    if (keytype == "ENTREZID" && all(grepl("^[0-9]+$", symbols))) {
      mapped <- data.frame(SYMBOL = symbols, ENTREZID = symbols,
                            stringsAsFactors = FALSE)
    } else {
      stop("Could not map any gene symbols to ", keytype, " ids for ", org_use,
            ". Check that your rownames are gene symbols.")
    }
  }
  gene_ids <- unique(mapped[[keytype]])

  bump(45L, sprintf("Running %s enrichment on %d genes", toupper(method_use), length(gene_ids)))
  res <- if (method_use == "go") {
    clusterProfiler::enrichGO(
      gene          = gene_ids,
      OrgDb         = get(orgdb, envir = asNamespace(orgdb)),
      keyType       = keytype,
      ont           = "BP",
      pAdjustMethod = "BH",
      pvalueCutoff  = 0.05,
      qvalueCutoff  = 0.2,
      readable      = TRUE
    )
  } else {
    # KEGG only accepts its own 3-letter species codes.
    tryCatch(clusterProfiler::enrichKEGG(
      gene          = gene_ids,
      organism      = org_use,
      keyType       = if (keytype == "ENTREZID") "kegg" else "kegg",
      pAdjustMethod = "BH",
      pvalueCutoff  = 0.05,
      qvalueCutoff  = 0.2
    ), error = function(e) {
      # Some KEGG REST failures (network, species not supported) come here
      # – surface an actionable message to the user.
      stop("enrichKEGG() failed for organism '", org_use, "': ",
            conditionMessage(e),
            ". If this is a network error retry, or switch to GO.")
    })
  }

  bump(80L, "Formatting results")
  if (is.null(res)) {
    bump(100L, "No enriched terms")
    return(list(
      success = TRUE, database = toupper(method_use), organism = org_use,
      direction = direction, deg_count = length(symbols),
      mapped_count = length(gene_ids),
      data = data.frame(), plot = NA_character_
    ))
  }

  if (method_use == "kegg") {
    res <- tryCatch(
      clusterProfiler::setReadable(res,
        OrgDb = get(orgdb, envir = asNamespace(orgdb)),
        keyType = keytype),
      error = function(e) res)
  }

  df <- as.data.frame(res)
  if (nrow(df) && top_n > 0) df <- utils::head(df, as.integer(top_n * 2))

  bump(90L, "Building dot plot")
  plot_b64 <- NA_character_
  if (nrow(df) > 0) {
    plot_b64 <- tryCatch({
      if (requireNamespace("enrichplot", quietly = TRUE)) {
        p <- enrichplot::dotplot(res, showCategory = min(as.integer(top_n), 20)) +
          ggplot2::labs(title = paste0(toupper(method_use), " enrichment (",
                                          direction, " DEGs, ", org_use, ")")) +
          emp_pub_theme(base_size = 11)
        plot_to_base64(p, width = 9, height = 7)
      } else {
        p <- clusterProfiler::barplot(res, showCategory = min(as.integer(top_n), 20)) +
          ggplot2::labs(title = paste0(toupper(method_use), " enrichment (",
                                          direction, " DEGs, ", org_use, ")")) +
          emp_pub_theme(base_size = 11)
        plot_to_base64(p, width = 9, height = 7)
      }
    }, error = function(e) NA_character_)
  }

  bump(100L, "Done")
  list(
    success      = TRUE,
    database     = toupper(method_use),
    organism     = org_use,
    direction    = direction,
    deg_count    = length(symbols),
    mapped_count = length(gene_ids),
    n_rows       = nrow(df),
    data         = df,
    plot         = plot_b64
  )
}

run_network <- function(session_id, experiment, method = "spearman", cutoff = 0.6) {
  empt <- get_empt(session_id, experiment)
  method_key <- tolower(trimws(as.character(method %||% "spearman")))
  # EMP_network_analysis `method` is bootnet default ("cor", "EBICglasso", ...).
  # Frontend often sends correlation names ("spearman"/"pearson"), map them.
  if (method_key %in% c("spearman", "pearson", "kendall")) {
    net_method <- "cor"
    cor_method <- method_key
  } else {
    net_method <- method
    cor_method <- "spearman"
  }
  empt <- empt |> EasyMultiProfiler::EMP_network_analysis(
    method = net_method,
    corMethod = cor_method,
    threshold = cutoff
  )
  save_empt(session_id, experiment, empt)
  list(success = TRUE, message = "Network analysis completed. Use visualization to view.")
}
