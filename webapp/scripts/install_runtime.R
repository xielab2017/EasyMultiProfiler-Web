#!/usr/bin/env Rscript
# install_runtime.R — install CRAN + Bioconductor + EMP dependencies.
#
# Reads the repo's DESCRIPTION (auto-discovered) and installs every
# Imports / Suggests package the platform needs, with R-version-aware
# Bioconductor handling (so it works for R 4.3 / 4.4 / 4.5 ...).
#
# Honours:
#   --fail-fast            abort on the first error (otherwise we keep
#                          going and report a final summary)
#   --with-suggests        also install Suggests (default: only Imports +
#                          LinkingTo; Suggests are loaded lazily and we
#                          don't want to drag a 2nd wave of installs
#                          unless the user opts in)
#   --no-emp               skip installing the EMP package itself
#
# Environment variables:
#   EMP_CRAN_MIRROR        CRAN mirror (default: https://cloud.r-project.org)
#   EMP_BIOC_MIRROR        Bioconductor mirror (default: https://bioconductor.org)
#   EMP_BIOC_VERSION       pin Bioc version (otherwise auto-detected from R)

args <- commandArgs(trailingOnly = TRUE)
fail_fast    <- "--fail-fast" %in% args
with_suggests <- "--with-suggests" %in% args
no_emp       <- "--no-emp" %in% args

msg <- function(...) cat(sprintf(...), "\n")

# ── repo + mirror setup ──────────────────────────────────────────────────
.emp_repo_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", args, value = TRUE)
  script <- if (length(fa)) sub("^--file=", "", fa[1]) else NA_character_
  if (!is.na(script) && nzchar(script)) {
    script <- gsub("~\\+~", " ", script)
    root <- normalizePath(file.path(dirname(script), "../.."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(root, "DESCRIPTION"))) return(root)
  }
  # Fallback: walk up from cwd until we see DESCRIPTION.
  wd <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  for (i in 0:5) {
    p <- file.path(wd, paste(rep("..", i), collapse = "/"), "DESCRIPTION")
    if (file.exists(p)) {
      return(normalizePath(file.path(wd, paste(rep("..", i), collapse = "/")), winslash = "/", mustWork = FALSE))
    }
  }
  wd
}

emp_root <- .emp_repo_root()
desc_path <- file.path(emp_root, "DESCRIPTION")

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

safe <- function(expr, label) {
  tryCatch(expr, error = function(e) {
    msg("[ERROR] %s failed: %s", label, conditionMessage(e))
    if (isTRUE(fail_fast)) stop(e)
  })
}

# ── Read DESCRIPTION with base R, no need for `desc` package ─────────────
parse_deps <- function(path) {
  raw <- read.dcf(path)
  fields <- colnames(raw)
  out <- data.frame(
    package = character(),
    version = character(),
    type    = character(),
    stringsAsFactors = FALSE
  )
  field_map <- c(
    "Depends"   = "Depends",
    "Imports"   = "Imports",
    "LinkingTo" = "LinkingTo",
    "Suggests"  = "Suggests",
    "Enhances"  = "Enhances"
  )
  for (i in seq_along(field_map)) {
    field <- field_map[[i]]
    type  <- names(field_map)[i]
    if (!(field %in% fields)) next
    val <- raw[, field]
    if (!nzchar(val)) next
    pkgs <- strsplit(val, ",", fixed = TRUE)[[1]]
    for (p in pkgs) {
      p <- trimws(p)
      if (!nzchar(p)) next
      m <- regmatches(p, regexec("^([A-Za-z][A-Za-z0-9.]*)\\s*\\(([^)]*)\\)", p))[[1]]
      if (length(m) == 3) {
        out <- rbind(out, data.frame(package = m[2], version = m[3], type = type, stringsAsFactors = FALSE))
      } else {
        out <- rbind(out, data.frame(package = p, version = "*", type = type, stringsAsFactors = FALSE))
      }
    }
  }
  # Strip R's base + recommended packages — they're always present.
  base_pkgs <- c(
    "base", "compiler", "datasets", "graphics", "grDevices", "grid",
    "methods", "parallel", "splines", "stats", "stats4", "tcltk",
    "tools", "utils"
  )
  out <- out[!(out$package %in% base_pkgs), , drop = FALSE]
  out <- out[!duplicated(out$package), , drop = FALSE]
  out
}

# ── Which packages belong to Bioconductor? ──────────────────────────────
# We classify each package by name. EMP's deps are stable so a curated
# list is faster + more reliable than a network round-trip to
# BiocManager::available() (which can stall on first run).
bioc_names <- c(
  "Biobase", "BiocGenerics", "BiocManager", "BiocParallel", "BiocVersion",
  "S4Vectors", "IRanges", "GenomicRanges", "SummarizedExperiment",
  "MultiAssayExperiment", "DESeq2", "edgeR", "limma", "DOSE",
  "clusterProfiler", "enrichplot", "ggtree", "impute", "qvalue",
  "tidybulk", "WGCNA", "biomformat", "phyloseq", "ReactomePA",
  "AnnotationDbi", "org.Hs.eg.db", "org.Mm.eg.db", "gson", "sva",
  "ropls", "ComplexHeatmap", "SingleCellExperiment", "TreeSummarizedExperiment",
  "microbiome", "Maaslin2", "ALDEx2", "ANCOMBC", "GenomeInfoDb",
  "GenomicFeatures", "GOSemSim", "meshes", "pathview",
  "topGO", "gage", "fgsea", "GSEABase", "TxDb", "GenomicAlignments",
  "Rsamtools", "ShortRead", "ChIPseeker", "HDF5Array", "rhdf5",
  "BioCircos", "MEAL", "LOLA", "RegioneR", "bumphunter", "minfi",
  "missMethyl", "methylKit"
)

is_bioc_package <- function(pkg) {
  pkg %in% bioc_names
}

install_cran <- function(pkgs) {
  pkgs <- unique(pkgs[!vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))])
  if (!length(pkgs)) return(invisible(TRUE))
  msg("[CRAN] Installing %d: %s", length(pkgs), paste(pkgs, collapse = ", "))
  install.packages(pkgs, dependencies = TRUE, Ncpus = max(1L, parallel::detectCores() - 1L))
}

install_bioc <- function(pkgs) {
  pkgs <- unique(pkgs[!vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))])
  if (!length(pkgs)) return(invisible(TRUE))
  if (!requireNamespace("BiocManager", quietly = TRUE)) {
    install.packages("BiocManager")
  }
  msg("[BIOC] Installing %d: %s", length(pkgs), paste(pkgs, collapse = ", "))
  BiocManager::install(pkgs, ask = FALSE, update = FALSE, Ncpus = max(1L, parallel::detectCores() - 1L))
}

# ── Begin ───────────────────────────────────────────────────────────────
options(timeout = max(900L, getOption("timeout", 60L)))
set_default_repos()
msg("=== EasyMultiProfiler web runtime installer ===")
msg("[REPO] EMP root: %s", emp_root)
msg("[REPO] CRAN mirror: %s", getOption("repos")[["CRAN"]])
msg("[REPO] Bioconductor mirror: %s", getOption("BioC_mirror"))
msg("[REPO] R %s, %s", getRversion(), .Platform$OS.type)

deps <- parse_deps(desc_path)
if (!nrow(deps)) {
  msg("[ERROR] Could not parse DESCRIPTION at %s", desc_path)
  quit(status = 1)
}
msg("[REPO] Parsed %d dependencies from DESCRIPTION", nrow(deps))

# Optional Bioc-version pin (useful for CI).
if (nzchar(Sys.getenv("EMP_BIOC_VERSION"))) {
  options(BiocManager.suggests = FALSE)
  # BiocManager::install(version=...) will set the version for this session
  if (requireNamespace("BiocManager", quietly = TRUE)) {
    BiocManager::install(version = Sys.getenv("EMP_BIOC_VERSION"), ask = FALSE)
  }
}

# Install CRAN first, then Bioconductor (Bioc packages depend on CRAN).
imports <- deps[deps$type %in% c("Imports", "LinkingTo"), , drop = FALSE]
suggests <- deps[deps$type == "Suggests", , drop = FALSE]

msg("[STEP] Classifying %d packages into CRAN vs Bioconductor…", nrow(imports))
imports$is_bioc <- vapply(imports$package, is_bioc_package, logical(1))

cran_list <- imports$package[!imports$is_bioc]
bioc_list <- imports$package[imports$is_bioc]
# Force some always-Bioc packages that might be misclassified by
# BiocManager::available() during the very first install (before
# Bioconductor data is cached).
always_bioc <- c("BiocManager")
bioc_list <- unique(c(bioc_list, always_bioc))
cran_list <- setdiff(cran_list, bioc_list)

# CRAN glue packages that are universally useful and that we always
# want in EMP web runtime, even if DESCRIPTION doesn't strictly require
# them as Imports.
cran_always <- c("remotes")
cran_list <- unique(c(cran_list, cran_always))

msg("[PLAN] CRAN: %d   Bioconductor: %d", length(cran_list), length(bioc_list))

safe(install_cran(cran_list), "CRAN dependency install")
safe(install_bioc(bioc_list), "Bioconductor dependency install")

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

# Optional: install Suggests (--with-suggests). Heavy but useful for
# docs / vignettes.
if (with_suggests && nrow(suggests)) {
  suggests$is_bioc <- vapply(suggests$package, is_bioc_package, logical(1))
  cran_sugg <- suggests$package[!suggests$is_bioc]
  bioc_sugg <- suggests$package[suggests$is_bioc]
  msg("[STEP] Suggests — CRAN: %d   Bioconductor: %d", length(cran_sugg), length(bioc_sugg))
  safe(install_cran(cran_sugg), "CRAN suggests install")
  safe(install_bioc(bioc_sugg), "Bioconductor suggests install")
}

# EMP itself
if (!no_emp) {
  if (!requireNamespace("remotes", quietly = TRUE)) {
    safe(install.packages("remotes"), "Install remotes")
  }
  if (file.exists(desc_path)) {
    msg("[LOCAL] Installing EasyMultiProfiler from repo: %s", emp_root)
    safe(
      remotes::install_local(emp_root, upgrade = "never", dependencies = TRUE, force = TRUE),
      "Install EasyMultiProfiler (local)"
    )
  } else {
    msg("[GITHUB] Installing EasyMultiProfiler from liubingdong/EasyMultiProfiler")
    safe(
      remotes::install_github("liubingdong/EasyMultiProfiler", upgrade = "never", dependencies = TRUE),
      "Install EasyMultiProfiler (GitHub)"
    )
  }
}

# Final smoke check
needed <- c("EasyMultiProfiler", "plumber", "clusterProfiler")
missing_final <- needed[!vapply(needed, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
if (length(missing_final)) {
  msg("[WARN] Missing after install: %s", paste(missing_final, collapse = ", "))
  quit(status = 2)
}

msg("[DONE] Runtime dependencies look good.")
msg("[NEXT] Start the web app with: bash webapp/scripts/launch_emp_web.sh")
