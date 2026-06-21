# Workflow registry for omics-specific pipeline planning.
# This file defines the canonical pipeline map used by web UI and API.

get_workflow_registry <- function() {
  list(
    transcriptomics = list(
      label = "Transcriptomics",
      description = "RNAseq gene expression pipeline from import to pathway interpretation.",
      stages = list(
        list(id = "import", name = "Import", steps = c("Load count/TPM matrix", "Attach sample metadata")),
        list(id = "preparation", name = "Preparation", steps = c("Filter low-expression features", "Normalize and impute if needed")),
        list(id = "analysis", name = "Analysis", steps = c("Differential analysis", "Dimension reduction", "Correlation/cluster")),
        list(id = "advanced", name = "Advanced", steps = c("GSEA", "WGCNA")),
        list(id = "visualization", name = "Visualization", steps = c("Volcano/heatmap/scatter", "Enrichment visual summaries")),
        list(id = "export", name = "Export", steps = c("Result tables", "Session RDS"))
      )
    ),
    microbiome_16s = list(
      label = "Microbiome 16S",
      description = "16S taxonomy workflow with diversity, composition, and differential abundance.",
      stages = list(
        list(id = "import", name = "Import", steps = c("Load taxonomy abundance table", "Attach metadata")),
        list(id = "preparation", name = "Preparation", steps = c("Rarefy/collapse taxonomy", "Normalize compositional signals")),
        list(id = "analysis", name = "Analysis", steps = c("Alpha diversity", "Differential abundance", "Network/correlation")),
        list(id = "advanced", name = "Advanced", steps = c("Marker analysis", "Multi-omics bridge")),
        list(id = "visualization", name = "Visualization", steps = c("Structure/bar/box", "Sankey and network plots")),
        list(id = "export", name = "Export", steps = c("Abundance and metadata exports", "Session RDS"))
      )
    ),
    metagenomics = list(
      label = "Metagenomics",
      description = "Functional metagenomics pipeline for pathway and module-level interpretation.",
      stages = list(
        list(id = "import", name = "Import", steps = c("Load functional matrix (KO/EC/pathway)", "Attach metadata")),
        list(id = "preparation", name = "Preparation", steps = c("Feature filtering", "Normalization")),
        list(id = "analysis", name = "Analysis", steps = c("Differential analysis", "Enrichment/GSEA")),
        list(id = "advanced", name = "Advanced", steps = c("Network analysis", "Cross-omics integration")),
        list(id = "visualization", name = "Visualization", steps = c("Heatmap/volcano", "Enrichment plots")),
        list(id = "export", name = "Export", steps = c("Functional result tables", "Session RDS"))
      )
    ),
    metabolomics = list(
      label = "Metabolomics",
      description = "Metabolite-level abundance pipeline from preprocessing to biological interpretation.",
      stages = list(
        list(id = "import", name = "Import", steps = c("Load metabolite abundance matrix", "Attach metadata")),
        list(id = "preparation", name = "Preparation", steps = c("Missing value imputation", "Normalization and filtering")),
        list(id = "analysis", name = "Analysis", steps = c("Differential analysis", "Dimension/correlation/cluster")),
        list(id = "advanced", name = "Advanced", steps = c("Pathway enrichment", "Network and module analysis")),
        list(id = "visualization", name = "Visualization", steps = c("Box/heatmap/scatter", "Volcano and pathway views")),
        list(id = "export", name = "Export", steps = c("Analysis outputs", "Session RDS"))
      )
    ),
    chipseq = list(
      label = "ChIP-seq",
      description = "BAM-level chromatin profiling workflow: MACS2/3 peak calling, ChIPseeker annotation, and cross-omics integration.",
      stages = list(
        list(id = "import", name = "Import", steps = c("Register treatment/control BAM paths", "Choose genome build and QC strategy")),
        list(id = "analysis", name = "Analysis", steps = c("MACS2/3 peak calling", "Peak QC and summit inspection")),
        list(id = "advanced", name = "Advanced", steps = c("ChIPseeker peak annotation", "Motif/enrichment and regulator hypothesis")),
        list(id = "integration", name = "Integration", steps = c("Peak-to-gene linkage", "Cross analysis with RNAseq / proteomics differential results")),
        list(id = "export", name = "Export", steps = c("narrowPeak/broadPeak/annotation tables", "Session artifacts and overlap gene sets"))
      )
    )
  )
}

list_workflows <- function() {
  reg <- get_workflow_registry()
  keys <- names(reg)
  lapply(keys, function(k) {
    w <- reg[[k]]
    list(
      id = k,
      label = w$label,
      description = w$description,
      n_stages = length(w$stages)
    )
  })
}

get_workflow <- function(workflow_id) {
  reg <- get_workflow_registry()
  if (is.null(reg[[workflow_id]])) {
    stop(paste("Unknown workflow:", workflow_id))
  }
  w <- reg[[workflow_id]]
  list(
    id = workflow_id,
    label = w$label,
    description = w$description,
    stages = w$stages
  )
}
