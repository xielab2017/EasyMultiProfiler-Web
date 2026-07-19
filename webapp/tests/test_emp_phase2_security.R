#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "webapp/tests/test_emp_phase2_security.R"
root <- normalizePath(file.path(dirname(script), "../.."), winslash = "/", mustWork = TRUE)
backend <- file.path(root, "webapp", "backend")

tmp <- tempfile("emp-phase2-test-")
dir.create(tmp, recursive = TRUE)
on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)
Sys.setenv(
  EMP_SESSION_DIR = file.path(tmp, "sessions"),
  EMP_JOB_DIR = file.path(tmp, "jobs"),
  EMP_PROJECT_DIR = file.path(tmp, "projects"),
  EMP_ENDPOINT_ID = "test-endpoint",
  EMP_API_OWNER_ID = "owner-a",
  API_HOST = "127.0.0.1"
)
Sys.unsetenv(c("EMP_API_TOKEN", "EMP_API_TOKEN_SHA256S", "EMP_CORS_ORIGIN"))

suppressPackageStartupMessages(library(jsonlite))
source(file.path(backend, "helpers", "storage.R"))
source(file.path(backend, "helpers", "session.R"))
source(file.path(backend, "helpers", "utils.R"))
source(file.path(backend, "helpers", "auth.R"))
source(file.path(backend, "helpers", "projects.R"))
source(file.path(backend, "helpers", "jobs.R"))

expect_error <- function(expr, pattern) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error), ignore.case = TRUE))
}

request <- function(path = "/api/capabilities", token = NULL, body = "") {
  req <- new.env(parent = emptyenv())
  req$PATH_INFO <- path
  req$postBody <- body
  req$args <- list()
  if (!is.null(token)) req$HTTP_AUTHORIZATION <- paste("Bearer", token)
  req
}

# Loopback keeps backward compatibility when no token is configured.
local_req <- request()
stopifnot(identical(emp_authenticate_request(local_req), "local"))

# A non-loopback bind fails closed unless a bearer token is configured.
Sys.setenv(API_HOST = "0.0.0.0")
expect_error(emp_validate_deployment(), "EMP_API_TOKEN.*required")
Sys.setenv(EMP_API_TOKEN = "phase2-secret")
expect_error(emp_validate_deployment(), "EMP_CORS_ORIGIN")
Sys.setenv(EMP_CORS_ORIGIN = "https://agent.example")
stopifnot(isTRUE(emp_validate_deployment()))
expect_error(emp_authenticate_request(request()), "Authentication required")
expect_error(emp_authenticate_request(request(token = "wrong")), "Authentication required")
auth_req <- request(token = "phase2-secret")
stopifnot(identical(emp_authenticate_request(auth_req), "owner-a"))

# Projects and sessions remain bound to endpoint + owner after a disk round trip.
project <- emp_create_project("owner-a", "Phase 2 test")
session <- emp_create_project_session(project$project_id, "owner-a")
stopifnot(
  file.exists(project_path(project$project_id)),
  file.exists(session_owner_path(session$session_id)),
  identical(emp_get_project(project$project_id)$session_ids[[1]], session$session_id),
  identical(emp_assert_session_owner(session$session_id, "owner-a")$project_id, project$project_id)
)
expect_error(emp_assert_project_owner(project$project_id, "owner-b"), "access denied")
expect_error(emp_assert_session_owner(session$session_id, "owner-b"), "access denied")
Sys.setenv(EMP_ENDPOINT_ID = "other-endpoint")
expect_error(emp_assert_session_owner(session$session_id, "owner-a"), "access denied")
Sys.setenv(EMP_ENDPOINT_ID = "test-endpoint")

emp_record_session_import(
  session$session_id,
  input_files = list(data = list(path = "data.csv", sha256 = "abc")),
  experiment = "study",
  data_type = "tax"
)
manifest <- emp_session_manifest(session$session_id, "owner-a")
stopifnot(
  identical(manifest$session_id, session$session_id),
  identical(manifest$project_id, project$project_id),
  identical(manifest$imports[[1]]$input_files$data$sha256, "abc"),
  nzchar(manifest$versions$r)
)

# Request-level authorization catches path and JSON-body session references.
path_req <- request(paste0("/api/session/", session$session_id, "/manifest"), "phase2-secret")
invisible(emp_authenticate_request(path_req))
stopifnot(isTRUE(invisible(emp_authorize_request_resources(path_req, "owner-a"))))
expect_error(emp_authorize_request_resources(path_req, "owner-b"), "access denied")
body_req <- request(
  "/api/analyze/alpha",
  "phase2-secret",
  jsonlite::toJSON(list(session_id = session$session_id), auto_unbox = TRUE)
)
invisible(emp_authenticate_request(body_req))
expect_error(emp_authorize_request_resources(body_req, "owner-b"), "access denied")

# Finished jobs are not killed. Running jobs retain a durable cancellation state.
finished_id <- .job_id()
.write_state(finished_id, list(
  id = finished_id, endpoint_id = emp_endpoint_id(), owner_id = "owner-a",
  session_id = session$session_id, status = "done", progress = 100L
))
stopifnot(identical(cancel_job(finished_id)$status, "already_finished"))
expect_error(emp_assert_job_owner(finished_id, "owner-b"), "access denied")

if (requireNamespace("callr", quietly = TRUE)) {
  process <- callr::r_bg(function() Sys.sleep(30), supervise = FALSE)
  on.exit(if (process$is_alive()) process$kill(), add = TRUE)
  running_id <- .job_id()
  .write_state(running_id, list(
    id = running_id, endpoint_id = emp_endpoint_id(), owner_id = "owner-a",
    session_id = session$session_id, status = "running", progress = 10L,
    pid = process$get_pid(), cancellable = TRUE
  ))
  assign(running_id, process, envir = .JOB_PROCESSES)
  cancelled <- cancel_job(running_id)
  Sys.sleep(0.2)
  stopifnot(
    cancelled$status %in% c("cancelled", "cancel_requested"),
    get_job_status(running_id)$status %in% c("cancelled", "cancel_requested")
  )
}

expect_error(.job_state_path("../escape"), "Invalid job_id")
cat("EMP Phase 2 security tests passed\n")
