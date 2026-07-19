#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "webapp/tests/test_emp_agent_api.R"
root <- normalizePath(file.path(dirname(script), "../.."), winslash = "/", mustWork = TRUE)
backend <- file.path(root, "webapp", "backend")

tmp <- tempfile("emp-agent-api-test-")
allowed <- file.path(tmp, "allowed")
outside <- file.path(tmp, "outside")
sessions <- file.path(tmp, "sessions")
jobs <- file.path(tmp, "jobs")
dir.create(allowed, recursive = TRUE)
dir.create(outside, recursive = TRUE)
on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)

data_file <- file.path(allowed, "16S_level-7.csv")
metadata_file <- file.path(allowed, "16S_mapping.csv")
stopifnot(file.copy(file.path(root, "tests", "16S_level-7.csv"), data_file))
stopifnot(file.copy(file.path(root, "tests", "16S_mapping.csv"), metadata_file))
outside_file <- file.path(outside, "outside.csv")
writeLines(c("feature,S1", "x,1"), outside_file)

Sys.setenv(
  EMP_SESSION_DIR = sessions,
  EMP_JOB_DIR = jobs,
  EMP_ALLOWED_ROOTS = allowed,
  EMP_PREVIEW_MAX_ROWS = "80"
)

suppressPackageStartupMessages({
  library(EasyMultiProfiler)
  library(MultiAssayExperiment)
  library(SummarizedExperiment)
  library(S4Vectors)
})

source(file.path(backend, "helpers", "storage.R"))
source(file.path(backend, "helpers", "session.R"))
source(file.path(backend, "helpers", "utils.R"))
source(file.path(backend, "helpers", "import.R"))
source(file.path(backend, "helpers", "agent_api.R"))

expect_error <- function(expr, pattern) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error), ignore.case = TRUE))
}

stopifnot(identical(SESSION_DIR, normalizePath(sessions, winslash = "/")))
stopifnot(identical(emp_storage_dir("jobs"), normalizePath(jobs, winslash = "/")))

caps <- emp_agent_capabilities()
stopifnot(
  identical(caps$api_version, "1.0"),
  identical(caps$emp_version, "7.0.0"),
  isTRUE(caps$features$path_import),
  isTRUE(caps$features$persistent_sessions),
  isTRUE(caps$features$arbitrary_r),
  "microbiome_16s" %in% caps$workflows
)

old_user_r <- Sys.getenv("EMP_ENABLE_USER_R", unset = NA_character_)
Sys.setenv(EMP_ENABLE_USER_R = "false")
stopifnot(identical(emp_agent_capabilities()$features$arbitrary_r, FALSE))
if (is.na(old_user_r)) Sys.unsetenv("EMP_ENABLE_USER_R") else Sys.setenv(EMP_ENABLE_USER_R = old_user_r)

expect_error(session_path("../escaped-session"), "Invalid session_id")

expect_error(emp_resolve_allowed_file(outside_file), "outside EMP_ALLOWED_ROOTS")
expect_error(emp_resolve_allowed_file(allowed), "regular file")
expect_error(emp_resolve_allowed_file(file.path(allowed, "missing.csv")), "No such file|cannot normalize|does not exist")

if (.Platform$OS.type != "windows") {
  link <- file.path(allowed, "outside-link.csv")
  if (isTRUE(file.symlink(outside_file, link))) {
    expect_error(emp_resolve_allowed_file(link), "outside EMP_ALLOWED_ROOTS")
  }
}

preview <- emp_path_import_preview(data_file, metadata_file, data_type = "tax")
stopifnot(
  isTRUE(preview$success),
  preview$data$orientation %in% c("features_in_rows", "samples_in_rows"),
  preview$data$rows_previewed > 0,
  preview$data$columns > 1,
  preview$metadata$rows_previewed > 0,
  nzchar(preview$metadata$sample_id_column),
  preview$sample_overlap$matched > 0,
  preview$sample_overlap$matched == preview$sample_overlap$metadata,
  length(preview$sample_overlap$metadata_only) == 0
)

imported <- emp_path_import(
  data_path = data_file,
  metadata_path = metadata_file,
  experiment_name = "agent_16s",
  data_type = "tax",
  assay_name = "counts",
  start_level = "Species"
)
stopifnot(
  isTRUE(imported$success),
  identical(imported$omics, "microbiome_16s"),
  imported$samples > 0,
  imported$features > 0,
  session_exists(imported$session_id),
  file.exists(mae_path(imported$session_id))
)

cat("EMP agent API tests passed\n")
