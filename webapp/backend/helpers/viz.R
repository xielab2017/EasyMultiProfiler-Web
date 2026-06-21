# Visualisation helpers - publication-grade plots backed by EasyMultiProfiler.
#
# Every function returns a base64 PNG suitable for direct rendering in the web
# UI.  Plots are tuned for journal output (300 dpi, journal-friendly palette,
# clear axes, statistical annotations where appropriate).

# -----------------------------------------------------------------------------
# Helper: pick a colour-friendly group vector + level order
# -----------------------------------------------------------------------------
.viz_group_levels <- function(values) {
  vals <- as.character(values)
  vals[is.na(vals) | !nzchar(vals)] <- "NA"
  ord <- unique(vals)
  factor(vals, levels = ord)
}

# For 16S/tax data feature IDs often look like "feature_1"; derive nicer labels
# from rowData by walking from deepest taxonomy level upward so that the labels
# are informative even when deeper ranks are unclassified.
.viz_feature_labels <- function(empt, ids) {
  ids <- as.character(ids)
  rd <- tryCatch(SummarizedExperiment::rowData(empt), error = function(e) NULL)
  if (is.null(rd) || nrow(rd) == 0) return(ids)
  rd_df <- as.data.frame(rd, stringsAsFactors = FALSE)
  # Always-safe fallback
  out <- ids
  idx <- match(ids, rownames(rd_df))
  if (any(!is.na(idx))) {
    tax_order <- c("Species", "Genus", "Family", "Order", "Class", "Phylum", "Kindom", "Kingdom", "Domain")
    cand_cols <- intersect(tax_order, names(rd_df))
    name_cols <- intersect(c("Name", "label", "feature"), names(rd_df))
    for (j in seq_along(ids)) {
      i <- idx[j]
      if (is.na(i)) next
      picked <- NA_character_
      for (col in cand_cols) {
        v <- as.character(rd_df[[col]][i])
        if (!is.na(v) && nzchar(v) && !grepl("_unclassified", v, ignore.case = TRUE)) {
          picked <- v; break
        }
      }
      if (is.na(picked)) {
        for (col in cand_cols) {
          v <- as.character(rd_df[[col]][i])
          if (!is.na(v) && nzchar(v)) { picked <- v; break }
        }
      }
      if (is.na(picked)) {
        for (col in name_cols) {
          v <- as.character(rd_df[[col]][i])
          if (!is.na(v) && nzchar(v) && v != ids[j]) { picked <- v; break }
        }
      }
      if (!is.na(picked) && nzchar(picked)) out[j] <- picked
    }
  }
  # Truncate overly long labels
  too_long <- nchar(out) > 50
  if (any(too_long)) out[too_long] <- paste0(substr(out[too_long], 1, 47), "...")
  out
}

# Heuristic: pick first categorical metadata column when caller didn't specify.
.viz_load_empt <- function(session_id, experiment) {
  empt <- get_empt(session_id, experiment)
  if (exists("apply_merged_coldata", mode = "function", inherits = TRUE)) {
    empt <- apply_merged_coldata(session_id, empt)
  }
  empt
}

.viz_pick_group <- function(empt, group) {
  cd <- as.data.frame(SummarizedExperiment::colData(empt))
  if (!is.null(group) && nzchar(group) && group %in% names(cd)) {
    return(list(name = group, values = cd[[group]]))
  }
  cats <- names(cd)[vapply(cd, function(x) {
    ux <- unique(stats::na.omit(as.character(x)))
    length(ux) > 1 && length(ux) < nrow(cd)
  }, logical(1))]
  if (length(cats) == 0) return(NULL)
  list(name = cats[1], values = cd[[cats[1]]])
}

## Ordination coordinates from the last EMP_dimension_analysis (PCoA/PCA/…).
.viz_emp_dimension_bundle <- function(empt) {
  dr <- tryCatch(
    EasyMultiProfiler::EMP_result(empt, info = "EMP_dimension_analysis"),
    error = function(e) NULL
  )
  if (!is.list(dr) || is.null(dr$dimension_coordinate)) return(NULL)
  coord <- as.data.frame(dr$dimension_coordinate, stringsAsFactors = FALSE)
  if (!"primary" %in% names(coord) || nrow(coord) < 2L) return(NULL)
  axis_pct <- if (!is.null(dr$dimension_axis)) as.numeric(dr$dimension_axis) else NULL
  list(coord = coord, axis_pct = axis_pct)
}

## Require the same samples as the current assay (order may differ).
.viz_dim_coords_match_assay <- function(coord, sample_ids) {
  prim <- as.character(coord$primary)
  sid <- as.character(sample_ids)
  if (length(prim) != length(sid)) return(FALSE)
  identical(sort(prim), sort(sid))
}

.viz_axis_group_stats <- function(scores, groups) {
  g <- as.factor(groups)
  if (length(unique(stats::na.omit(as.character(g)))) < 2) return(NULL)
  p1 <- tryCatch(stats::kruskal.test(scores$PC_x ~ g)$p.value, error = function(e) NA_real_)
  p2 <- tryCatch(stats::kruskal.test(scores$PC_y ~ g)$p.value, error = function(e) NA_real_)
  e1 <- tryCatch({
    fit <- stats::lm(PC_x ~ g, data = data.frame(PC_x = scores$PC_x, g = g))
    summary(fit)$r.squared
  }, error = function(e) NA_real_)
  e2 <- tryCatch({
    fit <- stats::lm(PC_y ~ g, data = data.frame(PC_y = scores$PC_y, g = g))
    summary(fit)$r.squared
  }, error = function(e) NA_real_)
  list(p1 = p1, p2 = p2, r1 = e1, r2 = e2)
}

.viz_axis_projection_test <- function(values, groups) {
  g <- droplevels(as.factor(groups))
  if (nlevels(g) < 2L) {
    return(list(p = NA_real_, label = "", method = NA_character_))
  }
  if (nlevels(g) == 2L) {
    pv <- tryCatch(
      stats::wilcox.test(values ~ g, exact = FALSE)$p.value,
      error = function(e) NA_real_
    )
    return(list(
      p = pv,
      label = if (is.finite(pv)) sprintf("p = %.4g", pv) else "ns",
      method = "wilcox"
    ))
  }
  pv <- tryCatch(
    stats::kruskal.test(values ~ g)$p.value,
    error = function(e) NA_real_
  )
  list(
    p = pv,
    label = if (is.finite(pv)) sprintf("KW p = %.4g", pv) else "ns",
    method = "kruskal"
  )
}

.viz_ordination_marginal <- function(df, axis = c("x", "y"), pal, stat = NULL) {
  axis <- match.arg(axis)
  val_col <- if (axis == "x") "PC_x" else "PC_y"
  ng <- nlevels(df$group)
  if (is.null(stat)) stat <- .viz_axis_projection_test(df[[val_col]], df$group)
  vr <- range(df[[val_col]], na.rm = TRUE)
  pad <- diff(vr) * 0.14
  if (!is.finite(pad) || pad < 1e-9) pad <- max(abs(vr), na.rm = TRUE) * 0.1 + 1
  y_lo <- vr[1] - pad * 0.25
  y_hi <- vr[2] + pad * (if (ng == 2L && stat$method == "wilcox") 1.6 else 1.1)

  if (axis == "x") {
    p <- ggplot2::ggplot(df, ggplot2::aes(
      x = .data[["group"]], y = .data[[val_col]],
      fill = group, color = group
    )) +
      ggplot2::geom_boxplot(
        width = 0.55, alpha = 0.32, outlier.shape = NA,
        linewidth = 0.35, color = "grey35"
      ) +
      ggplot2::geom_jitter(width = 0.11, size = 1.5, alpha = 0.78, stroke = 0) +
      ggplot2::scale_y_continuous(limits = c(y_lo, y_hi), expand = c(0, 0)) +
      ggplot2::theme(axis.text.x = ggplot2::element_blank())
  } else {
    p <- ggplot2::ggplot(df, ggplot2::aes(
      x = .data[[val_col]], y = .data[["group"]],
      fill = group, color = group
    )) +
      ggplot2::geom_boxplot(
        orientation = "y", width = 0.55, alpha = 0.32, outlier.shape = NA,
        linewidth = 0.35, color = "grey35"
      ) +
      ggplot2::geom_jitter(height = 0.11, size = 1.5, alpha = 0.78, stroke = 0) +
      ggplot2::scale_x_continuous(limits = c(y_lo, y_hi), expand = c(0, 0)) +
      ggplot2::theme(axis.text.y = ggplot2::element_blank())
  }

  p <- p +
    ggplot2::scale_fill_manual(values = pal) +
    ggplot2::scale_color_manual(values = pal) +
    ggplot2::theme_void(base_size = 8) +
    ggplot2::theme(
      legend.position = "none",
      plot.margin = grid::unit(c(1, 1, 1, 1), "pt")
    )

  if (is.finite(stat$p) && ng == 2L && stat$method == "wilcox" &&
      axis == "x" && requireNamespace("ggsignif", quietly = TRUE)) {
    y_br <- vr[2] + pad * 0.55
    p <- p + ggsignif::geom_signif(
      comparisons = list(levels(df$group)),
      map_signif_level = FALSE,
      annotations = stat$label,
      textsize = 2.6,
      tip_length = 0.02,
      y_position = y_br,
      vjust = 0.1
    )
  } else if (is.finite(stat$p)) {
    if (axis == "x") {
      p <- p + ggplot2::annotate(
        "text", x = (ng + 1) / 2, y = vr[2] + pad * 0.35,
        label = stat$label, size = 2.6, fontface = "bold"
      )
    } else {
      p <- p + ggplot2::annotate(
        "text", x = vr[2] + pad * 0.35, y = (ng + 1) / 2,
        label = stat$label, size = 2.6, fontface = "bold", angle = 90
      )
    }
  }
  p
}

.viz_ordination_compose <- function(scores, plot_title, xlab, ylab, grp_name,
                                  caption = NULL, subtitle = NULL,
                                  width = 9, height = 7) {
  ng <- length(levels(scores$group))
  pal <- emp_pub_palette(ng)
  names(pal) <- levels(scores$group)

  ell_in  <- emp_conf_ellipse(scores$PC_x, scores$PC_y, scores$group, level = 0.95)
  ell_out <- emp_conf_ellipse(scores$PC_x, scores$PC_y, scores$group, level = 0.99)

  cent <- stats::aggregate(
    cbind(PC_x, PC_y) ~ group, data = scores, FUN = mean, na.rm = TRUE
  )
  names(cent) <- c("group", "PC_x_cen", "PC_y_cen")
  scores <- merge(scores, cent, by = "group", sort = FALSE)

  # Robust bounds prevent extreme points/ellipses from stretching the panel.
  x_raw <- range(scores$PC_x, na.rm = TRUE)
  y_raw <- range(scores$PC_y, na.rm = TRUE)
  x_q <- stats::quantile(scores$PC_x, probs = c(0.02, 0.98), na.rm = TRUE, names = FALSE)
  y_q <- stats::quantile(scores$PC_y, probs = c(0.02, 0.98), na.rm = TRUE, names = FALSE)
  xlim <- c(min(x_raw[1], x_q[1]), max(x_raw[2], x_q[2]))
  ylim <- c(min(y_raw[1], y_q[1]), max(y_raw[2], y_q[2]))
  xpad <- diff(xlim) * 0.08
  ypad <- diff(ylim) * 0.08
  if (!is.finite(xpad) || xpad < 1e-9) xpad <- abs(xlim[1]) * 0.06 + 1
  if (!is.finite(ypad) || ypad < 1e-9) ypad <- abs(ylim[1]) * 0.06 + 1

  p_main <- ggplot2::ggplot(
    scores, ggplot2::aes(x = PC_x, y = PC_y, color = group, fill = group)
  ) +
    ggplot2::geom_hline(yintercept = 0, linetype = "dashed", color = "grey82", linewidth = 0.3) +
    ggplot2::geom_vline(xintercept = 0, linetype = "dashed", color = "grey82", linewidth = 0.3)

  if (!is.null(ell_out) && nrow(ell_out) > 0) {
    p_main <- p_main + ggplot2::geom_polygon(
      data = ell_out,
      ggplot2::aes(x = x, y = y, fill = group, group = group),
      alpha = 0.04, inherit.aes = FALSE, color = NA
    )
  }
  if (!is.null(ell_in) && nrow(ell_in) > 0) {
    p_main <- p_main + ggplot2::geom_polygon(
      data = ell_in,
      ggplot2::aes(x = x, y = y, fill = group, group = group),
      alpha = 0.12, inherit.aes = FALSE, color = NA
    )
  }

  if (ng >= 2L) {
    p_main <- p_main + ggplot2::geom_segment(
      ggplot2::aes(x = PC_x, y = PC_y, xend = PC_x_cen, yend = PC_y_cen, color = group),
      alpha = 0.28, linewidth = 0.28, lineend = "round"
    )
  }

  p_main <- p_main +
    ggplot2::geom_point(shape = 21, size = 5.2, alpha = 0.20, stroke = 0.42) +
    ggplot2::geom_point(shape = 21, size = 2.9, alpha = 0.97, color = "grey22", stroke = 0.33)

  if (ng >= 2L && ng <= 8L) {
    p_main <- p_main + ggplot2::geom_label(
      data = cent,
      ggplot2::aes(x = PC_x_cen, y = PC_y_cen, label = group, color = group, fill = group),
      size = 2.6, fontface = "bold", alpha = 0.88,
      label.padding = grid::unit(0.12, "lines"),
      show.legend = FALSE
    )
  }

  p_main <- p_main +
    emp_scale_color_pub(name = grp_name, n_hint = ng) +
    emp_scale_fill_pub(name = grp_name, n_hint = ng) +
    ggplot2::labs(title = plot_title, subtitle = subtitle, x = xlab, y = ylab,
                  caption = caption) +
    ggplot2::coord_fixed(
      xlim = c(xlim[1] - xpad, xlim[2] + xpad),
      ylim = c(ylim[1] - ypad, ylim[2] + ypad),
      expand = FALSE
    ) +
    emp_pub_theme() +
    ggplot2::theme(
      legend.position = "top",
      legend.title = ggplot2::element_text(face = "bold", size = 9),
      legend.text = ggplot2::element_text(size = 8)
    )

  if (ng < 2L || !requireNamespace("patchwork", quietly = TRUE)) {
    return(list(plot = p_main, width = width, height = height))
  }

  stat_x <- .viz_axis_projection_test(scores$PC_x, scores$group)
  stat_y <- .viz_axis_projection_test(scores$PC_y, scores$group)
  p_top <- .viz_ordination_marginal(scores, axis = "x", pal = pal, stat = stat_x)
  p_right <- .viz_ordination_marginal(scores, axis = "y", pal = pal, stat = stat_y)

  combined <- patchwork::wrap_plots(
    p_top, patchwork::plot_spacer(), p_main, p_right,
    design = "12\n34"
  ) + patchwork::plot_layout(widths = c(4, 1), heights = c(1, 4))

  list(plot = combined, width = width + 1.5, height = height + 0.8)
}

# -----------------------------------------------------------------------------
# Barplot: top-N feature mean-abundance with optional group facet
# -----------------------------------------------------------------------------
make_barplot <- function(session_id, experiment, group = NULL, feature = NULL,
                          mode = "top20", top_n = 20L, width = 9, height = 6,
                          color_panel = NULL, custom_colors = NULL) {
  old_panel <- emp_set_color_panel(color_panel, custom_colors = custom_colors)
  on.exit(emp_restore_color_panel(old_panel), add = TRUE)
  empt <- .viz_load_empt(session_id, experiment)
  ad   <- SummarizedExperiment::assays(empt)[[1]]
  cd   <- as.data.frame(SummarizedExperiment::colData(empt))

  if (mode == "single" && !is.null(feature) && feature != "" && feature %in% rownames(ad)) {
    df <- data.frame(sample = colnames(ad), value = as.numeric(ad[feature, ]))
    if (!is.null(group) && group %in% names(cd)) {
      df$group <- .viz_group_levels(cd[[group]])
      p <- ggplot2::ggplot(df, ggplot2::aes(x = sample, y = value, fill = group)) +
        ggplot2::geom_col(width = 0.7) +
        emp_scale_fill_pub(name = group) +
        ggplot2::facet_grid(~ group, scales = "free_x", space = "free_x")
    } else {
      p <- ggplot2::ggplot(df, ggplot2::aes(x = sample, y = value)) +
        ggplot2::geom_col(fill = emp_pub_palette(1)[1], width = 0.7)
    }
    p <- p +
      ggplot2::labs(title = feature, x = NULL, y = "Abundance") +
      emp_pub_theme() +
      ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
    return(plot_to_base64(p, width = width, height = height))
  }

  top_n <- max(3L, as.integer(top_n))
  ord   <- order(rowMeans(ad, na.rm = TRUE), decreasing = TRUE)
  topf  <- rownames(ad)[ord[seq_len(min(top_n, nrow(ad)))]]
  ad_t  <- ad[topf, , drop = FALSE]
  topf_lab <- make.unique(.viz_feature_labels(empt, topf))

  if (!is.null(group) && group %in% names(cd)) {
    grp <- .viz_group_levels(cd[[group]])
    means <- vapply(levels(grp), function(g) {
      cols <- which(grp == g)
      if (!length(cols)) return(rep(NA_real_, length(topf_lab)))
      rowMeans(ad_t[, cols, drop = FALSE], na.rm = TRUE)
    }, numeric(length(topf_lab)))
    df <- data.frame(
      feature = rep(topf_lab, ncol(means)),
      group   = rep(colnames(means), each = length(topf_lab)),
      value   = as.vector(means),
      stringsAsFactors = FALSE
    )
    df$feature <- factor(df$feature, levels = rev(topf_lab))
    df$group   <- factor(df$group, levels = colnames(means))
    sig_tbl <- do.call(rbind, lapply(topf_lab, function(fx) {
      sub <- df[df$feature == fx, , drop = FALSE]
      pv <- tryCatch(stats::kruskal.test(value ~ group, data = sub)$p.value, error = function(e) NA_real_)
      data.frame(feature = fx, p = pv, stringsAsFactors = FALSE)
    }))
    sig_tbl$signif <- ifelse(is.na(sig_tbl$p), "",
                             ifelse(sig_tbl$p < 0.001, "***",
                                    ifelse(sig_tbl$p < 0.01, "**",
                                           ifelse(sig_tbl$p < 0.05, "*", ""))))
    n_sig <- sum(nzchar(sig_tbl$signif), na.rm = TRUE)
    feat_lab_map <- stats::setNames(
      ifelse(nzchar(sig_tbl$signif), paste0(sig_tbl$feature, " ", sig_tbl$signif), sig_tbl$feature),
      sig_tbl$feature
    )
    df$feature_lab <- factor(feat_lab_map[as.character(df$feature)],
                             levels = rev(unname(feat_lab_map[topf_lab])))

    p <- ggplot2::ggplot(df, ggplot2::aes(x = feature_lab, y = value, fill = group)) +
      ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.8), width = 0.7) +
      ggplot2::coord_flip() +
      emp_scale_fill_pub(name = group, n_hint = length(levels(df$group))) +
      ggplot2::labs(title = paste0("Top ", length(topf), " features by mean abundance"),
                    subtitle = sprintf("Per-feature Kruskal test: %d/%d significant (p < 0.05)", n_sig, nrow(sig_tbl)),
                    x = NULL, y = "Mean abundance")
  } else {
    df <- data.frame(feature = factor(topf_lab, levels = rev(topf_lab)),
                     mean = rowMeans(ad_t, na.rm = TRUE))
    p <- ggplot2::ggplot(df, ggplot2::aes(x = feature, y = mean)) +
      ggplot2::geom_col(fill = emp_pub_palette(1)[1], width = 0.75) +
      ggplot2::coord_flip() +
      ggplot2::labs(title = paste0("Top ", length(topf_lab), " features by mean abundance"),
                    x = NULL, y = "Mean abundance")
  }
  p <- p + emp_pub_theme()
  plot_to_base64(p, width = width, height = height)
}

# -----------------------------------------------------------------------------
# Boxplot: feature value across groups with Wilcoxon p-values
# -----------------------------------------------------------------------------
make_boxplot <- function(session_id, experiment, group = NULL, feature = NULL,
                          width = 9, height = 6, color_panel = NULL, custom_colors = NULL) {
  old_panel <- emp_set_color_panel(color_panel, custom_colors = custom_colors)
  on.exit(emp_restore_color_panel(old_panel), add = TRUE)
  empt <- .viz_load_empt(session_id, experiment)
  ad   <- SummarizedExperiment::assays(empt)[[1]]
  cd   <- as.data.frame(SummarizedExperiment::colData(empt))

  if (is.null(feature) || !nzchar(feature) || !(feature %in% rownames(ad))) {
    feature <- rownames(ad)[which.max(rowMeans(ad, na.rm = TRUE))]
  }
  vals <- as.numeric(ad[feature, ])
  df <- data.frame(sample = colnames(ad), value = vals)
  pick <- .viz_pick_group(empt, group)
  if (!is.null(pick)) {
    df$group <- .viz_group_levels(pick$values)
    grp_name <- pick$name
  } else {
    df$group <- factor("All")
    grp_name <- "Group"
  }

  feat_label <- .viz_feature_labels(empt, feature)
  p <- ggplot2::ggplot(df, ggplot2::aes(x = group, y = value, fill = group)) +
    ggplot2::geom_boxplot(alpha = 0.55, outlier.shape = NA, width = 0.55) +
    ggplot2::geom_jitter(ggplot2::aes(color = group), width = 0.18, size = 1.6, alpha = 0.85) +
    emp_scale_fill_pub(name = grp_name, n_hint = length(levels(df$group))) +
    emp_scale_color_pub(name = grp_name, n_hint = length(levels(df$group))) +
    ggplot2::labs(title = feat_label, x = grp_name, y = "Abundance") +
    emp_pub_theme()

  pw <- emp_pairwise_wilcox(df$value, df$group)
  if (!is.null(pw) && nrow(pw) > 0 && requireNamespace("ggpubr", quietly = TRUE)) {
    comps <- lapply(seq_len(nrow(pw)), function(i) c(pw$group1[i], pw$group2[i]))
    p <- p + ggpubr::stat_compare_means(comparisons = comps, method = "wilcox.test",
                                         label = "p.signif", tip.length = 0.01,
                                         hide.ns = FALSE, size = 3.4)
  }
  ns <- table(df$group)
  cap <- paste(paste0(names(ns), "=n", as.integer(ns)), collapse = ", ")
  p <- emp_caption(p, paste("Wilcoxon rank-sum;", cap))
  plot_to_base64(p, width = width, height = height)
}

# -----------------------------------------------------------------------------
# Heatmap: top-variable features, z-scored, group-clustered, annotation bar
# -----------------------------------------------------------------------------
## Tolerant feature lookup used by make_heatmap() when the user paste-
## selects genes.  The order of the returned integer vector follows the
## order of `features` from the caller so the heatmap rows preserve the
## user's input order (before optional hierarchical clustering).
.match_features <- function(empt, features) {
  if (is.null(features)) return(list(idx = integer(0), matched = character(0),
                                      missing = character(0)))
  features <- trimws(as.character(features))
  features <- features[nzchar(features)]
  features <- unique(features)
  if (!length(features)) return(list(idx = integer(0), matched = character(0),
                                       missing = character(0)))

  ad <- SummarizedExperiment::assays(empt)[[1]]
  rd <- tryCatch(as.data.frame(SummarizedExperiment::rowData(empt),
                                 stringsAsFactors = FALSE),
                 error = function(e) data.frame())
  ids <- rownames(ad)

  ## 1. exact rowname.  2. case-insensitive rowname.  3. rowData alias columns.
  idx <- integer(length(features))
  names(idx) <- features
  for (i in seq_along(features)) {
    q <- features[i]
    h <- match(q, ids)
    if (is.na(h)) h <- match(tolower(q), tolower(ids))
    if (is.na(h) && nrow(rd)) {
      alias_cols <- intersect(
        c("Name", "name", "label", "gene", "gene_symbol", "symbol",
          "SYMBOL", "Gene", "Genus", "Species", "feature",
          ".FEATURE", ".feature"),
        names(rd))
      for (col in alias_cols) {
        vals <- rd[[col]]
        if (is.null(vals)) next
        mh <- match(q, vals)
        if (is.na(mh)) mh <- match(tolower(q), tolower(vals))
        if (!is.na(mh)) { h <- mh; break }
      }
    }
    idx[i] <- if (is.na(h)) NA_integer_ else as.integer(h)
  }
  matched <- features[!is.na(idx)]
  missing <- features[is.na(idx)]
  idx <- idx[!is.na(idx)]
  ## Keep only the first occurrence of each feature so a gene pasted twice
  ## doesn't duplicate rows.
  dup <- duplicated(idx)
  idx <- idx[!dup]; matched <- matched[!dup]
  list(idx = idx, matched = matched, missing = missing)
}

# Order sample columns by group; optionally cluster within each group only
# (pheatmap global column clustering would mix treatment groups).
.viz_order_heatmap_columns <- function(mat, grp, cluster_cols = TRUE) {
  grp <- as.factor(grp)
  if (length(grp) != ncol(mat)) {
    stop("Group vector length must match number of samples.")
  }
  ord <- unlist(lapply(levels(grp), function(gv) {
    idx <- which(grp == gv)
    if (length(idx) <= 2L || !isTRUE(cluster_cols)) return(idx)
    sub <- mat[, idx, drop = FALSE]
    tryCatch(idx[stats::hclust(stats::dist(t(sub)))$order], error = function(e) idx)
  }), use.names = FALSE)
  list(matrix = mat[, ord, drop = FALSE], group = grp[ord], order = ord)
}

# Render a pheatmap gtable to PNG base64 + optional PDF (classic DESeq2 style).
.pheatmap_to_outputs <- function(ph, pdf_path = NULL, width, height,
                                 cluster_rows = TRUE, cluster_cols = TRUE) {
  pdf_out <- NULL
  if (!is.null(pdf_path) && nzchar(pdf_path)) {
    tryCatch(
      save_plot_pdf(ph, pdf_path, width = width, height = height),
      error = function(e) message("[heatmap] PDF write failed: ", conditionMessage(e))
    )
    pdf_out <- pdf_path
  }
  png_b64 <- tryCatch({
    tmp <- tempfile(fileext = ".png")
    on.exit(if (file.exists(tmp)) file.remove(tmp), add = TRUE)
    if (requireNamespace("ragg", quietly = TRUE)) {
      ragg::agg_png(filename = tmp, width = width, height = height, units = "in",
                    res = 300, background = "white")
    } else {
      grDevices::png(filename = tmp, width = width, height = height, units = "in",
                     res = 300, bg = "white",
                     type = if (.Platform$OS.type == "windows") "windows" else "cairo")
    }
    grid::grid.newpage()
    grid::grid.draw(ph$gtable)
    grDevices::dev.off()
    base64enc::base64encode(tmp)
  }, error = function(e) NA_character_)
  list(png = png_b64, pdf = pdf_out)
}

.pheatmap_auto_size <- function(n_row, n_col, max_col_chars = 8, show_rn,
                                cluster_rows, cluster_cols) {
  cell_h <- if (n_row <= 20) 12 else if (n_row <= 60) 10 else 8
  cell_w <- if (n_col <= 10) 24 else if (n_col <= 20) 18 else 14
  .px2in <- function(pt) pt / 72
  body_w <- n_col * .px2in(cell_w)
  body_h <- n_row * .px2in(cell_h)
  lab_h <- min(2.0, max(0.8, max(1L, max_col_chars) * 0.09))
  lab_w <- if (show_rn) min(2.4, 0.08 * 12) else 0.5
  extra_w <- (if (isTRUE(cluster_rows)) 0.7 else 0.2) + 2.4
  extra_h <- 0.35 + (if (isTRUE(cluster_cols)) 0.5 else 0.15) + 1.0
  list(
    width  = max(7.0, min(24.0, body_w + lab_w + extra_w)),
    height = max(6.0, min(32.0, body_h + lab_h + extra_h)),
    cell_w = cell_w,
    cell_h = cell_h
  )
}

# Shared pheatmap renderer (DEG + top-variance + custom-list heatmaps).
# Columns: ordered by group; within-group hclust when cluster_cols=TRUE
# (no cross-group column dendrogram). Rows: pheatmap cluster_rows when enabled.
.viz_render_pheatmap <- function(mat, grp, title, subtitle = NULL,
                                 cluster_rows = TRUE, cluster_cols = TRUE,
                                 show_rownames = TRUE, font_size = 10,
                                 color_panel = NULL, pdf_path = NULL,
                                 width = NA_real_, height = NA_real_,
                                 log_transform = TRUE, ann_name = "Group") {
  if (!requireNamespace("pheatmap", quietly = TRUE)) {
    stop("Package 'pheatmap' is required for heatmap.")
  }
  mat_in <- as.matrix(mat)
  mat_in[!is.finite(mat_in)] <- 0
  if (isTRUE(log_transform)) mat_in <- log1p(mat_in)

  grp <- as.factor(grp)
  if (length(grp) != ncol(mat_in)) {
    stop("Group vector length must match number of samples.")
  }
  col_ord <- .viz_order_heatmap_columns(mat_in, grp, cluster_cols)
  mat_in <- col_ord$matrix
  grp <- col_ord$group

  ann_df <- data.frame(grp = as.character(grp), row.names = colnames(mat_in),
                       stringsAsFactors = FALSE)
  names(ann_df)[1] <- ann_name
  ann_colors <- list(
    stats::setNames(emp_pub_palette(length(levels(grp))), levels(grp))
  )
  names(ann_colors)[1] <- ann_name

  show_rn <- isTRUE(show_rownames) && nrow(mat_in) <= 200
  max_col_chars <- max(1L, max(nchar(colnames(mat_in))))
  do_cluster_rows <- isTRUE(cluster_rows) && nrow(mat_in) > 2
  sz <- .pheatmap_auto_size(nrow(mat_in), ncol(mat_in), max_col_chars, show_rn,
                            cluster_rows, cluster_cols = FALSE)
  if (!is.finite(width)  || is.na(width))  width  <- sz$width
  if (!is.finite(height) || is.na(height)) height <- sz$height

  main_title <- if (!is.null(subtitle) && nzchar(subtitle)) {
    paste0(title, "\n", subtitle)
  } else {
    title
  }

  build_ph <- function(cr = do_cluster_rows) {
    pheatmap::pheatmap(
      mat_in,
      scale             = "row",
      color             = emp_diverging_colors(panel = color_panel),
      annotation_col    = ann_df,
      annotation_colors = ann_colors,
      cluster_rows      = cr,
      cluster_cols      = FALSE,
      show_rownames     = show_rn,
      show_colnames     = TRUE,
      fontsize          = max(8, as.numeric(font_size)),
      fontsize_row      = if (show_rn) max(8, as.numeric(font_size)) else 1,
      fontsize_col      = max(8, as.numeric(font_size)),
      angle_col         = 90,
      cellwidth         = sz$cell_w,
      cellheight        = sz$cell_h,
      border_color      = "grey92",
      treeheight_row    = if (cr) 40 else 0,
      treeheight_col    = 0,
      main              = main_title,
      silent            = TRUE
    )
  }

  ph <- tryCatch(
    build_ph(),
    error = function(e) {
      message("[heatmap] row clustering failed, retrying without dendrogram: ",
              conditionMessage(e))
      build_ph(cr = FALSE)
    }
  )

  out <- .pheatmap_to_outputs(ph, pdf_path, width, height, cluster_rows, FALSE)
  list(png = out$png, pdf = out$pdf, n_rows = nrow(mat_in))
}

make_heatmap <- function(session_id, experiment, group = NULL,
                          top_n = 50L, width = 11, height = 8,
                          features = NULL, cluster_rows = TRUE,
                          cluster_cols = TRUE, show_gene_names = NULL,
                          font_size = 11, color_panel = NULL, custom_colors = NULL) {
  old_panel <- emp_set_color_panel(color_panel, custom_colors = custom_colors)
  on.exit(emp_restore_color_panel(old_panel), add = TRUE)
  empt <- .viz_load_empt(session_id, experiment)
  ad   <- SummarizedExperiment::assays(empt)[[1]]
  cd   <- as.data.frame(SummarizedExperiment::colData(empt))
  if (nrow(ad) == 0 || ncol(ad) == 0) stop("Assay matrix is empty.")

  ## Either user-supplied list or classic top-variance selection.  When
  ## a custom list is given we honour the user's order (and defer row
  ## ordering to hierarchical clustering of the scaled matrix).
  feat_info <- .match_features(empt, features)
  if (length(feat_info$idx)) {
    if (length(feat_info$idx) < 2L) {
      stop(sprintf("Need \u2265 2 matching features for a heatmap; only matched %d.",
                    length(feat_info$idx)))
    }
    ad_s <- ad[feat_info$idx, , drop = FALSE]
    use_custom <- TRUE
  } else {
    top_n <- max(5L, as.integer(top_n))
    topf  <- order(apply(ad, 1, var, na.rm = TRUE), decreasing = TRUE)[
               seq_len(min(top_n, nrow(ad)))]
    ad_s  <- ad[topf, , drop = FALSE]
    use_custom <- FALSE
  }

  pick <- if (!is.null(group) && nzchar(group) && group %in% names(cd)) {
    list(name = group, values = cd[[group]])
  } else {
    .viz_pick_group(empt, NULL)
  }
  if (!is.null(pick)) {
    grp <- .viz_group_levels(pick$values)
  } else {
    grp <- factor(rep("All", ncol(ad_s)))
    pick <- list(name = "Sample", values = grp)
  }

  feat_labs <- make.unique(.viz_feature_labels(empt, rownames(ad_s)))
  rownames(ad_s) <- feat_labs

  show_rn <- if (is.null(show_gene_names)) {
    use_custom || nrow(ad_s) <= 60
  } else {
    isTRUE(show_gene_names)
  }

  heat_title <- if (use_custom) {
    sprintf("Custom heatmap (%d features, z-scored)", nrow(ad_s))
  } else {
    paste0("Top ", nrow(ad_s), " variable features (z-scored)")
  }

  out <- .viz_render_pheatmap(
    ad_s, grp, title = heat_title,
    cluster_rows = cluster_rows, cluster_cols = cluster_cols,
    show_rownames = show_rn, font_size = font_size,
    color_panel = color_panel, width = width, height = height,
    ann_name = pick$name
  )

  if (use_custom) {
    return(list(plot     = out$png,
                 matched  = feat_info$matched,
                 missing  = feat_info$missing,
                 n_total  = length(feat_info$matched) + length(feat_info$missing),
                 n_used   = length(feat_info$matched),
                 n_missing= length(feat_info$missing)))
  }
  out$png
}

# -----------------------------------------------------------------------------
# Volcano: log2FC vs -log10(padj), three-colour UP/DOWN/none scheme
# matching the sample RNAseq.R workflow.  When available we read the raw
# DESeq2-style table cached by run_diff() so the plot speaks the same
# language as stand-alone DESeq2 scripts (log2FoldChange / padj columns).
# -----------------------------------------------------------------------------
make_volcano <- function(session_id, experiment, fc_cutoff = 1.0, p_cutoff = 0.05,
                          use_padj = TRUE, width = 8, height = 7, label_top = 15L,
                          color_panel = NULL, custom_colors = NULL) {
  old_panel <- emp_set_color_panel(color_panel, custom_colors = custom_colors)
  on.exit(emp_restore_color_panel(old_panel), add = TRUE)
  empt <- .viz_load_empt(session_id, experiment)

  raw <- load_diff_raw(session_id, experiment)
  if (!is.null(raw) && !is.null(raw$data) && nrow(raw$data) > 0) {
    df <- as.data.frame(raw$data, stringsAsFactors = FALSE)
  } else {
    # Fall back to EMP compact result.
    diff_res <- tryCatch(
      as.data.frame(EasyMultiProfiler::EMP_result(empt, info = "diff_analysis_result"),
                     stringsAsFactors = FALSE),
      error = function(e) NULL
    )
    if (is.null(diff_res) || nrow(diff_res) == 0) {
      stop("Run differential analysis before generating a volcano plot.")
    }
    pick <- function(patterns) {
      for (pat in patterns) {
        h <- grep(pat, names(diff_res), ignore.case = TRUE, value = TRUE)
        if (length(h)) return(h[1])
      }
      NA_character_
    }
    fc_col <- pick(c("^log2fc$", "^log2foldchange$", "^lfc$"))
    p_col  <- pick(c("^pvalue$",  "^p_value$",  "^p\\.value$"))
    q_col  <- pick(c("^padj$",    "^fdr$",      "^q[._]?value$", "^adj[._]?p"))
    df <- data.frame(
      feature        = if ("feature" %in% names(diff_res)) as.character(diff_res$feature) else rownames(diff_res),
      symbol         = if ("feature" %in% names(diff_res)) as.character(diff_res$feature) else rownames(diff_res),
      log2FoldChange = if (!is.na(fc_col)) suppressWarnings(as.numeric(diff_res[[fc_col]])) else NA_real_,
      pvalue         = if (!is.na(p_col))  suppressWarnings(as.numeric(diff_res[[p_col]]))  else NA_real_,
      padj           = if (!is.na(q_col))  suppressWarnings(as.numeric(diff_res[[q_col]]))  else NA_real_,
      stringsAsFactors = FALSE
    )
  }

  # Decide which p-value column to use.  If the caller asks for padj but the
  # dataset has no significant padj at the chosen cutoff we transparently
  # fall back to the raw p-value and annotate the subtitle.
  padj_vec <- suppressWarnings(as.numeric(df$padj))
  pval_vec <- suppressWarnings(as.numeric(df$pvalue))
  fallback_msg <- NULL
  if (isTRUE(use_padj) && any(is.finite(padj_vec))) {
    n_sig <- sum(is.finite(padj_vec) & padj_vec <= p_cutoff, na.rm = TRUE)
    if (n_sig == 0 && any(is.finite(pval_vec))) {
      use_padj <- FALSE
      fallback_msg <- "No features pass padj cutoff; using raw p-value instead"
    }
  }
  p_use <- if (isTRUE(use_padj) && any(is.finite(padj_vec))) padj_vec else pval_vec
  df$p_plot <- p_use
  df$fc <- suppressWarnings(as.numeric(df$log2FoldChange))

  fin <- is.finite(df$fc)
  if (any(fin) && any(!fin)) {
    cap <- max(abs(df$fc[fin]), na.rm = TRUE)
    df$fc[!fin & df$fc > 0] <-  cap
    df$fc[!fin & df$fc < 0] <- -cap
  }
  df <- df[is.finite(df$fc) & is.finite(df$p_plot), , drop = FALSE]
  if (!nrow(df)) stop("Differential result has no usable FC/p values.")

  # Soft 99th-percentile clipping to keep the bulk of the cloud readable.
  fc_q <- as.numeric(stats::quantile(abs(df$fc), probs = 0.99, na.rm = TRUE))
  if (is.finite(fc_q) && fc_q > 0) {
    fc_clip <- max(fc_q, fc_cutoff * 2, 2)
    df$fc <- pmax(pmin(df$fc, fc_clip), -fc_clip)
  }

  df$neg_log10p <- -log10(pmax(df$p_plot, 1e-300))
  df$change <- ifelse(df$p_plot <= p_cutoff & df$fc >=  fc_cutoff, "Up",
               ifelse(df$p_plot <= p_cutoff & df$fc <= -fc_cutoff, "Down", "NS"))
  df$change <- factor(df$change, levels = c("Down", "NS", "Up"))
  df$label  <- if (!is.null(df$symbol)) df$symbol else df$feature

  cnt <- table(df$change)
  n_up   <- as.integer(cnt["Up"]   %||% 0)
  n_down <- as.integer(cnt["Down"] %||% 0)
  n_ns   <- as.integer(cnt["NS"]   %||% 0)

  dpal <- emp_diverging_colors(panel = color_panel)
  pal <- c("Down" = dpal[25], "NS" = "#bdbdbd", "Up" = dpal[230])

  p_label <- if (isTRUE(use_padj)) expression(-log[10]~italic("padj")) else
    expression(-log[10]~italic("p-value"))
  sub <- paste0("|log2FC| >= ", fc_cutoff, ", ",
                if (isTRUE(use_padj)) "padj" else "p", " <= ", p_cutoff)
  if (!is.null(fallback_msg)) sub <- paste0(sub, "  (", fallback_msg, ")")

  p <- ggplot2::ggplot(df, ggplot2::aes(x = fc, y = neg_log10p, color = change)) +
    ggplot2::geom_point(alpha = 0.8, size = 1.75, na.rm = TRUE) +
    ggplot2::scale_color_manual(name = "Regulation", values = pal,
                                 labels = c("Down" = paste0("Down (n=", n_down, ")"),
                                            "NS"   = paste0("NS (n=", n_ns,   ")"),
                                            "Up"   = paste0("Up (n=", n_up,   ")"))) +
    ggplot2::geom_vline(xintercept = c(-fc_cutoff, fc_cutoff), linetype = "dashed",
                         color = "grey40", linewidth = 0.4) +
    ggplot2::geom_hline(yintercept = -log10(p_cutoff), linetype = "dashed",
                         color = "grey40", linewidth = 0.4) +
    ggplot2::labs(
      title = paste0("Volcano plot"),
      subtitle = sub,
      x = expression(log[2]~"Fold Change"),
      y = p_label
    ) +
    emp_pub_theme()

  # Label top differential genes – split Up vs Down so readers see both ends
  # of the distribution.  "Top" = largest combined rank of |log2FC| and
  # -log10(p), which is what Nature/Cell-style volcano plots highlight.
  if (requireNamespace("ggrepel", quietly = TRUE)) {
    sig <- df[df$change != "NS", , drop = FALSE]
    if (nrow(sig)) {
      # Combined rank: sum of quantile ranks for |fc| and -log10(p); features
      # ranked lowest (smallest rank == strongest combined signal) come first.
      r_fc <- rank(-abs(sig$fc), ties.method = "min")
      r_p  <- rank(-sig$neg_log10p, ties.method = "min")
      sig$label_score <- r_fc + r_p
      sig <- sig[order(sig$label_score), , drop = FALSE]
      per_side <- max(1L, as.integer(label_top) %/% 2L)
      top_up   <- sig[sig$change == "Up",   , drop = FALSE]
      top_down <- sig[sig$change == "Down", , drop = FALSE]
      top_up   <- top_up[  seq_len(min(per_side, nrow(top_up))),   , drop = FALSE]
      top_down <- top_down[seq_len(min(per_side, nrow(top_down))), , drop = FALSE]
      top <- rbind(top_up, top_down)
      if (nrow(top)) {
        p <- p + ggrepel::geom_text_repel(
          data = top, ggplot2::aes(label = label, color = change),
          size = 3.2, fontface = "bold",
          max.overlaps = 60, box.padding = 0.45, point.padding = 0.3,
          segment.color = "grey50", segment.size = 0.3, min.segment.length = 0,
          show.legend = FALSE
        )
        # Emphasise the labelled points themselves so reviewers can trace
        # a label back to its gene in the cloud.
        p <- p + ggplot2::geom_point(data = top,
                                      ggplot2::aes(x = fc, y = neg_log10p, color = change),
                                      size = 2.6, shape = 21, fill = NA,
                                      stroke = 0.9, show.legend = FALSE)
      }
    }
  }

  plot_to_base64(p, width = width, height = height)
}

# -----------------------------------------------------------------------------
# DEG heatmap (pheatmap): classic DESeq2-style layout — row dendrogram,
# group annotation bar, gene labels on the right, columns ordered by group
# (within-group clustering when Cluster cols = Yes; no cross-group dendrogram).
# Returns list(png = base64 PNG, pdf = PDF path, n_genes = <int>).
# -----------------------------------------------------------------------------
make_deg_heatmap <- function(session_id, experiment, group = NULL,
                              fc_cutoff = 1.0, p_cutoff = 0.05, use_padj = TRUE,
                              min_row_sum = 0, max_genes = 200L,
                              cluster_rows = TRUE, cluster_cols = TRUE,
                              show_rownames = TRUE, pdf_path = NULL,
                              width = NA_real_, height = NA_real_,
                              font_size = 10, color_panel = NULL, custom_colors = NULL) {
  old_panel <- emp_set_color_panel(color_panel, custom_colors = custom_colors)
  on.exit(emp_restore_color_panel(old_panel), add = TRUE)
  empt <- .viz_load_empt(session_id, experiment)
  raw <- ensure_diff_raw(session_id, experiment)
  if (is.null(raw) || is.null(raw$data) || !nrow(raw$data)) {
    stop("Run differential analysis first – no cached DEG table found.")
  }
  df <- as.data.frame(raw$data, stringsAsFactors = FALSE)
  padj_vec <- suppressWarnings(as.numeric(df$padj))
  pval_vec <- suppressWarnings(as.numeric(df$pvalue))
  if (isTRUE(use_padj) && any(is.finite(padj_vec))) {
    n_sig <- sum(is.finite(padj_vec) & padj_vec <= p_cutoff, na.rm = TRUE)
    if (n_sig == 0 && any(is.finite(pval_vec))) {
      use_padj <- FALSE
      message("[deg_heatmap] No padj-significant genes – using raw p-value.")
    }
  }
  df$p_plot <- if (isTRUE(use_padj) && any(is.finite(padj_vec))) padj_vec else pval_vec
  df$fc     <- suppressWarnings(as.numeric(df$log2FoldChange))
  df <- df[is.finite(df$fc) & is.finite(df$p_plot), , drop = FALSE]

  sig <- df[df$p_plot <= p_cutoff & abs(df$fc) >= fc_cutoff, , drop = FALSE]
  if (!nrow(sig)) stop("No differentially expressed genes pass the selected cutoffs.")
  sig <- sig[order(-abs(sig$fc)), , drop = FALSE]

  ad <- SummarizedExperiment::assays(empt)[[1]]
  cd <- as.data.frame(SummarizedExperiment::colData(empt))
  common <- intersect(sig$feature, rownames(ad))
  if (!length(common)) stop("DEG features not found in the current assay.")
  if (isTRUE(min_row_sum > 0)) {
    rs <- rowSums(ad[common, , drop = FALSE], na.rm = TRUE)
    keep <- names(rs)[rs > as.numeric(min_row_sum)]
    if (length(keep)) common <- keep
  }
  if (is.finite(max_genes) && length(common) > max_genes) {
    sub <- sig[sig$feature %in% common, , drop = FALSE]
    sub <- sub[order(-abs(sub$fc)), , drop = FALSE]
    common <- utils::head(sub$feature, max_genes)
  }
  sig <- sig[match(common, sig$feature), , drop = FALSE]

  ref_g  <- raw$ref_group
  test_g <- raw$test_group
  cmp_var <- raw$group_var %||% raw$group_var_orig

  if (!is.null(cmp_var) && cmp_var %in% names(cd) &&
      !is.null(ref_g) && !is.null(test_g)) {
    keep_s <- which(as.character(cd[[cmp_var]]) %in% c(ref_g, test_g))
    # Place reference group columns first, then test group (matches DESeq2 scripts).
    gvec <- as.character(cd[[cmp_var]][keep_s])
    keep_s <- keep_s[order(match(gvec, c(ref_g, test_g)), seq_along(gvec))]
  } else {
    keep_s <- seq_len(ncol(ad))
  }
  mat <- ad[common, keep_s, drop = FALSE]
  cd  <- cd[keep_s, , drop = FALSE]

  if (!isTRUE(cluster_rows) && nrow(mat) > 1L) {
    fc_ord <- stats::setNames(sig$fc, sig$feature)
    mat <- mat[order(fc_ord[rownames(mat)], decreasing = TRUE, na.last = TRUE), , drop = FALSE]
  }

  sym_map <- stats::setNames(
    make.unique(.viz_feature_labels(empt, as.character(sig$feature))),
    sig$feature
  )
  rownames(mat) <- sym_map[rownames(mat)]

  grp_col <- if (!is.null(group) && nzchar(group) && group %in% names(cd)) {
    group
  } else if (!is.null(cmp_var) && cmp_var %in% names(cd)) {
    cmp_var
  } else {
    pick0 <- .viz_pick_group(empt, NULL)
    if (!is.null(pick0)) pick0$name else names(cd)[1]
  }
  grp_vals <- as.character(cd[[grp_col]])
  grp_vals[is.na(grp_vals) | !nzchar(grp_vals)] <- "NA"
  grp_lv <- if (!is.null(ref_g) && !is.null(test_g)) {
    unique(c(ref_g, test_g, grp_vals))
  } else {
    unique(grp_vals)
  }
  grp <- factor(grp_vals, levels = grp_lv)

  title <- paste0("DEG heatmap (", nrow(mat), " genes)")
  subtitle <- paste0("|log2FC| >= ", fc_cutoff, ", ",
                     if (isTRUE(use_padj)) "padj" else "p", " <= ", p_cutoff,
                     if (min_row_sum > 0) paste0(", rowSum > ", min_row_sum) else "")

  show_rn <- isTRUE(show_rownames) && nrow(mat) <= 200
  out <- .viz_render_pheatmap(
    mat, grp, title = title, subtitle = subtitle,
    cluster_rows = cluster_rows, cluster_cols = cluster_cols,
    show_rownames = show_rn, font_size = font_size,
    color_panel = color_panel, pdf_path = pdf_path,
    width = width, height = height, ann_name = "Group"
  )
  list(png = out$png, pdf = out$pdf, n_genes = out$n_rows)
}

# -----------------------------------------------------------------------------
# Scatter / ordination: prefers EMP_dimension_analysis (PCoA / PCA / UMAP) when
# available so beta diversity matches Analysis > Dimension.  Falls back to a
# quick assay PCA when `ordination = "assay_pca"` or when cached coordinates
# no longer match the assay (e.g. after feature filtering).
# -----------------------------------------------------------------------------
make_scatter <- function(session_id, experiment, group = NULL,
                          dim1 = 1L, dim2 = 2L, width = 9, height = 7,
                          color_panel = NULL, ordination = "auto", custom_colors = NULL) {
  old_panel <- emp_set_color_panel(color_panel, custom_colors = custom_colors)
  on.exit(emp_restore_color_panel(old_panel), add = TRUE)
  ordination <- match.arg(
    tolower(trimws(as.character(ordination %||% "auto")[1])),
    c("auto", "emp", "assay_pca")
  )

  empt <- .viz_load_empt(session_id, experiment)
  ad   <- SummarizedExperiment::assays(empt)[[1]]
  cd   <- as.data.frame(SummarizedExperiment::colData(empt))
  if (ncol(ad) < 2 || nrow(ad) < 2) {
    stop("Ordination scatter needs at least 2 samples and 2 features.")
  }

  sample_ids <- colnames(ad)
  bundle <- .viz_emp_dimension_bundle(empt)
  use_emp <- FALSE
  if (!is.null(bundle) && .viz_dim_coords_match_assay(bundle$coord, sample_ids)) {
    if (identical(ordination, "assay_pca")) {
      use_emp <- FALSE
    } else if (identical(ordination, "emp")) {
      use_emp <- TRUE
    } else {
      use_emp <- TRUE
    }
  } else if (identical(ordination, "emp")) {
    stop(paste0("No usable EMP dimension coordinates for this experiment ",
                 "(run Analysis > Dimension first, or coordinates are out of ",
                 "date after filtering/collapse). Try ordination = auto or assay_pca."))
  }

  d1 <- max(1L, as.integer(dim1))
  d2 <- max(1L, as.integer(dim2))
  plot_title <- "Ordination"
  xlab <- "Axis 1"
  ylab <- "Axis 2"
  beta_permanova <- FALSE

  if (isTRUE(use_emp)) {
    coord <- bundle$coord
    axis_cols <- setdiff(names(coord), "primary")
    if (length(axis_cols) < 2L) {
      stop("Dimension result has fewer than two axes.")
    }
    d1 <- min(max(1L, as.integer(dim1)), length(axis_cols))
    d2 <- min(max(1L, as.integer(dim2)), length(axis_cols))
    if (d1 == d2) {
      d2 <- if (d1 < length(axis_cols)) d1 + 1L else d1 - 1L
      if (d2 < 1L) d2 <- 2L
    }
    c1 <- axis_cols[d1]; c2 <- axis_cols[d2]
    m <- match(sample_ids, as.character(coord$primary))
    if (anyNA(m)) stop("Sample IDs in dimension coordinates do not match the assay.")
    scores <- data.frame(
      PC_x = as.numeric(coord[[c1]][m]),
      PC_y = as.numeric(coord[[c2]][m]),
      sample = sample_ids,
      stringsAsFactors = FALSE
    )
    axp <- bundle$axis_pct
    if (!is.null(axp) && length(axp) >= max(d1, d2) && all(is.finite(axp))) {
      xlab <- sprintf("%s (%.1f%%)", c1, axp[d1])
      ylab <- sprintf("%s (%.1f%%)", c2, axp[d2])
    } else {
      xlab <- c1
      ylab <- c2
    }
    beta_permanova <- grepl("^pcoa", tolower(c1)) && grepl("^pcoa", tolower(c2))
    plot_title <- if (beta_permanova) {
      "PCoA (Bray–Curtis beta diversity)"
    } else if (grepl("^pc[0-9]", tolower(c1))) {
      "PCA (sample space)"
    } else if (grepl("^umap", tolower(c1))) {
      "UMAP"
    } else {
      "Dimension reduction"
    }
  } else {
    mat <- t(ad)
    mat[!is.finite(mat)] <- 0
    pca <- stats::prcomp(mat, center = TRUE, scale. = FALSE)
    vexp <- (pca$sdev^2) / sum(pca$sdev^2)
    dd1 <- max(1L, d1); dd2 <- max(dd1 + 1L, d2)
    dd1 <- min(dd1, ncol(pca$x)); dd2 <- min(dd2, ncol(pca$x))
    scores <- as.data.frame(pca$x[, c(dd1, dd2), drop = FALSE])
    names(scores) <- c("PC_x", "PC_y")
    scores$sample <- rownames(scores)
    plot_title <- "PCA (assay matrix, Euclidean)"
    xlab <- sprintf("PC%d (%.1f%%)", dd1, 100 * vexp[dd1])
    ylab <- sprintf("PC%d (%.1f%%)", dd2, 100 * vexp[dd2])
    beta_permanova <- FALSE
  }

  pick <- if (!is.null(group) && nzchar(group) && group %in% names(cd))
    list(name = group, values = cd[match(scores$sample, rownames(cd)), group]) else .viz_pick_group(empt, NULL)
  if (!is.null(pick)) {
    scores$group <- .viz_group_levels(pick$values)
    grp_name <- pick$name
  } else {
    scores$group <- factor("All")
    grp_name <- "Group"
  }

  caption <- NULL
  subtitle <- NULL
  if (length(levels(scores$group)) >= 2) {
    if (isTRUE(beta_permanova)) {
      pv <- emp_permanova_bray(ad, scores$group, method = "bray", permutations = 199)
      if (is.finite(pv)) {
        caption <- sprintf("PERMANOVA: p = %.3g (199 perms, Bray–Curtis)", pv)
      }
    } else {
      pv <- emp_permanova_p(scores[, c("PC_x", "PC_y"), drop = FALSE], scores$group)
      if (is.finite(pv)) {
        caption <- sprintf("PERMANOVA: p = %.3g (199 perms, Euclidean)", pv)
      }
    }
    ax <- .viz_axis_group_stats(scores, scores$group)
    if (!is.null(ax) && any(is.finite(unlist(ax)))) {
      subtitle <- sprintf(
        "Axis stats: %s p=%s, R2=%s | %s p=%s, R2=%s",
        sub(" \\(.*", "", xlab),
        if (is.finite(ax$p1)) formatC(ax$p1, format = "g", digits = 3) else "NA",
        if (is.finite(ax$r1)) formatC(ax$r1, format = "f", digits = 3) else "NA",
        sub(" \\(.*", "", ylab),
        if (is.finite(ax$p2)) formatC(ax$p2, format = "g", digits = 3) else "NA",
        if (is.finite(ax$r2)) formatC(ax$r2, format = "f", digits = 3) else "NA"
      )
    }
  }

  out <- .viz_ordination_compose(
    scores, plot_title = plot_title, xlab = xlab, ylab = ylab,
    grp_name = grp_name, caption = caption, subtitle = subtitle,
    width = width, height = height
  )
  plot_to_base64(out$plot, width = out$width, height = out$height)
}

# -----------------------------------------------------------------------------
# Stacked structure plot (relative abundance): top-N + Other, faceted by group
# -----------------------------------------------------------------------------
make_structure <- function(session_id, experiment, group = NULL,
                            top_n = 10L, width = 11, height = 6,
                            color_panel = NULL, custom_colors = NULL) {
  old_panel <- emp_set_color_panel(color_panel, custom_colors = custom_colors)
  on.exit(emp_restore_color_panel(old_panel), add = TRUE)
  empt <- .viz_load_empt(session_id, experiment)
  ad   <- SummarizedExperiment::assays(empt)[[1]]
  cd   <- as.data.frame(SummarizedExperiment::colData(empt))
  if (nrow(ad) == 0 || ncol(ad) == 0) stop("Assay matrix is empty.")

  top_n <- max(3L, as.integer(top_n))
  totals <- rowSums(ad, na.rm = TRUE)
  ord <- order(totals, decreasing = TRUE)
  topf <- rownames(ad)[ord[seq_len(min(top_n, nrow(ad)))]]
  other_rows <- setdiff(rownames(ad), topf)
  ad_top <- ad[topf, , drop = FALSE]
  top_labels <- make.unique(.viz_feature_labels(empt, topf))
  rownames(ad_top) <- top_labels
  if (length(other_rows)) {
    other_sum <- colSums(ad[other_rows, , drop = FALSE], na.rm = TRUE)
    ad_top <- rbind(ad_top, Other = other_sum)
  }
  rel <- sweep(ad_top, 2, colSums(ad_top, na.rm = TRUE), "/") * 100

  df <- as.data.frame(as.table(rel))
  names(df) <- c("Feature", "Sample", "Abundance")
  feat_order <- c(top_labels, if (length(other_rows)) "Other")
  df$Feature <- factor(df$Feature, levels = rev(feat_order))

  pick <- if (!is.null(group) && nzchar(group) && group %in% names(cd))
            list(name = group, values = cd[[group]]) else .viz_pick_group(empt, NULL)
  if (!is.null(pick)) {
    df$group <- .viz_group_levels(pick$values[match(as.character(df$Sample), rownames(cd))])
    grp_name <- pick$name
  } else {
    df$group <- factor("All")
    grp_name <- "Group"
  }

  pal_top <- emp_pub_palette(length(top_labels))
  pal <- c(pal_top, if (length(other_rows)) "grey70")
  names(pal) <- feat_order

  p <- ggplot2::ggplot(df, ggplot2::aes(x = Sample, y = Abundance, fill = Feature)) +
    ggplot2::geom_col(width = 0.95) +
    ggplot2::scale_fill_manual(values = pal, breaks = feat_order, name = "Feature") +
    ggplot2::scale_y_continuous(expand = c(0, 0), labels = function(z) paste0(z, "%")) +
    ggplot2::labs(title = paste0("Community structure (Top ", length(topf),
                                  if (length(other_rows)) " + Other" else "", ")"),
                  x = NULL, y = "Relative abundance") +
    emp_pub_theme(base_size = 11) +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, size = 7),
                   panel.grid.major.x = ggplot2::element_blank())
  if (length(levels(df$group)) > 1) {
    p <- p + ggplot2::facet_grid(~ group, scales = "free_x", space = "free_x") +
      ggplot2::theme(strip.background = ggplot2::element_rect(fill = "grey90"))
  }
  plot_to_base64(p, width = width, height = height)
}

# -----------------------------------------------------------------------------
# Alpha diversity boxplot with Wilcoxon p-values + sample sizes
# -----------------------------------------------------------------------------
make_alpha_plot <- function(session_id, experiment, group = NULL,
                             metric = "shannon", source = "current", width = 8, height = 6,
                             color_panel = NULL, custom_colors = NULL) {
  old_panel <- emp_set_color_panel(color_panel, custom_colors = custom_colors)
  on.exit(emp_restore_color_panel(old_panel), add = TRUE)
  empt <- .viz_load_empt(session_id, experiment)
  alpha_res <- tryCatch(run_alpha(session_id, experiment, method = metric, source = source), error = function(e) NULL)
  if (is.null(alpha_res)) stop("Could not compute alpha diversity table.")

  cd <- as.data.frame(SummarizedExperiment::colData(empt))
  df <- as.data.frame(alpha_res, check.names = FALSE)
  # Normalise sample ID column across possible names
  if ("primary" %in% names(df)) {
    df$sample <- as.character(df$primary)
  } else if ("sample" %in% names(df)) {
    df$sample <- as.character(df$sample)
  } else if ("sampleID" %in% names(df)) {
    df$sample <- as.character(df$sampleID)
  } else {
    df$sample <- as.character(rownames(df))
  }
  # If df rownames/sample IDs are just integers, fall back to colData rownames
  if (all(grepl("^[0-9]+$", df$sample)) && nrow(df) == nrow(cd)) {
    df$sample <- rownames(cd)[as.integer(df$sample)]
  }

  excl_cols <- c("sample", "primary", "sampleID")
  candidate <- setdiff(names(df), excl_cols)
  metric_key <- tolower(trimws(as.character(metric)))
  metric_alias <- c(
    "shannon" = "shannon",
    "simpson" = "simpson",
    "invsimpson" = "invsimpson",
    "chao1" = "chao1",
    "ace" = "ace",
    "observed" = "observed|observerd",
    "pielou" = "pielou"
  )
  metric_pat <- metric_alias[[metric_key]] %||% metric_key
  metric_col <- grep(metric_pat, candidate, ignore.case = TRUE, value = TRUE)[1]
  if (is.na(metric_col)) {
    # Recompute via analysis helper to guarantee full alpha column set.
    alpha_full <- tryCatch(run_alpha(session_id, experiment, method = metric_key, source = source), error = function(e) NULL)
    if (!is.null(alpha_full) && nrow(alpha_full)) {
      df2 <- as.data.frame(alpha_full, check.names = FALSE)
      if ("primary" %in% names(df2)) {
        df2$sample <- as.character(df2$primary)
      } else if ("sample" %in% names(df2)) {
        df2$sample <- as.character(df2$sample)
      } else if ("sampleID" %in% names(df2)) {
        df2$sample <- as.character(df2$sampleID)
      } else {
        df2$sample <- as.character(rownames(df2))
      }
      candidate2 <- setdiff(names(df2), excl_cols)
      metric_col <- grep(metric_pat, candidate2, ignore.case = TRUE, value = TRUE)[1]
      if (!is.na(metric_col)) df <- df2
    }
  }
  if (is.na(metric_col)) metric_col <- candidate[1]
  if (is.na(metric_col)) stop("Could not find an alpha-diversity metric column.")

  pick <- if (!is.null(group) && nzchar(group) && group %in% names(cd))
            list(name = group, values = cd[match(df$sample, rownames(cd)), group]) else .viz_pick_group(empt, NULL)
  if (!is.null(pick)) {
    df$group <- .viz_group_levels(pick$values)
    grp_name <- pick$name
  } else {
    df$group <- factor("All"); grp_name <- "Group"
  }

  df$value <- suppressWarnings(as.numeric(df[[metric_col]]))

  p <- ggplot2::ggplot(df, ggplot2::aes(x = group, y = value, fill = group)) +
    ggplot2::geom_boxplot(alpha = 0.6, outlier.shape = NA, width = 0.55) +
    ggplot2::geom_jitter(ggplot2::aes(color = group), width = 0.18, size = 1.8, alpha = 0.85) +
    emp_scale_fill_pub(name = grp_name, n_hint = length(levels(df$group))) +
    emp_scale_color_pub(name = grp_name, n_hint = length(levels(df$group))) +
    ggplot2::labs(title = paste(metric_col, "diversity"), x = grp_name, y = metric_col) +
    emp_pub_theme() +
    ggplot2::theme(legend.position = "none")

  if (length(levels(df$group)) >= 2 && requireNamespace("ggpubr", quietly = TRUE)) {
    pw <- emp_pairwise_wilcox(df$value, df$group)
    if (!is.null(pw) && nrow(pw)) {
      comps <- lapply(seq_len(nrow(pw)), function(i) c(pw$group1[i], pw$group2[i]))
      p <- p + ggpubr::stat_compare_means(comparisons = comps, method = "wilcox.test",
                                           label = "p.signif", tip.length = 0.01,
                                           hide.ns = FALSE, size = 3.6)
    }
  }
  ns <- table(df$group)
  cap <- paste(paste0(names(ns), "=n", as.integer(ns)), collapse = ", ")
  p <- emp_caption(p, paste("Wilcoxon rank-sum;", cap))
  plot_to_base64(p, width = width, height = height)
}
