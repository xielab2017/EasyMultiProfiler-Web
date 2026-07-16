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
  ensure_session_dir(session_id)
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

ensure_session_dir <- function(session_id) {
  if (is.null(session_id) || !nzchar(session_id)) return(FALSE)
  p <- session_path(session_id)
  if (!dir.exists(p)) dir.create(p, recursive = TRUE, showWarnings = FALSE)
  dir.exists(p)
}

session_exists <- function(session_id) {
  dir.exists(session_path(session_id))
}

# In-process MAE cache (mtime-keyed), mirroring the EMPT cache below. load_mae
# is called on most prep/analyze/import paths; re-reading the RDS each time is
# wasteful. The cache is invalidated automatically when save_mae() rewrites the
# file (mtime changes). R copy-on-modify means callers that mutate the returned
# object do not corrupt the cached copy.
.MAE_CACHE <- new.env(parent = emptyenv())

save_mae <- function(session_id, mae) {
  ensure_session_dir(session_id)
  p <- mae_path(session_id)
  saveRDS(mae, p)
  assign(session_id, list(mae = mae, mtime = file.mtime(p)), envir = .MAE_CACHE)
  tryCatch(write_experiments_meta(session_id, mae), error = function(e) NULL)
}

load_mae <- function(session_id) {
  p <- mae_path(session_id)
  if (!file.exists(p)) stop("Session data not found. Please import data first.")
  mtime <- file.mtime(p)
  if (exists(session_id, envir = .MAE_CACHE, inherits = FALSE)) {
    entry <- get(session_id, envir = .MAE_CACHE, inherits = FALSE)
    if (identical(entry$mtime, mtime)) return(entry$mae)
  }
  mae <- readRDS(p)
  assign(session_id, list(mae = mae, mtime = mtime), envir = .MAE_CACHE)
  mae
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
  if (exists(session_id, envir = .MAE_CACHE, inherits = FALSE)) {
    rm(list = session_id, envir = .MAE_CACHE)
  }
}

save_empt <- function(session_id, experiment, empt) {
  ensure_session_dir(session_id)
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
      old_rn <- rownames(SummarizedExperiment::assays(obj)[[1]])
      obj <- restore_feature_rownames(obj)
      new_rn <- rownames(SummarizedExperiment::assays(obj)[[1]])
      if (!identical(old_rn, new_rn)) save_empt(session_id, experiment, obj)
      mtime <- file.mtime(p)
      .cache_put(session_id, experiment, obj, mtime)
      return(obj)
    }
  }
  mae <- load_mae(session_id)
  empt <- .promote_to_empt(mae, experiment)
  empt <- restore_feature_rownames(empt)
  # Persist the promoted EMPT so the next call can hit the cache.
  tryCatch({
    saveRDS(empt, p)
    .cache_put(session_id, experiment, empt, file.mtime(p))
  }, error = function(e) invisible(NULL))
  empt
}

# Shared by /api/prepare/* routes and Code Lab preparation snippets.
.prepare_load_base <- function(session_id, experiment, mode = "stack") {
  m <- tolower(trimws(as.character(mode %||% "stack")))
  if (identical(m, "single")) {
    raw <- load_raw_empt(session_id, experiment)
    if (!is.null(raw)) return(raw)
  }
  load_empt(session_id, experiment)
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

experiments_meta_path <- function(session_id) {
  file.path(session_path(session_id), "experiments_meta.json")
}

experiment_registry_path <- function(session_id) {
  file.path(session_path(session_id), "experiment_registry.json")
}

data_type_to_omics <- function(data_type) {
  switch(data_type,
    tax = "microbiome_16s",
    normal = "transcriptomics",
    chipseq = "chipseq",
    "transcriptomics"
  )
}

read_experiment_registry <- function(session_id) {
  p <- experiment_registry_path(session_id)
  if (!file.exists(p)) return(list())
  tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) list())
}

register_experiment_meta <- function(session_id, experiment_name, data_type, omics = NULL) {
  ensure_session_dir(session_id)
  reg <- read_experiment_registry(session_id)
  reg[[experiment_name]] <- list(
    data_type = data_type,
    omics = omics %||% data_type_to_omics(data_type)
  )
  jsonlite::write_json(reg, experiment_registry_path(session_id), auto_unbox = TRUE, null = "null")
  invisible(reg)
}

enrich_experiments_with_registry <- function(session_id, info) {
  reg <- read_experiment_registry(session_id)
  lapply(info, function(e) {
    extra <- reg[[e$name]]
    if (!is.null(extra)) {
      e$data_type <- extra$data_type %||% NULL
      e$omics <- extra$omics %||% NULL
    } else if (grepl("16s|m16s|tax", e$name, ignore.case = TRUE)) {
      e$omics <- "microbiome_16s"
      e$data_type <- "tax"
    } else {
      e$omics <- "transcriptomics"
      e$data_type <- "normal"
    }
    e
  })
}

write_experiments_meta <- function(session_id, mae) {
  exps <- names(mae)
  info <- lapply(exps, function(e) {
    ex <- mae[[e]]
    list(
      name = e,
      samples = ncol(ex),
      features = nrow(ex),
      assay = names(SummarizedExperiment::assays(ex))[1]
    )
  })
  meta <- list(
    mae_mtime = as.numeric(file.mtime(mae_path(session_id))),
    experiments = info
  )
  jsonlite::write_json(meta, experiments_meta_path(session_id), auto_unbox = TRUE, null = "null")
  invisible(info)
}

read_experiments_meta <- function(session_id) {
  mp <- experiments_meta_path(session_id)
  mae_p <- mae_path(session_id)
  if (!file.exists(mp) || !file.exists(mae_p)) return(NULL)
  meta <- tryCatch(jsonlite::fromJSON(mp, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(meta) || is.null(meta$experiments)) return(NULL)
  stored <- suppressWarnings(as.numeric(meta$mae_mtime))
  cur <- as.numeric(file.mtime(mae_p))
  if (!is.finite(stored) || abs(stored - cur) > 1e-3) return(NULL)
  meta$experiments
}

list_experiments_info <- function(session_id) {
  cached <- read_experiments_meta(session_id)
  if (is.null(cached)) {
    if (!file.exists(mae_path(session_id))) return(list())
    mae <- load_mae(session_id)
    write_experiments_meta(session_id, mae)
    cached <- read_experiments_meta(session_id)
  }
  if (is.null(cached)) return(list())
  enrich_experiments_with_registry(session_id, cached)
}
