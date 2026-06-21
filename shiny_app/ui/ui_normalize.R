# Normalization UI

fluidPage(
  box(
    title = "Data Normalization", status = "primary", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Normalize Data"),
    p("Standardize and transform your data using various normalization methods."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("normalize_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        selectInput("normalize_method", "Normalization Method:",
          choices = list(
            "Total" = "total",
            "Max" = "max",
            "Frequency" = "freq",
            "Normalize" = "normalize",
            "Range" = "range",
            "Standardize" = "standardize",
            "Paired" = "pa",
            "Chi Square" = "chi.square",
            "Hellinger" = "hellinger",
            "Log" = "log",
            "Log2" = "log2",
            "Log10" = "log10"
          ),
          selected = "total"
        ),
        selectInput("normalize_bySample", "By Sample:",
          choices = list(
            "Default" = "default",
            "Yes" = TRUE,
            "No" = FALSE
          ),
          selected = "default"
        ),
        numericInput("normalize_logbase", "Log Base:", value = 2, min = 1),
        numericInput("normalize_pseudocount", "Pseudo Count:", value = 0.0000001, min = 0),
        checkboxInput("normalize_use_cached", "Use Cached", value = TRUE),
        actionButton("normalize_btn", "Normalize Data", 
          class = "btn-primary", icon = icon("cog"))
      ),
      column(6,
        h5("Normalization Methods:"),
        p("• Total: Divide by column totals"),
        p("• Max: Divide by column maximum"),
        p("• Frequency: Frequency transformation"),
        p("• Standardize: Z-score normalization"),
        p("• Hellinger: Hellinger transformation"),
        p("• Log: Logarithmic transformation"),
        br(),
        h5("Note:"),
        p("Normalization is applied to the selected experiment and stored in the EMP object.")
      )
    ),
    
    hr(),
    
    h4("Normalization Status"),
    verbatimTextOutput("normalize_status")
  )
)
