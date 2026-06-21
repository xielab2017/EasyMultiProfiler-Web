# Multi Analysis UI

fluidPage(
  box(
    title = "Multi-omics Integration Analysis", status = "success", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Multi-omics Integration Analysis"),
    p("Integrate and analyze multiple omics datasets together."),
    
    hr(),
    
    fluidRow(
      column(6,
        checkboxGroupInput("multi_experiments", "Select Experiments:",
          choices = NULL,
          width = "100%"
        ),
        selectInput("multi_method", "Integration Method:",
          choices = list(
            "Feature-based" = "feature",
            "Sample-based" = "sample"
          ),
          selected = "feature"
        ),
        selectInput("multi_combineFun", "Combine Function:",
          choices = list(
            "Enricher" = "enricher",
            "GSEA" = "gsea"
          ),
          selected = "enricher"
        ),
        actionButton("multi_btn", "Run Multi-omics Analysis", 
          class = "btn-success", icon = icon("layer-group"))
      ),
      column(6,
        h5("Multi-omics Analysis:"),
        p("Integrate multiple omics datasets to identify common patterns and pathways.")
      )
    ),
    
    hr(),
    
    h4("Multi-omics Results"),
    DT::dataTableOutput("multi_results_table"),
    
    hr(),
    
    h4("Multi-omics Plot"),
    plotOutput("multi_plot", height = "600px")
  )
)
