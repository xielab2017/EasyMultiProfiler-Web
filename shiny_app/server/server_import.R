# Data Import Server Logic - Simplified with Auto-Detection

# Reactive values for detection
detection_results <- reactiveValues(
  file_data = NULL,
  feature_col = NULL,
  sample_cols = NULL,
  detected_format = NULL,
  detected_type = NULL,
  detected_level = NULL,
  detected_sep = NULL,
  metadata_preview = NULL
)

# Helper function to detect file separator
detect_file_separator <- function(filepath) {
  first_line <- readLines(filepath, n = 3, warn = FALSE)
  if (length(first_line) > 0) {
    if (grepl("\t", first_line[1])) return("\t")
    if (grepl(",", first_line[1])) return(",")
    if (grepl(";", first_line[1])) return(";")
  }
  return("\t")
}

# Auto-detect feature and sample columns
auto_detect_columns <- function(data_df) {
  # Check if first column is numeric and looks like row index (1, 2, 3, ...)
  first_col <- data_df[[1]]
  first_col_numeric <- is.numeric(first_col)
  is_index <- FALSE
  
  # Check for common index column names (case-insensitive)
  first_col_name <- tolower(names(data_df)[1])
  if (first_col_name %in% c("index", "x", "row", "id", "rowid", "row.id", "rownames")) {
    is_index <- TRUE
  } else if (first_col_numeric && length(unique(first_col)) == nrow(data_df)) {
    # Check if it's sequential (likely index)
    if (all(diff(as.numeric(first_col)) == 1, na.rm = TRUE) || 
        all(first_col == 1:nrow(data_df), na.rm = TRUE)) {
      is_index <- TRUE
    }
  } else if (!first_col_numeric) {
    # If first column is character and looks like row numbers (e.g., "1", "2", "3")
    if (all(grepl("^\\d+$", as.character(first_col)), na.rm = TRUE)) {
      numeric_vals <- as.numeric(first_col)
      if (all(diff(numeric_vals) == 1, na.rm = TRUE) || 
          all(numeric_vals == 1:nrow(data_df), na.rm = TRUE)) {
        is_index <- TRUE
      }
    }
  }
  
  if (is_index) {
    # First column is index, second column is likely features
    feature_col_idx <- 2
    sample_start_idx <- 3
  } else {
    # First column is likely features
    feature_col_idx <- 1
    sample_start_idx <- 2
  }
  
  # Identify sample columns (numeric columns after feature column)
  numeric_cols <- sapply(data_df, is.numeric)
  
  # Get numeric columns starting from sample_start_idx
  if (sample_start_idx <= ncol(data_df)) {
    sample_indices <- which(numeric_cols[sample_start_idx:length(numeric_cols)]) + (sample_start_idx - 1)
  } else {
    sample_indices <- integer(0)
  }
  
  # If no numeric columns found, assume all columns after feature are samples
  if (length(sample_indices) == 0 && sample_start_idx <= ncol(data_df)) {
    sample_indices <- sample_start_idx:ncol(data_df)
  }
  
  return(list(
    feature_col = names(data_df)[feature_col_idx],
    feature_idx = feature_col_idx,
    sample_cols = names(data_df)[sample_indices],
    sample_indices = sample_indices,
    has_index = is_index
  ))
}

# Auto-detect taxonomy level and separator
auto_detect_taxonomy <- function(feature_values) {
  # Check for common separators
  if (any(grepl(";", feature_values))) {
    sep <- ";"
  } else if (any(grepl("\\|", feature_values))) {
    sep <- "|"
  } else {
    sep <- ";"
  }
  
  # Count taxonomy levels
  if (length(feature_values) > 0) {
    levels <- strsplit(feature_values[1], sep)[[1]]
    level_count <- length(levels)
    
    # Map to taxonomy level
    level_map <- c("Domain", "Kindom", "Phylum", "Class", "Order", "Family", "Genus", "Species", "Strain")
    if (level_count <= length(level_map)) {
      detected_level <- level_map[level_count]
    } else {
      detected_level <- "Species"
    }
  } else {
    detected_level <- "Species"
  }
  
  return(list(sep = sep, level = detected_level))
}

# Preview and auto-detect
observeEvent(input$preview_data_btn, {
  req(input$data_file)
  
  tryCatch({
    file_ext <- tolower(tools::file_ext(input$data_file$name))
    
    # Detect format
    if (file_ext == "biom") {
      detection_results$detected_format <- "biom"
      showNotification("BIOM format detected. Preview not available for BIOM files.", type = "message")
      return()
    } else if (file_ext == "qzv") {
      detection_results$detected_format <- "qzv"
      showNotification("QZV format detected. Preview not available for QZV files.", type = "message")
      return()
    } else {
      detection_results$detected_format <- NULL
    }
    
    # Read file
    file_sep <- detect_file_separator(input$data_file$datapath)
    data_df <- read.table(
      input$data_file$datapath,
      header = TRUE,
      sep = file_sep,
      nrows = 100,  # Read first 100 rows for preview
      stringsAsFactors = FALSE,
      check.names = FALSE,
      comment.char = ""
    )
    
    # Auto-detect columns
    col_info <- auto_detect_columns(data_df)
    detection_results$file_data <- data_df
    detection_results$feature_col <- col_info$feature_col
    detection_results$sample_cols <- col_info$sample_cols
    
    # Auto-detect taxonomy if applicable
    if (input$data_type_import == "tax" && col_info$feature_idx <= ncol(data_df)) {
      feature_values <- data_df[[col_info$feature_col]]
      tax_info <- auto_detect_taxonomy(feature_values)
      detection_results$detected_sep <- tax_info$sep
      detection_results$detected_level <- tax_info$level
      
      # Update UI
      updateSelectInput(session, "start_level_import", selected = tax_info$level)
      updateTextInput(session, "tax_sep_import", value = tax_info$sep)
    }
    
    # Auto-detect assay name (check if values are 0-1 range = relative abundance)
    if (length(col_info$sample_indices) > 0) {
      sample_col_name <- col_info$sample_cols[1]
      if (sample_col_name %in% names(data_df)) {
        sample_data <- data_df[[sample_col_name]]
        # Convert to numeric if needed
        if (!is.numeric(sample_data)) {
          sample_data <- as.numeric(as.character(sample_data))
          sample_data <- sample_data[!is.na(sample_data)]
        }
        if (length(sample_data) > 0) {
          max_val <- max(sample_data, na.rm = TRUE)
          if (max_val <= 1 && max_val > 0) {
            assay_name <- "relative_abundance"
          } else {
            assay_name <- "counts"
          }
          updateTextInput(session, "assay_name_import", value = assay_name)
        }
      }
    }
    
    # Auto-detect experiment name from filename
    exp_name <- gsub("\\.[^.]+$", "", basename(input$data_file$name))
    exp_name <- gsub("[^A-Za-z0-9_]", "_", exp_name)
    if (exp_name == "") exp_name <- "experiment"
    updateTextInput(session, "experiment_name_import", value = exp_name)
    
    showNotification("File previewed and settings auto-detected!", type = "message")
    
  }, error = function(e) {
    showNotification(paste("Preview error:", e$message), type = "error")
  })
})

# Display preview
output$data_preview <- DT::renderDataTable({
  if (is.null(detection_results$file_data)) {
    return(data.frame(Message = "Click 'Preview & Auto-Detect' to see your file."))
  }
  return(detection_results$file_data)
}, options = list(pageLength = 10, scrollX = TRUE))

# Display detection info
output$detection_info <- renderText({
  if (is.null(detection_results$file_data)) {
    return("No file previewed yet.")
  }
  
  info <- c()
  info <- c(info, paste("Detected Format:", if(is.null(detection_results$detected_format)) "CSV/TSV" else toupper(detection_results$detected_format)))
  info <- c(info, paste("Feature Column:", detection_results$feature_col))
  info <- c(info, paste("Sample Columns:", length(detection_results$sample_cols), "detected"))
  if (!is.null(detection_results$detected_level)) {
    info <- c(info, paste("Taxonomy Level:", detection_results$detected_level))
    info <- c(info, paste("Taxonomy Separator:", detection_results$detected_sep))
  }
  
  return(paste(info, collapse = "\n"))
})

# Import data
observeEvent(input$import_data_btn, {
  req(input$data_file)
  
  tryCatch({
    file_ext <- tolower(tools::file_ext(input$data_file$name))
    
    # Get settings
    exp_name <- input$experiment_name_import
    if (exp_name == "" || is.null(exp_name)) {
      exp_name <- gsub("\\.[^.]+$", "", basename(input$data_file$name))
      if (exp_name == "") exp_name <- "experiment"
    }
    
    assay_name <- input$assay_name_import
    if (assay_name == "" || is.null(assay_name)) {
      assay_name <- "counts"
    }
    
    data_type <- input$data_type_import
    
    # Handle different data types
    if (data_type == "tax") {
      # Taxonomy import
      if (file_ext == "biom") {
        result <- EMP_taxonomy_import(
          file = input$data_file$datapath,
          file_format = "biom",
          start_level = input$start_level_import,
          assay_name = assay_name
        )
      } else if (file_ext == "qzv") {
        result <- EMP_taxonomy_import(
          file = input$data_file$datapath,
          file_format = "qzv",
          start_level = input$start_level_import,
          assay_name = assay_name
        )
      } else {
        # CSV/TSV - read and process
        file_sep <- detect_file_separator(input$data_file$datapath)
        data_df <- read.table(
          input$data_file$datapath,
          header = TRUE,
          sep = file_sep,
          stringsAsFactors = FALSE,
          check.names = FALSE,
          comment.char = ""
        )
        
        # Auto-detect and remove index column if present
        col_info <- auto_detect_columns(data_df)
        if (col_info$has_index) {
          data_df <- data_df[, -1, drop = FALSE]
          # Recalculate after removing index
          col_info <- auto_detect_columns(data_df)
        }
        
        # Ensure first column is feature (should be after index removal)
        if (names(data_df)[1] != "feature") {
          names(data_df)[1] <- "feature"
        }
        
        # Remove metadata columns (not sample columns)
        # Common metadata column names that should be removed
        metadata_patterns <- c(
          'absolute-filepath', 'filepath', 'file.path', 'path', 'filename', 'file.name',
          'sample.name', 'sample_name', 'sample.id', 'sample_id',
          'OTU ID', 'OTU.ID', 'OTU_ID', 'ASV ID', 'ASV.ID', 'ASV_ID',
          'index', 'X', 'rownames', 'row.names', 'rowid', 'row.id'
        )
        
        cols_to_remove <- c()
        for (col_name in names(data_df)) {
          col_lower <- tolower(col_name)
          # Check if column name matches metadata patterns
          if (col_lower %in% tolower(metadata_patterns)) {
            cols_to_remove <- c(cols_to_remove, col_name)
          }
          # Check if column contains file paths (starts with / or contains .fastq, .fq, .gz)
          else if (col_name != "feature" && nrow(data_df) > 0) {
            sample_vals <- as.character(data_df[[col_name]][1:min(5, nrow(data_df))])
            if (any(grepl("^/|.fastq|.fq|.gz$|.csv$|.tsv$", sample_vals, ignore.case = TRUE))) {
              cols_to_remove <- c(cols_to_remove, col_name)
            }
            # Check if column is mostly non-numeric (likely metadata)
            else if (!is.numeric(data_df[[col_name]])) {
              # Try to convert a sample to numeric
              test_vals <- suppressWarnings(as.numeric(as.character(sample_vals)))
              na_ratio <- sum(is.na(test_vals)) / length(test_vals)
              # If more than 80% can't be converted, it's likely metadata
              if (na_ratio > 0.8) {
                cols_to_remove <- c(cols_to_remove, col_name)
              }
            }
          }
        }
        
        # Remove identified metadata columns
        if (length(cols_to_remove) > 0) {
          for (col in cols_to_remove) {
            col_idx <- which(names(data_df) == col)
            if (length(col_idx) > 0 && col_idx != 1) {
              data_df <- data_df[, -col_idx, drop = FALSE]
            }
          }
          if (length(cols_to_remove) > 0) {
            showNotification(paste("Removed metadata columns:", paste(cols_to_remove, collapse = ", ")), 
              type = "message", duration = 3)
          }
        }
        
        # Convert ALL sample columns (everything after feature column) to numeric
        # This is critical - EMP_taxonomy_import does rowSums on temp[,-1] which must be numeric
        if (ncol(data_df) > 1) {
          for (col_idx in 2:ncol(data_df)) {
            col_name <- names(data_df)[col_idx]
            if (!is.numeric(data_df[[col_idx]])) {
              # Try to convert to numeric
              converted <- suppressWarnings(as.numeric(as.character(data_df[[col_idx]])))
              # If conversion succeeded (less than 20% NA), use converted values
              na_ratio <- sum(is.na(converted)) / length(converted)
              if (na_ratio < 0.2) {
                data_df[[col_idx]] <- converted
                # Replace any resulting NA with 0
                data_df[[col_idx]][is.na(data_df[[col_idx]])] <- 0
              } else {
                # If conversion failed, this is likely a metadata column - remove it
                showNotification(paste("Removing non-numeric column:", col_name), 
                  type = "warning", duration = 3)
                data_df <- data_df[, -col_idx, drop = FALSE]
                # Adjust loop counter since we removed a column
                col_idx <- col_idx - 1
                if (col_idx < 2) break
              }
            }
          }
        }
        
        # Final verification that all columns after feature are numeric
        if (ncol(data_df) > 1) {
          non_numeric <- which(!sapply(data_df[, -1, drop = FALSE], is.numeric))
          if (length(non_numeric) > 0) {
            # Remove any remaining non-numeric columns
            for (idx in rev(non_numeric)) {  # Reverse order to maintain indices
              showNotification(paste("Removing non-numeric column:", names(data_df)[idx + 1]), 
                type = "warning", duration = 3)
              data_df <- data_df[, -(idx + 1), drop = FALSE]
            }
          }
        }
        
        # Check if we have any sample columns left
        if (ncol(data_df) <= 1) {
          stop("No sample columns found after processing. Please check your file format.")
        }
        
        # Check if data needs to be transposed
        # EMP_taxonomy_import expects: rows = features, columns = samples
        # If first column contains sample-like names (A1, A2, etc.) and other columns are features,
        # we need to transpose
        first_col_values <- data_df[[1]]
        first_col_is_sample <- FALSE
        
        # Check if first column looks like sample IDs (short alphanumeric, not taxonomy strings)
        if (all(nchar(first_col_values) < 20) && 
            all(grepl("^[A-Za-z0-9_-]+$", first_col_values))) {
          # Check if column headers look like taxonomy strings (contain ; or |)
          col_headers <- names(data_df)[-1]
          if (length(col_headers) > 0 && 
              any(grepl("[;|]", col_headers[1:min(5, length(col_headers))]))) {
            first_col_is_sample <- TRUE
          }
        }
        
        if (first_col_is_sample) {
          # Data is transposed: samples in rows, features in columns
          # Need to transpose: use first column as row names, then transpose
          rownames(data_df) <- data_df[[1]]
          data_df <- data_df[, -1, drop = FALSE]  # Remove first column
          data_df <- as.data.frame(t(data_df))  # Transpose
          data_df <- tibble::rownames_to_column(data_df, "feature")
          showNotification("Detected transposed format (samples in rows). Transposing data...", 
            type = "message", duration = 3)
        }
        
        # Import using data parameter
        result <- EMP_taxonomy_import(
          data = data_df,
          file_format = NULL,
          start_level = input$start_level_import,
          sep = input$tax_sep_import,
          assay_name = assay_name
        )
      }
    } else if (data_type == "functional") {
      # Functional import (KO/EC)
      result <- EMP_function_import(
        file = input$data_file$datapath,
        type = "ko",  # Default to KO, could add selection
        assay_name = assay_name
      )
    } else {
      # Normal import (RNAseq, Metabolomics, etc.)
      file_sep <- detect_file_separator(input$data_file$datapath)
      data_df <- read.table(
        input$data_file$datapath,
        header = TRUE,
        sep = file_sep,
        stringsAsFactors = FALSE,
        check.names = FALSE,
        comment.char = ""
      )
      
      # Auto-detect columns
      col_info <- auto_detect_columns(data_df)
      
      # Remove index column if present (before processing)
      if (col_info$has_index) {
        data_df <- data_df[, -1, drop = FALSE]
        # Recalculate sample indices after removing index column
        numeric_cols <- sapply(data_df, is.numeric)
        sample_indices <- which(numeric_cols[2:length(numeric_cols)]) + 1
        if (length(sample_indices) == 0) {
          sample_indices <- 2:ncol(data_df)
        }
        sampleID <- names(data_df)[sample_indices]
      } else {
        # Use detected sample columns
        sampleID <- col_info$sample_cols
      }
      
      # Ensure first column is named 'feature'
      if (names(data_df)[1] != "feature") {
        names(data_df)[1] <- "feature"
      }
      
      # Remove metadata columns (similar to taxonomy import)
      metadata_patterns <- c(
        'absolute-filepath', 'filepath', 'file.path', 'path', 'filename', 'file.name',
        'sample.name', 'sample_name', 'sample.id', 'sample_id',
        'index', 'X', 'rownames', 'row.names', 'rowid', 'row.id'
      )
      
      cols_to_remove <- c()
      for (col_name in names(data_df)) {
        if (col_name != "feature" && col_name %in% sampleID) {
          col_lower <- tolower(col_name)
          if (col_lower %in% tolower(metadata_patterns)) {
            cols_to_remove <- c(cols_to_remove, col_name)
          } else if (nrow(data_df) > 0) {
            # Check if column contains file paths or is mostly non-numeric
            sample_vals <- as.character(data_df[[col_name]][1:min(5, nrow(data_df))])
            if (any(grepl("^/|.fastq|.fq|.gz$|.csv$|.tsv$", sample_vals, ignore.case = TRUE))) {
              cols_to_remove <- c(cols_to_remove, col_name)
            } else if (!is.numeric(data_df[[col_name]])) {
              test_vals <- suppressWarnings(as.numeric(as.character(sample_vals)))
              na_ratio <- sum(is.na(test_vals)) / length(test_vals)
              if (na_ratio > 0.8) {
                cols_to_remove <- c(cols_to_remove, col_name)
              }
            }
          }
        }
      }
      
      # Remove metadata columns and update sampleID
      if (length(cols_to_remove) > 0) {
        for (col in cols_to_remove) {
          col_idx <- which(names(data_df) == col)
          if (length(col_idx) > 0) {
            data_df <- data_df[, -col_idx, drop = FALSE]
          }
        }
        sampleID <- setdiff(sampleID, cols_to_remove)
        if (length(cols_to_remove) > 0) {
          showNotification(paste("Removed metadata columns:", paste(cols_to_remove, collapse = ", ")), 
            type = "message", duration = 3)
        }
      }
      
      # Convert sample columns to numeric (fixes 'x' must be numeric error)
      for (col_name in sampleID) {
        if (col_name %in% names(data_df) && !is.numeric(data_df[[col_name]])) {
          # Try to convert to numeric
          data_df[[col_name]] <- as.numeric(as.character(data_df[[col_name]]))
          # Replace any resulting NA with 0
          data_df[[col_name]][is.na(data_df[[col_name]])] <- 0
        }
      }
      
      # Final check - ensure we have sample columns
      if (length(sampleID) == 0) {
        stop("No valid sample columns found after processing. Please check your file format.")
      }
      
      result <- EMP_normal_import(
        data = data_df,
        sampleID = sampleID,
        assay_name = assay_name
      )
    }
    
    # Handle metadata if provided - Enhanced metadata processing
    sample_names <- colnames(result)
    
    if (!is.null(input$metadata_file_import)) {
      tryCatch({
        meta_sep <- detect_file_separator(input$metadata_file_import$datapath)
        metadata_df <- read.table(
          input$metadata_file_import$datapath,
          header = TRUE,
          sep = meta_sep,
          stringsAsFactors = FALSE,
          check.names = FALSE
        )
        
        # Find primary column - check for "Primary", "primary", "SampleID", "sample", "id"
        primary_col <- names(metadata_df)[1]
        if (any(grepl("^primary$|^Primary$", names(metadata_df), ignore.case = TRUE))) {
          primary_col <- names(metadata_df)[grepl("^primary$|^Primary$", names(metadata_df), ignore.case = TRUE)][1]
        } else if (any(grepl("sample|id", names(metadata_df), ignore.case = TRUE))) {
          primary_col <- names(metadata_df)[grepl("sample|id", names(metadata_df), ignore.case = TRUE)][1]
        }
        
        # Check if there's a "colname" column (for mapping files)
        colname_col <- NULL
        if ("colname" %in% names(metadata_df)) {
          colname_col <- "colname"
        } else if (any(grepl("colname|col.name", names(metadata_df), ignore.case = TRUE))) {
          colname_col <- names(metadata_df)[grepl("colname|col.name", names(metadata_df), ignore.case = TRUE)][1]
        }
        
        # If colname exists, use it for matching (this handles mapping files)
        if (!is.null(colname_col)) {
          # Use colname to match with sample names
          metadata_df$match_col <- as.character(metadata_df[[colname_col]])
          # Also keep primary for coldata
          if (primary_col != "primary") {
            names(metadata_df)[names(metadata_df) == primary_col] <- "primary"
          }
        } else {
          # Use primary column for matching
          if (primary_col != "primary") {
            names(metadata_df)[names(metadata_df) == primary_col] <- "primary"
          }
          metadata_df$match_col <- as.character(metadata_df$primary)
        }
        
        # Convert to character for matching
        metadata_df$primary <- as.character(metadata_df$primary)
        sample_names_char <- as.character(sample_names)
        
        # Match with sample names from data
        # First try matching with match_col (colname), then with primary
        matched_samples <- NULL
        if (!is.null(metadata_df$match_col)) {
          matched_indices <- which(metadata_df$match_col %in% sample_names_char)
          if (length(matched_indices) > 0) {
            # Update primary to match sample names
            metadata_df$primary[matched_indices] <- sample_names_char[match(metadata_df$match_col[matched_indices], sample_names_char)]
            matched_samples <- metadata_df$primary[matched_indices]
          }
        }
        
        # If no match with colname, try primary
        if (length(matched_samples) == 0) {
          matched_indices <- which(metadata_df$primary %in% sample_names_char)
          if (length(matched_indices) > 0) {
            matched_samples <- metadata_df$primary[matched_indices]
          }
        }
        
        # Try case-insensitive matching if still no match
        if (length(matched_samples) == 0) {
          sample_names_lower <- tolower(sample_names_char)
          metadata_lower <- tolower(metadata_df$match_col)
          matched_indices <- which(metadata_lower %in% sample_names_lower)
          if (length(matched_indices) > 0) {
            metadata_df$primary[matched_indices] <- sample_names_char[match(metadata_lower[matched_indices], sample_names_lower)]
            matched_samples <- metadata_df$primary[matched_indices]
          }
        }
        
        if (length(matched_samples) > 0) {
          # Filter to matched samples
          metadata_df <- metadata_df[metadata_df$primary %in% matched_samples, ]
          
          # Remove match_col if it exists (temporary column)
          if ("match_col" %in% names(metadata_df)) {
            metadata_df$match_col <- NULL
          }
          
          # Add any data samples not in metadata
          missing_samples <- setdiff(sample_names_char, metadata_df$primary)
          if (length(missing_samples) > 0) {
            missing_df <- data.frame(
              primary = missing_samples,
              stringsAsFactors = FALSE
            )
            # Add NA for other columns (except primary)
            for (col in setdiff(names(metadata_df), "primary")) {
              missing_df[[col]] <- NA
            }
            metadata_df <- rbind(metadata_df, missing_df)
          }
          
          # Ensure all data samples are included and in correct order
          metadata_df <- metadata_df[match(sample_names_char, metadata_df$primary), ]
          
          # Remove match_col if it still exists
          if ("match_col" %in% names(metadata_df)) {
            metadata_df$match_col <- NULL
          }
          
          # Set rownames to primary values
          # IMPORTANT: Do NOT keep "primary" as a column in coldata
          # EMP_coldata_extract will add it automatically from rownames
          # Having it as both rownames and column causes duplication error
          primary_values <- metadata_df$primary
          metadata_df$primary <- NULL  # Remove primary column
          rownames(metadata_df) <- primary_values
          
          # Check for duplicate column names
          if (any(duplicated(names(metadata_df)))) {
            metadata_df <- metadata_df[, !duplicated(names(metadata_df)), drop = FALSE]
          }
          
          coldata <- S4Vectors::DataFrame(metadata_df)
          showNotification(paste("Metadata linked to", length(matched_samples), "samples"), type = "message")
        } else {
          showNotification("Warning: No matching samples found between data and metadata. Creating minimal metadata.", 
            type = "warning")
          # Create minimal coldata - do NOT include primary column
          # EMP_coldata_extract will add it from rownames
          coldata_df <- data.frame(
            row.names = sample_names_char,
            stringsAsFactors = FALSE
          )
          coldata <- S4Vectors::DataFrame(coldata_df)
        }
      }, error = function(e) {
        showNotification(paste("Metadata processing error:", e$message, "- Using minimal metadata"), 
          type = "warning")
        coldata <- S4Vectors::DataFrame(
          primary = sample_names,
          row.names = sample_names
        )
      })
    } else {
      # Create minimal coldata - do NOT include primary column
      # EMP_coldata_extract will add it from rownames
      coldata_df <- data.frame(
        row.names = sample_names,
        stringsAsFactors = FALSE
      )
      coldata <- S4Vectors::DataFrame(coldata_df)
    }
    
    # Create or add to MAE
    if (is.null(values$emp_data)) {
      objlist <- list(result)
      names(objlist) <- exp_name
      
      dfmap <- data.frame(
        assay = factor(exp_name),
        primary = colnames(result),
        colname = colnames(result)
      )
      
      values$emp_data <- MultiAssayExperiment::MultiAssayExperiment(
        experiments = objlist,
        colData = coldata,
        sampleMap = dfmap
      )
    } else {
      values$emp_data[[exp_name]] <- result
      
      # Update sampleMap
      new_map <- data.frame(
        assay = factor(exp_name),
        primary = colnames(result),
        colname = colnames(result)
      )
      existing_map <- as.data.frame(values$emp_data@sampleMap)
      combined_map <- rbind(existing_map, new_map)
      values$emp_data@sampleMap <- S4Vectors::DataFrame(combined_map)
      
      # Merge coldata
      existing_coldata <- as.data.frame(colData(values$emp_data))
      if ("primary" %in% names(existing_coldata)) {
        merged_coldata <- merge(existing_coldata, as.data.frame(coldata), 
                               by = "primary", all = TRUE)
        rownames(merged_coldata) <- merged_coldata$primary
        colData(values$emp_data) <- S4Vectors::DataFrame(merged_coldata)
      }
    }
    
    # Detect and store experiment type
    exp_type <- detect_experiment_type(values$emp_data, exp_name)
    values$experiment_types[[exp_name]] <- exp_type
    values$current_experiment <- exp_name
    
    showNotification(paste("Data imported successfully as:", exp_name, 
      " (Type:", exp_type, ")"), type = "message")
    
  }, error = function(e) {
    showNotification(paste("Import error:", e$message), type = "error", duration = 10)
  })
})

# Display import status
output$import_status <- renderText({
  if (is.null(values$emp_data)) {
    return("No data imported yet.")
  } else {
    exp_names <- names(values$emp_data)
    return(paste("Data imported successfully! Experiments:", 
      paste(exp_names, collapse = ", ")))
  }
})

# Preview metadata
observeEvent(input$preview_metadata_btn, {
  req(input$metadata_file_import)
  
  tryCatch({
    meta_sep <- detect_file_separator(input$metadata_file_import$datapath)
    metadata_df <- read.table(
      input$metadata_file_import$datapath,
      header = TRUE,
      sep = meta_sep,
      nrows = 20,
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
    
    detection_results$metadata_preview <- metadata_df
    showNotification("Metadata preview loaded!", type = "message")
  }, error = function(e) {
    showNotification(paste("Metadata preview error:", e$message), type = "error")
  })
})

# Display metadata preview
output$metadata_preview_import <- DT::renderDataTable({
  if (is.null(detection_results$metadata_preview)) {
    return(data.frame(Message = "Click 'Preview Metadata' to see your metadata file."))
  }
  return(detection_results$metadata_preview)
}, options = list(pageLength = 5, scrollX = TRUE, dom = 't'))

# Display available experiments
output$experiments_table <- DT::renderDataTable({
  if (is.null(values$emp_data)) {
    return(data.frame(Experiment = character(0), Samples = integer(0), Features = integer(0)))
  }
  
  exp_info <- lapply(names(values$emp_data), function(exp_name) {
    exp_data <- values$emp_data[[exp_name]]
    data.frame(
      Experiment = exp_name,
      Samples = ncol(exp_data),
      Features = nrow(exp_data),
      stringsAsFactors = FALSE
    )
  })
  
  do.call(rbind, exp_info)
}, options = list(pageLength = 10, scrollX = TRUE))
