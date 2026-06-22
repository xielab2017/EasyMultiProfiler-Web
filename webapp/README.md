# EasyMultiProfiler Webapp

This folder contains the non-Shiny web interface for EasyMultiProfiler.

## Run locally

### One-line install (recommended)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/v5.0.2/webapp/scripts/install_from_github.sh)"
```

This command does everything automatically:

1. Download project from GitHub
2. Install required dependencies
3. Start services and open the web page

Open:

- Frontend: http://127.0.0.1:8080
- API health: http://127.0.0.1:8000/api/health

Stop services:

```bash
webapp/scripts/stop_local.sh
```

## Verify operation

Run the end-to-end smoke workflow:

```bash
webapp/scripts/smoke_local.sh
```

The smoke test creates a temporary session and verifies:

- Session creation and data import.
- Summary, inspector, assay/metadata/RDS/EMPT exports.
- Generic preparation, alpha, dimension, correlation, barplot, boxplot, heatmap, structure, alpha plot, PCA scatter, differential, and volcano operations.
- Transcriptomics, metagenomics, metabolomics, and microbiome 16S workflow validation.
- 16S sample-row matrix import, Sankey plot, network plot, and taxonomy preparation.

## Upload formats

The importer accepts both common matrix orientations:

- Features as rows and samples as columns.
- Samples as rows and features as columns, when the first column is a sample ID column or matches the metadata sample IDs.

For 16S/taxonomy data, nonnumeric upload columns such as `absolute-filepath` are ignored during automatic transposition.

