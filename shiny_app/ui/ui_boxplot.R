# Boxplot UI

fluidPage(
  box(
    title = "Boxplot", status = "warning", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Boxplot Visualization"),
    p("Create boxplots with statistical comparisons."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("boxplot_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        selectInput("boxplot_method", "Statistical Test:",
          choices = list(
            "None" = "none",
            "Wilcoxon" = "wilcox.test",
            "t-test" = "t.test",
            "Kruskal-Wallis" = "kruskal.test",
            "ANOVA" = "aov"
          ),
          selected = "wilcox.test"
        ),
        selectInput("boxplot_group", "Group Variable:",
          choices = NULL,
          width = "100%"
        ),
        checkboxInput("boxplot_violin", "Show Violin Plot", value = FALSE),
        numericInput("boxplot_width", "Plot Width (px):", value = 800, min = 400),
        numericInput("boxplot_height", "Plot Height (px):", value = 600, min = 400),
        actionButton("boxplot_btn", "Generate Boxplot", 
          class = "btn-warning", icon = icon("chart-bar"))
      ),
      column(6,
        h5("Boxplot Options:"),
        p("• Group Variable: Variable to group by"),
        p("• Statistical Test: Add comparisons"),
        p("• Violin Plot: Show distribution shape")
      )
    ),
    
    hr(),
    
    h4("Boxplot"),
    plotOutput("boxplot_output", height = "600px"),
    
    hr(),
    
    downloadButton("boxplot_download", "Download Plot", class = "btn-primary")
  )
)
