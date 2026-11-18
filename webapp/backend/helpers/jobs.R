# Lightweight async job runner with disk-persistent state.
#
# A single Plumber process dispatches a bounded backlog to callr workers.
# Jobs live as files under JOB_DIR:
#   <id>.json      current status (queued / running / done / error) + metadata
#   <id>.result    serialized RDS of the result (written on success)
#   <id>.log       optional stderr log
#
# Requests awaiting a worker are kept in memory. JSON states and results
# remain on disk so clients can inspect completed work after a restart.

JOB_DIR <- emp_storage_dir("jobs")
.JOB_PROCESSES <- new.env(parent = emptyenv())
.JOB_QUEUE <- new.env(parent = emptyenv())
.JOB_QUEUE$entries <- list()
.JOB_QUEUE$armed <- FALSE
.JOB_BACKLOG_LIMIT <- 16L

.jobs_ensure_dir <- function() {
  dir.create(JOB_DIR, recursive = TRUE, showWarnings = FALSE)
}

.job_id <- function() {
  paste0(format(Sys.time(), "%Y%m%d%H%M%OS3"), "-",
         paste0(sample(c(letters, 0:9), 8, replace = TRUE), collapse = ""))
}

validate_job_id <- function(id) {
  value <- trimws(as.character(id %||% ""))
  if (length(value) != 1L || !grepl("^[0-9]{14}\\.[0-9]{3}-[a-z0-9]{8}$", value)) stop("Invalid job_id")
  value
}

.job_state_path  <- function(id) file.path(JOB_DIR, paste0(validate_job_id(id), ".json"))
.job_result_path <- function(id) file.path(JOB_DIR, paste0(validate_job_id(id), ".result"))
.job_json_path   <- function(id) file.path(JOB_DIR, paste0(validate_job_id(id), ".response"))
.job_log_path    <- function(id) file.path(JOB_DIR, paste0(validate_job_id(id), ".log"))

.write_state <- function(id, state) {
  .jobs_ensure_dir()
  tmp <- tempfile(tmpdir = JOB_DIR)
  writeLines(jsonlite::toJSON(state, auto_unbox = TRUE, null = "null",
                               na = "null", pretty = FALSE), tmp)
  on.exit(unlink(tmp), add = TRUE)
  if (!file.rename(tmp, .job_state_path(id))) stop("Cannot write analysis job state")
}

.read_state <- function(id) {
  p <- .job_state_path(id)
  if (!file.exists(p)) return(NULL)
  tryCatch(jsonlite::fromJSON(readLines(p, warn = FALSE), simplifyVector = TRUE),
           error = function(e) NULL)
}

.job_pid_alive <- function(pid) {
  isTRUE(tryCatch(ps::ps_is_running(ps::ps_handle(as.integer(pid))), error = function(e) FALSE))
}

# Atomic directory lock serializes session writes across worker processes.
# A killed worker's lock is reclaimed only after its recorded PID is gone.
.job_session_lock <- function(session_id, on_wait = function() NULL) {
  lock <- file.path(session_path(session_id), ".analysis-lock")
  repeat {
    if (isTRUE(dir.create(lock, showWarnings = FALSE))) {
      writeLines(as.character(Sys.getpid()), file.path(lock, "pid"))
      return(lock)
    }
    pid_file <- file.path(lock, "pid")
    pid <- suppressWarnings(tryCatch(as.integer(readLines(pid_file, n = 1, warn = FALSE)), error = function(e) NA_integer_))
    old <- as.numeric(difftime(Sys.time(), file.info(lock)$mtime, units = "secs")) > 30
    dead <- length(pid) == 1L && !is.na(pid) && !.job_pid_alive(pid)
    if (isTRUE(dead) || (isTRUE(old) && (length(pid) != 1L || is.na(pid)))) {
      unlink(lock, recursive = TRUE)
      next
    }
    on_wait()
    Sys.sleep(1)
  }
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
    .write_state(id, st)
    invisible(NULL)
  }
}

submit_job <- function(kind, fn, args = list(), session_id = NULL, owner_id = NULL, project_id = NULL) {
  if (!requireNamespace("callr", quietly = TRUE)) {
    stop("R package 'callr' is required for async jobs.")
  }
  .dispatch_jobs()
  if (length(.JOB_QUEUE$entries) >= .JOB_BACKLOG_LIMIT) {
    stop(errorCondition("Analysis queue is full. Wait for a job to finish or cancel a queued job.",
                        class = "emp_capacity_error"))
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
  experiment_name <- args$payload$experiment %||% args$experiment %||% NULL
  # Persist the registered experiment type rather than a client hint or name.
  experiment_omics <- "unknown"
  if (!is.null(session_id) && length(experiment_name) == 1L &&
      exists("read_experiment_registry", mode = "function")) {
    registry <- tryCatch(read_experiment_registry(session_id), error = function(e) list())
    metadata <- registry[[experiment_name]]
    value <- metadata$omics %||% switch(metadata$data_type %||% "", tax="microbiome_16s", chipseq="chipseq", "unknown")
    if (is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)) experiment_omics <- value
  }
  .write_state(id, list(
    id         = id,
    kind       = kind,
    experiment = experiment_name,
    omics = experiment_omics,
    parameters = (args$payload %||% args)[intersect(names(args$payload %||% args), c('method','use','k','group_var','ref_group','test_group','comparison_mode','filter_low'))],
    session_id = session_id,
    endpoint_id = emp_endpoint_id(),
    owner_id = owner_id,
    project_id = project_id,
    dispatcher_pid = Sys.getpid(),
    status     = "queued",
    cancellable = TRUE,
    progress   = 0L,
    message    = "Queued",
    started    = started,
    updated    = started
  ))

  .JOB_QUEUE$entries[[id]] <- list(fn = fn, args = args, session_id = session_id)
  .dispatch_jobs()
  id
}

.job_worker_limit <- function() {
  value <- suppressWarnings(as.integer(Sys.getenv("EMP_ANALYSIS_WORKERS", "4")))
  if (is.na(value) || value < 1L) 4L else value
}

.job_terminal <- c("done", "error", "cancelled")

.fail_job <- function(id, message) {
  st <- .read_state(id)
  if (is.null(st) || st$status %in% .job_terminal) return(invisible(NULL))
  st$status <- if (identical(st$status, "cancel_requested")) "cancelled" else "error"
  if (st$status == "error") st$error <- message
  st$message <- if (st$status == "cancelled") "Cancelled" else message
  st$finished <- st$updated <- as.integer(Sys.time())
  .write_state(id, st)
}

.run_job <- function(id, kind, fn, args, backend_dir, log_path) {
  log_con <- file(log_path, open = "at")
  sink(log_con, type = "output")
  sink(log_con, type = "message")
  on.exit({ sink(type = "message"); sink(); close(log_con) }, add = TRUE)

  helpers <- file.path(backend_dir, "helpers")
  for (name in c("utils.R", "storage.R", "jobs.R")) {
    source(file.path(helpers, name), local = FALSE)
  }
  initial <- .read_state(id)
  initial$pid <- Sys.getpid()
  .write_state(id, initial)

  tryCatch({
    if (!is.null(initial$session_id)) {
      source(file.path(helpers, "session.R"), local = FALSE)
      lock <- .job_session_lock(initial$session_id, function() {
        st <- .read_state(id)
        if (!identical(st$message, "Waiting for another task in this session")) {
          st$message <- "Waiting for another task in this session"
          st$updated <- as.integer(Sys.time())
          .write_state(id, st)
        }
      })
      on.exit(unlink(lock, recursive = TRUE), add = TRUE)
    }
    # These two workbenches are self-contained and namespace their dependencies.
    # Keep the full legacy environment for session analyses and registered routes.
    standalone <- switch(kind, count_workbench = "omics_workbench.R",
                         integration_exploration = "integration_workbench.R", NULL)
    if (is.null(standalone)) {
      suppressPackageStartupMessages({
        library(EasyMultiProfiler)
        library(SummarizedExperiment)
        library(MultiAssayExperiment)
        library(jsonlite)
        library(ggplot2)
        library(base64enc)
      })
      helper_files <- list.files(helpers, pattern = "\\.R$", full.names = TRUE)
      helper_files <- helper_files[!basename(helper_files) %in% c("jobs.R", "storage.R")]
      for (file in helper_files) source(file, local = FALSE)
    } else {
      source(file.path(helpers, standalone), local = FALSE)
    }

    bump <- .make_progress_callback(id)
    bump(1, "Starting")
    args$on_progress <- bump
    result <- do.call(fn, args)
    st <- .read_state(id)
    if (st$status %in% c("cancel_requested", "cancelled")) return(invisible(NULL))
    saveRDS(result, .job_result_path(id))
    if (!is.null(standalone)) {
      # Serialize large result tables in the worker, away from the API event loop.
      temporary_cache <- tempfile(tmpdir = JOB_DIR)
      on.exit(unlink(temporary_cache), add = TRUE)
      tryCatch({
        json <- jsonlite::toJSON(result, auto_unbox = TRUE, digits = NA, na = "null", null = "null")
        payload <- charToRaw(enc2utf8(json))
        writeBin(payload, temporary_cache)
        if (!file.rename(temporary_cache, .job_json_path(id))) stop("Cannot publish response cache")
        st$response_bytes <- length(payload)
      }, error = function(e) {
        message("Result JSON cache unavailable: ", conditionMessage(e))
      })
    }
    st$status <- "done"
    st$finished <- st$updated <- as.integer(Sys.time())
    st$progress <- 100L
    st$message <- "Done"
    .write_state(id, st)
  }, error = function(e) {
    .fail_job(id, conditionMessage(e))
    stop(e)
  })
}

.reap_jobs <- function() {
  for (id in ls(.JOB_PROCESSES)) {
    process <- get(id, envir = .JOB_PROCESSES, inherits = FALSE)
    if (isTRUE(process$is_alive())) next
    rm(list = id, envir = .JOB_PROCESSES)
    .fail_job(id, "Worker exited before producing a result; inspect the job log.")
  }
}

.dispatch_jobs <- function() {
  .reap_jobs()
  if (!length(.JOB_QUEUE$entries)) return(invisible(NULL))
  active <- ls(.JOB_PROCESSES)
  busy_sessions <- vapply(active, function(id) .read_state(id)$session_id %||% "", character(1))
  for (id in names(.JOB_QUEUE$entries)) {
    if (length(active) >= .job_worker_limit()) break
    entry <- .JOB_QUEUE$entries[[id]]
    if (!is.null(entry$session_id) && entry$session_id %in% busy_sessions) next

    .JOB_QUEUE$entries[[id]] <- NULL
    st <- .read_state(id)
    if (is.null(st) || st$status != "queued") next
    backend_dir <- Sys.getenv("EMP_BACKEND_DIR", unset = normalizePath("webapp/backend", mustWork = FALSE))
    process <- tryCatch(callr::r_bg(
      func = .run_job, args = list(id = id, kind = st$kind, fn = entry$fn, args = entry$args,
                                   backend_dir = backend_dir, log_path = .job_log_path(id)),
      stdout = "|", stderr = "2>&1", supervise = FALSE
    ), error = function(e) {
      .fail_job(id, paste("Could not start analysis worker:", conditionMessage(e)))
      NULL
    })
    if (is.null(process)) next
    assign(id, process, envir = .JOB_PROCESSES)
    active <- c(active, id)
    busy_sessions <- c(busy_sessions, entry$session_id %||% "")
  }
  if (length(.JOB_QUEUE$entries) && !.JOB_QUEUE$armed) {
    .JOB_QUEUE$armed <- TRUE
    later::later(function() {
      .JOB_QUEUE$armed <- FALSE
      .dispatch_jobs()
    }, delay = 0.25)
  }
  invisible(NULL)
}

.job_summary <- function(st) {
  if (is.null(st)) return(NULL)
  list(
    id       = st$id %||% NULL,
    kind     = st$kind %||% NULL,
    experiment = st$experiment %||% NULL,
    omics = st$omics %||% "unknown",
    parameters = st$parameters %||% list(),
    status   = st$status %||% "unknown",
    progress = suppressWarnings(as.integer(st$progress %||% 0L)),
    message  = st$message %||% st$error %||% NULL,
    created  = st$created %||% st$started %||% NULL,
    started  = st$started %||% NULL,
    finished = st$finished %||% NULL,
    pid = st$pid %||% NULL,
    cancellable = isTRUE(st$cancellable) && !st$status %in% c(.job_terminal, "cancel_requested") &&
      (st$id %in% names(.JOB_QUEUE$entries) || exists(st$id, envir = .JOB_PROCESSES, inherits = FALSE)),
    session_id = st$session_id %||% NULL,
    elapsed_seconds = max(0L, (st$finished %||% (if (st$status %in% c("done", "error", "cancelled")) st$updated else as.integer(Sys.time()))) - (st$started %||% as.integer(Sys.time())))
  )
}

# List recent jobs (newest first) for the job tray / API. Reads the
# on-disk JSON states under JOB_DIR; optionally filters by owner/project
# when those fields are recorded on the job state.
list_jobs <- function(limit = 20, owner_id = NULL, project_id = NULL) {
  .jobs_ensure_dir()
  limit <- suppressWarnings(as.integer(limit))
  if (is.na(limit) || limit < 1L) limit <- 20L
  files <- list.files(JOB_DIR, pattern = "\\.json$", full.names = TRUE)
  if (!length(files)) return(list())
  files <- files[order(file.mtime(files), decreasing = TRUE)]
  out <- list()
  for (path in files) {
    if (length(out) >= limit) break
    st <- tryCatch(
      jsonlite::fromJSON(readLines(path, warn = FALSE), simplifyVector = TRUE),
      error = function(e) NULL
    )
    if (is.null(st) || is.null(st$id)) next
    if (!is.null(owner_id) && !identical(st$owner_id %||% NULL, owner_id)) next
    if (!is.null(project_id) && !identical(st$project_id %||% NULL, project_id)) next
    st <- get_job_status(st$id)
    summary <- .job_summary(st)
    if (!is.null(summary)) out[[length(out) + 1]] <- summary
  }
  out
}

get_job_status <- function(id) {
  .reap_jobs()
  st <- .read_state(id)
  if (is.null(st)) return(list(error = paste0("Job not found: ", id)))
  if (!st$status %in% .job_terminal) {
    lost_queue <- is.null(st$pid) && !is.null(st$dispatcher_pid) &&
      st$dispatcher_pid != Sys.getpid() && !.job_pid_alive(st$dispatcher_pid)
    dead_worker <- !is.null(st$pid) && !.job_pid_alive(st$pid)
    if (lost_queue || dead_worker) {
      .fail_job(id, if (lost_queue) "Analysis service restarted before this job could start."
                else "Worker exited before producing a result; inspect the job log.")
      st <- .read_state(id)
    }
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
  lapply(jobs, function(st) st[setdiff(names(st), c("pid", "dispatcher_pid"))])
}

cancel_job <- function(id) {
  .reap_jobs()
  st <- .read_state(id)
  if (is.null(st)) return(list(status = "not_found", job_id = id))
  if (st$status %in% c("done", "error", "cancelled")) {
    return(list(status = if (identical(st$status, "cancelled")) "cancelled" else "already_finished", job_id = id))
  }
  if (id %in% names(.JOB_QUEUE$entries)) {
    st$status <- "cancelled"
    st$finished <- st$updated <- as.integer(Sys.time())
    st$message <- "Cancelled before starting"
    .write_state(id, st)
    .JOB_QUEUE$entries[[id]] <- NULL
    return(list(status = "cancelled", job_id = id))
  }
  if (!exists(id, envir = .JOB_PROCESSES, inherits = FALSE)) {
    return(list(status = "not_cancellable", job_id = id))
  }
  process <- get(id, envir = .JOB_PROCESSES, inherits = FALSE)
  if (!isTRUE(tryCatch(process$is_alive(), error = function(e) FALSE))) {
    rm(list = id, envir = .JOB_PROCESSES)
    .fail_job(id, "Worker exited before producing a result; inspect the job log.")
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
    if (identical(latest$status, "cancelled")) return(list(status = "cancelled", job_id = id))
    return(list(status = "cancel_requested", job_id = id))
  }
  st$status <- "cancelled"
  st$finished <- as.integer(Sys.time())
  st$message <- "Cancelled"
  st$progress <- as.integer(st$progress %||% 0L)
  st$updated <- as.integer(Sys.time())
  .write_state(id, st)
  unlink(c(.job_result_path(id), .job_json_path(id)), force = TRUE)
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
