# Real R/DESeq2 numerical acceptance. Input must be an explicitly synthetic fixture.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Provide a prepared synthetic fixture JSON")
source("webapp/backend/helpers/omics_workbench.R")
payload <- jsonlite::fromJSON(args[[1]], simplifyVector = FALSE)
validated <- emp_wb_validate(payload)
actual <- emp_wb_compute(payload)
stopifnot(actual$success, actual$execution_performed, !actual$raw_count_provenance_verified)
stopifnot(identical(vapply(actual$steps, `[[`, character(1), "operation"), c("qc", "normalize", "pca", "deseq2", "heatmap")))
counts <- validated$counts
plan <- validated$plan
p <- plan$steps[[4]]$parameters
keep <- rowSums(counts >= p$min_count) >= p$min_samples
group <- factor(vapply(validated$samples, `[[`, character(1), "group"), levels = c(plan$design$reference, plan$design$test))
dds <- DESeq2::DESeqDataSetFromMatrix(counts[keep, , drop = FALSE], data.frame(group, row.names = colnames(counts)), ~group)
dds <- DESeq2::DESeq(dds, parallel = FALSE, quiet = TRUE)
expected <- as.data.frame(DESeq2::results(dds, contrast = c("group", plan$design$test, plan$design$reference), alpha = p$alpha, pAdjustMethod = "BH"))
rows <- actual$artifacts$differential$rows
observed <- do.call(rbind, lapply(rows, function(x) as.data.frame(lapply(x, function(v) if (is.null(v)) NA else v))))
stopifnot(identical(observed$feature_id, rownames(expected)))
# Statistics retain full floating precision through JSON, including small p-values.
for (column in c("baseMean", "log2FoldChange", "lfcSE", "stat", "pvalue", "padj")) {
  stopifnot(identical(is.na(observed[[column]]), is.na(expected[[column]])))
  stopifnot(isTRUE(all.equal(observed[[column]], expected[[column]], tolerance = 1e-12)))
}
stopifnot(actual$artifacts$differential$positive_log2fc == "test / reference")
stopifnot(length(actual$artifacts$pca$scores) == ncol(counts), length(actual$artifacts$heatmap$values) == plan$steps[[5]]$parameters$top_n)
reject <- function(changed) stopifnot(inherits(try(emp_wb_validate(changed), silent = TRUE), "try-error"))
bad <- payload; bad$matrix_csv <- sub('"[0-9]+"', '"-1"', payload$matrix_csv); reject(bad)
bad <- payload; bad$plan_sha256 <- paste(rep("0", 64), collapse = ""); reject(bad)
for (change in c("type", "paired", "order", "groups", "parameter", "code", "missing")) {
  bad <- payload; p <- jsonlite::fromJSON(payload$plan_json, simplifyVector = FALSE)
  if (change == "type") p$data_type <- "tpm"
  if (change == "paired") p$samples[[1]]$subject <- "one"
  if (change == "order") p$steps <- p$steps[c(1, 3, 2, 4, 5)]
  if (change == "groups") p$design$reference <- p$design$test
  if (change == "parameter") p$steps[[4]]$parameters$min_samples <- 999
  if (change == "code") p$code <- "stop()"
  if (change == "missing") p$samples <- p$samples[-1]
  bad$plan_json <- jsonlite::toJSON(p, auto_unbox = TRUE, null = "null")
  bad$plan_sha256 <- digest::digest(as.character(bad$plan_json), algo = "sha256", serialize = FALSE)
  reject(bad)
}
cat(sprintf("PASS: real DESeq2 comparison; %d samples, %d input features, %d tested features; all operation and input guards passed.\n", ncol(counts), nrow(counts), nrow(expected)))
