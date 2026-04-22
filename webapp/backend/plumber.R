# EasyMultiProfiler – Plumber REST API
# All routes for the web platform

library(EasyMultiProfiler)
library(MultiAssayExperiment)
library(SummarizedExperiment)
library(S4Vectors)
library(ggplot2)
library(base64enc)

# Source helpers (absolute paths set at startup via env var or inferred)
.BACKEND_DIR <- Sys.getenv("BACKEND_DIR", unset = "/app")

source(file.path(.BACKEND_DIR, "helpers/session.R"))
source(file.path(.BACKEND_DIR, "helpers/utils.R"))
source(file.path(.BACKEND_DIR, "helpers/plot_theme.R"))
source(file.path(.BACKEND_DIR, "helpers/import.R"))
source(file.path(.BACKEND_DIR, "helpers/analysis.R"))
source(file.path(.BACKEND_DIR, "helpers/viz.R"))
source(file.path(.BACKEND_DIR, "helpers/workflow_registry.R"))
source(file.path(.BACKEND_DIR, "helpers/workflow_metabolomics.R"))
source(file.path(.BACKEND_DIR, "helpers/workflow_metagenomics.R"))
source(file.path(.BACKEND_DIR, "helpers/workflow_transcriptomics.R"))
source(file.path(.BACKEND_DIR, "helpers/workflow_microbiome_16s.R"))
source(file.path(.BACKEND_DIR, "helpers/workflow_microbiome_16s_api.R"))
source(file.path(.BACKEND_DIR, "helpers/clinical.R"))
source(file.path(.BACKEND_DIR, "helpers/jobs.R"))
Sys.setenv(EMP_BACKEND_DIR = .BACKEND_DIR)

#* @filter cors
#* @serializer unboxedJSON
function(req, res) {
  res$setHeader("Access-Control-Allow-Origin",  "*")
  res$setHeader("Access-Control-Allow-Methods", "GET,POST,DELETE,OPTIONS")
  res$setHeader("Access-Control-Allow-Headers", "Content-Type,X-Session-Id")
  if (req$REQUEST_METHOD == "OPTIONS") {
    res$status <- 200
    return(list())
  }
  plumber::forward()
}

# ══════════════════════════════════════════════════════════
# SESSION
# ══════════════════════════════════════════════════════════

#* List all supported omics workflows
#* @get /api/workflows
#* @serializer unboxedJSON
function(res) {
  safe_api({
    list(success = TRUE, workflows = list_workflows())
  }, res)
}

#* Get workflow blueprint by id
#* @get /api/workflows/<workflow_id>
#* @serializer unboxedJSON
function(workflow_id, res) {
  safe_api({
    list(success = TRUE, workflow = get_workflow(workflow_id))
  }, res)
}

#* Create a new analysis session
#* @post /api/session
#* @serializer unboxedJSON
function(res) {
  safe_api({
    id <- create_session()
    list(success = TRUE, session_id = id)
  }, res)
}

#* Delete a session and free its storage
#* @delete /api/session/<session_id>
#* @serializer unboxedJSON
function(session_id, res) {
  safe_api({
    delete_session(session_id)
    list(success = TRUE)
  }, res)
}

#* List experiments in session
#* @get /api/session/<session_id>/experiments
#* @serializer unboxedJSON
function(session_id, res) {
  safe_api({
    mae  <- load_mae(session_id)
    exps <- names(mae)
    info <- lapply(exps, function(e) {
      ex <- mae[[e]]
      list(name     = e,
           samples  = ncol(ex),
           features = nrow(ex),
           assay    = names(SummarizedExperiment::assays(ex))[1])
    })
    list(success = TRUE, experiments = info)
  }, res)
}

# ══════════════════════════════════════════════════════════
# IMPORT
# ══════════════════════════════════════════════════════════

# Helper: save a Plumber multipart file entry to a temp file, return path
.save_upload <- function(file_entry, suffix = ".tmp") {
  if (is.null(file_entry)) return(NULL)
  # Plumber stores file bytes in $value (raw vector)
  raw_bytes <- file_entry$value
  if (is.null(raw_bytes) || length(raw_bytes) == 0) return(NULL)
  # Try to preserve extension from original filename
  orig <- file_entry$filename %||% ""
  ext  <- if (nzchar(orig)) paste0(".", tools::file_ext(orig)) else suffix
  tmp  <- tempfile(fileext = ext)
  writeBin(raw_bytes, tmp)
  tmp
}

#* Import data file (multipart: data_file, [metadata_file])
#* @post /api/import
#* @parser multi
#* @serializer unboxedJSON
function(req, res,
         experiment_name = "experiment",
         data_type       = "normal",
         assay_name      = "counts",
         start_level     = "Species",
         tax_sep         = ";",
         session_id      = NULL) {
  safe_api({
    body      <- req$body
    # Plumber multipart: file is a list with $value (raw bytes)
    data_file <- .save_upload(body$data_file, ".csv")
    if (is.null(data_file)) stop("data_file is required")

    meta_file <- .save_upload(body$metadata_file, ".csv")

    # Create session if not provided
    if (is.null(session_id) || session_id == "") session_id <- create_session()

    # Check if MAE already exists → add experiment
    mae_exists <- file.exists(mae_path(session_id))
    if (data_type %in% c("clinical_meta", "clinical_raw")) {
      meta_upload <- read_metadata_table(data_file)
      standalone_path <- if (identical(data_type, "clinical_meta")) {
        file.path(dirname(mae_path(session_id)), "clinical_uploaded_meta.csv")
      } else {
        file.path(dirname(mae_path(session_id)), "clinical_uploaded_raw.csv")
      }
      if (!mae_exists) {
        meta <- meta_upload
        utils::write.csv(meta, standalone_path, row.names = FALSE)
        if (identical(data_type, "clinical_raw")) {
          # Backward compatibility for sessions created before split storage.
          p_legacy <- file.path(dirname(mae_path(session_id)), "clinical_uploaded.csv")
          utils::write.csv(meta, p_legacy, row.names = FALSE)
        }
        return(list(
          success = TRUE,
          session_id = session_id,
          import_mode = "clinical_standalone",
          updated_experiments = 0L,
          columns = setdiff(names(meta), "primary"),
          orientation = attr(meta, "orientation_note") %||% "samples in rows"
        ))
      }
      mae <- load_mae(session_id)
      out <- tryCatch({
        merged <- merge_metadata_into_mae(mae, data_file)
        mae <- merged$mae
        save_mae(session_id, mae)
        exp_names <- names(as.list(MultiAssayExperiment::experiments(mae)))
        for (exn in exp_names) {
          tryCatch(save_raw_empt(session_id, exn, .promote_to_empt(mae, exn)), error = function(e) NULL)
        }
        list(
          success = TRUE,
          session_id = session_id,
          import_mode = "clinical_merge",
          updated_experiments = merged$touched,
          columns = merged$columns,
          orientation = attr(meta_upload, "orientation_note") %||% "samples in rows"
        )
      }, error = function(e) {
        msg <- as.character(conditionMessage(e))
        if (grepl("No matching sample IDs", msg, ignore.case = TRUE)) {
          meta <- meta_upload
          utils::write.csv(meta, standalone_path, row.names = FALSE)
          if (identical(data_type, "clinical_raw")) {
            p_legacy <- file.path(dirname(mae_path(session_id)), "clinical_uploaded.csv")
            utils::write.csv(meta, p_legacy, row.names = FALSE)
          }
          list(
            success = TRUE,
            session_id = session_id,
            import_mode = "clinical_standalone",
            updated_experiments = 0L,
            columns = setdiff(names(meta), "primary"),
            orientation = attr(meta, "orientation_note") %||% "samples in rows"
          )
        } else {
          stop(e)
        }
      })
      return(out)
    }

    if (mae_exists) {
      mae <- load_mae(session_id)
      mae <- add_experiment_to_mae(mae, data_file, meta_file,
                                    experiment_name, data_type,
                                    assay_name, start_level, tax_sep)
    } else {
      mae <- build_mae(data_file, meta_file,
                       experiment_name, data_type,
                       assay_name, start_level, tax_sep)
    }

    save_mae(session_id, mae)
    tryCatch({
      save_raw_empt(session_id, experiment_name, .promote_to_empt(mae, experiment_name))
    }, error = function(e) NULL)

    # Summarise
    ex <- mae[[experiment_name]]
    list(success         = TRUE,
         session_id      = session_id,
         experiment_name = experiment_name,
         samples         = ncol(ex),
         features        = nrow(ex),
         assay           = assay_name)
  }, res)
}

#* Reorient standalone clinical table.
#* Body: { session_id, mode } where mode in {"auto","transpose"}
#* @post /api/clinical/reorient
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    mode <- b$mode %||% "auto"
    out <- reorient_standalone_clinical_table(session_id = session_id, mode = mode)
    list(success = TRUE, mode = out$mode, orientation = out$orientation,
         n_samples = out$n_samples, n_variables = out$n_variables,
         warning = out$warning %||% NULL)
  }, res)
}

#* Preview file columns (multipart: data_file)
#* @post /api/preview
#* @parser multi
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    data_file <- .save_upload(req$body$data_file, ".csv")
    if (is.null(data_file)) stop("data_file is required")
    df <- read_table_auto(data_file, nrows = 5)
    list(success  = TRUE,
         columns  = names(df),
         nrow     = nrow(df),
         preview  = jsonlite::toJSON(df[seq_len(min(5, nrow(df))), ], na = "null", auto_unbox = TRUE))
  }, res)
}

# ══════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════

#* Get experiment summary
#* @get /api/summary/<session_id>/<experiment>
#* @serializer unboxedJSON
function(session_id, experiment, res) {
  safe_api({
    empt    <- load_empt(session_id, experiment)
    ad      <- SummarizedExperiment::assays(empt)[[1]]
    cd      <- as.data.frame(SummarizedExperiment::colData(empt))
    rd      <- as.data.frame(SummarizedExperiment::rowData(empt))

    coldata_records <- lapply(seq_len(nrow(cd)), function(i) {
      row <- as.list(cd[i, , drop = FALSE])
      row$sample <- rownames(cd)[i]
      row
    })

    list(
      success      = TRUE,
      n_samples    = ncol(ad),
      n_features   = nrow(ad),
      assay_name   = names(SummarizedExperiment::assays(empt))[1],
      sample_names = colnames(ad),
      feature_names= rownames(ad)[seq_len(min(20, nrow(ad)))],
      coldata_cols = names(cd),
      coldata      = coldata_records,
      rowdata_cols = names(rd)
    )
  }, res)
}

#* Get coldata columns (for group selection)
#* @get /api/coldata/<session_id>/<experiment>
#* @serializer unboxedJSON
function(session_id, experiment, res) {
  safe_api({
    empt <- load_empt(session_id, experiment)
    cd   <- as.data.frame(SummarizedExperiment::colData(empt))
    cols <- lapply(names(cd), function(col) {
      vals <- unique(na.omit(cd[[col]]))
      list(name   = col,
           n_unique = length(vals),
           values = as.character(vals[seq_len(min(20, length(vals)))]))
    })
    list(success = TRUE, columns = cols)
  }, res)
}

#* Get feature list
#* @get /api/features/<session_id>/<experiment>
#* @serializer unboxedJSON
function(session_id, experiment, res) {
  safe_api({
    empt     <- load_empt(session_id, experiment)
    features <- rownames(SummarizedExperiment::assays(empt)[[1]])
    list(success = TRUE, features = features)
  }, res)
}

#* Inspector overview for EMPT object
#* @get /api/inspect/<session_id>/<experiment>
#* @serializer unboxedJSON
function(session_id, experiment, res) {
  safe_api({
    empt <- load_empt(session_id, experiment)
    ad <- SummarizedExperiment::assays(empt)[[1]]
    cd <- as.data.frame(SummarizedExperiment::colData(empt))
    rd <- as.data.frame(SummarizedExperiment::rowData(empt))
    assay_name <- names(SummarizedExperiment::assays(empt))[1]
    if (is.null(assay_name) || !nzchar(assay_name)) assay_name <- "assay"
    list(
      success = TRUE,
      summary = list(
        experiment = experiment,
        assay_name = assay_name,
        n_features = nrow(ad),
        n_samples = ncol(ad),
        n_coldata_cols = ncol(cd),
        n_rowdata_cols = ncol(rd)
      )
    )
  }, res)
}

#* Inspector assay preview (paged)
#* @get /api/inspect/assay/<session_id>/<experiment>
#* @serializer unboxedJSON
function(session_id, experiment, offset = 1, limit = 20, res) {
  safe_api({
    empt <- load_empt(session_id, experiment)
    ad <- SummarizedExperiment::assays(empt)[[1]]
    total <- nrow(ad)
    offset_i <- max(1L, suppressWarnings(as.integer(offset %||% 1L)))
    limit_i <- max(1L, min(200L, suppressWarnings(as.integer(limit %||% 20L))))
    end_i <- min(total, offset_i + limit_i - 1L)
    idx <- if (total == 0 || offset_i > total) integer(0) else seq.int(offset_i, end_i)
    ad_slice <- ad[idx, , drop = FALSE]
    df <- as.data.frame(ad_slice, stringsAsFactors = FALSE)
    df$feature <- rownames(ad_slice)
    df <- df[, c("feature", setdiff(names(df), "feature")), drop = FALSE]
    list(
      success = TRUE,
      total = total,
      offset = offset_i,
      limit = limit_i,
      rows = jsonlite::toJSON(df, na = "null", auto_unbox = TRUE)
    )
  }, res)
}

#* Inspector colData preview
#* @get /api/inspect/coldata/<session_id>/<experiment>
#* @serializer unboxedJSON
function(session_id, experiment, res) {
  safe_api({
    empt <- load_empt(session_id, experiment)
    cd <- as.data.frame(SummarizedExperiment::colData(empt), stringsAsFactors = FALSE)
    if (nrow(cd) > 0) {
      cd$sample <- rownames(cd)
      cd <- cd[, c("sample", setdiff(names(cd), "sample")), drop = FALSE]
    }
    list(success = TRUE, rows = jsonlite::toJSON(cd, na = "null", auto_unbox = TRUE))
  }, res)
}

#* Inspector rowData preview
#* @get /api/inspect/rowdata/<session_id>/<experiment>
#* @serializer unboxedJSON
function(session_id, experiment, offset = 1, limit = 50, res) {
  safe_api({
    empt <- load_empt(session_id, experiment)
    rd <- as.data.frame(SummarizedExperiment::rowData(empt))
    total <- nrow(rd)
    offset_i <- max(1L, suppressWarnings(as.integer(offset %||% 1L)))
    limit_i <- max(1L, min(500L, suppressWarnings(as.integer(limit %||% 50L))))
    end_i <- min(total, offset_i + limit_i - 1L)
    idx <- if (total == 0 || offset_i > total) integer(0) else seq.int(offset_i, end_i)
    rd_slice <- rd[idx, , drop = FALSE]
    if (nrow(rd_slice) > 0) {
      rd_slice$feature <- rownames(rd_slice)
      rd_slice <- rd_slice[, c("feature", setdiff(names(rd_slice), "feature")), drop = FALSE]
    }
    list(
      success = TRUE,
      total = total,
      offset = offset_i,
      limit = limit_i,
      rows = jsonlite::toJSON(rd_slice, na = "null", auto_unbox = TRUE)
    )
  }, res)
}

#* Inspector: list available EMP result tables
#* @get /api/inspect/results/<session_id>/<experiment>
#* @serializer unboxedJSON
function(session_id, experiment, res) {
  safe_api({
    empt <- load_empt(session_id, experiment)
    candidates <- c(
      "diversity_result", "diff_analysis_result", "dimension_coordinate",
      "dimension_axis", "dimension_VIP", "sample_cluster_result",
      "feature_cluster_result", "enrich_data", "rf_feature_importance",
      "net", "net_feature_info", "net_centrality"
    )
    available <- Filter(function(info) {
      out <- tryCatch(EasyMultiProfiler::EMP_result(empt, info = info), error = function(e) NULL)
      !is.null(out)
    }, candidates)
    list(success = TRUE, results = available)
  }, res)
}

#* Inspector: preview one EMP result table
#* @get /api/inspect/result/<session_id>/<experiment>/<result_name>
#* @serializer unboxedJSON
function(session_id, experiment, result_name, res) {
  safe_api({
    empt <- load_empt(session_id, experiment)
    result <- EasyMultiProfiler::EMP_result(empt, info = result_name)
    result_df <- tryCatch(as.data.frame(result), error = function(e) data.frame())
    list(
      success = TRUE,
      result_name = result_name,
      n_rows = nrow(result_df),
      rows = jsonlite::toJSON(result_df, na = "null", auto_unbox = TRUE)
    )
  }, res)
}

# ══════════════════════════════════════════════════════════
# DATA PREPARATION
# ══════════════════════════════════════════════════════════

.prepare_load_base <- function(session_id, experiment, mode = "stack") {
  m <- tolower(trimws(as.character(mode %||% "stack")))
  if (identical(m, "single")) {
    raw <- load_raw_empt(session_id, experiment)
    if (!is.null(raw)) return(raw)
  }
  load_empt(session_id, experiment)
}

#* Filter features by count / prevalence
#* @post /api/prepare/filter
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    min_count  <- as.numeric(b$min_count  %||% 0)
    min_samples<- as.integer(b$min_samples %||% 0L)
    min_detect_rate <- as.numeric(b$min_detect_rate %||% NA_real_)
    max_detect_rate <- as.numeric(b$max_detect_rate %||% NA_real_)
    min_prevalence <- as.numeric(b$min_prevalence %||% 0)
    max_na     <- as.numeric(b$max_na     %||% 1)

    mode <- b$prepare_mode %||% "stack"
    empt  <- .prepare_load_base(session_id, experiment, mode = mode)
    ad    <- SummarizedExperiment::assays(empt)[[1]]
    keep  <- rep(TRUE, nrow(ad))
    if (min_count  > 0) keep <- keep & apply(ad, 1, max, na.rm = TRUE) >= min_count
    if (min_samples> 0) keep <- keep & apply(ad, 1, function(x) sum(x > 0, na.rm=TRUE)) >= min_samples
    if (is.finite(min_detect_rate) && min_detect_rate > 0) {
      keep <- keep & apply(ad, 1, function(x) mean(x > 0, na.rm = TRUE)) >= min_detect_rate
    }
    if (is.finite(max_detect_rate) && max_detect_rate < 1) {
      keep <- keep & apply(ad, 1, function(x) mean(x > 0, na.rm = TRUE)) <= max_detect_rate
    }
    if (min_prevalence > 0) {
      keep <- keep & apply(ad, 1, function(x) mean(x > 0, na.rm = TRUE)) >= min_prevalence
    }
    if (max_na     < 1) keep <- keep & apply(ad, 1, function(x) sum(is.na(x))/length(x)) <= max_na

    empt_filtered <- empt[keep, ]

    # Update MAE
    mae            <- load_mae(session_id)
    mae[[experiment]] <- empt_filtered
    save_mae(session_id, mae)
    save_empt(session_id, experiment, empt_filtered)
    snap_id <- save_prepare_snapshot(session_id, experiment, empt_filtered, label = "filter")

    list(success = TRUE,
         kept    = sum(keep),
         removed = sum(!keep),
         prepare_mode = mode,
         snapshot_id = snap_id,
         preview_data = emp_prepare_preview_rows(empt_filtered))
  }, res)
}

#* Normalize data
#* @post /api/prepare/normalize
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    method     <- b$method %||% "rclr"

    mode <- b$prepare_mode %||% "stack"
    empt <- .prepare_load_base(session_id, experiment, mode = mode)
    empt <- empt |> EasyMultiProfiler::EMP_decostand(method = method)

    mae            <- load_mae(session_id)
    mae[[experiment]] <- empt
    save_mae(session_id, mae)
    save_empt(session_id, experiment, empt)
    snap_id <- save_prepare_snapshot(session_id, experiment, empt, label = paste0("normalize_", method))

    list(success = TRUE, method = method, prepare_mode = mode,
         snapshot_id = snap_id,
         preview_data = emp_prepare_preview_rows(empt))
  }, res)
}

#* Impute missing values
#* @post /api/prepare/impute
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    method     <- b$method %||% "knn"

    mode <- b$prepare_mode %||% "stack"
    empt <- .prepare_load_base(session_id, experiment, mode = mode)
    empt <- empt |> EasyMultiProfiler::EMP_impute(method = method)

    mae            <- load_mae(session_id)
    mae[[experiment]] <- empt
    save_mae(session_id, mae)
    save_empt(session_id, experiment, empt)
    snap_id <- save_prepare_snapshot(session_id, experiment, empt, label = paste0("impute_", method))

    list(success = TRUE, method = method, prepare_mode = mode,
         snapshot_id = snap_id,
         preview_data = emp_prepare_preview_rows(empt))
  }, res)
}

#* Rarefy counts
#* @post /api/prepare/rarefy
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    sample_size<- as.integer(b$sample_size %||% 0L)

    mode <- b$prepare_mode %||% "stack"
    empt <- .prepare_load_base(session_id, experiment, mode = mode)
    args <- list(empt)
    if (sample_size > 0) args[["sample"]] <- sample_size
    empt <- do.call(EasyMultiProfiler::EMP_rrarefy, args)

    mae            <- load_mae(session_id)
    mae[[experiment]] <- empt
    save_mae(session_id, mae)
    save_empt(session_id, experiment, empt)
    snap_id <- save_prepare_snapshot(session_id, experiment, empt, label = "rarefy")

    list(success = TRUE, prepare_mode = mode,
         snapshot_id = snap_id,
         preview_data = emp_prepare_preview_rows(empt))
  }, res)
}

#* Collapse taxonomy
#* @post /api/prepare/collapse
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    taxa_level <- b$taxa_level %||% "Genus"

    mode <- b$prepare_mode %||% "stack"
    empt <- .prepare_load_base(session_id, experiment, mode = mode)
    empt <- empt |> EasyMultiProfiler::EMP_collapse(taxa_level = taxa_level)

    mae            <- load_mae(session_id)
    mae[[experiment]] <- empt
    save_mae(session_id, mae)
    save_empt(session_id, experiment, empt)
    snap_id <- save_prepare_snapshot(session_id, experiment, empt, label = paste0("collapse_", taxa_level))

    list(success = TRUE, taxa_level = taxa_level,
         n_features = nrow(SummarizedExperiment::assays(empt)[[1]]),
         prepare_mode = mode,
         snapshot_id = snap_id,
         preview_data = emp_prepare_preview_rows(empt))
  }, res)
}

#* List preparation snapshots for an experiment
#* @get /api/prepare/snapshots/<session_id>/<experiment>
#* @serializer unboxedJSON
function(session_id, experiment, res) {
  safe_api({
    snaps <- list_prepare_snapshots(session_id, experiment)
    list(success = TRUE, n_rows = nrow(snaps), snapshots = snaps)
  }, res)
}

#* Activate one preparation snapshot as current working data
#* @post /api/prepare/use_snapshot
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    snapshot_id <- b$snapshot_id
    empt <- load_prepare_snapshot(session_id, experiment, snapshot_id)
    if (is.null(empt)) stop("Snapshot not found.")
    mae <- load_mae(session_id)
    mae[[experiment]] <- empt
    save_mae(session_id, mae)
    save_empt(session_id, experiment, empt)
    list(success = TRUE, snapshot_id = snapshot_id)
  }, res)
}

# ══════════════════════════════════════════════════════════
# ANALYSIS
# ══════════════════════════════════════════════════════════

#* Transcriptomics workflow profile
#* @post /api/workflows/transcriptomics/profile
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    assay_hint <- b$assay_hint %||% "counts"
    profile <- tx_profile(session_id, experiment, assay_hint)
    list(success = TRUE, profile = profile)
  }, res)
}

#* Transcriptomics workflow pre-check validation
#* @post /api/workflows/transcriptomics/validate
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    list(success = TRUE, validation = tx_validate(session_id, experiment))
  }, res)
}

#* Transcriptomics differential analysis
#* @post /api/workflows/transcriptomics/analyze/differential
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    method <- b$method %||% "DESeq2"
    group_var <- b$group_var %||% NULL
    ref_group <- b$ref_group %||% NULL
    test_group <- b$test_group %||% NULL
    filter_low        <- if (is.null(b$filter_low))        TRUE else isTRUE(b$filter_low)
    subset_two_groups <- if (is.null(b$subset_two_groups)) TRUE else isTRUE(b$subset_two_groups)
    cores             <- b$cores %||% "auto"

    result <- tx_run_differential(
      session_id = session_id,
      experiment = experiment,
      method = method,
      group_var = group_var,
      ref_group = ref_group,
      test_group = test_group,
      filter_low = filter_low,
      subset_two_groups = subset_two_groups,
      cores = cores
    )
    result_df <- tryCatch(as.data.frame(result), error = function(e) data.frame())

    list(
      success = TRUE,
      n_rows = nrow(result_df),
      columns = names(result_df),
      data = jsonlite::toJSON(result_df, na = "null", auto_unbox = TRUE)
    )
  }, res)
}

#* Transcriptomics GSEA analysis
#* @post /api/workflows/transcriptomics/analyze/gsea
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    database <- b$database %||% "KEGG"
    organism <- b$organism %||% "hsa"

    result <- tx_run_gsea(
      session_id = session_id,
      experiment = experiment,
      database = database,
      organism = organism
    )
    result_df <- tryCatch(as.data.frame(result), error = function(e) data.frame())

    list(
      success = TRUE,
      n_rows = nrow(result_df),
      columns = names(result_df),
      data = jsonlite::toJSON(result_df, na = "null", auto_unbox = TRUE)
    )
  }, res)
}

#* Transcriptomics WGCNA analysis
#* @post /api/workflows/transcriptomics/analyze/wgcna
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    method <- b$method %||% "spearman"
    cutoff <- as.numeric(b$cutoff %||% 0.7)

    result <- tx_run_wgcna(
      session_id = session_id,
      experiment = experiment,
      method = method,
      cutoff = cutoff
    )
    result_df <- tryCatch(as.data.frame(result), error = function(e) data.frame())

    list(
      success = TRUE,
      mode = "correlation_fallback",
      n_rows = nrow(result_df),
      columns = names(result_df),
      data = jsonlite::toJSON(result_df, na = "null", auto_unbox = TRUE)
    )
  }, res)
}

#* Metagenomics workflow profile (functional matrix checks)
#* @post /api/workflows/metagenomics/profile
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    id_type <- b$id_type %||% "auto"
    profile <- mgx_profile(session_id, experiment, id_type)
    list(success = TRUE, profile = profile)
  }, res)
}

#* Metagenomics workflow pre-check validation
#* @post /api/workflows/metagenomics/validate
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    id_type <- b$id_type %||% "auto"
    list(success = TRUE, validation = mgx_validate(session_id, experiment, id_type))
  }, res)
}

#* Metagenomics preprocess with functional defaults
#* @post /api/workflows/metagenomics/preprocess
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    max_na <- b$max_na %||% 0.2
    normalize_method <- b$normalize_method %||% "rclr"

    mgx_preprocess(session_id, experiment, max_na, normalize_method)
  }, res)
}

#* Metagenomics differential analysis
#* @post /api/workflows/metagenomics/analyze/differential
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    id_type <- b$id_type %||% "auto"
    method <- b$method %||% "limma"
    group_var <- b$group_var %||% NULL
    ref_group <- b$ref_group %||% NULL
    test_group <- b$test_group %||% NULL

    result <- mgx_run_differential(
      session_id = session_id,
      experiment = experiment,
      id_type = id_type,
      method = method,
      group_var = group_var,
      ref_group = ref_group,
      test_group = test_group
    )
    result_df <- tryCatch(as.data.frame(result), error = function(e) data.frame())

    list(
      success = TRUE,
      n_rows = nrow(result_df),
      columns = names(result_df),
      data = jsonlite::toJSON(result_df, na = "null", auto_unbox = TRUE)
    )
  }, res)
}

#* Metagenomics enrichment analysis
#* @post /api/workflows/metagenomics/analyze/enrichment
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    id_type <- b$id_type %||% "auto"
    database <- b$database %||% NULL
    organism <- b$organism %||% "hsa"

    result <- mgx_run_enrichment(
      session_id = session_id,
      experiment = experiment,
      id_type = id_type,
      database = database,
      organism = organism
    )
    result_df <- tryCatch(as.data.frame(result), error = function(e) data.frame())

    list(
      success = TRUE,
      n_rows = nrow(result_df),
      columns = names(result_df),
      data = jsonlite::toJSON(result_df, na = "null", auto_unbox = TRUE)
    )
  }, res)
}

#* Microbiome 16S workflow profile
#* @post /api/workflows/microbiome_16s/profile
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    tax_sep <- b$tax_sep %||% ";"
    profile <- m16s_profile(session_id = session_id, experiment = experiment, tax_sep = tax_sep)
    list(success = TRUE, profile = profile)
  }, res)
}

#* Microbiome 16S workflow pre-check validation
#* @post /api/workflows/microbiome_16s/validate
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    tax_sep <- b$tax_sep %||% ";"
    list(success = TRUE, validation = m16s_validate(session_id = session_id, experiment = experiment, tax_sep = tax_sep))
  }, res)
}

#* Microbiome 16S taxonomy-aware preparation
#* @post /api/workflows/microbiome_16s/prepare/taxonomy
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    collapse_level <- b$collapse_level %||% "Genus"
    min_total_abundance <- as.numeric(b$min_total_abundance %||% 0)
    drop_unassigned <- as.logical(b$drop_unassigned %||% TRUE)
    keep_top_n <- as.integer(b$keep_top_n %||% 0L)
    tax_sep <- b$tax_sep %||% ";"
    normalize_method <- b$normalize_method %||% NULL

    m16s_prepare_taxonomy_step(
      session_id = session_id,
      experiment = experiment,
      collapse_level = collapse_level,
      min_total_abundance = min_total_abundance,
      drop_unassigned = drop_unassigned,
      keep_top_n = keep_top_n,
      tax_sep = tax_sep,
      normalize_method = normalize_method
    )
  }, res)
}

#* Alpha diversity analysis
#* @post /api/analyze/alpha
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    method     <- b$method %||% "shannon"
    source     <- b$source %||% "current"

    result <- run_alpha(session_id, experiment, method, source = source)
    result_df <- tryCatch(as.data.frame(result), error = function(e) data.frame())

    list(success = TRUE,
         n_rows  = nrow(result_df),
         columns = names(result_df),
         data    = jsonlite::toJSON(result_df, na = "null", auto_unbox = TRUE))
  }, res)
}

#* Differential analysis (synchronous)
#* @post /api/analyze/differential
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    method     <- b$method    %||% "DESeq2"
    group_var  <- b$group_var %||% NULL
    ref_group  <- b$ref_group %||% NULL
    test_group <- b$test_group%||% NULL
    filter_low        <- if (is.null(b$filter_low))        TRUE else isTRUE(b$filter_low)
    subset_two_groups <- if (is.null(b$subset_two_groups)) TRUE else isTRUE(b$subset_two_groups)
    cores             <- b$cores %||% "auto"

    result <- run_diff(session_id, experiment, method, group_var, ref_group,
                      test_group, filter_low = filter_low,
                      subset_two_groups = subset_two_groups, cores = cores)
    result_df <- tryCatch(as.data.frame(result), error = function(e) data.frame())

    list(success = TRUE,
         n_rows  = nrow(result_df),
         columns = names(result_df),
         data    = jsonlite::toJSON(result_df, na = "null", auto_unbox = TRUE))
  }, res)
}

#* Differential analysis (asynchronous) – returns job_id immediately
#* @post /api/analyze/differential/async
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    method     <- b$method    %||% "DESeq2"
    group_var  <- b$group_var %||% NULL
    ref_group  <- b$ref_group %||% NULL
    test_group <- b$test_group%||% NULL
    filter_low        <- if (is.null(b$filter_low))        TRUE else isTRUE(b$filter_low)
    subset_two_groups <- if (is.null(b$subset_two_groups)) TRUE else isTRUE(b$subset_two_groups)
    cores             <- b$cores %||% "auto"

    job_id <- submit_job(
      kind = "differential",
      fn = "run_diff",
      args = list(
        session_id = session_id, experiment = experiment, method = method,
        group_var = group_var, ref_group = ref_group, test_group = test_group,
        filter_low = filter_low, subset_two_groups = subset_two_groups,
        cores = cores
      ),
      session_id = session_id
    )
    list(success = TRUE, job_id = job_id)
  }, res)
}

#* Poll job status
#* @get /api/jobs/<job_id>
#* @serializer unboxedJSON
function(job_id, res) {
  safe_api({
    st <- get_job_status(job_id)
    if (!is.null(st$error) && is.null(st$status)) {
      res$status <- 404
      return(list(success = FALSE, error = st$error))
    }
    list(success = TRUE, job = st)
  }, res)
}

#* Fetch the result of a completed job
#* @get /api/jobs/<job_id>/result
#* @serializer unboxedJSON
function(job_id, res) {
  safe_api({
    st <- get_job_status(job_id)
    if (is.null(st$status) || !identical(st$status, "done")) {
      res$status <- 409
      return(list(success = FALSE, error = "Job not finished",
                  status = st$status %||% "unknown"))
    }
    result_obj <- get_job_result(job_id)
    if (is.null(result_obj)) {
      res$status <- 500
      return(list(success = FALSE, error = "Result not available"))
    }
    # Three shapes are possible:
    #   - a list returned by run_all_* (bundle metadata)
    #   - a rich list returned by run_enrichment (data df + plot + counts)
    #   - a plain data.frame returned by run_diff / run_marker etc.
    if (is.list(result_obj) && !is.data.frame(result_obj) &&
        !is.null(result_obj$run_id %||% result_obj$zip_name)) {
      result_obj$success <- TRUE
      return(result_obj)
    }
    if (is.list(result_obj) && !is.data.frame(result_obj) &&
        !is.null(result_obj$data) && is.data.frame(result_obj$data)) {
      df <- result_obj$data
      out <- result_obj
      out$data    <- jsonlite::toJSON(df, na = "null", auto_unbox = TRUE)
      out$n_rows  <- nrow(df)
      out$columns <- names(df)
      out$success <- TRUE
      return(out)
    }
    result_df <- tryCatch(as.data.frame(result_obj), error = function(e) data.frame())
    list(success = TRUE,
         n_rows  = nrow(result_df),
         columns = names(result_df),
         data    = jsonlite::toJSON(result_df, na = "null", auto_unbox = TRUE))
  }, res)
}

# ══════════════════════════════════════════════════════════
#  One-click pipelines (RNAseq, 16S)
# ══════════════════════════════════════════════════════════

#* Run the full RNAseq pipeline in the background
#* @post /api/workflows/rnaseq/run_all
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    job_id <- submit_job(
      kind = "rnaseq_run_all",
      fn   = "run_all_rnaseq",
      args = list(
        session_id    = b$session_id,
        experiment    = b$experiment,
        group_var     = b$group_var %||% "Group",
        ref_group     = b$ref_group %||% NULL,
        test_group    = b$test_group %||% NULL,
        organism      = b$organism  %||% "mmu",
        fc_cutoff     = as.numeric(b$fc_cutoff %||% 1.0),
        p_cutoff      = as.numeric(b$p_cutoff  %||% 0.05),
        use_padj      = if (is.null(b$use_padj)) TRUE else isTRUE(b$use_padj),
        min_row_sum   = as.numeric(b$min_row_sum %||% 0),
        do_enrichment = if (is.null(b$do_enrichment)) TRUE else isTRUE(b$do_enrichment)
      ),
      session_id = b$session_id
    )
    list(success = TRUE, job_id = job_id, kind = "rnaseq_run_all")
  }, res)
}

#* Run the full 16S pipeline in the background
#* @post /api/workflows/microbiome_16s/run_all
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    job_id <- submit_job(
      kind = "m16s_run_all",
      fn   = "run_all_m16s",
      args = list(
        session_id     = b$session_id,
        experiment     = b$experiment,
        group_var      = b$group_var %||% NULL,
        taxonomy_level = b$taxonomy_level %||% "Genus",
        alpha_index    = b$alpha_index %||% "shannon",
        beta_method    = b$beta_method %||% "bray",
        ord_method     = b$ord_method  %||% "PCoA"
      ),
      session_id = b$session_id
    )
    list(success = TRUE, job_id = job_id, kind = "m16s_run_all")
  }, res)
}

#* List bundles produced for a session
#* @get /api/bundles/<session_id>
#* @serializer unboxedJSON
function(session_id, res) {
  safe_api({
    root <- file.path(session_path(session_id), "bundles")
    if (!dir.exists(root)) return(list(success = TRUE, bundles = list()))
    zips <- list.files(root, pattern = "\\.zip$", full.names = TRUE)
    info <- lapply(zips, function(z) {
      list(name = basename(z),
           size_kb = round(file.size(z) / 1024, 1),
           mtime = format(file.mtime(z), "%Y-%m-%dT%H:%M:%S"))
    })
    list(success = TRUE, bundles = info)
  }, res)
}

#* Download a bundle zip – streams the file to the client
#* @get /api/bundles/<session_id>/<bundle_name>
#* @serializer contentType list(type="application/zip")
function(session_id, bundle_name, res) {
  zip_path <- file.path(session_path(session_id), "bundles", bundle_name)
  if (!file.exists(zip_path) || !grepl("\\.zip$", bundle_name)) {
    res$status <- 404
    return(charToRaw('{"success":false,"error":"Bundle not found"}'))
  }
  res$setHeader("Content-Disposition",
                sprintf('attachment; filename="%s"', bundle_name))
  readBin(zip_path, what = "raw", n = file.info(zip_path)$size)
}

#* Download a per-experiment plot PDF from the session cache
#* @get /api/download/plot/<session_id>/<experiment>/<kind>
#* @serializer contentType list(type="application/pdf")
function(session_id, experiment, kind, res) {
  # Direct hit first (`kind` already is the on-disk filename, e.g.
  # "clinical_cor_experiment.pdf" or "wgcna_modtrait_experiment.pdf").
  plots_dir <- file.path(session_path(session_id), "plots")
  safe_kind <- basename(kind)                             # strip path traversal
  direct <- file.path(plots_dir, safe_kind)
  if (nzchar(safe_kind) && grepl("\\.pdf$", safe_kind, ignore.case = TRUE) &&
      file.exists(direct)) {
    res$setHeader("Content-Disposition",
                  sprintf('attachment; filename="%s"', safe_kind))
    return(readBin(direct, what = "raw", n = file.info(direct)$size))
  }
  # Legacy short-name form (e.g. "volcano.pdf" → "volcano_<experiment>.pdf")
  allowed <- c("deg_heatmap.pdf", "volcano.pdf", "heatmap.pdf")
  if (safe_kind %in% allowed) {
    base <- sub("\\.pdf$", "", safe_kind)
    path <- file.path(plots_dir, paste0(base, "_", make.names(experiment), ".pdf"))
    if (file.exists(path)) {
      res$setHeader("Content-Disposition",
                    sprintf('attachment; filename="%s_%s"', experiment, safe_kind))
      return(readBin(path, what = "raw", n = file.info(path)$size))
    }
  }
  res$status <- 404
  charToRaw('{"success":false,"error":"PDF not found, generate the plot first"}')
}

#* Dimension reduction
#* @post /api/analyze/dimension
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    method     <- b$method %||% "PCA"

    result    <- run_dimension(session_id, experiment, method)
    result_df <- tryCatch(as.data.frame(result), error = function(e) data.frame())

    list(success = TRUE,
         n_rows  = nrow(result_df),
         columns = names(result_df),
         data    = jsonlite::toJSON(result_df, na = "null", auto_unbox = TRUE))
  }, res)
}

#* Correlation analysis
#* @post /api/analyze/correlation
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    use        <- b$use %||% "spearman"

    result    <- run_correlation(session_id, experiment, use)
    result_df <- tryCatch(as.data.frame(result), error = function(e) data.frame())

    list(success = TRUE,
         n_rows  = nrow(result_df),
         columns = names(result_df),
         data    = jsonlite::toJSON(result_df, na = "null", auto_unbox = TRUE))
  }, res)
}

#* Cluster analysis
#* @post /api/analyze/cluster
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    method     <- b$method %||% "hclust"
    k          <- as.integer(b$k %||% 3L)

    result    <- run_cluster(session_id, experiment, method, k)
    result_df <- tryCatch(as.data.frame(result), error = function(e) data.frame())

    list(success = TRUE,
         n_rows  = nrow(result_df),
         columns = names(result_df),
         data    = jsonlite::toJSON(result_df, na = "null", auto_unbox = TRUE))
  }, res)
}

#* Marker (biomarker) analysis
#* @post /api/analyze/marker
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    method     <- b$method    %||% "randomForest"
    group_var  <- b$group_var %||% NULL
    ref_group  <- b$ref_group %||% NULL
    test_group <- b$test_group %||% NULL

    result    <- run_marker(session_id, experiment, method, group_var, ref_group = ref_group, test_group = test_group)
    result_df <- tryCatch(as.data.frame(result), error = function(e) data.frame())

    list(success = TRUE,
         n_rows  = nrow(result_df),
         columns = names(result_df),
         data    = jsonlite::toJSON(result_df, na = "null", auto_unbox = TRUE))
  }, res)
}

#* Enrichment analysis (KEGG / GO via clusterProfiler on the cached DEG list)
#* @post /api/analyze/enrichment
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    database   <- b$database  %||% "KEGG"
    organism   <- b$organism  %||% "hsa"
    fc_cutoff  <- as.numeric(b$fc_cutoff %||% 1.0)
    p_cutoff   <- as.numeric(b$p_cutoff  %||% 0.05)
    use_padj   <- if (is.null(b$use_padj)) TRUE else isTRUE(b$use_padj)
    direction  <- b$direction %||% "both"
    top_n      <- as.integer(b$top_n %||% 20)

    out <- run_enrichment(session_id, experiment,
                          database = database, organism = organism,
                          fc_cutoff = fc_cutoff, p_cutoff = p_cutoff,
                          use_padj = use_padj, direction = direction,
                          top_n = top_n)

    result_df <- tryCatch(as.data.frame(out$data), error = function(e) data.frame())
    list(
      success      = TRUE,
      database     = out$database,
      organism     = out$organism,
      direction    = out$direction,
      deg_count    = out$deg_count,
      mapped_count = out$mapped_count,
      n_rows       = nrow(result_df),
      columns      = names(result_df),
      data         = jsonlite::toJSON(result_df, na = "null", auto_unbox = TRUE),
      plot         = out$plot
    )
  }, res)
}

#* Enrichment analysis (async) – submits background job, streams progress
#* @post /api/analyze/enrichment/async
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    database   <- b$database  %||% "KEGG"
    organism   <- b$organism  %||% "hsa"
    fc_cutoff  <- as.numeric(b$fc_cutoff %||% 1.0)
    p_cutoff   <- as.numeric(b$p_cutoff  %||% 0.05)
    use_padj   <- if (is.null(b$use_padj)) TRUE else isTRUE(b$use_padj)
    direction  <- b$direction %||% "both"
    top_n      <- as.integer(b$top_n %||% 20)

    job_id <- submit_job(
      kind = "enrichment",
      fn   = "run_enrichment",
      args = list(
        session_id = session_id, experiment = experiment,
        database   = database,   organism   = organism,
        fc_cutoff  = fc_cutoff,  p_cutoff   = p_cutoff,
        use_padj   = use_padj,   direction  = direction,
        top_n      = top_n
      ),
      session_id = session_id
    )
    list(success = TRUE, job_id = job_id)
  }, res)
}

#* List known enrichment species and whether the OrgDb is installed locally.
#* Used by the frontend to render a dynamic organism dropdown.
#* @get /api/enrichment/species
#* @serializer unboxedJSON
function(res) {
  safe_api({
    df <- list_enrichment_species()
    list(success = TRUE, n_rows = nrow(df), data = df)
  }, res)
}

#* Install a missing OrgDb package on the server (async).
#* Body: { orgdb: "org.Xx.xx.db" }
#* Returns a job_id that the frontend polls with its usual progress bar.
#* @post /api/enrichment/install
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b     <- jsonlite::fromJSON(req$postBody)
    orgdb <- as.character(b$orgdb %||% "")
    if (!nzchar(orgdb)) {
      res$status <- 400
      return(list(success = FALSE, error = "orgdb field is required"))
    }
    job_id <- submit_job(
      kind = "orgdb_install",
      fn   = "install_orgdb",
      args = list(orgdb = orgdb)
    )
    list(success = TRUE, job_id = job_id, orgdb = orgdb)
  }, res)
}

#* Network analysis
#* @post /api/analyze/network
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    method     <- b$method  %||% "spearman"
    cutoff     <- as.numeric(b$cutoff %||% 0.6)

    run_network(session_id, experiment, method, cutoff)
    list(success = TRUE, message = "Network analysis completed.")
  }, res)
}

# ══════════════════════════════════════════════════════════
# VISUALIZATION
# ══════════════════════════════════════════════════════════

#* Transcriptomics heatmap
#* @post /api/workflows/transcriptomics/visualize/heatmap
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- if (!is.null(b$session_id) && length(b$session_id) > 0) as.character(b$session_id[[1]]) else NULL
    experiment <- if (!is.null(b$experiment) && length(b$experiment) > 0) as.character(b$experiment[[1]]) else NULL
    group <- if (!is.null(b$group) && length(b$group) > 0) as.character(b$group[[1]]) else NULL
    top_n <- if (!is.null(b$top_n) && length(b$top_n) > 0) as.integer(b$top_n[[1]]) else 50L
    features <- .parse_feature_list(b$features)
    cluster_rows <- if (is.null(b$cluster_rows)) TRUE else isTRUE(b$cluster_rows)
    cluster_cols <- if (is.null(b$cluster_cols)) TRUE else isTRUE(b$cluster_cols)
    show_gene_names <- if (is.null(b$show_gene_names)) NULL else isTRUE(b$show_gene_names)
    font_size <- as.numeric(b$font_size %||% 11)
    color_panel <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL

    img <- tx_make_heatmap(session_id, experiment, group = group,
                            top_n = top_n, features = features,
                            cluster_rows = cluster_rows, cluster_cols = cluster_cols,
                            show_gene_names = show_gene_names,
                            font_size = font_size, color_panel = color_panel,
                            custom_colors = custom_colors)
    .heatmap_response(img)
  }, res)
}

#* Transcriptomics volcano plot
#* @post /api/workflows/transcriptomics/visualize/volcano
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- if (!is.null(b$session_id) && length(b$session_id) > 0) as.character(b$session_id[[1]]) else NULL
    experiment <- if (!is.null(b$experiment) && length(b$experiment) > 0) as.character(b$experiment[[1]]) else NULL
    fc_cutoff <- if (!is.null(b$fc_cutoff) && length(b$fc_cutoff) > 0) as.numeric(b$fc_cutoff[[1]]) else 1.0
    p_cutoff <- if (!is.null(b$p_cutoff) && length(b$p_cutoff) > 0) as.numeric(b$p_cutoff[[1]]) else 0.05
    color_panel <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL

    img <- tx_make_volcano(session_id, experiment, fc_cutoff = fc_cutoff, p_cutoff = p_cutoff,
                           color_panel = color_panel, custom_colors = custom_colors)
    list(success = TRUE, plot = img)
  }, res)
}

#* Metagenomics functional heatmap
#* @post /api/workflows/metagenomics/visualize/heatmap
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- if (!is.null(b$session_id) && length(b$session_id) > 0) as.character(b$session_id[[1]]) else NULL
    experiment <- if (!is.null(b$experiment) && length(b$experiment) > 0) as.character(b$experiment[[1]]) else NULL
    group <- if (!is.null(b$group) && length(b$group) > 0) as.character(b$group[[1]]) else NULL
    top_n <- if (!is.null(b$top_n) && length(b$top_n) > 0) as.integer(b$top_n[[1]]) else 50L
    features <- .parse_feature_list(b$features)
    cluster_rows <- if (is.null(b$cluster_rows)) TRUE else isTRUE(b$cluster_rows)
    cluster_cols <- if (is.null(b$cluster_cols)) TRUE else isTRUE(b$cluster_cols)
    show_gene_names <- if (is.null(b$show_gene_names)) NULL else isTRUE(b$show_gene_names)
    font_size <- as.numeric(b$font_size %||% 11)
    color_panel <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL

    img <- mgx_make_heatmap(session_id, experiment, group = group,
                              top_n = top_n, features = features,
                              cluster_rows = cluster_rows, cluster_cols = cluster_cols,
                              show_gene_names = show_gene_names,
                              font_size = font_size, color_panel = color_panel,
                              custom_colors = custom_colors)
    .heatmap_response(img)
  }, res)
}

#* Metagenomics functional volcano plot
#* @post /api/workflows/metagenomics/visualize/volcano
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- if (!is.null(b$session_id) && length(b$session_id) > 0) as.character(b$session_id[[1]]) else NULL
    experiment <- if (!is.null(b$experiment) && length(b$experiment) > 0) as.character(b$experiment[[1]]) else NULL
    fc_cutoff <- if (!is.null(b$fc_cutoff) && length(b$fc_cutoff) > 0) as.numeric(b$fc_cutoff[[1]]) else 1.0
    p_cutoff <- if (!is.null(b$p_cutoff) && length(b$p_cutoff) > 0) as.numeric(b$p_cutoff[[1]]) else 0.05
    color_panel <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL

    img <- mgx_make_volcano(session_id, experiment, fc_cutoff = fc_cutoff, p_cutoff = p_cutoff,
                            color_panel = color_panel, custom_colors = custom_colors)
    list(success = TRUE, plot = img)
  }, res)
}

#* Metabolomics workflow profile (missingness/normalization defaults)
#* @post /api/workflows/metabolomics/profile
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    profile <- mbx_profile(session_id, experiment)
    list(success = TRUE, profile = profile)
  }, res)
}

#* Metabolomics workflow pre-check validation
#* @post /api/workflows/metabolomics/validate
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    list(success = TRUE, validation = mbx_validate(session_id, experiment))
  }, res)
}

#* Metabolomics preprocessing with missingness-aware defaults
#* @post /api/workflows/metabolomics/preprocess
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    max_na <- b$max_na %||% NULL
    impute_method <- b$impute_method %||% NULL
    normalize_method <- b$normalize_method %||% NULL

    result <- mbx_preprocess(
      session_id = session_id,
      experiment = experiment,
      max_na = max_na,
      impute_method = impute_method,
      normalize_method = normalize_method
    )
    list(success = TRUE, result = result)
  }, res)
}

#* Metabolomics differential analysis with workflow defaults
#* @post /api/workflows/metabolomics/analyze/differential
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    method <- b$method %||% NULL
    group_var <- b$group_var %||% NULL
    ref_group <- b$ref_group %||% NULL
    test_group <- b$test_group %||% NULL

    mbx_run_differential(
      session_id = session_id,
      experiment = experiment,
      method = method,
      group_var = group_var,
      ref_group = ref_group,
      test_group = test_group
    )
  }, res)
}

#* Metabolomics volcano plot
#* @post /api/workflows/metabolomics/visualize/volcano
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    fc_cutoff <- b$fc_cutoff %||% 1
    p_cutoff <- b$p_cutoff %||% 0.05
    color_panel <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL

    mbx_volcano_plot(
      session_id = session_id,
      experiment = experiment,
      fc_cutoff = fc_cutoff,
      p_cutoff = p_cutoff,
      color_panel = color_panel,
      custom_colors = custom_colors
    )
  }, res)
}

#* Microbiome 16S taxonomy sankey plot
#* @post /api/workflows/microbiome_16s/visualize/sankey
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    tax_sep <- b$tax_sep %||% ";"
    from_level <- b$from_level %||% "Phylum"
    to_level <- b$to_level %||% "Genus"
    top_n <- as.integer(b$top_n %||% 25L)
    width <- as.numeric(b$width %||% 10)
    height <- as.numeric(b$height %||% 6)
    color_panel <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL

    out <- m16s_visualize_sankey(
      session_id = session_id,
      experiment = experiment,
      from_level = from_level,
      to_level = to_level,
      top_n = top_n,
      width = width,
      height = height,
      tax_sep = tax_sep,
      color_panel = color_panel,
      custom_colors = custom_colors
    )
    list(success = TRUE, plot = out$plot, edges = out$edges, from_nodes = out$from_nodes, to_nodes = out$to_nodes)
  }, res)
}

#* Microbiome 16S taxa correlation network plot
#* @post /api/workflows/microbiome_16s/visualize/network
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    method <- b$method %||% "spearman"
    cutoff <- as.numeric(b$cutoff %||% 0.6)
    top_n <- as.integer(b$top_n %||% 40L)
    width <- as.numeric(b$width %||% 8)
    height <- as.numeric(b$height %||% 8)

    out <- m16s_visualize_network(
      session_id = session_id,
      experiment = experiment,
      method = method,
      cutoff = cutoff,
      top_n = top_n,
      width = width,
      height = height
    )
    list(success = TRUE, plot = out$plot, nodes = out$nodes, edges = out$edges, method = out$method, cutoff = out$cutoff)
  }, res)
}

#* Barplot
#* @post /api/visualize/barplot
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    group      <- b$group   %||% NULL
    feature    <- b$feature %||% NULL
    mode       <- b$mode    %||% "top20"
    top_n      <- as.integer(b$top_n %||% 20L)
    color_panel <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL

    img <- make_barplot(session_id, experiment, group, feature, mode, top_n,
                        color_panel = color_panel,
                        custom_colors = custom_colors)
    list(success = TRUE, plot = img)
  }, res)
}

#* Boxplot
#* @post /api/visualize/boxplot
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    group      <- b$group   %||% NULL
    feature    <- b$feature %||% NULL
    color_panel <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL

    img <- make_boxplot(session_id, experiment, group, feature,
                        color_panel = color_panel,
                        custom_colors = custom_colors)
    list(success = TRUE, plot = img)
  }, res)
}

#* Heatmap
#* @post /api/visualize/heatmap
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    group      <- b$group %||% NULL
    top_n      <- as.integer(b$top_n %||% 50L)
    features   <- .parse_feature_list(b$features)
    cluster_rows <- if (is.null(b$cluster_rows)) TRUE else isTRUE(b$cluster_rows)
    cluster_cols <- if (is.null(b$cluster_cols)) TRUE else isTRUE(b$cluster_cols)
    show_gene_names <- if (is.null(b$show_gene_names)) NULL else isTRUE(b$show_gene_names)
    font_size <- as.numeric(b$font_size %||% 11)
    color_panel <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL

    img <- make_heatmap(session_id, experiment, group, top_n,
                          features = features,
                          cluster_rows = cluster_rows,
                          cluster_cols = cluster_cols,
                          show_gene_names = show_gene_names,
                          font_size = font_size,
                          color_panel = color_panel,
                          custom_colors = custom_colors)
    .heatmap_response(img)
  }, res)
}

#* Volcano plot (DESeq2-style three-colour scheme, top-N labelled)
#* @post /api/visualize/volcano
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    fc_cutoff  <- as.numeric(b$fc_cutoff %||% 1.0)
    p_cutoff   <- as.numeric(b$p_cutoff  %||% 0.05)
    use_padj   <- if (is.null(b$use_padj)) TRUE else isTRUE(b$use_padj)
    label_top  <- as.integer(b$label_top %||% 15L)
    color_panel <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL

    img <- make_volcano(session_id, experiment,
                        fc_cutoff = fc_cutoff, p_cutoff = p_cutoff,
                        use_padj = use_padj, label_top = label_top,
                        color_panel = color_panel,
                        custom_colors = custom_colors)
    # Best-effort: also save a PDF for one-click download.
    pdf_ok <- FALSE
    tryCatch({
      p <- .make_volcano_plot(session_id, experiment,
                               fc_cutoff = fc_cutoff, p_cutoff = p_cutoff,
                               use_padj = use_padj, label_top = label_top)
      if (!is.null(p)) {
        pdf_dir <- file.path(session_path(session_id), "plots")
        dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
        save_plot_pdf(p, file.path(pdf_dir, paste0("volcano_",
                                                   make.names(experiment), ".pdf")),
                       width = 9, height = 7)
        pdf_ok <<- TRUE
      }
    }, error = function(e) NULL)
    list(success = TRUE, plot = img, pdf_available = pdf_ok)
  }, res)
}

#* DEG heatmap – all DEGs from the cached DESeq2 table, pheatmap style
#* @post /api/visualize/deg_heatmap
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b            <- jsonlite::fromJSON(req$postBody)
    session_id   <- b$session_id
    experiment   <- b$experiment
    group        <- b$group %||% NULL
    fc_cutoff    <- as.numeric(b$fc_cutoff %||% 1.0)
    p_cutoff     <- as.numeric(b$p_cutoff  %||% 0.05)
    use_padj     <- if (is.null(b$use_padj)) TRUE else isTRUE(b$use_padj)
    min_row_sum  <- as.numeric(b$min_row_sum %||% 0)
    max_genes    <- as.integer(b$max_genes %||% 200L)
    cluster_rows <- if (is.null(b$cluster_rows)) TRUE else isTRUE(b$cluster_rows)
    cluster_cols <- if (is.null(b$cluster_cols)) TRUE else isTRUE(b$cluster_cols)
    show_rn      <- if (is.null(b$show_rownames)) TRUE else isTRUE(b$show_rownames)
    font_size    <- as.numeric(b$font_size %||% 10)
    color_panel  <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL

    pdf_dir <- file.path(session_path(session_id), "plots")
    dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
    pdf_path <- file.path(pdf_dir, paste0("deg_heatmap_", make.names(experiment), ".pdf"))

    out <- make_deg_heatmap(session_id, experiment, group = group,
                             fc_cutoff = fc_cutoff, p_cutoff = p_cutoff,
                             use_padj = use_padj, min_row_sum = min_row_sum,
                             max_genes = max_genes,
                             cluster_rows = cluster_rows,
                             cluster_cols = cluster_cols,
                             show_rownames = show_rn,
                             pdf_path = pdf_path,
                             font_size = font_size,
                             color_panel = color_panel,
                             custom_colors = custom_colors)
    list(success = TRUE, plot = out$png, n_genes = out$n_genes,
         pdf_available = !is.null(out$pdf),
         pdf_name = basename(out$pdf %||% ""))
  }, res)
}

#* Retrieve the cached raw DESeq2-style DEG table (for download / preview)
#* @get /api/analyze/diff_raw/<session_id>/<experiment>
#* @serializer unboxedJSON
function(session_id, experiment, res) {
  safe_api({
    raw <- load_diff_raw(session_id, experiment)
    if (is.null(raw) || is.null(raw$data) || !nrow(raw$data)) {
      res$status <- 404
      return(list(success = FALSE, error = "No cached DEG result – run differential analysis first."))
    }
    df <- as.data.frame(raw$data, stringsAsFactors = FALSE)
    list(
      success    = TRUE,
      method     = raw$method,
      group_var  = raw$group_var,
      ref_group  = raw$ref_group,
      test_group = raw$test_group,
      n_rows     = nrow(df),
      columns    = names(df),
      data       = jsonlite::toJSON(df, na = "null", auto_unbox = TRUE)
    )
  }, res)
}

#* Scatter / PCA plot
#* @post /api/visualize/scatter
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    group      <- b$group %||% NULL
    dim1       <- as.integer(b$dim1 %||% 1L)
    dim2       <- as.integer(b$dim2 %||% 2L)
    color_panel <- b$color_panel %||% NULL
    ordination <- b$ordination %||% "auto"
    custom_colors <- b$custom_colors %||% NULL

    img <- make_scatter(session_id, experiment, group, dim1, dim2,
                        color_panel = color_panel, ordination = ordination,
                        custom_colors = custom_colors)
    list(success = TRUE, plot = img)
  }, res)
}

#* Structure / composition plot
#* @post /api/visualize/structure
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    group      <- b$group %||% NULL
    top_n      <- as.integer(b$top_n %||% 10L)
    color_panel <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL

    img <- make_structure(session_id, experiment, group, top_n,
                          color_panel = color_panel,
                          custom_colors = custom_colors)
    list(success = TRUE, plot = img)
  }, res)
}

#* Alpha diversity plot
#* @post /api/visualize/alpha
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    group      <- b$group  %||% NULL
    metric     <- b$metric %||% "shannon"
    source     <- b$source %||% "current"
    color_panel <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL

    img <- make_alpha_plot(session_id, experiment, group, metric, source,
                           color_panel = color_panel,
                           custom_colors = custom_colors)
    list(success = TRUE, plot = img)
  }, res)
}

# ══════════════════════════════════════════════════════════
# EXPORT
# ══════════════════════════════════════════════════════════

#* Export metabolomics differential result
#* @get /api/workflows/metabolomics/export/result/<session_id>/<experiment>
#* @serializer contentType list(type="text/csv")
function(session_id, experiment, res) {
  tryCatch({
    df <- mbx_export_diff_csv(session_id, experiment)
    res$setHeader(
      "Content-Disposition",
      paste0('attachment; filename="', experiment, '_metabolomics_differential.csv"')
    )
    write.csv(df, row.names = FALSE)
  }, error = function(e) {
    res$status <- 500
    paste("Error:", e$message)
  })
}

#* Export metagenomics differential result
#* @get /api/workflows/metagenomics/export/result/<session_id>/<experiment>
#* @serializer contentType list(type="text/csv")
function(session_id, experiment, res) {
  tryCatch({
    df <- mgx_export_diff_csv(session_id, experiment)
    res$setHeader(
      "Content-Disposition",
      paste0('attachment; filename="', experiment, '_metagenomics_differential.csv"')
    )
    write.csv(df, row.names = FALSE)
  }, error = function(e) {
    res$status <- 500
    paste("Error:", e$message)
  })
}

#* Download assay matrix as CSV
#* @get /api/export/assay/<session_id>/<experiment>
#* @serializer contentType list(type="text/csv")
function(session_id, experiment, res) {
  tryCatch({
    empt <- load_empt(session_id, experiment)
    ad   <- SummarizedExperiment::assays(empt)[[1]]
    df   <- as.data.frame(ad)
    df   <- cbind(feature = rownames(df), df)
    res$setHeader("Content-Disposition",
                  paste0('attachment; filename="', experiment, '_assay.csv"'))
    write.csv(df, row.names = FALSE)
  }, error = function(e) {
    res$status <- 500
    paste("Error:", e$message)
  })
}

#* Prepare EMP-format object (EMPT) in background-safe step
#* @post /api/export/empt/prepare
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    if (is.null(session_id) || !nzchar(session_id)) stop("session_id is required")
    if (is.null(experiment) || !nzchar(experiment)) stop("experiment is required")

    empt <- load_empt(session_id, experiment)
    save_empt(session_id, experiment, empt)
    ad <- SummarizedExperiment::assays(empt)[[1]]
    list(
      success = TRUE,
      ready = TRUE,
      experiment = experiment,
      n_samples = ncol(ad),
      n_features = nrow(ad)
    )
  }, res)
}

#* Download current experiment as EMP-format RDS (EMPT)
#* @get /api/export/empt/<session_id>/<experiment>
#* @serializer contentType list(type="application/octet-stream")
function(session_id, experiment, res) {
  tryCatch({
    empt <- load_empt(session_id, experiment)
    tmp <- tempfile(fileext = ".rds")
    on.exit(if (file.exists(tmp)) file.remove(tmp))
    saveRDS(empt, tmp)
    res$setHeader(
      "Content-Disposition",
      paste0('attachment; filename="', experiment, '_EMP_EMPT.rds"')
    )
    readBin(tmp, "raw", file.info(tmp)$size)
  }, error = function(e) {
    res$status <- 500
    paste("Error:", e$message)
  })
}

#* Download coldata as CSV
#* @get /api/export/coldata/<session_id>/<experiment>
#* @serializer contentType list(type="text/csv")
function(session_id, experiment, res) {
  tryCatch({
    empt <- load_empt(session_id, experiment)
    cd   <- as.data.frame(SummarizedExperiment::colData(empt))
    cd   <- cbind(sample = rownames(cd), cd)
    res$setHeader("Content-Disposition",
                  paste0('attachment; filename="', experiment, '_metadata.csv"'))
    write.csv(cd, row.names = FALSE)
  }, error = function(e) {
    res$status <- 500
    paste("Error:", e$message)
  })
}

#* Download analysis result as CSV
#* @get /api/export/result/<session_id>/<experiment>/<analysis>
#* @serializer contentType list(type="text/csv")
function(session_id, experiment, analysis, res) {
  tryCatch({
    empt   <- load_empt(session_id, experiment)
    result_info_map <- c(
      "alpha" = "EMP_alpha_analysis",
      "alpha_analysis" = "EMP_alpha_analysis",
      "diff" = "EMP_diff_analysis",
      "differential" = "EMP_diff_analysis",
      "diff_analysis" = "EMP_diff_analysis",
      "dimension" = "EMP_dimension_analysis",
      "enrich" = "EMP_enrich_analysis",
      "enrichment" = "EMP_enrich_analysis",
      "network" = "EMP_network_analysis"
    )
    result_info <- unname(result_info_map[[analysis]])
    if (is.null(result_info) || !nzchar(result_info)) {
      result_info <- paste0(analysis, "_result")
    }
    result <- EasyMultiProfiler::EMP_result(empt, info = result_info)
    df     <- as.data.frame(result)
    res$setHeader("Content-Disposition",
                  paste0('attachment; filename="', experiment, '_', analysis, '.csv"'))
    write.csv(df, row.names = FALSE)
  }, error = function(e) {
    res$status <- 500
    paste("Error:", e$message)
  })
}

#* Download full session as RDS
#* @get /api/export/rds/<session_id>
#* @serializer contentType list(type="application/octet-stream")
function(session_id, res) {
  tryCatch({
    mae <- load_mae(session_id)
    tmp <- tempfile(fileext = ".rds")
    on.exit(if(file.exists(tmp)) file.remove(tmp))
    saveRDS(mae, tmp)
    res$setHeader("Content-Disposition", 'attachment; filename="EMP_session.rds"')
    readBin(tmp, "raw", file.info(tmp)$size)
  }, error = function(e) {
    res$status <- 500
    paste("Error:", e$message)
  })
}

#* Download metabolomics differential result as CSV
#* @get /api/workflows/metabolomics/export/differential/<session_id>/<experiment>
#* @serializer contentType list(type="text/csv")
function(session_id, experiment, res) {
  tryCatch({
    df <- mbx_export_diff_csv(session_id, experiment)
    res$setHeader("Content-Disposition",
                  paste0('attachment; filename="', experiment, '_metabolomics_differential.csv"'))
    write.csv(df, row.names = FALSE)
  }, error = function(e) {
    res$status <- 500
    paste("Error:", e$message)
  })
}

# ══════════════════════════════════════════════════════════
# CLINICAL / PHENOTYPE ANALYSIS
# ══════════════════════════════════════════════════════════

#* List the numeric / categorical columns in an experiment's colData.
#* Used by the frontend to populate the Clinical & Phenotype page dropdowns.
#* @get /api/clinical/vars/<session_id>/<experiment>
#* @serializer unboxedJSON
function(session_id, experiment, res) {
  safe_api({
    df <- list_clinical_vars(session_id, experiment)
    list(success = TRUE, n_rows = nrow(df), data = df)
  }, res)
}

#* List variables from standalone uploaded clinical table (no experiment needed).
#* @get /api/clinical/vars_standalone/<session_id>
#* @serializer unboxedJSON
function(session_id, res) {
  safe_api({
    df <- list_clinical_vars_standalone(session_id)
    list(success = TRUE, n_rows = nrow(df), data = df)
  }, res)
}

#* One-click clinical three-line table (experiment or standalone source).
#* Body: { session_id, experiment, source, group_var, skip_high_cardinality, max_levels, table_engine }
#* @post /api/clinical/three_line
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment %||% NULL
    source <- b$source %||% "standalone"
    group_var <- b$group_var %||% NULL
    skip_high_cardinality <- if (is.null(b$skip_high_cardinality)) TRUE else isTRUE(b$skip_high_cardinality)
    max_levels <- as.integer(b$max_levels %||% 20L)
    table_engine <- b$table_engine %||% "gtsummary"
    vars_df <- NULL
    if (identical(source, "experiment")) {
      if (is.null(experiment) || !nzchar(experiment)) stop("experiment is required when source='experiment'.")
      vars_df <- list_clinical_vars(session_id, experiment)
      df <- tryCatch(
        make_clinical_three_line_table_experiment(
          session_id = session_id, experiment = experiment, group_var = group_var,
          skip_high_cardinality = skip_high_cardinality, max_levels = max_levels,
          table_engine = table_engine
        ),
        error = function(e) {
          msg <- conditionMessage(e)
          if (grepl("no variables|no .*metadata|empty", msg, ignore.case = TRUE)) {
            data.frame(Variable = character(), stringsAsFactors = FALSE)
          } else stop(e)
        }
      )
    } else {
      vars_df <- list_clinical_vars_standalone(session_id)
      df <- tryCatch(
        make_clinical_three_line_table(
          session_id = session_id, group_var = group_var,
          skip_high_cardinality = skip_high_cardinality, max_levels = max_levels,
          table_engine = table_engine
        ),
        error = function(e) {
          msg <- conditionMessage(e)
          if (grepl("no variables|no standalone clinical data|empty", msg, ignore.case = TRUE)) {
            data.frame(Variable = character(), stringsAsFactors = FALSE)
          } else stop(e)
        }
      )
    }
    n_num <- if (!is.null(vars_df) && nrow(vars_df)) sum(vars_df$type == "numeric", na.rm = TRUE) else 0L
    warn_msg <- NULL
    if (n_num <= 0L) {
      warn_msg <- "No numeric clinical indicators detected in selected source. Output is count-only summary."
    }
    if (!nrow(df)) {
      warn_msg <- paste(c(warn_msg, "No clinical variables found in selected source."), collapse = " ")
      warn_msg <- trimws(warn_msg)
    }
    list(
      success = TRUE,
      n_rows = nrow(df),
      columns = names(df),
      data = df,
      engine_used = attr(df, "engine_used") %||% as.character(table_engine),
      n_numeric_vars = as.integer(n_num),
      warning = warn_msg
    )
  }, res)
}

#* Clinical systematic summary (baseline + within-group paired change + between-group delta).
#* Body: { session_id, experiment, source, group_var, skip_high_cardinality, max_levels, table_engine }
#* @post /api/clinical/systematic_summary
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment %||% NULL
    source <- b$source %||% "standalone"
    group_var <- b$group_var %||% NULL
    skip_high_cardinality <- if (is.null(b$skip_high_cardinality)) TRUE else isTRUE(b$skip_high_cardinality)
    max_levels <- as.integer(b$max_levels %||% 20L)
    table_engine <- b$table_engine %||% "gtsummary"
    out <- run_clinical_systematic_summary(
      session_id = session_id,
      source = source,
      experiment = experiment,
      group_var = group_var,
      skip_high_cardinality = skip_high_cardinality,
      max_levels = max_levels,
      table_engine = table_engine
    )
    list(
      success = TRUE,
      baseline = out$baseline,
      within = out$within,
      between = out$between,
      n_baseline = nrow(out$baseline),
      n_within = nrow(out$within),
      n_between = nrow(out$between),
      n_pairs = out$meta$n_pairs %||% 0L
    )
  }, res)
}

#* Feature × Trait correlation (synchronous, typically < 5 s).
#* Body: { session_id, experiment, traits:[..], method, top_n_features, p_adjust, clinical_source }
#* @post /api/clinical/cor
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b              <- jsonlite::fromJSON(req$postBody)
    session_id     <- b$session_id
    experiment     <- b$experiment
    traits         <- as.character(b$traits)
    method         <- b$method %||% "spearman"
    top_n_features <- as.integer(b$top_n_features %||% 30L)
    p_adjust       <- b$p_adjust %||% "BH"
    clinical_source<- b$clinical_source %||% "experiment"

    pdf_dir <- file.path(session_path(session_id), "plots")
    dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
    pdf_path <- file.path(pdf_dir, paste0("clinical_cor_", make.names(experiment), ".pdf"))

    out <- run_clinical_cor(session_id, experiment,
                             traits = traits, method = method,
                             top_n_features = top_n_features,
                             p_adjust = p_adjust,
                             clinical_source = clinical_source,
                             pdf_path = pdf_path)
    list(success = TRUE, plot = out$png, n_feat = out$n_feat,
         n_samp = out$n_samp, method = out$method, p_adjust = out$p_adjust,
         table = utils::head(out$table, 500L),           # cap for payload size
         table_n = nrow(out$table),
         pdf_available = !is.null(out$pdf),
         pdf_name = basename(out$pdf %||% ""))
  }, res)
}

#* Scatter + regression line for ONE feature against ONE numeric trait.
#* Body: { session_id, experiment, feature, trait, group, method, log_y, clinical_source }
#* @post /api/clinical/fitline
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiment <- b$experiment
    feature    <- b$feature
    trait      <- b$trait
    group      <- b$group %||% NULL
    method     <- b$method %||% "lm"
    log_y      <- isTRUE(b$log_y)
    clinical_source <- b$clinical_source %||% "experiment"

    pdf_dir <- file.path(session_path(session_id), "plots")
    dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
    pdf_path <- file.path(pdf_dir,
                          paste0("fitline_", make.names(feature), "_vs_",
                                  make.names(trait), ".pdf"))
    out <- make_fitline_scatter(session_id, experiment, feature = feature,
                                 trait = trait, group = group, method = method,
                                 log_y = log_y, clinical_source = clinical_source,
                                 pdf_path = pdf_path)
    list(success = TRUE, plot = out$png, r = out$r, p = out$p, n = out$n,
         group_used = out$group_used,
         pdf_available = !is.null(out$pdf),
         pdf_name = basename(out$pdf %||% ""))
  }, res)
}

#* WGCNA module–trait correlation (async: 1–5 min on bulk RNAseq).
#* Body: { session_id, experiment, traits:[..], min_module_size, clinical_source }
#* Returns a job_id that the frontend polls with the global progress bar.
#* @post /api/clinical/wgcna/async
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b           <- jsonlite::fromJSON(req$postBody)
    session_id  <- b$session_id
    experiment  <- b$experiment
    traits      <- if (length(b$traits)) as.character(b$traits) else NULL
    min_mod     <- as.integer(b$min_module_size %||% 30L)
    clinical_source <- b$clinical_source %||% "experiment"

    pdf_dir <- file.path(session_path(session_id), "plots")
    dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
    pdf_path <- file.path(pdf_dir, paste0("wgcna_modtrait_",
                                            make.names(experiment), ".pdf"))

    job_id <- submit_job(
      kind = "clinical_wgcna",
      fn   = "run_clinical_wgcna",
      args = list(
        session_id = session_id, experiment = experiment,
        traits = traits, min_module_size = min_mod,
        clinical_source = clinical_source,
        pdf_path = pdf_path
      ),
      session_id = session_id
    )
    list(success = TRUE, job_id = job_id, kind = "clinical_wgcna")
  }, res)
}

#* Multi-omics + clinical joint analysis (feature-trait + cross-omics edges).
#* Body: { session_id, exp_a, exp_b, traits:[..], method, top_n, clinical_source }
#* @post /api/clinical/multiomics_joint
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    exp_a <- b$exp_a
    exp_b <- b$exp_b
    traits <- if (length(b$traits)) as.character(b$traits) else NULL
    method <- b$method %||% "spearman"
    top_n <- as.integer(b$top_n %||% 20L)
    clinical_source <- b$clinical_source %||% "experiment"
    out <- run_multiomics_clinical_joint(
      session_id = session_id,
      exp_a = exp_a,
      exp_b = exp_b,
      traits = traits,
      method = method,
      top_n = top_n,
      clinical_source = clinical_source
    )
    list(
      success = TRUE,
      top_a = out$top_a,
      top_b = out$top_b,
      edges = out$edges,
      n_top_a = nrow(out$top_a),
      n_top_b = nrow(out$top_b),
      n_edges = nrow(out$edges)
    )
  }, res)
}

# ══════════════════════════════════════════════════════════
# HEALTH CHECK
# ══════════════════════════════════════════════════════════

#* Health check
#* @get /api/health
#* @serializer unboxedJSON
function() {
  list(status = "ok", version = as.character(packageVersion("EasyMultiProfiler")))
}
