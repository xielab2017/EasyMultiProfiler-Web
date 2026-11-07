# Registered count workflows. No user code, formulas, paths or method fallback.
EMP_WB_CONTRACT <- "emp-count-workbench-v1"

emp_wb_capabilities <- function() {
  packages <- c("DESeq2", "callr", "digest", "jsonlite", "edgeR")
  versions <- vapply(packages, function(p) {
    if (requireNamespace(p, quietly = TRUE)) as.character(utils::packageVersion(p)) else "missing"
  }, character(1))
  list(success = TRUE, contract = EMP_WB_CONTRACT, ready = all(versions[c("DESeq2", "callr", "digest", "jsonlite")] != "missing"),
       packages = as.list(versions), r_version = as.character(getRversion()),
       operations = c("qc", "normalize", "pca", "deseq2", "heatmap", "edger"),
       multiple_contrasts = TRUE, methods_ready = list(DESeq2 = versions[["DESeq2"]] != "missing", edgeR = versions[["edgeR"]] != "missing"),
       supported_omics = "bulk_rnaseq", max_cells = 1000000L)
}

.wb_fields <- function(x, allowed) {
  if (!is.list(x) || is.null(names(x)) || anyDuplicated(names(x)) || any(!names(x) %in% allowed)) stop("Unsupported workbench fields")
}
.wb_label <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x)) && nchar(x) <= 256L && !grepl("[[:cntrl:]]", x)
}
.wb_integer <- function(x, low, high) {
  is.numeric(x) && length(x) == 1L && is.finite(x) && x == floor(x) && x >= low && x <= high
}

.wb_contrasts <- function(design, groups) {
  .wb_fields(design, c("test", "reference", "independent_samples", "contrasts"))
  pairs <- design$contrasts
  if (is.null(pairs)) {
    if (length(groups) != 2L) stop("Explicit comparisons are required for more than two groups")
    pairs <- list(list(test = design$test, reference = design$reference))
  }
  if (!is.list(pairs) || !is.null(names(pairs)) || !length(pairs) || length(pairs) > 20L) stop("Select 1-20 explicit comparisons")
  keys <- character()
  for (pair in pairs) {
    .wb_fields(pair, c("test", "reference"))
    if (!.wb_label(pair$test) || !.wb_label(pair$reference) || identical(pair$test, pair$reference) || !all(c(pair$test, pair$reference) %in% groups)) stop("Contrast groups must be distinct declared groups")
    key <- paste(match(pair$test, groups), match(pair$reference, groups), sep = ":")
    if (key %in% keys) stop("Duplicate contrasts")
    keys <- c(keys, key)
  }
  if (!identical(design$test, pairs[[1]]$test) || !identical(design$reference, pairs[[1]]$reference)) stop("Primary comparison differs from displayed contrasts")
  pairs
}

.wb_group_review <- function(review, samples) {
  .wb_fields(review, c("confirmed", "method", "field", "metadata_sha256", "paper", "sample_rows"))
  if (!isTRUE(review$confirmed) || !is.character(review$method) || length(review$method) != 1L || !review$method %in% c("manual", "geo_characteristic") || nchar(jsonlite::toJSON(review, auto_unbox = TRUE), type = "bytes") > 48000L) stop("Review grouping evidence before analysis")
  rows <- review$sample_rows
  if (!is.list(rows) || length(rows) != length(samples)) stop("Grouping evidence must cover every sample")
  for (row in rows) {
    .wb_fields(row, c("id", "group", "gsm", "match", "evidence"))
    if (!all(vapply(row, function(value) is.character(value) && length(value) == 1L && !is.na(value) && nchar(value) <= 1000L, logical(1)))) stop("Invalid grouping evidence")
  }
  ids <- vapply(rows, `[[`, character(1), "id")
  expected <- vapply(samples, `[[`, character(1), "id")
  if (anyDuplicated(ids) || !setequal(ids, expected) || !identical(vapply(rows[match(expected, ids)], `[[`, character(1), "group"), vapply(samples, `[[`, character(1), "group"))) stop("Grouping evidence no longer matches sample labels")
  paper <- review$paper
  if (!is.list(paper)) stop("Paper evidence must be an object")
  if (length(paper)) .wb_fields(paper, c("title", "doi", "pmid", "filename", "pdf_sha256", "source_url", "evidence"))
  for (name in setdiff(names(paper), "evidence")) if (!is.character(paper[[name]]) || length(paper[[name]]) != 1L || is.na(paper[[name]]) || nchar(paper[[name]]) > 2048L) stop("Invalid paper evidence metadata")
  if (!is.null(paper$evidence)) {
    if (!is.list(paper$evidence) || length(paper$evidence) > 12L) stop("Paper evidence exceeds limit")
    for (row in paper$evidence) {
      .wb_fields(row, c("page", "text", "kind"))
      if (!.wb_integer(row$page, 1, 100) || !is.character(row$text) || length(row$text) != 1L || is.na(row$text) || nchar(row$text) > 700L) stop("Invalid paper page evidence")
    }
  }
}

emp_wb_validate <- function(payload) {
  .wb_fields(payload, c("plan_json", "plan_sha256", "matrix_csv", "confirmed"))
  if (!is.character(payload$plan_json) || length(payload$plan_json) != 1L || nchar(payload$plan_json, type = "bytes") > 512 * 1024 ||
      !is.character(payload$matrix_csv) || length(payload$matrix_csv) != 1L || nchar(payload$matrix_csv, type = "bytes") > 16 * 1024^2) stop("Bounded prepared plan and matrix required")
  if (!identical(digest::digest(enc2utf8(payload$plan_json), algo = "sha256", serialize = FALSE), payload$plan_sha256)) stop("Plan changed after preparation")
  plan <- jsonlite::fromJSON(payload$plan_json, simplifyVector = FALSE)
  .wb_fields(plan, c("version", "dataset_id", "omics", "data_type", "samples", "design", "steps", "seed", "raw_counts_evidence",
                     "contract", "input_sha256", "source_sha256", "source", "excluded_columns", "raw_count_provenance_verified", "grouping_review", "deferred_steps"))
  if (!identical(plan$contract, EMP_WB_CONTRACT) || !identical(plan$version, 1L) || !identical(plan$omics, "bulk_rnaseq") || !identical(plan$data_type, "raw_counts")) stop("Only bulk RNA-seq raw counts are executable")
  if (!is.character(plan$raw_counts_evidence) || length(plan$raw_counts_evidence) != 1L || !nzchar(trimws(plan$raw_counts_evidence)) || nchar(plan$raw_counts_evidence) > 2048L) stop("Reviewed raw-count evidence required")
  if (!.wb_integer(plan$seed, 1, 2147483647)) stop("Invalid random seed")
  if (!identical(digest::digest(enc2utf8(payload$matrix_csv), algo = "sha256", serialize = FALSE), plan$input_sha256)) stop("Prepared matrix checksum mismatch")
  if (!is.character(plan$source_sha256) || length(plan$source_sha256) != 1L || !grepl("^[a-f0-9]{64}$", plan$source_sha256)) stop("Original-file checksum required")
  table <- utils::read.csv(text = payload$matrix_csv, check.names = FALSE, colClasses = "character", na.strings = NULL)
  if (nrow(table) < 2L || nrow(table) > 50000L || ncol(table) < 3L || ncol(table) > 257L || nrow(table) * (ncol(table) - 1L) > 1000000L) stop("Count matrix exceeds supported dimensions")
  feature_ids <- table[[1]]; sample_ids <- names(table)[-1]
  if (anyDuplicated(feature_ids) || anyDuplicated(sample_ids) || !all(vapply(c(feature_ids, sample_ids), .wb_label, logical(1)))) stop("Invalid or duplicate feature/sample IDs")
  text_counts <- as.matrix(table[-1])
  if (!all(grepl("^[0-9]{1,10}$", text_counts))) stop("Counts must be exact integers; no rounding or filling")
  counts <- matrix(as.numeric(text_counts), nrow = nrow(table), dimnames = list(feature_ids, sample_ids))
  if (any(!is.finite(counts)) || any(counts > 2147483647) || any(colSums(counts) == 0)) stop("Invalid raw counts or empty libraries")
  if (!is.list(plan$samples) || length(plan$samples) != length(sample_ids)) stop("Annotate every matrix sample")
  for (row in plan$samples) {
    .wb_fields(row, c("id", "group"))
    if (!.wb_label(row$id) || !.wb_label(row$group)) stop("Sample ID/group required; adjusted and paired designs are unsupported")
  }
  ids <- vapply(plan$samples, `[[`, character(1), "id")
  if (anyDuplicated(ids) || !setequal(ids, sample_ids)) stop("Matrix and metadata IDs must match exactly")
  samples <- plan$samples[match(sample_ids, ids)]
  deferred <- unlist(plan$deferred_steps, use.names = FALSE)
  if (length(deferred) > 3L || anyDuplicated(deferred) || any(!deferred %in% c("volcano", "enrichment", "wgcna"))) stop("Invalid deferred workflow steps")
  if (!is.null(plan$grouping_review)) .wb_group_review(plan$grouping_review, samples)
  .wb_fields(plan$design, c("test", "reference", "independent_samples", "contrasts"))
  ops <- c("qc", "normalize", "pca", "deseq2", "heatmap", "edger")
  if (!is.list(plan$steps) || !length(plan$steps) || length(plan$steps) > 6L) stop("Select 1-6 registered steps")
  seen <- character(); step_ids <- character()
  for (step in plan$steps) {
    .wb_fields(step, c("id", "operation", "parameters"))
    op <- step$operation
    if (!.wb_label(op) || !op %in% ops || op %in% seen || !.wb_label(step$id) || !grepl("^[a-zA-Z0-9_-]{1,64}$", step$id) || step$id %in% step_ids) stop("Invalid or duplicate workflow step")
    step_ids <- c(step_ids, step$id)
    p <- step$parameters
    expected <- switch(op, qc = character(), normalize = character(), pca = "components", deseq2 = c("alpha", "min_count", "min_samples"), edger = c("alpha", "min_count", "min_samples"), heatmap = "top_n")
    if (!is.list(p) || !setequal(names(p), expected)) stop("Unexpected or missing step parameters")
    if (op == "pca" && !.wb_integer(p$components, 1, min(length(sample_ids) - 1L, 10L))) stop("Invalid PCA components")
    if (op == "heatmap" && !.wb_integer(p$top_n, 1, min(nrow(counts), 500L))) stop("Invalid heatmap feature count")
    if (op %in% c("deseq2", "edger")) {
      if (!is.numeric(p$alpha) || length(p$alpha) != 1L || !is.finite(p$alpha) || p$alpha <= 0 || p$alpha >= 1 || !.wb_integer(p$min_count, 1, 1000000) || !.wb_integer(p$min_samples, 1, ncol(counts))) stop("Invalid DESeq2 parameters")
      groups <- table(vapply(samples, `[[`, character(1), "group"))
      if (!isTRUE(plan$design$independent_samples) || length(groups) < 2L || length(groups) > 12L || min(groups) < 2L) stop("Differential analysis needs 2-12 independent groups and >=2 replicates in every group")
      .wb_contrasts(plan$design, names(groups))
    }
    if (op %in% c("pca", "heatmap") && !"normalize" %in% seen) stop("Normalize before PCA/heatmap")
    if (op == "qc" && length(seen)) stop("QC must be first")
    seen <- c(seen, op)
  }
  if (!"qc" %in% seen) stop("QC is required")
  list(plan = plan, counts = counts, samples = samples)
}

emp_wb_compute <- function(payload, on_progress = function(...) NULL) {
  validated <- emp_wb_validate(payload)
  plan <- validated$plan; counts <- validated$counts; samples <- validated$samples
  set.seed(plan$seed)
  artifacts <- list(); events <- list(); norm <- NULL; differentials <- list()
  warnings <- c("Raw-count provenance is user-declared, not independently established.",
                "Unadjusted independent-sample analysis; no batch adjustment, pairing or causal inference.")
  as_rows <- function(x) jsonlite::fromJSON(jsonlite::toJSON(x, dataframe = "rows", na = "null", auto_unbox = TRUE, digits = NA), simplifyVector = FALSE)
  artifacts$qc <- list(samples = as_rows(data.frame(sample = colnames(counts), library_size = colSums(counts), detected_features = colSums(counts > 0), check.names = FALSE)),
                       feature_count = nrow(counts), all_zero_features = sum(rowSums(counts) == 0),
                       missing_values = 0L, input_sha256 = plan$input_sha256)
  for (i in seq_along(plan$steps)) {
    step <- plan$steps[[i]]; op <- step$operation; p <- step$parameters
    on_progress(round(5 + 85 * (i - 1) / length(plan$steps)), paste("Running", op))
    if (op == "normalize") {
      if (!requireNamespace("DESeq2", quietly = TRUE)) stop("DESeq2 is required; no substitute method was run")
      if (!any(rowSums(counts > 0) == ncol(counts))) stop("Default ratio size factors need a feature positive in all samples; choose a separately reviewed sparse-data workflow")
      size_factors <- DESeq2::estimateSizeFactorsForMatrix(counts)
      norm <- log2(sweep(counts, 2, size_factors, "/") + 1)
      artifacts$normalization <- list(method = "DESeq2 ratio size factors; log2(normalized_count + 1) for exploration", size_factors = as.list(stats::setNames(size_factors, colnames(counts))))
    } else if (op == "pca") {
      variance <- apply(norm, 1, stats::var)
      keep <- is.finite(variance) & variance > 0
      if (sum(keep) < p$components) stop("Too few variable features for requested PCA")
      fit <- stats::prcomp(t(norm[keep, , drop = FALSE]), center = TRUE, scale. = FALSE, rank. = p$components)
      scores <- as.data.frame(fit$x[, seq_len(p$components), drop = FALSE]); scores$sample <- rownames(scores)
      scores$group <- vapply(samples, `[[`, character(1), "group")
      artifacts$pca <- list(scores = as_rows(scores), variance_explained = as.list((fit$sdev^2 / sum(fit$sdev^2))[seq_len(p$components)]),
                            excluded_constant_features = sum(!keep), transform = "log2 size-factor normalized counts + 1")
    } else if (op == "heatmap") {
      variance <- apply(norm, 1, stats::var)
      idx <- head(order(variance, decreasing = TRUE, na.last = NA), p$top_n)
      idx <- idx[variance[idx] > 0]
      if (!length(idx)) stop("No variable features for heatmap")
      scaled <- t(scale(t(norm[idx, , drop = FALSE])))
      artifacts$heatmap <- list(feature_ids = as.list(rownames(scaled)), sample_ids = as.list(colnames(scaled)),
                                values = lapply(seq_len(nrow(scaled)), function(j) as.list(unname(scaled[j, ]))),
                                transform = "row z-score of log2 size-factor normalized counts + 1; variance-ranked features")
    } else if (op %in% c("deseq2", "edger")) {
      package <- if (op == "deseq2") "DESeq2" else "edgeR"
      if (!requireNamespace(package, quietly = TRUE)) stop(paste(package, "is required; no substitute method was run"))
      keep <- rowSums(counts >= p$min_count) >= p$min_samples
      if (sum(keep) < 2L) stop("Too few features after the explicit count filter")
      labels <- vapply(samples, `[[`, character(1), "group")
      levels <- c(plan$design$reference, setdiff(unique(labels), plan$design$reference))
      safe <- paste0("G", seq_along(levels))
      group <- factor(safe[match(labels, levels)], levels = safe)
      pairs <- .wb_contrasts(plan$design, levels)
      metadata <- data.frame(group = group, row.names = colnames(counts))
      if (op == "deseq2") {
        dds <- DESeq2::DESeqDataSetFromMatrix(counts[keep, , drop = FALSE], metadata, design = ~group)
        dds <- DESeq2::DESeq(dds, parallel = FALSE, quiet = TRUE)
      } else {
        model <- stats::model.matrix(~0 + group)
        y <- edgeR::DGEList(counts = counts[keep, , drop = FALSE], group = group)
        y <- edgeR::calcNormFactors(y, method = "TMM")
        y <- edgeR::estimateDisp(y, design = model, robust = FALSE)
        fit <- edgeR::glmQLFit(y, design = model, robust = FALSE)
      }
      for (pair in pairs) {
        if (op == "deseq2") {
          result <- as.data.frame(DESeq2::results(dds, contrast = c("group", safe[match(pair$test, levels)], safe[match(pair$reference, levels)]), alpha = p$alpha, pAdjustMethod = "BH"))
          fdr <- result$padj; pvalue <- result$pvalue
          details <- list(test_type = "Wald", dispersion_fit = attr(DESeq2::dispersionFunction(dds), "fitType"), normalization = "DESeq2 ratio size factors")
        } else {
          contrast <- numeric(ncol(model)); contrast[match(pair$test, levels)] <- 1; contrast[match(pair$reference, levels)] <- -1
          qlf <- edgeR::glmQLFTest(fit, contrast = contrast)
          result <- edgeR::topTags(qlf, n = Inf, adjust.method = "BH", sort.by = "none")$table
          fdr <- result$FDR; pvalue <- result$PValue
          details <- list(test_type = "quasi-likelihood F-test", normalization = "TMM", robust = FALSE,
                          normalization_factors = as.list(stats::setNames(y$samples$norm.factors, colnames(counts))))
        }
        result$feature_id <- rownames(result)
        differentials[[length(differentials) + 1L]] <- c(list(method = package, adjustment = "BH", alpha = p$alpha,
          test = pair$test, reference = pair$reference, positive_log2fc = "test / reference", rows = as_rows(result),
          fitted_groups = as.list(levels), contrast_count = length(pairs), fdr_scope = "within_each_contrast",
          tested_features = nrow(result), significant_features = sum(fdr < p$alpha, na.rm = TRUE),
          excluded_feature_ids = as.list(rownames(counts)[!keep]), filter = p,
          missing_pvalue = sum(is.na(pvalue)), missing_padj = sum(is.na(fdr))), details)
      }
      if (length(pairs) > 1L) warnings <- c(warnings, "All groups were fitted together; BH FDR is controlled within each contrast, not across the contrast family.")
      if (min(table(group)) < 3L) warnings <- c(warnings, "Two biological replicates per group offer limited power.")
    }
    events[[i]] <- list(step_id = step$id, operation = op, status = "done")
  }
  if (length(differentials)) { artifacts$differentials <- differentials; artifacts$differential <- differentials[[1]] }
  versions <- emp_wb_capabilities()
  list(success = TRUE, contract = EMP_WB_CONTRACT, execution_performed = TRUE,
       plan_sha256 = payload$plan_sha256, plan = plan, steps = events,
       execution_scope = list(executed_steps = lapply(plan$steps, function(step) step$operation), deferred_steps = if (is.null(plan$deferred_steps)) list() else plan$deferred_steps),
       artifacts = artifacts, warnings = warnings, environment = versions,
       session_info = capture.output(utils::sessionInfo()), raw_count_provenance_verified = FALSE)
}

emp_wb_submit <- function(payload, owner_id) {
  if (!isTRUE(payload$confirmed)) stop("Confirm the exact prepared plan before execution")
  caps <- emp_wb_capabilities()
  if (!isTRUE(caps$ready)) stop("Required R packages are unavailable; no job submitted")
  emp_wb_validate(payload)
  prepared_plan <- jsonlite::fromJSON(payload$plan_json, simplifyVector = FALSE)
  if (any(vapply(prepared_plan$steps, function(step) identical(step$operation, "edger"), logical(1))) && !isTRUE(caps$methods_ready$edgeR)) stop("edgeR is unavailable; no job submitted or substitute method selected")
  # The same exact plan can be retried safely after a lost HTTP response.
  # A process-local reservation serializes duplicate submissions.
  if (!exists(".EMP_WB_SUBMISSIONS", inherits = TRUE)) stop("Workbench submission registry unavailable")
  key <- paste0(owner_id, ":", payload$plan_sha256)
  if (exists(key, envir = .EMP_WB_SUBMISSIONS, inherits = FALSE)) return(get(key, envir = .EMP_WB_SUBMISSIONS))
  previous <- as.list(.EMP_WB_SUBMISSIONS)
  active <- sum(vapply(previous, function(item) {
    st <- get_job_status(item$job_id)
    identical(st$owner_id, owner_id) && st$status %in% c("queued", "running", "cancel_requested")
  }, logical(1)))
  if (active >= 2L) stop("Two count workflows are already active; wait or cancel before submitting another")
  id <- submit_job("count_workbench", emp_wb_compute, list(payload = payload), owner_id = owner_id)
  result <- list(success = TRUE, job_id = id, plan_sha256 = payload$plan_sha256, contract = EMP_WB_CONTRACT)
  assign(key, result, envir = .EMP_WB_SUBMISSIONS)
  result
}

if (!exists(".EMP_WB_SUBMISSIONS", inherits = FALSE)) .EMP_WB_SUBMISSIONS <- new.env(parent = emptyenv())
