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
source(file.path(.BACKEND_DIR, "helpers/workflow_chipseq.R"))
source(file.path(.BACKEND_DIR, "helpers/workflow_microbiome_16s.R"))
source(file.path(.BACKEND_DIR, "helpers/workflow_microbiome_16s_api.R"))
source(file.path(.BACKEND_DIR, "helpers/clinical.R"))
source(file.path(.BACKEND_DIR, "helpers/jobs.R"))
source(file.path(.BACKEND_DIR, "helpers/user_exec.R"))
source(file.path(.BACKEND_DIR, "helpers/llm.R"))
source(file.path(.BACKEND_DIR, "helpers/user_evolution.R"))
source(file.path(.BACKEND_DIR, "helpers/ai_copilot.R"))
source(file.path(.BACKEND_DIR, "helpers/teaching.R"))
source(file.path(.BACKEND_DIR, "helpers/demo_data.R"))
Sys.setenv(EMP_BACKEND_DIR = .BACKEND_DIR)

#* @filter cors
#* @serializer unboxedJSON
function(req, res) {
  res$setHeader("Access-Control-Allow-Origin",  "*")
  res$setHeader("Access-Control-Allow-Methods", "GET,POST,DELETE,OPTIONS")
  res$setHeader("Access-Control-Allow-Headers", "Content-Type,X-Session-Id,X-Teaching-Token")
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
    ensure_session_dir(session_id)
    if (!file.exists(mae_path(session_id))) {
      return(list(success = TRUE, experiments = list()))
    }
    info <- list_experiments_info(session_id)
    list(success = TRUE, experiments = info)
  }, res)
}

# ══════════════════════════════════════════════════════════
# IMPORT
# ══════════════════════════════════════════════════════════

# Helper: save a Plumber multipart file entry to a temp file, return path.
# Plumber 1.3+ multipart parts look like list(value=<raw>, filename=..., parsed=...).
# After combine_keys (or when only nested parsers succeed), the handler may also
# receive: raw vectors, data.frames, or named list(filename = <raw|df>).
.save_upload <- function(file_entry, suffix = ".tmp") {
  if (is.null(file_entry)) return(NULL)
  if (is.character(file_entry) && length(file_entry) == 1L && file.exists(file_entry)) {
    return(file_entry)
  }

  write_raw <- function(raw_bytes, orig = "") {
    if (is.null(raw_bytes) || !length(raw_bytes)) return(NULL)
    if (is.character(raw_bytes)) raw_bytes <- charToRaw(paste(raw_bytes, collapse = "\n"))
    if (!is.raw(raw_bytes)) return(NULL)
    ext <- if (nzchar(orig)) paste0(".", tools::file_ext(orig)) else suffix
    if (!nzchar(ext) || ext == ".") ext <- suffix
    tmp <- tempfile(fileext = ext)
    writeBin(raw_bytes, tmp)
    tmp
  }

  write_df <- function(df, orig = "") {
    ext <- if (nzchar(orig) && grepl("\\.[A-Za-z0-9]+$", orig)) {
      paste0(".", tools::file_ext(orig))
    } else {
      ".csv"
    }
    tmp <- tempfile(fileext = ext)
    utils::write.csv(df, tmp, row.names = FALSE)
    tmp
  }

  if (is.raw(file_entry)) return(write_raw(file_entry))
  if (is.data.frame(file_entry)) return(write_df(file_entry))

  if (is.list(file_entry)) {
    if (!is.null(file_entry$datapath) && nzchar(file_entry$datapath) && file.exists(file_entry$datapath)) {
      return(file_entry$datapath)
    }

    # Classic plumber multipart part
    if (!is.null(file_entry$value) || !is.null(file_entry$filename) || !is.null(file_entry$parsed)) {
      orig <- as.character(file_entry$filename %||% file_entry$name %||% "")
      if (is.raw(file_entry$value) && length(file_entry$value) > 0) {
        return(write_raw(file_entry$value, orig))
      }
      parsed <- file_entry$parsed
      if (is.raw(parsed) && length(parsed) > 0) return(write_raw(parsed, orig))
      if (is.data.frame(parsed)) return(write_df(parsed, orig))
      if (is.character(parsed) && length(parsed) == 1L && file.exists(parsed)) return(parsed)
    }

    # Named list from combine_keys: list("file.csv" = <raw|df>)
    if (length(file_entry) >= 1L) {
      orig <- names(file_entry)[1] %||% ""
      item <- file_entry[[1]]
      if (is.raw(item) && length(item) > 0) return(write_raw(item, orig))
      if (is.data.frame(item)) return(write_df(item, orig))
      if (is.list(item)) {
        nested <- .save_upload(item, suffix = suffix)
        if (!is.null(nested)) return(nested)
      }
    }
  }

  NULL
}

#* Import data file (multipart: data_file, [metadata_file])
#* @post /api/import
#* @parser multi
#* @parser octet
#* @parser form
#* @parser csv
#* @parser text
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

    # Create session if not provided; otherwise ensure storage dir still exists
    # (browser may keep an old session_id after /tmp was cleared on server restart).
    if (is.null(session_id) || session_id == "") {
      session_id <- create_session()
    } else {
      ensure_session_dir(session_id)
    }

    # Check if MAE already exists → add experiment
    mae_exists <- file.exists(mae_path(session_id))
    if (data_type %in% c("clinical_meta", "clinical_raw")) {
      meta_upload <- read_metadata_table(data_file)
      paired_meta_upload <- if (identical(data_type, "clinical_raw") && !is.null(meta_file)) {
        read_metadata_table(meta_file)
      } else {
        NULL
      }
      standalone_path <- if (identical(data_type, "clinical_meta")) {
        file.path(dirname(mae_path(session_id)), "clinical_uploaded_meta.csv")
      } else {
        file.path(dirname(mae_path(session_id)), "clinical_uploaded_raw.csv")
      }
      standalone_meta_path <- file.path(dirname(mae_path(session_id)), "clinical_uploaded_meta.csv")
      write_standalone_clinical <- function(meta, path) {
        utils::write.csv(meta, path, row.names = FALSE)
      }
      if (!mae_exists) {
        meta <- meta_upload
        write_standalone_clinical(meta, standalone_path)
        if (!is.null(paired_meta_upload) && nrow(paired_meta_upload)) {
          write_standalone_clinical(paired_meta_upload, standalone_meta_path)
        }
        if (identical(data_type, "clinical_raw")) {
          # Backward compatibility for sessions created before split storage.
          p_legacy <- file.path(dirname(mae_path(session_id)), "clinical_uploaded.csv")
          write_standalone_clinical(meta, p_legacy)
        }
        merged_preview <- tryCatch(.clin_merge_external_tables(meta, paired_meta_upload), error = function(e) meta)
        return(list(
          success = TRUE,
          session_id = session_id,
          import_mode = "clinical_standalone",
          updated_experiments = 0L,
          columns = setdiff(names(merged_preview), "primary"),
          orientation = attr(meta, "orientation_note") %||% "samples in rows",
          meta_columns = if (!is.null(paired_meta_upload)) setdiff(names(paired_meta_upload), "primary") else character()
        ))
      }
      mae <- load_mae(session_id)
      out <- tryCatch({
        write_standalone_clinical(meta_upload, standalone_path)
        if (!is.null(paired_meta_upload) && nrow(paired_meta_upload)) {
          write_standalone_clinical(paired_meta_upload, standalone_meta_path)
        }
        if (identical(data_type, "clinical_raw")) {
          p_legacy <- file.path(dirname(mae_path(session_id)), "clinical_uploaded.csv")
          write_standalone_clinical(meta_upload, p_legacy)
        }
        merged <- merge_metadata_into_mae(mae, if (!is.null(paired_meta_upload)) meta_file else data_file)
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
          orientation = attr(if (!is.null(paired_meta_upload)) paired_meta_upload else meta_upload, "orientation_note") %||% "samples in rows",
          meta_columns = if (!is.null(paired_meta_upload)) setdiff(names(paired_meta_upload), "primary") else character()
        )
      }, error = function(e) {
        msg <- as.character(conditionMessage(e))
        if (grepl("No matching sample IDs", msg, ignore.case = TRUE)) {
          meta <- meta_upload
          write_standalone_clinical(meta, standalone_path)
          if (!is.null(paired_meta_upload) && nrow(paired_meta_upload)) {
            write_standalone_clinical(paired_meta_upload, standalone_meta_path)
          }
          if (identical(data_type, "clinical_raw")) {
            p_legacy <- file.path(dirname(mae_path(session_id)), "clinical_uploaded.csv")
            write_standalone_clinical(meta, p_legacy)
          }
          merged_preview <- tryCatch(.clin_merge_external_tables(meta, paired_meta_upload), error = function(e) meta)
          list(
            success = TRUE,
            session_id = session_id,
            import_mode = "clinical_standalone",
            updated_experiments = 0L,
            columns = setdiff(names(merged_preview), "primary"),
            orientation = attr(meta, "orientation_note") %||% "samples in rows",
            meta_columns = if (!is.null(paired_meta_upload)) setdiff(names(paired_meta_upload), "primary") else character()
          )
        } else {
          stop(e)
        }
      })
      return(out)
    }

    if (identical(data_type, "chipseq")) {
      stop("ChIP-seq uses BAM/SAM upload on the Analysis page (ChIP-seq tab), not count matrix import.")
    }

    if (mae_exists) {
      mae <- load_mae(session_id)
      if (experiment_name %in% names(mae)) {
        stop(sprintf(
          "Experiment name '%s' already exists. Choose a unique name to add another omics dataset.",
          experiment_name
        ))
      }
      mae <- add_experiment_to_mae(mae, data_file, meta_file,
                                    experiment_name, data_type,
                                    assay_name, start_level, tax_sep)
      import_mode <- "omics_add"
    } else {
      mae <- build_mae(data_file, meta_file,
                       experiment_name, data_type,
                       assay_name, start_level, tax_sep)
      import_mode <- "omics_new"
    }

    save_mae(session_id, mae)
    tryCatch({
      save_raw_empt(session_id, experiment_name, .promote_to_empt(mae, experiment_name))
    }, error = function(e) NULL)
    register_experiment_meta(session_id, experiment_name, data_type)
    write_experiments_meta(session_id, mae)

    # Summarise
    ex <- mae[[experiment_name]]
    list(success         = TRUE,
         session_id      = session_id,
         import_mode     = import_mode,
         experiment_name = experiment_name,
         samples         = ncol(ex),
         features        = nrow(ex),
         assay           = assay_name,
         omics           = data_type_to_omics(data_type),
         experiment_count = length(mae))
  }, res)
}

#* List bundled demo datasets (16S / RNA-seq / clinical)
#* @get /api/demo_datasets
#* @serializer unboxedJSON
function(res) {
  safe_api({
    ds <- demo_dataset_catalog()
    list(success = TRUE, datasets = lapply(ds, function(d) {
      list(
        id = d$id,
        label = d$label_en %||% d$label,
        label_en = d$label_en %||% d$label,
        label_zh = d$label_zh %||% d$label,
        omics = d$omics,
        description = d$description,
        available = isTRUE(d$available)
      )
    }))
  }, res)
}

#* Import a bundled demo dataset by id
#* Body: { session_id?, dataset_id, experiment_name? }
#* @post /api/import/demo
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    dataset_id <- b$dataset_id
    if (is.null(dataset_id) || !nzchar(as.character(dataset_id))) stop("dataset_id is required")
    session_id <- b$session_id %||% NULL
    out <- import_demo_dataset(
      session_id = session_id,
      dataset_id = dataset_id,
      experiment_name = b$experiment_name %||% NULL,
      assay_name = b$assay_name %||% NULL
    )
    out
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
#* @parser octet
#* @parser form
#* @parser csv
#* @parser text
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
    cd      <- merged_experiment_coldata(session_id, empt)
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
    cd   <- merged_experiment_coldata(session_id, empt)
    cols <- .coldata_column_summaries(cd)
    list(success = TRUE, columns = cols)
  }, res)
}

#* Get feature list (optional limit/offset/q for large matrices)
#* @get /api/features/<session_id>/<experiment>
#* @param limit Max features to return (0 = all; default 0 for backward compat)
#* @param offset Skip first N features after optional search filter
#* @param q Case-insensitive substring filter on feature names
#* @serializer unboxedJSON
function(session_id, experiment, limit = 0, offset = 0, q = "", res) {
  safe_api({
    empt     <- load_empt(session_id, experiment)
    features <- rownames(SummarizedExperiment::assays(empt)[[1]])
    n_total  <- length(features)
  if (nzchar(trimws(as.character(q %||% "")))) {
      qq <- tolower(trimws(as.character(q)))
      features <- features[grepl(qq, tolower(features), fixed = TRUE)]
    }
    n_filtered <- length(features)
    off <- suppressWarnings(as.integer(offset %||% 0L))
    if (!is.finite(off) || off < 0L) off <- 0L
    lim <- suppressWarnings(as.integer(limit %||% 0L))
    truncated <- FALSE
    if (is.finite(lim) && lim > 0L) {
      from <- off + 1L
      to <- min(off + lim, n_filtered)
      if (from <= n_filtered) {
        features <- features[seq.int(from, to)]
      } else {
        features <- character(0)
      }
      truncated <- (off + lim) < n_filtered
    }
    list(
      success = TRUE,
      features = features,
      n_total = n_total,
      n_filtered = n_filtered,
      offset = off,
      truncated = truncated
    )
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
# DATA PREPARATION  (.prepare_load_base in helpers/session.R)
# ══════════════════════════════════════════════════════════

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

#* ChIP-seq workflow profile
#* @post /api/workflows/chipseq/profile
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody, simplifyVector = FALSE)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    list(success = TRUE, profile = chip_profile(session_id, experiment))
  }, res)
}

#* List uploaded / registered BAM/SAM files (treatment vs control groups)
#* @get /api/workflows/chipseq/bams/list
#* @serializer unboxedJSON
function(session_id = NULL, res) {
  safe_api({
  chip_list_bams(session_id)
  }, res)
}

#* Upload one BAM/SAM file and assign treatment (t) or control (c) group
#* @post /api/workflows/chipseq/bams/upload
#* @parser multi
#* @parser octet
#* @parser form
#* @parser csv
#* @parser text
#* @serializer unboxedJSON
function(req, res, session_id = NULL, group = "t") {
  safe_api({
    if (is.null(session_id) || session_id == "") session_id <- create_session()
    else ensure_session_dir(session_id)
    body <- req$body
    f <- .save_upload(body$bam_file %||% body$file %||% body$data_file)
    if (is.null(f)) stop("bam_file is required (multipart field: bam_file).")
    orig <- if (is.list(body$bam_file)) body$bam_file$filename %||% body$bam_file$name else ""
    chip_upload_bam(session_id, f, original_name = orig, group = group)
  }, res)
}

#* Register server-side BAM/SAM paths with group assignment
#* @post /api/workflows/chipseq/bams/register
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody, simplifyVector = FALSE)
    chip_register_bams(b$session_id %||% NULL, b$entries %||% b$files %||% list())
  }, res)
}

#* Scan a server folder for BAM/SAM files and register them
#* @post /api/workflows/chipseq/bams/scan_folder
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody, simplifyVector = FALSE)
    chip_scan_folder(
      session_id = b$session_id %||% NULL,
      folder_path = b$folder_path %||% NULL,
      default_group = b$default_group %||% "t"
    )
  }, res)
}

#* Update treatment/control group for a registered BAM
#* @post /api/workflows/chipseq/bams/set_group
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody, simplifyVector = FALSE)
    chip_set_bam_group(b$session_id %||% NULL, b$file_id %||% b$name, b$group %||% "t")
  }, res)
}

#* Upload pre-called peaks (BED/narrowPeak/broadPeak/GFF) for downstream annotation
#* @post /api/workflows/chipseq/peaks/upload
#* @parser multi
#* @parser octet
#* @parser form
#* @parser csv
#* @parser text
#* @serializer unboxedJSON
function(req, res,
         session_id  = NULL,
         genome      = "hs",
         preset      = "chipseq_tf") {
  safe_api({
    session_id <- as.character(session_id %||% "")[1]
    if (!nzchar(session_id)) session_id <- create_session()
    else ensure_session_dir(session_id)
    genome <- as.character(genome %||% "hs")[1]
    preset <- as.character(preset %||% "chipseq_tf")[1]
    body <- req$body
    peak_entry <- body$peak_file %||% body$data_file %||% body$file
    peak_path <- .save_upload(peak_entry, ".bed")
    if (is.null(peak_path) || !file.exists(peak_path)) {
      stop("peak_file is required (multipart field: peak_file, .bed/.narrowPeak/.broadPeak/.gff)")
    }
    orig <- if (is.list(peak_entry)) {
      peak_entry$filename %||% peak_entry$name %||% basename(peak_path)
    } else basename(peak_path)
    orig <- as.character(orig %||% basename(peak_path))[1]
    out <- chip_upload_peaks(
      session_id    = session_id,
      src_path      = peak_path,
      original_name = orig,
      genome        = genome,
      preset        = preset
    )
    out$session_id <- session_id
    out
  }, res)
}


#* ChIP-seq workflow pre-check validation
#* @post /api/workflows/chipseq/validate
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody, simplifyVector = FALSE)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    list(success = TRUE, validation = chip_validate(session_id, experiment))
  }, res)
}

#* MACS2/3 recommended parameter presets (ChIP-seq, ATAC, CUT&Tag, etc.)
#* @get /api/workflows/chipseq/macs/presets
#* @serializer unboxedJSON
function(res) {
  safe_api({
    list(success = TRUE, presets = chip_macs_presets())
  }, res)
}

#* ChIP-seq peak calling from BAM using MACS2/3
#* @post /api/workflows/chipseq/analyze/peaks
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody, simplifyVector = FALSE)
    out <- chip_call_peaks(
      session_id = b$session_id %||% NULL,
      treatment_bam = b$treatment_bam %||% NULL,
      control_bam = b$control_bam %||% NULL,
      treatment_bams = b$treatment_bams %||% NULL,
      control_bams = b$control_bams %||% NULL,
      use_manifest = isTRUE(b$use_manifest),
      genome = b$genome %||% "hs",
      run_id = b$run_id %||% NULL,
      qvalue = b$qvalue %||% 0.01,
      pvalue = b$pvalue %||% NULL,
      format = b$format %||% NULL,
      preset = b$preset %||% NULL,
      broad = isTRUE(b$broad),
      broad_cutoff = b$broad_cutoff %||% NULL,
      keep_dup = b$keep_dup %||% "auto",
      nomodel = isTRUE(b$nomodel),
      shift = b$shift %||% NULL,
      extsize = b$extsize %||% NULL,
      fix_bimodal = isTRUE(b$fix_bimodal),
      tsize = b$tsize %||% NULL,
      call_summits = isTRUE(b$call_summits),
      fe_cutoff = b$fe_cutoff %||% NULL,
      min_length = b$min_length %||% NULL,
      max_gap = b$max_gap %||% NULL,
      nolambda = isTRUE(b$nolambda),
      slocal = b$slocal %||% NULL,
      llocal = b$llocal %||% NULL,
      scale_to = b$scale_to %||% NULL,
      cutoff_analysis = isTRUE(b$cutoff_analysis),
      save_bdg = isTRUE(b$save_bdg),
      prefer_macs = b$prefer_macs %||% "auto",
      extra_args = b$extra_args %||% NULL
    )
    out
  }, res)
}

#* ChIP-seq peak annotation (ChIPseeker annotatePeak)
#* @post /api/workflows/chipseq/analyze/annotation
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody, simplifyVector = FALSE)
    chip_annotate_peaks(
      session_id = b$session_id %||% NULL,
      peak_file = b$peak_file %||% NULL,
      txdb = b$txdb %||% "TxDb.Hsapiens.UCSC.hg38.knownGene",
      anno_db = b$anno_db %||% "org.Hs.eg.db",
      tss_upstream = b$tss_upstream %||% -3000,
      tss_downstream = b$tss_downstream %||% 3000
    )
  }, res)
}

#* ChIP-seq full annotation: pie chart, promoter filters, GO/KEGG bubble plots
#* @post /api/workflows/chipseq/analyze/annotation_full
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody, simplifyVector = FALSE)
    chip_annotate_peaks_full(
      session_id = b$session_id %||% NULL,
      peak_file = b$peak_file %||% NULL,
      genome = b$genome %||% "hs",
      tss_upstream = b$tss_upstream %||% -3000,
      tss_downstream = b$tss_downstream %||% 3000,
      score_cutoff = b$score_cutoff %||% 5
    )
  }, res)
}

#* ChIP-seq + RNA-seq co-analysis (heatmap, volcano, GO/KEGG)
#* @post /api/workflows/chipseq/analyze/rnaseq_coanalysis
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody, simplifyVector = FALSE)
    chip_rnaseq_coanalysis(
      session_id = b$session_id %||% NULL,
      rnaseq_experiment = b$rnaseq_experiment %||% NULL,
      peak_annotation_csv = b$peak_annotation_csv %||% NULL,
      genome = b$genome %||% "hs",
      score_cutoff = b$score_cutoff %||% 10,
      min_total_counts = b$min_total_counts %||% 100,
      rnaseq_p_cutoff = b$rnaseq_p_cutoff %||% 0.05,
      promoter_filter = if (is.null(b$promoter_filter)) TRUE else isTRUE(b$promoter_filter)
    )
  }, res)
}

#* ChIP-seq cross-omics integration with RNAseq / proteomics differential results
#* @post /api/workflows/chipseq/analyze/cross_omics
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody, simplifyVector = FALSE)
    chip_cross_integrate(
      session_id = b$session_id %||% NULL,
      peak_annotation_csv = b$peak_annotation_csv %||% NULL,
      rnaseq_experiment = b$rnaseq_experiment %||% NULL,
      proteomics_experiment = b$proteomics_experiment %||% NULL,
      rnaseq_p_cutoff = b$rnaseq_p_cutoff %||% 0.05,
      rnaseq_fc_cutoff = b$rnaseq_fc_cutoff %||% 1.0,
      proteomics_p_cutoff = b$proteomics_p_cutoff %||% 0.05,
      proteomics_fc_cutoff = b$proteomics_fc_cutoff %||% 0.5
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
    comparison_mode   <- b$comparison_mode %||% "pairwise"
    cores             <- b$cores %||% "auto"

    result <- run_diff(session_id, experiment, method, group_var, ref_group,
                      test_group, filter_low = filter_low,
                      subset_two_groups = subset_two_groups,
                      comparison_mode = comparison_mode, cores = cores)
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
    comparison_mode   <- b$comparison_mode %||% "pairwise"
    cores             <- b$cores %||% "auto"

    job_id <- submit_job(
      kind = "differential",
      fn = "run_diff",
      args = list(
        session_id = session_id, experiment = experiment, method = method,
        group_var = group_var, ref_group = ref_group, test_group = test_group,
        filter_low = filter_low, subset_two_groups = subset_two_groups,
        comparison_mode = comparison_mode, cores = cores
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

.viz_api_style <- function(b) {
  old <- emp_viz_style_begin(b)
  on.exit(emp_viz_style_end(old), add = TRUE)
  invisible(NULL)
}

#* Transcriptomics heatmap
#* @post /api/workflows/transcriptomics/visualize/heatmap
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    .viz_api_style(b)
    session_id <- if (!is.null(b$session_id) && length(b$session_id) > 0) as.character(b$session_id[[1]]) else NULL
    experiment <- if (!is.null(b$experiment) && length(b$experiment) > 0) as.character(b$experiment[[1]]) else NULL
    group <- if (!is.null(b$group) && length(b$group) > 0) as.character(b$group[[1]]) else NULL
    top_n <- if (!is.null(b$top_n) && length(b$top_n) > 0) as.integer(b$top_n[[1]]) else 50L
    features <- .parse_feature_list(b$features)
    cluster_rows <- if (is.null(b$cluster_rows)) TRUE else isTRUE(b$cluster_rows)
    cluster_cols <- if (is.null(b$cluster_cols)) TRUE else isTRUE(b$cluster_cols)
    show_gene_names <- if (is.null(b$show_gene_names)) NULL else isTRUE(b$show_gene_names)
    font_size <- emp_viz_scale_num(b$font_size %||% 11, 11)
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
    .viz_api_style(b)
    session_id <- if (!is.null(b$session_id) && length(b$session_id) > 0) as.character(b$session_id[[1]]) else NULL
    experiment <- if (!is.null(b$experiment) && length(b$experiment) > 0) as.character(b$experiment[[1]]) else NULL
    fc_cutoff <- if (!is.null(b$fc_cutoff) && length(b$fc_cutoff) > 0) as.numeric(b$fc_cutoff[[1]]) else 1.0
    p_cutoff <- if (!is.null(b$p_cutoff) && length(b$p_cutoff) > 0) as.numeric(b$p_cutoff[[1]]) else 0.05
    color_panel <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL

    img <- tx_make_volcano(session_id, experiment, fc_cutoff = fc_cutoff, p_cutoff = p_cutoff,
                           color_panel = color_panel, custom_colors = custom_colors)
    .viz_api_plot_response(img)
  }, res)
}

#* Metagenomics functional heatmap
#* @post /api/workflows/metagenomics/visualize/heatmap
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    .viz_api_style(b)
    session_id <- if (!is.null(b$session_id) && length(b$session_id) > 0) as.character(b$session_id[[1]]) else NULL
    experiment <- if (!is.null(b$experiment) && length(b$experiment) > 0) as.character(b$experiment[[1]]) else NULL
    group <- if (!is.null(b$group) && length(b$group) > 0) as.character(b$group[[1]]) else NULL
    top_n <- if (!is.null(b$top_n) && length(b$top_n) > 0) as.integer(b$top_n[[1]]) else 50L
    features <- .parse_feature_list(b$features)
    cluster_rows <- if (is.null(b$cluster_rows)) TRUE else isTRUE(b$cluster_rows)
    cluster_cols <- if (is.null(b$cluster_cols)) TRUE else isTRUE(b$cluster_cols)
    show_gene_names <- if (is.null(b$show_gene_names)) NULL else isTRUE(b$show_gene_names)
    font_size <- emp_viz_scale_num(b$font_size %||% 11, 11)
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
    .viz_api_style(b)
    session_id <- if (!is.null(b$session_id) && length(b$session_id) > 0) as.character(b$session_id[[1]]) else NULL
    experiment <- if (!is.null(b$experiment) && length(b$experiment) > 0) as.character(b$experiment[[1]]) else NULL
    fc_cutoff <- if (!is.null(b$fc_cutoff) && length(b$fc_cutoff) > 0) as.numeric(b$fc_cutoff[[1]]) else 1.0
    p_cutoff <- if (!is.null(b$p_cutoff) && length(b$p_cutoff) > 0) as.numeric(b$p_cutoff[[1]]) else 0.05
    color_panel <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL

    img <- mgx_make_volcano(session_id, experiment, fc_cutoff = fc_cutoff, p_cutoff = p_cutoff,
                            color_panel = color_panel, custom_colors = custom_colors)
    .viz_api_plot_response(img)
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
    .viz_api_style(b)
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
    .viz_api_style(b)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    tax_sep <- b$tax_sep %||% ";"
    from_level <- b$from_level %||% "Phylum"
    to_level <- b$to_level %||% "Genus"
    top_n <- as.integer(b$top_n %||% 25L)
    width <- emp_viz_scale_num(b$width %||% 10, 10)
    height <- emp_viz_scale_num(b$height %||% 6, 6)
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
    c(list(success = TRUE,
           plot = out$plot,
           edges = out$edges,
           from_nodes = out$from_nodes,
           to_nodes = out$to_nodes),
      viz_pdf_meta(out$pdf %||% NULL))
  }, res)
}

#* Microbiome 16S taxa correlation network plot
#* @post /api/workflows/microbiome_16s/visualize/network
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    .viz_api_style(b)
    session_id <- b$session_id %||% NULL
    experiment <- b$experiment %||% NULL
    method <- b$method %||% "spearman"
    cutoff <- as.numeric(b$cutoff %||% 0.6)
    top_n <- as.integer(b$top_n %||% 40L)
    width <- emp_viz_scale_num(b$width %||% 8, 8)
    height <- emp_viz_scale_num(b$height %||% 8, 8)

    out <- m16s_visualize_network(
      session_id = session_id,
      experiment = experiment,
      method = method,
      cutoff = cutoff,
      top_n = top_n,
      width = width,
      height = height
    )
    c(list(success = TRUE,
           plot = out$plot,
           nodes = out$nodes,
           edges = out$edges,
           method = out$method,
           cutoff = out$cutoff),
      viz_pdf_meta(out$pdf %||% NULL))
  }, res)
}

#* Barplot
#* @post /api/visualize/barplot
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    .viz_api_style(b)
    session_id <- b$session_id
    experiment <- b$experiment
    group      <- b$group   %||% NULL
    feature    <- b$feature %||% NULL
    mode       <- b$mode    %||% "top20"
    top_n      <- as.integer(b$top_n %||% 20L)
    color_panel <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL
    width  <- emp_viz_scale_num(b$width %||% 9, 9)
    height <- emp_viz_scale_num(b$height %||% 6, 6)

    out <- make_barplot(session_id, experiment, group, feature, mode, top_n,
                        width = width, height = height,
                        color_panel = color_panel,
                        custom_colors = custom_colors)
    .viz_api_plot_response(out)
  }, res)
}

#* Boxplot
#* @post /api/visualize/boxplot
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    .viz_api_style(b)
    session_id <- b$session_id
    experiment <- b$experiment
    group      <- b$group   %||% NULL
    feature    <- b$feature %||% NULL
    color_panel <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL
    width  <- emp_viz_scale_num(b$width %||% 9, 9)
    height <- emp_viz_scale_num(b$height %||% 6, 6)

    out <- make_boxplot(session_id, experiment, group, feature,
                        width = width, height = height,
                        color_panel = color_panel,
                        custom_colors = custom_colors)
    .viz_api_plot_response(out)
  }, res)
}

#* Heatmap
#* @post /api/visualize/heatmap
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    .viz_api_style(b)
    session_id <- b$session_id
    experiment <- b$experiment
    group      <- b$group %||% NULL
    top_n      <- as.integer(b$top_n %||% 50L)
    features   <- .parse_feature_list(b$features)
    cluster_rows <- if (is.null(b$cluster_rows)) TRUE else isTRUE(b$cluster_rows)
    cluster_cols <- if (is.null(b$cluster_cols)) TRUE else isTRUE(b$cluster_cols)
    show_gene_names <- if (is.null(b$show_gene_names)) NULL else isTRUE(b$show_gene_names)
    font_size <- emp_viz_scale_num(b$font_size %||% 11, 11)
    width <- emp_viz_scale_num(b$width %||% 11, 11)
    height <- emp_viz_scale_num(b$height %||% 8, 8)
    color_panel <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL

    img <- make_heatmap(session_id, experiment, group, top_n,
                          features = features,
                          cluster_rows = cluster_rows,
                          cluster_cols = cluster_cols,
                          show_gene_names = show_gene_names,
                          width = width,
                          height = height,
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
    .viz_api_style(b)
    session_id <- b$session_id
    experiment <- b$experiment
    fc_cutoff  <- as.numeric(b$fc_cutoff %||% 1.0)
    p_cutoff   <- as.numeric(b$p_cutoff  %||% 0.05)
    use_padj   <- if (is.null(b$use_padj)) TRUE else isTRUE(b$use_padj)
    label_top  <- as.integer(b$label_top %||% 15L)
    color_panel <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL
    width  <- emp_viz_scale_num(b$width %||% 8, 8)
    height <- emp_viz_scale_num(b$height %||% 7, 7)

    img <- make_volcano(session_id, experiment,
                        fc_cutoff = fc_cutoff, p_cutoff = p_cutoff,
                        use_padj = use_padj, label_top = label_top,
                        width = width, height = height,
                        color_panel = color_panel,
                        custom_colors = custom_colors)
    .viz_api_plot_response(img)
  }, res)
}

#* DEG heatmap – all DEGs from the cached DESeq2 table, pheatmap style
#* @post /api/visualize/deg_heatmap
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b            <- jsonlite::fromJSON(req$postBody)
    .viz_api_style(b)
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
    font_size    <- emp_viz_scale_num(b$font_size %||% 10, 10)
    width        <- emp_viz_scale_num(b$width %||% NA_real_, NA_real_)
    height       <- emp_viz_scale_num(b$height %||% NA_real_, NA_real_)
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
                             width = width,
                             height = height,
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
    .viz_api_style(b)
    session_id <- b$session_id
    experiment <- b$experiment
    group      <- b$group %||% NULL
    dim1       <- as.integer(b$dim1 %||% 1L)
    dim2       <- as.integer(b$dim2 %||% 2L)
    width      <- emp_viz_scale_num(b$width %||% 9, 9)
    height     <- emp_viz_scale_num(b$height %||% 7, 7)
    proj_width <- emp_viz_scale_num(b$proj_width %||% 7, 7)
    proj_height <- emp_viz_scale_num(b$proj_height %||% 4.5, 4.5)
    groups_include <- b$groups_include %||% NULL
    color_panel <- b$color_panel %||% NULL
    ordination <- b$ordination %||% "auto"
    custom_colors <- b$custom_colors %||% NULL

    out <- make_scatter(session_id, experiment, group, dim1, dim2,
                        width = width, height = height,
                        proj_width = proj_width, proj_height = proj_height,
                        groups_include = groups_include,
                        color_panel = color_panel, ordination = ordination,
                        custom_colors = custom_colors)
    c(list(success = TRUE), out)
  }, res)
}

#* Structure / composition plot
#* @post /api/visualize/structure
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    .viz_api_style(b)
    session_id <- b$session_id
    experiment <- b$experiment
    group      <- b$group %||% NULL
    top_n      <- as.integer(b$top_n %||% 10L)
    color_panel <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL
    width  <- emp_viz_scale_num(b$width %||% 11, 11)
    height <- emp_viz_scale_num(b$height %||% 6, 6)

    out <- make_structure(session_id, experiment, group, top_n,
                          width = width, height = height,
                          color_panel = color_panel,
                          custom_colors = custom_colors)
    .viz_api_plot_response(out)
  }, res)
}

#* Alpha diversity plot
#* @post /api/visualize/alpha
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b          <- jsonlite::fromJSON(req$postBody)
    .viz_api_style(b)
    session_id <- b$session_id
    experiment <- b$experiment
    group      <- b$group  %||% NULL
    metric     <- b$metric %||% "shannon"
    source     <- b$source %||% "current"
    color_panel <- b$color_panel %||% NULL
    custom_colors <- b$custom_colors %||% NULL
    width  <- emp_viz_scale_num(b$width %||% 8, 8)
    height <- emp_viz_scale_num(b$height %||% 6, 6)

    out <- make_alpha_plot(session_id, experiment, group, metric, source,
                           width = width, height = height,
                           color_panel = color_panel,
                           custom_colors = custom_colors)
    .viz_api_plot_response(out)
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
    .csv_response(df)
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
    .csv_response(df)
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
    .csv_response(df)
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
    .csv_response(cd)
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
    .csv_response(df)
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
    .csv_response(df)
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
    cohort_filter <- b$cohort_filter %||% NULL
    out <- run_clinical_systematic_summary(
      session_id = session_id,
      source = source,
      experiment = experiment,
      group_var = group_var,
      skip_high_cardinality = skip_high_cardinality,
      max_levels = max_levels,
      table_engine = table_engine,
      cohort_filter = cohort_filter
    )
    list(
      success = TRUE,
      baseline = out$baseline,
      within = out$within,
      between = out$between,
      n_baseline = nrow(out$baseline),
      n_within = nrow(out$within),
      n_between = nrow(out$between),
      n_pairs = out$meta$n_pairs %||% 0L,
      design_type = out$meta$design_type %||% NULL,
      group_var = out$meta$group_var %||% NULL,
      n_groups = out$meta$n_groups %||% 0L,
      analysis_note = out$meta$analysis_note %||% NULL
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

#* Multi-omics + clinical marker diagnostic model.
#* Body: { session_id, experiments:[..], outcome_var, positive_class, methods:[..],
#*         clinical_source, include_clinical_numeric, max_features_per_omics,
#*         top_n, validation_fraction, seed }
#* @post /api/clinical/marker_model
#* @serializer unboxedJSON
function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    experiments <- if (length(b$experiments)) as.character(b$experiments) else character()
    methods <- if (length(b$methods)) as.character(b$methods) else c("randomForest", "lasso", "xgboost")
    out <- run_clinical_marker_model(
      session_id = session_id,
      experiments = experiments,
      outcome_var = b$outcome_var %||% NULL,
      positive_class = b$positive_class %||% NULL,
      methods = methods,
      clinical_source = b$clinical_source %||% "experiment",
      include_clinical_numeric = if (is.null(b$include_clinical_numeric)) TRUE else isTRUE(b$include_clinical_numeric),
      max_features_per_omics = as.integer(b$max_features_per_omics %||% 200L),
      top_n = as.integer(b$top_n %||% 30L),
      validation_fraction = as.numeric(b$validation_fraction %||% 0.3),
      seed = as.integer(b$seed %||% 123L)
    )
    list(
      success = TRUE,
      performance = out$performance,
      markers = out$markers,
      sample_scores = out$sample_scores,
      n_performance = nrow(out$performance),
      n_markers = nrow(out$markers),
      n_scores = nrow(out$sample_scores),
      meta = out$meta
    )
  }, res)
}

# ══════════════════════════════════════════════════════════
# USER R EXEC (local learning — arbitrary code in server process)
# ══════════════════════════════════════════════════════════

#* Execute user R snippet (Code Lab — canonical URL for browsers / proxies).
#* @post /api/user_r/run
#* @serializer unboxedJSON
function(req, res) {
  plumber_user_r_post(req, res)
}

#* Same as /api/user_r/run (legacy / alternate path).
#* @post /api/exec/user_r
#* @serializer unboxedJSON
function(req, res) {
  plumber_user_r_post(req, res)
}

#* Download a Code Lab execution package (script + outputs + manifest).
#* @get /api/code_lab/artifacts/<session_id>/<artifact_name>
#* @serializer contentType list(type="application/zip")
function(session_id, artifact_name, res) {
  plumber_code_lab_artifact_get(session_id, artifact_name, res)
}

# ══════════════════════════════════════════════════════════
# LLM CODE OPTIMIZATION (Code Lab)
# ══════════════════════════════════════════════════════════

#* Optimize a Code Lab R snippet through a configured LLM provider.
#* @post /api/llm/optimize_r
#* @serializer unboxedJSON
function(req, res) {
  plumber_llm_optimize_r_post(req, res)
}

#* Return last OpenRouter model probe manifest (working / failed lists).
#* @get /api/llm/openrouter_verified
#* @serializer unboxedJSON
function(req, res) {
  plumber_llm_openrouter_verified_get(req, res)
}

#* Probe OpenRouter models with a minimal chat request; writes verified manifest.
#* Body: { config: { api_key, base_url?, timeout? }, models?: string[] }
#* @post /api/llm/probe_openrouter
#* @serializer unboxedJSON
function(req, res) {
  plumber_llm_probe_openrouter_post(req, res)
}

#* AI copilot: interpret an analysis result and suggest next steps
#* Body: { context: {...}, provider?, config?, user_id? }
#* @post /api/ai/interpret
#* @serializer unboxedJSON
function(req, res) {
  plumber_ai_interpret_post(req, res)
}

#* Self-evolution: record anonymized usage event
#* Body: { user_id, event_type, payload?, session_id? }
#* @post /api/evolution/event
#* @serializer unboxedJSON
function(req, res) {
  plumber_evolution_event_post(req, res)
}

#* Self-evolution: aggregated user profile
#* @get /api/evolution/profile
#* @serializer unboxedJSON
function(req, user_id = NULL, res) {
  plumber_evolution_profile_get(user_id, req, res)
}

# ══════════════════════════════════════════════════════════
# TEACHING (cases, prompts, learning trace)
# ══════════════════════════════════════════════════════════

#* List teaching cases
#* @get /api/teaching/cases
#* @serializer unboxedJSON
function(res) {
  plumber_teaching_cases_get(res)
}

#* Get one teaching case with task cards, videos, quiz (no answers), unlock state
#* @get /api/teaching/cases/<case_id>
#* @serializer unboxedJSON
function(req, case_id, res) {
  plumber_teaching_case_get(case_id, req, res)
}

#* Submit step quiz (all questions must be correct to unlock next step)
#* @post /api/teaching/quiz
#* @serializer unboxedJSON
function(req, res) {
  plumber_teaching_quiz_post(req, res)
}

#* Prompt template library
#* @get /api/teaching/prompts
#* @serializer unboxedJSON
function(res) {
  plumber_teaching_prompts_get(res)
}

#* Append learning trace event (requires X-Teaching-Token)
#* @post /api/teaching/trace
#* @serializer unboxedJSON
function(req, res) {
  plumber_teaching_trace_post(req, res)
}

#* List learning trace events
#* @get /api/teaching/trace
#* @serializer unboxedJSON
function(req, res, user_id = NULL, limit = 200) {
  plumber_teaching_trace_get(req, res, user_id, limit)
}

#* Submit task reflection / AI declaration
#* @post /api/teaching/reflection
#* @serializer unboxedJSON
function(req, res) {
  plumber_teaching_reflection_post(req, res)
}

#* Student progress (teacher may pass user_id)
#* @get /api/teaching/progress
#* @serializer unboxedJSON
function(req, res, user_id = NULL) {
  plumber_teaching_progress_get(req, res, user_id)
}

#* Pre-class question card template
#* @get /api/teaching/preclass
#* @serializer unboxedJSON
function(res) {
  plumber_teaching_preclass_get(res)
}

#* Submit pre-class question card
#* @post /api/teaching/preclass
#* @serializer unboxedJSON
function(req, res) {
  plumber_teaching_preclass_post(req, res)
}

#* AI critique training cases
#* @get /api/teaching/critique
#* @serializer unboxedJSON
function(res) {
  plumber_teaching_critique_get(res)
}

#* Submit AI critique exercise
#* @post /api/teaching/critique
#* @serializer unboxedJSON
function(req, res) {
  plumber_teaching_critique_post(req, res)
}

#* Save interpretation / hypothesis journal
#* @post /api/teaching/journal
#* @serializer unboxedJSON
function(req, res) {
  plumber_teaching_journal_post(req, res)
}

#* Build course project report (markdown)
#* @get /api/teaching/report
#* @serializer unboxedJSON
function(req, res) {
  plumber_teaching_report_get(req, res)
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
