# End-to-end 16S pipeline check using repository test data (species-capable matrix).
# Run from repository root:
#   Rscript webapp/test_outputs/m16s_species_e2e.R
#
# Steps: import level-7 taxonomy table + mapping → filter → taxonomy prep (Species)
# → alpha → PCoA → scatter (EMP coordinates) → assert coordinates track filtered assay.
suppressPackageStartupMessages({
  library(EasyMultiProfiler)
  library(SummarizedExperiment)
  library(MultiAssayExperiment)
})
dir <- "webapp/backend"
for (f in c(
    "helpers/session.R", "helpers/utils.R", "helpers/plot_theme.R",
    "helpers/import.R", "helpers/analysis.R", "helpers/viz.R",
    "helpers/workflow_registry.R", "helpers/workflow_microbiome_16s.R",
    "helpers/workflow_microbiome_16s_api.R"
  )) {
  source(file.path(dir, f))
}

repo <- normalizePath(".")
feat <- file.path(repo, "webapp/tests/level-7.csv")
map  <- file.path(repo, "webapp/tests/16S_mapping.csv")
stopifnot(file.exists(feat), file.exists(map))

exp <- "m16s_demo"
mae <- build_mae(
  data_file       = feat,
  metadata_file   = map,
  experiment_name = exp,
  data_type       = "tax",
  assay_name      = "counts",
  start_level     = "Species",
  tax_sep         = ";"
)

sid <- create_session()
save_mae(sid, mae)
empt0 <- load_empt(sid, exp)
n0 <- nrow(SummarizedExperiment::assays(empt0)[[1]])

## Preparation: light filter (drops only ultra-rare rows)
empt1 <- load_empt(sid, exp)
ad <- SummarizedExperiment::assays(empt1)[[1]]
keep <- rowSums(ad > 0, na.rm = TRUE) >= 3L
empt_f <- empt1[keep, ]
mae2 <- load_mae(sid)
mae2[[exp]] <- empt_f
save_mae(sid, mae2)
save_empt(sid, exp, empt_f)
n1 <- nrow(SummarizedExperiment::assays(load_empt(sid, exp))[[1]])
stopifnot(n1 <= n0, n1 > 50L)

## 16S taxonomy-aware prep at Species (same as workflow button)
prep <- m16s_prepare_taxonomy_step(
  session_id           = sid,
  experiment           = exp,
  collapse_level       = "Species",
  min_total_abundance  = 0,
  drop_unassigned      = TRUE,
  keep_top_n           = 0L,
  tax_sep              = ";"
)
stopifnot(isTRUE(prep$success))
ad2 <- SummarizedExperiment::assays(load_empt(sid, exp))[[1]]
stopifnot(ncol(ad2) >= 2L, nrow(ad2) >= 2L)

## Alpha (writes EMP_alpha_analysis on object)
run_alpha(sid, exp)

## Beta: PCoA Bray (same as Analysis → Dimension → PCoA)
run_dimension(sid, exp, method = "PCoA")
empt_dim <- load_empt(sid, exp)
dr <- EasyMultiProfiler::EMP_result(empt_dim, info = "EMP_dimension_analysis")
stopifnot(is.list(dr), !is.null(dr$dimension_coordinate))
coord <- as.data.frame(dr$dimension_coordinate)
stopifnot(nrow(coord) == ncol(ad2))

## Scatter must consume EMP coordinates (not a silent PCA mismatch)
img_auto <- make_scatter(sid, exp, group = "Group", dim1 = 1L, dim2 = 2L,
                         ordination = "auto")
stopifnot(is.character(img_auto), nchar(img_auto) > 500L)

## Stale-dimension guard: auto falls back to assay PCA without error
img_pca <- make_scatter(sid, exp, group = "Group", ordination = "assay_pca")
stopifnot(nchar(img_pca) > 500L)

cat("\n[m16s_species_e2e] OK\n")
cat(sprintf("  features after filter: %d → after Species prep: %d\n", n1, nrow(ad2)))
cat(sprintf("  PCoA rows: %d (expect %d samples)\n", nrow(coord), ncol(ad2)))
