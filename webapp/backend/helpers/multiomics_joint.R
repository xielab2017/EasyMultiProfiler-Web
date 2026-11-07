# multiomics_joint.R - EMP Web v9.1.0 analysis upgrade C (base R only).
#
# Lightweight cross-omics helpers that complement the existing workflow
# modules: a Spearman cross-omics correlation network with BH FDR, a
# simple joint factor decomposition over matched samples, and a
# peak-to-gene link table for ChIP-RNA style integration. All functions
# match samples by column names and never silently drop data: unmatched
# samples are simply not used, and the matched set is reported.

#' Cross-omics Spearman correlation network between two matrices.
#'
#' @param mat_a,mat_b Numeric matrices, features in rows, samples in
#'   columns. Samples are matched by the intersection of column names.
#' @param fdr BH-adjusted p-value cutoff for kept edges.
#' @param cor_min Minimum absolute Spearman correlation for kept edges.
#' @return data.frame(from, to, cor, p_adj), one row per kept edge.
#'   P-values use the t approximation with n = matched samples; this is
#'   documented behaviour, not an exact permutation test.
emp_cross_omics_network <- function(mat_a, mat_b, fdr = 0.05,
                                    cor_min = 0.5) {
  empty <- data.frame(from = character(0), to = character(0),
                      cor = numeric(0), p_adj = numeric(0),
                      stringsAsFactors = FALSE)
  if (is.data.frame(mat_a)) mat_a <- as.matrix(mat_a)
  if (is.data.frame(mat_b)) mat_b <- as.matrix(mat_b)
  if (is.null(colnames(mat_a)) || is.null(colnames(mat_b))) return(empty)
  common <- intersect(colnames(mat_a), colnames(mat_b))
  if (length(common) < 4) return(empty)
  a <- mat_a[, common, drop = FALSE]
  b <- mat_b[, common, drop = FALSE]
  n <- length(common)

  cors <- tryCatch(
    stats::cor(t(a), t(b), method = "spearman",
               use = "pairwise.complete.obs"),
    error = function(e) NULL
  )
  if (is.null(cors)) return(empty)

  r <- as.numeric(cors)
  t_stat <- r * sqrt((n - 2) / pmax(1e-12, 1 - r^2))
  p <- 2 * stats::pt(-abs(t_stat), df = n - 2)
  p_adj <- stats::p.adjust(p, method = "BH")

  idx <- which(!is.na(r) & abs(r) >= cor_min & !is.na(p_adj) & p_adj <= fdr)
  if (length(idx) == 0) return(empty)
  nr <- nrow(cors)
  from_i <- ((idx - 1) %% nr) + 1
  to_i <- ((idx - 1) %/% nr) + 1
  data.frame(
    from = rownames(cors)[from_i],
    to = colnames(cors)[to_i],
    cor = r[idx],
    p_adj = p_adj[idx],
    stringsAsFactors = FALSE
  )
}

#' Simple joint factor decomposition across omics blocks (SVD).
#'
#' Each block is row-scaled (features z-scored over matched samples),
#' features are row-bound, and an SVD over samples x features yields
#' shared factor scores. Constant features contribute zeros after
#' scaling instead of NaNs.
#'
#' @param blocks Named list of numeric matrices (features x samples).
#' @param n_factors Number of joint factors to return.
#' @return list(scores, loadings, variance_explained, samples).
emp_joint_factor <- function(blocks, n_factors = 2) {
  if (!is.list(blocks) || length(blocks) == 0) {
    stop("emp_joint_factor: `blocks` must be a non-empty list of matrices")
  }
  mats <- lapply(blocks, function(m) {
    if (is.data.frame(m)) m <- as.matrix(m)
    m
  })
  common <- Reduce(intersect, lapply(mats, colnames))
  if (is.null(common) || length(common) < 3) {
    stop("emp_joint_factor: fewer than 3 matched samples across blocks")
  }
  scaled <- lapply(mats, function(m) {
    m <- m[, common, drop = FALSE]
    sds <- apply(m, 1, function(x) stats::sd(x, na.rm = TRUE))
    means <- rowMeans(m, na.rm = TRUE)
    z <- sweep(m, 1, means, "-")
    ok <- !is.na(sds) & sds > 0
    z[ok, ] <- sweep(z[ok, , drop = FALSE], 1, sds[ok], "/")
    z[!ok, ] <- 0
    z[is.na(z)] <- 0
    z
  })
  combined <- do.call(rbind, scaled)
  x <- t(combined)
  sv <- svd(x)
  k <- max(1L, min(as.integer(n_factors), length(sv$d), ncol(x), nrow(x)))
  scores <- sweep(sv$u[, seq_len(k), drop = FALSE], 2, sv$d[seq_len(k)], "*")
  loadings <- sv$v[, seq_len(k), drop = FALSE]
  rownames(scores) <- common
  colnames(scores) <- paste0("F", seq_len(k))
  rownames(loadings) <- rownames(combined)
  colnames(loadings) <- paste0("F", seq_len(k))
  var_exp <- (sv$d^2) / sum(sv$d^2)
  list(
    scores = scores,
    loadings = loadings,
    variance_explained = var_exp[seq_len(k)],
    samples = common
  )
}

#' Link ChIP peaks to genes, optionally correlating per-sample signal
#' with gene expression.
#'
#' @param peaks data.frame with at least chr, start, end, gene. Optional
#'   columns: peak_id, gene_tss (absolute TSS coordinate), signal, and
#'   per-sample signal columns whose names match `gene_expr` columns.
#' @param gene_expr Optional numeric matrix (genes x samples).
#' @param max_dist Maximum |peak midpoint - TSS| flagged as linked.
#' @return data.frame(peak_id, chr, gene, distance_to_tss, within_max_dist,
#'   expr_cor, note). Distances are NA (with a note) when `gene_tss` is
#'   absent: coordinates are never guessed.
emp_chip_rna_links <- function(peaks, gene_expr = NULL, max_dist = 50000) {
  if (!is.data.frame(peaks) ||
      !all(c("chr", "start", "end", "gene") %in% names(peaks))) {
    stop("emp_chip_rna_links: `peaks` needs chr, start, end, gene columns")
  }
  n <- nrow(peaks)
  peak_id <- if ("peak_id" %in% names(peaks)) {
    as.character(peaks$peak_id)
  } else {
    paste0("peak_", seq_len(n))
  }
  mid <- (as.numeric(peaks$start) + as.numeric(peaks$end)) / 2
  has_tss <- "gene_tss" %in% names(peaks)
  distance <- if (has_tss) abs(mid - as.numeric(peaks$gene_tss)) else rep(NA_real_, n)
  note <- if (has_tss) "" else "gene_tss column absent; distance not computed"

  expr_cor <- rep(NA_real_, n)
  if (!is.null(gene_expr)) {
    if (is.data.frame(gene_expr)) gene_expr <- as.matrix(gene_expr)
    sample_cols <- intersect(names(peaks), colnames(gene_expr))
    if (length(sample_cols) >= 3 && !is.null(rownames(gene_expr))) {
      for (i in seq_len(n)) {
        gene <- as.character(peaks$gene[[i]])
        if (gene %in% rownames(gene_expr)) {
          expr_cor[[i]] <- tryCatch(
            stats::cor(as.numeric(peaks[i, sample_cols]),
                       as.numeric(gene_expr[gene, sample_cols]),
                       method = "spearman", use = "complete.obs"),
            error = function(e) NA_real_
          )
        }
      }
    }
  }

  data.frame(
    peak_id = peak_id,
    chr = as.character(peaks$chr),
    gene = as.character(peaks$gene),
    distance_to_tss = distance,
    within_max_dist = if (has_tss) distance <= max_dist else rep(NA, n),
    expr_cor = expr_cor,
    note = note,
    stringsAsFactors = FALSE
  )
}
