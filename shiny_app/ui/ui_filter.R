# Filter UI

fluidPage(
  box(
    title = "Data Filtering", status = "primary", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Filter Data"),
    p("Filter samples and features based on various criteria."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("filter_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        h4("Sample Filtering"),
        textInput("filter_sample_condition", "Sample Condition (R expression):", 
          placeholder = "e.g., group == 'Control'"),
        h4("Feature Filtering"),
        numericInput("filter_min_count", "Minimum Count:", value = 0, min = 0),
        numericInput("filter_min_samples", "Minimum Samples:", value = 0, min = 0),
        numericInput("filter_max_na", "Maximum NA Proportion:", value = 1, min = 0, max = 1, step = 0.1),
        actionButton("filter_btn", "Apply Filter", 
          class = "btn-primary", icon = icon("filter"))
      ),
      column(6,
        h5("Filtering Options:"),
        p("• Sample Condition: R expression to filter samples"),
        p("• Minimum Count: Remove features with counts below threshold"),
        p("• Minimum Samples: Remove features present in fewer samples"),
        p("• Maximum NA: Remove features with high missing values"),
        br(),
        h5("Example Conditions:"),
        p("• group == 'Control'"),
        p("• age > 30"),
        p("• treatment %in% c('A', 'B')")
      )
    ),
    
    hr(),
    
    h4("Filter Status"),
    verbatimTextOutput("filter_status")
  )
)
