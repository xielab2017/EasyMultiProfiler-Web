# Session management helpers

SESSION_DIR <- "/tmp/emp_sessions"

new_session_id <- function() {
  paste0(sample(c(letters, LETTERS, 0:9), 24, replace = TRUE), collapse = "")
}

session_path <- function(session_id) {
  file.path(SESSION_DIR, session_id)
}

mae_path <- function(session_id) {
  file.path(SESSION_DIR, session_id, "mae.rds")
}

empt_path <- function(session_id, experiment) {
  file.path(SESSION_DIR, session_id, paste0("empt_", make.names(experiment), ".rds"))
}

diff_raw_path <- function(session_id, experiment) {
  file.path(SESSION_DIR, session_id, paste0("diff_raw_", make.names(experiment), ".rds"))
}

raw_empt_path <- function(session_id, experiment) {
  file.path(SESSION_DIR, session_id, paste0("raw_empt_", make.names(experiment), ".rds"))
}

prepare_snapshot_dir <- function(session_id, experiment) {
  file.path(SESSION_DIR, session_id, "prepare_snapshots", make.names(experiment))
}

save_raw_empt <- function(session_id, experiment, empt) {
  saveRDS(empt, raw_empt_path(session_id, experiment))
}

load_raw_empt <- function(session_id, experiment) {
  p <- raw_empt_path(session_id, experiment)
  if (!file.exists(p)) return(NULL)
  readRDS(p)
}

save_prepare_snapshot <- function(session_id, experiment, empt, label = NULL) {
  dir <- prepare_snapshot_dir(session_id, experiment)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  stamp <- format(Sys.time(), "%Y%m%d-%H%M%S")
  safe <- if (is.null(label) || !nzchar(label)) "snapshot" else make.names(label)
  id <- paste0(stamp, "_", safe)
  saveRDS(empt, file.path(dir, paste0(id, ".rds")))
  id
}

load_prepare_snapshot <- function(session_id, experiment, snapshot_id) {
  if (is.null(snapshot_id) || !nzchar(snapshot_id)) return(NULL)
  p <- file.path(prepare_snapshot_dir(session_id, experiment), paste0(snapshot_id, ".rds"))
  if (!file.exists(p)) return(NULL)
  readRDS(p)
}

list_prepare_snapshots <- function(session_id, experiment) {
  dir <- prepare_snapshot_dir(session_id, experiment)
  if (!dir.exists(dir)) return(data.frame(snapshot_id = character(), mtime = character(), stringsAsFactors = FALSE))
  files <- list.files(dir, pattern = "\\.rds$", full.names = TRUE)
  if (!length(files)) return(data.frame(snapshot_id = character(), mtime = character(), stringsAsFactors = FALSE))
  data.frame(
    snapshot_id = sub("\\.rds$", "", basename(files)),
    mtime = format(file.mtime(files), "%Y-%m-%d %H:%M:%S"),
    stringsAsFactors = FALSE
  )
}

create_session <- function() {
  id <- new_session_id()
  dir.create(session_path(id), recursive = TRUE, showWarnings = FALSE)
  id
}

session_exists <- function(session_id) {
  dir.exists(session_path(session_id))
}

save_mae <- function(session_id, mae) {
  saveRDS(mae, mae_path(session_id))
}

load_mae <- function(session_id) {
  p <- mae_path(session_id)
  if (!file.exists(p)) stop("Session data not found. Please import data first.")
  readRDS(p)
}

# ------------------------------------------------------------------
# EMPT in-process cache
# ------------------------------------------------------------------
# Re-reading & re-promoting a SummarizedExperiment from disk on every
# API call is expensive (RNAseq ~1s, 16S ~50ms) and happens for *every*
# analyze/* and visualize/* endpoint.  We cache the last-loaded EMPT
# keyed by (session_id, experiment).  The cache is invalidated when the
# backing file mtime changes (i.e. after save_empt() rewrites it).
#
# The cache lives inside the plumber R process – async jobs fork a new
# R session via callr and do NOT share this cache, which is fine because
# they run `save_empt()` on exit and the next request will reload from
# disk with the fresh mtime.
.EMPT_CACHE <- new.env(parent = emptyenv())

.cache_key <- function(session_id, experiment) paste0(session_id, "::", experiment)

.cache_put <- function(session_id, experiment, empt, mtime) {
  assign(.cache_key(session_id, experiment),
         list(empt = empt, mtime = mtime),
         envir = .EMPT_CACHE)
}

.cache_get <- function(session_id, experiment, mtime) {
  k <- .cache_key(session_id, experiment)
  if (!exists(k, envir = .EMPT_CACHE, inherits = FALSE)) return(NULL)
  entry <- get(k, envir = .EMPT_CACHE, inherits = FALSE)
  if (!identical(entry$mtime, mtime)) return(NULL)
  entry$empt
}

.cache_drop_session <- function(session_id) {
  prefix <- paste0(session_id, "::")
  ks <- ls(.EMPT_CACHE, all.names = TRUE)
  for (k in ks) {
    if (startsWith(k, prefix)) rm(list = k, envir = .EMPT_CACHE)
  }
}

save_empt <- function(session_id, experiment, empt) {
  p <- empt_path(session_id, experiment)
  saveRDS(empt, p)
  .cache_put(session_id, experiment, empt, file.mtime(p))
}

.is_proper_empt <- function(obj) {
  if (is.null(obj)) return(FALSE)
  cls <- class(obj)
  any(grepl("^EMP", cls)) || methods::isVirtualClass("EMPT") && methods::is(obj, "EMPT")
}

.promote_to_empt <- function(mae, experiment) {
  # Use the package's public extractor, which wraps .as.EMPT and
  # reliably converts a MAE experiment into a full EMPT with
  # colData, rowData (with `feature` column), and history slots.
  tryCatch(
    EasyMultiProfiler::EMP_assay_extract(mae, experiment = experiment),
    error = function(e) {
      # Fall back to internal constructor if public wrapper fails.
      tryCatch(EasyMultiProfiler:::.as.EMPT(mae, experiment = experiment),
               error = function(e2) stop(e2$message))
    }
  )
}

load_empt <- function(session_id, experiment) {
  p <- empt_path(session_id, experiment)
  if (file.exists(p)) {
    mtime <- file.mtime(p)
    cached <- .cache_get(session_id, experiment, mtime)
    if (!is.null(cached)) return(cached)
    obj <- readRDS(p)
    if (.is_proper_empt(obj)) {
      .cache_put(session_id, experiment, obj, mtime)
      return(obj)
    }
  }
  mae <- load_mae(session_id)
  empt <- .promote_to_empt(mae, experiment)
  # Persist the promoted EMPT so the next call can hit the cache.
  tryCatch({
    saveRDS(empt, p)
    .cache_put(session_id, experiment, empt, file.mtime(p))
  }, error = function(e) invisible(NULL))
  empt
}

delete_session <- function(session_id) {
  p <- session_path(session_id)
  if (dir.exists(p)) unlink(p, recursive = TRUE)
  .cache_drop_session(session_id)
}

list_experiments <- function(session_id) {
  mae <- load_mae(session_id)
  names(mae)
}
