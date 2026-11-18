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

# Match run_api.R: a project-local library avoids administrator-owned R paths.
runtime_lib <- file.path(emp_root, ".local_run", "R_libs")
if (!dir.exists(runtime_lib)) dir.create(runtime_lib, recursive = TRUE, showWarnings = FALSE)
if (!dir.exists(runtime_lib) || file.access(runtime_lib, 2L) != 0L) {
  stop("Project R library is not writable: ", runtime_lib)
}
runtime_lib <- normalizePath(runtime_lib, winslash = "/", mustWork = TRUE)
.libPaths(c(runtime_lib, .libPaths()))
Sys.setenv(R_LIBS_USER = runtime_lib)

set_default_repos <- function() {
  repos <- getOption("repos")
  if (is.null(repos) || !length(repos)) repos <- c(CRAN = "@CRAN@")
  mirror <- Sys.getenv("EMP_CRAN_MIRROR")
  if (nzchar(mirror)) {
    repos["CRAN"] <- mirror
  } else if (identical(unname(repos["CRAN"]), "@CRAN@") || is.na(repos["CRAN"]) || !nzchar(repos["CRAN"])) {
    repos["CRAN"] <- "https://cloud.r-project.org"
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

# BiocManager resolves both CRAN and Bioconductor dependencies against
# repositories compatible with the selected R version.
install_deps <- function(pkgs) {
  if (!length(pkgs)) return(invisible(TRUE))
  if (!requireNamespace("BiocManager", quietly = TRUE)) {
    install.packages("BiocManager", lib = runtime_lib)
  }
  version <- Sys.getenv("EMP_BIOC_VERSION")
  args <- list(pkgs = pkgs, lib = runtime_lib, ask = FALSE, update = FALSE,
               dependencies = NA, Ncpus = max(1L, parallel::detectCores() - 1L))
  if (nzchar(version)) args$version <- version
  do.call(BiocManager::install, args)
}

meets_requirement <- function(package, constraint) {
  # Avoid loading packages while deciding which ones must be replaced.
  # Windows keeps a loaded package DLL locked until the R process exits.
  installed <- tryCatch(as.character(packageVersion(package)), error = function(e) NULL)
  if (is.null(installed)) return(FALSE)
  if (constraint == "*") return(TRUE)
  match <- regmatches(constraint, regexec("^(>=|<=|==|>|<)\\s*(.+)$", constraint))[[1L]]
  if (length(match) != 3L) stop("Unrecognized version constraint: ", constraint)
  observed <- utils::compareVersion(installed, match[3L])
  switch(match[2L], ">=" = observed >= 0L, "<=" = observed <= 0L,
         "==" = observed == 0L, ">" = observed > 0L, "<" = observed < 0L)
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

fields <- c("Imports", "LinkingTo", if (with_suggests) "Suggests")
requested <- deps[deps$type %in% fields, , drop = FALSE]
cran_always <- c("plumber", "jsonlite", "base64enc", "callr", "digest", "ps")
plot_packages <- c("svglite", "pheatmap")
requested <- rbind(requested, data.frame(package = c(cran_always, plot_packages), version = "*", type = "Web"))
satisfied <- function() mapply(meets_requirement, requested$package, requested$version)
missing <- unique(requested$package[!satisfied()])
if (length(missing)) {
  msg("[PLAN] Installing %d dependencies: %s", length(missing), paste(missing, collapse = ", "))
  safe(install_deps(missing), "Runtime dependencies")
  missing <- unique(requested$package[!satisfied()])
  if (length(missing)) {
    msg("[ERROR] Missing or incompatible packages: %s", paste(missing, collapse = ", "))
    quit(status = 2)
  }
}

if (!no_emp) {
  msg("[LOCAL] Installing EasyMultiProfiler from repo: %s", emp_root)
  # Install this checkout directly, without copying its project library into
  # a temporary source tree or installing every suggested package.
  # R CMD INSTALL returns a nonzero exit status on failure even if the
  # package manager restored an older copy into the destination library.
  r <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R")
  status <- system2(r, c("CMD", "INSTALL", shQuote(paste0("--library=", runtime_lib)), shQuote(emp_root)))
  if (status != 0L) stop("Local EasyMultiProfiler installation failed (exit ", status, ")")
  expected <- read.dcf(desc_path, fields = "Version")[[1L]]
  found <- packageDescription("EasyMultiProfiler", lib.loc = runtime_lib, fields = "Version")
  if (!identical(found, expected)) stop("Expected EasyMultiProfiler ", expected, " in ", runtime_lib)
}

# Final smoke check
needed <- c(if (!no_emp) "EasyMultiProfiler", cran_always, "clusterProfiler")
missing_final <- needed[!vapply(needed, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
if (length(missing_final)) {
  msg("[WARN] Missing after install: %s", paste(missing_final, collapse = ", "))
  quit(status = 2)
}

msg("[DONE] Runtime dependencies look good.")
msg("[NEXT] Start the web app with: bash webapp/scripts/launch_emp_web.sh")
