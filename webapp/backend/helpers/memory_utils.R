# memory_utils.R - EMP Web v9.1.0 Round 2: memory helpers.
#
# Base R + Matrix only (Matrix is already a package dependency). The
# helpers support the memory strategy documented in
# docs/PERFORMANCE_AND_MEMORY.md:
#   - inspect what the API R session is holding (emp_memory_info)
#   - estimate matrix density and switch very sparse matrices to a
#     Matrix sparse representation without changing any value
#     (emp_matrix_density / emp_maybe_sparse)
#   - plan row chunks that fit a memory budget (emp_chunk_plan)
#   - explicitly release large intermediates (emp_release)
# Nothing here silently alters analysis data: conversion to sparse only
# changes the storage class, never the values, and release only removes
# objects the caller names.

.emp_used_mb <- function() {
  tryCatch({
    g <- suppressWarnings(gc())
    mb_cols <- which(colnames(g) == "(Mb)")
    if (length(mb_cols) == 0 || nrow(g) == 0) return(NA_real_)
    sum(g[, mb_cols[1]], na.rm = TRUE)
  }, error = function(e) NA_real_)
}

#' Memory snapshot of an environment (default: the global env).
#'
#' @return list(gc_used_mb, top_objects, r_version). `top_objects` is a
#'   data.frame(name, size_mb) with the (up to) 10 largest objects.
emp_memory_info <- function(env = .GlobalEnv) {
  top_objects <- tryCatch({
    nms <- ls(envir = env, all.names = TRUE)
    if (length(nms) == 0) {
      data.frame(name = character(0), size_mb = numeric(0),
                 stringsAsFactors = FALSE)
    } else {
      sizes <- vapply(nms, function(nm) {
        obj <- tryCatch(get(nm, envir = env), error = function(e) NULL)
        if (is.null(obj)) return(NA_real_)
        as.numeric(object.size(obj)) / (1024^2)
      }, numeric(1))
      df <- data.frame(name = nms, size_mb = sizes,
                       stringsAsFactors = FALSE)
      df <- df[is.finite(df$size_mb), , drop = FALSE]
      df <- df[order(df$size_mb, decreasing = TRUE), , drop = FALSE]
      utils::head(df, 10)
    }
  }, error = function(e) {
    data.frame(name = character(0), size_mb = numeric(0),
               stringsAsFactors = FALSE)
  })
  rownames(top_objects) <- NULL
  list(
    gc_used_mb = .emp_used_mb(),
    top_objects = top_objects,
    r_version = as.character(getRversion())
  )
}

#' Storage density of a matrix: the proportion of entries that carry a
#' stored value, i.e. non-zero entries plus NA entries (an NA still
#' occupies storage in a dense matrix and becomes an explicit entry in a
#' sparse one). This is a storage measure only; missingness itself is
#' reported by emp_qc_rigor(), not here.
emp_matrix_density <- function(mat) {
  if (is.data.frame(mat)) mat <- as.matrix(mat)
  if (!is.matrix(mat) || length(mat) == 0) return(NA_real_)
  if (inherits(mat, "sparseMatrix")) {
    return(length(mat@x) / (nrow(mat) * ncol(mat)))
  }
  stored <- sum(mat != 0 | is.na(mat))
  stored / length(mat)
}

#' Convert a very sparse dense matrix to a Matrix sparse matrix.
#'
#' @param threshold Convert when density is strictly below this value.
#' @return The sparse matrix (with attributes `sparse_converted = TRUE`
#'   and a human-readable `note`), or the original object unchanged.
#'   Values are never modified.
emp_maybe_sparse <- function(mat, threshold = 0.30, quiet = FALSE) {
  original <- mat
  if (is.data.frame(mat)) mat <- as.matrix(mat)
  if (!is.matrix(mat) || !is.numeric(mat)) return(original)
  density <- emp_matrix_density(mat)
  if (!is.finite(density) || density >= threshold) return(original)
  if (!requireNamespace("Matrix", quietly = TRUE)) {
    if (!quiet) message("emp_maybe_sparse: Matrix package not available; keeping dense matrix.")
    return(original)
  }
  out <- tryCatch(Matrix::Matrix(mat, sparse = TRUE),
                  error = function(e) NULL)
  if (is.null(out)) return(original)
  attr(out, "sparse_converted") <- TRUE
  attr(out, "note") <- sprintf(
    "Converted to sparse Matrix (density %.3f < threshold %.3f); values unchanged.",
    density, threshold
  )
  if (!quiet) message(attr(out, "note"))
  out
}

#' Plan row-chunk sizes so each chunk fits a target memory budget.
#'
#' @param n Number of rows to split.
#' @param target_mb Per-chunk memory budget in megabytes.
#' @param row_bytes_estimate Estimated bytes per row.
#' @return Integer vector of chunk sizes; sum() equals n (integer(0)
#'   when n <= 0).
emp_chunk_plan <- function(n, target_mb = 512, row_bytes_estimate = 8192) {
  n <- suppressWarnings(as.integer(n))
  if (length(n) == 0 || is.na(n) || n <= 0) return(integer(0))
  budget_bytes <- max(1, as.numeric(target_mb)) * 1024 * 1024
  per_row <- max(1, as.numeric(row_bytes_estimate))
  rows_per_chunk <- max(1L, as.integer(floor(budget_bytes / per_row)))
  full <- rep(rows_per_chunk, n %/% rows_per_chunk)
  rest <- n %% rows_per_chunk
  if (rest > 0) full <- c(full, as.integer(rest))
  as.integer(full)
}

#' Remove explicitly named objects from an environment, then gc.
#'
#' Accepts character names or bare symbols: emp_release(x, "y").
#' @return list(removed, freed_mb_estimate) — the freed estimate is the
#'   gc "used" difference before/after and is approximate by nature.
emp_release <- function(..., env = .GlobalEnv) {
  dots <- as.list(substitute(...()))
  nms <- vapply(dots, function(e) {
    if (is.character(e)) as.character(e[[1]]) else deparse(e)
  }, character(1))
  nms <- unique(nms[nzchar(nms)])
  before <- .emp_used_mb()
  present <- nms[vapply(nms, exists, logical(1), envir = env, inherits = FALSE)]
  if (length(present)) {
    rm(list = present, envir = env)
  }
  invisible(suppressWarnings(gc()))
  after <- .emp_used_mb()
  freed <- if (is.finite(before) && is.finite(after)) max(0, before - after) else NA_real_
  list(removed = present, freed_mb_estimate = freed)
}
