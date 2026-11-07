# Base-R contract test. No biological computation, packages, or server needed.
source("webapp/backend/helpers/workflow_transcriptomics.R")
tx_stop_if_missing <- function(...) invisible(NULL)
called <- character()
run_diff <- function(session_id, experiment, method, ...) {
  called <<- c(called, method)
  stop("intentional method failure")
}
error <- tryCatch(tx_run_differential("test", "test", "DESeq2"), error = identity)
stopifnot(inherits(error, "error"), identical(called, "DESeq2"),
          grepl("intentional method failure", conditionMessage(error), fixed = TRUE))
called <- character()
run_diff <- function(session_id, experiment, method, ...) {
  called <<- c(called, method)
  list(method = method)
}
result <- tx_run_differential("test", "test", "limma")
stopifnot(identical(called, "limma"), identical(result$method, "limma"))
cat("Transcriptomics method contract passed; no fallback performed.\n")
