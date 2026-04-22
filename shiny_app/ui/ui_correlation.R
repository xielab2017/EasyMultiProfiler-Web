# Correlation Analysis UI

fluidPage(
  box(
    title = "Correlation Analysis", status = "success", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Correlation Analysis"),
    p("Calculate correlations between features or samples."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("cor_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        selectInput("cor_method", "Correlation Method:",
          choices = list(
            "Pearson" = "pearson",
            "Spearman" = "spearman",
            "Kendall" = "kendall"
          ),
          selected = "pearson"
        ),
        radioButtons("cor_type", "Correlation Type:",
          choices = list(
            "Feature-Feature" = "feature",
            "Sample-Sample" = "sample"
          ),
          selected = "feature"
        ),
        numericInput("cor_threshold", "Correlation Threshold:", value = 0.7, min = 0, max = 1, step = 0.1),
        checkboxInput("cor_use_cached", "Use Cached", value = TRUE),
        actionButton("cor_btn", "Calculate Correlations", 
          class = "btn-success", icon = icon("project-diagram"))
      ),
      column(6,
        h5("Correlation Methods:"),
        p("• Pearson: Linear correlation"),
        p("• Spearman: Rank-based correlation"),
        p("• Kendall: Rank-based correlation"),
        br(),
        h5("Analysis Types:"),
        p("• Feature-Feature: Correlations between features"),
        p("• Sample-Sample: Correlations between samples")
      )
    ),
    
    hr(),
    
    h4("Correlation Results"),
    DT::dataTableOutput("cor_results_table"),
    
    hr(),
    
    h4("Correlation Heatmap"),
    plotOutput("cor_heatmap", height = "600px")
  )
)
