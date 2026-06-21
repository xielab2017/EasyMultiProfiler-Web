# Sankey Plot UI

fluidPage(
  box(
    title = "Sankey Plot", status = "warning", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Sankey Diagram"),
    p("Create Sankey diagrams for flow visualization."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("sankey_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        selectInput("sankey_from", "From Level:",
          choices = list(
            "Phylum" = "Phylum",
            "Class" = "Class",
            "Order" = "Order",
            "Family" = "Family",
            "Genus" = "Genus"
          )
        ),
        selectInput("sankey_to", "To Level:",
          choices = list(
            "Class" = "Class",
            "Order" = "Order",
            "Family" = "Family",
            "Genus" = "Genus",
            "Species" = "Species"
          )
        ),
        actionButton("sankey_btn", "Generate Sankey Plot", 
          class = "btn-warning", icon = icon("stream"))
      ),
      column(6,
        h5("Sankey Plot:"),
        p("Visualize flow between taxonomy levels or groups.")
      )
    ),
    
    hr(),
    
    h4("Sankey Plot"),
    plotOutput("sankey_output", height = "600px"),
    
    hr(),
    
    downloadButton("sankey_download", "Download Plot", class = "btn-primary")
  )
)
