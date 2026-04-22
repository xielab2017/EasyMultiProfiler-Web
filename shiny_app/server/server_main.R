# Main Server for EasyMultiProfiler Web Application

server <- function(input, output, session) {
  
  # Reactive values to store data
  values <- reactiveValues(
    emp_data = NULL,
    current_experiment = NULL,
    experiment_types = list(),  # Store experiment types: experiment_name -> type
    analysis_results = list(),
    plots = list(),
    sample_metadata_transformed = NULL,
    tax_file_preview = NULL
  )
  
  # Note: detection_results is defined in server_import.R
  
  # Source utility functions first
  source("server/server_utils.R", local = TRUE)
  source("server/server_experiment_type.R", local = TRUE)
  
  # Source server modules
  source("server/server_import.R", local = TRUE)
  source("server/server_summary.R", local = TRUE)
  source("server/server_preparation.R", local = TRUE)
  source("server/server_analysis.R", local = TRUE)
  source("server/server_visualization.R", local = TRUE)
  source("server/server_export.R", local = TRUE)
  
  # Update experiment types when data changes
  observe({
    if (!is.null(values$emp_data) && inherits(values$emp_data, "MultiAssayExperiment")) {
      exp_names <- names(values$emp_data)
      for (exp_name in exp_names) {
        if (is.null(values$experiment_types[[exp_name]])) {
          exp_type <- detect_experiment_type(values$emp_data, exp_name)
          values$experiment_types[[exp_name]] <- exp_type
        }
      }
    }
  })
  
  # Update menu visibility based on current experiment type
  observe({
    if (!is.null(values$current_experiment) && 
        !is.null(values$experiment_types[[values$current_experiment]])) {
      exp_type <- values$experiment_types[[values$current_experiment]]
      
      # Remove all type classes from body
      shinyjs::removeClass(selector = "body", class = "show-microbiome")
      shinyjs::removeClass(selector = "body", class = "show-rnaseq")
      shinyjs::removeClass(selector = "body", class = "show-proteomics")
      shinyjs::removeClass(selector = "body", class = "show-metabolomics")
      shinyjs::removeClass(selector = "body", class = "show-functional")
      shinyjs::removeClass(selector = "body", class = "show-clinical")
      
      # Add appropriate class based on experiment type
      if (exp_type == "microbiome") {
        shinyjs::addClass(selector = "body", class = "show-microbiome")
      } else if (exp_type == "rnaseq") {
        shinyjs::addClass(selector = "body", class = "show-rnaseq")
      } else if (exp_type == "proteomics") {
        shinyjs::addClass(selector = "body", class = "show-proteomics")
      } else if (exp_type == "metabolomics") {
        shinyjs::addClass(selector = "body", class = "show-metabolomics")
      } else if (exp_type == "functional") {
        shinyjs::addClass(selector = "body", class = "show-functional")
      } else if (exp_type == "clinical") {
        shinyjs::addClass(selector = "body", class = "show-clinical")
      }
    } else {
      # If no experiment selected, show all menu items
      shinyjs::removeClass(selector = "body", class = "show-microbiome")
      shinyjs::removeClass(selector = "body", class = "show-rnaseq")
      shinyjs::removeClass(selector = "body", class = "show-proteomics")
      shinyjs::removeClass(selector = "body", class = "show-metabolomics")
      shinyjs::removeClass(selector = "body", class = "show-functional")
      shinyjs::removeClass(selector = "body", class = "show-clinical")
    }
  })
  
  # Update current experiment when user selects one in summary or other modules
  observe({
    # This will be triggered by modules that select experiments
    # For now, we'll update it when summary experiment is selected
    if (!is.null(input$summary_experiment)) {
      values$current_experiment <- input$summary_experiment
    }
  })
  
  # Helper function to get current EMP/MAE object
  get_emp_data <- reactive({
    if (is.null(values$emp_data)) {
      return(NULL)
    }
    return(values$emp_data)
  })
  
  # Helper function to get current experiment
  get_current_experiment <- reactive({
    if (is.null(values$current_experiment)) {
      return(NULL)
    }
    return(values$current_experiment)
  })
  
  # Helper to get EMPT from MAE
  get_empt <- function(experiment) {
    if (is.null(values$emp_data) || is.null(experiment)) {
      return(NULL)
    }
    
    # If it's already an EMPT, return it
    if (inherits(values$emp_data, "EMPT")) {
      return(values$emp_data)
    }
    
    # If it's MAE, convert to EMPT
    if (inherits(values$emp_data, "MultiAssayExperiment")) {
      # Check if experiment exists
      if (!experiment %in% names(values$emp_data)) {
        return(NULL)
      }
      return(get_empt_from_mae(values$emp_data, experiment))
    }
    
    # If it's EMP, extract EMPT
    if (inherits(values$emp_data, "EMP")) {
      if (experiment %in% names(values$emp_data)) {
        return(values$emp_data[[experiment]])
      }
      return(NULL)
    }
    
    return(NULL)
  }
  
  # Show notification helper
  show_notification <- function(message, type = "default", duration = 3) {
    showNotification(
      message,
      type = type,
      duration = duration
    )
  }
  
  # Error handling wrapper
  safe_execute <- function(expr, error_msg = "An error occurred") {
    tryCatch({
      expr
    }, error = function(e) {
      show_notification(paste(error_msg, ":", e$message), type = "error")
      return(NULL)
    })
  }
}
