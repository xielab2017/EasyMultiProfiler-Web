# Data Summary UI

fluidPage(
  box(
    title = "Data Summary", status = "info", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Data Overview"),
    p("View summary information about your imported data."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("summary_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        uiOutput("experiment_type_badge"),
        br(),
        actionButton("generate_summary_btn", "Generate Summary", 
          class = "btn-primary", icon = icon("refresh"))
      ),
      column(6,
        h5("Summary Information:"),
        p("• Sample count and metadata"),
        p("• Feature count and annotations"),
        p("• Data statistics and quality metrics"),
        p("• Experiment type and available analyses"),
        br(),
        uiOutput("available_analyses_info")
      )
    ),
    
    hr(),
    
    h4("Summary Output"),
    verbatimTextOutput("summary_output"),
    
    hr(),
    
    h4("Sample Metadata"),
    DT::dataTableOutput("sample_metadata_table"),
    
    hr(),
    
    h4("Feature Annotations"),
    DT::dataTableOutput("feature_annotations_table")
  )
)
