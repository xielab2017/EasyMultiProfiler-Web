# Volcano Plot UI

fluidPage(
  box(
    title = "Volcano Plot", status = "warning", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Volcano Plot"),
    p("Visualize differential analysis results with volcano plots."),
    
    hr(),
    
    fluidRow(
      column(6,
        uiOutput("volcano_experiment_info"),
        uiOutput("volcano_diff_warning"),
        selectInput("volcano_y", "Y-axis:",
          choices = list(
            "P-value" = "pvalue",
            "Adjusted P-value" = "padj"
          ),
          selected = "pvalue"
        ),
        numericInput("volcano_pvalue", "P-value Threshold:", value = 0.05, min = 0, max = 1),
        numericInput("volcano_fc", "Fold Change Threshold:", value = 1.5, min = 0),
        numericInput("volcano_threshold_x", "Log2FC Threshold (for coloring):", value = 0, min = 0),
        hr(),
        h5("Color Settings:"),
        textInput("volcano_color_up", "Upregulated Color:", value = "#E74C3C", placeholder = "#E74C3C (red)"),
        textInput("volcano_color_down", "Downregulated Color:", value = "#3498DB", placeholder = "#3498DB (blue)"),
        textInput("volcano_color_ns", "Non-significant Color:", value = "#636363", placeholder = "#636363 (gray)"),
        hr(),
        numericInput("volcano_width", "Plot Width (px):", value = 800, min = 400),
        numericInput("volcano_height", "Plot Height (px):", value = 600, min = 400),
        actionButton("volcano_btn", "Generate Volcano Plot", 
          class = "btn-warning", icon = icon("mountain"))
      ),
      column(6,
        h5("Volcano Plot:"),
        p("Visualize significance vs. fold change."),
        p("Features above thresholds are highlighted."),
        br(),
        h5("Color Coding:"),
        p("• Red: Upregulated genes (log2FC > threshold)"),
        p("• Blue: Downregulated genes (log2FC < -threshold)"),
        p("• Gray: Non-significant genes"),
        p("• Different groups are shown with different color shades")
      )
    ),
    
    hr(),
    
    h4("Volcano Plot"),
    plotOutput("volcano_output", height = "600px"),
    
    hr(),
    
    downloadButton("volcano_download", "Download Plot", class = "btn-primary")
  )
)
