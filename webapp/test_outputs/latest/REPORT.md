# EasyMultiProfiler Web — Full Validation Report

Date: 2026-04-17
Runner: `webapp/tests/run_full_validation.py`

## Scope

Drives every user-facing web feature against the two reference datasets in
`webapp/tests/`:

- RNAseq (24 samples × 19,150 genes, `Group` with 6 levels)
- 16S (6 samples × 160 taxa → collapsed to 50, `group` tax_1 / tax_2)

For every step the runner captures the JSON payload and/or the rendered PNG
under `webapp/test_outputs/latest/<omics>/`. All PNGs are generated server-side
at 300 dpi via ragg/cairo with journal-ready typography.

## Results

| Omics | Passed | Total |
| --- | --- | --- |
| Transcriptomics (RNAseq) | 18 | 18 |
| Microbiome 16S | 22 | 22 |
| **Total** | **40** | **40** |

## Coverage per workflow

Transcriptomics (`webapp/test_outputs/latest/transcriptomics/`):

- Data import, summary, coldata, inspector (overview / assay / colData / rowData)
- Workflow profile + validate, differential (Wilcoxon)
- Heatmap (top-50 variable, within-group clustering, group annotation bar)
- Volcano (`log2FC` clipped to 99th-percentile, legend with Up/Down/NS counts, ggrepel labels)
- PCA scatter (variance %, 95% CI ellipses, PERMANOVA p-value)
- Boxplot (top feature, Wilcoxon significance stars, per-group N)
- Barplot (top-20, mean abundance grouped)
- Structure (top-10 + Other, relative abundance, faceted)
- EMPT export (`.rds` file generated server-side before download)
- CSV exports (assay / metadata / differential table)

Microbiome 16S (`webapp/test_outputs/latest/microbiome_16s/`):

- All of the above where applicable, plus:
- Alpha diversity (Shannon, Simpson, InvSimpson, Chao1, observed, ACE) with Wilcoxon annotation
- Sankey (Phylum → Genus, top-40 ribbons proportional to abundance)
- Network (Spearman, force-directed layout via igraph, taxa-level node labels, diverging correlation palette)
- Taxonomy prepare / collapse round-trip (rebuilt as proper EMPT after collapse)

## Publication-grade plot standards

All plots share a consistent visual system defined in
`webapp/backend/helpers/plot_theme.R`:

- 300 dpi output with ragg when available, cairo fallback
- Journal-friendly theme (sans serif, tuned axis/title/legend weights)
- Editorial categorical palettes (ggsci NPG / Lancet / NEJM) with RColorBrewer fallback
- Diverging palette `RdBu` for continuous `z-score` / correlation
- Statistical annotations:
  - `emp_pairwise_wilcox` → significance stars on boxplots / alpha plots
  - `emp_permanova_p` → PERMANOVA p-value in scatter captions
  - `emp_conf_ellipse` → 95 % confidence ellipses per group
- `ggrepel` non-overlapping labels for volcano / network
- `patchwork` group annotation bars for heatmaps

## Fixes applied during this pass

1. `m16s_prepare_taxonomy` now writes a `feature` column in `rowData` so the
   collapsed experiment re-promotes to a proper EMPT via
   `EMP_assay_extract`.
2. `load_empt` checks the persisted class; if the cached `.rds` is a bare
   `SummarizedExperiment` it rebuilds the EMPT from the MAE so downstream
   `EMP_*` calls continue to work after collapse / export round-trips.
3. Alpha plot now resolves sample IDs via `primary`/`sample`/`sampleID`
   columns and maps them back to `colData` so groups never render as `NA`.
4. New `.viz_feature_labels` helper maps internal `feature_N` IDs to the
   deepest informative taxonomy or gene name for heatmap / boxplot /
   barplot / structure / volcano / network outputs.
5. Heatmap adds a colored group annotation bar (via `patchwork`) and uses
   within-group hierarchical clustering of samples.
6. Volcano plot picks `log2FC` columns over raw `fold_change`, clips extreme
   values to the 99th-percentile, and renders Up/Down/NS counts in the legend
   even when a category is empty.

## Artifacts

- `transcriptomics/` — all JSON payloads, CSV exports, PNG plots, EMPT .rds
- `microbiome_16s/` — same, plus alpha / sankey / network / taxonomy prepare
- `REPORT.md` (this file)
