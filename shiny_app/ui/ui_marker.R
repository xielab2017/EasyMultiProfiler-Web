# Marker Analysis UI

fluidPage(
  box(
    title = "Marker Analysis", status = "success", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Marker Feature Analysis"),
    p("Identify marker features for different groups."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("marker_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        selectInput("marker_method", "Method:",
          choices = list(
            "Random Forest" = "rf",
            "LEfSe" = "lefse",
            "ANCOM" = "ancom"
          ),
          selected = "rf"
        ),
        selectInput("marker_group", "Group Variable:",
          choices = NULL,
          width = "100%"
        ),
        numericInput("marker_topN", "Top N Markers:", value = 20, min = 1),
        checkboxInput("marker_use_cached", "Use Cached", value = TRUE),
        actionButton("marker_btn", "Find Markers", 
          class = "btn-success", icon = icon("bullseye"))
      ),
      column(6,
        h5("Marker Methods:"),
        p("• Random Forest: Feature importance"),
        p("• LEfSe: Linear discriminant analysis"),
        p("• ANCOM: Analysis of composition of microbiomes")
      )
    ),
    
    hr(),
    
    h4("Marker Results"),
    DT::dataTableOutput("marker_results_table")
  )
)
