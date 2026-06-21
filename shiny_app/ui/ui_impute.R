# Imputation UI

fluidPage(
  box(
    title = "Missing Value Imputation", status = "primary", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Impute Missing Values"),
    p("Fill missing values in your data using various imputation methods."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("impute_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        selectInput("impute_method", "Imputation Method:",
          choices = list(
            "KNN" = "knn",
            "Random Forest" = "rf",
            "Mean" = "mean",
            "Median" = "median",
            "Zero" = "zero"
          ),
          selected = "knn"
        ),
        checkboxInput("impute_use_cached", "Use Cached", value = TRUE),
        actionButton("impute_btn", "Impute Missing Values", 
          class = "btn-primary", icon = icon("magic"))
      ),
      column(6,
        h5("Imputation Methods:"),
        p("• KNN: K-nearest neighbors imputation"),
        p("• Random Forest: Random forest-based imputation"),
        p("• Mean: Replace with column mean"),
        p("• Median: Replace with column median"),
        p("• Zero: Replace with zero")
      )
    ),
    
    hr(),
    
    h4("Imputation Status"),
    verbatimTextOutput("impute_status")
  )
)
