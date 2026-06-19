/**
 * Reference snippets mirroring server routes in webapp/backend/plumber.R (+ helpers).
 * Shown in the UI for transparency; edits are local notes only — API calls are unchanged.
 */
export const CODE_LAB_TEMPLATES = {
  preparation: {
    "prep-filter": `# ── POST /api/prepare/filter (plumber.R) ─────────────────────
# Loads EMPT (stack vs single mode), filters rows by assay thresholds, saves MAE + snapshot.

.prepare_load_base <- function(session_id, experiment, mode = "stack") {
  m <- tolower(trimws(as.character(mode %||% "stack")))
  if (identical(m, "single")) {
    raw <- load_raw_empt(session_id, experiment)
    if (!is.null(raw)) return(raw)
  }
  load_empt(session_id, experiment)
}

# Body JSON: session_id, experiment, min_count, min_detect_rate, max_detect_rate,
# min_prevalence, max_na, min_samples, prepare_mode
empt  <- .prepare_load_base(session_id, experiment, mode = mode)
ad    <- SummarizedExperiment::assays(empt)[[1]]
keep  <- rep(TRUE, nrow(ad))
if (min_count  > 0) keep <- keep & apply(ad, 1, max, na.rm = TRUE) >= min_count
# ... detect_rate / prevalence / max_na filters ...
empt_filtered <- empt[keep, ]
# save_mae, save_empt, save_prepare_snapshot(...)
`,

    "prep-normalize": `# ── POST /api/prepare/normalize ─────────────────────────────
# Body: session_id, experiment, method (rclr|clr|hellinger|total|log|CSS), prepare_mode
empt <- .prepare_load_base(session_id, experiment, mode = mode)
empt <- empt |> EasyMultiProfiler::EMP_decostand(method = method)
# mae[[experiment]] <- empt; save_mae; save_empt; snapshot
`,

    "prep-impute": `# ── POST /api/prepare/impute ────────────────────────────────
empt <- .prepare_load_base(session_id, experiment, mode = mode)
empt <- empt |> EasyMultiProfiler::EMP_impute(method = method)  # knn|zero|min|mean
`,

    "prep-rarefy": `# ── POST /api/prepare/rarefy ────────────────────────────────
empt <- .prepare_load_base(session_id, experiment, mode = mode)
empt <- do.call(EasyMultiProfiler::EMP_rrarefy, args)  # optional sample= integer
`,

    "prep-collapse": `# ── POST /api/prepare/collapse ──────────────────────────────
empt <- .prepare_load_base(session_id, experiment, mode = mode)
empt <- empt |> EasyMultiProfiler::EMP_collapse(taxa_level = taxa_level)
`,

    "prep-m16s-taxonomy": `# ── 16S taxonomy prep (see workflow_microbiome_16s_api.R + plumber routes)
# Frontend calls e.g. POST /api/workflows/microbiome_16s/prepare/taxonomy
# with collapse_level, tax_sep, filters — server merges into MAE and snapshots.
`,
  },

  analysis: {
    "ana-alpha": `# ── POST /api/analyze/alpha ─────────────────────────────────
# helpers/analysis.R → run_alpha(): EMP_alpha_analysis on EMPT, optional vegan metrics
# JSON: session_id, experiment, method, source (current|raw|relative)
`,
    "ana-diff": `# ── POST /api/analyze/differential | /analyze/differential/async
# DESeq2 / edgeR / limma / wilcox / t.test — helpers/analysis.R + jobs for async
`,
    "ana-dim": `# ── POST /api/analyze/dimension ────────────────────────────
# PCA / PCoA / NMDS etc. via EasyMultiProfiler EMP pipeline on current EMPT
`,
    "ana-cor": `# ── POST /api/analyze/correlation ──────────────────────────
`,
    "ana-cluster": `# ── POST /api/analyze/cluster ───────────────────────────────
`,
    "ana-marker": `# ── POST /api/analyze/marker ─────────────────────────────────
`,
    "ana-enrich": `# ── POST /api/analyze/enrichment (+ /async, /enrichment/install)
# clusterProfiler + OrgDb species packages
`,
    "ana-network": `# ── POST /api/analyze/network ───────────────────────────────
`,
    "ana-tx": `# ── Transcriptomics workflow routes under /api/workflows/transcriptomics/…
# profile, validate, differential, gsea, wgcna, visualize/* — see workflow_transcriptomics.R
`,
    "ana-mgx": `# ── Metagenomics: /api/workflows/metagenomics/* — workflow_metagenomics.R
`,
    "ana-mbx": `# ── Metabolomics: /api/workflows/metabolomics/* — workflow_metabolomics.R
`,
    "ana-cross": `# ── Cross-omics helpers (clinical/multiomics_joint etc.) — clinical.R + plumber
`,
  },

  clinical: {
    overview: `# ── Clinical overview (plumber + helpers/clinical.R)
# GET /api/clinical/vars/:session/:experiment
# GET /api/clinical/vars_standalone/:session
# POST /api/clinical/reorient — metadata orientation
`,
    cor: `# ── POST /api/clinical/cor ─────────────────────────────────────
# Feature × trait correlation matrix + heatmap payload
`,
    fitline: `# ── POST /api/clinical/fitline ────────────────────────────────
# Single feature vs numeric trait + optional grouping
`,
    wgcna: `# ── POST /api/clinical/wgcna/async ───────────────────────────
# Background job: WGCNA module–trait correlation
`,
    three_line: `# ── POST /api/clinical/three_line ───────────────────────────
# gtsummary / EMP fallback three-line table
`,
    systematic: `# ── POST /api/clinical/systematic_summary ───────────────────
# Baseline + within/between group summaries
`,
    joint: `# ── POST /api/clinical/multiomics_joint ───────────────────────
`,
    marker_model: `# ── POST /api/clinical/marker_model ───────────────────────
# Multi-omics + clinical marker diagnostic / warning model

b <- list(
  session_id = session_id,
  experiments = c("REPLACE_EXPERIMENT"),
  outcome_var = "REPLACE_BINARY_OUTCOME",
  positive_class = NULL,
  methods = c("randomForest", "lasso", "xgboost"),
  clinical_source = "experiment",
  include_clinical_numeric = TRUE,
  max_features_per_omics = 200L,
  validation_fraction = 0.3,
  top_n = 30L,
  seed = 123L
)

out <- run_clinical_marker_model(
  session_id = b$session_id,
  experiments = b$experiments,
  outcome_var = b$outcome_var,
  positive_class = b$positive_class,
  methods = b$methods,
  clinical_source = b$clinical_source,
  include_clinical_numeric = b$include_clinical_numeric,
  max_features_per_omics = b$max_features_per_omics,
  top_n = b$top_n,
  validation_fraction = b$validation_fraction,
  seed = b$seed
)

list(
  success = TRUE,
  performance = out$performance,
  markers = out$markers,
  sample_scores = out$sample_scores,
  meta = out$meta
)
`,
    reorient: `# ── POST /api/clinical/reorient ─────────────────────────────
`,
  },

  runall: {
    "runall-rnaseq": `# ── POST /api/workflows/rnaseq/run_all ─────────────────────
# helpers/runall.R + jobs: DESeq2 pipeline, plots, Excel, zip bundle download
`,
    "runall-m16s": `# ── POST /api/workflows/microbiome_16s/run_all ───────────────
# 16S end-to-end: taxonomy, alpha/beta, diff, exports → zip
`,
  },

  visualization: {
    "viz-barplot": `# Web API: POST /api/visualize/barplot → make_barplot(session_id, experiment, …)
# 全文片段：js/snippets/visualization__viz-barplot.r.txt（由 build_code_snippets.py 生成）
`,
    "viz-boxplot": `# ── POST /api/visualize/boxplot ────────────────────────────
`,
    "viz-heatmap": `# ── POST /api/visualize/heatmap ─────────────────────────────
`,
    "viz-volcano": `# ── POST /api/visualize/volcano ─────────────────────────────
`,
    "viz-scatter": `# ── POST /api/visualize/scatter ─────────────────────────────
`,
    "viz-structure": `# ── POST /api/visualize/structure ──────────────────────────
`,
    "viz-alpha": `# ── POST /api/visualize/alpha ───────────────────────────────
`,
    "viz-tx": `# ── /api/workflows/transcriptomics/visualize/* — heatmap, volcano
`,
    "viz-m16s-sankey": `# ── POST /api/workflows/microbiome_16s/visualize/sankey ───
`,
    "viz-m16s-network": `# ── POST /api/workflows/microbiome_16s/visualize/network ─
`,
    "viz-mgx": `# ── POST /api/workflows/metagenomics/visualize/heatmap|volcano ───
`,
  },
};
