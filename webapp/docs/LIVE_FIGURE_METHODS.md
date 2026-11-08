# Omics-specific figure methods

The Visualization page contains an applicable-figure directory. Shared native R plots remain available only for their declared omics. Proteomics now has a dedicated sidebar choice. Switching while a page is hidden also reselects an applicable tab, rather than leaving a panel from the previous omics visible.

- Microbiome 16S / metagenomics: ternary composition bubbles, existing composition/diversity and PCA/PCoA plots.
- Transcriptomics / proteomics / metabolomics: differential significance scatter from reviewed cached adjusted-P/log2FC statistics; existing applicable heatmap/PCA/volcano entries.
- Gene-based enrichment/GSEA: transcriptomics/proteomics and mapped metagenomic gene/function results. Generic clinical or metabolite tables are not treated as gene rankings.
- ChIP: existing dedicated ChIP/deepTools downstream page. The library's synthetic genome-track demo is not exposed as a real BigWig pipeline.
- Clinical: existing clinical plotting modules.

New live methods load current trusted `EMP_FIGURE_METHODS_ROOT/library/plot_methods.R` and `common.R` on every render. No case code from a request is executed. If the library is unavailable, the request fails clearly.

Ternary input: nonnegative finite feature-by-sample abundance, group metadata and exactly three selected groups. Normalize each sample by its complete library sum, compute per-group means, then normalize each feature's three means to A+B+C=1. Top N is applied after normalization. Size is the equal-weight mean of group mean relative abundances. Color denotes the group with greatest mean abundance; ties are Unclassified, not taxonomy. CLR/negative inputs and zero-library samples are rejected. No differential test is implied.

Differential scatter: x=−log10(adjusted P), optionally square-root spacing with explicit axis note; y=log2FC. External statistics are not refit, truncated or BH-recomputed. Missing, nonfinite or zero adjusted P values require input review; they are not quietly replaced. Labels, thresholds, point size, palette, dimensions and font size are configurable.

Each render preserves PNG (300dpi), PDF, SVG, derived CSV, exact input CSV, RDS config, sessionInfo and source/code checksums in a unique case directory. Existing results are not overwritten. The integration fixtures were rendered and visually reviewed; they are not biological findings.

Checks: `Rscript --vanilla webapp/tests/test_viz_method_library.R`; `node --test webapp/tests/*.mjs`.
