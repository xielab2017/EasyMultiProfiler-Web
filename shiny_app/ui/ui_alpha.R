# Alpha Diversity Analysis UI

fluidPage(
  box(
    title = "Alpha Diversity Analysis", status = "success", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Alpha Diversity Analysis"),
    p("Calculate alpha diversity indices for your samples."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("alpha_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        checkboxInput("alpha_use_cached", "Use Cached", value = TRUE),
        actionButton("alpha_btn", "Calculate Alpha Diversity", 
          class = "btn-success", icon = icon("calculator"))
      ),
      column(6,
        h5("Alpha Diversity Indices:"),
        p("• Shannon: Shannon diversity index"),
        p("• Simpson: Simpson diversity index"),
        p("• Chao1: Chao1 richness estimator"),
        p("• ACE: Abundance-based Coverage Estimator"),
        p("• Observed: Number of observed features")
      )
    ),
    
    hr(),
    
    h4("Alpha Diversity Results"),
    DT::dataTableOutput("alpha_results_table"),
    
    hr(),
    
    h4("Alpha Diversity Plot"),
    plotOutput("alpha_plot", height = "600px")
  )
)
