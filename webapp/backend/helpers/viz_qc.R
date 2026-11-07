# viz_qc.R - EMP Web v9.1.0 Round 2: QC / network visualization.
#
# ggplot2-based figures for the rigor QC result (emp_qc_rigor) and for
# cross-omics correlation networks (emp_cross_omics_network). Design
# rules:
#   - ggplot2 is guarded with requireNamespace(): when it is missing the
#     functions return NULL and say so, instead of erroring mid-request.
#   - The publication theme emp_pub_theme() (plot_theme.R) is used when
#     it has been sourced, and every plot's text family is set from
#     emp_plot_font_family(locale) so CJK / Arabic labels do not render
#     as boxes (see docs/I18N_PLATFORM_v910.md).
#   - Panels are combined with patchwork when available; otherwise the
#     list of panels is returned so the caller can arrange them.
#   - No igraph dependency: the network layout is a deterministic circle.

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
}

.qc_theme <- function(locale) {
  base <- if (exists("emp_pub_theme", mode = "function")) {
    emp_pub_theme()
  } else {
    ggplot2::theme_bw()
  }
  fam <- "sans"
  if (exists("emp_plot_font_family", mode = "function")) {
    fam <- tryCatch(emp_plot_font_family(locale), error = function(e) "sans")
  }
  base + ggplot2::theme(text = ggplot2::element_text(family = fam))
}

#' QC dashboard for an emp_qc_rigor() result.
#'
#' Panels: (1) per-sample missingness bars, (2) per-feature missingness
#' distribution, (3) batch / group association tile (PCA R-squared per
#' factor, or the batch x group confounding summary when PCA results are
#' absent). Older QC results without the per-sample/per-feature vectors
#' fall back to the scalar missingness summaries.
#'
#' @return A patchwork object when patchwork is available, otherwise a
#'   named list of ggplots; NULL (with a message) when ggplot2 is absent
#'   or `qc` carries no plottable checks.
emp_plot_qc_dashboard <- function(qc, locale = "en") {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    message("emp_plot_qc_dashboard: ggplot2 is not available; returning NULL.")
    return(NULL)
  }
  if (!is.list(qc) || is.null(qc$checks)) {
    message("emp_plot_qc_dashboard: `qc` is not an emp_qc_rigor() result.")
    return(NULL)
  }
  th <- .qc_theme(locale)
  panels <- list()

  miss <- qc$checks$missingness
  if (!is.null(miss)) {
    if (!is.null(miss$per_sample) && length(miss$per_sample) > 0) {
      df <- data.frame(
        sample = names(miss$per_sample),
        missing = as.numeric(miss$per_sample),
        stringsAsFactors = FALSE
      )
      if (is.null(df$sample) || any(!nzchar(df$sample))) {
        df$sample <- paste0("S", seq_len(nrow(df)))
      }
      panels$per_sample_missingness <- ggplot2::ggplot(
        df, ggplot2::aes(x = sample, y = missing)
      ) +
        ggplot2::geom_col(fill = "#4E79A7") +
        ggplot2::scale_y_continuous(limits = c(0, 1)) +
        ggplot2::labs(title = "Per-sample missingness", x = NULL,
                      y = "Proportion missing") +
        th +
        ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 90, hjust = 1))
    } else {
      df <- data.frame(
        measure = c("Overall", "Max per sample", "Max per feature"),
        missing = c(miss$overall %||% NA_real_,
                    miss$max_per_sample %||% NA_real_,
                    miss$max_per_feature %||% NA_real_),
        stringsAsFactors = FALSE
      )
      panels$missingness_summary <- ggplot2::ggplot(
        df, ggplot2::aes(x = measure, y = missing)
      ) +
        ggplot2::geom_col(fill = "#4E79A7") +
        ggplot2::scale_y_continuous(limits = c(0, 1)) +
        ggplot2::labs(title = "Missingness summary", x = NULL,
                      y = "Proportion missing") +
        th
    }

    if (!is.null(miss$per_feature) && length(miss$per_feature) > 0) {
      df <- data.frame(missing = as.numeric(miss$per_feature))
      panels$per_feature_missingness <- ggplot2::ggplot(
        df, ggplot2::aes(x = missing)
      ) +
        ggplot2::geom_histogram(bins = 30, fill = "#59A14F",
                                colour = "white") +
        ggplot2::scale_x_continuous(limits = c(0, 1)) +
        ggplot2::labs(title = "Per-feature missingness", x = "Proportion missing",
                      y = "Features") +
        th
    }
  }

  # Batch / group association tile.
  tile_df <- NULL
  pcs <- qc$checks$pca$pcs
  if (!is.null(pcs) && length(pcs) > 0) {
    rows <- lapply(pcs, function(entry) {
      out <- list()
      if (!is.null(entry$batch_r2)) {
        out[[length(out) + 1]] <- data.frame(
          pc = entry$pc, factor = "batch", r2 = as.numeric(entry$batch_r2),
          stringsAsFactors = FALSE)
      }
      if (!is.null(entry$group_r2)) {
        out[[length(out) + 1]] <- data.frame(
          pc = entry$pc, factor = "group", r2 = as.numeric(entry$group_r2),
          stringsAsFactors = FALSE)
      }
      out
    })
    rows <- Filter(Negate(is.null), unlist(rows, recursive = FALSE))
    if (length(rows)) tile_df <- do.call(rbind, rows)
  }
  if (is.null(tile_df) && !is.null(qc$checks$batch_group_confounding)) {
    conf <- qc$checks$batch_group_confounding
    if (!is.null(conf$cramers_v)) {
      tile_df <- data.frame(pc = "batch x group", factor = "cramers_v",
                            r2 = as.numeric(conf$cramers_v),
                            stringsAsFactors = FALSE)
    }
  }
  if (!is.null(tile_df) && nrow(tile_df) > 0) {
    panels$batch_group_tile <- ggplot2::ggplot(
      tile_df, ggplot2::aes(x = factor, y = pc, fill = r2)
    ) +
      ggplot2::geom_tile(colour = "white") +
      ggplot2::geom_text(ggplot2::aes(label = sprintf("%.2f", r2)), size = 3) +
      ggplot2::scale_fill_gradient(low = "#F1F5F9", high = "#E15759",
                                   limits = c(0, 1)) +
      ggplot2::labs(title = "Batch / group association", x = NULL, y = NULL,
                    fill = "R2 / V") +
      th
  }

  if (length(panels) == 0) {
    message("emp_plot_qc_dashboard: no plottable QC checks found.")
    return(NULL)
  }
  if (requireNamespace("patchwork", quietly = TRUE)) {
    return(patchwork::wrap_plots(panels) +
             patchwork::plot_annotation(title = "Rigor QC dashboard"))
  }
  panels
}

#' Cross-omics correlation network plot (circle layout, no igraph).
#'
#' @param edges data.frame(from, to, cor, p_adj) as returned by
#'   emp_cross_omics_network().
#' @return A ggplot, or NULL when ggplot2 is absent or `edges` is empty.
emp_plot_crossomics_network <- function(edges, locale = "en") {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    message("emp_plot_crossomics_network: ggplot2 is not available; returning NULL.")
    return(NULL)
  }
  if (is.null(edges) || !is.data.frame(edges) || nrow(edges) == 0 ||
      !all(c("from", "to", "cor") %in% names(edges))) {
    message("emp_plot_crossomics_network: no edges to plot.")
    return(NULL)
  }
  nodes <- unique(c(as.character(edges$from), as.character(edges$to)))
  k <- length(nodes)
  ang <- if (k > 1) 2 * pi * (seq_len(k) - 1) / k else 0
  pos <- data.frame(
    node = nodes,
    x = cos(ang),
    y = sin(ang),
    side = ifelse(nodes %in% as.character(edges$from), "A", "B"),
    stringsAsFactors = FALSE
  )
  seg <- data.frame(
    x = pos$x[match(as.character(edges$from), pos$node)],
    y = pos$y[match(as.character(edges$from), pos$node)],
    xend = pos$x[match(as.character(edges$to), pos$node)],
    yend = pos$y[match(as.character(edges$to), pos$node)],
    cor = as.numeric(edges$cor),
    stringsAsFactors = FALSE
  )
  seg <- seg[stats::complete.cases(seg), , drop = FALSE]
  ggplot2::ggplot() +
    ggplot2::geom_segment(
      data = seg,
      ggplot2::aes(x = x, y = y, xend = xend, yend = yend,
                   alpha = abs(cor), colour = cor > 0)
    ) +
    ggplot2::geom_point(
      data = pos,
      ggplot2::aes(x = x, y = y, shape = side),
      size = 3, colour = "grey20"
    ) +
    ggplot2::geom_text(
      data = pos,
      ggplot2::aes(x = x * 1.14, y = y * 1.14, label = node),
      size = 3
    ) +
    ggplot2::scale_alpha_continuous(range = c(0.15, 0.9), guide = "none") +
    ggplot2::scale_colour_manual(
      values = c(`TRUE` = "#2166AC", `FALSE` = "#B2182B"),
      guide = "none"
    ) +
    ggplot2::coord_equal() +
    ggplot2::labs(title = "Cross-omics correlation network") +
    .qc_theme(locale) +
    ggplot2::theme(
      axis.text = ggplot2::element_blank(),
      axis.ticks = ggplot2::element_blank(),
      axis.title = ggplot2::element_blank(),
      panel.grid = ggplot2::element_blank()
    )
}

#' Save a plot with locale-aware text family and device by extension.
#'
#' Supports .pdf, .svg and .png (any other extension is left to
#' ggsave's extension-based default device). The locale font family is
#' passed to the device for PDF/PNG output. Returns the file path.
emp_save_plot_i18n <- function(plot, file, locale = "en", width = 10,
                               height = 8, dpi = 300) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("emp_save_plot_i18n: ggplot2 is required to save plots.")
  }
  if (is.null(plot)) stop("emp_save_plot_i18n: `plot` is NULL.")
  ext <- tolower(tools::file_ext(file))
  device <- switch(ext,
    pdf = grDevices::cairo_pdf,
    png = "png",
    NULL
  )
  if (identical(ext, "svg") && requireNamespace("svglite", quietly = TRUE)) {
    device <- function(...) svglite::svglite(...)
  }
  args <- list(filename = file, plot = plot, width = width,
               height = height, dpi = dpi)
  if (!is.null(device)) args$device <- device
  # The graphics `family` argument is honoured by the PDF/PNG devices;
  # SVG output carries the family through the plot theme instead.
  if (ext %in% c("pdf", "png") &&
      exists("emp_plot_font_family", mode = "function")) {
    args$family <- tryCatch(emp_plot_font_family(locale),
                            error = function(e) "sans")
  }
  do.call(ggplot2::ggsave, args)
  file
}
