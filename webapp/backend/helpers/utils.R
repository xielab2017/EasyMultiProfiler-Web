# General utility helpers

## Null-coalescing helper (re-declared by each workflow file for safety;
## having it here too means utils.R-only consumers don't depend on load
## order).
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
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
    return(list(success   = TRUE,
                 plot      = img$plot,
                 matched   = img$matched %||% character(0),
                 missing   = img$missing %||% character(0),
                 n_used    = img$n_used %||% length(img$matched %||% character(0)),
                 n_missing = img$n_missing %||% length(img$missing %||% character(0))))
  }
  list(success = TRUE, plot = img)
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
restore_feature_rownames <- function(obj) {
  if (!inherits(obj, c("SummarizedExperiment", "EMPT"))) return(obj)
  ad <- SummarizedExperiment::assays(obj)[[1]]
  if (is.null(ad) || !nrow(ad)) return(obj)
  ids <- rownames(ad)
  if (!length(ids) || !all(grepl("^feature_?\\d+$", ids, ignore.case = TRUE))) return(obj)

  rd <- as.data.frame(SummarizedExperiment::rowData(obj), stringsAsFactors = FALSE)
  if (!nrow(rd)) return(obj)

  alias_cols <- unique(c(
    ".FEATURE", ".feature", "Name", "name", "SYMBOL", "symbol",
    "gene_symbol", "Gene", "gene"
  ))
  alias_cols <- intersect(alias_cols, names(rd))
  labels <- NULL
  for (col in alias_cols) {
    vals <- trimws(as.character(rd[[col]]))
    vals[!nzchar(vals)] <- NA_character_
    ok <- !is.na(vals) & !grepl("^feature_?\\d+$", vals, ignore.case = TRUE)
    if (sum(ok) >= 0.5 * length(ids)) {
      labels <- vals
      break
    }
  }
  if (is.null(labels)) return(obj)

  fill <- is.na(labels) | !nzchar(labels)
  labels[fill] <- ids[fill]
  new_rn <- make.unique(labels, sep = "_")

  rownames(ad) <- new_rn
  if ("feature" %in% names(rd)) rd$feature <- new_rn

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
      res$status <- 500
      list(success = FALSE, error = conditionMessage(e))
    }
  )
  dt <- as.numeric(difftime(Sys.time(), t0, units = "secs")) * 1000
  if (is.list(result)) {
    result$backend_ms <- round(dt, 1)
    result$server_ts  <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z")
  }
  result
}
