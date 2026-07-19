#!/usr/bin/env Rscript
# Entry point: start the Plumber REST API

library(plumber)

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
host <- trimws(Sys.getenv("API_HOST", unset = "127.0.0.1"))
if (!nzchar(host)) host <- "127.0.0.1"
pr$run(host = host, port = port, docs = FALSE)
