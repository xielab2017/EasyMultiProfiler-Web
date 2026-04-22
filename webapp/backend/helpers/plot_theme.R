#  Publication-grade theme, palettes and stat helpers (CNS quality).
#
#  Design goals
#  ------------
#  * Crisp, journal-ready typography (sans-serif, ~12pt axis text).
#  * Editorial colour palettes (ggsci NPG / Lancet / NEJM) with safe fallbacks.
#  * Diverging palette for log2FC/z-score plots (RdBu via RColorBrewer).
#  * Built-in helpers for confidence ellipses, PERMANOVA p-values, FC labelling.
#  * 300 DPI rendering hooks (consumed by `plot_to_base64`).

emp_pub_packages <- function() {
  list(
    ggrepel = requireNamespace("ggrepel", quietly = TRUE),
    ggsci = requireNamespace("ggsci", quietly = TRUE),
    ggpubr = requireNamespace("ggpubr", quietly = TRUE),
    vegan = requireNamespace("vegan", quietly = TRUE),
    viridisLite = requireNamespace("viridisLite", quietly = TRUE),
    RColorBrewer = requireNamespace("RColorBrewer", quietly = TRUE),
    igraph = requireNamespace("igraph", quietly = TRUE)
  )
}

emp_pub_theme <- function(base_size = 12) {
  ggplot2::theme_bw(base_size = base_size, base_family = "") +
    ggplot2::theme(
      plot.title       = ggplot2::element_text(size = base_size + 2, face = "bold", hjust = 0.5,
                                                margin = ggplot2::margin(b = 6)),
      plot.subtitle    = ggplot2::element_text(size = base_size - 1, hjust = 0.5, colour = "grey30"),
      plot.caption     = ggplot2::element_text(size = base_size - 3, hjust = 1, colour = "grey40"),
      axis.title       = ggplot2::element_text(size = base_size, face = "bold"),
      axis.text        = ggplot2::element_text(size = base_size - 1, colour = "grey15"),
      axis.ticks       = ggplot2::element_line(colour = "grey30", linewidth = 0.4),
      axis.line        = ggplot2::element_line(colour = "grey20", linewidth = 0.5),
      panel.border     = ggplot2::element_rect(colour = "grey20", fill = NA, linewidth = 0.6),
      panel.grid.major = ggplot2::element_line(colour = "grey92", linewidth = 0.3),
      panel.grid.minor = ggplot2::element_blank(),
      strip.background = ggplot2::element_rect(colour = "grey20", fill = "grey95"),
      strip.text       = ggplot2::element_text(size = base_size - 1, face = "bold"),
      legend.position  = "right",
      legend.title     = ggplot2::element_text(size = base_size - 1, face = "bold"),
      legend.text      = ggplot2::element_text(size = base_size - 2),
      legend.key       = ggplot2::element_blank(),
      plot.background  = ggplot2::element_rect(fill = "white", colour = NA),
      panel.background = ggplot2::element_rect(fill = "white", colour = NA)
    )
}

emp_normalize_color_panel <- function(panel = NULL, default = "npg") {
  panel_use <- if (is.null(panel) || length(panel) == 0) "" else panel[[1]]
  p <- tolower(trimws(as.character(panel_use)))
  if (!nzchar(p)) p <- tolower(default)
  alias <- c(
    nature = "npg",
    npg = "npg",
    lancet = "lancet",
    nejm = "nejm",
    jama = "jama",
    aaas = "aaas",
    tableau = "tableau",
    set2 = "set2",
    dark3 = "dark3",
    viridis = "viridis"
  )
  out <- alias[[p]]
  if (is.null(out) || !nzchar(out)) out <- tolower(default)
  out
}

emp_get_color_panel <- function(default = "npg") {
  emp_normalize_color_panel(getOption("emp.color_panel", default), default = default)
}

emp_set_color_panel <- function(panel = NULL, custom_colors = NULL) {
  old <- list(
    panel = getOption("emp.color_panel", "npg"),
    custom = getOption("emp.custom_colors", NULL)
  )
  options(emp.color_panel = emp_normalize_color_panel(panel))
  custom <- NULL
  if (!is.null(custom_colors)) {
    vals <- trimws(unlist(strsplit(as.character(custom_colors), "[,;\\s]+")))
    vals <- vals[nzchar(vals)]
    vals <- vals[grepl("^#?[0-9A-Fa-f]{6}$", vals)]
    if (length(vals)) {
      vals <- toupper(ifelse(startsWith(vals, "#"), vals, paste0("#", vals)))
      custom <- unique(vals)
    }
  }
  options(emp.custom_colors = custom)
  invisible(old)
}

emp_restore_color_panel <- function(old) {
  if (is.list(old) && !is.null(old$panel)) {
    options(emp.color_panel = old$panel)
    options(emp.custom_colors = old$custom)
  } else {
    options(emp.color_panel = old %||% "npg")
  }
  invisible(TRUE)
}

# Editorial categorical palette: NPG → Lancet → NEJM → Set1.
emp_pub_palette <- function(n = 9, name = NULL) {
  custom <- getOption("emp.custom_colors", NULL)
  if (length(custom) >= 2) {
    pal <- rep_len(custom, n)
    return(pal[seq_len(n)])
  }
  name_use <- if (is.null(name) || !nzchar(name)) emp_get_color_panel("npg") else name
  name <- emp_normalize_color_panel(name_use, default = "npg")
  pkgs <- emp_pub_packages()
  if (pkgs$ggsci) {
    pal <- switch(
      name,
      "npg"    = ggsci::pal_npg("nrc")(min(n, 10)),
      "lancet" = ggsci::pal_lancet("lanonc")(min(n, 9)),
      "nejm"   = ggsci::pal_nejm("default")(min(n, 8)),
      "jama"   = ggsci::pal_jama("default")(min(n, 7)),
      "aaas"   = ggsci::pal_aaas("default")(min(n, 10)),
      "viridis" = if (pkgs$viridisLite) viridisLite::viridis(min(n, 20)) else ggsci::pal_npg("nrc")(min(n, 10)),
      "tableau" = if (pkgs$RColorBrewer) RColorBrewer::brewer.pal(min(max(n, 3), 12), "Paired") else ggsci::pal_npg("nrc")(min(n, 10)),
      "set2"    = if (pkgs$RColorBrewer) RColorBrewer::brewer.pal(min(max(n, 3), 8), "Set2") else ggsci::pal_npg("nrc")(min(n, 10)),
      "dark3"   = grDevices::hcl.colors(min(max(n, 3), 12), "Dark 3"),
      ggsci::pal_npg("nrc")(min(n, 10))
    )
  } else if (pkgs$RColorBrewer) {
    pal <- RColorBrewer::brewer.pal(min(max(n, 3), 9), "Set1")
  } else {
    pal <- grDevices::hcl.colors(n, palette = "Dark 3")
  }
  if (length(pal) < n) pal <- rep_len(pal, n)
  pal[seq_len(n)]
}

emp_scale_color_pub <- function(name = "Group", palette = NULL, n_hint = 9) {
  pal_use <- if (is.null(palette) || !nzchar(as.character(palette))) {
    emp_get_color_panel("npg")
  } else {
    as.character(palette)
  }
  vals <- emp_pub_palette(n_hint, pal_use)
  ggplot2::scale_color_manual(name = name, values = vals, na.value = "grey60")
}
emp_scale_fill_pub <- function(name = "Group", palette = NULL, n_hint = 9) {
  pal_use <- if (is.null(palette) || !nzchar(as.character(palette))) {
    emp_get_color_panel("npg")
  } else {
    as.character(palette)
  }
  vals <- emp_pub_palette(n_hint, pal_use)
  ggplot2::scale_fill_manual(name = name, values = vals, na.value = "grey80")
}

# Heatmap diverging palette (z-score / log2FC).
emp_diverging_colors <- function(n = 11, panel = NULL) {
  custom <- getOption("emp.custom_colors", NULL)
  if (length(custom) >= 3) {
    return(grDevices::colorRampPalette(custom)(256))
  }
  panel_use <- if (is.null(panel) || !nzchar(panel)) emp_get_color_panel("npg") else panel
  panel <- emp_normalize_color_panel(panel_use, default = "npg")
  if (identical(panel, "viridis") && requireNamespace("viridisLite", quietly = TRUE)) {
    return(viridisLite::viridis(256))
  }
  if (identical(panel, "tableau")) {
    return(grDevices::colorRampPalette(c("#4E79A7", "#A0CBE8", "#F7F7F7", "#F28E2B", "#E15759"))(256))
  }
  if (identical(panel, "set2")) {
    return(grDevices::colorRampPalette(c("#66C2A5", "#B3E2CD", "#F7F7F7", "#FC8D62", "#8DA0CB"))(256))
  }
  if (requireNamespace("RColorBrewer", quietly = TRUE)) {
    return(grDevices::colorRampPalette(rev(RColorBrewer::brewer.pal(n, "RdBu")))(256))
  }
  grDevices::colorRampPalette(c("#2166ac", "#67a9cf", "white", "#ef8a62", "#b2182b"))(256)
}

# Confidence-ellipse computation (95%) per group, returns df: x, y, group.
emp_conf_ellipse <- function(x, y, group, level = 0.95, n_segments = 60) {
  groups <- as.character(group)
  out <- list()
  for (g in unique(groups)) {
    idx <- which(groups == g)
    if (length(idx) < 3) next
    mat <- cbind(x[idx], y[idx])
    mu <- colMeans(mat, na.rm = TRUE)
    Sg <- stats::cov(mat, use = "pairwise.complete.obs")
    if (any(!is.finite(Sg))) next
    eg <- tryCatch(eigen(Sg), error = function(e) NULL)
    if (is.null(eg)) next
    rad <- sqrt(stats::qchisq(level, df = 2))
    theta <- seq(0, 2 * pi, length.out = n_segments)
    circle <- cbind(cos(theta), sin(theta))
    pts <- t(mu + rad * eg$vectors %*% (sqrt(pmax(eg$values, 0)) * t(circle)))
    out[[g]] <- data.frame(x = pts[, 1], y = pts[, 2], group = g, stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}

# Wilcoxon comparison labels for boxplots (k>=2 groups).
emp_pairwise_wilcox <- function(values, groups) {
  groups <- as.character(groups)
  lvls <- sort(unique(stats::na.omit(groups)))
  if (length(lvls) < 2) return(NULL)
  pairs <- utils::combn(lvls, 2, simplify = FALSE)
  rows <- lapply(pairs, function(pp) {
    a <- values[groups == pp[1]]
    b <- values[groups == pp[2]]
    if (sum(!is.na(a)) < 2 || sum(!is.na(b)) < 2) return(NULL)
    pv <- tryCatch(stats::wilcox.test(a, b, exact = FALSE)$p.value, error = function(e) NA_real_)
    data.frame(group1 = pp[1], group2 = pp[2], p = pv, stringsAsFactors = FALSE)
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (!length(rows)) return(NULL)
  out <- do.call(rbind, rows)
  out$signif <- ifelse(is.na(out$p), "ns",
                       ifelse(out$p < 0.001, "***",
                              ifelse(out$p < 0.01, "**",
                                     ifelse(out$p < 0.05, "*", "ns"))))
  out$label <- ifelse(is.na(out$p), "ns",
                      paste0("p = ", formatC(out$p, format = "g", digits = 2)))
  out
}

# PERMANOVA p-value via vegan::adonis2 on Euclidean distance (samples in rows).
emp_permanova_p <- function(score_mat, groups, permutations = 199) {
  if (!requireNamespace("vegan", quietly = TRUE)) return(NA_real_)
  g_chr <- as.character(groups)
  ok <- !is.na(g_chr) & nzchar(g_chr)
  if (sum(ok) < 4) return(NA_real_)
  if (length(unique(g_chr[ok])) < 2) return(NA_real_)
  d <- stats::dist(score_mat[ok, , drop = FALSE])
  res <- tryCatch(
    vegan::adonis2(d ~ factor(g_chr[ok]), permutations = permutations),
    error = function(e) NULL
  )
  if (is.null(res)) return(NA_real_)
  pcol <- grep("Pr.*F", colnames(res), value = TRUE)[1]
  if (is.na(pcol)) return(NA_real_)
  as.numeric(res[1, pcol])
}

# PERMANOVA on a sample-wise ecological distance (e.g. Bray–Curtis for 16S beta).
# `ad` is features × samples (same orientation as SummarizedExperiment assays).
emp_permanova_bray <- function(ad, groups, method = "bray", permutations = 199) {
  if (!requireNamespace("vegan", quietly = TRUE)) return(NA_real_)
  g_chr <- as.character(groups)
  ok <- !is.na(g_chr) & nzchar(g_chr)
  if (sum(ok) < 4) return(NA_real_)
  if (length(unique(g_chr[ok])) < 2) return(NA_real_)
  X <- t(ad[, ok, drop = FALSE])
  X[!is.finite(X)] <- 0
  d <- tryCatch(
    vegan::vegdist(X, method = method, na.rm = TRUE),
    error = function(e) NULL
  )
  if (is.null(d)) return(NA_real_)
  res <- tryCatch(
    vegan::adonis2(d ~ factor(g_chr[ok]), permutations = permutations),
    error = function(e) NULL
  )
  if (is.null(res)) return(NA_real_)
  pcol <- grep("Pr.*F", colnames(res), value = TRUE)[1]
  if (is.na(pcol)) return(NA_real_)
  as.numeric(res[1, pcol])
}

# Annotate ggplot with caption text (sample sizes / stats etc.).
emp_caption <- function(p, text) {
  if (is.null(text) || !nzchar(text)) return(p)
  p + ggplot2::labs(caption = text)
}
