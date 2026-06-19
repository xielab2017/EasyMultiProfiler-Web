# ============================================================================
# Clinical & phenotype analysis helpers
#
# Exposes four backend entry points that the `/api/clinical/*` plumber routes
# use.  The underlying math is delegated to `psych::corr.test()` (feature/
# trait correlation, fast) and EasyMultiProfiler's `EMP_WGCNA_*` stack
# (module–trait analysis, slower, returns the module × trait heatmap).
#
# Clinical variables are, by convention, any *numeric* column in `colData`
# (e.g. age, BMI, biomarker level, survival time).  Categorical columns are
# handled by the existing diff-analysis / grouping tools, not here.
# ============================================================================

.clin_norm_id <- function(x) {
  x <- toupper(trimws(as.character(x)))
  x <- gsub("\\.", "_", x)
  x <- sub("^X_", "", x)
  x <- sub("^X([A-Z])_", "\\1_", x)
  x <- gsub("_+", "_", x)
  x <- sub("_[0-9]+$", "", x)
  x <- sub("^[A-Z]([A-Z]_XYL_)", "\\1", x)
  x
}

.clin_exact_id <- function(x) {
  x <- toupper(trimws(as.character(x)))
  x <- sub("^\ufeff", "", x)
  x <- gsub("[\\.\\-]+", "_", x)
  x <- gsub("_+", "_", x)
  x
}

.clin_external_path <- function(session_id, kind = "legacy") {
  k <- tolower(trimws(as.character(kind %||% "legacy")))
  dirp <- dirname(mae_path(session_id))
  if (identical(k, "raw")) return(file.path(dirp, "clinical_uploaded_raw.csv"))
  if (identical(k, "meta")) return(file.path(dirp, "clinical_uploaded_meta.csv"))
  file.path(dirp, "clinical_uploaded.csv")
}

.clin_merge_external_tables <- function(raw, meta) {
  if (is.null(raw) || !nrow(raw)) return(meta)
  if (is.null(meta) || !nrow(meta)) return(raw)
  if (!"primary" %in% names(raw) || !"primary" %in% names(meta)) return(raw)

  raw_key <- .clin_exact_id(raw$primary)
  meta_key <- .clin_exact_id(meta$primary)
  all_key <- unique(c(raw_key[nzchar(raw_key)], meta_key[nzchar(meta_key)]))
  out <- data.frame(primary = character(length(all_key)), stringsAsFactors = FALSE)
  out$primary <- all_key

  raw_idx <- match(all_key, raw_key)
  meta_idx <- match(all_key, meta_key)
  raw_cols <- setdiff(names(raw), "primary")
  meta_cols <- setdiff(names(meta), "primary")
  for (col in union(raw_cols, meta_cols)) {
    vals <- rep(NA_character_, length(all_key))
    if (col %in% raw_cols) {
      ii <- which(!is.na(raw_idx))
      vals[ii] <- as.character(raw[[col]][raw_idx[ii]])
    }
    if (col %in% meta_cols) {
      ii <- which(!is.na(meta_idx))
      mv <- as.character(meta[[col]][meta_idx[ii]])
      empty <- is.na(vals[ii]) | !nzchar(vals[ii])
      vals[ii[empty]] <- mv[empty]
    }
    out[[col]] <- vals
  }
  raw_primary <- as.character(raw$primary)[raw_idx]
  meta_primary <- as.character(meta$primary)[meta_idx]
  out$primary <- ifelse(!is.na(raw_idx), raw_primary, meta_primary)
  out
}

.clin_read_external <- function(session_id) {
  raw <- NULL
  legacy <- NULL
  meta <- NULL
  p_raw <- .clin_external_path(session_id, "raw")
  p_legacy <- .clin_external_path(session_id, "legacy")
  p_meta <- .clin_external_path(session_id, "meta")
  if (file.exists(p_raw)) raw <- tryCatch(read_metadata_table(p_raw), error = function(e) NULL)
  if (file.exists(p_legacy)) legacy <- tryCatch(read_metadata_table(p_legacy), error = function(e) NULL)
  if (file.exists(p_meta)) meta <- tryCatch(read_metadata_table(p_meta), error = function(e) NULL)

  base <- if (!is.null(raw) && nrow(raw) && ncol(raw)) raw else legacy
  merged <- .clin_merge_external_tables(base, meta)
  if (!is.null(merged) && nrow(merged) && ncol(merged)) return(merged)
  NULL
}

reorient_standalone_clinical_table <- function(session_id, mode = "auto") {
  p <- .clin_external_path(session_id, "raw")
  if (!file.exists(p)) p <- .clin_external_path(session_id, "legacy")
  if (!file.exists(p)) p <- .clin_external_path(session_id, "meta")
  if (!file.exists(p)) {
    return(list(
      mode = tolower(trimws(as.character(mode %||% "auto"))),
      orientation = "not_available",
      n_samples = 0L,
      n_variables = 0L,
      warning = "No standalone clinical data found in this session."
    ))
  }
  m <- tolower(trimws(as.character(mode %||% "auto")))
  if (!m %in% c("auto", "transpose")) m <- "auto"
  if (identical(m, "auto")) {
    meta <- read_metadata_table(p)
    if (is.null(meta) || !nrow(meta)) stop("Clinical table is empty.")
    utils::write.csv(meta, p, row.names = FALSE)
    return(list(
      mode = m,
      orientation = attr(meta, "orientation_note") %||% "samples in rows",
      n_samples = nrow(meta),
      n_variables = max(0L, ncol(meta) - 1L)
    ))
  }

  raw <- read_table_auto(p)
  if (is.null(raw) || nrow(raw) < 2 || ncol(raw) < 2) stop("Clinical table too small to transpose.")
  first_col <- names(raw)[1]
  row_keys <- as.character(raw[[first_col]])
  row_keys[is.na(row_keys) | !nzchar(row_keys)] <- paste0("row_", seq_len(sum(is.na(row_keys) | !nzchar(row_keys))))
  mtx <- as.matrix(raw[, -1, drop = FALSE])
  rownames(mtx) <- row_keys
  tdf <- as.data.frame(t(mtx), stringsAsFactors = FALSE, check.names = FALSE)
  tdf$primary <- rownames(tdf)
  tdf <- tdf[, c("primary", setdiff(names(tdf), "primary")), drop = FALSE]
  utils::write.csv(tdf, p, row.names = FALSE)

  meta <- read_metadata_table(p)
  utils::write.csv(meta, p, row.names = FALSE)
  list(
    mode = m,
    orientation = "transposed and corrected",
    n_samples = nrow(meta),
    n_variables = max(0L, ncol(meta) - 1L)
  )
}

.clin_merge_external_cd <- function(session_id, empt) {
  cd <- as.data.frame(SummarizedExperiment::colData(empt), stringsAsFactors = FALSE)
  sn <- as.character(colnames(empt))
  if (is.null(rownames(cd)) || !length(rownames(cd))) rownames(cd) <- sn
  ext <- .clin_read_external(session_id)
  if (is.null(ext) || !nrow(ext)) return(cd)

  idx <- match(.clin_norm_id(sn), .clin_norm_id(ext$primary))
  ok <- which(!is.na(idx))
  hit <- if (length(ok)) {
    hh <- ext[idx[ok], , drop = FALSE]
    hh$primary <- sn[ok]
    hh
  } else {
    ext
  }
  all_rows <- union(sn, as.character(hit$primary))
  merged <- data.frame(row.names = all_rows, stringsAsFactors = FALSE)
  for (col in union(names(cd), setdiff(names(hit), "primary"))) {
    vals <- rep(NA_character_, length(all_rows))
    if (col %in% names(cd)) vals[match(rownames(cd), all_rows)] <- as.character(cd[[col]])
    if (col %in% names(hit)) vals[match(as.character(hit$primary), all_rows)] <- as.character(hit[[col]])
    merged[[col]] <- vals
  }
  merged
}

merged_experiment_coldata <- function(session_id, empt) {
  cd <- .clin_merge_external_cd(session_id, empt)
  sn <- as.character(colnames(empt))
  if (!length(sn) || !nrow(cd)) return(cd)
  if (all(sn %in% rownames(cd))) {
    return(cd[sn, , drop = FALSE])
  }
  idx <- match(sn, rownames(cd))
  if (any(is.na(idx))) {
  idx2 <- match(.clin_norm_id(sn), .clin_norm_id(rownames(cd)))
  idx[is.na(idx)] <- idx2[is.na(idx)]
  }
  out <- cd[idx, , drop = FALSE]
  rownames(out) <- sn
  out
}

apply_merged_coldata <- function(session_id, empt) {
  cd_df <- merged_experiment_coldata(session_id, empt)
  SummarizedExperiment::colData(empt) <- S4Vectors::DataFrame(cd_df)
  empt
}

.coldata_is_group_like_name <- function(nm) {
  tolower(trimws(as.character(nm))) %in% c(
    "group", "subgroup", "cohort", "condition", "disease", "diagnosis", "treatment"
  )
}

.coldata_column_summaries <- function(cd, max_values = 100L) {
  lapply(names(cd), function(col) {
    vals <- unique(na.omit(as.character(cd[[col]])))
    vals <- vals[nzchar(vals)]
    list(
      name = col,
      n_unique = length(vals),
      values = as.character(vals[seq_len(min(max_values, length(vals)))])
    )
  })
}

# ---------------------------------------------------------------------------
# list_clinical_vars(session_id, experiment)
#
# Return a data-frame describing each candidate clinical/phenotype column in
# the experiment's sample metadata:
#   name            : column name
#   type            : "numeric" | "categorical"
#   n_samples       : # samples with non-NA value
#   n_unique        : # distinct values
#   min / max / mean: only for numeric columns
# The frontend uses `type == "numeric"` to populate dropdowns of continuous
# clinical variables; categorical ones are also returned so users can see
# what else is available.
# ---------------------------------------------------------------------------
list_clinical_vars <- function(session_id, experiment) {
  empt <- get_empt_fresh(session_id, experiment)
  cd <- .clin_merge_external_cd(session_id, empt)
  # Drop the sample-id column the importer adds (`primary`), since that is
  # never a trait.
  drop <- intersect(c("primary", "SampleID", "sampleID", "Sample"), names(cd))
  if (length(drop)) cd <- cd[, setdiff(names(cd), drop), drop = FALSE]
  rows <- lapply(names(cd), function(nm) {
    v <- cd[[nm]]
    vn <- suppressWarnings(as.numeric(v))
    is_num <- (is.numeric(v) || (sum(is.finite(vn)) >= max(3L, floor(0.1 * length(v))))) &&
      !.coldata_is_group_like_name(nm)
    if (is_num) {
      data.frame(
        name      = nm,
        type      = "numeric",
        n_samples = sum(is.finite(vn)),
        n_unique  = length(unique(stats::na.omit(vn))),
        min       = suppressWarnings(min(vn,  na.rm = TRUE)),
        max       = suppressWarnings(max(vn,  na.rm = TRUE)),
        mean      = suppressWarnings(mean(vn, na.rm = TRUE)),
        stringsAsFactors = FALSE
      )
    } else {
      ux <- unique(stats::na.omit(as.character(v)))
      data.frame(
        name      = nm,
        type      = "categorical",
        n_samples = sum(!is.na(v) & nzchar(as.character(v))),
        n_unique  = length(ux),
        min       = NA_real_, max = NA_real_, mean = NA_real_,
        stringsAsFactors = FALSE
      )
    }
  })
  out <- do.call(rbind, rows)
  if (is.null(out)) out <- data.frame(name = character(), type = character(),
                                       n_samples = integer(), n_unique = integer(),
                                       min = numeric(), max = numeric(), mean = numeric(),
                                       stringsAsFactors = FALSE)
  out
}

list_clinical_vars_standalone <- function(session_id) {
  cd <- .clin_read_external(session_id)
  if (is.null(cd) || !nrow(cd)) {
    return(data.frame(
      name = character(), type = character(),
      n_samples = integer(), n_unique = integer(),
      min = numeric(), max = numeric(), mean = numeric(),
      stringsAsFactors = FALSE
    ))
  }
  drop <- intersect(c("primary", "SampleID", "sampleID", "Sample"), names(cd))
  if (length(drop)) cd <- cd[, setdiff(names(cd), drop), drop = FALSE]
  rows <- lapply(names(cd), function(nm) {
    v <- cd[[nm]]
    vn <- suppressWarnings(as.numeric(v))
    is_num <- (is.numeric(v) || (sum(is.finite(vn)) >= max(3L, floor(0.1 * length(v))))) &&
      !.coldata_is_group_like_name(nm)
    if (is_num) {
      data.frame(
        name = nm, type = "numeric",
        n_samples = sum(is.finite(vn)),
        n_unique = length(unique(stats::na.omit(vn))),
        min = suppressWarnings(min(vn, na.rm = TRUE)),
        max = suppressWarnings(max(vn, na.rm = TRUE)),
        mean = suppressWarnings(mean(vn, na.rm = TRUE)),
        stringsAsFactors = FALSE
      )
    } else {
      ux <- unique(stats::na.omit(as.character(v)))
      data.frame(
        name = nm, type = "categorical",
        n_samples = sum(!is.na(v) & nzchar(as.character(v))),
        n_unique = length(ux),
        min = NA_real_, max = NA_real_, mean = NA_real_,
        stringsAsFactors = FALSE
      )
    }
  })
  out <- do.call(rbind, rows)
  if (is.null(out)) out <- data.frame(
    name = character(), type = character(),
    n_samples = integer(), n_unique = integer(),
    min = numeric(), max = numeric(), mean = numeric(),
    stringsAsFactors = FALSE
  )
  out
}

.clinical_is_numeric_like <- function(v) {
  vn <- suppressWarnings(as.numeric(v))
  is.numeric(v) || (sum(is.finite(vn)) >= max(3L, floor(0.1 * length(v))))
}

.clinical_is_low_cardinality_group <- function(v, max_levels = 20L) {
  if (.clinical_is_numeric_like(v)) return(FALSE)
  ux <- unique(stats::na.omit(as.character(v)))
  ux <- ux[nzchar(ux)]
  length(ux) >= 2L && length(ux) <= max_levels
}

.clinical_preferred_group_var <- function(cd, group_var = NULL, max_levels = 20L) {
  if (is.null(cd) || !ncol(cd)) return(NULL)
  if (!is.null(group_var) && nzchar(group_var)) {
    hit <- names(cd)[tolower(names(cd)) == tolower(group_var)]
    if (length(hit)) return(hit[1])
  }
  preferred <- c(
    "Group", "group", "Disease", "disease", "Condition", "condition",
    "Diagnosis", "diagnosis", "Cohort", "cohort", "Subgroup", "subgroup"
  )
  for (nm in preferred) {
    hit <- names(cd)[tolower(names(cd)) == tolower(nm)]
    if (length(hit) && .clinical_is_low_cardinality_group(cd[[hit[1]]], max_levels = max_levels)) {
      return(hit[1])
    }
  }
  avoid <- c("primary", "SampleID", "sampleID", "Sample", "patient", "Patient", "gender", "Gender", "sex", "Sex")
  cat_cols <- setdiff(names(cd)[sapply(cd, .clinical_is_low_cardinality_group, max_levels = max_levels)], avoid)
  if (length(cat_cols)) return(cat_cols[1])
  cat_cols <- names(cd)[sapply(cd, .clinical_is_low_cardinality_group, max_levels = max_levels)]
  if (length(cat_cols)) cat_cols[1] else NULL
}

.three_line_gtsummary_from_df <- function(cd, group_var = NULL,
                                          skip_high_cardinality = TRUE,
                                          max_levels = 20L) {
  if (!requireNamespace("gtsummary", quietly = TRUE)) {
    stop("R package 'gtsummary' is not installed.")
  }
  keep_cols <- setdiff(names(cd), "primary")
  if (!length(keep_cols)) stop("Clinical table has no variables.")
  x <- cd[, keep_cols, drop = FALSE]

  max_levels <- suppressWarnings(as.integer(max_levels))
  if (!is.finite(max_levels) || is.na(max_levels) || max_levels < 2L) max_levels <- 20L
  skip_high_cardinality <- isTRUE(skip_high_cardinality)

  # Optional filtering of high-cardinality categorical variables (e.g. patient ID)
  keep_var <- names(x)
  if (skip_high_cardinality) {
    keep_var <- keep_var[sapply(keep_var, function(nm) {
      v <- x[[nm]]
      vn <- suppressWarnings(as.numeric(v))
      is_num <- (is.numeric(v) || (sum(is.finite(vn)) >= max(3L, floor(0.1 * length(v))))) &&
      !.coldata_is_group_like_name(nm)
      if (is_num) return(TRUE)
      nlv <- length(unique(stats::na.omit(as.character(v))))
      nlv <= max_levels
    })]
    x <- x[, keep_var, drop = FALSE]
  }
  if (!ncol(x)) stop("No variables left after high-cardinality filtering.")

  by_var <- .clinical_preferred_group_var(x, group_var = group_var, max_levels = min(max_levels, 20L))

  .is_score_like <- function(v) {
    vn <- suppressWarnings(as.numeric(v))
    fin <- vn[is.finite(vn)]
    if (length(fin) < 3L) return(FALSE)
    # Treat low-cardinality integer scales as categorical (clinical scores).
    all(abs(fin - round(fin)) < 1e-8) && length(unique(fin)) >= 2L && length(unique(fin)) <= 8L
  }
  # Build gtsummary variable types systematically for clinical indicators.
  var_type <- setNames(rep("categorical", length(names(x))), names(x))
  for (nm in names(x)) {
    v <- x[[nm]]
    if (.clinical_is_numeric_like(v) && !.is_score_like(v)) {
      var_type[[nm]] <- "continuous"
      x[[nm]] <- suppressWarnings(as.numeric(v))
    } else {
      x[[nm]] <- as.factor(as.character(v))
    }
  }

  # When grouping, drop rows with missing/blank group to avoid "NA." columns
  # in final publication tables.
  if (!is.null(by_var)) {
    gv <- as.character(x[[by_var]])
    keep <- !is.na(gv) & nzchar(gv)
    x <- x[keep, , drop = FALSE]
    if (nrow(x) < 3L) stop("Too few samples after removing missing grouping values.")
  }

  tbl <- if (!is.null(by_var)) {
    gtsummary::tbl_summary(
      data = x,
      by = by_var,
      statistic = list(
        gtsummary::all_continuous() ~ "{median} [{p25}; {p75}]",
        gtsummary::all_categorical() ~ "{n} ({p}%)"
      ),
      digits = list(gtsummary::all_continuous() ~ 2),
      missing = "no"
    ) |>
      gtsummary::add_n() |>
      gtsummary::add_p() |>
      gtsummary::bold_labels()
  } else {
    gtsummary::tbl_summary(
      data = x,
      statistic = list(
        gtsummary::all_continuous() ~ "{median} [{p25}; {p75}]",
        gtsummary::all_categorical() ~ "{n} ({p}%)"
      ),
      digits = list(gtsummary::all_continuous() ~ 2),
      missing = "no"
    ) |>
      gtsummary::add_n() |>
      gtsummary::bold_labels()
  }

  out <- tryCatch(
    gtsummary::as_tibble(tbl, col_labels = TRUE),
    error = function(e) NULL
  )
  if (is.null(out)) {
    out <- tryCatch(as.data.frame(tbl$table_body, stringsAsFactors = FALSE), error = function(e) NULL)
  }
  if (is.null(out) || !nrow(out)) stop("gtsummary generated no rows.")
  out <- as.data.frame(out, stringsAsFactors = FALSE)

  # Normalize column names for stable frontend rendering.
  nm <- names(out)
  nm <- gsub("\\*+", "", nm)
  nm <- gsub("\\s*\\n\\s*N\\s*=\\s*\\d+.*$", "", nm) # "Female** \nN = 66" -> "Female"
  nm <- gsub("\\s+", " ", nm)
  nm <- trimws(nm)
  names(out) <- nm
  if ("Characteristic" %in% names(out) && !("Variable" %in% names(out))) {
    names(out)[names(out) == "Characteristic"] <- "Variable"
  }
  if ("label" %in% names(out) && !("Variable" %in% names(out))) {
    names(out)[names(out) == "label"] <- "Variable"
  }
  pnm <- names(out)[grepl("^p([\\.|_|\\s|-])?(value|overall)?$", tolower(names(out)))]
  if (length(pnm)) names(out)[names(out) == pnm[1]] <- "P_value"
  if ("Variable" %in% names(out)) {
    vv <- as.character(out$Variable)
    vv <- gsub("^_+|_+$", "", vv)
    vv <- gsub("\\*+", "", vv)
    vv <- gsub("\\s+", " ", vv)
    out$Variable <- trimws(vv)
  }
  attr(out, "engine_used") <- "gtsummary"
  out
}

.three_line_from_df <- function(cd, group_var = NULL,
                                skip_high_cardinality = TRUE,
                                max_levels = 20L) {
  if (is.null(cd) || !nrow(cd)) stop("Clinical table is empty.")
  keep_cols <- setdiff(names(cd), "primary")
  if (!length(keep_cols)) stop("Clinical table has no variables.")
  cd <- cd[, keep_cols, drop = FALSE]

  group_var <- .clinical_preferred_group_var(cd, group_var = group_var, max_levels = min(max_levels, 20L))
  grp <- if (!is.null(group_var)) as.character(cd[[group_var]]) else rep("All", nrow(cd))
  grp[!nzchar(grp)] <- NA_character_
  grp[is.na(grp)] <- "NA"
  groups <- unique(grp)
  groups <- groups[order(groups)]

  .fmt_num <- function(x) {
    x <- suppressWarnings(as.numeric(x))
    x <- x[is.finite(x)]
    if (!length(x)) return("NA")
    sprintf("%.2f ± %.2f", mean(x), stats::sd(x))
  }
  .fmt_cat <- function(x, lv) {
    x <- as.character(x)
    n <- sum(!is.na(x) & nzchar(x))
    if (!n) return("0 (0.0%)")
    k <- sum(x == lv, na.rm = TRUE)
    sprintf("%d (%.1f%%)", k, 100 * k / n)
  }

  out <- list()
  pidx <- 1L
  max_levels <- suppressWarnings(as.integer(max_levels))
  if (!is.finite(max_levels) || is.na(max_levels) || max_levels < 2L) max_levels <- 20L
  skip_high_cardinality <- isTRUE(skip_high_cardinality)

  for (nm in names(cd)) {
    if (!is.null(group_var) && identical(nm, group_var)) next
    v <- cd[[nm]]
    vn <- suppressWarnings(as.numeric(v))
    is_num <- (is.numeric(v) || (sum(is.finite(vn)) >= max(3L, floor(0.1 * length(v))))) &&
      !.coldata_is_group_like_name(nm)
    row_base <- list(Variable = nm)

    if (is_num) {
      row_base$Overall <- .fmt_num(vn)
      for (g in groups) row_base[[g]] <- .fmt_num(vn[grp == g])
      gvals <- split(vn, grp)
      gvals <- gvals[sapply(gvals, function(x) sum(is.finite(x)) > 0)]
      p <- NA_real_
      if (length(gvals) >= 2) {
        if (length(gvals) == 2) {
          p <- tryCatch(stats::wilcox.test(gvals[[1]], gvals[[2]])$p.value, error = function(e) NA_real_)
        } else {
          p <- tryCatch(stats::kruskal.test(vn ~ as.factor(grp))$p.value, error = function(e) NA_real_)
        }
      }
      row_base$P_value <- ifelse(is.finite(p), signif(p, 3), NA)
      out[[pidx]] <- as.data.frame(row_base, stringsAsFactors = FALSE)
      pidx <- pidx + 1L
    } else {
      lvls <- unique(stats::na.omit(as.character(v)))
      lvls <- lvls[nzchar(lvls)]
      if (!length(lvls)) next
      if (skip_high_cardinality && length(lvls) > max_levels) next
      p <- NA_real_
      if (length(groups) >= 2) {
        tb <- table(as.factor(v), as.factor(grp))
        if (all(dim(tb) >= 2)) {
          p <- tryCatch({
            nr <- nrow(tb); nc <- ncol(tb)
            # Avoid extremely slow Fisher exact tests on large RxC tables
            # (e.g. patient IDs with dozens of levels), which can make the
            # frontend appear stuck at 92% while the request is still running.
            if (nr > 8 || nc > 5 || (nr * nc) > 60) {
              stats::chisq.test(tb, simulate.p.value = TRUE, B = 2000)$p.value
            } else if (all(tb >= 5)) {
              stats::chisq.test(tb)$p.value
            } else if (nr == 2 && nc == 2) {
              stats::fisher.test(tb)$p.value
            } else {
              stats::chisq.test(tb, simulate.p.value = TRUE, B = 2000)$p.value
            }
          }, error = function(e) NA_real_)
        }
      }
      for (i in seq_along(lvls)) {
        lv <- lvls[i]
        r <- list(Variable = paste0(nm, ": ", lv))
        r$Overall <- .fmt_cat(v, lv)
        for (g in groups) r[[g]] <- .fmt_cat(v[grp == g], lv)
        r$P_value <- ifelse(i == 1L && is.finite(p), signif(p, 3), NA)
        out[[pidx]] <- as.data.frame(r, stringsAsFactors = FALSE)
        pidx <- pidx + 1L
      }
    }
  }
  if (!length(out)) stop("No valid variables for three-line table.")
  tab <- dplyr::bind_rows(out)
  attr(tab, "engine_used") <- "emp_custom"
  tab
}

make_clinical_three_line_table <- function(session_id, group_var = NULL,
                                           skip_high_cardinality = TRUE,
                                           max_levels = 20L,
                                           table_engine = "gtsummary") {
  cd <- .clin_read_external(session_id)
  if (is.null(cd) || !nrow(cd)) stop("No standalone clinical data found. Upload clinical data first.")
  engine <- tolower(trimws(as.character(table_engine %||% "gtsummary")))
  if (identical(engine, "gtsummary")) {
    tryCatch(
      .three_line_gtsummary_from_df(cd, group_var = group_var,
                                    skip_high_cardinality = skip_high_cardinality,
                                    max_levels = max_levels),
      error = function(e) .three_line_from_df(cd, group_var = group_var,
                                              skip_high_cardinality = skip_high_cardinality,
                                              max_levels = max_levels)
    )
  } else {
    .three_line_from_df(cd, group_var = group_var,
                        skip_high_cardinality = skip_high_cardinality,
                        max_levels = max_levels)
  }
}

make_clinical_three_line_table_experiment <- function(session_id, experiment, group_var = NULL,
                                                      skip_high_cardinality = TRUE,
                                                      max_levels = 20L,
                                                      table_engine = "gtsummary") {
  empt <- get_empt_fresh(session_id, experiment)
  sn <- as.character(colnames(empt))
  cd <- .clin_merge_external_cd(session_id, empt)
  if (is.null(cd) || !nrow(cd)) stop("No experiment clinical metadata found.")
  if (is.null(rownames(cd)) || !length(rownames(cd))) rownames(cd) <- sn
  cd <- cd[sn, , drop = FALSE]
  if (is.null(cd) || !nrow(cd)) stop("No experiment clinical metadata found.")
  cd$primary <- rownames(cd)
  engine <- tolower(trimws(as.character(table_engine %||% "gtsummary")))
  if (identical(engine, "gtsummary")) {
    tryCatch(
      .three_line_gtsummary_from_df(cd, group_var = group_var,
                                    skip_high_cardinality = skip_high_cardinality,
                                    max_levels = max_levels),
      error = function(e) .three_line_from_df(cd, group_var = group_var,
                                              skip_high_cardinality = skip_high_cardinality,
                                              max_levels = max_levels)
    )
  } else {
    .three_line_from_df(cd, group_var = group_var,
                        skip_high_cardinality = skip_high_cardinality,
                        max_levels = max_levels)
  }
}

.clinical_sample_sid <- function(cd) {
  id_col <- intersect(c("primary", "SampleID", "sampleID", "Sample"), names(cd))
  sid <- if (length(id_col)) as.character(cd[[id_col[1]]]) else rownames(cd)
  sid <- as.character(sid)
  sid[is.na(sid)] <- ""
  trimws(sid)
}

.clinical_infer_cohort <- function(sid) {
  prefix2 <- ifelse(nchar(sid) >= 2L, substr(sid, 1L, 2L), "")
  ifelse(substr(prefix2, 2L, 2L) == "K", "UC",
         ifelse(substr(prefix2, 2L, 2L) == "J", "IBS", NA_character_))
}

.clinical_is_paired_sample_id <- function(sid) {
  sid <- as.character(sid)
  prefix2 <- ifelse(nchar(sid) >= 2L, substr(sid, 1L, 2L), "")
  grepl("^[ABCD][KJ](_|$)", prefix2, ignore.case = TRUE) |
    grepl("^[ABCD][KJ]_", sid, ignore.case = TRUE)
}

.clinical_infer_longitudinal_design <- function(cd, sid) {
  sid <- as.character(sid)
  prefix2 <- ifelse(nchar(sid) >= 2L, substr(sid, 1L, 2L), "")
  paired_id <- .clinical_is_paired_sample_id(sid)
  phase <- rep(NA_character_, length(sid))
  cohort <- rep(NA_character_, length(sid))
  if (any(paired_id)) {
    phase[paired_id] <- ifelse(substr(prefix2[paired_id], 1L, 1L) %in% c("A", "C"), "before", "after")
    cohort[paired_id] <- .clinical_infer_cohort(sid[paired_id])
  }
  pair_key <- ifelse(nchar(sid) >= 2L, substring(sid, 2L), sid)

  group_col <- .clinical_preferred_group_var(cd, max_levels = 50L)
  if (!is.null(group_col)) {
    gv <- trimws(as.character(cd[[group_col]]))
    temporal <- grepl("(^|[_ -])(pre|before|baseline|base|前|治疗前|post|after|follow|治疗后|后)([_ -]|$)", gv, ignore.case = TRUE)
    if (any(temporal)) {
      phase_from_group <- ifelse(grepl("(^|[_ -])(pre|before|baseline|base|前|治疗前)([_ -]|$)", gv, ignore.case = TRUE), "before",
                                 ifelse(grepl("(^|[_ -])(post|after|follow|治疗后|后)([_ -]|$)", gv, ignore.case = TRUE), "after", NA_character_))
      phase[!is.na(phase_from_group)] <- phase_from_group[!is.na(phase_from_group)]
      cohort_from_group <- gsub("(^|[_ -])(pre|before|baseline|base|post|after|follow|前|后|治疗前|治疗后)([_ -]|$)", "_", gv, ignore.case = TRUE)
      cohort_from_group <- gsub("(_before|_after|before_|after_)", "_", cohort_from_group, ignore.case = TRUE)
      cohort_from_group <- gsub("[_ -]+$", "", gsub("^[_ -]+", "", cohort_from_group))
      cohort_from_group <- toupper(cohort_from_group)
      cohort_from_group[!nzchar(cohort_from_group)] <- NA_character_
      cohort[is.na(cohort) & !is.na(cohort_from_group)] <- cohort_from_group[is.na(cohort) & !is.na(cohort_from_group)]
    }
  }

  patient_cols <- names(cd)[tolower(names(cd)) %in% c("patient", "subject", "subjectid", "patientid", "id")]
  patient_cols <- setdiff(patient_cols, c("primary", "SampleID", "sampleID", "Sample"))
  if (length(patient_cols)) {
    pk <- trimws(as.character(cd[[patient_cols[1]]]))
    pair_key[nzchar(pk)] <- pk[nzchar(pk)]
  }

  data.frame(pair_key = pair_key, phase = phase, cohort = cohort, stringsAsFactors = FALSE)
}

.clinical_count_paired_samples <- function(design) {
  pair_key_before <- unique(design$pair_key[design$phase == "before" & !is.na(design$cohort) & nzchar(design$pair_key)])
  pair_key_after <- unique(design$pair_key[design$phase == "after" & !is.na(design$cohort) & nzchar(design$pair_key)])
  length(intersect(pair_key_before, pair_key_after))
}

.clinical_fmt_med_iqr <- function(v) {
  v <- suppressWarnings(as.numeric(v))
  v <- v[is.finite(v)]
  if (!length(v)) return("NA")
  qs <- stats::quantile(v, probs = c(0.25, 0.5, 0.75), na.rm = TRUE, names = FALSE)
  sprintf("%.2f [%.2f; %.2f]", qs[2], qs[1], qs[3])
}

.clinical_cross_group_table <- function(cd, group_var = NULL) {
  group_var <- .clinical_preferred_group_var(cd, group_var = group_var, max_levels = 50L)
  if (is.null(group_var) || !group_var %in% names(cd)) return(data.frame())
  grp <- trimws(as.character(cd[[group_var]]))
  keep <- !is.na(grp) & nzchar(grp)
  if (sum(keep) < 6L) return(data.frame())
  cd <- cd[keep, , drop = FALSE]
  grp <- grp[keep]
  groups <- sort(unique(grp))
  if (length(groups) < 2L) return(data.frame())

  skip_cols <- c("primary", "SampleID", "sampleID", "Sample", group_var, "Subgroup", "subgroup", "patient", "Patient")
  keep_cols <- setdiff(names(cd), skip_cols)
  num_vars <- keep_cols[vapply(keep_cols, function(nm) .clinical_is_numeric_like(cd[[nm]]), logical(1L))]
  num_vars <- num_vars[!grepl("^(D_|R_)", num_vars, ignore.case = TRUE)]
  if (!length(num_vars)) return(data.frame())

  rows <- list()
  idx <- 1L
  for (nm in num_vars) {
    v <- suppressWarnings(as.numeric(cd[[nm]]))
    ok <- is.finite(v)
    if (sum(ok) < 6L) next
    gtab <- table(grp[ok])
    if (length(gtab) < 2L || any(gtab < 3L)) next
    p <- tryCatch(
      if (length(gtab) == 2L) {
        g1 <- v[ok & grp == groups[1]]
        g2 <- v[ok & grp == groups[2]]
        stats::wilcox.test(g1, g2)$p.value
      } else {
        stats::kruskal.test(v[ok] ~ as.factor(grp[ok]))$p.value
      },
      error = function(e) NA_real_
    )
    row <- list(
      Variable = nm,
      Comparison = paste(groups, collapse = " vs "),
      P_value = ifelse(is.finite(p), signif(p, 4), NA_real_)
    )
    for (g in groups) row[[g]] <- .clinical_fmt_med_iqr(v[ok & grp == g])
    rows[[idx]] <- as.data.frame(row, stringsAsFactors = FALSE)
    idx <- idx + 1L
  }
  if (!length(rows)) return(data.frame())
  dplyr::bind_rows(rows)
}

.clinical_resolve_cohorts <- function(cohort_filter = NULL) {
  if (is.null(cohort_filter) || !length(cohort_filter)) return(c("UC", "IBS"))
  cohorts <- toupper(trimws(as.character(cohort_filter)))
  cohorts <- cohorts[nzchar(cohorts)]
  cohorts <- cohorts[cohorts %in% c("UC", "IBS")]
  if (!length(cohorts)) c("UC", "IBS") else unique(cohorts)
}

.clinical_filter_cd_by_cohorts <- function(cd, cohort_filter = NULL) {
  if (is.null(cohort_filter) || !length(cohort_filter)) return(cd)
  cohorts <- .clinical_resolve_cohorts(cohort_filter)
  sid <- .clinical_sample_sid(cd)
  cohort <- .clinical_infer_longitudinal_design(cd, sid)$cohort
  keep <- !is.na(cohort) & cohort %in% cohorts
  if (!any(keep)) {
    stop(sprintf(
      "No samples matched cohort_filter (%s). Sample IDs use AK/BK=UC and CJ/DJ=IBS prefixes.",
      paste(cohorts, collapse = ", ")
    ))
  }
  cd[keep, , drop = FALSE]
}

.clinical_systematic_tables_from_df <- function(cd, group_var = NULL,
                                                skip_high_cardinality = TRUE,
                                                max_levels = 20L,
                                                table_engine = "gtsummary",
                                                cohort_filter = NULL) {
  sid <- .clinical_sample_sid(cd)
  cohorts_to_run <- .clinical_resolve_cohorts(cohort_filter)
  design <- .clinical_infer_longitudinal_design(cd, sid)
  n_pairs_total <- .clinical_count_paired_samples(design)
  longitudinal <- n_pairs_total >= 3L
  baseline_cd <- cd
  baseline_group_var <- .clinical_preferred_group_var(cd, group_var = group_var, max_levels = max_levels)
  if (is.null(baseline_group_var) || !nzchar(baseline_group_var)) baseline_group_var <- group_var
  if (isTRUE(longitudinal) && (is.null(group_var) || !nzchar(group_var))) {
    keep_base <- design$phase == "before" & !is.na(design$cohort)
    if (length(cohorts_to_run) && !identical(sort(cohorts_to_run), sort(c("UC", "IBS")))) {
      keep_base <- keep_base & design$cohort %in% cohorts_to_run
    }
    if (any(keep_base)) {
      baseline_cd <- cd[keep_base, , drop = FALSE]
      baseline_cd$Cohort <- design$cohort[keep_base]
      baseline_group_var <- "Cohort"
    }
  }

  base_tbl <- tryCatch(
    {
      engine <- tolower(trimws(as.character(table_engine %||% "gtsummary")))
      if (identical(engine, "gtsummary")) {
        tryCatch(
          .three_line_gtsummary_from_df(
            baseline_cd,
            group_var = baseline_group_var,
            skip_high_cardinality = skip_high_cardinality,
            max_levels = max_levels
          ),
          error = function(e) .three_line_from_df(
            baseline_cd,
            group_var = baseline_group_var,
            skip_high_cardinality = skip_high_cardinality,
            max_levels = max_levels
          )
        )
      } else {
        .three_line_from_df(
          baseline_cd,
          group_var = baseline_group_var,
          skip_high_cardinality = skip_high_cardinality,
          max_levels = max_levels
        )
      }
    },
    error = function(e) data.frame(Variable = character(), stringsAsFactors = FALSE)
  )

  # Longitudinal design is inferred from either:
  # - sample IDs (AK/BK = UC before/after; CJ/DJ = IBS before/after), or
  # - metadata columns such as Group=UC_before/UC_after plus patient IDs.
  pair_key <- design$pair_key
  phase <- design$phase
  cohort <- design$cohort

  keep_cols <- setdiff(names(cd), c("primary", "SampleID", "sampleID", "Sample"))
  if (length(keep_cols) == 0L) {
    return(list(
      baseline = base_tbl,
      within = data.frame(),
      between = data.frame(),
      meta = list(n_pairs = 0L)
    ))
  }

  x <- cd[, keep_cols, drop = FALSE]
  num_vars <- keep_cols[sapply(keep_cols, function(nm) {
    v <- x[[nm]]
    vn <- suppressWarnings(as.numeric(v))
    is.numeric(v) || (sum(is.finite(vn)) >= max(3L, floor(0.1 * length(v))))
  })]
  # Prefer interpretable baseline measures for paired analysis.
  num_vars <- num_vars[!grepl("^(D_|R_)", num_vars, ignore.case = TRUE)]
  if (!length(num_vars)) {
    return(list(
      baseline = base_tbl,
      within = data.frame(),
      between = data.frame(),
      meta = list(n_pairs = 0L)
    ))
  }

  d <- data.frame(
    pair_key = pair_key,
    phase = phase,
    cohort = cohort,
    stringsAsFactors = FALSE
  )
  d <- cbind(d, x[, num_vars, drop = FALSE])
  d <- d[!is.na(d$phase) & !is.na(d$cohort) & nzchar(d$pair_key), , drop = FALSE]
  if (length(cohorts_to_run) && !identical(sort(cohorts_to_run), sort(c("UC", "IBS")))) {
    d <- d[d$cohort %in% cohorts_to_run, , drop = FALSE]
  }
  pair_key_before <- unique(d$pair_key[d$phase == "before"])
  pair_key_after <- unique(d$pair_key[d$phase == "after"])
  n_pairs_total <- length(intersect(pair_key_before, pair_key_after))
  if (!longitudinal) {
    grp_var <- .clinical_preferred_group_var(cd, group_var = group_var, max_levels = max_levels)
    between_tbl <- .clinical_cross_group_table(cd = cd, group_var = grp_var)
    n_groups <- if (!is.null(grp_var) && grp_var %in% names(cd)) {
      length(unique(stats::na.omit(trimws(as.character(cd[[grp_var]])))))
    } else {
      0L
    }
    return(list(
      baseline = base_tbl,
      within = data.frame(),
      between = between_tbl,
      meta = list(
        n_pairs = 0L,
        design_type = "cross_sectional",
        group_var = grp_var,
        n_groups = n_groups,
        analysis_note = if (nrow(between_tbl)) {
          "Cross-sectional design detected: Table 1 by group plus between-group comparison. Paired before/after tables are not applicable."
        } else {
          "Cross-sectional design detected: only baseline Table 1 is available."
        }
      )
    ))
  }
  if (!nrow(d)) {
    return(list(
      baseline = base_tbl,
      within = data.frame(),
      between = data.frame(),
      meta = list(
        n_pairs = 0L,
        design_type = "longitudinal",
        group_var = baseline_group_var %||% group_var,
        n_groups = 0L,
        analysis_note = "Longitudinal labels were detected but no valid paired before/after samples were found."
      )
    ))
  }

  fmt_med_iqr <- .clinical_fmt_med_iqr

  within_rows <- list()
  between_rows <- list()
  ridx <- 1L
  bidx <- 1L

  for (coh in cohorts_to_run) {
    dd <- d[d$cohort == coh, , drop = FALSE]
    if (!nrow(dd)) next
    keys <- unique(dd$pair_key)
    for (nm in num_vars) {
      bef <- rep(NA_real_, length(keys))
      aft <- rep(NA_real_, length(keys))
      for (i in seq_along(keys)) {
        k <- keys[i]
        sub <- dd[dd$pair_key == k, c("phase", nm), drop = FALSE]
        vb <- suppressWarnings(as.numeric(sub[sub$phase == "before", nm]))
        va <- suppressWarnings(as.numeric(sub[sub$phase == "after", nm]))
        if (length(vb)) bef[i] <- vb[1]
        if (length(va)) aft[i] <- va[1]
      }
      keep <- is.finite(bef) & is.finite(aft)
      if (sum(keep) < 3L) next
      delta <- aft[keep] - bef[keep]
      p <- tryCatch(stats::wilcox.test(aft[keep], bef[keep], paired = TRUE)$p.value, error = function(e) NA_real_)
      within_rows[[ridx]] <- data.frame(
        Cohort = coh,
        Variable = nm,
        N_pairs = sum(keep),
        Before = fmt_med_iqr(bef[keep]),
        After = fmt_med_iqr(aft[keep]),
        Delta = fmt_med_iqr(delta),
        P_value = ifelse(is.finite(p), signif(p, 4), NA_real_),
        stringsAsFactors = FALSE
      )
      ridx <- ridx + 1L
    }
  }

  within_tbl <- if (length(within_rows)) dplyr::bind_rows(within_rows) else data.frame()

  # Between-cohort comparison on paired deltas (only when both UC and IBS are requested).
  if (nrow(within_tbl) && all(c("UC", "IBS") %in% cohorts_to_run)) {
    for (nm in unique(within_tbl$Variable)) {
      get_delta <- function(coh) {
        dd <- d[d$cohort == coh, , drop = FALSE]
        if (!nrow(dd)) return(numeric(0))
        keys <- unique(dd$pair_key)
        out <- c()
        for (k in keys) {
          sub <- dd[dd$pair_key == k, c("phase", nm), drop = FALSE]
          vb <- suppressWarnings(as.numeric(sub[sub$phase == "before", nm]))
          va <- suppressWarnings(as.numeric(sub[sub$phase == "after", nm]))
          if (length(vb) && length(va) && is.finite(vb[1]) && is.finite(va[1])) out <- c(out, va[1] - vb[1])
        }
        out
      }
      du <- get_delta("UC")
      di <- get_delta("IBS")
      if (length(du) < 3L || length(di) < 3L) next
      p <- tryCatch(stats::wilcox.test(du, di)$p.value, error = function(e) NA_real_)
      between_rows[[bidx]] <- data.frame(
        Variable = nm,
        UC_Delta = fmt_med_iqr(du),
        IBS_Delta = fmt_med_iqr(di),
        P_value = ifelse(is.finite(p), signif(p, 4), NA_real_),
        stringsAsFactors = FALSE
      )
      bidx <- bidx + 1L
    }
  }
  between_tbl <- if (length(between_rows)) dplyr::bind_rows(between_rows) else data.frame()

  list(
    baseline = base_tbl,
    within = within_tbl,
    between = between_tbl,
    meta = list(
      n_pairs = as.integer(n_pairs_total),
      design_type = "longitudinal",
      group_var = baseline_group_var %||% group_var,
      n_groups = length(unique(d$cohort[!is.na(d$cohort)])),
      analysis_note = "Longitudinal paired design detected: baseline (before), within-group change, and between-cohort delta tables."
    )
  )
}

run_clinical_systematic_summary <- function(session_id,
                                            source = "standalone",
                                            experiment = NULL,
                                            group_var = NULL,
                                            skip_high_cardinality = TRUE,
                                            max_levels = 20L,
                                            table_engine = "gtsummary",
                                            cohort_filter = NULL) {
  src <- tolower(trimws(as.character(source %||% "standalone")))
  if (identical(src, "experiment")) {
    if (is.null(experiment) || !nzchar(experiment)) stop("experiment is required when source='experiment'.")
    mae <- load_mae(session_id)
    empt <- .promote_to_empt(mae, experiment)
    sn <- as.character(colnames(empt))
    cd <- as.data.frame(SummarizedExperiment::colData(empt), stringsAsFactors = FALSE)
    if (is.null(rownames(cd)) || !length(rownames(cd))) rownames(cd) <- sn
    cd$primary <- rownames(cd)
  } else {
    cd <- .clin_read_external(session_id)
    if (is.null(cd) || !nrow(cd)) stop("No standalone clinical data found. Upload clinical data first.")
  }
  cd <- .clinical_filter_cd_by_cohorts(cd, cohort_filter = cohort_filter)
  .clinical_systematic_tables_from_df(
    cd = cd,
    group_var = group_var,
    skip_high_cardinality = skip_high_cardinality,
    max_levels = max_levels,
    table_engine = table_engine,
    cohort_filter = cohort_filter
  )
}

run_multiomics_clinical_joint <- function(session_id, exp_a, exp_b,
                                          traits = NULL,
                                          method = "spearman",
                                          top_n = 20L,
                                          clinical_source = "experiment") {
  if (is.null(exp_a) || !nzchar(exp_a) || is.null(exp_b) || !nzchar(exp_b)) {
    stop("exp_a and exp_b are required.")
  }
  ea <- get_empt_fresh(session_id, exp_a)
  eb <- get_empt_fresh(session_id, exp_b)
  xa <- SummarizedExperiment::assays(ea)[[1]]
  xb <- SummarizedExperiment::assays(eb)[[1]]
  if (is.null(xa) || is.null(xb)) stop("Assay matrix missing in selected experiments.")
  common_s <- intersect(colnames(xa), colnames(xb))
  if (length(common_s) < 5L) stop("Too few shared samples between selected experiments (need >= 5).")
  xa <- xa[, common_s, drop = FALSE]
  xb <- xb[, common_s, drop = FALSE]

  cd <- if (identical(clinical_source, "standalone")) {
    ext <- .clin_read_external(session_id)
    if (is.null(ext) || !nrow(ext)) stop("No standalone clinical data found.")
    ext
  } else {
    .clin_merge_external_cd(session_id, ea)
  }
  if (!"primary" %in% names(cd)) cd$primary <- rownames(cd)
  cd <- cd[!is.na(cd$primary), , drop = FALSE]
  rownames(cd) <- as.character(cd$primary)
  cd <- cd[common_s, , drop = FALSE]

  if (is.null(traits) || !length(traits)) {
    vc <- list_clinical_vars_standalone(session_id)
    if (!identical(clinical_source, "standalone")) {
      vc <- list_clinical_vars(session_id, exp_a)
    }
    traits <- vc$name[vc$type == "numeric"]
    if (length(traits) > 3) traits <- traits[1:3]
  }
  traits <- intersect(as.character(traits), names(cd))
  trait_map <- list()
  for (tn in traits) {
    v <- suppressWarnings(as.numeric(cd[[tn]]))
    if (sum(is.finite(v)) >= 5L) trait_map[[tn]] <- v
  }
  if (!length(trait_map)) {
    # Fallback: encode the first usable categorical trait to numeric codes.
    cat_cols <- names(cd)[sapply(cd, function(x) {
      ux <- unique(stats::na.omit(as.character(x)))
      length(ux) >= 2 && length(ux) <= 10
    })]
    cat_cols <- setdiff(cat_cols, "primary")
    if (length(cat_cols)) {
      tn <- cat_cols[1]
      v <- as.numeric(as.factor(as.character(cd[[tn]])))
      if (sum(is.finite(v)) >= 5L) trait_map[[paste0(tn, "_encoded")]] <- v
    }
  }
  if (!length(trait_map)) stop("No numeric clinical traits selected/found.")

  .safe_cor <- function(x, y, method = "spearman") {
    ok <- is.finite(x) & is.finite(y)
    if (sum(ok) < 5L) return(c(r = NA_real_, p = NA_real_, n = sum(ok)))
    ct <- tryCatch(stats::cor.test(x[ok], y[ok], method = method), error = function(e) NULL)
    if (is.null(ct)) return(c(r = NA_real_, p = NA_real_, n = sum(ok)))
    c(r = unname(ct$estimate), p = ct$p.value, n = sum(ok))
  }
  .top_trait <- function(mat, trait_vec, trait_name, exp_name) {
    m <- as.matrix(mat)
    out <- vector("list", nrow(m))
    for (i in seq_len(nrow(m))) {
      st <- .safe_cor(as.numeric(m[i, ]), trait_vec, method = method)
      out[[i]] <- data.frame(
        experiment = exp_name,
        feature = rownames(m)[i],
        trait = trait_name,
        r = as.numeric(st[["r"]]),
        p = as.numeric(st[["p"]]),
        n = as.integer(st[["n"]]),
        stringsAsFactors = FALSE
      )
    }
    df <- dplyr::bind_rows(out)
    df$abs_r <- abs(df$r)
    df <- df[order(-df$abs_r, df$p), , drop = FALSE]
    utils::head(df, as.integer(top_n))
  }

  all_top_a <- list(); all_top_b <- list()
  for (tn in names(trait_map)) {
    tv <- trait_map[[tn]]
    all_top_a[[tn]] <- .top_trait(xa, tv, tn, exp_a)
    all_top_b[[tn]] <- .top_trait(xb, tv, tn, exp_b)
  }
  top_a <- dplyr::bind_rows(all_top_a)
  top_b <- dplyr::bind_rows(all_top_b)
  feats_a <- unique(top_a$feature)
  feats_b <- unique(top_b$feature)
  if (!length(feats_a) || !length(feats_b)) {
    return(list(top_a = top_a, top_b = top_b, edges = data.frame()))
  }
  xa2 <- as.matrix(xa[feats_a, , drop = FALSE])
  xb2 <- as.matrix(xb[feats_b, , drop = FALSE])
  edges <- list(); idx <- 1L
  for (fa in rownames(xa2)) {
    for (fb in rownames(xb2)) {
      st <- .safe_cor(as.numeric(xa2[fa, ]), as.numeric(xb2[fb, ]), method = method)
      edges[[idx]] <- data.frame(
        feature_a = fa, feature_b = fb,
        r = as.numeric(st[["r"]]), p = as.numeric(st[["p"]]), n = as.integer(st[["n"]]),
        stringsAsFactors = FALSE
      )
      idx <- idx + 1L
    }
  }
  edge_df <- dplyr::bind_rows(edges)
  edge_df$abs_r <- abs(edge_df$r)
  edge_df <- edge_df[order(-edge_df$abs_r, edge_df$p), , drop = FALSE]
  edge_df <- utils::head(edge_df, as.integer(top_n * 5L))

  list(
    top_a = top_a,
    top_b = top_b,
    edges = edge_df
  )
}

.clinical_binary_metrics <- function(y_true, score, positive_class = NULL) {
  y <- as.character(y_true)
  if (is.null(positive_class) || !nzchar(positive_class)) {
    lv <- unique(stats::na.omit(y))
    positive_class <- if (length(lv) >= 2L) lv[2] else lv[1]
  }
  ok <- !is.na(y) & is.finite(score)
  y <- y[ok]
  score <- as.numeric(score[ok])
  if (length(unique(y)) != 2L || length(score) < 4L) {
    return(list(auc = NA_real_, cutoff = NA_real_, sensitivity = NA_real_,
                specificity = NA_real_, n = length(score), positive_class = positive_class))
  }
  truth <- y == positive_class
  pos <- score[truth]
  neg <- score[!truth]
  if (!length(pos) || !length(neg)) {
    return(list(auc = NA_real_, cutoff = NA_real_, sensitivity = NA_real_,
                specificity = NA_real_, n = length(score), positive_class = positive_class))
  }
  auc <- (sum(rank(c(pos, neg))[seq_along(pos)]) - length(pos) * (length(pos) + 1) / 2) /
    (length(pos) * length(neg))
  if (auc < 0.5) {
    score <- -score
    auc <- 1 - auc
  }
  cuts <- sort(unique(score), decreasing = TRUE)
  best <- data.frame(cutoff = NA_real_, sensitivity = NA_real_, specificity = NA_real_, youden = -Inf)
  for (ct in cuts) {
    pred <- score >= ct
    sens <- sum(pred & truth) / sum(truth)
    spec <- sum(!pred & !truth) / sum(!truth)
    yd <- sens + spec - 1
    if (is.finite(yd) && yd > best$youden[1]) {
      best <- data.frame(cutoff = ct, sensitivity = sens, specificity = spec, youden = yd)
    }
  }
  list(
    auc = as.numeric(auc),
    cutoff = as.numeric(best$cutoff[1]),
    sensitivity = as.numeric(best$sensitivity[1]),
    specificity = as.numeric(best$specificity[1]),
    n = length(score),
    positive_class = positive_class
  )
}

.clinical_marker_build_matrix <- function(session_id, experiments,
                                          clinical_source = "experiment",
                                          include_clinical_numeric = TRUE,
                                          max_features_per_omics = 200L) {
  experiments <- unique(stats::na.omit(trimws(as.character(experiments))))
  experiments <- experiments[nzchar(experiments)]
  if (!length(experiments)) stop("Select at least one omics experiment.")

  mats <- list()
  common_s <- NULL
  first_empt <- NULL
  for (exp in experiments) {
    empt <- get_empt_fresh(session_id, exp)
    if (is.null(first_empt)) first_empt <- empt
    ad <- SummarizedExperiment::assays(empt)[[1]]
    if (is.null(ad) || !nrow(ad) || !ncol(ad)) next
    m <- as.matrix(ad)
    storage.mode(m) <- "numeric"
    m[!is.finite(m)] <- NA_real_
    vars <- apply(m, 1L, stats::var, na.rm = TRUE)
    vars[!is.finite(vars)] <- 0
    keep_n <- max(1L, min(as.integer(max_features_per_omics), length(vars)))
    keep <- names(sort(vars, decreasing = TRUE))[seq_len(keep_n)]
    m <- m[keep, , drop = FALSE]
    rownames(m) <- paste0(make.names(exp), "::", make.names(rownames(m), unique = TRUE))
    mats[[exp]] <- m
    common_s <- if (is.null(common_s)) colnames(m) else intersect(common_s, colnames(m))
  }
  if (!length(mats)) stop("No usable omics matrices found.")
  if (length(common_s) < 6L) stop("Too few shared samples across selected omics experiments (need >= 6).")

  X <- do.call(cbind, lapply(mats, function(m) t(m[, common_s, drop = FALSE])))
  X <- as.matrix(X)
  rownames(X) <- common_s
  X[!is.finite(X)] <- NA_real_
  for (j in seq_len(ncol(X))) {
    v <- X[, j]
    med <- stats::median(v, na.rm = TRUE)
    if (!is.finite(med)) med <- 0
    v[!is.finite(v)] <- med
    sdv <- stats::sd(v)
    X[, j] <- if (is.finite(sdv) && sdv > 0) (v - mean(v)) / sdv else 0
  }

  cd <- if (identical(tolower(clinical_source), "standalone")) {
    ext <- .clin_read_external(session_id)
    if (is.null(ext) || !nrow(ext)) stop("No standalone clinical data found.")
    ext
  } else {
    .clin_merge_external_cd(session_id, first_empt)
  }
  if (!"primary" %in% names(cd)) cd$primary <- rownames(cd)
  idx <- match(.clin_norm_id(common_s), .clin_norm_id(cd$primary))
  ok <- !is.na(idx)
  if (sum(ok) < 6L) stop("Too few samples could be matched between omics and clinical metadata.")
  X <- X[ok, , drop = FALSE]
  cd <- cd[idx[ok], , drop = FALSE]
  rownames(cd) <- rownames(X)

  if (isTRUE(include_clinical_numeric)) {
    num_cols <- setdiff(names(cd)[sapply(cd, function(v) {
      vv <- suppressWarnings(as.numeric(v))
      sum(is.finite(vv)) >= max(4L, floor(0.2 * nrow(cd)))
    })], c("primary", "SampleID", "sampleID", "Sample"))
    if (length(num_cols)) {
      clin <- sapply(num_cols, function(nm) suppressWarnings(as.numeric(cd[[nm]])))
      clin <- as.matrix(clin)
      colnames(clin) <- paste0("Clinical::", make.names(num_cols, unique = TRUE))
      for (j in seq_len(ncol(clin))) {
        v <- clin[, j]
        med <- stats::median(v, na.rm = TRUE)
        if (!is.finite(med)) med <- 0
        v[!is.finite(v)] <- med
        sdv <- stats::sd(v)
        clin[, j] <- if (is.finite(sdv) && sdv > 0) (v - mean(v)) / sdv else 0
      }
      X <- cbind(X, clin)
    }
  }
  list(X = X, clinical = cd, experiments = experiments)
}

.clinical_train_test_split <- function(y, validation_fraction = 0.3, seed = 123L) {
  set.seed(as.integer(seed %||% 123L))
  y <- as.factor(y)
  n <- length(y)
  vf <- suppressWarnings(as.numeric(validation_fraction %||% 0.3))
  if (!is.finite(vf) || vf <= 0 || vf >= 0.8 || n < 12L || any(table(y) < 4L)) {
    return(list(train = seq_len(n), test = integer(0), validation = "apparent"))
  }
  test <- unlist(lapply(split(seq_len(n), y), function(idx) {
    ns <- max(1L, floor(length(idx) * vf))
    sample(idx, ns)
  }), use.names = FALSE)
  train <- setdiff(seq_len(n), test)
  if (length(unique(y[train])) < 2L || length(unique(y[test])) < 2L) {
    return(list(train = seq_len(n), test = integer(0), validation = "apparent"))
  }
  list(train = train, test = test, validation = "holdout")
}

run_clinical_marker_model <- function(session_id, experiments, outcome_var,
                                      positive_class = NULL,
                                      methods = c("randomForest", "lasso", "xgboost"),
                                      clinical_source = "experiment",
                                      include_clinical_numeric = TRUE,
                                      max_features_per_omics = 200L,
                                      top_n = 30L,
                                      validation_fraction = 0.3,
                                      seed = 123L) {
  built <- .clinical_marker_build_matrix(
    session_id = session_id,
    experiments = experiments,
    clinical_source = clinical_source,
    include_clinical_numeric = include_clinical_numeric,
    max_features_per_omics = max_features_per_omics
  )
  X <- built$X
  cd <- built$clinical
  if (is.null(outcome_var) || !nzchar(outcome_var) || !outcome_var %in% names(cd)) {
    cats <- names(cd)[sapply(cd, function(v) {
      ux <- unique(stats::na.omit(as.character(v)))
      length(ux) == 2L
    })]
    cats <- setdiff(cats, c("primary", "SampleID", "sampleID", "Sample"))
    if (!length(cats)) stop("Select a binary clinical outcome variable.")
    outcome_var <- cats[1]
  }
  y <- as.character(cd[[outcome_var]])
  ok <- !is.na(y) & nzchar(y)
  X <- X[ok, , drop = FALSE]
  cd <- cd[ok, , drop = FALSE]
  y <- y[ok]
  y <- as.factor(y)
  if (length(levels(y)) != 2L) stop("Outcome variable must have exactly 2 classes.")
  if (is.null(positive_class) || !nzchar(positive_class) || !positive_class %in% levels(y)) {
    positive_class <- levels(y)[2]
  }
  y <- stats::relevel(y, ref = setdiff(levels(y), positive_class)[1])

  split <- .clinical_train_test_split(y, validation_fraction = validation_fraction, seed = seed)
  train <- split$train
  test <- split$test
  eval_idx <- if (length(test)) test else train
  methods <- unique(tolower(trimws(as.character(methods))))
  methods <- methods[nzchar(methods)]
  if (!length(methods)) methods <- c("randomforest")

  performance <- list()
  marker_rows <- list()
  score_rows <- list()
  pidx <- 1L
  midx <- 1L
  sidx <- 1L

  add_perf <- function(method, score, status = "ok", message = "") {
    mm <- .clinical_binary_metrics(y[eval_idx], score[eval_idx], positive_class = positive_class)
    performance[[pidx]] <<- data.frame(
      model = method,
      validation = split$validation,
      outcome = outcome_var,
      positive_class = positive_class,
      n_total = length(y),
      n_train = length(train),
      n_test = length(test),
      auc = signif(mm$auc, 4),
      auc_gt_0_8 = is.finite(mm$auc) && mm$auc > 0.8,
      cutoff = signif(mm$cutoff, 4),
      sensitivity = signif(mm$sensitivity, 4),
      specificity = signif(mm$specificity, 4),
      model_type = ifelse(grepl("^single:", method), "single_marker", "multi_marker"),
      independent_validation = FALSE,
      validation_note = ifelse(identical(split$validation, "holdout"),
                               "Internal stratified holdout; external validation cohort not supplied.",
                               "Apparent performance; sample size was too small for holdout."),
      status = status,
      message = message,
      stringsAsFactors = FALSE
    )
    pidx <<- pidx + 1L
  }

  # Single-indicator ROC screen for the top variance-filtered features.
  assoc <- apply(X, 2L, function(v) {
    mm <- .clinical_binary_metrics(y, as.numeric(v), positive_class = positive_class)
    mm$auc
  })
  assoc[!is.finite(assoc)] <- NA_real_
  ord <- order(abs(assoc - 0.5), decreasing = TRUE, na.last = NA)
  ord <- utils::head(ord, as.integer(top_n))
  for (j in ord) {
    nm <- colnames(X)[j]
    score <- as.numeric(X[, j])
    mm <- .clinical_binary_metrics(y[eval_idx], score[eval_idx], positive_class = positive_class)
    marker_rows[[midx]] <- data.frame(
      model = "single_marker",
      feature = nm,
      importance = abs(assoc[j] - 0.5),
      auc = signif(mm$auc, 4),
      cutoff = signif(mm$cutoff, 4),
      sensitivity = signif(mm$sensitivity, 4),
      specificity = signif(mm$specificity, 4),
      stringsAsFactors = FALSE
    )
    midx <- midx + 1L
  }

  fit_methods <- list(
    randomforest = function() {
      if (!requireNamespace("randomForest", quietly = TRUE)) stop("Package 'randomForest' is required.")
      fit <- randomForest::randomForest(x = X[train, , drop = FALSE], y = y[train], importance = TRUE)
      prob <- stats::predict(fit, X, type = "prob")[, positive_class]
      imp <- randomForest::importance(fit, type = 1)
      importance <- if (is.null(dim(imp))) as.numeric(imp) else as.numeric(imp[, 1])
      names(importance) <- if (is.null(dim(imp))) names(imp) else rownames(imp)
      list(score = prob, importance = importance)
    },
    lasso = function() {
      if (!requireNamespace("glmnet", quietly = TRUE)) stop("Package 'glmnet' is required.")
      nfolds <- max(2L, min(5L, as.integer(min(table(y[train]))), length(train)))
      fit <- glmnet::cv.glmnet(X[train, , drop = FALSE], y[train], family = "binomial", alpha = 1, nfolds = nfolds)
      prob <- as.numeric(stats::predict(fit, X, s = "lambda.min", type = "response"))
      cf <- as.matrix(stats::coef(fit, s = "lambda.min"))
      importance <- abs(as.numeric(cf[, 1]))
      names(importance) <- rownames(cf)
      importance <- importance[names(importance) != "(Intercept)"]
      list(score = prob, importance = importance)
    },
    xgboost = function() {
      if (!requireNamespace("xgboost", quietly = TRUE)) stop("Package 'xgboost' is required.")
      label <- as.integer(y == positive_class)
      dtrain <- xgboost::xgb.DMatrix(data = X[train, , drop = FALSE], label = label[train])
      fit <- xgboost::xgb.train(
        params = list(objective = "binary:logistic", eval_metric = "auc", eta = 0.08, max_depth = 3),
        data = dtrain,
        nrounds = 80,
        verbose = 0
      )
      prob <- stats::predict(fit, xgboost::xgb.DMatrix(data = X))
      imp <- xgboost::xgb.importance(model = fit, feature_names = colnames(X))
      importance <- if (!is.null(imp) && nrow(imp)) stats::setNames(imp$Gain, imp$Feature) else numeric(0)
      list(score = prob, importance = importance)
    }
  )

  for (m in methods) {
    key <- if (m %in% c("rf", "randomforest", "random_forest")) "randomforest" else if (m %in% c("xgb", "xgboost")) "xgboost" else m
    label <- if (identical(key, "randomforest")) "randomForest" else key
    if (is.null(fit_methods[[key]])) next
    fit_out <- tryCatch(fit_methods[[key]](), error = function(e) e)
    if (inherits(fit_out, "error")) {
      performance[[pidx]] <- data.frame(
        model = label, validation = split$validation, outcome = outcome_var,
        positive_class = positive_class, n_total = length(y), n_train = length(train),
        n_test = length(test), auc = NA_real_, auc_gt_0_8 = FALSE, cutoff = NA_real_,
        sensitivity = NA_real_, specificity = NA_real_, model_type = "multi_marker",
        independent_validation = FALSE,
        validation_note = "Model failed before validation metrics could be computed.",
        status = "error", message = conditionMessage(fit_out), stringsAsFactors = FALSE
      )
      pidx <- pidx + 1L
      next
    }
    add_perf(label, fit_out$score)
    imp <- sort(fit_out$importance, decreasing = TRUE)
    imp <- imp[is.finite(imp) & imp > 0]
    for (nm in names(utils::head(imp, as.integer(top_n)))) {
      marker_rows[[midx]] <- data.frame(
        model = label, feature = nm, importance = as.numeric(imp[[nm]]),
        auc = NA_real_, cutoff = NA_real_, sensitivity = NA_real_, specificity = NA_real_,
        stringsAsFactors = FALSE
      )
      midx <- midx + 1L
    }
    score_rows[[sidx]] <- data.frame(
      sample = rownames(X),
      outcome = as.character(y),
      model = label,
      risk_score = as.numeric(fit_out$score),
      data_split = ifelse(seq_along(y) %in% test, "test", "train"),
      stringsAsFactors = FALSE
    )
    sidx <- sidx + 1L
  }

  list(
    performance = if (length(performance)) do.call(rbind, performance) else data.frame(),
    markers = if (length(marker_rows)) do.call(rbind, marker_rows) else data.frame(),
    sample_scores = if (length(score_rows)) do.call(rbind, score_rows) else data.frame(),
    meta = list(
      experiments = built$experiments,
      n_samples = length(y),
      n_features = ncol(X),
      outcome = outcome_var,
      positive_class = positive_class,
      validation = split$validation
    )
  )
}

# ---------------------------------------------------------------------------
# Internal: coerce one colData column to a numeric vector, aligning with the
# rownames of the assay matrix.  Silently drops samples where the value is
# not parseable (e.g. "NA", "").
# ---------------------------------------------------------------------------
.clin_numeric_col <- function(cd, var) {
  if (!var %in% names(cd)) stop("Clinical variable '", var, "' not found.")
  v <- cd[[var]]
  if (is.factor(v)) v <- as.character(v)
  suppressWarnings(as.numeric(v))
}

# ---------------------------------------------------------------------------
# run_clinical_cor(session_id, experiment, traits, method, top_n_features,
#                   p_adjust, on_progress = NULL)
#
# For each numeric trait, correlate every feature's expression/abundance
# against the trait across samples.  Uses `psych::corr.test()` which is
# fast & vectorised.
#
# Inputs:
#   traits         : character; one or more numeric colData columns
#   method         : "spearman" | "pearson" | "kendall"
#   top_n_features : integer; after correlating all features we keep the
#                    `top_n_features` features with smallest |min p-value|
#                    across the selected traits (0 = keep all)
#   p_adjust       : "none" | "BH" | "holm" | "bonferroni" (default "BH")
#
# Returns: list(
#   table   = long data.frame: feature, trait, r, p, p_adj
#   png     = base64 heatmap of r (only traits × top features), NA if small
#   pdf     = path to the heatmap PDF, or NULL
#   n_feat  = number of features tested
#   n_samp  = number of samples with complete data
# )
# ---------------------------------------------------------------------------
run_clinical_cor <- function(session_id, experiment, traits,
                              method = "spearman",
                              top_n_features = 30L,
                              p_adjust = "BH",
                              clinical_source = "experiment",
                              pdf_path = NULL,
                              on_progress = NULL) {
  bump <- function(p, m) {
    if (!is.null(on_progress) && is.function(on_progress))
      tryCatch(on_progress(p, m), error = function(e) NULL)
  }
  bump(2, "Loading experiment")
  empt <- get_empt_fresh(session_id, experiment)
  ad <- SummarizedExperiment::assays(empt)[[1]]
  source_key <- tolower(trimws(as.character(clinical_source %||% "experiment")))
  cd <- if (identical(source_key, "standalone")) {
    ext <- .clin_read_external(session_id)
    if (is.null(ext) || !nrow(ext)) stop("No standalone clinical data found.")
    if (!"primary" %in% names(ext)) ext$primary <- rownames(ext)
    rownames(ext) <- as.character(ext$primary)
    ext
  } else {
    .clin_merge_external_cd(session_id, empt)
  }

  if (length(traits) == 0) stop("Select at least one numeric clinical variable.")
  missing <- setdiff(traits, names(cd))
  if (length(missing)) stop("Trait(s) not found: ", paste(missing, collapse = ", "))

  # Align samples present in both the assay and the clinical matrix, then
  # restrict to the rows that have at least one finite trait value.
  trait_mat <- do.call(cbind, lapply(traits, function(tn) .clin_numeric_col(cd, tn)))
  colnames(trait_mat) <- traits
  rownames(trait_mat) <- rownames(cd)
  common_s <- intersect(colnames(ad), rownames(trait_mat))
  trait_mat <- trait_mat[common_s, , drop = FALSE]
  keep_s <- which(rowSums(is.finite(trait_mat)) >= 1L)
  if (length(keep_s) < 5) {
    stop("Fewer than 5 samples have a numeric value for the selected trait(s).")
  }
  trait_mat <- trait_mat[keep_s, , drop = FALSE]
  ad_sub <- ad[, rownames(trait_mat), drop = FALSE]

  # Drop features with no variance (kills corr.test warnings).
  rv <- matrixStats::rowVars(as.matrix(ad_sub), na.rm = TRUE)
  rv[is.na(rv)] <- 0
  ad_sub <- ad_sub[rv > 0, , drop = FALSE]
  n_feat <- nrow(ad_sub)
  if (!n_feat) stop("No features with variance across the selected samples.")

  bump(20, paste0("Correlating ", n_feat, " features × ",
                   length(traits), " trait(s)"))
  if (!requireNamespace("psych", quietly = TRUE)) {
    stop("Package 'psych' is required for clinical correlation.")
  }

  # psych::corr.test handles NA via "pairwise.complete.obs" automatically.
  ct <- suppressWarnings(
    psych::corr.test(
      x      = t(as.matrix(ad_sub)),        # samples × features
      y      = trait_mat,                   # samples × traits
      method = method,
      adjust = "none"                        # we adjust ourselves below
    )
  )
  r_mat <- ct$r; p_mat <- ct$p
  if (is.null(r_mat) || is.null(p_mat)) stop("Correlation produced no results.")

  # Long table.
  long <- data.frame(
    feature = rep(rownames(r_mat), times = ncol(r_mat)),
    trait   = rep(colnames(r_mat), each  = nrow(r_mat)),
    r       = as.numeric(r_mat),
    p       = as.numeric(p_mat),
    stringsAsFactors = FALSE
  )
  long$p <- suppressWarnings(as.numeric(long$p))
  long$p_adj <- stats::p.adjust(long$p, method = if (is.null(p_adjust)) "BH" else p_adjust)
  long <- long[order(long$p), , drop = FALSE]
  bump(55, "Selecting top features")

  # Pick top_n_features by *smallest min-p-adj across traits* for heatmap.
  if (!is.finite(top_n_features) || top_n_features <= 0) {
    top_feats <- unique(long$feature)
  } else {
    fmin <- tapply(long$p, long$feature, function(x) suppressWarnings(min(x, na.rm = TRUE)))
    fmin <- sort(fmin)
    top_feats <- names(fmin)[seq_len(min(as.integer(top_n_features), length(fmin)))]
  }
  r_top <- r_mat[top_feats, , drop = FALSE]
  p_top <- p_mat[top_feats, , drop = FALSE]

  # Render a pheatmap (traits as columns, features as rows).
  png_b64 <- NA_character_
  pdf_out <- NULL
  if (nrow(r_top) >= 2 && ncol(r_top) >= 1 &&
      requireNamespace("pheatmap", quietly = TRUE)) {
    bump(75, "Drawing heatmap")
    # Annotate cells with '*'/'**'/'***' for significance.
    star <- matrix("", nrow = nrow(p_top), ncol = ncol(p_top),
                   dimnames = dimnames(p_top))
    star[p_top <= 0.05]  <- "*"
    star[p_top <= 0.01]  <- "**"
    star[p_top <= 0.001] <- "***"

    # Auto-size (same formula as DEG heatmap).
    cell_h <- if (nrow(r_top) <= 60) 12 else if (nrow(r_top) <= 120) 8 else 6
    cell_w <- 28
    body_w_in <- ncol(r_top) * cell_w / 72
    body_h_in <- nrow(r_top) * cell_h / 72
    auto_w <- max(6, min(18, body_w_in + 4.5))
    auto_h <- max(5, min(32, body_h_in + 2.8))

    ph <- pheatmap::pheatmap(
      r_top,
      scale           = "none",
      color           = grDevices::colorRampPalette(c("#2166ac", "white", "#b2182b"))(256),
      breaks          = seq(-1, 1, length.out = 257),
      display_numbers = star,
      number_color    = "black",
      fontsize_number = 10,
      cluster_rows    = nrow(r_top) > 2,
      cluster_cols    = ncol(r_top) > 2,
      cellwidth       = cell_w,
      cellheight      = cell_h,
      border_color    = NA,
      fontsize        = 10,
      fontsize_row    = if (nrow(r_top) <= 80) 8 else 6,
      fontsize_col    = 10,
      main            = paste0("Feature × Trait correlation (", method, ")\n",
                                 "* p<=0.05   ** p<=0.01   *** p<=0.001"),
      silent          = TRUE
    )

    if (!is.null(pdf_path) && nzchar(pdf_path)) {
      tryCatch(save_plot_pdf(ph, pdf_path, width = auto_w, height = auto_h),
               error = function(e) message("[clinical_cor] PDF write failed: ",
                                            conditionMessage(e)))
      pdf_out <- pdf_path
    }
    png_b64 <- tryCatch({
      tmp <- tempfile(fileext = ".png"); on.exit(if (file.exists(tmp)) file.remove(tmp))
      if (requireNamespace("ragg", quietly = TRUE)) {
        ragg::agg_png(tmp, width = auto_w, height = auto_h,
                       units = "in", res = 300, background = "white")
      } else {
        grDevices::png(tmp, width = auto_w, height = auto_h, units = "in",
                        res = 300, bg = "white",
                        type = if (.Platform$OS.type == "windows") "windows" else "cairo")
      }
      grid::grid.newpage(); grid::grid.draw(ph$gtable); grDevices::dev.off()
      base64enc::base64encode(tmp)
    }, error = function(e) NA_character_)
  }

  bump(100, "Done")
  list(
    table  = long,
    png    = png_b64,
    pdf    = pdf_out,
    n_feat = n_feat,
    n_samp = nrow(trait_mat),
    method = method,
    p_adjust = p_adjust %||% "BH"
  )
}

# ---------------------------------------------------------------------------
# make_fitline_scatter(session_id, experiment, feature, trait,
#                       group = NULL, method = "lm", log_y = FALSE)
#
# Scatter of one feature (assay row) against one numeric trait, with
# per-group regression lines (if group is provided) or a single line.
# Returns list(png, pdf, r, p, n).
# ---------------------------------------------------------------------------
make_fitline_scatter <- function(session_id, experiment, feature, trait,
                                  group = NULL, method = "lm",
                                  log_y = FALSE, clinical_source = "experiment",
                                  pdf_path = NULL,
                                  width = NA_real_, height = NA_real_) {
  empt <- get_empt_fresh(session_id, experiment)
  ad <- SummarizedExperiment::assays(empt)[[1]]
  source_key <- tolower(trimws(as.character(clinical_source %||% "experiment")))
  cd <- if (identical(source_key, "standalone")) {
    ext <- .clin_read_external(session_id)
    if (is.null(ext) || !nrow(ext)) stop("No standalone clinical data found.")
    if (!"primary" %in% names(ext)) ext$primary <- rownames(ext)
    rownames(ext) <- as.character(ext$primary)
    ext
  } else {
    .clin_merge_external_cd(session_id, empt)
  }

  if (is.null(feature) || !nzchar(feature))
    stop("Select a feature (gene / taxon / metabolite).")
  if (is.null(trait) || !nzchar(trait))
    stop("Select a numeric clinical variable.")
  if (!feature %in% rownames(ad)) stop("Feature '", feature, "' not found in assay.")
  if (!trait %in% names(cd))      stop("Trait '", trait, "' not found in colData.")
  common_s <- intersect(colnames(ad), rownames(cd))
  if (length(common_s) < 4) stop("Fewer than 4 samples overlap between assay and clinical table.")
  ad <- ad[, common_s, drop = FALSE]
  cd <- cd[common_s, , drop = FALSE]

  y <- as.numeric(ad[feature, ])
  x <- .clin_numeric_col(cd, trait)
  keep <- is.finite(x) & is.finite(y)
  df <- data.frame(
    trait   = x[keep],
    feature = y[keep],
    sample  = colnames(ad)[keep],
    stringsAsFactors = FALSE
  )
  if (!is.null(group) && nzchar(group) && group %in% names(cd)) {
    df$group <- as.character(cd[[group]])[keep]
    df <- df[!is.na(df$group) & nzchar(df$group), , drop = FALSE]
  } else {
    df$group <- "all"
  }
  if (nrow(df) < 4) stop("Fewer than 4 samples have both feature + trait values.")
  if (isTRUE(log_y)) df$feature <- log1p(df$feature)

  # Overall correlation for the caption.
  ct <- tryCatch(stats::cor.test(df$trait, df$feature, method = "spearman"),
                  error = function(e) NULL)
  r_val <- if (!is.null(ct)) unname(ct$estimate) else NA_real_
  p_val <- if (!is.null(ct)) ct$p.value          else NA_real_

  p <- ggplot2::ggplot(df, ggplot2::aes(x = trait, y = feature)) +
    ggplot2::geom_point(ggplot2::aes(color = group), size = 2.2, alpha = 0.85) +
    ggplot2::geom_smooth(ggplot2::aes(color = group, fill = group),
                          method = method, formula = y ~ x, se = TRUE, alpha = 0.15) +
    ggplot2::labs(
      title    = paste0(feature, "  ~  ", trait),
      subtitle = sprintf("Spearman  r = %.2f    p = %.2e    n = %d",
                          r_val, p_val, nrow(df)),
      x = trait, y = if (isTRUE(log_y)) paste0("log1p(", feature, ")") else feature,
      color = if (length(unique(df$group)) > 1) "Group" else NULL,
      fill  = if (length(unique(df$group)) > 1) "Group" else NULL
    ) +
    emp_pub_theme()
  if (length(unique(df$group)) > 1) {
    pal <- emp_pub_palette(length(unique(df$group)))
    p <- p + ggplot2::scale_color_manual(values = pal) +
             ggplot2::scale_fill_manual(values  = pal)
  } else {
    p <- p + ggplot2::scale_color_manual(values = c("all" = "#3182bd")) +
             ggplot2::scale_fill_manual(values  = c("all" = "#3182bd")) +
             ggplot2::guides(color = "none", fill = "none")
  }

  if (!is.finite(width))  width  <- 7
  if (!is.finite(height)) height <- 5.5

  pdf_out <- NULL
  if (!is.null(pdf_path) && nzchar(pdf_path)) {
    tryCatch({ grDevices::pdf(pdf_path, width = width, height = height); print(p); grDevices::dev.off() },
             error = function(e) message("[fitline] PDF write failed: ", conditionMessage(e)))
    pdf_out <- pdf_path
  }
  png_b64 <- plot_to_base64(p, width = width, height = height)
  list(
    png = png_b64, pdf = pdf_out, r = r_val, p = p_val, n = nrow(df),
    group_used = (length(unique(df$group)) > 1)
  )
}

# ---------------------------------------------------------------------------
# run_clinical_wgcna(session_id, experiment, traits, soft_power = "auto",
#                     min_module_size = 30, on_progress = NULL)
#
# WGCNA module–trait correlation:
#   1. EMP_WGCNA_cluster_analysis  → feature modules (coloured)
#   2. EMP_WGCNA_cor_analysis      → module-eigengene × trait correlation
#   3. Render the canonical module × trait heatmap with R / p cells.
#
# WGCNA is slow (~1–5 min on bulk RNAseq); this is async-friendly and reports
# progress via on_progress(pct, msg).
# ---------------------------------------------------------------------------
run_clinical_wgcna <- function(session_id, experiment, traits = NULL,
                                soft_power = "auto", min_module_size = 30L,
                                clinical_source = "experiment",
                                pdf_path = NULL, on_progress = NULL) {
  bump <- function(p, m) {
    if (!is.null(on_progress) && is.function(on_progress))
      tryCatch(on_progress(p, m), error = function(e) NULL)
  }
  if (!requireNamespace("WGCNA", quietly = TRUE)) {
    stop("R package 'WGCNA' is not installed. Run:  ",
         "BiocManager::install('WGCNA')  on the server.")
  }
  bump(2, "Loading experiment")
  empt <- get_empt_fresh(session_id, experiment)
  source_key <- tolower(trimws(as.character(clinical_source %||% "experiment")))
  if (identical(source_key, "standalone")) {
    ext <- .clin_read_external(session_id)
    if (!is.null(ext) && nrow(ext)) {
      if (!"primary" %in% names(ext)) ext$primary <- rownames(ext)
      rownames(ext) <- as.character(ext$primary)
      sn <- colnames(empt)
      idx <- match(.clin_norm_id(sn), .clin_norm_id(rownames(ext)))
      ok <- which(!is.na(idx))
      if (length(ok)) {
        cd <- as.data.frame(SummarizedExperiment::colData(empt), stringsAsFactors = FALSE)
        if (!nrow(cd)) cd <- data.frame(row.names = sn, stringsAsFactors = FALSE)
        if (is.null(rownames(cd)) || !length(rownames(cd))) rownames(cd) <- sn
        hit <- ext[idx[ok], , drop = FALSE]
        rownames(hit) <- sn[ok]
        for (nm in setdiff(names(hit), "primary")) {
          vals <- rep(NA_character_, length(sn))
          vals[ok] <- as.character(hit[[nm]])
          cd[[nm]] <- vals
        }
        SummarizedExperiment::colData(empt) <- S4Vectors::DataFrame(cd)
      }
    }
  }

  # Drop near-zero-variance features to keep WGCNA manageable.
  ad <- SummarizedExperiment::assays(empt)[[1]]
  rv <- matrixStats::rowVars(as.matrix(ad), na.rm = TRUE)
  rv[is.na(rv)] <- 0
  keep <- order(-rv)[seq_len(min(5000L, length(rv)))]
  empt_sub <- empt[keep, ]

  bump(10, paste0("Running WGCNA clustering on top ", length(keep), " features"))
  # Ignore the EMPT's cached analysis class via get_empt_fresh.
  empt_wg <- empt_sub |> EasyMultiProfiler::EMP_WGCNA_cluster_analysis(
    RsquaredCut = 0.85
  )
  bump(55, "Correlating modules with clinical traits")
  empt_wg <- empt_wg |> EasyMultiProfiler::EMP_WGCNA_cor_analysis(method = "pearson")

  # EMP stashes the result on @deposit_append$WGCNA_cor_result; the public
  # EMP_result(info=...) wrapper doesn't expose it reliably across versions,
  # so read the slot directly.
  wg <- tryCatch(empt_wg@deposit_append[["WGCNA_cor_result"]],
                 error = function(e) NULL)
  if (is.null(wg) || is.null(wg$correlation) || !nrow(wg$correlation)) {
    stop("WGCNA returned no correlation matrix; ",
         "check trait and sample counts (need \u2265 8 samples with ",
         "non-NA values per trait).")
  }
  R  <- wg$correlation
  P  <- wg$pvalue
  if (!is.null(traits) && length(traits) && all(traits %in% rownames(R))) {
    R <- R[traits, , drop = FALSE]; P <- P[traits, , drop = FALSE]
  }

  # Heatmap: traits (rows) × modules (cols).
  bump(80, "Drawing module–trait heatmap")
  star <- matrix("", nrow = nrow(P), ncol = ncol(P), dimnames = dimnames(P))
  star[P <= 0.05]  <- "*"
  star[P <= 0.01]  <- "**"
  star[P <= 0.001] <- "***"
  cell_h <- 22
  cell_w <- 28
  auto_w <- max(7,  min(22, ncol(R) * cell_w / 72 + 3.5))
  auto_h <- max(4.5, min(18, nrow(R) * cell_h / 72 + 2.5))
  ph <- pheatmap::pheatmap(
    R,
    scale           = "none",
    color           = grDevices::colorRampPalette(c("#2166ac", "white", "#b2182b"))(256),
    breaks          = seq(-1, 1, length.out = 257),
    display_numbers = star,
    number_color    = "black",
    fontsize_number = 11,
    cluster_rows    = nrow(R) > 2,
    cluster_cols    = ncol(R) > 2,
    cellwidth       = cell_w, cellheight = cell_h,
    border_color    = NA,
    fontsize        = 10,
    main            = paste0("WGCNA module × trait correlation (Pearson)\n",
                              "* p<=0.05   ** p<=0.01   *** p<=0.001"),
    silent          = TRUE
  )
  pdf_out <- NULL
  if (!is.null(pdf_path) && nzchar(pdf_path)) {
    tryCatch(save_plot_pdf(ph, pdf_path, width = auto_w, height = auto_h),
             error = function(e) message("[wgcna] PDF write failed: ", conditionMessage(e)))
    pdf_out <- pdf_path
  }
  png_b64 <- tryCatch({
    tmp <- tempfile(fileext = ".png"); on.exit(if (file.exists(tmp)) file.remove(tmp))
    if (requireNamespace("ragg", quietly = TRUE)) {
      ragg::agg_png(tmp, width = auto_w, height = auto_h, units = "in", res = 300,
                     background = "white")
    } else {
      grDevices::png(tmp, width = auto_w, height = auto_h, units = "in",
                      res = 300, bg = "white",
                      type = if (.Platform$OS.type == "windows") "windows" else "cairo")
    }
    grid::grid.newpage(); grid::grid.draw(ph$gtable); grDevices::dev.off()
    base64enc::base64encode(tmp)
  }, error = function(e) NA_character_)

  # Long table of module–trait associations.
  long <- data.frame(
    trait  = rep(rownames(R), times = ncol(R)),
    module = rep(colnames(R), each  = nrow(R)),
    r      = as.numeric(R),
    p      = as.numeric(P),
    stringsAsFactors = FALSE
  )
  long$p_adj <- stats::p.adjust(long$p, method = "BH")
  long <- long[order(long$p), , drop = FALSE]
  bump(100, "Done")
  # Use `data` (a data.frame) as the primary payload – this matches the shape
  # that /api/jobs/<id>/result recognises for async jobs (same pattern as
  # run_enrichment) so the frontend gets `png`, `pdf`, `table`, etc. along
  # with a properly encoded data.frame.
  list(
    success      = TRUE,
    png          = png_b64,
    pdf          = pdf_out,
    table        = long,
    data         = long,                       # makes the job result serializer happy
    n_modules    = ncol(R),
    n_traits     = nrow(R),
    n_feat_used  = length(keep)
  )
}
