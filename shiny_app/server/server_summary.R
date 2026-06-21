# Data Summary Server Logic

# Update experiment choices
observe({
  if (!is.null(values$emp_data)) {
    exp_names <- names(values$emp_data)
    updateSelectInput(session, "summary_experiment", 
      choices = exp_names,
      selected = if(is.null(values$current_experiment)) exp_names[1] else values$current_experiment
    )
    
    # Update current experiment
    if (is.null(values$current_experiment) && length(exp_names) > 0) {
      values$current_experiment <- exp_names[1]
    }
  }
})

# Update current experiment when user selects a different one
observeEvent(input$summary_experiment, {
  if (!is.null(input$summary_experiment)) {
    values$current_experiment <- input$summary_experiment
  }
})

# Generate summary
observeEvent(input$generate_summary_btn, {
  req(input$summary_experiment)
  req(values$emp_data)
  
  tryCatch({
    # Validate experiment exists
    if (!input$summary_experiment %in% names(values$emp_data)) {
      showNotification(paste("Experiment", input$summary_experiment, "not found. Available:", 
        paste(names(values$emp_data), collapse = ", ")), type = "error", duration = 10)
      return()
    }
    
    # Get EMPT object using helper function
    emp_obj <- get_empt(input$summary_experiment)
    
    if (is.null(emp_obj)) {
      # Try direct conversion as fallback
      tryCatch({
        if (inherits(values$emp_data, "MultiAssayExperiment")) {
          emp_obj <- EasyMultiProfiler:::.as.EMPT(values$emp_data, experiment = input$summary_experiment)
        }
      }, error = function(e2) {
        showNotification(paste("Conversion error:", e2$message), type = "error", duration = 10)
      })
      
      if (is.null(emp_obj)) {
        showNotification(paste("Could not convert data to EMPT format. Experiment:", input$summary_experiment, 
          ". Available experiments:", paste(names(values$emp_data), collapse = ", "),
          ". Data type:", class(values$emp_data)[1]), 
          type = "error", duration = 10)
        return()
      }
    }
    
    # Generate summary - EMP_summary needs MAE or EMP, not EMPT
    # So we use the original MAE object
    if (inherits(values$emp_data, "MultiAssayExperiment")) {
      summary_result <- EMP_summary(values$emp_data)
    } else if (inherits(values$emp_data, "EMP")) {
      summary_result <- EMP_summary(values$emp_data)
    } else {
      # If it's EMPT, we can't use EMP_summary directly
      # Instead, create a simple summary from the EMPT object
      summary_result <- data.frame(
        Experiment = input$summary_experiment,
        Samples = ncol(emp_obj),
        Features = nrow(emp_obj),
        Assay = assayNames(emp_obj)[1],
        stringsAsFactors = FALSE
      )
    }
    
    # Store summary
    values$summary_result <- summary_result
    
    showNotification("Summary generated successfully!", type = "message")
  }, error = function(e) {
    showNotification(paste("Summary error:", e$message), type = "error", duration = 10)
  })
})

# Display summary output
output$summary_output <- renderText({
  if (is.null(values$summary_result)) {
    return("Click 'Generate Summary' to view data summary.")
  }
  return(capture.output(print(values$summary_result)))
})

# Display sample metadata
output$sample_metadata_table <- DT::renderDataTable({
  req(input$summary_experiment)
  req(values$emp_data)
  
  # Validate experiment exists
  if (!input$summary_experiment %in% names(values$emp_data)) {
    return(data.frame(Message = paste("Experiment", input$summary_experiment, "not found")))
  }
  
  tryCatch({
    emp_obj <- get_empt(input$summary_experiment)
    if (is.null(emp_obj)) {
      # Try direct conversion
      if (inherits(values$emp_data, "MultiAssayExperiment")) {
        tryCatch({
          emp_obj <- EasyMultiProfiler:::.as.EMPT(values$emp_data, experiment = input$summary_experiment)
        }, error = function(e) {
          # Silently fail for display
        })
      }
    }
    if (is.null(emp_obj)) {
      return(data.frame(Message = "Could not load metadata. Try generating summary first."))
    }
    col_data <- as.data.frame(SummarizedExperiment::colData(emp_obj))
    return(col_data)
  }, error = function(e) {
    return(data.frame(Message = paste("Error:", e$message)))
  })
}, options = list(pageLength = 10, scrollX = TRUE))

# Display experiment type badge
output$experiment_type_badge <- renderUI({
  req(input$summary_experiment)
  req(values$emp_data)
  
  exp_type <- values$experiment_types[[input$summary_experiment]]
  if (is.null(exp_type)) {
    exp_type <- detect_experiment_type(values$emp_data, input$summary_experiment)
    values$experiment_types[[input$summary_experiment]] <- exp_type
  }
  
  # Map types to display names and colors
  type_info <- switch(exp_type,
    "microbiome" = list(name = "16S/Metagenomics", color = "primary", icon = "dna"),
    "rnaseq" = list(name = "RNAseq", color = "success", icon = "dna"),
    "proteomics" = list(name = "Proteomics", color = "warning", icon = "flask"),
    "metabolomics" = list(name = "Metabolomics", color = "info", icon = "atom"),
    "functional" = list(name = "Functional", color = "purple", icon = "sitemap"),
    "clinical" = list(name = "Clinical", color = "secondary", icon = "user-md"),
    list(name = "Unknown", color = "default", icon = "question")
  )
  
  tags$span(
    class = paste0("label label-", type_info$color),
    style = "font-size: 14px; padding: 5px 10px;",
    icon(type_info$icon),
    " ",
    type_info$name
  )
})

# Display available analyses info
output$available_analyses_info <- renderUI({
  req(input$summary_experiment)
  req(values$emp_data)
  
  exp_type <- values$experiment_types[[input$summary_experiment]]
  if (is.null(exp_type)) {
    exp_type <- detect_experiment_type(values$emp_data, input$summary_experiment)
    values$experiment_types[[input$summary_experiment]] <- exp_type
  }
  
  analyses <- get_available_analyses(exp_type)
  
  tagList(
    h5("Available for this experiment type:"),
    tags$strong("Analyses: "),
    tags$span(paste(analyses$analysis, collapse = ", ")),
    br(),
    tags$strong("Visualizations: "),
    tags$span(paste(analyses$visualization, collapse = ", "))
  )
})

# Display feature annotations
output$feature_annotations_table <- DT::renderDataTable({
  req(input$summary_experiment)
  req(values$emp_data)
  
  # Validate experiment exists
  if (!input$summary_experiment %in% names(values$emp_data)) {
    return(data.frame(Message = paste("Experiment", input$summary_experiment, "not found")))
  }
  
  tryCatch({
    emp_obj <- get_empt(input$summary_experiment)
    if (is.null(emp_obj)) {
      # Try direct conversion
      if (inherits(values$emp_data, "MultiAssayExperiment")) {
        tryCatch({
          emp_obj <- EasyMultiProfiler:::.as.EMPT(values$emp_data, experiment = input$summary_experiment)
        }, error = function(e) {
          # Silently fail for display
        })
      }
    }
    if (is.null(emp_obj)) {
      return(data.frame(Message = "Could not load annotations. Try generating summary first."))
    }
    row_data <- as.data.frame(SummarizedExperiment::rowData(emp_obj))
    return(row_data)
  }, error = function(e) {
    return(data.frame(Message = paste("Error:", e$message)))
  })
}, options = list(pageLength = 10, scrollX = TRUE))
