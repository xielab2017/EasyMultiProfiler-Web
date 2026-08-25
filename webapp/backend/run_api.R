#!/usr/bin/env Rscript
# Entry point: start the Plumber REST API

# Path to plumber.R (same directory as this script)
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg) > 0) sub("^--file=", "", file_arg[1]) else NA_character_

if (is.na(script_path) || !nzchar(script_path)) {
  script_path <- tryCatch(sys.frames()[[1]]$ofile, error = function(e) NA_character_)
}

if (is.na(script_path) || !nzchar(script_path)) {
  script_dir <- getwd()
} else {
  # Some launchers encode spaces as "~+~" in --file paths.
  script_path <- gsub("~\\+~", " ", script_path)
  script_dir <- dirname(normalizePath(script_path, winslash = "/", mustWork = FALSE))
}

if (length(script_dir) == 0 || !nzchar(script_dir)) {
  script_dir <- getwd()
}

# Prepend project-local R libs (.local_run/R_libs) before package loads so
# DiffBind / dplyr etc. resolve even when the launcher forgot R_LIBS.
repo_root <- normalizePath(file.path(script_dir, "..", ".."), winslash = "/", mustWork = FALSE)
local_r_libs <- file.path(repo_root, ".local_run", "R_libs")
if (dir.exists(local_r_libs)) {
  local_r_libs <- normalizePath(local_r_libs, winslash = "/", mustWork = FALSE)
  .libPaths(c(local_r_libs, .libPaths()))
  cur_r_libs <- Sys.getenv("R_LIBS", unset = "")
  if (!nzchar(cur_r_libs) || !grepl(local_r_libs, cur_r_libs, fixed = TRUE)) {
    Sys.setenv(R_LIBS = if (nzchar(cur_r_libs)) paste(local_r_libs, cur_r_libs, sep = .Platform$path.sep) else local_r_libs)
  }
  cur_user <- Sys.getenv("R_LIBS_USER", unset = "")
  if (!nzchar(cur_user) || !grepl(local_r_libs, cur_user, fixed = TRUE)) {
    Sys.setenv(R_LIBS_USER = if (nzchar(cur_user)) paste(local_r_libs, cur_user, sep = .Platform$path.sep) else local_r_libs)
  }
}

if (!nzchar(Sys.getenv("EMP_ROOT", unset = ""))) Sys.setenv(EMP_ROOT = repo_root)
# Keep standalone Windows launches self-contained and writable. The PowerShell
# launcher supplies the same default, but direct `Rscript run_api.R` should also
# work without depending on LOCALAPPDATA permissions.
if (!nzchar(Sys.getenv("EMP_DATA_DIR", unset = ""))) {
  default_data_dir <- file.path(repo_root, ".local_run", "data")
  if (!dir.exists(default_data_dir)) dir.create(default_data_dir, recursive = TRUE, showWarnings = FALSE)
  if (dir.exists(default_data_dir)) Sys.setenv(EMP_DATA_DIR = default_data_dir)
}

library(plumber)

# Plumber is single-process: BiocParallel forks/sockets can kill the API
# (DiffBind / DESeq2 / GenomicAlignments). Force serial backends at boot.
if (requireNamespace("BiocParallel", quietly = TRUE)) {
  tryCatch({
    BiocParallel::register(BiocParallel::SerialParam(), default = TRUE)
    options(BiocParallel.ForcedSerial = TRUE)
  }, error = function(e) invisible(NULL))
}
Sys.setenv(OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1")

plumber_file <- file.path(script_dir, "plumber.R")
cat("Starting EasyMultiProfiler API from:", plumber_file, "\n")

if (!nzchar(Sys.getenv("BACKEND_DIR", unset = ""))) {
  Sys.setenv(BACKEND_DIR = script_dir)
}

source(file.path(script_dir, "helpers", "utils.R"))
source(file.path(script_dir, "helpers", "auth.R"))
emp_validate_deployment()

pr <- plumb(plumber_file)
port <- suppressWarnings(as.integer(Sys.getenv("API_PORT", unset = "8000")))
if (is.na(port) || port <= 0 || port > 65535) port <- 8000L
# Default 0.0.0.0 so LAN / Tailscale peers can reach the API.
# Override with API_HOST=127.0.0.1 for loopback-only.
host <- trimws(Sys.getenv("API_HOST", unset = "0.0.0.0"))
if (!nzchar(host)) host <- "0.0.0.0"
cat(sprintf("Binding API on %s:%s\n", host, port))
pr$run(host = host, port = port, docs = FALSE)
