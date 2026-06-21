# Data Import UI - Simplified with Auto-Detection

fluidPage(
  box(
    title = "Data Import", status = "primary", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Import Multi-omics Data"),
    p("Upload your data file. The system will automatically detect format, samples, and features."),
    
    hr(),
    
    h4("1. Upload Data File"),
    fluidRow(
      column(6,
        fileInput("data_file", "Choose Data File",
          accept = c(".csv", ".tsv", ".txt", ".biom", ".qzv")
        ),
        p(strong("Auto-Detection:"), "Format, samples, and features will be automatically detected.", 
          style = "color: #5cb85c;"),
        br(),
        actionButton("preview_data_btn", "Preview & Auto-Detect", 
          class = "btn-info", icon = icon("search")),
        br(), br(),
        actionButton("import_data_btn", "Import Data", 
          class = "btn-primary btn-lg", icon = icon("upload"))
      ),
      column(6,
        h5("Supported Formats:"),
        p("• CSV/TSV files (.csv, .tsv, .txt)"),
        p("• BIOM files (.biom)"),
        p("• QZV files (.qzv)"),
        br(),
        h5("Auto-Detection Features:"),
        p("✓ File format from extension"),
        p("✓ Feature column (first non-index column)"),
        p("✓ Sample columns (numeric columns)"),
        p("✓ Taxonomy level (if applicable)"),
        p("✓ Data type (counts vs relative abundance)")
      )
    ),
    
    hr(),
    
    h4("2. File Preview & Detected Settings"),
    fluidRow(
      column(12,
        DT::dataTableOutput("data_preview", height = "300px"),
        br(),
        verbatimTextOutput("detection_info")
      )
    ),
    
    hr(),
    
    h4("3. Adjust Settings (Optional)"),
    p("Most settings are auto-detected. Only adjust if needed:"),
    fluidRow(
      column(4,
        selectInput("data_type_import", "Data Type:",
          choices = list(
            "16S/Microbiome" = "tax",
            "RNAseq" = "normal",
            "Metabolomics" = "normal",
            "Proteomics" = "normal",
            "Functional (KO/EC)" = "functional",
            "Clinical" = "normal"
          ),
          selected = "tax"
        )
      ),
      column(4,
        conditionalPanel(
          condition = "input.data_type_import == 'tax'",
          selectInput("start_level_import", "Taxonomy Level:",
            choices = list("Species" = "Species", "Genus" = "Genus", "Family" = "Family",
                         "Order" = "Order", "Class" = "Class", "Phylum" = "Phylum",
                         "Kingdom" = "Kindom", "Domain" = "Domain"),
            selected = "Species"
          ),
          textInput("tax_sep_import", "Taxonomy Separator:", value = ";", width = "100%")
        )
      ),
      column(4,
        textInput("experiment_name_import", "Experiment Name:", value = "", 
          placeholder = "Auto-detected from filename"),
        textInput("assay_name_import", "Assay Name:", value = "", 
          placeholder = "Auto-detected")
      )
    ),
    
    hr(),
    
    h4("4. Upload Sample Metadata (Optional)"),
    p("Upload metadata file to automatically map sample information. Metadata will be automatically linked to your data."),
    fluidRow(
      column(6,
        fileInput("metadata_file_import", "Choose Metadata File (CSV/TSV)",
          accept = c(".csv", ".tsv", ".txt")
        ),
        p(strong("Metadata Format:"), "First column should contain sample IDs matching your data column names."),
        p(strong("Example:"), "SampleID,Group,Treatment,Age"),
        actionButton("preview_metadata_btn", "Preview Metadata", 
          class = "btn-info btn-sm", icon = icon("eye")),
        br(), br(),
        DT::dataTableOutput("metadata_preview_import", height = "200px")
      ),
      column(6,
        h5("Metadata Benefits:"),
        p("• Automatically maps sample information to your data"),
        p("• Links samples to groups, treatments, clinical variables, etc."),
        p("• Enables group-based analysis (differential, clustering, etc.)"),
        p("• No manual mapping needed - system auto-detects sample IDs"),
        br(),
        h5("Auto-Mapping:"),
        p("• System automatically finds sample ID column"),
        p("• Matches metadata to data samples"),
        p("• Merges metadata with imported data")
      )
    ),
    
    hr(),
    
    h4("5. Import Status"),
    verbatimTextOutput("import_status"),
    
    hr(),
    
    h4("6. Available Experiments"),
    DT::dataTableOutput("experiments_table")
  )
)
