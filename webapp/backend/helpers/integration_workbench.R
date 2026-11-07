# Reviewed, matched-subject exploration. No inferred pairing or missing-value imputation.
.iw_omics <- c("transcriptomics", "proteomics", "metabolomics", "microbiome", "epigenomics", "clinical")
.iw_label <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x)) && nchar(x) <= 256L && !grepl("[[:cntrl:]]", x)
.iw_fields <- function(x, allowed) {
  if (!is.list(x) || is.null(names(x)) || anyDuplicated(names(x)) || any(!names(x) %in% allowed)) stop("Unsupported integration fields")
}

emp_iw_validate <- function(payload, require_mapping = TRUE) {
  .iw_fields(payload, c("version", "blocks", "mapping", "missing_policy", "allow_unmatched", "preprocessing_reviewed", "design_reviewed", "confirmed"))
  if (!identical(payload$version, 1L) || !is.list(payload$blocks) || length(payload$blocks) < 2L || length(payload$blocks) > 8L) stop("Select 2-8 omics matrices")
  mats <- list(); info <- list(); cells <- 0L
  for (b in payload$blocks) {
    .iw_fields(b, c("id", "study_id", "omics", "scale", "data_csv", "source_sha256"))
    if (!all(vapply(b[c("id", "study_id")], .iw_label, logical(1))) || !b$omics %in% .iw_omics || !b$scale %in% c("unknown", "raw_counts", "processed")) stop("Declare study, modality and data scale for every matrix")
    if (b$id %in% names(mats)) stop("Duplicate matrix ID")
    if (!is.character(b$data_csv) || length(b$data_csv) != 1L || nchar(b$data_csv, type = "bytes") > 12 * 1024^2 || !grepl("^[a-f0-9]{64}$", b$source_sha256)) stop("Bounded matrix and source checksum required")
    tab <- utils::read.table(text = b$data_csv, header = TRUE, sep = if (grepl("\t", strsplit(b$data_csv, "\n", fixed = TRUE)[[1]][1], fixed = TRUE)) "\t" else ",", check.names = FALSE, colClasses = "character", na.strings = NULL, comment.char = "", quote = "\"", fill = FALSE)
    if (nrow(tab) < 2L || nrow(tab) > 50000L || ncol(tab) < 4L || ncol(tab) > 257L) stop("Each feature-by-sample matrix needs 2-50000 features and 3-256 samples")
    ids <- tab[[1]]; samples <- names(tab)[-1]
    if (anyNA(ids) || any(!nzchar(trimws(ids))) || anyDuplicated(ids) || anyDuplicated(samples) || !all(vapply(samples, .iw_label, logical(1)))) stop("Unique, nonempty feature IDs and sample columns required")
    raw <- as.matrix(tab[-1]); missing <- is.na(raw) | trimws(raw) %in% c("", "NA", "NaN")
    numeric <- suppressWarnings(matrix(as.numeric(raw), nrow = nrow(raw), dimnames = list(ids, samples)))
    if (any(!missing & !is.finite(numeric))) stop("Nonnumeric or infinite values found; exclude annotation columns before upload")
    numeric[missing] <- NA_real_; mats[[b$id]] <- numeric
    cells <- cells + length(numeric); if (cells > 1000000L) stop("Integration input exceeds 1000000 cells")
    info[[b$id]] <- list(id = b$id, study_id = b$study_id, omics = b$omics, scale = b$scale, declared_source_sha256 = b$source_sha256, input_sha256 = digest::digest(enc2utf8(b$data_csv), algo = "sha256", serialize = FALSE), features = nrow(numeric), samples = as.list(samples), missing_values = sum(missing))
  }
  if (!require_mapping) return(list(matrices = mats, info = info))
  if (!isTRUE(payload$preprocessing_reviewed) || any(vapply(info, function(b) b$scale != "processed", logical(1)))) stop("Review modality-specific preprocessing and declare processed matrices; raw counts/unknown scales cannot enter joint exploration")
  if (!isTRUE(payload$design_reviewed)) stop("Review that mappings identify the same independent biological units, with no unmodelled batch or repeated-measure design")
  mapping <- payload$mapping
  if (!is.list(mapping) || length(mapping) > 2048L) stop("Explicit sample mapping required")
  for (row in mapping) {
    .iw_fields(row, c("block", "column", "subject", "group"))
    if (!all(vapply(row, .iw_label, logical(1))) || !row$block %in% names(mats) || !row$column %in% colnames(mats[[row$block]])) stop("Every mapping row needs a valid matrix, column, subject and group")
  }
  key <- vapply(mapping, function(x) paste(match(x$block, names(mats)), x$column, sep = "\r"), character(1))
  if (anyDuplicated(key) || length(key) != sum(vapply(mats, ncol, integer(1)))) stop("Map every sample column exactly once")
  subject_sets <- list(); groups <- list()
  for (id in names(mats)) {
    rows <- Filter(function(row) identical(row$block, id), mapping)
    columns <- vapply(rows, `[[`, character(1), "column"); subjects <- vapply(rows, `[[`, character(1), "subject")
    if (!setequal(columns, colnames(mats[[id]])) || anyDuplicated(subjects)) stop("Repeated subjects within one matrix require a specialist model")
    for (row in rows) {if (!is.null(groups[[row$subject]]) && groups[[row$subject]] != row$group) stop("Conflicting group labels for the same biological unit"); groups[[row$subject]] <- row$group}
    colnames(mats[[id]]) <- subjects[match(colnames(mats[[id]]), columns)];subject_sets[[id]] <- subjects
  }
  common <- Reduce(intersect, subject_sets)
  if (length(common) < 4L) stop("Fewer than four explicitly matched biological units; independent cohorts cannot be paired for sample-level integration")
  unmatched <- lapply(subject_sets, setdiff, y = common)
  if (any(lengths(unmatched) > 0L) && !isTRUE(payload$allow_unmatched)) stop("Unmatched subjects found. Review the exclusions and explicitly allow their exclusion")
  if (!payload$missing_policy %in% c("reject", "exclude_features")) stop("Select an explicit missing-value policy")
  exclusions <- list()
  for (id in names(mats)) {
    m <- mats[[id]][, common, drop = FALSE]; bad <- rowSums(is.na(m)) > 0L
    if (any(bad) && payload$missing_policy == "reject") stop("Missing measurements remain; choose an explicit exclusion policy or preprocess separately")
    incomplete <- rownames(m)[bad];m <- m[!bad, , drop = FALSE]
    constant <- if (nrow(m)) apply(m, 1L, stats::sd) == 0 else logical()
    exclusions[[id]] <- list(unmatched_subjects = as.list(unmatched[[id]]), incomplete_features = as.list(incomplete), constant_features = as.list(rownames(m)[constant]))
    m <- m[!constant, , drop = FALSE];if (nrow(m) < 2L) stop("Fewer than two complete variable features in a block")
    mats[[id]] <- m
  }
  list(matrices = mats, info = info, subjects = common, groups = groups, exclusions = exclusions)
}

emp_iw_preview <- function(payload) {
  parsed <- emp_iw_validate(payload, FALSE)
  list(success = TRUE, blocks = unname(parsed$info), analysis_executed = FALSE)
}

emp_iw_compute <- function(payload, progress = function(...) NULL) {
  x <- emp_iw_validate(payload); progress(15, "Validated explicit sample mapping")
  # Equal total variance per block after feature standardization; this is exploratory PCA, not MOFA/DIABLO.
  scaled <- lapply(x$matrices, function(m) scale(t(m), center = TRUE, scale = TRUE) / sqrt(nrow(m)))
  combined <- do.call(cbind, scaled);fit <- stats::prcomp(combined, center = FALSE, scale. = FALSE, rank. = 2L)
  scores <- data.frame(subject = x$subjects, group = vapply(x$subjects, function(s) x$groups[[s]], character(1)), PC1 = fit$x[, 1], PC2 = fit$x[, 2], check.names = FALSE)
  progress(40, "Computed block-balanced exploratory PCA")
  # Test a bounded, declared variance-selected set with the correct complete-pair n for every test.
  top <- lapply(x$matrices, function(m) m[head(order(apply(m, 1, stats::var), decreasing = TRUE), 20L), , drop = FALSE])
  edges <- list();ids <- names(top)
  for (i in seq_len(length(ids) - 1L)) for (j in seq.int(i + 1L, length(ids))) {
    a <- top[[i]];b <- top[[j]]
    for (u in seq_len(nrow(a))) for (v in seq_len(nrow(b))) {
      test <- suppressWarnings(stats::cor.test(a[u, ], b[v, ], method = "spearman", exact = FALSE))
      edges[[length(edges) + 1L]] <- data.frame(block_a = ids[i], feature_a = rownames(a)[u], block_b = ids[j], feature_b = rownames(b)[v], n = length(x$subjects), rho = unname(test$estimate), pvalue = test$p.value)
    }
  }
  edges <- do.call(rbind, edges);edges$padj <- stats::p.adjust(edges$pvalue, "BH");edges <- edges[order(edges$padj, edges$pvalue), ]
  progress(90, "Recorded all tested associations and explicit exclusions")
  list(contract = "emp-integration-exploration-v1", execution_performed = TRUE, method = "Feature z-score, block-balanced PCA; cross-block Spearman with exact=FALSE and global BH over tested pairs", blocks = unname(x$info), sample_mapping = payload$mapping, exclusions = x$exclusions,
       scores = scores, variance_explained = as.list((fit$sdev^2 / sum(fit$sdev^2))[1:2]), associations = edges,
       preprocessing = list(missing_policy = payload$missing_policy, imputation = FALSE, top_features_per_block_for_associations = 20L),
       limitations = c("Exploratory association, not causation or predictive validation", "No batch correction, repeated-measure modelling, differential analysis, cross-cohort meta-analysis or feature annotation mapping", "Clinical matrices must contain reviewed numeric variables; compositional microbiome data require suitable preprocessing", "Groups are displayed only; there is no differential group test"),
       r_version = as.character(getRversion()), stats_version = as.character(utils::packageVersion("stats")), created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
}

emp_iw_submit <- function(payload, owner_id) {
  if (!isTRUE(payload$confirmed)) stop("Review and confirm this integration analysis")
  emp_iw_validate(payload)
  id <- submit_job("integration_exploration", function(payload, on_progress) emp_iw_compute(payload, on_progress), args = list(payload = payload), owner_id = owner_id)
  list(success = TRUE, job_id = id, kind = "integration_exploration")
}
