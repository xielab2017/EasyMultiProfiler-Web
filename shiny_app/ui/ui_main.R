# Main UI for EasyMultiProfiler Web Application

ui <- dashboardPage(
  dashboardHeader(
    title = "EasyMultiProfiler",
    titleWidth = 250,
    tags$li(
      class = "dropdown",
      tags$a(
        href = "https://github.com/liubingdong/EasyMultiProfiler",
        target = "_blank",
        icon("github", class = "fa-lg"),
        style = "padding-top: 10px; padding-bottom: 10px;"
      )
    )
  ),
  
  dashboardSidebar(
    width = 250,
    sidebarMenu(
      id = "sidebarMenu",
      menuItem("Data Import", tabName = "import", icon = icon("upload")),
      menuItem("Data Summary", tabName = "summary", icon = icon("info-circle")),
      menuItem("Data Preparation", tabName = "preparation", icon = icon("cog"),
        menuSubItem("Filter", tabName = "filter"),
        menuSubItem("Normalize", tabName = "normalize"),
        menuSubItem("Impute", tabName = "impute"),
        menuSubItem("Rarefy", tabName = "rarefy"),
        menuSubItem("Collapse", tabName = "collapse"),
        menuSubItem("Feature Convert", tabName = "feature_convert")
      ),
      menuItem("Analysis", tabName = "analysis", icon = icon("chart-line"),
        menuSubItem("Alpha Diversity", tabName = "alpha"),
        menuSubItem("Correlation", tabName = "correlation"),
        menuSubItem("Differential", tabName = "differential"),
        menuSubItem("Dimension Reduction", tabName = "dimension"),
        menuSubItem("Cluster", tabName = "cluster"),
        menuSubItem("Marker", tabName = "marker"),
        menuSubItem("Enrichment", tabName = "enrichment"),
        menuSubItem("GSEA", tabName = "gsea"),
        menuSubItem("WGCNA", tabName = "wgcna"),
        menuSubItem("Network", tabName = "network"),
        menuSubItem("Multi Analysis", tabName = "multi_analysis")
      ),
      menuItem("Visualization", tabName = "visualization", icon = icon("image"),
        menuSubItem("Barplot", tabName = "barplot"),
        menuSubItem("Boxplot", tabName = "boxplot"),
        menuSubItem("Heatmap", tabName = "heatmap"),
        menuSubItem("Volcano Plot", tabName = "volcano"),
        menuSubItem("Scatterplot", tabName = "scatterplot"),
        menuSubItem("Sankey Plot", tabName = "sankey"),
        menuSubItem("Network Plot", tabName = "network_plot"),
        menuSubItem("Enrichment Plots", tabName = "enrich_plots"),
        menuSubItem("Structure Plot", tabName = "structure_plot")
      ),
      menuItem("Results Export", tabName = "export", icon = icon("download"))
    )
  ),
  
  dashboardBody(
    useShinyjs(),
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "www/custom.css")
    ),
    
    tabItems(
      # Data Import (includes metadata)
      tabItem(tabName = "import",
        source("ui/ui_import.R", local = TRUE)$value
      ),
      
      # Data Summary
      tabItem(tabName = "summary",
        source("ui/ui_summary.R", local = TRUE)$value
      ),
      
      # Data Preparation Tabs
      tabItem(tabName = "filter",
        source("ui/ui_filter.R", local = TRUE)$value
      ),
      tabItem(tabName = "normalize",
        source("ui/ui_normalize.R", local = TRUE)$value
      ),
      tabItem(tabName = "impute",
        source("ui/ui_impute.R", local = TRUE)$value
      ),
      tabItem(tabName = "rarefy",
        source("ui/ui_rarefy.R", local = TRUE)$value
      ),
      tabItem(tabName = "collapse",
        source("ui/ui_collapse.R", local = TRUE)$value
      ),
      tabItem(tabName = "feature_convert",
        source("ui/ui_feature_convert.R", local = TRUE)$value
      ),
      
      # Analysis Tabs
      tabItem(tabName = "alpha",
        source("ui/ui_alpha.R", local = TRUE)$value
      ),
      tabItem(tabName = "correlation",
        source("ui/ui_correlation.R", local = TRUE)$value
      ),
      tabItem(tabName = "differential",
        source("ui/ui_differential.R", local = TRUE)$value
      ),
      tabItem(tabName = "dimension",
        source("ui/ui_dimension.R", local = TRUE)$value
      ),
      tabItem(tabName = "cluster",
        source("ui/ui_cluster.R", local = TRUE)$value
      ),
      tabItem(tabName = "marker",
        source("ui/ui_marker.R", local = TRUE)$value
      ),
      tabItem(tabName = "enrichment",
        source("ui/ui_enrichment.R", local = TRUE)$value
      ),
      tabItem(tabName = "gsea",
        source("ui/ui_gsea.R", local = TRUE)$value
      ),
      tabItem(tabName = "wgcna",
        source("ui/ui_wgcna.R", local = TRUE)$value
      ),
      tabItem(tabName = "network",
        source("ui/ui_network.R", local = TRUE)$value
      ),
      tabItem(tabName = "multi_analysis",
        source("ui/ui_multi_analysis.R", local = TRUE)$value
      ),
      
      # Visualization Tabs
      tabItem(tabName = "barplot",
        source("ui/ui_barplot.R", local = TRUE)$value
      ),
      tabItem(tabName = "boxplot",
        source("ui/ui_boxplot.R", local = TRUE)$value
      ),
      tabItem(tabName = "heatmap",
        source("ui/ui_heatmap.R", local = TRUE)$value
      ),
      tabItem(tabName = "volcano",
        source("ui/ui_volcano.R", local = TRUE)$value
      ),
      tabItem(tabName = "scatterplot",
        source("ui/ui_scatterplot.R", local = TRUE)$value
      ),
      tabItem(tabName = "sankey",
        source("ui/ui_sankey.R", local = TRUE)$value
      ),
      tabItem(tabName = "network_plot",
        source("ui/ui_network_plot.R", local = TRUE)$value
      ),
      tabItem(tabName = "enrich_plots",
        source("ui/ui_enrich_plots.R", local = TRUE)$value
      ),
      tabItem(tabName = "structure_plot",
        source("ui/ui_structure_plot.R", local = TRUE)$value
      ),
      
      # Export
      tabItem(tabName = "export",
        source("ui/ui_export.R", local = TRUE)$value
      )
    )
  )
)
