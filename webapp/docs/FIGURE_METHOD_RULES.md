# R figure methods integration

The visualization page uses the original R rendering endpoints. The experimental browser SVG snapshot renderer is disconnected.

Choose **Original** (default) or **Self-built methods** in Visualization / Figure style. Self-built style applies to ggplot-based figures, reading the live `library/common.R` theme; pheatmap retains the original renderer. This is theme integration, not a complete port of the library's specialized case layouts.

Configure `EMP_FIGURE_METHODS_ROOT` in the ignored `webapp/config/runtime.env` on the server. No library implementation is copied into this repository. If the selected library is unavailable, the request reports an error. Other installations retain the original theme by default.

Scientific contracts: the requested adjusted-P metric is retained even when no result passes the cutoff; finite fold changes are not clipped. Missing P rows are reported as exclusions. Non-finite heatmap values, negative values requested for log1p, and zero-variance rows report errors instead of silent repair. PCA regions are labeled as covariance dispersion, drawn only with at least four samples and nonsingular covariance; they are not mean confidence intervals.

Self-built ggplot PDF saves also create a unique sibling archive directory with PNG (300 dpi), SVG, PDF, and a manifest containing dimensions, style parameters, library checksums and R/ggplot2 versions. Existing archive outputs are not overwritten. The ordinary PDF remains the session preview/download cache. Original style keeps its existing export behavior.

Validation:

```bash
Rscript --vanilla webapp/tests/test_figure_method_rules.R
Rscript --vanilla webapp/tests/test_viz_scientific_rules.R
node --test webapp/tests/*.mjs
```
