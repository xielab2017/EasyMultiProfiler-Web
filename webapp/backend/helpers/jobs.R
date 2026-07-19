# Lightweight async job runner with disk-persistent state.
#
# We can't use a shared in-memory cache between plumber requests because each
# request runs on the same R process but callr workers are spawned on demand.
# Jobs live as files under JOB_DIR:
#   <id>.json      current status (queued / running / done / error) + metadata
#   <id>.result    serialized RDS of the result (written on success)
#   <id>.log       optional stderr log
#
# `submit_job()` launches a callr process, records pid/start, and returns the
# job id.  `get_job_status()` reads the JSON and surfaces it to the client.

JOB_DIR <- emp_storage_dir("jobs")

.jobs_ensure_dir <- function() {
  dir.create(JOB_DIR, recursive = TRUE, showWarnings = FALSE)
}

.job_id <- function() {
  paste0(format(Sys.time(), "%Y%m%d%H%M%OS3"), "-",
         paste0(sample(c(letters, 0:9), 8, replace = TRUE), collapse = ""))
}

.job_state_path  <- function(id) file.path(JOB_DIR, paste0(id, ".json"))
.job_result_path <- function(id) file.path(JOB_DIR, paste0(id, ".result"))
.job_log_path    <- function(id) file.path(JOB_DIR, paste0(id, ".log"))

.write_state <- function(id, state) {
  .jobs_ensure_dir()
  tmp <- tempfile(tmpdir = JOB_DIR)
  writeLines(jsonlite::toJSON(state, auto_unbox = TRUE, null = "null",
                               na = "null", pretty = FALSE), tmp)
  file.rename(tmp, .job_state_path(id))
}

.read_state <- function(id) {
  p <- .job_state_path(id)
  if (!file.exists(p)) return(NULL)
  tryCatch(jsonlite::fromJSON(readLines(p, warn = FALSE), simplifyVector = TRUE),
           error = function(e) NULL)
}

# Publicly exposed helper – workers call this from inside the child R session
# via a closure produced by `.make_progress_callback()` to publish progress
# updates to the shared JSON state file.
.make_progress_callback <- function(id) {
  state_path <- .job_state_path(id)
  function(pct, msg = NULL) {
    st <- tryCatch(jsonlite::fromJSON(readLines(state_path, warn = FALSE),
                                       simplifyVector = TRUE),
                   error = function(e) list())
    st$status   <- "running"
    st$progress <- max(1L, min(99L, as.integer(pct)))
    if (!is.null(msg)) st$message <- as.character(msg)
    st$updated  <- as.integer(Sys.time())
    writeLines(jsonlite::toJSON(st, auto_unbox = TRUE, null = "null",
                                 na = "null", pretty = FALSE), state_path)
    invisible(NULL)
  }
}

submit_job <- function(kind, fn, args = list(), session_id = NULL) {
  if (!requireNamespace("callr", quietly = TRUE)) {
    stop("R package 'callr' is required for async jobs.")
  }
  .jobs_ensure_dir()
  id <- .job_id()
  started <- as.integer(Sys.time())
  .write_state(id, list(
    id         = id,
    kind       = kind,
    session_id = session_id,
    status     = "queued",
    progress   = 0L,
    message    = "Queued",
    started    = started,
    updated    = started
  ))

  .BACKEND_DIR <- Sys.getenv("EMP_BACKEND_DIR",
                              unset = normalizePath("webapp/backend", mustWork = FALSE))

  run_body <- function(id, fn, args, backend_dir, state_path, result_path, log_path) {
    # Redirect stdout & messages to the log file via an open connection.
    log_con <- file(log_path, open = "at")
    sink(log_con, split = FALSE, type = "output")
    sink(log_con, type = "message")
    on.exit({ sink(type = "message"); sink(); try(close(log_con), silent = TRUE) },
            add = TRUE)

    suppressPackageStartupMessages({
      library(EasyMultiProfiler)
      library(SummarizedExperiment)
      library(MultiAssayExperiment)
      library(jsonlite)
    })
    helper_files <- list.files(file.path(backend_dir, "helpers"), pattern = "\\.R$", full.names = TRUE)
    storage_file <- helper_files[basename(helper_files) == "storage.R"]
    helper_files <- c(storage_file, helper_files[basename(helper_files) != "storage.R"])
    for (f in helper_files) {
      source(f, local = FALSE)
    }

    write_state <- function(s) {
      writeLines(toJSON(s, auto_unbox = TRUE, null = "null", na = "null",
                        pretty = FALSE), state_path)
    }
    bump <- function(pct, msg = NULL) {
      st <- tryCatch(fromJSON(readLines(state_path, warn = FALSE),
                               simplifyVector = TRUE),
                     error = function(e) list())
      st$status   <- "running"
      st$progress <- max(1L, min(99L, as.integer(pct)))
      if (!is.null(msg)) st$message <- as.character(msg)
      st$updated  <- as.integer(Sys.time())
      write_state(st)
    }

    bump(1, "Starting")
    result <- tryCatch({
      args$on_progress <- bump
      do.call(fn, args)
    }, error = function(e) {
      st <- tryCatch(fromJSON(readLines(state_path, warn = FALSE),
                               simplifyVector = TRUE),
                     error = function(e) list())
      st$status  <- "error"
      st$error   <- conditionMessage(e)
      st$updated <- as.integer(Sys.time())
      write_state(st)
      stop(e)
    })

    saveRDS(result, result_path)

    st <- tryCatch(fromJSON(readLines(state_path, warn = FALSE),
                             simplifyVector = TRUE),
                   error = function(e) list())
    st$status   <- "done"
    st$progress <- 100L
    st$message  <- "Done"
    st$updated  <- as.integer(Sys.time())
    write_state(st)
  }

  callr::r_bg(
    func = run_body,
    args = list(
      id          = id,
      fn          = fn,
      args        = args,
      backend_dir = .BACKEND_DIR,
      state_path  = .job_state_path(id),
      result_path = .job_result_path(id),
      log_path    = .job_log_path(id)
    ),
    stdout = "|",
    stderr = "2>&1",
    supervise = FALSE
  )

  id
}

get_job_status <- function(id) {
  st <- .read_state(id)
  if (is.null(st)) return(list(error = paste0("Job not found: ", id)))
  st
}

get_job_result <- function(id) {
  p <- .job_result_path(id)
  if (!file.exists(p)) return(NULL)
  tryCatch(readRDS(p), error = function(e) NULL)
}

cleanup_old_jobs <- function(max_age_hours = 6) {
  .jobs_ensure_dir()
  cutoff <- Sys.time() - max_age_hours * 3600
  for (f in list.files(JOB_DIR, full.names = TRUE)) {
    if (file.mtime(f) < cutoff) try(unlink(f), silent = TRUE)
  }
  invisible(NULL)
}
