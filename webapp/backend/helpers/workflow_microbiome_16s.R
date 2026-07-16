# 16S-specific workflow helpers for taxonomy-aware preparation and visualization.

.m16s_tax_levels <- c("Domain", "Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species", "Strain")

m16s_parse_taxonomy <- function(x, tax_sep = ";") {
  parts <- strsplit(as.character(x), tax_sep, fixed = TRUE)[[1]]
  parts <- trimws(parts)
  parts[parts == ""] <- NA_character_
  parts
}

m16s_tax_index <- function(level) {
  idx <- match(level, .m16s_tax_levels)
  if (is.na(idx)) stop("Invalid taxonomy level. Use one of: ", paste(.m16s_tax_levels, collapse = ", "))
  idx
}

m16s_taxonomy_parts <- function(empt, tax_sep = ";") {
  ad <- SummarizedExperiment::assays(empt)[[1]]
  taxa_raw <- rownames(ad)
  if (!is.null(taxa_raw) && any(grepl(tax_sep, taxa_raw, fixed = TRUE))) {
    return(lapply(taxa_raw, m16s_parse_taxonomy, tax_sep = tax_sep))
  }

  rd <- tryCatch(as.data.frame(SummarizedExperiment::rowData(empt)), error = function(e) data.frame())
  level_cols <- intersect(.m16s_tax_levels, names(rd))
  if (!length(level_cols)) {
    feature_col <- if ("feature" %in% names(rd)) as.character(rd$feature) else taxa_raw
    return(lapply(feature_col, m16s_parse_taxonomy, tax_sep = tax_sep))
  }

  lapply(seq_len(nrow(rd)), function(i) {
    vals <- as.character(rd[i, level_cols, drop = TRUE])
    vals[is.na(vals) | vals == ""] <- NA_character_
    names(vals) <- level_cols
    out <- rep(NA_character_, length(.m16s_tax_levels))
    names(out) <- .m16s_tax_levels
    out[level_cols] <- vals
    unname(out)
  })
}

m16s_validate_session_experiment <- function(session_id, experiment) {
  if (is.null(session_id) || !nzchar(session_id)) stop("session_id is required.")
  if (is.null(experiment) || !nzchar(experiment)) stop("experiment is required.")
}

m16s_validate_numeric <- function(x, name, min_value = -Inf, max_value = Inf) {
  if (is.null(x) || is.na(x)) stop(name, " is required.")
  val <- suppressWarnings(as.numeric(x))
  if (is.na(val)) stop(name, " must be numeric.")
  if (val < min_value || val > max_value) {
    stop(name, " must be between ", min_value, " and ", max_value, ".")
  }
  val
}

m16s_prepare_taxonomy <- function(empt, tax_sep = ";", collapse_level = "Genus",
                                  min_total_abundance = 0, drop_unassigned = TRUE,
                                  keep_top_n = 0L) {
  if (is.null(empt)) stop("Experiment object is empty.")
  ad <- SummarizedExperiment::assays(empt)[[1]]
  if (is.null(ad) || nrow(ad) == 0 || ncol(ad) == 0) stop("Assay matrix is empty.")

  level_idx <- m16s_tax_index(collapse_level)
  taxa_parts <- m16s_taxonomy_parts(empt, tax_sep = tax_sep)
  if (!length(taxa_parts)) stop("No feature/taxonomy names found in assay rows.")

  taxa_label <- vapply(taxa_parts, function(parts) {
    val <- if (length(parts) >= level_idx) parts[level_idx] else NA_character_
    if (is.na(val) || !nzchar(val)) "Unassigned" else val
  }, character(1))

  grouped <- rowsum(ad, group = taxa_label, reorder = FALSE, na.rm = TRUE)
  totals <- rowSums(grouped, na.rm = TRUE)
  keep <- rep(TRUE, length(totals))

  if (drop_unassigned && "Unassigned" %in% rownames(grouped)) {
    keep <- keep & rownames(grouped) != "Unassigned"
  }
  if (min_total_abundance > 0) {
    keep <- keep & totals >= min_total_abundance
  }
  if (isTRUE(keep_top_n > 0)) {
    ord <- order(totals, decreasing = TRUE)
    top_names <- rownames(grouped)[ord[seq_len(min(length(ord), as.integer(keep_top_n)))]]
    keep <- keep & rownames(grouped) %in% top_names
  }

  grouped <- grouped[keep, , drop = FALSE]
  if (!nrow(grouped)) stop("All taxa were filtered out. Relax filtering thresholds.")

  # Many downstream EMP_* analyses (alpha, tax composition, enterotype)
  # assume an *integer* count matrix. rowsum() on an integer matrix can
  # still return numeric, so coerce back explicitly and drop NAs.
  storage.mode(grouped) <- "integer"
  grouped[is.na(grouped)] <- 0L

  new_rd <- S4Vectors::DataFrame(
    feature        = rownames(grouped),
    Name           = rownames(grouped),
    taxon          = rownames(grouped),
    taxonomy_level = collapse_level,
    row.names      = rownames(grouped)
  )
  assay_name <- names(SummarizedExperiment::assays(empt))[1]
  new_empt <- SummarizedExperiment::SummarizedExperiment(
    assays  = list(tmp_assay = grouped),
    colData = SummarizedExperiment::colData(empt),
    rowData = new_rd
  )
  names(SummarizedExperiment::assays(new_empt))[1] <- assay_name
  new_empt
}

m16s_make_sankey <- function(empt, tax_sep = ";", from_level = "Phylum", to_level = "Genus",
                             top_n = 25L, width = 11, height = 7,
                             color_panel = NULL, custom_colors = NULL,
                             session_id = NULL, experiment = NULL) {
  old_panel <- emp_set_color_panel(color_panel, custom_colors = custom_colors)
  on.exit(emp_restore_color_panel(old_panel), add = TRUE)
  from_idx <- m16s_tax_index(from_level)
  to_idx <- m16s_tax_index(to_level)
  if (from_idx >= to_idx) stop("from_level must be broader than to_level.")

  ad <- SummarizedExperiment::assays(empt)[[1]]
  if (is.null(ad) || nrow(ad) == 0) stop("No abundance data available.")

  totals <- rowSums(ad, na.rm = TRUE)
  top_idx <- order(totals, decreasing = TRUE)[seq_len(min(length(totals), as.integer(top_n)))]
  top_ad <- ad[top_idx, , drop = FALSE]
  taxa_parts <- m16s_taxonomy_parts(empt, tax_sep = tax_sep)[top_idx]

  edges <- do.call(rbind, lapply(seq_along(taxa_parts), function(i) {
    parts <- taxa_parts[[i]]
    from <- if (length(parts) >= from_idx && !is.na(parts[from_idx]) && nzchar(parts[from_idx]))
              parts[from_idx] else "Unassigned"
    to <- if (length(parts) >= to_idx && !is.na(parts[to_idx]) && nzchar(parts[to_idx]))
              parts[to_idx] else "Unassigned"
    data.frame(from = from, to = to, weight = sum(top_ad[i, ], na.rm = TRUE), stringsAsFactors = FALSE)
  }))
  edges <- stats::aggregate(weight ~ from + to, data = edges, FUN = sum)
  if (!nrow(edges)) stop("No valid taxonomy edges were generated.")

  # Order nodes from largest to smallest aggregate flow → cleaner ribbon stack.
  from_w <- stats::aggregate(weight ~ from, data = edges, FUN = sum)
  to_w   <- stats::aggregate(weight ~ to,   data = edges, FUN = sum)
  from_nodes <- from_w$from[order(-from_w$weight)]
  to_nodes   <- to_w$to[order(-to_w$weight)]

  total <- sum(edges$weight, na.rm = TRUE)
  if (total <= 0) stop("Sum of edge weights is zero.")

  # Stack node bars vertically with proportional heights (Sankey style).
  from_pos <- data.frame(node = from_nodes,
                         h = from_w$weight[match(from_nodes, from_w$from)] / total,
                         stringsAsFactors = FALSE)
  from_pos$top <- cumsum(from_pos$h)
  from_pos$bot <- from_pos$top - from_pos$h
  from_pos$mid <- (from_pos$top + from_pos$bot) / 2

  to_pos <- data.frame(node = to_nodes,
                       h = to_w$weight[match(to_nodes, to_w$to)] / total,
                       stringsAsFactors = FALSE)
  to_pos$top <- cumsum(to_pos$h)
  to_pos$bot <- to_pos$top - to_pos$h
  to_pos$mid <- (to_pos$top + to_pos$bot) / 2

  # Edge ribbons: stack within each from/to node by weight.
  edges <- edges[order(match(edges$from, from_nodes), match(edges$to, to_nodes)), ]
  edges$h <- edges$weight / total

  ribbons <- vector("list", nrow(edges))
  from_cum <- stats::setNames(rep(0, length(from_nodes)), from_nodes)
  to_cum   <- stats::setNames(rep(0, length(to_nodes)),   to_nodes)
  curve_n <- 60
  for (i in seq_len(nrow(edges))) {
    e <- edges[i, ]
    fb_top <- from_pos$bot[match(e$from, from_nodes)] + from_cum[[e$from]] + e$h
    fb_bot <- from_pos$bot[match(e$from, from_nodes)] + from_cum[[e$from]]
    tb_top <- to_pos$bot[match(e$to, to_nodes)]   + to_cum[[e$to]]   + e$h
    tb_bot <- to_pos$bot[match(e$to, to_nodes)]   + to_cum[[e$to]]
    from_cum[[e$from]] <- from_cum[[e$from]] + e$h
    to_cum[[e$to]]     <- to_cum[[e$to]]     + e$h

    t <- seq(0, 1, length.out = curve_n)
    sigmoid <- 1 / (1 + exp(-12 * (t - 0.5)))
    x_vals <- c(0 + t, rev(0 + t))
    y_top <- fb_top + (tb_top - fb_top) * sigmoid
    y_bot <- fb_bot + (tb_bot - fb_bot) * sigmoid
    ribbons[[i]] <- data.frame(
      x = c(t, rev(t)),
      y = c(y_top, rev(y_bot)),
      group = paste0("edge_", i),
      from  = e$from,
      stringsAsFactors = FALSE
    )
  }
  ribbon_df <- do.call(rbind, ribbons)

  pal <- emp_pub_palette(length(from_nodes), name = color_panel %||% emp_get_color_panel("npg"))
  names(pal) <- from_nodes

  p <- ggplot2::ggplot() +
    ggplot2::geom_polygon(data = ribbon_df,
                           ggplot2::aes(x = x, y = y, group = group, fill = from),
                           alpha = 0.55, color = NA) +
    ggplot2::geom_rect(data = from_pos,
                        ggplot2::aes(xmin = -0.04, xmax = 0, ymin = bot, ymax = top, fill = node),
                        color = "grey20", linewidth = 0.3) +
    ggplot2::geom_rect(data = to_pos,
                        ggplot2::aes(xmin = 1, xmax = 1.04, ymin = bot, ymax = top),
                        fill = "grey80", color = "grey20", linewidth = 0.3) +
    ggplot2::geom_text(data = from_pos, ggplot2::aes(x = -0.05, y = mid, label = node),
                        hjust = 1, size = 3.2) +
    ggplot2::geom_text(data = to_pos, ggplot2::aes(x = 1.05, y = mid, label = node),
                        hjust = 0, size = 3.2) +
    ggplot2::scale_fill_manual(name = from_level, values = pal) +
    ggplot2::scale_x_continuous(breaks = c(0, 1), labels = c(from_level, to_level),
                                 limits = c(-0.45, 1.45)) +
    ggplot2::scale_y_continuous(expand = c(0.01, 0.01)) +
    ggplot2::labs(title = paste0("Taxonomy flow: ", from_level, " \u2192 ", to_level),
                  subtitle = paste0("Top ", length(top_idx), " taxa, ribbon width \u221d abundance"),
                  x = NULL, y = NULL) +
    emp_pub_theme(base_size = 11) +
    ggplot2::theme(axis.text.y = ggplot2::element_blank(),
                   axis.ticks.y = ggplot2::element_blank(),
                   panel.grid = ggplot2::element_blank(),
                   panel.border = ggplot2::element_blank(),
                   axis.line = ggplot2::element_blank(),
                   legend.position = "none")

  result <- list(plot = plot_to_base64(p, width = width, height = height),
       edges = nrow(edges),
       from_nodes = length(from_nodes),
       to_nodes = length(to_nodes))
  if (!is.null(session_id) && nzchar(session_id) &&
      !is.null(experiment) && nzchar(experiment)) {
    pdf <- viz_save_session_pdf(p, session_id, experiment, "sankey", width, height)
    result <- c(result, viz_pdf_meta(pdf))
  }
  result
}

m16s_make_network <- function(empt, method = "spearman", cutoff = 0.6,
                              top_n = 40L, width = 9, height = 8,
                              session_id = NULL, experiment = NULL) {
  method <- tolower(method)
  if (!method %in% c("spearman", "pearson")) stop("method must be 'spearman' or 'pearson'.")
  if (cutoff <= 0 || cutoff > 1) stop("cutoff must be in (0, 1].")

  ad <- SummarizedExperiment::assays(empt)[[1]]
  if (is.null(ad) || nrow(ad) < 2) stop("Need at least 2 taxa for network plotting.")
  totals <- rowSums(ad, na.rm = TRUE)
  keep_idx <- order(totals, decreasing = TRUE)[seq_len(min(length(totals), as.integer(top_n)))]
  ad <- ad[keep_idx, , drop = FALSE]
  taxa <- rownames(ad)

  cor_mat <- suppressWarnings(stats::cor(t(ad), method = method, use = "pairwise.complete.obs"))
  if (all(is.na(cor_mat))) stop("Could not compute correlation matrix for selected taxa.")

  upper <- which(upper.tri(cor_mat) & abs(cor_mat) >= cutoff, arr.ind = TRUE)
  if (!nrow(upper)) stop("No edges passed the cutoff. Try a lower cutoff.")

  edges <- data.frame(
    from   = taxa[upper[, 1]],
    to     = taxa[upper[, 2]],
    weight = cor_mat[upper],
    stringsAsFactors = FALSE
  )
  node_names <- unique(c(edges$from, edges$to))

  # Force-directed layout via igraph if available (much cleaner than circular).
  if (requireNamespace("igraph", quietly = TRUE)) {
    g <- igraph::graph_from_data_frame(
      d = edges[, c("from", "to", "weight")],
      vertices = data.frame(name = node_names, stringsAsFactors = FALSE),
      directed = FALSE
    )
    layout_mat <- igraph::layout_with_fr(g, weights = abs(igraph::E(g)$weight))
    nodes <- data.frame(name = igraph::V(g)$name,
                         x = layout_mat[, 1], y = layout_mat[, 2],
                         degree = as.integer(igraph::degree(g)),
                         stringsAsFactors = FALSE)
  } else {
    n <- length(node_names)
    theta <- seq(0, 2 * pi, length.out = n + 1)[-1]
    nodes <- data.frame(name = node_names, x = cos(theta), y = sin(theta),
                         degree = as.integer(table(c(edges$from, edges$to))[node_names]),
                         stringsAsFactors = FALSE)
  }

  edges$x    <- nodes$x[match(edges$from, nodes$name)]
  edges$y    <- nodes$y[match(edges$from, nodes$name)]
  edges$xend <- nodes$x[match(edges$to,   nodes$name)]
  edges$yend <- nodes$y[match(edges$to,   nodes$name)]
  nodes$abundance <- as.numeric(rowSums(ad, na.rm = TRUE)[match(nodes$name, taxa)])
  if (any(!is.finite(nodes$abundance))) nodes$abundance[!is.finite(nodes$abundance)] <- 0
  if (max(nodes$abundance, na.rm = TRUE) == 0) nodes$abundance <- 1

  # Prefer descriptive taxonomy labels from rowData (Genus > Family > ...).
  nodes$short <- .viz_feature_labels(empt, nodes$name)
  # Fallback for purely semicolon-delimited names (legacy behaviour).
  miss <- nodes$short == nodes$name & grepl(";", nodes$name, fixed = TRUE)
  if (any(miss)) {
    nodes$short[miss] <- vapply(nodes$name[miss], function(nm) {
      parts <- strsplit(nm, ";", fixed = TRUE)[[1]]
      last <- parts[length(parts)]
      if (is.na(last) || !nzchar(last)) nm else last
    }, character(1))
  }

  p <- ggplot2::ggplot() +
    ggplot2::geom_segment(data = edges,
                           ggplot2::aes(x = x, y = y, xend = xend, yend = yend,
                                         color = weight, linewidth = abs(weight)),
                           alpha = 0.6, lineend = "round") +
    ggplot2::geom_point(data = nodes,
                         ggplot2::aes(x = x, y = y, size = abundance),
                         fill = "#fde68a", color = "grey20", shape = 21, stroke = 0.4) +
    ggplot2::scale_color_gradient2(name = "Correlation",
                                    low = "#2166ac", mid = "grey80", high = "#b2182b",
                                    midpoint = 0, limits = c(-1, 1)) +
    ggplot2::scale_linewidth(range = c(0.25, 1.6), guide = "none") +
    ggplot2::scale_size(range = c(2.5, 8), name = "Total abundance") +
    ggplot2::coord_equal() +
    ggplot2::labs(title = "Taxa correlation network",
                  subtitle = paste0("method = ", method, ", |r| \u2265 ", cutoff,
                                     ", top ", length(taxa), " taxa")) +
    emp_pub_theme(base_size = 11) +
    ggplot2::theme(axis.title = ggplot2::element_blank(),
                   axis.text  = ggplot2::element_blank(),
                   axis.ticks = ggplot2::element_blank(),
                   panel.grid = ggplot2::element_blank(),
                   panel.border = ggplot2::element_blank(),
                   axis.line  = ggplot2::element_blank())

  if (requireNamespace("ggrepel", quietly = TRUE)) {
    p <- p + ggrepel::geom_text_repel(data = nodes,
                                       ggplot2::aes(x = x, y = y, label = short),
                                       size = 2.6, max.overlaps = 30,
                                       segment.color = "grey60", segment.size = 0.2,
                                       min.segment.length = 0)
  } else {
    p <- p + ggplot2::geom_text(data = nodes,
                                 ggplot2::aes(x = x, y = y, label = short),
                                 nudge_y = 0.06, size = 2.6)
  }

  result <- list(plot = plot_to_base64(p, width = width, height = height),
       nodes = nrow(nodes),
       edges = nrow(edges),
       method = method,
       cutoff = cutoff)
  if (!is.null(session_id) && nzchar(session_id) &&
      !is.null(experiment) && nzchar(experiment)) {
    pdf <- viz_save_session_pdf(p, session_id, experiment, "network", width, height)
    result <- c(result, viz_pdf_meta(pdf))
  }
  result
}
