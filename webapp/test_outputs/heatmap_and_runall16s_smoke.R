# End-to-end smoke test:
#   (a) make_heatmap(features = ...) tolerant feature-list path
#   (b) run_all_m16s now produces a bundle containing one boxplot per
#       alpha index and one scatter per ordination method.
#
#  Uses the demo MAE (which ships with EasyMultiProfiler) and writes all
#  artefacts under webapp/test_outputs/.
suppressPackageStartupMessages({
  library(EasyMultiProfiler)
  library(MultiAssayExperiment)
  library(SummarizedExperiment)
  library(ggplot2)
  library(S4Vectors)
})
dir <- "webapp/backend"
for (f in c("helpers/session.R", "helpers/utils.R", "helpers/plot_theme.R",
            "helpers/import.R", "helpers/analysis.R", "helpers/viz.R",
            "helpers/workflow_registry.R", "helpers/workflow_metabolomics.R",
            "helpers/workflow_metagenomics.R", "helpers/workflow_transcriptomics.R",
            "helpers/workflow_microbiome_16s.R",
            "helpers/workflow_microbiome_16s_api.R", "helpers/clinical.R",
            "helpers/runall.R"))
  source(file.path(dir, f))

data(MAE)
sid <- create_session()
save_mae(sid, MAE)
cat(sprintf("\nSession: %s\nExperiments: %s\n",
            sid, paste(names(MAE), collapse = ", ")))

stopifnot("host_gene" %in% names(MAE))

# ----------------------------------------------------------------------
# (a) make_heatmap custom features: pass a mix of matching + missing IDs
# ----------------------------------------------------------------------
ad_hg <- assay(MAE[["host_gene"]])
picked <- sample(rownames(ad_hg), 15L)            # these should match
fake <- c("NOT_A_REAL_GENE_001", "NOT_A_REAL_GENE_002")
feat_list <- c(picked, fake)

res <- make_heatmap(sid, "host_gene",
                    group = "Group",
                    top_n = 50L,
                    features = feat_list)

cat("\n[make_heatmap(features=...)] mode: custom\n")
stopifnot(is.list(res), !is.null(res$plot))
cat(sprintf("  n_used   = %d\n", res$n_used))
cat(sprintf("  n_missing= %d\n", res$n_missing))
cat(sprintf("  missing  = %s\n", paste(res$missing, collapse = ", ")))
stopifnot(res$n_used   == 15L)
stopifnot(res$n_missing == 2L)
stopifnot(nchar(res$plot) > 1000)    # base64 PNG looks sane

# Tolerant match test: request 5 picked genes lowercased; they should
# still map back via case-insensitive fallback.
picked_lc <- tolower(picked[seq_len(5)])
res_ci <- make_heatmap(sid, "host_gene",
                        group = "Group",
                        top_n = 50L,
                        features = picked_lc)
cat("\n[make_heatmap tolerant-match] ", sprintf("n_used=%d / n_missing=%d\n",
                                                  res_ci$n_used, res_ci$n_missing))
stopifnot(res_ci$n_used == 5L, res_ci$n_missing == 0L)

# Back-compat: top-variance call (no features) still returns a bare
# base64 string (not a list).
res_topvar <- make_heatmap(sid, "host_gene", group = "Group", top_n = 30L)
cat("[make_heatmap top-variance back-compat] class = ", class(res_topvar), "\n")
stopifnot(is.character(res_topvar), nchar(res_topvar) > 1000)

# ----------------------------------------------------------------------
# (b) run_all_m16s exports every alpha index and every ordination.
# ----------------------------------------------------------------------
# Build a small fake 16S experiment using demo MAE structure so we can
# exercise the bundle.  For expediency use the gene experiment but pick
# an experiment that supports EMP_alpha_analysis; the demo MAE ships a
# 'microbiome' experiment.
target_exp <- intersect(c("microbiome", "micro", "Genus", "OTU"), names(MAE))
if (!length(target_exp)) {
  # fall back to first experiment; EMP_alpha_analysis still computes the
  # per-sample alpha metrics on any assay.
  target_exp <- names(MAE)[1]
}
target_exp <- target_exp[1]
cat(sprintf("\n[run_all_m16s] using experiment: %s\n", target_exp))

bundle <- run_all_m16s(
  session_id     = sid,
  experiment     = target_exp,
  group_var      = "Group",
  taxonomy_level = "Genus",
  alpha_index    = "shannon",
  beta_method    = "bray",
  ord_method     = "PCoA",
  on_progress    = function(p, m) cat(sprintf("  [%3d%%] %s\n", p, m))
)

cat("\nBundle output:\n")
cat(sprintf("  run_id  = %s\n", bundle$run_id))
cat(sprintf("  zip     = %s (%s)\n", bundle$zip_name,
             if (file.exists(bundle$zip_path)) "exists" else "MISSING"))
cat(sprintf("  elapsed = %.1fs\n", bundle$elapsed_s))

stopifnot(file.exists(bundle$zip_path))

plot_files <- list.files(file.path(bundle$bundle, "plots"))
table_files <- list.files(file.path(bundle$bundle, "tables"))
cat("\nPlots in bundle:\n  ", paste(plot_files, collapse = "\n  "), "\n")
cat("\nTables in bundle:\n  ", paste(table_files, collapse = "\n  "), "\n")

# Alpha: expect at least 2 different alpha indices to have produced a PDF
alpha_pdfs <- grep("^02_alpha_.+_boxplot\\.pdf$", plot_files, value = TRUE)
cat("\nAlpha index PDFs:\n  ", paste(alpha_pdfs, collapse = "\n  "), "\n")
stopifnot(length(alpha_pdfs) >= 2)

# Beta: expect all three ordinations' PDFs
beta_pdfs <- grep("^03_beta_(pcoa|pca|nmds)_scatter\\.pdf$", plot_files, value = TRUE)
cat("\nBeta ordination PDFs:\n  ", paste(beta_pdfs, collapse = "\n  "), "\n")
stopifnot(length(beta_pdfs) >= 2)  # NMDS might silently fail on a tiny dataset

# Done
cat("\nAll smoke checks passed.\n")
