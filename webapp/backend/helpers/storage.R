# Persistent storage roots shared by sessions and asynchronous jobs.

.emp_platform_data_root <- function() {
  override <- trimws(Sys.getenv("EMP_DATA_DIR", unset = ""))
  if (nzchar(override)) return(path.expand(override))

  if (.Platform$OS.type == "windows") {
    base <- Sys.getenv("LOCALAPPDATA", unset = path.expand("~/AppData/Local"))
    return(file.path(base, "EasyMultiProfiler"))
  }
  if (identical(Sys.info()[["sysname"]], "Darwin")) {
    return(file.path(path.expand("~/Library/Application Support"), "EasyMultiProfiler"))
  }
  base <- Sys.getenv("XDG_DATA_HOME", unset = file.path(path.expand("~"), ".local", "share"))
  file.path(base, "EasyMultiProfiler")
}

emp_storage_dir <- function(kind = c("sessions", "jobs")) {
  kind <- match.arg(kind)
  env_name <- if (identical(kind, "sessions")) "EMP_SESSION_DIR" else "EMP_JOB_DIR"
  configured <- trimws(Sys.getenv(env_name, unset = ""))
  target <- if (nzchar(configured)) path.expand(configured) else file.path(.emp_platform_data_root(), kind)
  if (!dir.exists(target) && !isTRUE(dir.create(target, recursive = TRUE, showWarnings = FALSE))) {
    stop(sprintf("EMP %s storage directory cannot be created: %s", kind, target))
  }
  resolved <- normalizePath(target, winslash = "/", mustWork = TRUE)
  probe <- tempfile(".emp-write-", tmpdir = resolved)
  if (!isTRUE(tryCatch(file.create(probe), warning = function(w) FALSE, error = function(e) FALSE))) {
    stop(sprintf("EMP %s storage directory is not writable: %s", kind, resolved))
  }
  unlink(probe, force = TRUE)
  resolved
}
