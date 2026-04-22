# EasyMultiProfiler Web Migration (No Shiny UI)

This project already contains a non-Shiny web stack:

- `webapp/frontend`: static HTML/CSS/JS client
- `webapp/backend`: `plumber` REST API
- `R/`: core EasyMultiProfiler analysis/plot functions

The recommended direction is:

1. Keep all analysis logic in R package functions (`R/*.R`)
2. Expose capabilities as REST endpoints in `webapp/backend/plumber.R`
3. Bind each endpoint to web controls in `webapp/frontend`
4. Keep `shiny_app` only as legacy reference until full parity is reached

## Current Coverage (Web API/Frontend)

Already wired end-to-end in web mode:

- Import and session management
- Summary and metadata browsing
- Preparation: filter / normalize / impute / rarefy / collapse
- Analysis: alpha / differential / dimension / correlation / cluster / marker / enrichment / network
- Visualization: barplot / boxplot / heatmap / volcano / scatter / structure / alpha plot
- Export: assay / colData / result / RDS

## Remaining Parity Work vs Shiny Modules

The following modules exist in `shiny_app` but are not fully surfaced in the current web frontend/API:

- GSEA (`ui_gsea.R`)
- WGCNA (`ui_wgcna.R`)
- Multi-omics integrated analysis (`ui_multi_analysis.R`)
- Sankey plot (`ui_sankey.R`)
- Network plot (dedicated view) (`ui_network_plot.R`)
- Enrichment companion plots (`ui_enrich_plots.R`)
- Feature ID convert workflow (`ui_feature_convert.R`)

## Integration Pattern for Any Missing Module

For each missing module, follow this template:

1. **Backend helper**
   - Add an R wrapper in `webapp/backend/helpers/analysis.R` or `viz.R`
   - Call corresponding EasyMultiProfiler function
   - Save updated object via `save_empt()`
   - Return table JSON or base64 plot

2. **API route**
   - Add endpoint in `webapp/backend/plumber.R`
   - Parse request JSON, validate required fields
   - Return `{ success: TRUE, ... }` payload

3. **Frontend API client**
   - Add function in `webapp/frontend/js/api.js`
   - Keep same endpoint naming convention

4. **Frontend UI**
   - Add tab/panel in `webapp/frontend/index.html`
   - Bind event in `webapp/frontend/js/app.js`
   - Render result table (`showResultTable`) or image (`showPlot`)

## Suggested Build Order (Fastest to Full Web Parity)

1. GSEA
2. WGCNA
3. Sankey + network specialized plots
4. Enrichment plot family
5. Multi-omics integration workflow
6. Feature convert tooling

Detailed phase roadmap:

- `webapp/WORKFLOW_ROADMAP.md`

## Run Web Version (No Shiny UI)

From project root:

```bash
# Terminal 1: backend API
Rscript webapp/backend/run_api.R

# Terminal 2: frontend static server (example)
python -m http.server 8080 --directory webapp/frontend
```

Then open:

- Frontend: `http://localhost:8080`
- API health: `http://localhost:8000/api/health`

If frontend and backend are on different ports/domains, set `window.API_BASE` in frontend deployment to point to the API base URL.

## Local operation (recommended)

From project root:

```bash
# Start API + frontend together
webapp/scripts/start_local.sh

# Run smoke regression locally
webapp/scripts/smoke_local.sh

# Stop local services
webapp/scripts/stop_local.sh
```
