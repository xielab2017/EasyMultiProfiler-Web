# One-click "run everything" pipelines for transcriptomics (RNAseq) and 16S.
#
# Each run produces:
#   <session>/bundles/<run_id>/plots/*.pdf        - publication-ready figures
#   <session>/bundles/<run_id>/plots/*.png        - PNG previews (mirror the PDFs)
#   <session>/bundles/<run_id>/tables/*.xlsx      - Excel tables (one per step)
#   <session>/bundles/<run_id>/summary.txt        - human-readable step log
# and then zips the whole folder to:
#   <session>/bundles/<run_id>.zip                - single-file download
#
# The caller passes an `on_progress(pct, msg)` callback (injected by jobs.R)
# so the UI can render a unified progress bar.

.bundle_root <- function(session_id) file.path(session_path(session_id), "bundles")

.new_run_id <- function() format(Sys.time(), "%Y%m%d-%H%M%S")

.bundle_init <- function(session_id) {
  run_id <- .new_run_id()
  base   <- file.path(.bundle_root(session_id), run_id)
  dir.create(file.path(base, "plots"),  recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(base, "tables"), recursive = TRUE, showWarnings = FALSE)
  list(run_id = run_id, base = base,
       plots  = file.path(base, "plots"),
       tables = file.path(base, "tables"),
       log    = file.path(base, "summary.txt"))
}

# Append a step line to summary.txt. Silently no-op if write fails.
.log_step <- function(bundle, step, elapsed_s, status = "ok", extra = NULL) {
  line <- sprintf("[%s] %-42s %6.2fs  %s%s\n",
                  format(Sys.time(), "%H:%M:%S"), step,
                  elapsed_s, status,
                  if (!is.null(extra)) paste0(" | ", extra) else "")
  try(cat(line, file = bundle$log, append = TRUE), silent = TRUE)
}

# Capture a standalone plot result, write both PDF and PNG, return file paths.
# We call the same internal builders the /visualize/* endpoints use, but we
# skip the base64 step entirely – plots are written straight to the bundle.
.save_ggplot_bundle <- function(p, bundle, name, width = 9, height = 6) {
  pdf  <- file.path(bundle$plots, paste0(name, ".pdf"))
  png  <- file.path(bundle$plots, paste0(name, ".png"))
  tryCatch({
    save_plot_pdf(p, pdf, width = width, height = height)
  }, error = function(e) message("[bundle] PDF ", name, ": ", conditionMessage(e)))
  tryCatch({
    if (requireNamespace("ragg", quietly = TRUE)) {
      ragg::agg_png(filename = png, width = width, height = height, units = "in",
                     res = 300, background = "white")
    } else {
      grDevices::png(filename = png, width = width, height = height, units = "in",
                      res = 300, bg = "white",
                      type = if (.Platform$OS.type == "windows") "windows" else "cairo")
    }
    if (inherits(p, "pheatmap")) {
      grid::grid.newpage(); grid::grid.draw(p$gtable)
    } else {
      print(p)
    }
    grDevices::dev.off()
  }, error = function(e) {
    try(grDevices::dev.off(), silent = TRUE)
    message("[bundle] PNG ", name, ": ", conditionMessage(e))
  })
  list(pdf = pdf, png = png)
}

.save_xlsx_bundle <- function(x, bundle, name, sheet = "data") {
  path <- file.path(bundle$tables, paste0(name, ".xlsx"))
  tryCatch(save_df_xlsx(x, path, sheet = sheet),
           error = function(e) {
             message("[bundle] XLSX ", name, ": ", conditionMessage(e))
             path <- sub("\\.xlsx$", ".csv", path)
             utils::write.csv(if (is.data.frame(x)) x else as.data.frame(x), path, row.names = FALSE)
             path
           })
}

# ------------------------------------------------------------------
# RNAseq one-click pipeline
# ------------------------------------------------------------------
run_all_rnaseq <- function(session_id, experiment,
                            group_var = "Group",
                            ref_group = NULL, test_group = NULL,
                            organism = "mmu",
                            fc_cutoff = 1.0, p_cutoff = 0.05,
                            use_padj = TRUE, min_row_sum = 0,
                            do_enrichment = TRUE,
                            on_progress = NULL) {
  bump <- function(p, msg) {
    if (!is.null(on_progress) && is.function(on_progress)) {
      tryCatch(on_progress(p, msg), error = function(e) NULL)
    }
  }

  bundle <- .bundle_init(session_id)
  cat(sprintf("EasyMultiProfiler RNAseq one-click run\nExperiment: %s\nStarted:    %s\n\n",
              experiment, format(Sys.time())),
      file = bundle$log, append = FALSE)

  total_steps <- if (isTRUE(do_enrichment)) 8L else 6L
  step_no <- 0L
  step_bump <- function(msg) {
    step_no <<- step_no + 1L
    bump(as.integer(5 + 90 * (step_no - 1) / total_steps), msg)
  }

  t_all <- Sys.time()

  # 1. Summary + PCA
  step_bump(sprintf("[1/%d] Summary & PCA", total_steps)); t0 <- Sys.time()
  pca_res <- tryCatch(run_dimension(session_id, experiment, method = "PCA"),
                       error = function(e) NULL)
  if (is.data.frame(pca_res)) .save_xlsx_bundle(pca_res, bundle, "01_pca_scores", "PCA")
  scatter <- tryCatch(.make_scatter_plot(session_id, experiment, group_var),
                      error = function(e) NULL)
  if (!is.null(scatter)) .save_ggplot_bundle(scatter, bundle, "01_pca_scatter", width = 8, height = 6)
  .log_step(bundle, "PCA + scatter", as.numeric(Sys.time() - t_all, units = "secs"),
            extra = if (is.null(scatter)) "no plot" else NULL)

  # 2. Differential analysis (DESeq2)
  step_bump(sprintf("[2/%d] Differential analysis (DESeq2)", total_steps)); t0 <- Sys.time()
  diff_compact <- run_diff(session_id, experiment, method = "DESeq2",
                            group_var = group_var,
                            ref_group = ref_group, test_group = test_group,
                            filter_low = TRUE, subset_two_groups = TRUE,
                            cores = "auto")
  .save_xlsx_bundle(as.data.frame(diff_compact), bundle,
                     "02_deseq2_compact", "DESeq2_compact")
  raw <- load_diff_raw(session_id, experiment)
  raw_df <- if (!is.null(raw)) as.data.frame(raw$data) else data.frame()
  .save_xlsx_bundle(raw_df, bundle, "02_deseq2_raw", "DESeq2_raw")
  .log_step(bundle, "DESeq2 diff", as.numeric(Sys.time() - t0, units = "secs"),
            extra = sprintf("n=%d", nrow(raw_df)))

  # 3. Volcano
  step_bump(sprintf("[3/%d] Volcano plot", total_steps)); t0 <- Sys.time()
  volcano_p <- tryCatch(.make_volcano_plot(session_id, experiment,
                                            fc_cutoff = fc_cutoff,
                                            p_cutoff = p_cutoff,
                                            use_padj = use_padj,
                                            label_top = 20L),
                        error = function(e) NULL)
  if (!is.null(volcano_p)) {
    .save_ggplot_bundle(volcano_p, bundle, "03_volcano", width = 8, height = 7)
  }
  .log_step(bundle, "Volcano", as.numeric(Sys.time() - t0, units = "secs"))

  # 4. DEG heatmap (pheatmap style)
  step_bump(sprintf("[4/%d] DEG heatmap", total_steps)); t0 <- Sys.time()
  deg_info <- tryCatch(make_deg_heatmap(
    session_id, experiment, group = group_var,
    fc_cutoff = fc_cutoff, p_cutoff = p_cutoff,
    use_padj = use_padj, min_row_sum = min_row_sum,
    cluster_rows = TRUE, cluster_cols = TRUE, show_rownames = TRUE,
    pdf_path = file.path(bundle$plots, "04_deg_heatmap.pdf")),
    error = function(e) { message("DEG heatmap: ", conditionMessage(e)); NULL })
  # Also write the PNG copy next to the PDF (best-effort)
  if (!is.null(deg_info) && !is.na(deg_info$png)) {
    png_path <- file.path(bundle$plots, "04_deg_heatmap.png")
    tryCatch(writeBin(base64enc::base64decode(deg_info$png), png_path),
             error = function(e) NULL)
  }
  sig <- raw_df
  if (nrow(sig)) {
    p_use_vec <- if (isTRUE(use_padj) && any(is.finite(sig$padj))) sig$padj else sig$pvalue
    sig$direction <- ifelse(p_use_vec <= p_cutoff & sig$log2FoldChange >=  fc_cutoff, "Up",
                     ifelse(p_use_vec <= p_cutoff & sig$log2FoldChange <= -fc_cutoff, "Down", "NS"))
    sig <- sig[sig$direction != "NS", , drop = FALSE]
    sig <- sig[order(-abs(sig$log2FoldChange)), , drop = FALSE]
    .save_xlsx_bundle(sig, bundle, "04_deg_list", "DEGs")
  }
  .log_step(bundle, "DEG heatmap", as.numeric(Sys.time() - t0, units = "secs"),
            extra = if (!is.null(deg_info)) sprintf("n_genes=%d", deg_info$n_genes) else "failed")

  # 5. Top-variance heatmap
  step_bump(sprintf("[5/%d] Top-variance heatmap", total_steps)); t0 <- Sys.time()
  tv_p <- tryCatch(.make_heatmap_plot(session_id, experiment, group = group_var, top_n = 50),
                    error = function(e) NULL)
  if (!is.null(tv_p)) {
    .save_ggplot_bundle(tv_p, bundle, "05_heatmap_topvar", width = 11, height = 8)
  }
  .log_step(bundle, "Top-var heatmap", as.numeric(Sys.time() - t0, units = "secs"))

  # 6. Sample-level correlation heatmap (fast: only n_samples^2 cells)
  step_bump(sprintf("[6/%d] Sample correlation", total_steps)); t0 <- Sys.time()
  sample_cor_p <- tryCatch({
    empt <- load_empt(session_id, experiment)
    ad   <- SummarizedExperiment::assays(empt)[[1]]
    if (ncol(ad) >= 2) {
      # Sample-by-sample spearman correlation – O(n_samples^2) not O(n_features^2)
      cor_mat <- suppressWarnings(stats::cor(log1p(as.matrix(ad)), method = "spearman",
                                                use = "pairwise.complete.obs"))
      if (all(is.finite(cor_mat))) {
        .save_xlsx_bundle(as.data.frame(cor_mat), bundle,
                           "06_sample_correlation", "Corr")
        df <- as.data.frame(as.table(cor_mat))
        names(df) <- c("Sample1", "Sample2", "rho")
        df$Sample1 <- factor(df$Sample1, levels = rownames(cor_mat))
        df$Sample2 <- factor(df$Sample2, levels = rev(colnames(cor_mat)))
        ggplot2::ggplot(df, ggplot2::aes(x = Sample1, y = Sample2, fill = rho)) +
          ggplot2::geom_tile() +
          ggplot2::geom_text(ggplot2::aes(label = sprintf("%.2f", rho)),
                              size = 3, color = "grey20") +
          ggplot2::scale_fill_gradient2(name = "Spearman",
                 low = "#2166ac", mid = "white", high = "#b2182b",
                 midpoint = 0, limits = c(-1, 1)) +
          ggplot2::labs(title = "Sample-level correlation", x = NULL, y = NULL) +
          emp_pub_theme() +
          ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
                          panel.grid = ggplot2::element_blank())
      }
    }
  }, error = function(e) NULL)
  if (!is.null(sample_cor_p)) .save_ggplot_bundle(sample_cor_p, bundle,
                                                     "06_sample_correlation",
                                                     width = 7, height = 6)
  .log_step(bundle, "Sample correlation", as.numeric(Sys.time() - t0, units = "secs"))

  # 7-8. Enrichment (optional, slow)
  if (isTRUE(do_enrichment)) {
    step_bump(sprintf("[7/%d] KEGG enrichment (clusterProfiler)", total_steps))
    t0 <- Sys.time()
    kegg <- tryCatch(run_enrichment(session_id, experiment,
                                     database = "KEGG", organism = organism,
                                     fc_cutoff = fc_cutoff, p_cutoff = p_cutoff,
                                     use_padj = use_padj, direction = "both",
                                     top_n = 20L),
                      error = function(e) list(data = data.frame(), plot = NA_character_,
                                                 error = conditionMessage(e)))
    if (is.data.frame(kegg$data) && nrow(kegg$data)) {
      .save_xlsx_bundle(kegg$data, bundle, "07_enrichment_kegg", "KEGG")
    }
    if (!is.na(kegg$plot %||% NA)) {
      png_path <- file.path(bundle$plots, "07_enrichment_kegg.png")
      pdf_path <- file.path(bundle$plots, "07_enrichment_kegg.pdf")
      try(writeBin(base64enc::base64decode(kegg$plot), png_path), silent = TRUE)
      # Also re-run enrichplot::dotplot and save as PDF directly for high fidelity.
      tryCatch({
        if (requireNamespace("clusterProfiler", quietly = TRUE) &&
            requireNamespace("enrichplot", quietly = TRUE)) {
          # Re-run enrichment (cheap once cached) for direct PDF output.
          # Use the already-mapped `data` frame as input to dotplot is not
          # possible – but we can build a ggplot from kegg$data ourselves.
          df <- kegg$data
          df$Description <- factor(df$Description, levels = rev(df$Description))
          gr <- vapply(strsplit(as.character(df$GeneRatio), "/"), function(x) {
            as.numeric(x[1]) / as.numeric(x[2])
          }, numeric(1))
          df$GeneRatioNum <- gr
          p <- ggplot2::ggplot(df,
                  ggplot2::aes(x = GeneRatioNum, y = Description,
                                size = Count, colour = p.adjust)) +
            ggplot2::geom_point() +
            ggplot2::scale_colour_gradient(low = "#b2182b", high = "#2166ac") +
            ggplot2::labs(title = sprintf("KEGG enrichment (%s)", organism),
                           x = "GeneRatio", y = NULL) +
            emp_pub_theme(base_size = 11)
          save_plot_pdf(p, pdf_path, width = 9, height = 7)
        }
      }, error = function(e) NULL)
    }
    .log_step(bundle, "KEGG enrichment", as.numeric(Sys.time() - t0, units = "secs"),
              extra = if (!is.null(kegg$n_rows)) sprintf("n=%d", kegg$n_rows) else
                       if (!is.null(kegg$error)) paste0("err: ", kegg$error) else "")

    step_bump(sprintf("[8/%d] GO enrichment (clusterProfiler)", total_steps))
    t0 <- Sys.time()
    go <- tryCatch(run_enrichment(session_id, experiment,
                                   database = "GO", organism = organism,
                                   fc_cutoff = fc_cutoff, p_cutoff = p_cutoff,
                                   use_padj = use_padj, direction = "both",
                                   top_n = 20L),
                    error = function(e) list(data = data.frame(), plot = NA_character_,
                                               error = conditionMessage(e)))
    if (is.data.frame(go$data) && nrow(go$data)) {
      .save_xlsx_bundle(go$data, bundle, "08_enrichment_go", "GO_BP")
    }
    if (!is.na(go$plot %||% NA)) {
      png_path <- file.path(bundle$plots, "08_enrichment_go.png")
      try(writeBin(base64enc::base64decode(go$plot), png_path), silent = TRUE)
    }
    .log_step(bundle, "GO enrichment", as.numeric(Sys.time() - t0, units = "secs"),
              extra = if (!is.null(go$n_rows)) sprintf("n=%d", go$n_rows) else
                       if (!is.null(go$error)) paste0("err: ", go$error) else "")
  }

  bump(97L, "Packaging bundle")
  zip_path <- file.path(.bundle_root(session_id), paste0(bundle$run_id, ".zip"))
  tryCatch(zip_dir(bundle$base, zip_path),
           error = function(e) message("[bundle] zip failed: ", conditionMessage(e)))

  total_s <- as.numeric(Sys.time() - t_all, units = "secs")
  cat(sprintf("\nTotal elapsed: %.1fs\nBundle: %s\n",
              total_s, basename(zip_path)),
      file = bundle$log, append = TRUE)

  list(success    = TRUE,
       session_id = session_id,
       experiment = experiment,
       run_id     = bundle$run_id,
       bundle     = bundle$base,
       zip_path   = zip_path,
       zip_name   = basename(zip_path),
       elapsed_s  = round(total_s, 1))
}

# ------------------------------------------------------------------
# 16S one-click pipeline
# ------------------------------------------------------------------
run_all_m16s <- function(session_id, experiment,
                          group_var = NULL, taxonomy_level = "Genus",
                          alpha_index = "shannon",
                          beta_method = "bray", ord_method = "PCoA",
                          on_progress = NULL) {
  bump <- function(p, msg) {
    if (!is.null(on_progress) && is.function(on_progress)) {
      tryCatch(on_progress(p, msg), error = function(e) NULL)
    }
  }
  bundle <- .bundle_init(session_id)
  cat(sprintf("EasyMultiProfiler 16S one-click run\nExperiment: %s\nStarted:    %s\n\n",
              experiment, format(Sys.time())),
      file = bundle$log, append = FALSE)

  total_steps <- 6L; step_no <- 0L
  step_bump <- function(msg) {
    step_no <<- step_no + 1L
    bump(as.integer(5 + 90 * (step_no - 1) / total_steps), msg)
  }
  t_all <- Sys.time()

  # 1. Prepare taxonomy level
  step_bump(sprintf("[1/%d] Prepare taxonomy (%s)", total_steps, taxonomy_level)); t0 <- Sys.time()
  tryCatch(m16s_prepare_taxonomy_step(session_id, experiment,
                                      collapse_level = taxonomy_level,
                                      keep_top_n = 40L,
                                      drop_unassigned = FALSE),
           error = function(e) message("Prepare taxonomy: ", conditionMessage(e)))
  .log_step(bundle, "Taxonomy prep", as.numeric(Sys.time() - t0, units = "secs"))

  # 2. Alpha diversity — compute every supported index in one pass, then
  #    emit one boxplot (PDF + PNG) per index.
  step_bump(sprintf("[2/%d] Alpha diversity (all indices)", total_steps)); t0 <- Sys.time()
  alpha <- tryCatch(run_alpha(session_id, experiment, method = alpha_index),
                     error = function(e) NULL)
  if (is.data.frame(alpha)) .save_xlsx_bundle(alpha, bundle, "02_alpha_indices", "Alpha")

  alpha_pool <- c("shannon", "simpson", "invsimpson",
                   "chao1",   "ace",     "observed", "pielou")
  ## Discover which indices are actually present in the result to avoid
  ## writing blank placeholders for unsupported metrics (EMP picks what
  ## it can from the assay type).  EMP 1.x also ships a typo column
  ## "observerd_index" which the pattern below forgives.
  alpha_present <- character(0)
  if (is.data.frame(alpha)) {
    present_cols <- tolower(names(alpha))
    present_cols <- sub("^observerd", "observed", present_cols)
    alpha_present <- alpha_pool[
      vapply(alpha_pool,
              function(m) any(grepl(paste0("^", m), present_cols)),
              logical(1))]
  }
  if (!length(alpha_present)) alpha_present <- alpha_index %||% "shannon"

  # Make the configured `alpha_index` go first so the bundle order matches
  # the user's primary selection in the UI.
  if (alpha_index %in% alpha_present) {
    alpha_present <- c(alpha_index,
                        setdiff(alpha_present, alpha_index))
  }

  for (m in alpha_present) {
    ap <- tryCatch(.make_alpha_plot(session_id, experiment,
                                      group = group_var, metric = m),
                   error = function(e) NULL)
    if (!is.null(ap)) {
      fname <- sprintf("02_alpha_%s_boxplot", tolower(m))
      .save_ggplot_bundle(ap, bundle, fname, width = 7, height = 5)
    }
  }
  .log_step(bundle, "Alpha", as.numeric(Sys.time() - t0, units = "secs"),
             extra = sprintf("indices=%s", paste(alpha_present, collapse = ",")))

  # 3. Beta / ordination — always run PCA, PCoA and NMDS so the user can
  # compare layouts; the `ord_method` argument still determines which one
  # stays cached on the EMPT for downstream use.
  step_bump(sprintf("[3/%d] Beta diversity (PCA + PCoA + NMDS)",
                    total_steps)); t0 <- Sys.time()

  ord_methods <- c("PCoA", "PCA", "NMDS")
  if (nzchar(ord_method %||% "") && ord_method %in% ord_methods) {
    ord_methods <- c(ord_method, setdiff(ord_methods, ord_method))
  }
  beta_scores_all <- list()
  for (m in ord_methods) {
    # Run the EMP dimension analysis for PCA/PCoA (NMDS isn't part of EMP,
    # we build it locally).  Skip errors so one bad method doesn't torpedo
    # the whole bundle.
    if (toupper(m) %in% c("PCA", "PCOA")) {
      tryCatch(run_dimension(session_id, experiment, method = m),
                error = function(e) message("[bundle] dim ", m, ": ",
                                               conditionMessage(e)))
    }
    built <- tryCatch(.make_scatter_plot(session_id, experiment, group_var,
                                          method = m, return_scores = TRUE),
                       error = function(e) NULL)
    if (!is.null(built) && !is.null(built$plot)) {
      fname <- sprintf("03_beta_%s_scatter", tolower(m))
      .save_ggplot_bundle(built$plot, bundle, fname, width = 8, height = 6)
      if (is.data.frame(built$scores))
        beta_scores_all[[m]] <- built$scores
    }
  }
  if (length(beta_scores_all)) {
    beta_all <- do.call(rbind, lapply(names(beta_scores_all), function(m) {
      df <- beta_scores_all[[m]]
      if (!nrow(df)) return(NULL)
      df$method <- m; df
    }))
    if (!is.null(beta_all) && nrow(beta_all))
      .save_xlsx_bundle(beta_all, bundle, "03_beta_coords", "Beta")
  }
  .log_step(bundle, "Beta", as.numeric(Sys.time() - t0, units = "secs"),
             extra = sprintf("methods=%s", paste(ord_methods, collapse = ",")))

  # 4. Top-taxa heatmap + barplot
  step_bump(sprintf("[4/%d] Top taxa heatmap + barplot", total_steps)); t0 <- Sys.time()
  heat_p <- tryCatch(.make_heatmap_plot(session_id, experiment, group = group_var, top_n = 40),
                      error = function(e) NULL)
  if (!is.null(heat_p)) .save_ggplot_bundle(heat_p, bundle, "04_top40_heatmap",
                                             width = 11, height = 9)
  bar_p  <- tryCatch(.make_barplot_plot(session_id, experiment, group = group_var, top_n = 15),
                      error = function(e) NULL)
  if (!is.null(bar_p))  .save_ggplot_bundle(bar_p, bundle, "04_top15_barplot",
                                             width = 9, height = 6)
  .log_step(bundle, "Heatmap + barplot", as.numeric(Sys.time() - t0, units = "secs"))

  # 5. Differential taxa (wilcox)
  if (!is.null(group_var) && nzchar(group_var)) {
    step_bump(sprintf("[5/%d] Differential taxa (wilcox)", total_steps)); t0 <- Sys.time()
    diff <- tryCatch(run_diff(session_id, experiment,
                               method = "wilcox.test", group_var = group_var,
                               filter_low = TRUE, subset_two_groups = FALSE,
                               cores = "auto"),
                      error = function(e) NULL)
    if (is.data.frame(diff)) .save_xlsx_bundle(diff, bundle,
                                                  "05_diff_taxa", "DiffTaxa")
    .log_step(bundle, "Diff taxa", as.numeric(Sys.time() - t0, units = "secs"))
  } else {
    step_bump(sprintf("[5/%d] Differential taxa (skipped – no group)", total_steps))
    .log_step(bundle, "Diff taxa", 0, status = "skip")
  }

  # 6. Sample metadata snapshot
  step_bump(sprintf("[6/%d] Snapshot colData & feature labels", total_steps)); t0 <- Sys.time()
  tryCatch({
    empt <- load_empt(session_id, experiment)
    cd   <- as.data.frame(SummarizedExperiment::colData(empt))
    rd   <- tryCatch(as.data.frame(SummarizedExperiment::rowData(empt)),
                     error = function(e) data.frame())
    .save_xlsx_bundle(list(colData = cd, rowData = rd), bundle, "06_experiment_metadata")
  }, error = function(e) NULL)
  .log_step(bundle, "Metadata snapshot", as.numeric(Sys.time() - t0, units = "secs"))

  bump(97L, "Packaging bundle")
  zip_path <- file.path(.bundle_root(session_id), paste0(bundle$run_id, ".zip"))
  tryCatch(zip_dir(bundle$base, zip_path),
           error = function(e) message("[bundle] zip failed: ", conditionMessage(e)))

  total_s <- as.numeric(Sys.time() - t_all, units = "secs")
  cat(sprintf("\nTotal elapsed: %.1fs\nBundle: %s\n",
              total_s, basename(zip_path)),
      file = bundle$log, append = TRUE)

  list(success    = TRUE,
       session_id = session_id,
       experiment = experiment,
       run_id     = bundle$run_id,
       bundle     = bundle$base,
       zip_path   = zip_path,
       zip_name   = basename(zip_path),
       elapsed_s  = round(total_s, 1))
}

# ------------------------------------------------------------------
# Thin ggplot builders that *return the plot object* (rather than base64).
# These mirror the logic of make_scatter / make_heatmap / make_volcano /
# make_barplot / make_boxplot in viz.R but skip the plot_to_base64 call,
# so the bundle code can write PDF + PNG directly.
# ------------------------------------------------------------------
.with_plot_obj <- function(fn_body, ...) {
  # fn_body is a function that returns either a ggplot or NULL.
  tryCatch(fn_body(...), error = function(e) NULL)
}

## Ordination scatter for PCA / PCoA / NMDS (Bray-Curtis distance).
##  - `method`: "PCA" (default, linear prcomp), "PCoA" (cmdscale on
##              Bray-Curtis dissimilarity), "NMDS" (vegan::metaMDS on
##              Bray-Curtis).
##  - Returns a list(plot, scores_df, method, axis1_var, axis2_var)
##    when `return_scores = TRUE`; otherwise a ggplot as before.
##    The scores frame always has columns "sample", "Axis1", "Axis2",
##    plus the grouping variable (if any).
.make_scatter_plot <- function(session_id, experiment, group = NULL,
                                method = "PCA", return_scores = FALSE) {
  empt <- load_empt(session_id, experiment)
  ad   <- SummarizedExperiment::assays(empt)[[1]]
  cd   <- as.data.frame(SummarizedExperiment::colData(empt))
  if (ncol(ad) < 2 || nrow(ad) < 2) return(NULL)
  method <- toupper(as.character(method)[1])
  if (!method %in% c("PCA", "PCOA", "NMDS")) method <- "PCA"
  mat <- t(ad); mat[!is.finite(mat)] <- 0

  axis_labels <- c("Axis1", "Axis2")
  vexp <- NULL
  scores_mat <- NULL

  if (method == "PCA") {
    pca <- stats::prcomp(mat, center = TRUE, scale. = FALSE)
    vexp <- (pca$sdev^2) / sum(pca$sdev^2)
    scores_mat <- pca$x[, 1:2, drop = FALSE]
    axis_labels <- c(
      sprintf("PC1 (%.1f%%)", 100 * vexp[1]),
      sprintf("PC2 (%.1f%%)", 100 * vexp[2])
    )
  } else if (method == "PCOA") {
    ## Bray-Curtis requires non-negative abundance; shift if needed.
    mat_bc <- mat
    if (any(mat_bc < 0, na.rm = TRUE)) mat_bc <- mat_bc - min(mat_bc, na.rm = TRUE)
    d <- tryCatch(
      if (requireNamespace("vegan", quietly = TRUE))
        vegan::vegdist(mat_bc, method = "bray") else stats::dist(mat_bc),
      error = function(e) stats::dist(mat_bc)
    )
    fit <- stats::cmdscale(d, k = 2, eig = TRUE)
    pts <- fit$points
    ev  <- fit$eig
    ev[ev < 0] <- 0
    vexp <- ev / sum(ev)
    scores_mat <- pts
    colnames(scores_mat) <- c("PCo1", "PCo2")
    axis_labels <- c(
      sprintf("PCo1 (%.1f%%)", 100 * vexp[1]),
      sprintf("PCo2 (%.1f%%)", 100 * vexp[2])
    )
  } else { # NMDS
    if (!requireNamespace("vegan", quietly = TRUE)) {
      stop("NMDS requires the 'vegan' package to be installed.")
    }
    mat_bc <- mat
    if (any(mat_bc < 0, na.rm = TRUE)) mat_bc <- mat_bc - min(mat_bc, na.rm = TRUE)
    nmds <- tryCatch(
      suppressWarnings(vegan::metaMDS(mat_bc, distance = "bray", k = 2,
                                        trace = 0, autotransform = TRUE)),
      error = function(e) NULL
    )
    if (is.null(nmds) || is.null(nmds$points)) return(NULL)
    scores_mat <- nmds$points
    colnames(scores_mat) <- c("NMDS1", "NMDS2")
    axis_labels <- c(
      sprintf("NMDS1  (stress = %.3f)", nmds$stress),
      "NMDS2"
    )
  }

  scores <- as.data.frame(scores_mat)
  names(scores) <- c("PC1", "PC2")
  scores$sample <- rownames(scores)
  pick <- if (!is.null(group) && nzchar(group) && group %in% names(cd))
            list(name = group, values = cd[match(scores$sample, rownames(cd)), group]) else
            .viz_pick_group(empt, NULL)
  if (!is.null(pick)) {
    scores$group <- .viz_group_levels(pick$values); grp_name <- pick$name
  } else {
    scores$group <- factor("All"); grp_name <- "Group"
  }
  ell <- emp_conf_ellipse(scores$PC1, scores$PC2, scores$group)
  title_by_method <- switch(method,
                             PCA  = "PCA",
                             PCOA = "PCoA (Bray-Curtis)",
                             NMDS = "NMDS (Bray-Curtis)")
  p <- ggplot2::ggplot(scores, ggplot2::aes(x = PC1, y = PC2,
                                              color = group, fill = group)) +
    ggplot2::geom_hline(yintercept = 0, linetype = "dashed", color = "grey80", linewidth = 0.3) +
    ggplot2::geom_vline(xintercept = 0, linetype = "dashed", color = "grey80", linewidth = 0.3) +
    ggplot2::geom_point(size = 3.2, alpha = 0.9, stroke = 0.3, shape = 21, color = "grey20") +
    emp_scale_color_pub(name = grp_name, n_hint = length(levels(scores$group))) +
    emp_scale_fill_pub(name = grp_name, n_hint = length(levels(scores$group))) +
    ggplot2::labs(title = title_by_method,
                   x = axis_labels[1], y = axis_labels[2]) +
    emp_pub_theme()
  if (!is.null(ell) && nrow(ell) > 0) {
    p <- p + ggplot2::geom_polygon(data = ell,
              ggplot2::aes(x = x, y = y, fill = group, group = group),
              alpha = 0.12, inherit.aes = FALSE, color = NA)
  }
  if (isTRUE(return_scores)) {
    scores_out <- data.frame(
      sample = scores$sample,
      Axis1  = scores$PC1,
      Axis2  = scores$PC2,
      group  = as.character(scores$group),
      method = method,
      stringsAsFactors = FALSE
    )
    return(list(plot = p, scores = scores_out, method = method,
                 axis_labels = axis_labels))
  }
  p
}

.make_volcano_plot <- function(session_id, experiment,
                                fc_cutoff = 1.0, p_cutoff = 0.05,
                                use_padj = TRUE, label_top = 15L) {
  # Reuse the viz.R implementation for its raw-table loading and smart
  # fallback; it returns a base64 PNG *after* building the ggplot.  For the
  # bundle we want the ggplot object instead – simplest path is to re-run
  # the builder below (copy of the business logic from viz.R without the
  # trailing plot_to_base64 call).
  empt <- load_empt(session_id, experiment)
  raw  <- load_diff_raw(session_id, experiment)
  if (is.null(raw) || is.null(raw$data) || !nrow(raw$data)) return(NULL)
  df <- as.data.frame(raw$data, stringsAsFactors = FALSE)
  padj_vec <- suppressWarnings(as.numeric(df$padj))
  pval_vec <- suppressWarnings(as.numeric(df$pvalue))
  fallback_msg <- NULL
  if (isTRUE(use_padj) && any(is.finite(padj_vec))) {
    if (sum(is.finite(padj_vec) & padj_vec <= p_cutoff, na.rm = TRUE) == 0 &&
        any(is.finite(pval_vec))) {
      use_padj <- FALSE
      fallback_msg <- "No features pass padj cutoff; using raw p-value instead"
    }
  }
  df$p_plot <- if (isTRUE(use_padj) && any(is.finite(padj_vec))) padj_vec else pval_vec
  df$fc <- suppressWarnings(as.numeric(df$log2FoldChange))
  fin <- is.finite(df$fc)
  if (any(fin) && any(!fin)) {
    cap <- max(abs(df$fc[fin]), na.rm = TRUE)
    df$fc[!fin & df$fc > 0] <-  cap; df$fc[!fin & df$fc < 0] <- -cap
  }
  df <- df[is.finite(df$fc) & is.finite(df$p_plot), , drop = FALSE]
  if (!nrow(df)) return(NULL)
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
  n_up <- as.integer(cnt["Up"] %||% 0); n_dn <- as.integer(cnt["Down"] %||% 0)
  n_ns <- as.integer(cnt["NS"] %||% 0)
  pal <- c("Down" = "#3182bd", "NS" = "#bdbdbd", "Up" = "#E64B35")
  p_label <- if (isTRUE(use_padj)) expression(-log[10]~italic("padj")) else
               expression(-log[10]~italic("p-value"))
  sub <- paste0("|log2FC| >= ", fc_cutoff, ", ",
                if (isTRUE(use_padj)) "padj" else "p", " <= ", p_cutoff)
  if (!is.null(fallback_msg)) sub <- paste0(sub, "  (", fallback_msg, ")")
  p <- ggplot2::ggplot(df, ggplot2::aes(x = fc, y = neg_log10p, color = change)) +
    ggplot2::geom_point(alpha = 0.8, size = 1.75, na.rm = TRUE) +
    ggplot2::scale_color_manual(name = "Regulation", values = pal,
          labels = c("Down" = paste0("Down (n=", n_dn, ")"),
                      "NS"   = paste0("NS (n=",   n_ns, ")"),
                      "Up"   = paste0("Up (n=",   n_up, ")"))) +
    ggplot2::geom_vline(xintercept = c(-fc_cutoff, fc_cutoff),
                         linetype = "dashed", color = "grey40", linewidth = 0.4) +
    ggplot2::geom_hline(yintercept = -log10(p_cutoff),
                         linetype = "dashed", color = "grey40", linewidth = 0.4) +
    ggplot2::labs(title = "Volcano plot", subtitle = sub,
                   x = expression(log[2]~"Fold Change"), y = p_label) +
    emp_pub_theme()
  if (requireNamespace("ggrepel", quietly = TRUE)) {
    sig <- df[df$change != "NS", , drop = FALSE]
    if (nrow(sig)) {
      # Combined rank of |log2FC| + -log10(p) → strongest signals first.
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
        p <- p + ggrepel::geom_text_repel(data = top,
                ggplot2::aes(label = label, color = change),
                size = 3.2, fontface = "bold",
                max.overlaps = 60, box.padding = 0.45, point.padding = 0.3,
                segment.color = "grey50", segment.size = 0.3, min.segment.length = 0,
                show.legend = FALSE) +
             ggplot2::geom_point(data = top,
                ggplot2::aes(x = fc, y = neg_log10p, color = change),
                size = 2.6, shape = 21, fill = NA, stroke = 0.9, show.legend = FALSE)
      }
    }
  }
  p
}

.make_heatmap_plot <- function(session_id, experiment, group = NULL, top_n = 50L) {
  empt <- load_empt(session_id, experiment)
  ad   <- SummarizedExperiment::assays(empt)[[1]]
  cd   <- as.data.frame(SummarizedExperiment::colData(empt))
  if (nrow(ad) == 0 || ncol(ad) == 0) return(NULL)
  top_n <- max(5L, as.integer(top_n))
  topf  <- order(apply(ad, 1, var, na.rm = TRUE), decreasing = TRUE)[seq_len(min(top_n, nrow(ad)))]
  ad_s  <- ad[topf, , drop = FALSE]
  ad_z  <- t(scale(t(ad_s))); ad_z[!is.finite(ad_z)] <- 0
  pick <- if (!is.null(group) && nzchar(group) && group %in% names(cd))
            list(name = group, values = cd[[group]]) else .viz_pick_group(empt, NULL)
  grp  <- if (!is.null(pick))
            .viz_group_levels(pick$values[match(colnames(ad_z), rownames(cd))]) else
            factor(rep("All", ncol(ad_z)))
  rownames(ad_z) <- make.unique(.viz_feature_labels(empt, rownames(ad_z)))
  df <- as.data.frame(as.table(ad_z))
  names(df) <- c("Feature", "Sample", "Z")
  df$Sample  <- factor(df$Sample,  levels = colnames(ad_z))
  df$Feature <- factor(df$Feature, levels = rev(rownames(ad_z)))
  zlim <- max(abs(stats::quantile(df$Z, probs = c(0.02, 0.98), na.rm = TRUE)))
  if (!is.finite(zlim) || zlim == 0) zlim <- max(abs(df$Z), na.rm = TRUE) + 1e-6
  ggplot2::ggplot(df, ggplot2::aes(x = Sample, y = Feature, fill = Z)) +
    ggplot2::geom_tile() +
    ggplot2::scale_fill_gradient2(name = "Z-score",
            low = "#2166ac", mid = "white", high = "#b2182b",
            midpoint = 0, limits = c(-zlim, zlim), oob = scales::squish) +
    ggplot2::labs(x = NULL, y = NULL,
            title = paste0("Top ", nrow(ad_z), " variable features (z-scored)")) +
    emp_pub_theme(base_size = 11) +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, size = 8),
      axis.text.y = if (nrow(ad_z) <= 60) ggplot2::element_text(size = 7) else ggplot2::element_blank(),
      panel.grid  = ggplot2::element_blank()
    )
}

## Alpha-diversity boxplot for a *specific* metric.
##  - `metric`:   column of the EMP_alpha_analysis result to plot.  When NULL
##                (or not found) we fall back to the first available alpha
##                column, which matches the old single-index behaviour.
##  - Returns `NULL` if the experiment has no alpha result or the requested
##    metric column is missing.  Callers can tryCatch/NULL-check safely.
.make_alpha_plot <- function(session_id, experiment, group = NULL, metric = NULL) {
  empt <- load_empt(session_id, experiment)
  cd <- as.data.frame(SummarizedExperiment::colData(empt))
  res <- tryCatch(EasyMultiProfiler::EMP_result(empt, info = "EMP_alpha_analysis"),
                   error = function(e) NULL)
  df <- as.data.frame(res, stringsAsFactors = FALSE)
  if (!nrow(df)) return(NULL)

  ## EMP v1.x emits column names like `shannon`, `simpson`, `invsimpson`,
  ## `chao1`, `ACE`, `observerd_index` (sic), `pielou`.  Match them all with
  ## a tolerant case-insensitive prefix search including the typo variant.
  alpha_cols <- grep("^(shannon|simpson|invsimpson|chao|ace|observ|pielou)",
                      names(df), ignore.case = TRUE, value = TRUE)
  if (!length(alpha_cols)) return(NULL)

  ## Helper: normalise a metric label so both inputs and column names can
  ## be compared regardless of case or the "observerd" typo.
  .norm <- function(x) {
    x <- tolower(as.character(x))
    sub("^observerd", "observed", x)
  }
  ycol <- NULL
  if (!is.null(metric) && nzchar(metric)) {
    mkey <- .norm(metric)
    ckeys <- .norm(alpha_cols)
    hit <- which(ckeys == mkey)
    if (!length(hit)) hit <- grep(paste0("^", mkey), ckeys)
    if (length(hit)) ycol <- alpha_cols[hit[1]]
  }
  if (is.null(ycol)) ycol <- alpha_cols[1]

  id_col <- names(df)[1]
  grp_vec <- if (!is.null(group) && nzchar(group) && group %in% names(cd))
               cd[match(df[[id_col]], rownames(cd)), group] else
               .viz_pick_group(empt, NULL)$values
  if (is.null(grp_vec)) grp_vec <- rep("All", nrow(df))
  df$Group <- .viz_group_levels(grp_vec)
  df[[ycol]] <- suppressWarnings(as.numeric(df[[ycol]]))
  p <- ggplot2::ggplot(df, ggplot2::aes(x = Group, y = .data[[ycol]],
                                          fill = Group, color = Group)) +
    ggplot2::geom_boxplot(alpha = 0.7, outlier.shape = NA, width = 0.55) +
    ggplot2::geom_jitter(width = 0.15, size = 2.2, shape = 21, stroke = 0.3,
                          color = "grey25", na.rm = TRUE) +
    emp_scale_fill_pub(name = "Group", n_hint = length(levels(df$Group))) +
    emp_scale_color_pub(name = "Group", n_hint = length(levels(df$Group))) +
    ggplot2::labs(title = sprintf("Alpha diversity (%s)", ycol),
                   x = NULL, y = ycol) +
    emp_pub_theme()
  p
}

.make_barplot_plot <- function(session_id, experiment, group = NULL, top_n = 15L) {
  empt <- load_empt(session_id, experiment)
  ad <- SummarizedExperiment::assays(empt)[[1]]
  if (nrow(ad) == 0 || ncol(ad) == 0) return(NULL)
  top_n <- max(3L, as.integer(top_n))
  ranks <- order(rowMeans(ad, na.rm = TRUE), decreasing = TRUE)
  topf  <- ranks[seq_len(min(top_n, length(ranks)))]
  mat <- ad[topf, , drop = FALSE]
  labs <- make.unique(.viz_feature_labels(empt, rownames(mat)))
  rownames(mat) <- labs
  long <- as.data.frame(as.table(mat))
  names(long) <- c("Feature", "Sample", "Abundance")
  long$Feature <- factor(long$Feature, levels = rev(labs))
  pal <- emp_pub_palette(length(labs))
  p <- ggplot2::ggplot(long, ggplot2::aes(x = Sample, y = Abundance, fill = Feature)) +
    ggplot2::geom_bar(stat = "identity", position = "fill", width = 0.9) +
    ggplot2::scale_fill_manual(values = pal) +
    ggplot2::labs(title = sprintf("Top %d features (relative abundance)", length(labs)),
                   x = NULL, y = "Relative abundance") +
    emp_pub_theme(base_size = 11) +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, size = 8),
      legend.text = ggplot2::element_text(size = 7),
      legend.key.size = grid::unit(10, "pt")
    )
  p
}
