# Cluster Analysis UI

fluidPage(
  box(
    title = "Cluster Analysis", status = "success", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Cluster Analysis"),
    p("Perform clustering analysis on samples or features."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("cluster_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        selectInput("cluster_method", "Agglomeration Method (for Hierarchical):",
          choices = list(
            "Average (UPGMA)" = "average",
            "Complete" = "complete",
            "Single" = "single",
            "Ward.D" = "ward.D",
            "Ward.D2" = "ward.D2",
            "McQuitty (WPGMA)" = "mcquitty",
            "Median (WPGMC)" = "median",
            "Centroid (UPGMC)" = "centroid"
          ),
          selected = "average"
        ),
        numericInput("cluster_k", "Number of Clusters:", value = 3, min = 2),
        checkboxInput("cluster_use_cached", "Use Cached", value = TRUE),
        actionButton("cluster_btn", "Run Cluster Analysis", 
          class = "btn-success", icon = icon("sitemap"))
      ),
      column(6,
        h5("Clustering Methods:"),
        p("• Hierarchical: Hierarchical clustering"),
        p("• K-means: K-means clustering"),
        p("• PAM: Partitioning Around Medoids")
      )
    ),
    
    hr(),
    
    h4("Cluster Plot"),
    plotOutput("cluster_plot", height = "600px")
  )
)
