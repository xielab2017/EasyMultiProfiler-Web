# One-click RNA-seq and 16S bundles

Both background pipelines create a unique run directory and ZIP. The response keeps
`run_id`, `zip_name`, `elapsed_s`, and adds `stages`, `counts`, `partial`, `figures`.
Every stage records `done`, `skipped`, or `error`, a reason, warnings, elapsed time,
and the files it actually generated. Disabled or inapplicable work is never
reported as a completed analysis. A ZIP with stage errors has `partial=true`.

The bundle contains `manifest.json`, `stages.json`, `summary.txt`, `sessionInfo.txt`,
input/source details, CSV tables, XLSX when openxlsx is available, and real R
PNG/PDF/SVG exports. Every run gets a unique path; existing runs are preserved.

## Parameters

Shared optional fields: `do_correlation=true`, `do_cluster=true`,
`do_method_figures=true`, `feature_top_n=100` (2–300), `network_cutoff=0.6`, `seed=1`.
Feature networks use the top varying features, export every retained edge, and
show at most 500 strongest absolute correlations. These are descriptive networks,
without correlation P-value filtering or causal inference.

RNA-seq retains its group/reference/test, species, FC/P and enrichment options.
`do_gsea=false` is deliberately opt-in because annotation/network analysis can be
slow; configure `gsea_database=GO_BP` and `gsea_top_n=3` for real preranked GSEA.
No significant-DEG filtering is applied to GSEA ranks. GO/KEGG ORA and GSEA stages
record unavailable dependencies or network errors; they never install packages.
Multiple RNA-seq groups require an explicit reference/test for this one-click
contrast; the analysis workspace remains the place for all-pairwise/LRT designs.

16S accepts `ternary_groups=[top_A,left_B,right_C]`. Without an explicit selection,
ternary is only attempted when the reviewed group variable has exactly three
groups. Taxonomy is aggregated locally without deleting unassigned or low-ranked
taxa; raw counts and the caller's assay are unchanged. The composition graph
retains an Other category, avoiding renormalization of just the displayed taxa.

## Statistical scope

RNA differential analysis receives validated original counts, recovering by exact
feature/sample identifiers when needed. Log2(CPM+1) is used only in local display
matrices. This display transform is not presented as DESeq2 VST or used to fit
count models. Adjusted-P selection never switches to raw P when nothing passes.

16S alpha diversity uses all input features. Beta diversity uses relative-abundance
Bray-Curtis with explicit sample/group data. PERMANOVA and dispersion tests use
up to 999 unrestricted permutations (complete enumeration for small sample spaces) and assume independent exchangeable samples; no
batch, paired/repeated-measure, or covariate adjustment is inferred. Differential
relative abundance uses two-group Wilcoxon, or all-group Kruskal-Wallis, with BH
adjustment. An omnibus result has no single fold-change direction, so pairwise
volcano and DEG heatmap stages are explicitly skipped.

Missingness, negative/CLR inputs, invalid libraries, and undefined statistics are
not silently repaired. Optional Figure Methods Lab adapters load the current
trusted `EMP_FIGURE_METHODS_ROOT`, preserve their source hashes and parameters,
and export derived values without copying the external implementations.

## Checks

`Rscript --vanilla webapp/tests/test_runall_complete.R` exercises stage errors,
intentional skips, unique run paths, unchanged count inputs, real R exports/ZIP,
three-group microbial tests, taxonomy, diversity, and conditional ternary figures
using deterministic synthetic fixtures. These checks do not perform genuine
DESeq2/GO/KEGG/GSEA scientific inference or external annotation-network requests.

网页的完整 RNA-seq 流程默认勾选 GSEA；用户可在高级设置取消。后端保留缺省关闭以兼容原有 API 调用。所有实际完成、跳过与失败以结果包的阶段清单为准。
