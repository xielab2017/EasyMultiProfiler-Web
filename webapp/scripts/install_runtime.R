#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
fail_fast <- "--fail-fast" %in% args

msg <- function(...) cat(sprintf(...), "\n")

install_cran <- function(pkgs) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
  if (!length(missing)) return(invisible(TRUE))
  msg("[CRAN] Installing: %s", paste(missing, collapse = ", "))
  install.packages(missing, dependencies = TRUE)
}

install_bioc <- function(pkgs) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
  if (!length(missing)) return(invisible(TRUE))
  if (!requireNamespace("BiocManager", quietly = TRUE)) {
    install.packages("BiocManager")
  }
  msg("[BIOC] Installing: %s", paste(missing, collapse = ", "))
  BiocManager::install(missing, ask = FALSE, update = FALSE)
}

safe <- function(expr, label) {
  tryCatch(expr, error = function(e) {
    msg("[ERROR] %s failed: %s", label, conditionMessage(e))
    if (isTRUE(fail_fast)) stop(e)
  })
}

options(timeout = max(600L, getOption("timeout", 60L)))
msg("=== EasyMultiProfiler web runtime installer ===")

cran_pkgs <- c(
  "plumber", "jsonlite", "base64enc", "matrixStats", "pheatmap",
  "ggplot2", "gtsummary", "dplyr", "tidyr", "stringr", "purrr",
  "tibble", "readr", "psych", "callr", "ragg", "DT"
)

bioc_pkgs <- c(
  "Biobase", "S4Vectors", "SummarizedExperiment", "MultiAssayExperiment",
  "WGCNA", "clusterProfiler", "org.Hs.eg.db", "org.Mm.eg.db"
)

safe(install_cran(cran_pkgs), "CRAN dependency install")
safe(install_bioc(bioc_pkgs), "Bioconductor dependency install")

if (!requireNamespace("remotes", quietly = TRUE)) {
  safe(install.packages("remotes"), "Install remotes")
}

safe({
  if (!requireNamespace("EasyMultiProfiler", quietly = TRUE)) {
    msg("[GITHUB] Installing EasyMultiProfiler from liubingdong/EasyMultiProfiler")
    remotes::install_github("liubingdong/EasyMultiProfiler", upgrade = "never", dependencies = TRUE)
  } else {
    msg("[OK] EasyMultiProfiler already installed.")
  }
}, "Install EasyMultiProfiler")

needed <- c("EasyMultiProfiler", "plumber", "gtsummary", "clusterProfiler", "WGCNA")
missing_final <- needed[!vapply(needed, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]

if (length(missing_final)) {
  msg("[WARN] Missing after install: %s", paste(missing_final, collapse = ", "))
  quit(status = 2)
}

msg("[DONE] Runtime dependencies look good.")
