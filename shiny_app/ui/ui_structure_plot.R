# Structure Plot UI

fluidPage(
  box(
    title = "Structure Plot", status = "warning", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Structure Plot"),
    p("Visualize data structure and composition."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("structure_plot_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        selectInput("structure_plot_level", "Taxonomy Level:",
          choices = list(
            "Phylum" = "Phylum",
            "Class" = "Class",
            "Order" = "Order",
            "Family" = "Family",
            "Genus" = "Genus"
          ),
          selected = "Genus"
        ),
        numericInput("structure_plot_width", "Plot Width (px):", value = 1000, min = 400),
        numericInput("structure_plot_height", "Plot Height (px):", value = 600, min = 400),
        actionButton("structure_plot_btn", "Generate Structure Plot", 
          class = "btn-warning", icon = icon("layer-group"))
      ),
      column(6,
        h5("Structure Plot:"),
        p("Visualize composition and structure of your data.")
      )
    ),
    
    hr(),
    
    h4("Structure Plot"),
    plotOutput("structure_plot_output", height = "600px"),
    
    hr(),
    
    downloadButton("structure_plot_download", "Download Plot", class = "btn-primary")
  )
)
