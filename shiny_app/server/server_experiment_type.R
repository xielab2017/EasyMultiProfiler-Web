# Experiment Type Detection and Management

# Helper function to detect experiment type
detect_experiment_type <- function(mae_obj, experiment_name) {
  if (is.null(mae_obj) || is.null(experiment_name)) {
    return("unknown")
  }
  
  if (!experiment_name %in% names(mae_obj)) {
    return("unknown")
  }
  
  # Get the experiment
  exp_obj <- mae_obj[[experiment_name]]
  
  # Check rowData for taxonomy information (16S/metagenomics)
  row_data <- SummarizedExperiment::rowData(exp_obj)
  if (ncol(row_data) > 0) {
    row_cols <- tolower(colnames(row_data))
    # Check for taxonomy columns
    tax_cols <- c("kindom", "kingdom", "phylum", "class", "order", "family", "genus", "species", "strain")
    if (any(tax_cols %in% row_cols)) {
      return("microbiome")  # 16S/Metagenomics
    }
    
    # Check for functional annotation (KO, EC)
    if (any(grepl("ko|ec|kegg|pathway", row_cols))) {
      return("functional")  # Functional metagenomics
    }
  }
  
  # Check assay name
  assay_names <- names(SummarizedExperiment::assays(exp_obj))
  if (length(assay_names) > 0) {
    assay_lower <- tolower(assay_names[1])
    if (grepl("relative|abundance|counts", assay_lower)) {
      # Could be microbiome or other
      if (any(tax_cols %in% row_cols)) {
        return("microbiome")
      }
    }
  }
  
  # Check experiment name for hints
  exp_lower <- tolower(experiment_name)
  if (grepl("taxonomy|16s|microbiome|metagenom", exp_lower)) {
    return("microbiome")
  } else if (grepl("rna|gene|transcript|expression", exp_lower)) {
    return("rnaseq")
  } else if (grepl("protein|proteom", exp_lower)) {
    return("proteomics")
  } else if (grepl("metabolit|metabolom", exp_lower)) {
    return("metabolomics")
  } else if (grepl("clinical|phenotype|metadata", exp_lower)) {
    return("clinical")
  } else if (grepl("ko|ec|function|pathway", exp_lower)) {
    return("functional")
  }
  
  # Check feature names (row names)
  feature_names <- rownames(exp_obj)
  if (length(feature_names) > 0) {
    # Check if features look like gene IDs
    sample_features <- head(feature_names, min(100, length(feature_names)))
    if (any(grepl("^ENS[GTP]|^[0-9]+$|^[A-Z]{2,}[0-9]+", sample_features))) {
      return("rnaseq")  # Likely gene IDs
    }
    # Check if features look like taxonomy
    if (any(grepl("k__|p__|c__|o__|f__|g__|s__", sample_features))) {
      return("microbiome")
    }
  }
  
  # Default: assume it's general omics data (could be metabolomics or clinical)
  # Check number of features - metabolomics typically has fewer features than RNAseq
  n_features <- nrow(exp_obj)
  if (n_features < 1000) {
    return("metabolomics")  # Likely metabolomics
  }
  
  return("clinical")  # Default to clinical/general
}

# Get available analyses for experiment type
get_available_analyses <- function(exp_type) {
  analyses <- list()
  
  # Common analyses for all types
  common <- c("correlation", "differential", "dimension", "cluster", "marker", "network")
  
  switch(exp_type,
    "microbiome" = {
      analyses$preparation <- c("filter", "normalize", "impute", "rarefy", "collapse", "feature_convert")
      analyses$analysis <- c("alpha", common, "multi_analysis")
      analyses$visualization <- c("barplot", "boxplot", "heatmap", "scatterplot", "sankey", "structure_plot", "network_plot")
    },
    "rnaseq" = {
      analyses$preparation <- c("filter", "normalize", "impute", "feature_convert")
      analyses$analysis <- c(common, "enrichment", "gsea", "wgcna", "multi_analysis")
      analyses$visualization <- c("barplot", "boxplot", "heatmap", "volcano", "scatterplot", "enrich_plots", "network_plot")
    },
    "proteomics" = {
      analyses$preparation <- c("filter", "normalize", "impute", "feature_convert")
      analyses$analysis <- c(common, "enrichment", "gsea", "wgcna", "multi_analysis")
      analyses$visualization <- c("barplot", "boxplot", "heatmap", "volcano", "scatterplot", "enrich_plots", "network_plot")
    },
    "metabolomics" = {
      analyses$preparation <- c("filter", "normalize", "impute", "feature_convert")
      analyses$analysis <- c(common, "wgcna", "multi_analysis")
      analyses$visualization <- c("barplot", "boxplot", "heatmap", "volcano", "scatterplot", "network_plot")
    },
    "functional" = {
      analyses$preparation <- c("filter", "normalize", "impute", "feature_convert")
      analyses$analysis <- c(common, "enrichment", "gsea", "multi_analysis")
      analyses$visualization <- c("barplot", "boxplot", "heatmap", "scatterplot", "enrich_plots", "network_plot")
    },
    "clinical" = {
      analyses$preparation <- c("filter", "normalize", "impute", "feature_convert")
      analyses$analysis <- c(common, "multi_analysis")
      analyses$visualization <- c("barplot", "boxplot", "heatmap", "scatterplot", "network_plot")
    },
    {
      # Default: show all
      analyses$preparation <- c("filter", "normalize", "impute", "rarefy", "collapse", "feature_convert")
      analyses$analysis <- c("alpha", common, "enrichment", "gsea", "wgcna", "multi_analysis")
      analyses$visualization <- c("barplot", "boxplot", "heatmap", "volcano", "scatterplot", "sankey", "network_plot", "enrich_plots", "structure_plot")
    }
  )
  
  return(analyses)
}

# Update experiment type when data is imported or experiment is selected
update_experiment_type <- function(session, mae_obj, experiment_name) {
  if (is.null(mae_obj) || is.null(experiment_name)) {
    return(NULL)
  }
  
  exp_type <- detect_experiment_type(mae_obj, experiment_name)
  
  # Store in session
  session$userData$experiment_types <- session$userData$experiment_types %||% list()
  session$userData$experiment_types[[experiment_name]] <- exp_type
  
  return(exp_type)
}

# Get experiment type for current experiment
get_current_experiment_type <- function(session, experiment_name) {
  if (is.null(session$userData$experiment_types)) {
    return("unknown")
  }
  return(session$userData$experiment_types[[experiment_name]] %||% "unknown")
}
