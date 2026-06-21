# GSEA Analysis UI

fluidPage(
  box(
    title = "GSEA Analysis", status = "success", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Gene Set Enrichment Analysis (GSEA)"),
    p("Perform GSEA to identify enriched gene sets in ranked gene lists."),
    
    hr(),
    
    fluidRow(
      column(6,
        uiOutput("gsea_experiment_info"),
        uiOutput("gsea_diff_warning"),
        selectInput("gsea_method", "GSEA Method:",
          choices = list(
            "GSEA" = "gsea",
            "FGSEA" = "fgsea"
          ),
          selected = "gsea"
        ),
        selectInput("gsea_organism", "Organism:",
          choices = list(
            "Human" = "human",
            "Mouse" = "mouse",
            "Rat" = "rat"
          ),
          selected = "human"
        ),
        numericInput("gsea_pvalue", "P-value Threshold:", value = 0.05, min = 0, max = 1),
        checkboxInput("gsea_use_cached", "Use Cached", value = TRUE),
        actionButton("gsea_btn", "Run GSEA", 
          class = "btn-success", icon = icon("chart-line"))
      ),
      column(6,
        h5("GSEA Analysis:"),
        p("GSEA identifies gene sets that are enriched at the top or bottom of a ranked gene list."),
        p("This is useful for identifying coordinated changes in gene expression.")
      )
    ),
    
    hr(),
    
    h4("GSEA Results"),
    DT::dataTableOutput("gsea_results_table"),
    
    hr(),
    
    h4("GSEA Plot"),
    plotOutput("gsea_plot", height = "600px")
  )
)
