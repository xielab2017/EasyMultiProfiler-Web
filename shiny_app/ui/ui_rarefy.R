# Rarefaction UI

fluidPage(
  box(
    title = "Rarefaction", status = "primary", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Rarefy Data"),
    p("Rarefy samples to a common sequencing depth."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("rarefy_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        numericInput("rarefy_sample_size", "Sample Size:", value = 1000, min = 1),
        checkboxInput("rarefy_use_cached", "Use Cached", value = TRUE),
        actionButton("rarefy_btn", "Rarefy Data", 
          class = "btn-primary", icon = icon("random"))
      ),
      column(6,
        h5("Rarefaction:"),
        p("Rarefaction is used to normalize samples to the same sequencing depth."),
        p("This is commonly used in microbiome analysis to account for sequencing depth variation.")
      )
    ),
    
    hr(),
    
    h4("Rarefaction Status"),
    verbatimTextOutput("rarefy_status")
  )
)
