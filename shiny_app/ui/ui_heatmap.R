# Heatmap UI

fluidPage(
  box(
    title = "Heatmap", status = "warning", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Heatmap Visualization"),
    p("Create heatmaps for feature expression patterns."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("heatmap_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        uiOutput("heatmap_diff_warning"),
        selectInput("heatmap_group", "Group Variable (for annotation):",
          choices = NULL,
          width = "100%"
        ),
        hr(),
        h4("Feature Selection"),
        radioButtons("heatmap_feature_source", "Feature Selection Method:",
          choices = list(
            "Top N by Variance" = "topN",
            "From Differential Analysis" = "diff"
          ),
          selected = "topN"
        ),
        conditionalPanel(
          condition = "input.heatmap_feature_source == 'topN'",
          numericInput("heatmap_topN", "Top N Features:", value = 50, min = 1)
        ),
        conditionalPanel(
          condition = "input.heatmap_feature_source == 'diff'",
          h5("Filter by Differential Analysis Results:"),
          selectInput("heatmap_diff_direction", "Gene Direction:",
            choices = list(
              "All DEGs" = "all",
              "Upregulated only" = "up",
              "Downregulated only" = "down"
            ),
            selected = "all"
          ),
          selectInput("heatmap_diff_pvalue_type", "P-value Type:",
            choices = list(
              "P-value" = "pvalue",
              "Adjusted P-value (FDR)" = "fdr"
            ),
            selected = "fdr"
          ),
          numericInput("heatmap_diff_pvalue", "P-value Threshold:", 
            value = 0.05, min = 0, max = 1, step = 0.01),
          numericInput("heatmap_diff_fc", "Fold Change Threshold:", 
            value = 1.5, min = 0, step = 0.1),
          uiOutput("heatmap_diff_group_filter")
        ),
        selectInput("heatmap_cluster_rows", "Cluster Rows:",
          choices = list("Yes" = TRUE, "No" = FALSE),
          selected = TRUE
        ),
        selectInput("heatmap_cluster_cols", "Cluster Columns:",
          choices = list("Yes" = TRUE, "No" = FALSE),
          selected = TRUE
        ),
        numericInput("heatmap_width", "Plot Width (px):", value = 1000, min = 400),
        numericInput("heatmap_height", "Plot Height (px):", value = 800, min = 400),
        actionButton("heatmap_btn", "Generate Heatmap", 
          class = "btn-warning", icon = icon("th"))
      ),
      column(6,
        h5("Heatmap Options:"),
        p("• Top N Features: Show top variable features"),
        p("• Clustering: Cluster rows and/or columns"),
        p("• Group Annotation: Add sample group annotations")
      )
    ),
    
    hr(),
    
    h4("Heatmap"),
    plotOutput("heatmap_output", height = "800px"),
    
    hr(),
    
    downloadButton("heatmap_download", "Download Plot", class = "btn-primary")
  )
)
