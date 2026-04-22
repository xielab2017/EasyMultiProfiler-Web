# Feature Convert UI

fluidPage(
  box(
    title = "Feature ID Conversion", status = "primary", solidHeader = TRUE, width = 12,
    collapsible = TRUE,
    
    h3("Convert Feature IDs"),
    p("Convert feature identifiers between different formats (e.g., gene IDs, taxonomy IDs)."),
    
    hr(),
    
    fluidRow(
      column(6,
        selectInput("feature_convert_experiment", "Select Experiment:",
          choices = NULL,
          width = "100%"
        ),
        selectInput("feature_convert_from", "From ID Type:",
          choices = list(
            "ENTREZID" = "ENTREZID",
            "ENSEMBL" = "ENSEMBL",
            "SYMBOL" = "SYMBOL",
            "UNIPROT" = "UNIPROT",
            "REFSEQ" = "REFSEQ"
          )
        ),
        selectInput("feature_convert_to", "To ID Type:",
          choices = list(
            "ENTREZID" = "ENTREZID",
            "ENSEMBL" = "ENSEMBL",
            "SYMBOL" = "SYMBOL",
            "UNIPROT" = "UNIPROT",
            "REFSEQ" = "REFSEQ"
          )
        ),
        selectInput("feature_convert_species", "Species:",
          choices = list(
            "Human" = "Human",
            "Mouse" = "Mouse",
            "Pig" = "Pig",
            "Zebrafish" = "Zebrafish",
            "Custom (use OrgDb)" = "custom"
          ),
          selected = "Human"
        ),
        conditionalPanel(
          condition = "input.feature_convert_species == 'custom'",
          textInput("feature_convert_orgdb", "OrgDb (e.g., 'org.Hs.eg.db'):", 
            value = "org.Hs.eg.db",
            placeholder = "org.Hs.eg.db")
        ),
        actionButton("feature_convert_btn", "Convert Features", 
          class = "btn-primary", icon = icon("exchange-alt"))
      ),
      column(6,
        h5("ID Conversion:"),
        p("Convert between different gene/feature identifier formats."),
        p("Common conversions:"),
        p("• ENTREZID ↔ SYMBOL"),
        p("• ENSEMBL ↔ SYMBOL"),
        p("• UNIPROT ↔ ENTREZID"),
        br(),
        h5("Organism Databases:"),
        p("• Human: org.Hs.eg.db"),
        p("• Mouse: org.Mm.eg.db"),
        p("• Rat: org.Rn.eg.db")
      )
    ),
    
    hr(),
    
    h4("Conversion Status"),
    verbatimTextOutput("feature_convert_status")
  )
)
