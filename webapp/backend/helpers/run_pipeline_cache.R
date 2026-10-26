# run_pipeline_cache.R - EMP Web v9.1.0 analysis upgrade B (base R only):
# deterministic step caching, parallel lapply, and resume planning for
# long Run All pipelines. helpers/jobs.R already provides async jobs with
# progress; these helpers make individual steps cacheable and resumable.

#' Deterministic cache key for a pipeline step.
#' Deparses the step name plus all key parts into a temp file and returns
#' its md5, so identical inputs always map to the same key.
emp_step_key <- function(step_name, key_parts = list()) {
  tf <- tempfile(pattern = "emp_step_key_")
  on.exit(unlink(tf), add = TRUE)
  txt <- paste(c(
    paste0("step:", as.character(step_name)),
    paste(deparse(key_parts, width.cutoff = 500L), collapse = "\n")
  ), collapse = "\n")
  writeLines(txt, tf, useBytes = TRUE)
  unname(tools::md5sum(tf))
}

#' Run one pipeline step with an RDS cache.
#' On a cache hit the stored value is returned and `fn` is NOT called.
#' @return list(value = ..., cached = TRUE/FALSE, key = ..., file = ...)
emp_run_cached_step <- function(name, key_parts = list(), fn,
                                cache_dir = NULL) {
  if (!is.function(fn)) stop("emp_run_cached_step: `fn` must be a function")
  key <- emp_step_key(name, key_parts)
  if (is.null(cache_dir)) {
    return(list(value = fn(), cached = FALSE, key = key, file = NULL))
  }
  if (!dir.exists(cache_dir)) {
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  }
  safe_name <- gsub("[^A-Za-z0-9_.-]", "_", as.character(name))
  file <- file.path(cache_dir, paste0(safe_name, "_", key, ".rds"))
  if (file.exists(file)) {
    return(list(value = readRDS(file), cached = TRUE, key = key, file = file))
  }
  value <- fn()
  saveRDS(value, file)
  list(value = value, cached = FALSE, key = key, file = file)
}

#' Parallel lapply with a platform-safe fallback.
#' Worker count comes from the EMP_PARALLEL_WORKERS env var (default 1 =
#' serial). Unix uses parallel::mclapply (fork); Windows cannot fork, so
#' it uses a PSOCK cluster that is always stopped on exit.
emp_lapply_parallel <- function(X, FUN) {
  workers <- suppressWarnings(
    as.integer(Sys.getenv("EMP_PARALLEL_WORKERS", unset = "1"))
  )
  if (is.na(workers) || workers <= 1 || length(X) <= 1) {
    return(lapply(X, FUN))
  }
  workers <- min(workers, length(X))
  if (.Platform$OS.type == "windows") {
    cl <- parallel::makeCluster(workers)
    on.exit(parallel::stopCluster(cl), add = TRUE)
    return(parallel::parLapply(cl, X, FUN))
  }
  parallel::mclapply(X, FUN, mc.cores = workers)
}

#' Resume planning: which steps still need to run?
#' @param steps Character vector of step names in pipeline order.
#' @param manifest Named list (or named logical vector) marking finished
#'   steps as done (TRUE / "done" / "complete").
#' @return Character vector of the steps not marked done, in order.
emp_resume_plan <- function(steps, manifest = list()) {
  if (length(steps) == 0) return(character(0))
  done <- vapply(steps, function(step) {
    value <- manifest[[step]]
    if (is.null(value)) return(FALSE)
    if (is.logical(value)) return(isTRUE(value[[1]]))
    identical(tolower(as.character(value[[1]])), "done") ||
      identical(tolower(as.character(value[[1]])), "complete")
  }, logical(1))
  steps[!done]
}
