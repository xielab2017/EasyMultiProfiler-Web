# Data import helpers

metadata_sample_ids <- function(metadata_file = NULL) {
  if (is.null(metadata_file) || !file.exists(metadata_file)) return(character())
  meta <- tryCatch(read_table_auto(metadata_file), error = function(e) NULL)
  if (is.null(meta) || ncol(meta) == 0) return(character())

  primary_col <- names(meta)[1]
  for (candidate in names(meta)) {
    if (grepl("sample|id|primary", candidate, ignore.case = TRUE)) {
      primary_col <- candidate
      break
    }
  }
  unique(as.character(meta[[primary_col]]))
}

should_transpose_sample_rows <- function(df, metadata_ids = character(),
                                         data_type = "normal", tax_sep = ";") {
  if (is.null(df) || ncol(df) <= 1 || nrow(df) <= 1) return(FALSE)

  first_col_values <- as.character(df[[1]])
  feature_names <- names(df)[-1]
  first_name <- tolower(names(df)[1])
  sample_hint <- grepl("sample|sampleid|sample_id|primary", first_name)

  row_match <- 0
  col_match <- 0
  if (length(metadata_ids) > 0) {
    row_match <- mean(first_col_values %in% metadata_ids)
    col_match <- mean(feature_names %in% metadata_ids)
  }

  sep_to_check <- if (is.null(tax_sep) || tax_sep == "auto" || !nzchar(tax_sep)) ";" else tax_sep
  taxonomy_feature_cols <- isTRUE(data_type == "tax") &&
    any(grepl(sep_to_check, feature_names, fixed = TRUE))

  # Common uploaded shape: first column is sample IDs, remaining columns are features.
  (row_match >= 0.5 && row_match > col_match) ||
    (sample_hint && taxonomy_feature_cols) ||
    (sample_hint && ncol(df) > nrow(df) && col_match < 0.2)
}

transpose_sample_rows <- function(df) {
  sample_names <- as.character(df[[1]])
  if (any(!nzchar(sample_names))) stop("Sample-row matrix contains empty sample IDs.")
  if (anyDuplicated(sample_names)) {
    stop("Sample-row matrix contains duplicated sample IDs: ",
         paste(unique(sample_names[duplicated(sample_names)]), collapse = ", "))
  }

  feature_names <- names(df)[-1]
  value_df <- df[, -1, drop = FALSE]
  numeric_cols <- lapply(value_df, function(x) suppressWarnings(as.numeric(as.character(x))))
  keep <- vapply(numeric_cols, function(x) {
    length(x) > 0 && mean(is.na(x)) <= 0.2
  }, logical(1))
  if (!any(keep)) stop("No numeric feature columns found after transposing sample-row matrix.")

  numeric_mat <- do.call(cbind, numeric_cols[keep])
  numeric_mat[is.na(numeric_mat)] <- 0
  colnames(numeric_mat) <- feature_names[keep]
  rownames(numeric_mat) <- sample_names

  transposed <- t(numeric_mat)
  out <- as.data.frame(transposed, check.names = FALSE, stringsAsFactors = FALSE)
  out <- cbind(feature = rownames(transposed), out)
  rownames(out) <- NULL
  out
}

read_metadata_table <- function(metadata_file) {
  if (is.null(metadata_file) || !file.exists(metadata_file)) return(NULL)
  meta <- read_table_auto(metadata_file)
  if (is.null(meta) || !ncol(meta)) return(NULL)
  .id_like <- function(x) {
    x <- trimws(as.character(x))
    x <- x[nzchar(x)]
    if (!length(x)) return(FALSE)
    xx <- toupper(gsub("[\\.\\-]+", "_", x))
    mean(grepl("(^[A-Z]{1,3}_[A-Z0-9]+)|(_XYL_)|(^S\\d+$)|(^SAMPLE)", xx)) >= 0.4
  }
  .pick_primary <- function(df) {
    out <- names(df)[1]
    for (candidate in names(df)) {
      if (grepl("sample|id|primary", candidate, ignore.case = TRUE)) {
        out <- candidate
        break
      }
    }
    out
  }

  primary_col <- .pick_primary(meta)
  need_transpose <- (!grepl("sample|id|primary", primary_col, ignore.case = TRUE) &&
                     ncol(meta) > nrow(meta) &&
                     ncol(meta) >= 3L &&
                     .id_like(names(meta)[-1]) &&
                     !.id_like(meta[[primary_col]]))
  orientation_note <- "samples in rows"
  if (isTRUE(need_transpose)) {
    var_col <- as.character(meta[[primary_col]])
    m <- as.matrix(meta[, setdiff(names(meta), primary_col), drop = FALSE])
    rownames(m) <- var_col
    mt <- as.data.frame(t(m), stringsAsFactors = FALSE, check.names = FALSE)
    mt$primary <- rownames(mt)
    meta <- mt[, c("primary", setdiff(names(mt), "primary")), drop = FALSE]
    orientation_note <- "transposed and corrected"
  } else {
    names(meta)[names(meta) == primary_col] <- "primary"
  }

  meta$primary <- as.character(meta$primary)
  meta <- meta[nzchar(meta$primary), , drop = FALSE]
  meta <- meta[!duplicated(meta$primary), , drop = FALSE]
  attr(meta, "orientation_note") <- orientation_note
  meta
}

detect_taxonomy_start_level <- function(feature_values, tax_sep = ";") {
  vals <- as.character(feature_values)
  vals <- vals[nzchar(vals)]
  if (!length(vals)) return(NULL)
  sep <- if (is.null(tax_sep) || tax_sep == "auto" || !nzchar(tax_sep)) ";" else tax_sep
  first_token <- trimws(strsplit(vals[1], sep, fixed = TRUE)[[1]][1])
  prefix <- sub("^([A-Za-z])_.*$", "\\1", first_token)
  prefix_map <- c(
    "d" = "Domain",
    "k" = "Kindom",
    "p" = "Phylum",
    "c" = "Class",
    "o" = "Order",
    "f" = "Family",
    "g" = "Genus",
    "s" = "Species"
  )
  inferred <- unname(prefix_map[tolower(prefix)])
  if (is.na(inferred) || !nzchar(inferred)) NULL else inferred
}

build_mae <- function(data_file, metadata_file = NULL,
                      experiment_name = "experiment",
                      data_type       = "normal",   # "tax" | "normal"
                      assay_name      = "counts",
                      start_level     = "Species",
                      tax_sep         = ";") {

  # ── 1. Read & clean count matrix ──────────────────────────────────────────
  df <- read_table_auto(data_file)
  meta_ids <- metadata_sample_ids(metadata_file)
  if (should_transpose_sample_rows(df, meta_ids, data_type, tax_sep)) {
    df <- transpose_sample_rows(df)
  }
  df <- clean_feature_col(df)
  df <- enforce_numeric_samples(df)

  if (ncol(df) <= 1) stop("No numeric sample columns found after processing.")

  sampleID <- names(df)[-1]
  original_feature_labels <- trimws(as.character(df$feature))

  # ── 2. Build EMPT via EasyMultiProfiler import function ───────────────────
  if (data_type == "tax") {
    tax_info <- detect_taxonomy(as.character(df$feature))
    if (tax_sep == "auto") tax_sep <- tax_info$sep
    inferred_start <- detect_taxonomy_start_level(df$feature, tax_sep)
    if (!is.null(inferred_start)) start_level <- inferred_start
    empt <- EasyMultiProfiler::EMP_taxonomy_import(
      data        = df,
      file_format = NULL,
      start_level = start_level,
      sep         = tax_sep,
      assay_name  = assay_name
    )
  } else {
    empt <- EasyMultiProfiler::EMP_normal_import(
      data       = df,
      sampleID   = sampleID,
      assay_name = assay_name
    )
  }
  empt <- restore_feature_rownames(
    empt,
    original_labels = if (data_type == "tax") original_feature_labels else NULL
  )

  sample_names <- colnames(empt)

  # ── 3. Build colData ───────────────────────────────────────────────────────
  coldata_df <- data.frame(row.names = sample_names, stringsAsFactors = FALSE)

  if (!is.null(metadata_file) && file.exists(metadata_file)) {
    tryCatch({
      meta <- read_metadata_table(metadata_file)
      if (is.null(meta)) return(NULL)
      sn_char      <- as.character(sample_names)

      # Match
      matched <- meta[meta$primary %in% sn_char, , drop = FALSE]
      if (nrow(matched) > 0) {
        # Add missing samples
        missing <- setdiff(sn_char, matched$primary)
        if (length(missing) > 0) {
          miss_df <- data.frame(primary = missing, stringsAsFactors = FALSE)
          for (col in setdiff(names(matched), "primary")) miss_df[[col]] <- NA
          matched <- rbind(matched, miss_df)
        }
        matched  <- matched[match(sn_char, matched$primary), , drop = FALSE]
        primvals <- matched$primary
        matched$primary <- NULL
        rownames(matched) <- primvals
        coldata_df <- matched
      }
    }, error = function(e) {
      message("Metadata processing warning: ", e$message)
    })
  }

  coldata <- S4Vectors::DataFrame(coldata_df)

  # ── 4. Build MultiAssayExperiment ─────────────────────────────────────────
  objlist        <- list(empt)
  names(objlist) <- experiment_name
  dfmap <- data.frame(
    assay   = factor(experiment_name),
    primary = sample_names,
    colname = sample_names
  )

  MultiAssayExperiment::MultiAssayExperiment(
    experiments = objlist,
    colData     = coldata,
    sampleMap   = S4Vectors::DataFrame(dfmap)
  )
}

merge_metadata_into_mae <- function(mae, metadata_file) {
  .norm_id <- function(x) {
    x <- toupper(trimws(as.character(x)))
    x <- gsub("\\.", "_", x)
    x <- sub("^X_", "", x)
    x <- sub("^X([A-Z])_", "\\1_", x)
    x <- gsub("_+", "_", x)
    x <- sub("_[0-9]+$", "", x)
    x <- sub("^[A-Z]([A-Z]_XYL_)", "\\1", x)
    x
  }
  meta <- read_metadata_table(metadata_file)
  if (is.null(meta) || !nrow(meta)) stop("Clinical/metadata file is empty or has no sample IDs.")

  exp_list <- as.list(MultiAssayExperiment::experiments(mae))
  touched <- 0L
  for (nm in names(exp_list)) {
    empt <- exp_list[[nm]]
    sn <- as.character(colnames(empt))
    hit <- meta[meta$primary %in% sn, , drop = FALSE]
    if (!nrow(hit)) {
      idx <- match(.norm_id(sn), .norm_id(meta$primary))
      ok <- which(!is.na(idx))
      if (length(ok)) {
        hit <- meta[idx[ok], , drop = FALSE]
        hit$primary <- sn[ok]
      }
    }
    if (!nrow(hit)) next
    cd <- as.data.frame(SummarizedExperiment::colData(empt), stringsAsFactors = FALSE)
    if (is.null(rownames(cd)) || !length(rownames(cd))) {
      rownames(cd) <- sn
    }
    all_rows <- sn
    merged <- data.frame(row.names = all_rows, stringsAsFactors = FALSE)
    for (col in union(names(cd), setdiff(names(hit), "primary"))) {
      vals <- rep(NA_character_, length(all_rows))
      if (col %in% names(cd)) vals[match(rownames(cd), all_rows)] <- as.character(cd[[col]])
      if (col %in% names(hit)) vals[match(hit$primary, all_rows)] <- as.character(hit[[col]])
      merged[[col]] <- vals
    }
    SummarizedExperiment::colData(empt) <- S4Vectors::DataFrame(merged)
    exp_list[[nm]] <- empt
    touched <- touched + 1L
  }
  if (!touched) stop("No matching sample IDs found between clinical file and loaded experiments.")

  existing_cd <- as.data.frame(MultiAssayExperiment::colData(mae), stringsAsFactors = FALSE)
  all_primary <- union(rownames(existing_cd), meta$primary)
  merged_cd <- data.frame(row.names = all_primary, stringsAsFactors = FALSE)
  for (col in union(names(existing_cd), setdiff(names(meta), "primary"))) {
    vals <- rep(NA_character_, length(all_primary))
    if (col %in% names(existing_cd)) vals[match(rownames(existing_cd), all_primary)] <- as.character(existing_cd[[col]])
    if (col %in% names(meta)) vals[match(meta$primary, all_primary)] <- as.character(meta[[col]])
    merged_cd[[col]] <- vals
  }

  mae_new <- MultiAssayExperiment::MultiAssayExperiment(
    experiments = exp_list,
    colData = S4Vectors::DataFrame(merged_cd),
    sampleMap = mae@sampleMap
  )
  list(mae = mae_new, touched = touched, columns = setdiff(names(meta), "primary"))
}

add_experiment_to_mae <- function(mae, data_file, metadata_file = NULL,
                                   experiment_name = "experiment2",
                                   data_type = "normal",
                                   assay_name = "counts",
                                   start_level = "Species",
                                   tax_sep = ";") {
  existing_exps <- names(as.list(MultiAssayExperiment::experiments(mae)))
  if (experiment_name %in% existing_exps) {
    stop(sprintf(
      "Experiment name '%s' already exists in this session. Choose a unique name to add another omics dataset.",
      experiment_name
    ))
  }
  # Build new single-experiment MAE then merge
  new_mae <- build_mae(data_file, metadata_file, experiment_name,
                        data_type, assay_name, start_level, tax_sep)
  new_empt       <- new_mae[[experiment_name]]
  sample_names   <- colnames(new_empt)

  # Update sampleMap
  existing_map <- as.data.frame(mae@sampleMap)
  new_map <- data.frame(
    assay   = factor(experiment_name),
    primary = sample_names,
    colname = sample_names,
    stringsAsFactors = FALSE
  )

  # Merge colData
  existing_cd <- as.data.frame(MultiAssayExperiment::colData(mae))
  new_cd      <- as.data.frame(MultiAssayExperiment::colData(new_mae))
  all_primary <- union(rownames(existing_cd), rownames(new_cd))
  merged_cd   <- data.frame(row.names = all_primary)
  for (col in union(names(existing_cd), names(new_cd))) {
    v <- rep(NA_character_, length(all_primary))
    if (col %in% names(existing_cd)) v[match(rownames(existing_cd), all_primary)] <- as.character(existing_cd[[col]])
    if (col %in% names(new_cd))      v[match(rownames(new_cd),      all_primary)] <- as.character(new_cd[[col]])
    merged_cd[[col]] <- v
  }

  experiments <- as.list(MultiAssayExperiment::experiments(mae))
  experiments[[experiment_name]] <- new_empt
  sample_map <- rbind(existing_map, new_map)
  sample_map$assay <- factor(as.character(sample_map$assay), levels = names(experiments))

  MultiAssayExperiment::MultiAssayExperiment(
    experiments = experiments,
    colData = S4Vectors::DataFrame(merged_cd),
    sampleMap = S4Vectors::DataFrame(sample_map)
  )
}
