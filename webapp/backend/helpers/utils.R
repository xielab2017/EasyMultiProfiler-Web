# General utility helpers

## Null-coalescing helper (re-declared by each workflow file for safety;
## having it here too means utils.R-only consumers don't depend on load
## order).
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
}

## Run `expr_fn` with a fixed seed WITHOUT leaving that seed behind on the global RNG stream.
## Analyses that need reproducible randomness (k-means starts, random-forest splits) used to call
## set.seed() directly in the API process, which also made every later draw in that process
## deterministic - including the sample()-based session identifiers. Save the stream, seed, run,
## restore.
.emp_with_local_seed <- function(seed, expr_fn) {
  had_seed <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  old_seed <- if (had_seed) get(".Random.seed", envir = globalenv(), inherits = FALSE) else NULL
  on.exit({
    if (had_seed) {
      assign(".Random.seed", old_seed, envir = globalenv())
    } else if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
      rm(".Random.seed", envir = globalenv())
    }
  }, add = TRUE)
  set.seed(as.integer(seed))
  expr_fn()
}

## Cryptographically strong random identifier (session, project, job ids). sample() draws from R's
## global RNG, which is seedable by any analysis running in the same process.
.emp_random_id <- function(n = 24L, alphabet = c(letters, LETTERS, 0:9)) {
  alphabet <- as.character(alphabet)
  if (requireNamespace("openssl", quietly = TRUE)) {
    bytes <- as.integer(openssl::rand_bytes(n))
    return(paste0(alphabet[(bytes %% length(alphabet)) + 1L], collapse = ""))
  }
  con <- tryCatch(file("/dev/urandom", "rb"), error = function(e) NULL, warning = function(w) NULL)
  if (!is.null(con)) {
    on.exit(close(con), add = TRUE)
    bytes <- as.integer(readBin(con, what = "raw", n = n))
    if (length(bytes) == n) {
      return(paste0(alphabet[(bytes %% length(alphabet)) + 1L], collapse = ""))
    }
  }
  paste0(sample(alphabet, n, replace = TRUE), collapse = "")
}

## Is caller-supplied R execution enabled? One parser, one default, used by every gate.
##
## POST /api/user_r/run and /api/exec/user_r evaluate caller-supplied R in the API process with
## access to globalenv(). Three sites used to read this variable with `unset = "true"`, so the
## feature was ON by default: the bundled launchers and docker-compose all set it to false
## explicitly, but starting the API any other way (`Rscript run_api.R`, a custom unit file) served
## arbitrary remote code execution with no opt-in — and the startup guard in auth.R read the same
## variable with a different parser and a different default, so it could not catch that case.
## Default is now off, and `1/true/yes/on` (any case) are the accepted opt-ins everywhere.
emp_user_r_enabled <- function() {
  tolower(trimws(Sys.getenv("EMP_ENABLE_USER_R", unset = "false"))) %in% c("1", "true", "yes", "on")
}

## Error response for the file-serving endpoints (zip / pdf / rds / csv / png downloads).
##
## Those routes sit outside safe_api() and used to answer failures with `res$status <- 500` plus a
## plain character string, while the declared serializer was application/zip, application/pdf or
## application/octet-stream - so the client got a body whose content type contradicted its content
## and no parseable error. Return a JSON error object as raw bytes with the header corrected, the
## way /api/bundles already does for its 404.
emp_binary_error <- function(res, e, status = 500L) {
  res$status <- as.integer(status)
  try(res$setHeader("Content-Type", "application/json"), silent = TRUE)
  msg <- paste(conditionMessage(e), collapse = " ")
  body <- tryCatch(
    as.character(jsonlite::toJSON(list(success = FALSE, error = msg), auto_unbox = TRUE)),
    error = function(e2) '{"success":false,"error":"unserialisable error"}'
  )
  charToRaw(body)
}

## Canonical taxonomic ranks, root first, as the package spells them. EMP's own rowData column is
## "Kindom" (sic), so that spelling is authoritative for lookups; "Kingdom" is accepted as an input
## alias and normalised here. Four different rank vocabularies used to coexist across utils.R,
## viz.R, workflow_microbiome_16s.R and import.R, which is how a kingdom-rooted table could be
## imported with a rank name nothing downstream recognised.
EMP_TAX_RANKS <- c("Domain", "Kindom", "Phylum", "Class", "Order", "Family", "Genus", "Species",
                   "Strain")

.emp_normalize_tax_rank <- function(rank) {
  value <- trimws(as.character(rank %||% ""))
  if (!length(value) || !nzchar(value[1])) return(NULL)
  value <- value[1]
  aliases <- c(kingdom = "Kindom", kindom = "Kindom", domain = "Domain", superkingdom = "Domain",
               phylum = "Phylum", class = "Class", order = "Order", family = "Family",
               genus = "Genus", species = "Species", strain = "Strain")
  hit <- aliases[[tolower(value)]]
  if (!is.null(hit)) return(hit)
  exact <- EMP_TAX_RANKS[tolower(EMP_TAX_RANKS) == tolower(value)]
  if (length(exact)) return(exact[[1]])
  value
}

## Impute missing values in the primary assay.
##
## EMP_impute() has no `method` formal - its formals are obj, experiment, coldata, assay, rowdata,
## .formula, pmm.k, num.trees, seed, verbose, use_cached, action - so the previous call
## `EMP_impute(method = <ui value>)` had the argument swallowed by `...`: all four interface
## options (knn/zero/min/mean) ran the same mice/ranger imputation while the response echoed the
## method the user had picked. The deterministic imputers are implemented here, the model-based
## one is delegated to the package, and the executed method is returned so the endpoint can report
## it truthfully.
##
## Returns list(empt = <EMPT>, executed = <character>, n_imputed = <integer>).
.emp_impute_assay <- function(empt, method = "emp") {
  meth <- tolower(trimws(as.character(method %||% "emp")))
  if (meth %in% c("", "emp", "knn", "mice", "rf", "ranger", "model")) {
    out <- empt |> EasyMultiProfiler::EMP_impute()
    return(list(empt = out, executed = "EMP_impute (mice/ranger model-based)", n_imputed = NA_integer_))
  }

  # Validate the method BEFORE the "nothing to impute" shortcut, otherwise an unsupported method
  # is silently accepted on any complete matrix and only rejected when a gap happens to exist.
  supported <- c("zero", "min", "halfmin", "mean", "median")
  if (!meth %in% supported) {
    stop("Unsupported imputation method '", meth,
         "'. Supported: emp (model-based), ", paste(supported, collapse = ", "), ".", call. = FALSE)
  }
  mat <- as.matrix(SummarizedExperiment::assay(empt, 1L))
  n_missing <- sum(!is.finite(mat))
  if (n_missing == 0L) {
    return(list(empt = empt, executed = meth, n_imputed = 0L))
  }
  fill <- switch(
    meth,
    "zero"    = function(x) rep(0, length(x)),
    "min"     = function(x) rep(min(x[is.finite(x)], na.rm = TRUE), length(x)),
    "halfmin" = function(x) rep(min(x[is.finite(x)], na.rm = TRUE) / 2, length(x)),
    "mean"    = function(x) rep(mean(x[is.finite(x)], na.rm = TRUE), length(x)),
    "median"  = function(x) rep(stats::median(x[is.finite(x)], na.rm = TRUE), length(x)),
    stop("Unsupported imputation method '", meth,
         "'. Supported: emp (model-based), zero, min, halfmin, mean, median.", call. = FALSE)
  )
  for (i in seq_len(nrow(mat))) {
    row <- mat[i, ]
    bad <- !is.finite(row)
    if (!any(bad)) next
    if (all(bad)) {
      row[bad] <- 0
    } else {
      row[bad] <- fill(row)[bad]
    }
    mat[i, ] <- row
  }
  SummarizedExperiment::assay(empt, 1L) <- mat
  list(empt = empt, executed = meth, n_imputed = as.integer(n_missing))
}

## Parse a caller-provided gene/feature list.  Accepts: JSON array,
## already-split character vector, or a newline/comma/semicolon/tab/
## whitespace-delimited blob that the frontend may paste verbatim.
## Returns a deduplicated character vector (possibly length 0).
.parse_feature_list <- function(x) {
  if (is.null(x)) return(character(0))
  if (is.list(x))   x <- unlist(x, use.names = FALSE)
  if (is.factor(x)) x <- as.character(x)
  if (is.character(x) && length(x) == 1) {
    x <- strsplit(x, "[,;\\t\\r\\n\\s]+", perl = TRUE)[[1]]
  }
  x <- trimws(as.character(x))
  x <- x[nzchar(x)]
  unique(x)
}

## Normalise the return value of make_heatmap() into a plumber-friendly
## shape.  When `make_heatmap` ran in top-variance mode it returns a raw
## base64 string; in custom-features mode it returns a list with extra
## diagnostics (matched / missing).  The frontend always looks for the
## `plot` key, and optionally `matched` / `missing` when present.
.heatmap_response <- function(img) {
  if (is.list(img) && !is.null(img$plot)) {
    return(c(list(success   = TRUE,
                  plot      = img$plot,
                  matched   = img$matched %||% character(0),
                  missing   = img$missing %||% character(0),
                  n_used    = img$n_used %||% length(img$matched %||% character(0)),
                  n_missing = img$n_missing %||% length(img$missing %||% character(0))),
             viz_pdf_meta(img$pdf %||% NULL)))
  }
  if (is.list(img) && !is.null(img$pdf_available)) {
    return(c(list(success = TRUE), img))
  }
  list(success = TRUE, plot = img)
}

# Session-scoped path for a ggplot / pheatmap vector PDF artefact.
viz_session_pdf_path <- function(session_id, experiment, kind) {
  pdf_dir <- file.path(session_path(session_id), "plots")
  dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
  file.path(pdf_dir, paste0(kind, "_", make.names(experiment), ".pdf"))
}

# Best-effort vector PDF write; returns the file path or NULL.
viz_save_session_pdf <- function(p, session_id, experiment, kind,
                                 width = 9, height = 6) {
  if (is.null(p) || is.null(session_id) || !nzchar(session_id) ||
      is.null(experiment) || !nzchar(experiment) || is.null(kind) || !nzchar(kind)) {
    return(NULL)
  }
  path <- viz_session_pdf_path(session_id, experiment, kind)
  tryCatch(save_plot_pdf(p, path, width = width, height = height),
           error = function(e) NULL)
}

# PNG preview + editable vector PDF for web download buttons.
viz_emit_ggplot <- function(p, session_id, experiment, kind, width, height) {
  b64 <- plot_to_base64(p, width = width, height = height)
  pdf <- viz_save_session_pdf(p, session_id, experiment, kind, width, height)
  c(list(plot = b64, pdf = pdf), viz_pdf_meta(pdf))
}

viz_plot_b64 <- function(x) {
  if (is.list(x) && !is.null(x$plot)) x$plot else x
}

viz_pdf_meta <- function(pdf) {
  list(
    pdf_available = !is.null(pdf),
    pdf_name = if (!is.null(pdf)) basename(pdf) else ""
  )
}

.viz_api_plot_response <- function(out) {
  if (is.list(out) && !is.null(out$plot)) c(list(success = TRUE), out)
  else list(success = TRUE, plot = out)
}

# Detect CSV/TSV separator from first few lines
detect_sep <- function(filepath) {
  lines <- readLines(filepath, n = 3, warn = FALSE)
  if (length(lines) == 0) return(",")
  if (grepl("\t", lines[1])) return("\t")
  if (grepl(",", lines[1]))  return(",")
  if (grepl(";", lines[1]))  return(";")
  "\t"
}

# Read a tabular file auto-detecting sep
read_table_auto <- function(filepath, nrows = -1) {
  if (is.null(filepath) || !nzchar(filepath)) {
    stop("Uploaded data file path is empty.")
  }
  if (!file.exists(filepath)) {
    stop(sprintf("Uploaded data file not found on server: %s", filepath))
  }
  sep <- detect_sep(filepath)
  tryCatch(
    read.table(filepath, header = TRUE, sep = sep,
               stringsAsFactors = FALSE, check.names = FALSE,
               comment.char = "", nrows = if (nrows > 0) nrows else -1),
    error = function(e) {
      stop(sprintf("Failed to read uploaded table (%s): %s", basename(filepath), conditionMessage(e)))
    }
  )
}

# Detect if first column is a numeric index
is_index_col <- function(col_vals) {
  if (is.numeric(col_vals)) {
    return(all(diff(col_vals) == 1, na.rm = TRUE))
  }
  as_num <- suppressWarnings(as.numeric(as.character(col_vals)))
  if (all(!is.na(as_num))) {
    return(all(diff(as_num) == 1, na.rm = TRUE))
  }
  FALSE
}

# Remove index column and rename first real column to 'feature'
clean_feature_col <- function(df) {
  name1 <- tolower(names(df)[1])
  is_idx <- name1 %in% c("index","x","row","id","rowid","row.id","rownames") ||
            is_index_col(df[[1]])
  if (is_idx && ncol(df) > 1) df <- df[, -1, drop = FALSE]
  names(df)[1] <- "feature"
  df
}

# When EMP import detects duplicate feature IDs it stores the original labels in
# `.feature` / `.FEATURE` and assigns generic rownames (feature1, feature_1, …).
# Restore human-readable gene / feature symbols as assay rownames when possible.
.is_generic_feature_ids <- function(ids) {
  if (is.null(ids) || !length(ids)) return(FALSE)
  all(grepl("^feature_?\\d+$", as.character(ids), ignore.case = TRUE))
}

.rebuild_empt_with_rownames <- function(obj, ad, rd, new_rn) {
  rownames(ad) <- new_rn
  if ("feature" %in% names(rd)) rd$feature <- new_rn
  rownames(rd) <- new_rn

  assay_name <- names(SummarizedExperiment::assays(obj))[1]
  if (is.null(assay_name) || !nzchar(assay_name)) assay_name <- "counts"
  cd <- SummarizedExperiment::colData(obj)
  rebuilt <- SummarizedExperiment::SummarizedExperiment(
    assays = setNames(list(ad), assay_name),
    rowData = S4Vectors::DataFrame(rd, row.names = new_rn),
    colData = cd
  )
  if (!inherits(obj, "EMPT")) return(rebuilt)

  empt_slots <- c(
    "deposit", "deposit2", "plot_deposit", "deposit_append", "deposit_info",
    "experiment", "assay_name", "estimate_group", "estimate_group_info",
    "message_info", "formula", "method", "algorithm", "history", "palette",
    "plot_category", "plot_specific", "plot_info", "info"
  )
  for (slot_name in empt_slots) {
    if (methods::.hasSlot(obj, slot_name)) {
      methods::slot(rebuilt, slot_name) <- methods::slot(obj, slot_name)
    }
  }
  class(rebuilt) <- class(obj)
  rebuilt
}

restore_feature_rownames <- function(obj, original_labels = NULL) {
  if (!inherits(obj, c("SummarizedExperiment", "EMPT"))) return(obj)
  ad <- SummarizedExperiment::assays(obj)[[1]]
  if (is.null(ad) || !nrow(ad)) return(obj)
  ids <- rownames(ad)
  if (!.is_generic_feature_ids(ids)) return(obj)

  rd <- as.data.frame(SummarizedExperiment::rowData(obj), stringsAsFactors = FALSE)
  labels <- NULL

  if (!is.null(original_labels)) {
    orig <- trimws(as.character(original_labels))
    if (length(orig) == length(ids)) labels <- orig
  }

  if (is.null(labels) && nrow(rd)) {
    stored_cols <- c(
      "original_taxonomy", "taxonomy_label", ".original_feature",
      ".FEATURE", ".feature", "Name", "name", "SYMBOL", "symbol",
      "gene_symbol", "Gene", "gene"
    )
    for (col in intersect(stored_cols, names(rd))) {
      vals <- trimws(as.character(rd[[col]]))
      vals[!nzchar(vals)] <- NA_character_
      ok <- !is.na(vals) & !grepl("^feature_?\\d+$", vals, ignore.case = TRUE)
      if (sum(ok) >= 0.5 * length(ids)) {
        labels <- vals
        break
      }
    }
  }
  if (is.null(labels)) return(obj)

  fill <- is.na(labels) | !nzchar(labels)
  labels[fill] <- ids[fill]
  if (is.null(original_labels) && !"original_taxonomy" %in% names(rd)) {
    rd$original_taxonomy <- labels
  } else if (!is.null(original_labels) && !"original_taxonomy" %in% names(rd)) {
    rd$original_taxonomy <- trimws(as.character(original_labels))
  }
  new_rn <- make.unique(labels, sep = "_")
  .rebuild_empt_with_rownames(obj, ad, rd, new_rn)
}

# Force all columns after feature to numeric; remove columns that can't convert
enforce_numeric_samples <- function(df) {
  if (ncol(df) <= 1) return(df)
  keep <- c(1L)
  for (i in seq(2, ncol(df))) {
    col <- df[[i]]
    if (!is.numeric(col)) {
      converted <- suppressWarnings(as.numeric(as.character(col)))
      na_ratio  <- sum(is.na(converted)) / length(converted)
      if (na_ratio <= 0.2) {
        converted[is.na(converted)] <- 0
        df[[i]] <- converted
        keep <- c(keep, i)
      }
    } else {
      keep <- c(keep, i)
    }
  }
  df[, keep, drop = FALSE]
}

# Detect taxonomy separator and level from feature strings
detect_taxonomy <- function(feature_values) {
  sep <- if (any(grepl(";",  feature_values))) ";"  else
         if (any(grepl("\\|",feature_values))) "|"  else ";"
  n_levels <- length(strsplit(feature_values[1], sep, fixed = TRUE)[[1]])
  level_map <- c("Domain","Kindom","Phylum","Class","Order","Family","Genus","Species","Strain")
  level <- if (n_levels <= length(level_map)) level_map[n_levels] else "Species"
  list(sep = sep, level = level)
}

# Render a ggplot to base64-encoded PNG string at publication DPI (300).
plot_to_base64 <- function(p, width = 9, height = 6, dpi = 300) {
  tmp <- tempfile(fileext = ".png")
  on.exit(if (file.exists(tmp)) file.remove(tmp))
  # Use device + print so S3/S4 plot wrappers can dispatch their own plot methods.
  # ragg::agg_png yields better text rendering when available; fall back to grDevices::png.
  use_ragg <- requireNamespace("ragg", quietly = TRUE)
  if (use_ragg) {
    ragg::agg_png(
      filename = tmp,
      width = width,
      height = height,
      units = "in",
      res = dpi,
      background = "white",
      scaling = 1
    )
  } else {
    grDevices::png(
      filename = tmp,
      width = width,
      height = height,
      units = "in",
      res = dpi,
      type = if (.Platform$OS.type == "windows") "windows" else "cairo",
      bg = "white"
    )
  }
  tryCatch(
    print(p),
    error = function(e) {
      grDevices::dev.off()
      stop("Could not render plot object: ", conditionMessage(e))
    }
  )
  grDevices::dev.off()
  base64enc::base64encode(tmp)
}

# Render a ggplot / pheatmap object (or anything with a plot method) to a PDF
# file at the requested size.  Returns the file path on success.
save_plot_pdf <- function(p, path, width = 9, height = 6) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(file = path, width = width, height = height,
                  useDingbats = FALSE, onefile = FALSE)
  tryCatch(
    {
      if (inherits(p, "pheatmap")) grid::grid.draw(p$gtable) else print(p)
    },
    error = function(e) {
      grDevices::dev.off()
      stop("PDF render failed: ", conditionMessage(e))
    }
  )
  grDevices::dev.off()
  path
}

# Render the same plot to both an on-disk PDF (for downloads) and a base64
# PNG (for web preview).  Returns list(pdf_path, png_b64).
render_plot_artefacts <- function(p, pdf_path, width = 9, height = 6, dpi = 300) {
  save_plot_pdf(p, pdf_path, width = width, height = height)
  list(pdf_path = pdf_path,
       png_b64  = plot_to_base64(p, width = width, height = height, dpi = dpi))
}

# Write a data.frame to an .xlsx workbook (single or multiple sheets).
save_df_xlsx <- function(x, path, sheet = "data") {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    # Fallback: write csv with same basename so the caller still sees a file.
    alt <- sub("\\.xlsx$", ".csv", path)
    utils::write.csv(x, alt, row.names = FALSE)
    return(alt)
  }
  if (is.data.frame(x)) {
    wb <- openxlsx::createWorkbook()
    openxlsx::addWorksheet(wb, sheet)
    openxlsx::writeData(wb, sheet, x)
    openxlsx::freezePane(wb, sheet, firstRow = TRUE)
    openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  } else if (is.list(x)) {
    wb <- openxlsx::createWorkbook()
    for (nm in names(x)) {
      openxlsx::addWorksheet(wb, nm)
      openxlsx::writeData(wb, nm, x[[nm]])
      openxlsx::freezePane(wb, nm, firstRow = TRUE)
    }
    openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  } else {
    stop("save_df_xlsx: expected data.frame or named list of data.frames.")
  }
  path
}

# zip a directory recursively, writing the archive to zip_path.
# Uses `zip::zip()` when available (pure-R, cross-platform) else utils::zip.
# Preserves the directory structure (plots/, tables/, summary.txt) so users
# see a clean, browsable archive.
zip_dir <- function(dir_path, zip_path) {
  dir.create(dirname(zip_path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(zip_path)) unlink(zip_path)
  entries <- list.files(dir_path, recursive = FALSE, full.names = FALSE,
                         all.files = FALSE, include.dirs = TRUE)
  if (!length(entries)) stop("zip_dir: directory is empty – nothing to archive.")
  oldwd <- getwd(); on.exit(setwd(oldwd), add = TRUE)
  setwd(dir_path)
  if (requireNamespace("zip", quietly = TRUE)) {
    zip::zipr(zipfile = zip_path, files = entries, recurse = TRUE)
  } else {
    utils::zip(zipfile = zip_path, files = entries)
  }
  zip_path
}

# Safely convert data.frame columns to character for JSON serialisation
df_to_list <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(list())
  df[] <- lapply(df, function(x) {
    if (is.factor(x)) as.character(x) else x
  })
  as.list(df)
}

# First `n` assay rows as a list of named lists → JSON array of row objects
# (stable for Plumber; avoids embedding jsonlite::toJSON() strings).
emp_prepare_preview_rows <- function(empt, n = 30L) {
  ad <- SummarizedExperiment::assays(empt)[[1]]
  if (is.null(ad)) return(list())
  nr <- NROW(ad)
  if (nr < 1L) return(list())
  n_take <- suppressWarnings(as.integer(n[[1]]))
  if (length(n_take) != 1L || is.na(n_take) || n_take < 1L) n_take <- 30L
  idx <- seq_len(min(n_take, nr))
  cn <- colnames(ad)
  if (is.null(cn) || length(cn) != ncol(ad)) cn <- paste0("col", seq_len(ncol(ad)))
  rn <- rownames(ad)
  if (is.null(rn) || length(rn) != nr) rn <- paste0("row_", seq_len(nr))
  feats <- rn[idx]
  subm <- tryCatch(as.matrix(ad[idx, , drop = FALSE]), error = function(e) NULL)
  if (is.null(subm)) return(list())
  out <- vector("list", length(idx))
  for (i in seq_along(idx)) {
    rawv <- subm[i, , drop = TRUE]
    lst <- as.list(rawv)
    if (length(lst) != length(cn)) lst <- as.list(rep(NA_real_, length(cn)))
    names(lst) <- cn
    out[[i]] <- c(list(feature = feats[[i]]), lst)
  }
  out
}

# Serialise a data.frame to a CSV string for plumber contentType("text/csv")
# routes. Using write.csv() without a connection writes to stdout and returns
# NULL, which yields an empty download body; capture.output fixes that.
.csv_response <- function(df) {
  df <- tryCatch(as.data.frame(df), error = function(e) df)
  paste0(
    paste(utils::capture.output(utils::write.csv(df, row.names = FALSE)), collapse = "\n"),
    "\n"
  )
}

# Wrap a block so plumber returns a tidy error JSON on failure
safe_api <- function(expr, res) {
  t0 <- Sys.time()
  result <- tryCatch(
    expr,
    error = function(e) {
      message <- conditionMessage(e)
      if (!is.null(res)) {
        lower <- tolower(message)
        res$status <- if (grepl("access denied|ownership|allowed root|outside allowed|not allowed|invalid session_id|invalid project_id|invalid job_id", lower)) 403 else if (
          grepl("still running|wait before sync|busy or incomplete|conflict|homework sync blocked", lower)
        ) 409 else if (
          grepl("validation|metadata|sample|group|invalid|required|unsupported", lower)
        ) 400 else 500
      }
      list(success = FALSE, error = message)
    }
  )
  dt <- as.numeric(difftime(Sys.time(), t0, units = "secs")) * 1000
  if (is.list(result)) {
    result$backend_ms <- round(dt, 1)
    result$server_ts  <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z")
  }
  result
}
