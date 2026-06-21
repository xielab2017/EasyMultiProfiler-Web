# Barplot UI

fluidPage(
  box(
    title = "Barplot", status = "warning", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Barplot Visualization"),
    p("Create barplots for your data."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("barplot_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        radioButtons("barplot_mode", "Plot Mode:",
          choices = list(
            "Multiple Features (Top N)" = "multiple",
            "Single Feature" = "single"
          ),
          selected = "multiple"
        ),
        conditionalPanel(
          condition = "input.barplot_mode == 'single'",
          uiOutput("barplot_feature_selector")
        ),
        conditionalPanel(
          condition = "input.barplot_mode == 'multiple'",
          numericInput("barplot_topN", "Top N Features:", value = 10, min = 1)
        ),
        selectInput("barplot_method", "Statistical Test:",
          choices = list(
            "None" = "none",
            "Wilcoxon" = "wilcox.test",
            "t-test" = "t.test"
          ),
          selected = "wilcox.test"
        ),
        selectInput("barplot_group", "Group Variable:",
          choices = NULL,
          width = "100%"
        ),
        numericInput("barplot_width", "Plot Width (px):", value = 800, min = 400),
        numericInput("barplot_height", "Plot Height (px):", value = 600, min = 400),
        actionButton("barplot_btn", "Generate Barplot", 
          class = "btn-warning", icon = icon("chart-bar"))
      ),
      column(6,
        h5("Barplot Options:"),
        p("• Group Variable: Variable to group bars by"),
        p("• Statistical Test: Add statistical comparisons"),
        p("• Adjustable dimensions for export")
      )
    ),
    
    hr(),
    
    h4("Barplot"),
    plotOutput("barplot_output", height = "600px"),
    
    hr(),
    
    downloadButton("barplot_download", "Download Plot", class = "btn-primary")
  )
)
