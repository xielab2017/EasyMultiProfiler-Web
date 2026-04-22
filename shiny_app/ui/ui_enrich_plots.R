# Enrichment Plots UI

fluidPage(
  box(
    title = "Enrichment Plots", status = "warning", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Enrichment Visualization"),
    p("Visualize enrichment analysis results."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("enrich_plots_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        selectInput("enrich_plots_type", "Plot Type:",
          choices = list(
            "Dotplot" = "dotplot",
            "Network Plot" = "netplot",
            "Curve Plot" = "curveplot"
          ),
          selected = "dotplot"
        ),
        numericInput("enrich_plots_topN", "Top N Terms:", value = 20, min = 1),
        numericInput("enrich_plots_width", "Plot Width (px):", value = 800, min = 400),
        numericInput("enrich_plots_height", "Plot Height (px):", value = 600, min = 400),
        actionButton("enrich_plots_btn", "Generate Enrichment Plot", 
          class = "btn-warning", icon = icon("chart-pie"))
      ),
      column(6,
        h5("Enrichment Plot Types:"),
        p("• Dotplot: Dot plot of enriched terms"),
        p("• Network Plot: Network visualization"),
        p("• Curve Plot: Enrichment score curves")
      )
    ),
    
    hr(),
    
    h4("Enrichment Plot"),
    plotOutput("enrich_plots_output", height = "600px"),
    
    hr(),
    
    downloadButton("enrich_plots_download", "Download Plot", class = "btn-primary")
  )
)
