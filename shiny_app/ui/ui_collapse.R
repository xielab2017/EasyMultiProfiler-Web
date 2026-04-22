# Collapse UI

fluidPage(
  box(
    title = "Collapse Features", status = "primary", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Collapse Features by Taxonomy Level"),
    p("Aggregate features to a specific taxonomy level."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("collapse_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        selectInput("collapse_level", "Taxonomy Level:",
          choices = list(
            "Kingdom" = "Kingdom",
            "Phylum" = "Phylum",
            "Class" = "Class",
            "Order" = "Order",
            "Family" = "Family",
            "Genus" = "Genus",
            "Species" = "Species"
          ),
          selected = "Genus"
        ),
        selectInput("collapse_method", "Aggregation Method:",
          choices = list(
            "Sum" = "sum",
            "Mean" = "mean",
            "Median" = "median"
          ),
          selected = "sum"
        ),
        checkboxInput("collapse_use_cached", "Use Cached", value = TRUE),
        actionButton("collapse_btn", "Collapse Features", 
          class = "btn-primary", icon = icon("compress"))
      ),
      column(6,
        h5("Collapse Options:"),
        p("• Level: Target taxonomy level for aggregation"),
        p("• Method: How to combine features at the same level"),
        p("• Sum: Add all counts (default for count data)"),
        p("• Mean: Average values"),
        p("• Median: Median values")
      )
    ),
    
    hr(),
    
    h4("Collapse Status"),
    verbatimTextOutput("collapse_status")
  )
)
