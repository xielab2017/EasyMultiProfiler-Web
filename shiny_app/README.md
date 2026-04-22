# EasyMultiProfiler Web Application

A comprehensive web-based interactive platform for multi-omics data analysis using the EasyMultiProfiler R package.

## Features

### Data Management
- **Unified Data Import with Metadata**: 
  - **Single Page**: Import data and metadata together in one streamlined interface
  - **Auto-Detection**: Automatically detects file format, features, samples, and data types
  - **Smart Column Detection**: Handles index columns, automatically identifies feature and sample columns
  - **Metadata Integration**: Upload metadata file alongside data - automatically maps and merges
  - **Multi-omics Support**: 
    - **16S/Microbiome**: Taxonomy data (CSV, TSV, BIOM, QZV formats)
    - **RNAseq**: Gene expression data (counts, TPM, FPKM)
    - **Metabolomics**: Metabolite abundance/intensity data
    - **Proteomics**: Protein expression data
    - **Metagenomics**: Functional data (KEGG Orthology KO, Enzyme Commission EC)
    - **Clinical Data**: Any tabular omics data
- **Data Summary**: View comprehensive summaries of imported data
- **Data Preparation**: 
  - Filtering (samples and features)
  - Normalization (multiple methods)
  - Missing value imputation
  - Rarefaction
  - Feature collapsing
  - Feature ID conversion

### Analysis Modules
All analysis modules work with all omics data types (16S, RNAseq, Metabolomics, Proteomics, Metagenomics, Clinical):

- **Alpha Diversity**: Calculate diversity indices (Shannon, Simpson, Chao1, etc.) - *Primarily for 16S/microbiome*
- **Correlation Analysis**: Feature-feature and sample-sample correlations - *All omics types*
- **Differential Analysis**: DESeq2, edgeR, limma, Wilcoxon, t-test - *All omics types*
- **Dimension Reduction**: PCA, t-SNE, UMAP, MDS - *All omics types*
- **Cluster Analysis**: Hierarchical, K-means, PAM clustering - *All omics types*
- **Marker Analysis**: Identify marker features (Random Forest, LEfSe, ANCOM) - *All omics types*
- **Enrichment Analysis**: GO, KEGG, Reactome, MSigDB - *RNAseq, Proteomics, Functional data*
- **GSEA**: Gene Set Enrichment Analysis - *RNAseq, Proteomics, Functional data*
- **WGCNA**: Weighted Gene Co-expression Network Analysis - *RNAseq, Metabolomics, Proteomics*
- **Network Analysis**: Feature interaction networks - *All omics types*
- **Multi-omics Integration**: Integrate multiple omics datasets - *Combine any omics types*

### Visualization
- **Barplot**: Grouped barplots with statistical tests
- **Boxplot**: Boxplots with violin plots option
- **Heatmap**: Feature expression heatmaps with clustering
- **Volcano Plot**: Differential analysis visualization
- **Scatterplot**: Dimension reduction plots (PCA, t-SNE, UMAP)
- **Sankey Plot**: Flow diagrams for taxonomy levels
- **Network Plot**: Feature interaction networks
- **Enrichment Plots**: Dotplot, network plot, curve plot
- **Structure Plot**: Data composition visualization

### Export
- Export data in multiple formats (CSV, TSV, Excel, RDS)
- Export analysis results as tables
- Export plots in high-resolution formats (PNG, PDF, SVG, EPS)
- Export complete analysis session

## Installation

### Prerequisites
- R (>= 4.3.3)
- EasyMultiProfiler package installed
- Required R packages (see below)

### Required R Packages

```r
# Core Shiny packages
install.packages(c("shiny", "shinydashboard", "shinyjs", "DT"))

# EasyMultiProfiler dependencies (should be installed with EasyMultiProfiler)
# If not, install EasyMultiProfiler first:
if (!requireNamespace("pak", quietly=TRUE)) install.packages("pak")
pak::pak("liubingdong/EasyMultiProfiler")

# Optional for Excel export
install.packages("writexl")
```

### Installation Steps

1. Ensure EasyMultiProfiler is installed:
```r
library(EasyMultiProfiler)
```

2. Navigate to the shiny_app directory:
```r
setwd("path/to/EasyMultiProfiler-main/shiny_app")
```

3. Run the application:
```r
shiny::runApp("app.R")
```

Or from command line:
```bash
Rscript -e "shiny::runApp('app.R', port=3838, host='0.0.0.0')"
```

## Usage

### Starting the Application

1. Open R or RStudio
2. Load required libraries
3. Set working directory to `shiny_app`
4. Run `shiny::runApp("app.R")`

### Workflow

1. **Import Data with Metadata** (All in One Step): 
   - Go to "Data Import" tab
   - Upload your data file (CSV, TSV, BIOM, QZV)
   - Click "Preview & Auto-Detect" to see detected settings
   - (Optional) Upload metadata file - automatically maps to your data
   - Adjust settings if needed (most are auto-detected)
   - Click "Import Data" - data and metadata are imported together
   - System automatically:
     - Detects file format from extension
     - Identifies feature and sample columns
     - Handles index columns
     - Maps metadata to samples
     - Creates experiment with proper structure

2. **Data Preparation**:
   - Use "Data Preparation" menu for filtering, normalization, etc.
   - Each step modifies your data and stores results

3. **Analysis**:
   - Navigate to "Analysis" menu
   - Select the type of analysis you want to perform
   - Configure parameters and run analysis

4. **Visualization**:
   - Go to "Visualization" menu
   - Select plot type and configure options
   - Generate and download plots

5. **Export**:
   - Use "Results Export" tab to download:
     - Processed data
     - Analysis results
     - Plots
     - Complete session

## File Structure

```
shiny_app/
├── app.R                 # Main application file
├── ui/                   # UI modules
│   ├── ui_main.R        # Main UI structure
│   ├── ui_import.R      # Data import UI
│   ├── ui_summary.R     # Data summary UI
│   ├── ui_*.R           # Other UI modules
├── server/              # Server logic modules
│   ├── server_main.R    # Main server logic
│   ├── server_import.R  # Import server logic
│   ├── server_*.R       # Other server modules
├── www/                 # Static files
│   └── custom.css       # Custom styling
└── README.md            # This file
```

## Configuration

### Port and Host

To run on a specific port and make it accessible:

```r
shiny::runApp("app.R", port=3838, host='0.0.0.0')
```

### Memory and Performance

For large datasets, you may need to increase R memory:

```r
options(shiny.maxRequestSize = 500*1024^2)  # 500MB
```

## Troubleshooting

### Common Issues

1. **Package not found**: Ensure EasyMultiProfiler and all dependencies are installed
2. **Memory errors**: Increase available memory or reduce dataset size
3. **Plot not displaying**: Check that analysis has been run successfully
4. **Export errors**: Ensure required packages (e.g., writexl) are installed

### Getting Help

- Check EasyMultiProfiler documentation: http://easymultiprofiler.xielab.net
- GitHub Issues: https://github.com/liubingdong/EasyMultiProfiler/issues

## Supported Omics Data Types

### 16S/Microbiome (Taxonomy)
- **Format**: CSV, TSV, BIOM, QZV
- **Features**: Taxonomic classifications (Kingdom, Phylum, Class, Order, Family, Genus, Species)
- **Common Analyses**: Alpha diversity, beta diversity, differential abundance, taxonomic composition

### RNAseq (Gene Expression)
- **Format**: CSV, TSV (tab-separated recommended)
- **Features**: Gene IDs (ENSEMBL, ENTREZ, SYMBOL, etc.)
- **Data Types**: Counts, TPM, FPKM, RPKM
- **Common Analyses**: Differential expression, enrichment, GSEA, WGCNA, pathway analysis

### Metabolomics
- **Format**: CSV, TSV
- **Features**: Metabolite IDs or names
- **Data Types**: Intensity, abundance, concentration
- **Common Analyses**: Differential abundance, correlation, network analysis, pathway enrichment

### Proteomics
- **Format**: CSV, TSV
- **Features**: Protein IDs (UniProt, gene symbols, etc.)
- **Data Types**: Intensity, abundance, spectral counts
- **Common Analyses**: Differential expression, enrichment, GSEA, pathway analysis

### Metagenomics (Functional)
- **Format**: CSV, TSV, HUMAnN format
- **Features**: KEGG Orthology (KO) or Enzyme Commission (EC) numbers
- **Data Types**: Abundance, counts
- **Common Analyses**: Functional enrichment, pathway analysis, network analysis

### Clinical Data
- **Format**: CSV, TSV
- **Features**: Any feature identifiers
- **Data Types**: Continuous or categorical measurements
- **Common Analyses**: Correlation, differential analysis, clustering, dimension reduction

## Import Troubleshooting

### Common Import Errors and Solutions

#### Error: "'x' must be numeric"
**Solution**: 
- This error is now fixed! The system automatically converts sample columns to numeric
- If you still see this error, check that your sample columns contain numeric data
- The system now handles index columns and non-numeric data automatically

#### Error with Species-Level CSV Relative Abundance Data
**Correct Settings:**
1. **File Format**: Automatically detected from file extension (no selection needed!)
2. **Start Level**: Auto-detected, but you can set to "Species" if needed
3. **Taxonomy Separator**: Auto-detected (usually ";"), but you can adjust
4. **Assay Name**: Auto-detected (relative_abundance if values 0-1, counts otherwise)
5. **Index Columns**: Automatically detected and removed
6. **Sample Columns**: Automatically detected (numeric columns)

#### Automatic Format Detection
- **File format is automatically detected** from file extension
- **.csv, .tsv, .txt** → Treated as CSV/TSV format
- **.biom** → Treated as BIOM format (QIIME1)
- **.qzv** → Treated as QZV format (QIIME2)
- No manual selection needed - just upload your file!

#### Taxonomy Separator
- The separator in the **feature column** (taxonomy hierarchy)
- Common formats:
  - `;` for "Phylum;Class;Genus;Species"
  - `|` for HUMAnN format "k__Bacteria|p__Firmicutes|g__Lactobacillus"

#### Preview Your File
- Use the "Preview File" button to check your file format before importing
- Verify the first column contains taxonomy strings
- Check that sample columns contain numeric data

## Sample Metadata Format

The metadata upload is now integrated into the Data Import page. Upload your metadata file alongside your data file:

**Required:**
- One column must contain unique sample IDs (automatically detected)
- Sample IDs should match the sample names in your data columns
- System automatically finds the sample ID column (looks for "sample", "id", "primary" in column name)

**Example:**
```
SampleID,Group,Treatment,Age,Gender
Sample1,Control,Placebo,25,Male
Sample2,Treatment,Drug,30,Female
Sample3,Control,Placebo,28,Male
```

**Auto-Features:**
- Automatically detects file separator (comma, tab, semicolon)
- Automatically finds sample ID column
- Automatically matches metadata to data samples (case-insensitive matching)
- Automatically merges metadata with imported data
- Handles missing samples (adds NA values)
- Transforms to EMP-required format automatically

## Notes

- The application uses reactive programming - data flows through the analysis pipeline
- Results are cached when possible to improve performance
- All plots can be downloaded in high-resolution formats
- Complete analysis sessions can be saved and reloaded
- Sample metadata should be added early in the workflow for best results

## License

Same as EasyMultiProfiler package (Artistic-2.0)

## Citation

If you use this web application, please cite:

- EasyMultiProfiler: An Efficient Multi-Omics Data Integration and Analysis Workflow for Microbiome Research doi: https://doi.org/10.1007/s11427-025-3035-0
