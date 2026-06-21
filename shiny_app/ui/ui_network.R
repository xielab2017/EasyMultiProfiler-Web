# Network Analysis UI

fluidPage(
  box(
    title = "Network Analysis", status = "success", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Network Analysis"),
    p("Analyze feature interaction networks."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("network_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        selectInput("network_method", "Network Method:",
          choices = list(
            "Correlation" = "correlation",
            "Co-occurrence" = "cooccurrence"
          ),
          selected = "correlation"
        ),
        numericInput("network_threshold", "Correlation Threshold:", value = 0.7, min = 0, max = 1),
        checkboxInput("network_use_cached", "Use Cached", value = TRUE),
        actionButton("network_btn", "Run Network Analysis", 
          class = "btn-success", icon = icon("network-wired"))
      ),
      column(6,
        h5("Network Analysis:"),
        p("Build and analyze feature interaction networks based on correlations or co-occurrence patterns.")
      )
    ),
    
    hr(),
    
    h4("Network Plot"),
    plotOutput("network_plot", height = "600px")
  )
)
