# Sample Metadata Mapping UI

fluidPage(
  box(
    title = "Sample Metadata Mapping", status = "primary", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Upload and Transform Sample Metadata"),
    p("Upload a text file with sample information and transform it to the format required by EMP for downstream analysis."),
    
    hr(),
    
    h4("1. Upload Sample Metadata File"),
    fluidRow(
      column(6,
        fileInput("sample_metadata_file", "Choose Metadata File (CSV/TSV)",
          accept = c(".csv", ".tsv", ".txt")
        ),
        radioButtons("sample_metadata_sep", "File Separator:",
          choices = list(
            "Auto-detect" = "auto",
            "Comma (,)" = ",",
            "Tab (\\t)" = "\t",
            "Semicolon (;)" = ";"
          ),
          selected = "auto"
        ),
        checkboxInput("sample_metadata_header", "Has Header Row", value = TRUE),
        actionButton("sample_metadata_preview_btn", "Preview File", 
          class = "btn-info", icon = icon("eye"))
      ),
      column(6,
        h5("File Requirements:"),
        p("• CSV or TSV format"),
        p("• First column should contain sample IDs"),
        p("• Additional columns can contain any metadata (group, treatment, age, etc.)"),
        p("• Sample IDs should match the sample names in your data"),
        br(),
        h5("Example Format:"),
        p("SampleID,Group,Treatment,Age"),
        p("Sample1,Control,Placebo,25"),
        p("Sample2,Treatment,Drug,30")
      )
    ),
    
    hr(),
    
    h4("2. Preview Uploaded Metadata"),
    DT::dataTableOutput("sample_metadata_preview"),
    
    hr(),
    
    h4("3. Configure Mapping"),
    fluidRow(
      column(6,
        selectInput("sample_metadata_primary_col", "Primary Column (Sample ID):",
          choices = NULL,
          width = "100%"
        ),
        p("Select the column that contains unique sample identifiers."),
        br(),
        h5("Optional: Map to Existing Experiment"),
        selectInput("sample_metadata_experiment", "Target Experiment (optional):",
          choices = NULL,
          width = "100%"
        ),
        p("If selected, metadata will be added to this experiment. Leave empty to create new experiment."),
        br(),
        textInput("sample_metadata_experiment_name", "New Experiment Name (if creating new):",
          value = "metadata",
          placeholder = "metadata"
        )
      ),
      column(6,
        h5("Mapping Configuration:"),
        p("• Primary Column: The column containing sample IDs"),
        p("• These IDs should match sample names in your data"),
        p("• All other columns will be included as metadata"),
        br(),
        h5("Integration Options:"),
        p("• Add to existing experiment: Merge metadata with existing sample info"),
        p("• Create new experiment: Create a new experiment from metadata only")
      )
    ),
    
    hr(),
    
    h4("4. Transform and Apply"),
    fluidRow(
      column(6,
        actionButton("sample_metadata_transform_btn", "Transform and Apply Metadata", 
          class = "btn-success", icon = icon("magic")),
        br(), br(),
        verbatimTextOutput("sample_metadata_status")
      ),
      column(6,
        h5("Transformation Process:"),
        p("1. Validates sample ID column"),
        p("2. Transforms to EMP-required format"),
        p("3. Adds/updates metadata in selected experiment"),
        p("4. Creates sampleMap if needed")
      )
    ),
    
    hr(),
    
    h4("5. Transformed Metadata Preview"),
    DT::dataTableOutput("sample_metadata_transformed")
  )
)
