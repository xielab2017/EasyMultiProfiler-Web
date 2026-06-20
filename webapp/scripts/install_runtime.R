#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
fail_fast <- "--fail-fast" %in% args

msg <- function(...) cat(sprintf(...), "\n")
set_default_repos <- function() {
  repos <- getOption("repos")
  if (is.null(repos) || !length(repos)) repos <- c(CRAN = "@CRAN@")
  if (identical(unname(repos["CRAN"]), "@CRAN@") || is.na(repos["CRAN"]) || !nzchar(repos["CRAN"])) {
    repos["CRAN"] <- Sys.getenv("EMP_CRAN_MIRROR", unset = "https://cloud.r-project.org")
  }
  options(repos = repos)
  if (!nzchar(Sys.getenv("BIOCONDUCTOR_CONFIG_FILE", ""))) {
    options(BioC_mirror = Sys.getenv("EMP_BIOC_MIRROR", unset = "https://bioconductor.org"))
  }
}

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
set_default_repos()
msg("=== EasyMultiProfiler web runtime installer ===")
msg("[REPO] CRAN mirror: %s", getOption("repos")[["CRAN"]])

cran_pkgs <- c(
  "plumber", "jsonlite", "base64enc", "matrixStats", "pheatmap",
  "ggplot2", "gtsummary", "dplyr", "tidyr", "stringr", "purrr",
  "tibble", "readr", "psych", "callr", "ragg", "DT", "patchwork",
  "ggrepel", "RColorBrewer", "vegan", "ape", "igraph", "randomForest",
  "xgboost", "glmnet", "survival", "remotes"
)

bioc_pkgs <- c(
  "Biobase", "S4Vectors", "SummarizedExperiment", "MultiAssayExperiment",
  "DESeq2", "edgeR", "limma", "WGCNA", "clusterProfiler", "enrichplot",
  "org.Hs.eg.db", "org.Mm.eg.db", "BiocManager"
)

safe(install_cran(cran_pkgs), "CRAN dependency install")
safe(install_bioc(bioc_pkgs), "Bioconductor dependency install")

# patchwork 1.2.x is required by some EMP plots (see tutorial_related/Installation.md)
safe({
  if (requireNamespace("patchwork", quietly = TRUE)) {
    pv <- as.character(packageVersion("patchwork"))
    if (package_version(pv) > "1.2.0") {
      msg("[CRAN] Downgrading patchwork to 1.2.0 (EMP compatibility)")
      remotes::install_version("patchwork", version = "1.2.0", upgrade = "never")
    }
  }
}, "patchwork pin")

if (!requireNamespace("remotes", quietly = TRUE)) {
  safe(install.packages("remotes"), "Install remotes")
}

.emp_repo_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", args, value = TRUE)
  script <- if (length(fa)) sub("^--file=", "", fa[1]) else NA_character_
  if (!is.na(script) && nzchar(script)) {
    script <- gsub("~\\+~", " ", script)
    root <- normalizePath(file.path(dirname(script), "../.."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(root, "DESCRIPTION"))) return(root)
  }
  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}

safe({
  emp_root <- .emp_repo_root()
  local_desc <- file.path(emp_root, "DESCRIPTION")
  if (file.exists(local_desc)) {
    msg("[LOCAL] Installing EasyMultiProfiler from repo: %s", emp_root)
    remotes::install_local(emp_root, upgrade = "never", dependencies = TRUE, force = FALSE)
  } else if (!requireNamespace("EasyMultiProfiler", quietly = TRUE)) {
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
