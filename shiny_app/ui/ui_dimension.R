# Dimension Reduction UI

fluidPage(
  box(
    title = "Dimension Reduction", status = "success", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Dimension Reduction Analysis"),
    p("Reduce dimensionality of your data using PCA, t-SNE, UMAP, etc."),
    
    hr(),
    
    fluidRow(
      column(6,
        uiOutput("dimension_experiment_info"),
        selectInput("dimension_method", "Method:",
          choices = list(
            "PCA" = "pca",
            "t-SNE" = "tsne",
            "UMAP" = "umap",
            "MDS" = "mds",
            "PCOA" = "pcoa"
          ),
          selected = "pca"
        ),
        selectInput("dimension_group", "Group Variable (for coloring):",
          choices = NULL,
          width = "100%"
        ),
        numericInput("dimension_ncomp", "Number of Components:", value = 2, min = 2, max = 10),
        checkboxInput("dimension_use_cached", "Use Cached", value = TRUE),
        actionButton("dimension_btn", "Run Dimension Reduction", 
          class = "btn-success", icon = icon("compress-arrows-alt"))
      ),
      column(6,
        h5("Dimension Reduction Methods:"),
        p("• PCA: Principal Component Analysis"),
        p("• t-SNE: t-Distributed Stochastic Neighbor Embedding"),
        p("• UMAP: Uniform Manifold Approximation and Projection"),
        p("• MDS: Multidimensional Scaling")
      )
    ),
    
    hr(),
    
    h4("Dimension Reduction Plot"),
    plotOutput("dimension_plot", height = "600px")
  )
)
