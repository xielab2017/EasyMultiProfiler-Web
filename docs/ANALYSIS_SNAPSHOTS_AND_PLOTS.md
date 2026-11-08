# Analysis snapshots, plots and one AI chat

The Visualization page lists completed background tasks owned by the current user. The selector reads recent job metadata and uses each task's persisted RDS result through its job ID. Changing the active experiment does not change the selected task's numerical result. New job records also retain the analysis method, contrasts and other selected analysis parameters. Older records can lack those fields; their original results remain usable.

Choose a task, click **读取快照并出图**, then choose a compatible chart. The browser offers charts only when the saved fields support them:

| Result | Charts |
| --- | --- |
| Retained dimension coordinates | Scatter plot using the first two named coordinate axes |
| Differential effects and P/FDR | Volcano plot; effect bars ranked by P/FDR |
| Enrichment terms with Count | Term-count bars; bubbles when GeneRatio is also available |
| Correlation variable pairs and coefficients | Coefficient matrix; exploratory circular network |
| Cluster assignments | Cluster membership counts |
| A saved PNG plot | The original plot, when retained in the response |

Generated charts can be downloaded as SVG. Plotting uses retained results, not the currently selected assay, and does not recompute an analysis. Missing coefficients are left absent; missing adjusted P values are not replaced with raw P values. Networks are limited to the first 24 saved variables and do not imply significance or biological distance. A label-only cluster snapshot cannot reconstruct a dendrogram. Unknown result types remain downloadable from the task tray as full JSON. The selector currently reads up to 500 recent task records.

The result's **AI 解读结果** action opens the single right-side AI chat and automatically sends a bounded result summary to the loaded model. It excludes matrices, sample identifiers, filenames and images. Interpretation therefore cannot claim to visually inspect a plot. Only displayed result rows and approved statistical columns enter the summary; biological and causal interpretations require separate scientific review. Ordinary conversation no longer has a per-message sharing checkbox, following the requested interface preference. Agent task execution retains a separate current-page review grant.

Tests:

```sh
node --test webapp/tests/test_analysis_snapshots.mjs webapp/tests/test_agent_chat.mjs
Rscript webapp/tests/test_background_tasks.R
```

Browser verification used an existing dimension task (12 retained coordinates) and an existing enrichment task to switch between term-count bars and a bubble plot. A real MiniMax response was obtained for conversation and an enrichment interpretation. This does not validate every provider/model, scientific interpretation, or chart type with every possible dataset.
