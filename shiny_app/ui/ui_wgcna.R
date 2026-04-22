# WGCNA Analysis UI

fluidPage(
  box(
    title = "WGCNA Analysis", status = "success", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Weighted Gene Co-expression Network Analysis (WGCNA)"),
    p("Identify co-expression modules and their relationships."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("wgcna_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        numericInput("wgcna_power", "Soft Threshold Power:", value = 6, min = 1, max = 20),
        numericInput("wgcna_minModuleSize", "Min Module Size:", value = 30, min = 1),
        numericInput("wgcna_mergeCutHeight", "Merge Cut Height:", value = 0.25, min = 0, max = 1),
        checkboxInput("wgcna_use_cached", "Use Cached", value = TRUE),
        actionButton("wgcna_btn", "Run WGCNA", 
          class = "btn-success", icon = icon("project-diagram"))
      ),
      column(6,
        h5("WGCNA Parameters:"),
        p("• Power: Soft thresholding power"),
        p("• Min Module Size: Minimum number of features in a module"),
        p("• Merge Cut Height: Height for merging similar modules"),
        br(),
        h5("WGCNA Output:"),
        p("• Co-expression modules"),
        p("• Module-trait relationships"),
        p("• Hub features")
      )
    ),
    
    hr(),
    
    h4("WGCNA Results"),
    DT::dataTableOutput("wgcna_results_table"),
    
    hr(),
    
    h4("WGCNA Plots"),
    plotOutput("wgcna_plot", height = "600px")
  )
)
