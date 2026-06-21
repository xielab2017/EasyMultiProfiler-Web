# Results Export UI

fluidPage(
  box(
    title = "Results Export", status = "info", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Export Results and Data"),
    p("Download analysis results, plots, and processed data."),
    
    hr(),
    
    h4("1. Export Data"),
    fluidRow(
      column(6,
        selectInput("export_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        selectInput("export_format", "Export Format:",
          choices = list(
            "CSV" = "csv",
            "TSV" = "tsv",
            "Excel" = "xlsx",
            "RDS" = "rds"
          ),
          selected = "csv"
        ),
        downloadButton("export_data_btn", "Download Data", class = "btn-primary")
      ),
      column(6,
        h5("Data Export:"),
        p("Export processed data in various formats.")
      )
    ),
    
    hr(),
    
    h4("2. Export Analysis Results"),
    fluidRow(
      column(6,
        selectInput("export_analysis_type", "Analysis Type:",
          choices = list(
            "Alpha Diversity" = "alpha",
            "Correlation" = "correlation",
            "Differential" = "differential",
            "Enrichment" = "enrichment",
            "GSEA" = "gsea",
            "WGCNA" = "wgcna"
          )
        ),
        selectInput("export_results_format", "Format:",
          choices = list(
            "CSV" = "csv",
            "TSV" = "tsv",
            "Excel" = "xlsx"
          ),
          selected = "csv"
        ),
        downloadButton("export_results_btn", "Download Results", class = "btn-primary")
      ),
      column(6,
        h5("Results Export:"),
        p("Export analysis results as tables.")
      )
    ),
    
    hr(),
    
    h4("3. Export Plots"),
    fluidRow(
      column(6,
        selectInput("export_plot_type", "Plot Type:",
          choices = list(
            "Barplot" = "barplot",
            "Boxplot" = "boxplot",
            "Heatmap" = "heatmap",
            "Volcano Plot" = "volcano",
            "Scatterplot" = "scatterplot",
            "Sankey Plot" = "sankey",
            "Network Plot" = "network_plot",
            "Enrichment Plot" = "enrich_plots",
            "Structure Plot" = "structure_plot"
          )
        ),
        selectInput("export_plot_format", "Format:",
          choices = list(
            "PNG" = "png",
            "PDF" = "pdf",
            "SVG" = "svg",
            "EPS" = "eps"
          ),
          selected = "png"
        ),
        numericInput("export_plot_width", "Width (px):", value = 1200, min = 400),
        numericInput("export_plot_height", "Height (px):", value = 800, min = 400),
        numericInput("export_plot_dpi", "DPI:", value = 300, min = 72, max = 600),
        downloadButton("export_plot_btn", "Download Plot", class = "btn-primary")
      ),
      column(6,
        h5("Plot Export:"),
        p("Export plots in high-resolution formats.")
      )
    ),
    
    hr(),
    
    h4("4. Export Complete Session"),
    fluidRow(
      column(6,
        p("Export the entire analysis session including all data, results, and plots."),
        downloadButton("export_session_btn", "Download Session (RDS)", class = "btn-success")
      ),
      column(6,
        h5("Session Export:"),
        p("Save the complete analysis session for later use.")
      )
    )
  )
)
