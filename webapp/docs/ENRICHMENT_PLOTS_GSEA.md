# Enrichment figures and GSEA

Analysis → Pathway / Enrichment provides separate ORA (enrichGO/enrichKEGG) and **GSEA** sections. Complete valid differential ranks are used for GSEA; no DEG significance filter is applied. Supported input ID choices: SYMBOL, ENTREZID, ENSEMBL. Choose the correct species explicitly.

GSEA rank options: signed test statistic `stat` (e.g. DESeq2 Wald; unavailable columns fail), log2 fold change, or sign(log2FC) × −log10(raw P). Signed raw-P mode records its zero-P numerical floor. One-to-many and many-to-one mappings are excluded and counted; ranking ties and invalid rows are reported. Parameters: weight 1 (0–2), minimum set size 15, maximum 500 (up to 10000), seed 20261108. GO-BP/CC/MF uses gseGO; KEGG uses gseKEGG and requires external KEGG data access. Installed clusterProfiler interface selects multilevel or fgsea. BH-adjusted results, full ranked list, gene sets, mapping audit and versioned gseaResult RDS are saved. This is preranked gene-set inference, not sample-label permutation or a causal test.

Visualization tabs retain the original R renderer and add:

| Figure parameter | Default / behavior |
|---|---|
| Source | Explicit saved completed analysis task; current GSEA also available |
| ORA term selection | Optional IDs; otherwise Top N |
| Top N | 20, range 1–100 |
| Sort | Adjusted P ascending; GeneRatio or Count descending selectable |
| Adjusted-P filter | 1 (display all saved terms), range 0–1 |
| X axis | GeneRatio = Count / query size, not pathway background size |
| Bubble area | Count; maximum point size 10, range 1–25 |
| Bubble color | −log10(adjusted P); low/high colors configurable |
| Label wrapping | 45 characters, range 10–150 |
| Highlight | Source term IDs; outlined points, without changing significance |
| GSEA pathway | Select an ID from the saved GSEA table |
| GSEA weight | Frozen to original analysis exponent for saved inference |
| GSEA curve | Running ES, hit positions, full rank metric color strip |
| Manual ranked list | CSV/TSV gene_id,metric,in_set; optional consecutive rank; unique IDs, finite decreasing metric. This is ES-only visualization and does not estimate NES/FDR |
| Size and fonts | Width/height in inches, base size in points; title, line color and set label configurable |
| Exports | PNG 300 dpi, PDF, SVG, derived CSV and JSON source/parameter manifest |

Replotting reads saved values and never reruns enrichment. ORA sources cannot supply a GSEA ranked universe. Every export has a unique prefix. Session and job ownership are checked before source access or downloads. Figure style controls are forwarded to the existing R theme machinery.

Tests:

```bash
node --test webapp/tests/*.mjs
Rscript --vanilla webapp/tests/test_gsea_analysis.R
Rscript --vanilla webapp/tests/test_viz_enrichment.R
EMP_TEST_REAL_GSEA=1 Rscript --vanilla webapp/tests/test_gsea_analysis.R
```

Validated locally: actual mouse GO GSEA using an explicit 1500-gene statistical fixture, background submission, saved-job source selection, pathway figure and authenticated PNG/PDF/SVG/CSV/manifest downloads. Fixture results are not biological findings. Live KEGG access and browser clicking were not verified in this run.

Reference: [clusterProfiler documentation](https://www.bioconductor.org/packages/release/bioc/html/clusterProfiler.html).

Background task cleanup: “Clear finished tasks” hides done/error/cancelled records only, persists the view locally, and preserves all task result files and active jobs. “Restore hidden tasks” restores the list view. Cleanup does not cancel jobs or delete analysis data.

Source filtering: single-omics mode uses the experiment registry's declared omics type, includes compatible experiments from the same session, and never infers an experiment type from its name. Unknown legacy types remain restricted to the current experiment. Only the explicit multiomics mode lists all types. Switching type clears stale selections and plot outputs.
