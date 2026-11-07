#!/usr/bin/env Rscript
# Reproduce an exported workbench input. Always writes to a new directory.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Usage: Rscript webapp/scripts/run_count_workflow.R INPUT.json NEW_OUTPUT_DIR")
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1]])
source(file.path(dirname(normalizePath(script)), "../backend/helpers/omics_workbench.R"))
if (file.exists(args[[2]])) stop("Output already exists; choose a new output directory")
payload <- jsonlite::fromJSON(args[[1]], simplifyVector = FALSE)
if (!is.null(payload$prepared_input)) payload <- payload$prepared_input
result <- emp_wb_compute(payload, function(pct, message) cat(sprintf("%d%% %s\n", pct, message)))
if (!dir.create(args[[2]], recursive = TRUE)) stop("Cannot create output directory")
saveRDS(result, file.path(args[[2]], "results.rds"))
writeLines(jsonlite::toJSON(result, auto_unbox = TRUE, na = "null", null = "null", pretty = TRUE, digits = NA), file.path(args[[2]], "results.json"))
items <- result$artifacts$differentials
if (is.null(items) && !is.null(result$artifacts$differential)) items <- list(result$artifacts$differential)
manifest <- list()
for (i in seq_along(items)) {
  item <- items[[i]]; rows <- item$rows
  table <- do.call(rbind, lapply(rows, function(row) as.data.frame(lapply(row, function(x) if (is.null(x)) NA else x), stringsAsFactors = FALSE)))
  name <- if (length(items) == 1L) paste0(tolower(item$method), ".tsv") else sprintf("contrast-%02d-%s.tsv", i, tolower(item$method))
  utils::write.table(table, file.path(args[[2]], name), sep = "\t", quote = TRUE, row.names = FALSE, na = "")
  manifest[[i]] <- list(file = name, method = item$method, test = item$test, reference = item$reference)
}
if (length(manifest)) writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(args[[2]], "contrasts.json"))
cat("Results saved in", normalizePath(args[[2]]), "\n")
