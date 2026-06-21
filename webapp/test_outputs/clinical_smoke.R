# End-to-end smoke test for the clinical analysis helpers, using the MAE
# that ships with EasyMultiProfiler (has real clinical columns like Age,
# BMI, PHQ9, GAD7, etc. and a host_gene expression experiment).  Writes
# all outputs under webapp/test_outputs/.
suppressPackageStartupMessages({
  library(EasyMultiProfiler)
  library(MultiAssayExperiment)
  library(SummarizedExperiment)
  library(ggplot2)
  library(S4Vectors)
})
dir <- "webapp/backend"
for (f in c("helpers/session.R","helpers/utils.R","helpers/plot_theme.R",
            "helpers/import.R","helpers/analysis.R","helpers/viz.R",
            "helpers/workflow_registry.R","helpers/workflow_metabolomics.R",
            "helpers/workflow_metagenomics.R","helpers/workflow_transcriptomics.R",
            "helpers/workflow_microbiome_16s.R",
            "helpers/workflow_microbiome_16s_api.R","helpers/clinical.R"))
  source(file.path(dir, f))

data(MAE)
sid <- create_session()
save_mae(sid, MAE)
cat(sprintf("\nSession: %s\nExperiments: %s\n",
            sid, paste(names(MAE), collapse = ", ")))

# --- 1. list_clinical_vars ----------------------------------------
v <- list_clinical_vars(sid, "host_gene")
cat("\n[list_clinical_vars]\n")
print(v)
stopifnot("Age" %in% v$name[v$type == "numeric"])
stopifnot("BMI" %in% v$name[v$type == "numeric"])
stopifnot("Group" %in% v$name[v$type == "categorical"])

# --- 2. run_clinical_cor ------------------------------------------
cor_res <- run_clinical_cor(sid, "host_gene",
                             traits = c("Age", "BMI", "PHQ9", "GAD7"),
                             method = "spearman",
                             top_n_features = 30,
                             p_adjust = "BH",
                             pdf_path = "webapp/test_outputs/clinical_cor.pdf")
cat(sprintf("\n[run_clinical_cor] %d features × %d traits, n=%d samples; %d rows\n",
            cor_res$n_feat, 4L, cor_res$n_samp, nrow(cor_res$table)))
print(cor_res$table[order(cor_res$table$p), ][1:10, ])
stopifnot(nrow(cor_res$table) == cor_res$n_feat * 4L)
stopifnot(nchar(cor_res$png) > 1000)
stopifnot(file.exists(cor_res$pdf))

# --- 3. make_fitline_scatter --------------------------------------
# Pick the top-correlated feature for Age.
top_age <- cor_res$table
top_age <- top_age[top_age$trait == "Age", ]
top_age <- top_age[order(top_age$p), ][1, ]
fit_res <- make_fitline_scatter(sid, "host_gene",
                                 feature = top_age$feature,
                                 trait   = "Age",
                                 group   = "Group",
                                 pdf_path = "webapp/test_outputs/clinical_fitline.pdf")
cat(sprintf("\n[make_fitline_scatter] %s vs Age   r = %.3f   p = %.3g   n = %d   grouped = %s\n",
            top_age$feature, fit_res$r, fit_res$p, fit_res$n, fit_res$group_used))
stopifnot(fit_res$n > 0, file.exists(fit_res$pdf))

# --- 4. make_deg_heatmap canvas auto-sizing ------------------------
# Supply a small fake diff_raw so we can invoke the heatmap path.
genes <- rownames(assay(MAE[["host_gene"]]))[1:40]
diff_raw <- list(
  data = data.frame(
    feature = genes,
    symbol  = genes,
    log2FoldChange = c(runif(20, 1, 3), runif(20, -3, -1)),
    pvalue  = runif(40, 0, 0.01),
    padj    = runif(40, 0, 0.02),
    stringsAsFactors = FALSE
  ),
  ref_group = "Group_A", test_group = "Group_B",
  group_var = "Group", group_var_orig = "Group"
)
saveRDS(diff_raw, diff_raw_path(sid, "host_gene"))

hm <- make_deg_heatmap(sid, "host_gene", group = "Group",
                        fc_cutoff = 1, p_cutoff = 0.05, use_padj = TRUE,
                        pdf_path = "webapp/test_outputs/clinical_deg_heatmap.pdf")
cat(sprintf("\n[make_deg_heatmap] plotted %d genes\n", hm$n_genes))

# Inspect the PDF dimensions produced.
if (requireNamespace("pdftools", quietly = TRUE)) {
  info <- pdftools::pdf_info("webapp/test_outputs/clinical_deg_heatmap.pdf")
  dims <- info$pages[[1]]
  cat(sprintf("DEG heatmap PDF size: %.2f x %.2f inches\n",
              dims$width / 72, dims$height / 72))
}

cat("\nALL CLINICAL SMOKE TESTS PASSED\n")
