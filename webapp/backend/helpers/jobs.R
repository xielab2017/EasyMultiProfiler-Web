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
.JOB_PROCESSES <- new.env(parent = emptyenv())

.jobs_ensure_dir <- function() {
  dir.create(JOB_DIR, recursive = TRUE, showWarnings = FALSE)
}

.job_id <- function() {
  # Job ownership is asserted on this identifier (auth.R emp_assert_job_owner), so the random part
  # must not come from R's global RNG. Alphabet and length keep validate_job_id() satisfied.
  suffix <- if (exists(".emp_random_id", mode = "function")) {
    .emp_random_id(8L, alphabet = c(letters, 0:9))
  } else {
    paste0(sample(c(letters, 0:9), 8, replace = TRUE), collapse = "")
  }
  paste0(format(Sys.time(), "%Y%m%d%H%M%OS3"), "-", suffix)
}

validate_job_id <- function(id) {
  value <- trimws(as.character(id %||% ""))
  if (length(value) != 1L || !grepl("^[0-9]{14}\\.[0-9]{3}-[a-z0-9]{8}$", value)) stop("Invalid job_id")
  value
}

.job_state_path  <- function(id) file.path(JOB_DIR, paste0(validate_job_id(id), ".json"))
.job_result_path <- function(id) file.path(JOB_DIR, paste0(validate_job_id(id), ".result"))
.job_log_path    <- function(id) file.path(JOB_DIR, paste0(validate_job_id(id), ".log"))

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
    # Write to a sibling temp file and rename, so a concurrent GET /api/jobs/<id> can never read a
    # half-written state file (which .read_state() reports as NULL, i.e. "job vanished"). This
    # mirrors .write_state(), which cannot be called here: the callback is serialised into a callr
    # child process where the parent's helper functions do not exist.
    tmp <- paste0(state_path, ".tmp-", Sys.getpid())
    writeLines(jsonlite::toJSON(st, auto_unbox = TRUE, null = "null",
                                 na = "null", pretty = FALSE), tmp)
    if (!file.rename(tmp, state_path)) {
      file.copy(tmp, state_path, overwrite = TRUE)
      unlink(tmp)
    }
    invisible(NULL)
  }
}

submit_job <- function(kind, fn, args = list(), session_id = NULL, owner_id = NULL, project_id = NULL) {
  if (!requireNamespace("callr", quietly = TRUE)) {
    stop("R package 'callr' is required for async jobs.")
  }
  .jobs_ensure_dir()
  id <- .job_id()
  started <- as.integer(Sys.time())
  if (!is.null(session_id)) {
    ownership <- tryCatch(emp_get_session_owner(session_id), error = function(e) NULL)
    owner_id <- owner_id %||% ownership$owner_id %||% NULL
    project_id <- project_id %||% ownership$project_id %||% NULL
  }
  if (emp_auth_required() && (is.null(owner_id) || !nzchar(owner_id))) {
    stop("Job owner is required for an authenticated deployment.")
  }
  .write_state(id, list(
    id         = id,
    kind       = kind,
    session_id = session_id,
    endpoint_id = emp_endpoint_id(),
    owner_id = owner_id,
    project_id = project_id,
    status     = "queued",
    cancellable = TRUE,
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

    st <- tryCatch(fromJSON(readLines(state_path, warn = FALSE),
                             simplifyVector = TRUE),
                   error = function(e) list())
    if (st$status %in% c("cancel_requested", "cancelled")) return(invisible(NULL))
    saveRDS(result, result_path)
    st$status   <- "done"
    st$progress <- 100L
    st$message  <- "Done"
    st$updated  <- as.integer(Sys.time())
    write_state(st)
  }

  process <- callr::r_bg(
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

  state <- .read_state(id) %||% list(id = id)
  state$pid <- process$get_pid()
  state$cancellable <- TRUE
  state$updated <- as.integer(Sys.time())
  .write_state(id, state)
  assign(id, process, envir = .JOB_PROCESSES)

  id
}

get_job_status <- function(id) {
  st <- .read_state(id)
  if (is.null(st)) return(list(error = paste0("Job not found: ", id)))
  if (st$status %in% c("done", "error", "cancelled") && exists(id, envir = .JOB_PROCESSES, inherits = FALSE)) {
    rm(list = id, envir = .JOB_PROCESSES)
  }
  st
}

get_job_result <- function(id) {
  p <- .job_result_path(id)
  if (!file.exists(p)) return(NULL)
  tryCatch(readRDS(p), error = function(e) NULL)
}

emp_assert_job_owner <- function(id, owner_id) {
  st <- .read_state(id)
  if (is.null(st)) stop("Job not found.")
  if (is.null(st$owner_id) || !nzchar(st$owner_id)) {
    if (identical(owner_id, "local") && !emp_auth_required()) return(invisible(st))
    stop("Job ownership is not registered.")
  }
  if (!identical(st$endpoint_id %||% emp_endpoint_id(), emp_endpoint_id()) || !identical(st$owner_id, owner_id)) {
    stop("Job access denied.")
  }
  invisible(st)
}

list_jobs_for_session <- function(session_id, owner_id) {
  validate_session_id(session_id)
  files <- list.files(JOB_DIR, pattern = "\\.json$", full.names = TRUE)
  jobs <- lapply(files, function(path) {
    id <- sub("\\.json$", "", basename(path))
    tryCatch(.read_state(id), error = function(e) NULL)
  })
  jobs <- Filter(function(st) {
    !is.null(st) && identical(st$session_id %||% NULL, session_id) &&
      identical(st$endpoint_id %||% emp_endpoint_id(), emp_endpoint_id()) &&
      identical(st$owner_id %||% NULL, owner_id)
  }, jobs)
  lapply(jobs, function(st) st[setdiff(names(st), "pid")])
}

cancel_job <- function(id) {
  st <- .read_state(id)
  if (is.null(st)) return(list(status = "not_found", job_id = id))
  if (st$status %in% c("done", "error", "cancelled")) {
    return(list(status = if (identical(st$status, "cancelled")) "cancelled" else "already_finished", job_id = id))
  }
  if (!exists(id, envir = .JOB_PROCESSES, inherits = FALSE)) {
    return(list(status = "not_cancellable", job_id = id))
  }
  process <- get(id, envir = .JOB_PROCESSES, inherits = FALSE)
  if (!isTRUE(tryCatch(process$is_alive(), error = function(e) FALSE))) {
    rm(list = id, envir = .JOB_PROCESSES)
    latest <- .read_state(id) %||% st
    if (latest$status %in% c("done", "error")) return(list(status = "already_finished", job_id = id))
    return(list(status = "not_cancellable", job_id = id))
  }

  st$status <- "cancel_requested"
  st$message <- "Cancellation requested"
  st$updated <- as.integer(Sys.time())
  .write_state(id, st)
  signalled <- isTRUE(tryCatch(process$kill(), error = function(e) FALSE))
  if (!signalled) {
    latest <- .read_state(id) %||% st
    if (latest$status %in% c("done", "error")) return(list(status = "already_finished", job_id = id))
    latest$status <- "cancel_requested"
    .write_state(id, latest)
    return(list(status = "cancel_requested", job_id = id))
  }
  st$status <- "cancelled"
  st$message <- "Cancelled"
  st$progress <- as.integer(st$progress %||% 0L)
  st$updated <- as.integer(Sys.time())
  .write_state(id, st)
  if (exists(id, envir = .JOB_PROCESSES, inherits = FALSE)) rm(list = id, envir = .JOB_PROCESSES)
  unlink(.job_result_path(id), force = TRUE)
  list(status = "cancelled", job_id = id)
}

cleanup_old_jobs <- function(max_age_hours = 6) {
  .jobs_ensure_dir()
  cutoff <- Sys.time() - max_age_hours * 3600
  for (f in list.files(JOB_DIR, full.names = TRUE)) {
    if (file.mtime(f) < cutoff) try(unlink(f), silent = TRUE)
  }
  invisible(NULL)
}
