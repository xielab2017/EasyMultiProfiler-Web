# Data Preparation Server Logic

# Update experiment choices for all preparation modules
observe({
  if (!is.null(values$emp_data)) {
    exp_names <- names(values$emp_data)
    updateSelectInput(session, "filter_experiment", choices = exp_names)
    updateSelectInput(session, "normalize_experiment", choices = exp_names)
    updateSelectInput(session, "impute_experiment", choices = exp_names)
    updateSelectInput(session, "rarefy_experiment", choices = exp_names)
    updateSelectInput(session, "collapse_experiment", choices = exp_names)
    updateSelectInput(session, "feature_convert_experiment", choices = exp_names)
    
    # Update current experiment
    if (is.null(values$current_experiment) && length(exp_names) > 0) {
      values$current_experiment <- exp_names[1]
    }
  }
})

# Update current experiment when user selects in preparation modules
observeEvent(input$filter_experiment, {
  if (!is.null(input$filter_experiment)) values$current_experiment <- input$filter_experiment
})
observeEvent(input$normalize_experiment, {
  if (!is.null(input$normalize_experiment)) values$current_experiment <- input$normalize_experiment
})
observeEvent(input$impute_experiment, {
  if (!is.null(input$impute_experiment)) values$current_experiment <- input$impute_experiment
})
observeEvent(input$rarefy_experiment, {
  if (!is.null(input$rarefy_experiment)) values$current_experiment <- input$rarefy_experiment
})
observeEvent(input$collapse_experiment, {
  if (!is.null(input$collapse_experiment)) values$current_experiment <- input$collapse_experiment
})
observeEvent(input$feature_convert_experiment, {
  if (!is.null(input$feature_convert_experiment)) values$current_experiment <- input$feature_convert_experiment
})

# Filter Data
observeEvent(input$filter_btn, {
  req(input$filter_experiment)
  req(values$emp_data)
  
  tryCatch({
    # Get EMPT object first
    empt <- get_empt(input$filter_experiment)
    if (is.null(empt)) {
      showNotification("Could not convert data to EMPT format", type = "error")
      return()
    }
    
    # Get assay data
    if (is.null(empt)) {
      showNotification("Could not convert data to EMPT format", type = "error")
      return()
    }
    
    assay_data <- SummarizedExperiment::assays(empt)[[1]]
    row_data <- SummarizedExperiment::rowData(empt)
    
    # Calculate feature statistics and add to rowData
    if (input$filter_min_count > 0 || input$filter_min_samples > 0 || input$filter_max_na < 1) {
      # Calculate max count per feature
      max_counts <- apply(assay_data, 1, function(x) max(x, na.rm = TRUE))
      # Calculate number of samples with non-zero values per feature
      n_samples <- apply(assay_data, 1, function(x) sum(x > 0, na.rm = TRUE))
      # Calculate NA proportion per feature
      na_props <- apply(assay_data, 1, function(x) sum(is.na(x)) / length(x))
      
      # Add to rowData
      row_data$max_count <- max_counts
      row_data$n_samples <- n_samples
      row_data$na_prop <- na_props
      
      SummarizedExperiment::rowData(empt) <- row_data
    }
    
    # Update the MAE with the modified rowData
    if (input$filter_min_count > 0 || input$filter_min_samples > 0 || input$filter_max_na < 1) {
      exp_obj <- values$emp_data[[input$filter_experiment]]
      SummarizedExperiment::rowData(exp_obj) <- row_data
      values$emp_data[[input$filter_experiment]] <- exp_obj
    }
    
    # Filter features based on calculated stats
    feature_ids_to_keep <- rownames(assay_data)
    if (input$filter_min_count > 0 || input$filter_min_samples > 0 || input$filter_max_na < 1) {
      keep_features <- rep(TRUE, nrow(assay_data))
      if (input$filter_min_count > 0) {
        keep_features <- keep_features & (max_counts >= input$filter_min_count)
      }
      if (input$filter_min_samples > 0) {
        keep_features <- keep_features & (n_samples >= input$filter_min_samples)
      }
      if (input$filter_max_na < 1) {
        keep_features <- keep_features & (na_props <= input$filter_max_na)
      }
      feature_ids_to_keep <- rownames(assay_data)[keep_features]
    }
    
    # Get sample IDs to keep based on sample condition
    exp_obj <- values$emp_data[[input$filter_experiment]]
    col_data <- SummarizedExperiment::colData(exp_obj)
    sample_ids_to_keep <- rownames(col_data)
    
    if (nchar(trimws(input$filter_sample_condition)) > 0) {
      # Evaluate sample condition in the context of colData
      sample_expr <- parse(text = input$filter_sample_condition)
      sample_mask <- tryCatch({
        eval(sample_expr, envir = as.data.frame(col_data))
      }, error = function(e) {
        showNotification(paste("Error evaluating sample condition:", e$message), type = "error")
        return(rep(TRUE, nrow(col_data)))
      })
      sample_ids_to_keep <- rownames(col_data)[sample_mask]
    }
    
    # Apply filters using EMP_filter with filterFeature and filterSample
    # This avoids the enquo issue
    if (length(feature_ids_to_keep) < nrow(assay_data) || length(sample_ids_to_keep) < nrow(col_data)) {
      result <- EMP_filter(
        obj = values$emp_data,
        experiment = input$filter_experiment,
        sample_condition = 1 == 1,  # Dummy condition
        feature_condition = 1 == 1,  # Dummy condition
        filterFeature = feature_ids_to_keep,
        filterSample = sample_ids_to_keep,
        action = "select"
      )
    } else {
      result <- values$emp_data
    }
    
    if (!is.null(result)) {
      values$emp_data <- result
      showNotification("Filter applied successfully", type = "message")
      output$filter_status <- renderText("Filter applied successfully")
    } else {
      showNotification("Filter failed", type = "error")
      output$filter_status <- renderText("Filter failed")
    }
  }, error = function(e) {
    showNotification(paste("Filter error:", e$message), type = "error")
    output$filter_status <- renderText(paste("Error:", e$message))
  })
})

# Normalize Data
observeEvent(input$normalize_btn, {
  req(input$normalize_experiment)
  req(values$emp_data)
  
  tryCatch({
    # Get EMPT object
    empt <- get_empt(input$normalize_experiment)
    if (is.null(empt)) {
      showNotification("Could not convert data to EMPT format", type = "error")
      return()
    }
    
    # Handle bySample parameter
    by_sample <- if (input$normalize_bySample == "default") {
      "default"
    } else if (input$normalize_bySample == "TRUE") {
      TRUE
    } else {
      FALSE
    }
    
    # Apply normalization
    result <- EMP_decostand(
      obj = empt,
      experiment = input$normalize_experiment,
      method = input$normalize_method,
      bySample = by_sample,
      logbase = input$normalize_logbase,
      pseudocount = input$normalize_pseudocount,
      use_cached = input$normalize_use_cached
    )
    
    if (!is.null(result)) {
      # Convert back to MAE if needed
      if (inherits(result, "EMPT")) {
        # Update the experiment in MAE
        if (inherits(values$emp_data, "MultiAssayExperiment")) {
          # Extract the updated assay and rowData
          new_assay <- SummarizedExperiment::assays(result)[[1]]
          new_rowdata <- SummarizedExperiment::rowData(result)
          new_coldata <- SummarizedExperiment::colData(result)
          
          # Update the experiment
          exp_obj <- values$emp_data[[input$normalize_experiment]]
          SummarizedExperiment::assays(exp_obj)[[1]] <- new_assay
          SummarizedExperiment::rowData(exp_obj) <- new_rowdata
          SummarizedExperiment::colData(exp_obj) <- new_coldata
          
          values$emp_data[[input$normalize_experiment]] <- exp_obj
        }
      }
      
      showNotification("Normalization applied successfully", type = "message")
      output$normalize_status <- renderText("Normalization applied successfully")
    } else {
      showNotification("Normalization failed", type = "error")
      output$normalize_status <- renderText("Normalization failed")
    }
  }, error = function(e) {
    showNotification(paste("Normalization error:", e$message), type = "error")
    output$normalize_status <- renderText(paste("Error:", e$message))
  })
})

# Impute Missing Values
observeEvent(input$impute_btn, {
  req(input$impute_experiment)
  req(values$emp_data)
  
  tryCatch({
    # Apply imputation
    result <- EMP_impute(
      obj = values$emp_data,
      experiment = input$impute_experiment,
      use_cached = input$impute_use_cached
    )
    
    if (!is.null(result)) {
      values$emp_data <- result
      showNotification("Imputation applied successfully", type = "message")
      output$impute_status <- renderText("Imputation applied successfully")
    } else {
      showNotification("Imputation failed", type = "error")
      output$impute_status <- renderText("Imputation failed")
    }
  }, error = function(e) {
    showNotification(paste("Imputation error:", e$message), type = "error")
    output$impute_status <- renderText(paste("Error:", e$message))
  })
})

# Rarefy Data
observeEvent(input$rarefy_btn, {
  req(input$rarefy_experiment)
  req(values$emp_data)
  
  tryCatch({
    # Get EMPT object
    empt <- get_empt(input$rarefy_experiment)
    if (is.null(empt)) {
      showNotification("Could not convert data to EMPT format", type = "error")
      return()
    }
    
    # Apply rarefaction
    result <- EMP_rrarefy(
      obj = empt,
      experiment = input$rarefy_experiment,
      raresize = input$rarefy_sample_size,
      use_cached = input$rarefy_use_cached
    )
    
    if (!is.null(result)) {
      # Convert back to MAE if needed
      if (inherits(result, "EMPT")) {
        # Update the experiment in MAE
        if (inherits(values$emp_data, "MultiAssayExperiment")) {
          # Extract the updated assay and rowData
          new_assay <- SummarizedExperiment::assays(result)[[1]]
          new_rowdata <- SummarizedExperiment::rowData(result)
          new_coldata <- SummarizedExperiment::colData(result)
          
          # Update the experiment
          exp_obj <- values$emp_data[[input$rarefy_experiment]]
          SummarizedExperiment::assays(exp_obj)[[1]] <- new_assay
          SummarizedExperiment::rowData(exp_obj) <- new_rowdata
          SummarizedExperiment::colData(exp_obj) <- new_coldata
          
          values$emp_data[[input$rarefy_experiment]] <- exp_obj
        }
      }
      
      showNotification("Rarefaction applied successfully", type = "message")
      output$rarefy_status <- renderText("Rarefaction applied successfully")
    } else {
      showNotification("Rarefaction failed", type = "error")
      output$rarefy_status <- renderText("Rarefaction failed")
    }
  }, error = function(e) {
    showNotification(paste("Rarefaction error:", e$message), type = "error")
    output$rarefy_status <- renderText(paste("Error:", e$message))
  })
})

# Collapse Features
observeEvent(input$collapse_btn, {
  req(input$collapse_experiment)
  req(values$emp_data)
  
  tryCatch({
    # Get EMPT object
    empt <- get_empt(input$collapse_experiment)
    if (is.null(empt)) {
      showNotification("Could not convert data to EMPT format", type = "error")
      return()
    }
    
    # Apply collapse
    result <- EMP_collapse(
      obj = empt,
      experiment = input$collapse_experiment,
      estimate_group = input$collapse_level,
      method = input$collapse_method,
      use_cached = input$collapse_use_cached
    )
    
    if (!is.null(result)) {
      # Convert back to MAE if needed
      if (inherits(result, "EMPT")) {
        # Update the experiment in MAE
        if (inherits(values$emp_data, "MultiAssayExperiment")) {
          # Extract the updated assay and rowData
          new_assay <- SummarizedExperiment::assays(result)[[1]]
          new_rowdata <- SummarizedExperiment::rowData(result)
          new_coldata <- SummarizedExperiment::colData(result)
          
          # Update the experiment
          exp_obj <- values$emp_data[[input$collapse_experiment]]
          SummarizedExperiment::assays(exp_obj)[[1]] <- new_assay
          SummarizedExperiment::rowData(exp_obj) <- new_rowdata
          SummarizedExperiment::colData(exp_obj) <- new_coldata
          
          values$emp_data[[input$collapse_experiment]] <- exp_obj
        }
      }
      
      showNotification("Collapse applied successfully", type = "message")
      output$collapse_status <- renderText("Collapse applied successfully")
    } else {
      showNotification("Collapse failed", type = "error")
      output$collapse_status <- renderText("Collapse failed")
    }
  }, error = function(e) {
    showNotification(paste("Collapse error:", e$message), type = "error")
    output$collapse_status <- renderText(paste("Error:", e$message))
  })
})

# Feature Convert
observeEvent(input$feature_convert_btn, {
  req(input$feature_convert_experiment)
  req(values$emp_data)
  req(input$feature_convert_from)
  req(input$feature_convert_to)
  
  tryCatch({
    # Get EMPT object
    empt <- get_empt(input$feature_convert_experiment)
    if (is.null(empt)) {
      showNotification("Could not convert data to EMPT format", type = "error")
      return()
    }
    
    # Apply feature conversion
    # EMP_feature_convert accepts species or OrgDb, not organism
    # It doesn't have use_cached parameter
    if (input$feature_convert_species == "custom") {
      # Use OrgDb for custom species
      if (!is.null(input$feature_convert_orgdb) && nchar(trimws(input$feature_convert_orgdb)) > 0) {
        # Try to load the OrgDb
        orgdb_name <- trimws(input$feature_convert_orgdb)
        if (requireNamespace(orgdb_name, quietly = TRUE)) {
          # Load OrgDb object
          orgdb_pkg <- asNamespace(orgdb_name)
          OrgDb <- get(orgdb_name, envir = orgdb_pkg)
          result <- EMP_feature_convert(
            obj = empt,
            experiment = input$feature_convert_experiment,
            from = input$feature_convert_from,
            to = input$feature_convert_to,
            OrgDb = OrgDb
          )
        } else {
          showNotification(paste("Please install", orgdb_name, ": BiocManager::install('", orgdb_name, "')"), 
                          type = "error")
          return()
        }
      } else {
        showNotification("Please provide a valid OrgDb name", type = "error")
        return()
      }
    } else {
      # Use built-in species (Human, Mouse, Pig, Zebrafish)
      result <- EMP_feature_convert(
        obj = empt,
        experiment = input$feature_convert_experiment,
        from = input$feature_convert_from,
        to = input$feature_convert_to,
        species = input$feature_convert_species
      )
    }
    
    if (!is.null(result)) {
      # Convert back to MAE if needed
      if (inherits(result, "EMPT")) {
        # Update the experiment in MAE
        if (inherits(values$emp_data, "MultiAssayExperiment")) {
          # Extract the updated assay and rowData
          new_assay <- SummarizedExperiment::assays(result)[[1]]
          new_rowdata <- SummarizedExperiment::rowData(result)
          new_coldata <- SummarizedExperiment::colData(result)
          
          # Update the experiment
          exp_obj <- values$emp_data[[input$feature_convert_experiment]]
          # Use withDimnames=FALSE to avoid rownames/colnames mismatch
          SummarizedExperiment::assays(exp_obj, withDimnames=FALSE)[[1]] <- new_assay
          SummarizedExperiment::rowData(exp_obj) <- new_rowdata
          SummarizedExperiment::colData(exp_obj) <- new_coldata
          
          values$emp_data[[input$feature_convert_experiment]] <- exp_obj
        }
      }
      
      showNotification("Feature conversion applied successfully", type = "message")
      output$feature_convert_status <- renderText("Feature conversion applied successfully")
    } else {
      showNotification("Feature conversion failed", type = "error")
      output$feature_convert_status <- renderText("Feature conversion failed")
    }
  }, error = function(e) {
    showNotification(paste("Feature conversion error:", e$message), type = "error")
    output$feature_convert_status <- renderText(paste("Error:", e$message))
  })
})
