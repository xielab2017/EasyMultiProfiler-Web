# Scatterplot UI

fluidPage(
  box(
    title = "Scatterplot / Dimension Reduction Plot", status = "warning", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Scatterplot Visualization"),
    p("Create scatterplots for dimension reduction results (PCA, t-SNE, UMAP)."),
    
    hr(),
    
    fluidRow(
      column(6,
        uiOutput("scatterplot_experiment_info"),
        uiOutput("scatterplot_dimension_warning"),
        selectInput("scatterplot_method", "Dimension Reduction Method:",
          choices = list(
            "PCA" = "pca",
            "t-SNE" = "tsne",
            "UMAP" = "umap"
          ),
          selected = "pca"
        ),
        selectInput("scatterplot_group", "Color by Group:",
          choices = NULL,
          width = "100%"
        ),
        numericInput("scatterplot_width", "Plot Width (px):", value = 800, min = 400),
        numericInput("scatterplot_height", "Plot Height (px):", value = 600, min = 400),
        actionButton("scatterplot_btn", "Generate Scatterplot", 
          class = "btn-warning", icon = icon("braille"))
      ),
      column(6,
        h5("Scatterplot Options:"),
        p("• Method: Dimension reduction method"),
        p("• Color by Group: Color points by group variable")
      )
    ),
    
    hr(),
    
    h4("Scatterplot"),
    plotOutput("scatterplot_output", height = "600px"),
    
    hr(),
    
    downloadButton("scatterplot_download", "Download Plot", class = "btn-primary")
  )
)
