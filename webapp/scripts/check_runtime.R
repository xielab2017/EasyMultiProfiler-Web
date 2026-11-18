# Check the same package library order used by run_api.R.
root <- commandArgs(trailingOnly = TRUE)[[1L]]
local_lib <- file.path(root, ".local_run", "R_libs")
if (dir.exists(local_lib)) .libPaths(c(local_lib, .libPaths()))

expected <- read.dcf(file.path(root, "DESCRIPTION"), fields = "Version")[1L, 1L]
required <- c("EasyMultiProfiler", "plumber", "jsonlite", "base64enc", "callr", "digest", "ps")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  cat("Missing R packages:", paste(missing, collapse = ", "), "\n")
}
mismatch <- FALSE
if ("EasyMultiProfiler" %in% loadedNamespaces()) {
  loaded <- getNamespaceVersion("EasyMultiProfiler")
  mismatch <- package_version(loaded) != package_version(expected)
  if (mismatch) {
    cat(sprintf("EasyMultiProfiler version mismatch: loaded %s, checkout requires %s.\n", loaded, expected))
  }
}
quit(status = as.integer(length(missing) > 0L || mismatch))
