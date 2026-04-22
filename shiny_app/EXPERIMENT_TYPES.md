# Experiment Type-Based Interface

The Shiny app now dynamically shows/hides analysis and visualization options based on the detected experiment type.

## Experiment Types

1. **16S/Metagenomics (microbiome)**
   - Detected by: taxonomy columns in rowData, experiment name containing "taxonomy", "16s", "microbiome"
   - **Available Analyses:**
     - Alpha Diversity ✓
     - Correlation ✓
     - Differential ✓
     - Dimension Reduction ✓
     - Cluster ✓
     - Marker ✓
     - Network ✓
     - Multi Analysis ✓
   - **Available Visualizations:**
     - Barplot ✓
     - Boxplot ✓
     - Heatmap ✓
     - Scatterplot ✓
     - Sankey Plot ✓ (microbiome-specific)
     - Structure Plot ✓ (microbiome-specific)
     - Network Plot ✓
   - **Available Preparation:**
     - Filter ✓
     - Normalize ✓
     - Impute ✓
     - Rarefy ✓ (microbiome-specific)
     - Collapse ✓ (microbiome-specific)
     - Feature Convert ✓

2. **RNAseq (rnaseq)**
   - Detected by: experiment name containing "rna", "gene", "transcript", gene-like IDs (ENSG, numeric)
   - **Available Analyses:**
     - Correlation ✓
     - Differential ✓
     - Dimension Reduction ✓
     - Cluster ✓
     - Marker ✓
     - Enrichment ✓
     - GSEA ✓
     - WGCNA ✓
     - Network ✓
     - Multi Analysis ✓
   - **Available Visualizations:**
     - Barplot ✓
     - Boxplot ✓
     - Heatmap ✓
     - Volcano Plot ✓
     - Scatterplot ✓
     - Enrichment Plots ✓
     - Network Plot ✓
   - **Available Preparation:**
     - Filter ✓
     - Normalize ✓
     - Impute ✓
     - Feature Convert ✓

3. **Proteomics (proteomics)**
   - Detected by: experiment name containing "protein", "proteom"
   - **Available Analyses:**
     - Correlation ✓
     - Differential ✓
     - Dimension Reduction ✓
     - Cluster ✓
     - Marker ✓
     - Enrichment ✓
     - GSEA ✓
     - WGCNA ✓
     - Network ✓
     - Multi Analysis ✓
   - **Available Visualizations:**
     - Barplot ✓
     - Boxplot ✓
     - Heatmap ✓
     - Volcano Plot ✓
     - Scatterplot ✓
     - Enrichment Plots ✓
     - Network Plot ✓
   - **Available Preparation:**
     - Filter ✓
     - Normalize ✓
     - Impute ✓
     - Feature Convert ✓

4. **Metabolomics (metabolomics)**
   - Detected by: experiment name containing "metabolit", "metabolom", or <1000 features
   - **Available Analyses:**
     - Correlation ✓
     - Differential ✓
     - Dimension Reduction ✓
     - Cluster ✓
     - Marker ✓
     - WGCNA ✓
     - Network ✓
     - Multi Analysis ✓
   - **Available Visualizations:**
     - Barplot ✓
     - Boxplot ✓
     - Heatmap ✓
     - Volcano Plot ✓
     - Scatterplot ✓
     - Network Plot ✓
   - **Available Preparation:**
     - Filter ✓
     - Normalize ✓
     - Impute ✓
     - Feature Convert ✓

5. **Functional Metagenomics (functional)**
   - Detected by: KO/EC annotations, experiment name containing "ko", "ec", "function", "pathway"
   - **Available Analyses:**
     - Correlation ✓
     - Differential ✓
     - Dimension Reduction ✓
     - Cluster ✓
     - Marker ✓
     - Enrichment ✓
     - GSEA ✓
     - Network ✓
     - Multi Analysis ✓
   - **Available Visualizations:**
     - Barplot ✓
     - Boxplot ✓
     - Heatmap ✓
     - Scatterplot ✓
     - Enrichment Plots ✓
     - Network Plot ✓
   - **Available Preparation:**
     - Filter ✓
     - Normalize ✓
     - Impute ✓
     - Feature Convert ✓

6. **Clinical Data (clinical)**
   - Detected by: experiment name containing "clinical", "phenotype", "metadata", or default
   - **Available Analyses:**
     - Correlation ✓
     - Differential ✓
     - Dimension Reduction ✓
     - Cluster ✓
     - Marker ✓
     - Network ✓
     - Multi Analysis ✓
   - **Available Visualizations:**
     - Barplot ✓
     - Boxplot ✓
     - Heatmap ✓
     - Scatterplot ✓
     - Network Plot ✓
   - **Available Preparation:**
     - Filter ✓
     - Normalize ✓
     - Impute ✓
     - Feature Convert ✓

## How It Works

1. **Automatic Detection**: When data is imported, the system automatically detects the experiment type based on:
   - RowData column names (taxonomy columns, KO/EC annotations)
   - Experiment name patterns
   - Feature ID patterns
   - Number of features

2. **Dynamic Menu**: The sidebar menu automatically shows/hides options based on the currently selected experiment:
   - Menu items are hidden by default using CSS classes
   - When an experiment is selected, the appropriate CSS class is added to the body
   - CSS rules then show the relevant menu items

3. **Experiment Type Badge**: The Data Summary page shows a badge indicating the detected experiment type

4. **Current Experiment Tracking**: The system tracks which experiment is currently selected across all modules, ensuring menu visibility stays synchronized

## Implementation Details

- **Detection Function**: `detect_experiment_type()` in `server_experiment_type.R`
- **Menu Classes**: CSS classes applied to menu items:
  - `menu-microbiome-only`: Only for 16S/metagenomics
  - `menu-rnaseq-proteomics-functional`: For RNAseq, Proteomics, Functional
  - `menu-rnaseq-proteomics-metabolomics`: For RNAseq, Proteomics, Metabolomics
- **Body Classes**: CSS classes added to `<body>`:
  - `show-microbiome`, `show-rnaseq`, `show-proteomics`, `show-metabolomics`, `show-functional`, `show-clinical`
