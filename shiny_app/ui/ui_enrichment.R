# Enrichment Analysis UI

fluidPage(
  box(
    title = "Functional Enrichment Analysis", status = "success", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Functional Enrichment Analysis"),
    p("Perform enrichment analysis on differentially expressed genes from differential analysis results."),
    
    hr(),
    
    fluidRow(
      column(6,
        uiOutput("enrichment_experiment_info"),
        uiOutput("enrichment_diff_warning"),
        selectInput("enrichment_method", "Enrichment Method:",
          choices = list(
            "GO" = "go",
            "KEGG" = "kegg",
            "Reactome" = "reactome",
            "DOSE" = "do"
          ),
          selected = "go"
        ),
        conditionalPanel(
          condition = "input.enrichment_method == 'go'",
          selectInput("enrichment_ontology", "GO Ontology:",
            choices = list(
              "Biological Process (BP)" = "BP",
              "Cellular Component (CC)" = "CC",
              "Molecular Function (MF)" = "MF",
              "ALL" = "ALL"
            ),
            selected = "BP"
          )
        ),
        selectInput("enrichment_organism", "Organism:",
          choices = list(
            "Human" = "human",
            "Mouse" = "mouse",
            "Rat" = "rat"
          ),
          selected = "human"
        ),
        hr(),
        h4("Filter Differentially Expressed Genes"),
        selectInput("enrichment_direction", "Gene Direction:",
          choices = list(
            "All DEGs" = "all",
            "Upregulated only" = "up",
            "Downregulated only" = "down"
          ),
          selected = "all"
        ),
        selectInput("enrichment_pvalue_type", "P-value Type:",
          choices = list(
            "P-value" = "pvalue",
            "Adjusted P-value (FDR)" = "fdr"
          ),
          selected = "fdr"
        ),
        numericInput("enrichment_pvalue_threshold", "P-value Threshold:", 
          value = 0.05, min = 0, max = 1, step = 0.01),
        numericInput("enrichment_fc_threshold", "Fold Change Threshold:", 
          value = 1.5, min = 0, step = 0.1),
        uiOutput("enrichment_group_filter"),
        hr(),
        numericInput("enrichment_minGSSize", "Min Gene Set Size:", value = 10, min = 1),
        numericInput("enrichment_maxGSSize", "Max Gene Set Size:", value = 500, min = 1),
        numericInput("enrichment_qvalue", "Q-value Cutoff:", value = 0.2, min = 0, max = 1),
        checkboxInput("enrichment_use_cached", "Use Cached", value = TRUE),
        actionButton("enrichment_btn", "Run Enrichment Analysis", 
          class = "btn-success", icon = icon("search-plus"))
      ),
      column(6,
        h5("Enrichment Methods:"),
        p("• GO: Gene Ontology enrichment"),
        p("• KEGG: KEGG pathway enrichment"),
        p("• Reactome: Reactome pathway enrichment"),
        p("• DOSE: Disease Ontology Semantic Enrichment"),
        br(),
        h5("Requirements:"),
        p("• Requires differential analysis results from the selected experiment"),
        p("• Genes will be filtered by significance and fold change"),
        p("• Can filter by up/downregulated genes"),
        br(),
        h5("Organism Support:"),
        p("• Human: org.Hs.eg.db"),
        p("• Mouse: org.Mm.eg.db"),
        p("• Rat: org.Rn.eg.db")
      )
    ),
    
    hr(),
    
    h4("Enrichment Results"),
    DT::dataTableOutput("enrichment_results_table"),
    
    hr(),
    
    h4("Enrichment Dotplot"),
    plotOutput("enrichment_dotplot", height = "600px")
  )
)
