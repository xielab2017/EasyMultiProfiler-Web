#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "webapp/tests/test_emp_remote_security.R"
root <- normalizePath(file.path(dirname(script), "../.."), winslash = "/", mustWork = TRUE)
backend <- file.path(root, "webapp", "backend")
data_dir <- tempfile("emp-security-data-")
Sys.setenv(EMP_DATA_DIR = data_dir)
on.exit(unlink(data_dir, recursive = TRUE, force = TRUE), add = TRUE)
source(file.path(backend, "helpers", "utils.R"))
source(file.path(backend, "helpers", "storage.R"))
source(file.path(backend, "helpers", "session.R"))
source(file.path(backend, "helpers", "auth.R"))
source(file.path(backend, "helpers", "projects.R"))

old <- Sys.getenv(c("API_HOST", "EMP_API_TOKEN", "EMP_API_TOKEN_SHA256S", "EMP_CORS_ORIGIN"), unset = NA_character_)
on.exit({
  for (name in names(old)) if (is.na(old[[name]])) Sys.unsetenv(name) else do.call(Sys.setenv, setNames(list(old[[name]]), name))
}, add = TRUE)

Sys.setenv(API_HOST = "0.0.0.0")
Sys.setenv(EMP_CORS_ORIGIN = "https://hub.example.edu")
Sys.unsetenv(c("EMP_API_TOKEN", "EMP_API_TOKEN_SHA256S"))
error <- tryCatch({ emp_validate_deployment(); NULL }, error = identity)
stopifnot(inherits(error, "error"))

alice_token <- "alice-secret"
bob_token <- "bob-secret"
hashes <- jsonlite::toJSON(list(
  alice = digest::digest(alice_token, algo = "sha256", serialize = FALSE),
  bob = digest::digest(bob_token, algo = "sha256", serialize = FALSE)
), auto_unbox = TRUE)
Sys.setenv(EMP_API_TOKEN_SHA256S = hashes)
emp_validate_deployment()

request <- new.env(parent = emptyenv())
request$HTTP_AUTHORIZATION <- paste("Bearer", alice_token)
stopifnot(identical(emp_authenticate_request(request), "alice"))
project <- emp_create_project("alice", "Study")
stopifnot(identical(emp_assert_project_owner(project$project_id, "alice")$owner_id, "alice"))
denied <- tryCatch({ emp_assert_project_owner(project$project_id, "bob"); NULL }, error = identity)
stopifnot(inherits(denied, "error"))

bad <- new.env(parent = emptyenv())
bad$HTTP_AUTHORIZATION <- "Bearer wrong"
denied <- tryCatch({ emp_authenticate_request(bad); NULL }, error = identity)
stopifnot(inherits(denied, "error"))

cat("EMP remote security tests passed\n")
