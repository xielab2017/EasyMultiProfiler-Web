# Differential Analysis UI

fluidPage(
  box(
    title = "Differential Analysis", status = "success", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Differential Expression/Analysis"),
    p("Identify differentially expressed features between groups."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("diff_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        selectInput("diff_method", "Analysis Method:",
          choices = list(
            "DESeq2" = "DESeq2",
            "edgeR Quasi-likelihood" = "edgeR_quasi_likelihood",
            "edgeR Likelihood Ratio" = "edgeR_likelihood_ratio",
            "edgeR Robust" = "edger_robust_likelihood_ratio",
            "limma Voom" = "limma_voom",
            "limma Voom (weighted)" = "limma_voom_sample_weights",
            "Wilcoxon" = "wilcox.test",
            "t-test" = "t.test",
            "Kruskal-Wallis" = "kruskal.test",
            "One-way ANOVA" = "oneway.test"
          ),
          selected = "DESeq2"
        ),
        selectInput("diff_group", "Group Variable:",
          choices = NULL,
          width = "100%"
        ),
        uiOutput("diff_groups_info"),
        selectInput("diff_control_group", "Control/Reference Group:",
          choices = NULL,
          width = "100%"
        ),
        uiOutput("diff_comparison_group_selector"),
        uiOutput("diff_comparison_groups"),
        numericInput("diff_pvalue", "P-value Threshold:", value = 0.05, min = 0, max = 1, step = 0.01),
        numericInput("diff_fc", "Fold Change Threshold:", value = 1.5, min = 0),
        checkboxInput("diff_use_cached", "Use Cached", value = TRUE),
        actionButton("diff_btn", "Run Differential Analysis", 
          class = "btn-success", icon = icon("search")),
        hr(),
        h4("Volcano Plot Color Settings"),
        fluidRow(
          column(6,
            textInput("diff_color_up", "Upregulated Color (上调):", 
              value = "#E74C3C", placeholder = "#E74C3C (red)"),
            helpText("上调基因颜色 (红色系)")
          ),
          column(6,
            textInput("diff_color_down", "Downregulated Color (下调):", 
              value = "#3498DB", placeholder = "#3498DB (blue)"),
            helpText("下调基因颜色 (蓝色系)")
          )
        ),
        fluidRow(
          column(12,
            textInput("diff_color_ns", "Non-significant Color (非显著):", 
              value = "#BDC3C7", placeholder = "#BDC3C7 (gray)"),
            helpText("非显著基因颜色 (灰色)")
          )
        )
      ),
      column(6,
        h5("Analysis Methods:"),
        p("• DESeq2: Negative binomial model"),
        p("• edgeR: Negative binomial model"),
        p("• limma: Linear model"),
        p("• Wilcoxon: Non-parametric test"),
        p("• t-test: Parametric test"),
        br(),
        h5("Comparison Setup:"),
        p("1. Select a group variable from your metadata"),
        p("2. Choose the control/reference group"),
        p("3. Other groups will be compared against the control"),
        br(),
        h5("Note:"),
        p("For methods like DESeq2 and edgeR, comparisons are automatically set up based on the control group selection.")
      )
    ),
    
    hr(),
    
    h4("Differential Analysis Results"),
    DT::dataTableOutput("diff_results_table"),
    
    hr(),
    
    h4("Volcano Plot"),
    plotOutput("diff_volcano_plot", height = "600px")
  )
)
