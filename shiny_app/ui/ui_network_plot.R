# Network Plot UI

fluidPage(
  box(
    title = "Network Plot", status = "warning", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Network Visualization"),
    p("Visualize feature interaction networks."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("network_plot_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        numericInput("network_plot_threshold", "Correlation Threshold:", value = 0.7, min = 0, max = 1),
        numericInput("network_plot_topN", "Top N Features:", value = 50, min = 1),
        numericInput("network_plot_width", "Plot Width (px):", value = 1000, min = 400),
        numericInput("network_plot_height", "Plot Height (px):", value = 800, min = 400),
        actionButton("network_plot_btn", "Generate Network Plot", 
          class = "btn-warning", icon = icon("project-diagram"))
      ),
      column(6,
        h5("Network Plot:"),
        p("Visualize feature correlation networks.")
      )
    ),
    
    hr(),
    
    h4("Network Plot"),
    plotOutput("network_plot_output", height = "800px"),
    
    hr(),
    
    downloadButton("network_plot_download", "Download Plot", class = "btn-primary")
  )
)
