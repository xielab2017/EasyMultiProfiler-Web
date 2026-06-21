# Sample Metadata Mapping Server Logic

# Reactive value to store uploaded metadata
sample_metadata_raw <- reactiveVal(NULL)

# Auto-preview when file is uploaded
observeEvent(input$sample_metadata_file, {
  req(input$sample_metadata_file)
  
  # Trigger preview automatically
  shinyjs::click("sample_metadata_preview_btn")
})

# Update experiment choices
observe({
  if (!is.null(values$emp_data)) {
    exp_names <- names(values$emp_data)
    updateSelectInput(session, "sample_metadata_experiment", 
      choices = c("None" = "", exp_names))
  }
})

# Auto-detect separator helper
auto_detect_separator <- function(filepath) {
  first_line <- readLines(filepath, n = 1)
  if (grepl("\t", first_line)) {
    return("\t")
  } else if (grepl(",", first_line)) {
    return(",")
  } else if (grepl(";", first_line)) {
    return(";")
  } else {
    return(",")  # default
  }
}

# Preview uploaded file
observeEvent(input$sample_metadata_preview_btn, {
  req(input$sample_metadata_file)
  
  tryCatch({
    # Auto-detect separator if not specified
    sep <- input$sample_metadata_sep
    if (sep == "auto") {
      sep <- auto_detect_separator(input$sample_metadata_file$datapath)
    }
    
    # Read the file
    metadata_df <- read.table(
      input$sample_metadata_file$datapath,
      sep = sep,
      header = input$sample_metadata_header,
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
    
    # Store for later use
    sample_metadata_raw(metadata_df)
    
    # Update primary column choices
    updateSelectInput(session, "sample_metadata_primary_col",
      choices = names(metadata_df),
      selected = names(metadata_df)[1]
    )
    
    showNotification("File loaded successfully!", type = "message")
  }, error = function(e) {
    showNotification(paste("Error loading file:", e$message), type = "error")
  })
})

# Display preview
output$sample_metadata_preview <- DT::renderDataTable({
  if (is.null(sample_metadata_raw())) {
    return(data.frame(Message = "Please upload and preview a file first."))
  }
  
  metadata_df <- sample_metadata_raw()
  return(metadata_df)
}, options = list(pageLength = 10, scrollX = TRUE))

# Transform and apply metadata
observeEvent(input$sample_metadata_transform_btn, {
  req(sample_metadata_raw())
  req(input$sample_metadata_primary_col)
  
  tryCatch({
    # Re-read file if needed (in case separator changed)
    if (is.null(sample_metadata_raw())) {
      sep <- input$sample_metadata_sep
      if (sep == "auto") {
        sep <- auto_detect_separator(input$sample_metadata_file$datapath)
      }
      metadata_df <- read.table(
        input$sample_metadata_file$datapath,
        sep = sep,
        header = input$sample_metadata_header,
        stringsAsFactors = FALSE,
        check.names = FALSE
      )
    } else {
      metadata_df <- sample_metadata_raw()
    }
    
    # Check if primary column exists
    if (!input$sample_metadata_primary_col %in% names(metadata_df)) {
      showNotification("Primary column not found in metadata!", type = "error")
      return()
    }
    
    # Rename primary column to 'primary' for EMP format
    metadata_transformed <- metadata_df
    names(metadata_transformed)[names(metadata_transformed) == input$sample_metadata_primary_col] <- "primary"
    
    # Ensure primary column is character
    metadata_transformed$primary <- as.character(metadata_transformed$primary)
    
    # Remove any rows with NA in primary column
    metadata_transformed <- metadata_transformed[!is.na(metadata_transformed$primary), ]
    
    # Check for duplicate primary values
    if (any(duplicated(metadata_transformed$primary))) {
      showNotification("Warning: Duplicate sample IDs found! Only first occurrence will be kept.", 
        type = "warning")
      metadata_transformed <- metadata_transformed[!duplicated(metadata_transformed$primary), ]
    }
    
    # Store transformed metadata
    values$sample_metadata_transformed <- metadata_transformed
    
    # If adding to existing experiment
    if (!is.null(input$sample_metadata_experiment) && input$sample_metadata_experiment != "") {
      # Add metadata to existing MAE
      if (is.null(values$emp_data)) {
        showNotification("No data available. Please import data first.", type = "error")
        return()
      }
      
      # Get existing colData
      existing_coldata <- EMP_coldata_extract(
        values$emp_data,
        experiment = input$sample_metadata_experiment,
        action = "get"
      )
      
      # Merge with new metadata
      if ("primary" %in% names(existing_coldata)) {
        # Merge on primary column
        merged_coldata <- dplyr::full_join(
          existing_coldata,
          metadata_transformed,
          by = "primary"
        )
      } else {
        # If existing doesn't have primary, add it from rownames
        existing_coldata$primary <- rownames(existing_coldata)
        merged_coldata <- dplyr::full_join(
          existing_coldata,
          metadata_transformed,
          by = "primary"
        )
      }
      
      # Update colData in MAE
      # This requires updating the MultiAssayExperiment object
      # We'll use EMP_mutate or similar function if available
      # For now, we'll create a new experiment with merged metadata
      
      # Create new experiment with metadata as assay
      new_experiment_name <- paste0(input$sample_metadata_experiment, "_metadata")
      
      # Use EMP_coldata_extract with action='add' to create new experiment
      metadata_empt <- EMP_coldata_extract(
        values$emp_data,
        experiment = input$sample_metadata_experiment,
        coldata_to_assay = NULL,  # Use all numeric columns, or NULL for all
        assay_name = "metadata",
        action = "add"
      )
      
      # Add to MAE
      if (inherits(values$emp_data, "MultiAssayExperiment")) {
        # Add the metadata experiment
        values$emp_data[[new_experiment_name]] <- metadata_empt@assays[[1]]
        
        # Update colData
        colData(values$emp_data) <- S4Vectors::DataFrame(merged_coldata)
      }
      
      showNotification(paste("Metadata added to experiment:", input$sample_metadata_experiment), 
        type = "message")
      
    } else {
      # Create new experiment from metadata
      experiment_name <- input$sample_metadata_experiment_name
      if (experiment_name == "") {
        experiment_name <- "metadata"
      }
      
      # Create a new MAE or add to existing
      if (is.null(values$emp_data)) {
        # Create new MAE with metadata
        # Convert metadata to SummarizedExperiment format
        # Use numeric columns as assay, or create dummy assay
        numeric_cols <- sapply(metadata_transformed, is.numeric)
        
        if (any(numeric_cols)) {
          assay_data <- as.matrix(metadata_transformed[, numeric_cols, drop = FALSE])
          rownames(assay_data) <- metadata_transformed$primary
          assay_data <- t(assay_data)
        } else {
          # Create dummy assay if no numeric columns
          assay_data <- matrix(1, nrow = 1, ncol = nrow(metadata_transformed))
          rownames(assay_data) <- "dummy"
          colnames(assay_data) <- metadata_transformed$primary
        }
        
        # Create rowData
        rowdata <- data.frame(
          feature = rownames(assay_data),
          Name = rownames(assay_data)
        )
        
        # Create colData
        coldata <- metadata_transformed
        rownames(coldata) <- coldata$primary
        
        # Create SummarizedExperiment
        se <- SummarizedExperiment::SummarizedExperiment(
          assays = list(counts = assay_data),
          rowData = rowdata,
          colData = coldata
        )
        
        # Create MAE
        values$emp_data <- MultiAssayExperiment::MultiAssayExperiment(
          experiments = list(metadata = se),
          colData = S4Vectors::DataFrame(coldata)
        )
      } else {
        # Add to existing MAE
        # Similar process but add to existing MAE
        numeric_cols <- sapply(metadata_transformed, is.numeric)
        
        if (any(numeric_cols)) {
          assay_data <- as.matrix(metadata_transformed[, numeric_cols, drop = FALSE])
          rownames(assay_data) <- metadata_transformed$primary
          assay_data <- t(assay_data)
        } else {
          assay_data <- matrix(1, nrow = 1, ncol = nrow(metadata_transformed))
          rownames(assay_data) <- "dummy"
          colnames(assay_data) <- metadata_transformed$primary
        }
        
        rowdata <- data.frame(
          feature = rownames(assay_data),
          Name = rownames(assay_data)
        )
        
        coldata <- metadata_transformed
        rownames(coldata) <- coldata$primary
        
        se <- SummarizedExperiment::SummarizedExperiment(
          assays = list(counts = assay_data),
          rowData = rowdata,
          colData = coldata
        )
        
        # Add to existing MAE
        values$emp_data[[experiment_name]] <- se
        
        # Update colData - merge with existing
        existing_coldata <- as.data.frame(colData(values$emp_data))
        if ("primary" %in% names(existing_coldata)) {
          merged_coldata <- dplyr::full_join(
            existing_coldata,
            metadata_transformed,
            by = "primary"
          )
        } else {
          existing_coldata$primary <- rownames(existing_coldata)
          merged_coldata <- dplyr::full_join(
            existing_coldata,
            metadata_transformed,
            by = "primary"
          )
        }
        rownames(merged_coldata) <- merged_coldata$primary
        colData(values$emp_data) <- S4Vectors::DataFrame(merged_coldata)
      }
      
      showNotification(paste("New experiment created:", experiment_name), type = "message")
    }
    
    # Update status
    output$sample_metadata_status <- renderText({
      paste("Metadata successfully transformed and applied!\n",
            "Samples:", nrow(metadata_transformed), "\n",
            "Metadata columns:", ncol(metadata_transformed) - 1)
    })
    
  }, error = function(e) {
    showNotification(paste("Error transforming metadata:", e$message), type = "error")
    output$sample_metadata_status <- renderText({
      paste("Error:", e$message)
    })
  })
})

# Display transformed metadata
output$sample_metadata_transformed <- DT::renderDataTable({
  if (is.null(values$sample_metadata_transformed)) {
    return(data.frame(Message = "Transform metadata to see the result."))
  }
  
  return(values$sample_metadata_transformed)
}, options = list(pageLength = 10, scrollX = TRUE))
