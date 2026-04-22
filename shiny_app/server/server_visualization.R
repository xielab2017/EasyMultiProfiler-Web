# Visualization Server Logic

# Update experiment choices for all visualization modules
observe({
  if (!is.null(values$emp_data)) {
    exp_names <- names(values$emp_data)
    updateSelectInput(session, "barplot_experiment", choices = exp_names)
    updateSelectInput(session, "boxplot_experiment", choices = exp_names)
    updateSelectInput(session, "heatmap_experiment", choices = exp_names)
    # Volcano and Scatterplot use current experiment from differential/dimension analysis
    updateSelectInput(session, "sankey_experiment", choices = exp_names)
    updateSelectInput(session, "network_plot_experiment", choices = exp_names)
    updateSelectInput(session, "enrich_plots_experiment", choices = exp_names)
    updateSelectInput(session, "structure_plot_experiment", choices = exp_names)
    
    # Update current experiment
    if (is.null(values$current_experiment) && length(exp_names) > 0) {
      values$current_experiment <- exp_names[1]
    }
  }
})

# Update current experiment when user selects in visualization modules
observeEvent(input$barplot_experiment, {
  if (!is.null(input$barplot_experiment)) values$current_experiment <- input$barplot_experiment
})
observeEvent(input$boxplot_experiment, {
  if (!is.null(input$boxplot_experiment)) values$current_experiment <- input$boxplot_experiment
})
observeEvent(input$heatmap_experiment, {
  if (!is.null(input$heatmap_experiment)) values$current_experiment <- input$heatmap_experiment
})
# Volcano and Scatterplot use current experiment - no need to observe
observeEvent(input$sankey_experiment, {
  if (!is.null(input$sankey_experiment)) values$current_experiment <- input$sankey_experiment
})
observeEvent(input$network_plot_experiment, {
  if (!is.null(input$network_plot_experiment)) values$current_experiment <- input$network_plot_experiment
})
observeEvent(input$enrich_plots_experiment, {
  if (!is.null(input$enrich_plots_experiment)) values$current_experiment <- input$enrich_plots_experiment
})
observeEvent(input$structure_plot_experiment, {
  if (!is.null(input$structure_plot_experiment)) values$current_experiment <- input$structure_plot_experiment
})

# Update group variable choices
observe({
  if (!is.null(values$emp_data)) {
      tryCatch({
        exp_names <- names(values$emp_data)
        if (length(exp_names) > 0) {
          emp_obj <- get_empt(exp_names[1])
          if (is.null(emp_obj)) {
            emp_obj <- convert_mae_to_empt(values$emp_data, experiment = exp_names[1])
            if (inherits(emp_obj, "EMP")) {
              emp_obj <- emp_obj[[exp_names[1]]]
            }
          }
          if (is.null(emp_obj)) return()
          col_data <- SummarizedExperiment::colData(emp_obj)
        group_vars <- names(col_data)[sapply(col_data, function(x) length(unique(x)) < nrow(col_data))]
        
        updateSelectInput(session, "barplot_group", choices = group_vars)
        updateSelectInput(session, "boxplot_group", choices = group_vars)
        updateSelectInput(session, "heatmap_group", choices = group_vars)
        updateSelectInput(session, "scatterplot_group", choices = group_vars)
      }
    }, error = function(e) {
      # Silently fail
    })
  }
})

# Feature selector for single gene barplot
output$barplot_feature_selector <- renderUI({
  req(input$barplot_experiment)
  req(input$barplot_mode)
  req(values$emp_data)
  
  if (input$barplot_mode != "single") {
    return(NULL)
  }
  
  tryCatch({
    emp_obj <- get_empt(input$barplot_experiment)
    if (is.null(emp_obj)) {
      return(NULL)
    }
    
    # Get available features
    features <- rownames(emp_obj)
    if (length(features) == 0) {
      return(NULL)
    }
    
    # If differential analysis results exist, prioritize showing those
    diff_results <- tryCatch({
      EMP_result(emp_obj, info = "diff_analysis_result")
    }, error = function(e) NULL)
    
    if (!is.null(diff_results) && nrow(diff_results) > 0 && "feature" %in% names(diff_results)) {
      # Show differential features first
      diff_features <- diff_results$feature
      other_features <- setdiff(features, diff_features)
      feature_choices <- c(diff_features, other_features)
    } else {
      feature_choices <- features
    }
    
    # Limit to first 1000 for performance
    if (length(feature_choices) > 1000) {
      feature_choices <- feature_choices[1:1000]
    }
    
    return(
      selectizeInput("barplot_feature", "Select Feature/Gene:",
        choices = feature_choices,
        selected = if(length(feature_choices) > 0) feature_choices[1] else NULL,
        width = "100%",
        options = list(
          placeholder = "Type to search...",
          maxOptions = 1000
        )
      )
    )
  }, error = function(e) {
    return(NULL)
  })
  
  return(NULL)
})

# Barplot
observeEvent(input$barplot_btn, {
  req(input$barplot_experiment)
  req(input$barplot_mode)
  req(values$emp_data)
  
  tryCatch({
    emp_obj <- get_empt(input$barplot_experiment)
    if (is.null(emp_obj)) {
      showNotification("Could not convert data to EMPT format", type = "error")
      return()
    }
    
    if (input$barplot_mode == "single") {
      # Single feature mode
      if (is.null(input$barplot_feature) || input$barplot_feature == "") {
        showNotification("Please select a feature/gene", type = "error")
        return()
      }
      
      # Filter to only the selected feature
      emp_obj <- EMP_filter(
        obj = emp_obj,
        sample_condition = 1 == 1,
        feature_condition = 1 == 1,
        filterFeature = input$barplot_feature,
        action = "select"
      )
      
      plot_result <- EMP_barplot(
        obj = emp_obj,
        experiment = input$barplot_experiment,
        method = input$barplot_method,
        estimate_group = input$barplot_group
      )
    } else {
      # Multiple features mode (topN)
      # Filter to topN features by variance or other criteria
      if (input$barplot_topN > 0 && input$barplot_topN < length(rownames(emp_obj))) {
        # Get top N most variable features
        assay_data <- SummarizedExperiment::assays(emp_obj)[[1]]
        feature_vars <- apply(assay_data, 1, var, na.rm = TRUE)
        top_features <- names(sort(feature_vars, decreasing = TRUE)[1:input$barplot_topN])
        
        # Filter to top features
        emp_obj <- EMP_filter(
          obj = emp_obj,
          sample_condition = 1 == 1,
          feature_condition = 1 == 1,
          filterFeature = top_features,
          action = "select"
        )
      }
      
      plot_result <- EMP_barplot(
        obj = emp_obj,
        experiment = input$barplot_experiment,
        method = input$barplot_method,
        estimate_group = input$barplot_group
      )
    }
    
    values$plots$barplot <- plot_result
    showNotification("Barplot generated!", type = "message")
  }, error = function(e) {
    showNotification(paste("Barplot error:", e$message), type = "error")
  })
})

output$barplot_output <- renderPlot({
  if (is.null(values$plots$barplot)) {
    return(NULL)
  }
  # EMP_barplot returns EMP_barplot object, need to extract actual plot
  tryCatch({
    if (inherits(values$plots$barplot, "EMP_barplot")) {
      # Extract plot from plot_deposit (contains pic and html)
      plot_deposit <- EasyMultiProfiler:::.get.plot_deposit.EMPT(values$plots$barplot, info = 'EMP_barplot')
      if (!is.null(plot_deposit) && "pic" %in% names(plot_deposit)) {
        print(plot_deposit$pic)
      } else {
        # Fallback: try to show the object directly
        show(values$plots$barplot)
      }
    } else {
      # If it's already a plot object
      print(values$plots$barplot)
    }
  }, error = function(e) {
    # Fallback: try to show the object
    show(values$plots$barplot)
  })
}, width = reactive(if(is.null(input$barplot_width)) 800 else input$barplot_width),
   height = reactive(if(is.null(input$barplot_height)) 600 else input$barplot_height))

output$barplot_download <- downloadHandler(
  filename = function() { "barplot.pdf" },
  content = function(file) {
    if (!is.null(values$plots$barplot)) {
      tryCatch({
        if (inherits(values$plots$barplot, "EMP_barplot")) {
          # Extract plot from plot_deposit (contains pic and html)
          plot_deposit <- EasyMultiProfiler:::.get.plot_deposit.EMPT(values$plots$barplot, info = 'EMP_barplot')
          if (!is.null(plot_deposit) && "pic" %in% names(plot_deposit)) {
            ggsave(file, plot = plot_deposit$pic, width = input$barplot_width/100, 
                   height = input$barplot_height/100, device = "pdf")
          }
        } else {
          ggsave(file, plot = values$plots$barplot, width = input$barplot_width/100, 
                 height = input$barplot_height/100, device = "pdf")
        }
      }, error = function(e) {
        showNotification(paste("Error saving barplot:", e$message), type = "error")
      })
    }
  }
)

# Boxplot
observeEvent(input$boxplot_btn, {
  req(input$boxplot_experiment)
  req(values$emp_data)
  
  tryCatch({
    emp_obj <- get_empt(input$boxplot_experiment)
    if (is.null(emp_obj)) {
      emp_obj <- convert_mae_to_empt(values$emp_data, experiment = input$boxplot_experiment)
      if (inherits(emp_obj, "EMP")) {
        emp_obj <- emp_obj[[input$boxplot_experiment]]
      }
    }
    if (is.null(emp_obj)) {
      showNotification("Could not convert data to EMPT format", type = "error")
      return()
    }
    
    plot_result <- EMP_boxplot(
      obj = emp_obj,
      experiment = input$boxplot_experiment,
      method = input$boxplot_method,
      plot_category = input$boxplot_group,
      violin = input$boxplot_violin
    )
    
    values$plots$boxplot <- plot_result
    showNotification("Boxplot generated!", type = "message")
  }, error = function(e) {
    showNotification(paste("Boxplot error:", e$message), type = "error")
  })
})

output$boxplot_output <- renderPlot({
  if (is.null(values$plots$boxplot)) {
    return(NULL)
  }
  # EMP_boxplot returns EMP_boxplot object, need to extract actual plot
  tryCatch({
    if (inherits(values$plots$boxplot, "EMP_boxplot")) {
      # Extract plot from plot_deposit (contains pic and html)
      plot_deposit <- EasyMultiProfiler:::.get.plot_deposit.EMPT(values$plots$boxplot, info = 'EMP_boxplot')
      if (!is.null(plot_deposit) && "pic" %in% names(plot_deposit)) {
        print(plot_deposit$pic)
      } else {
        # Fallback: try to show the object directly
        show(values$plots$boxplot)
      }
    } else {
      # If it's already a plot object
      print(values$plots$boxplot)
    }
  }, error = function(e) {
    # Fallback: try to show the object
    show(values$plots$boxplot)
  })
}, width = reactive(if(is.null(input$boxplot_width)) 800 else input$boxplot_width),
   height = reactive(if(is.null(input$boxplot_height)) 600 else input$boxplot_height))

output$boxplot_download <- downloadHandler(
  filename = function() { "boxplot.pdf" },
  content = function(file) {
    if (!is.null(values$plots$boxplot)) {
      tryCatch({
        if (inherits(values$plots$boxplot, "EMP_boxplot")) {
          # Extract plot from plot_deposit (contains pic and html)
          plot_deposit <- EasyMultiProfiler:::.get.plot_deposit.EMPT(values$plots$boxplot, info = 'EMP_boxplot')
          if (!is.null(plot_deposit) && "pic" %in% names(plot_deposit)) {
            ggsave(file, plot = plot_deposit$pic, width = input$boxplot_width/100, 
                   height = input$boxplot_height/100, device = "pdf")
          }
        } else {
          ggsave(file, plot = values$plots$boxplot, width = input$boxplot_width/100, 
                 height = input$boxplot_height/100, device = "pdf")
        }
      }, error = function(e) {
        showNotification(paste("Error saving boxplot:", e$message), type = "error")
      })
    }
  }
)

# Check if experiment has differential analysis results for heatmap
output$heatmap_diff_warning <- renderUI({
  req(input$heatmap_experiment)
  req(values$emp_data)
  
  if (is.null(input$heatmap_feature_source) || input$heatmap_feature_source != "diff") {
    return(NULL)
  }
  
  tryCatch({
    emp_obj <- get_empt(input$heatmap_experiment)
    if (is.null(emp_obj)) {
      return(NULL)
    }
    
    # Check if differential analysis results exist
    diff_results <- tryCatch({
      EMP_result(emp_obj, info = "diff_analysis_result")
    }, error = function(e) NULL)
    
    if (is.null(diff_results) || nrow(diff_results) == 0) {
      return(
        helpText("Warning: No differential analysis results found. Please run differential analysis first.", 
                 style = "color: orange;")
      )
    } else {
      return(
        helpText(paste("Found", nrow(diff_results), "differential analysis results."), 
                 style = "color: green;")
      )
    }
  }, error = function(e) {
    return(NULL)
  })
})

# Show group filter for heatmap differential filtering
output$heatmap_diff_group_filter <- renderUI({
  req(input$heatmap_experiment)
  req(input$heatmap_feature_source)
  req(values$emp_data)
  
  if (input$heatmap_feature_source != "diff") {
    return(NULL)
  }
  
  tryCatch({
    emp_obj <- get_empt(input$heatmap_experiment)
    if (is.null(emp_obj)) {
      return(NULL)
    }
    
    diff_results <- tryCatch({
      EMP_result(emp_obj, info = "diff_analysis_result")
    }, error = function(e) NULL)
    
    if (is.null(diff_results) || !"sign_group" %in% names(diff_results)) {
      return(NULL)
    }
    
    available_groups <- unique(diff_results$sign_group)
    available_groups <- available_groups[!is.na(available_groups)]
    
    if (length(available_groups) > 0) {
      return(
        selectInput("heatmap_diff_filter_group", "Filter by Group (optional):",
          choices = c("All groups" = "all", available_groups),
          selected = "all",
          width = "100%"
        )
      )
    }
  }, error = function(e) {
    return(NULL)
  })
  
  return(NULL)
})

# Heatmap
observeEvent(input$heatmap_btn, {
  req(input$heatmap_experiment)
  req(values$emp_data)
  
  tryCatch({
    # Get EMPT object - use the one with diff results if available
    emp_obj <- NULL
    
    # Check if we should use differential analysis results
    if (!is.null(input$heatmap_feature_source) && input$heatmap_feature_source == "diff") {
      # Try to get EMPT with diff results
      diff_key <- paste0("differential_", input$heatmap_experiment)
      if (!is.null(values$analysis_results[[diff_key]])) {
        emp_obj <- values$analysis_results[[diff_key]]
      } else {
        emp_obj <- get_empt(input$heatmap_experiment)
      }
      
      if (is.null(emp_obj)) {
        showNotification("Could not get data with differential analysis results", type = "error")
        return()
      }
      
      # Get differential results and filter features
      diff_results <- tryCatch({
        EMP_result(emp_obj, info = "diff_analysis_result")
      }, error = function(e) NULL)
      
      if (is.null(diff_results) || nrow(diff_results) == 0) {
        showNotification("No differential analysis results found. Please run differential analysis first.", 
                        type = "error")
        return()
      }
      
      # Apply filters
      p_col <- if (input$heatmap_diff_pvalue_type == "fdr") {
        fdr_col <- names(diff_results)[grepl("fdr|p.adjust|padj", names(diff_results), ignore.case = TRUE)][1]
        if (is.null(fdr_col)) "pvalue" else fdr_col
      } else {
        "pvalue"
      }
      
      # Filter by p-value
      filtered_results <- diff_results[diff_results[[p_col]] <= input$heatmap_diff_pvalue, ]
      
      # Filter by fold change
      if (input$heatmap_diff_fc > 0) {
        if ("log2FC" %in% names(filtered_results)) {
          filtered_results <- filtered_results[abs(filtered_results$log2FC) >= log2(input$heatmap_diff_fc), ]
        } else if ("fold_change" %in% names(filtered_results)) {
          filtered_results <- filtered_results[abs(filtered_results$fold_change - 1) >= (input$heatmap_diff_fc - 1), ]
        }
      }
      
      # Filter by direction
      if (input$heatmap_diff_direction == "up") {
        if ("log2FC" %in% names(filtered_results)) {
          filtered_results <- filtered_results[filtered_results$log2FC > 0, ]
        } else if ("fold_change" %in% names(filtered_results)) {
          filtered_results <- filtered_results[filtered_results$fold_change > 1, ]
        }
      } else if (input$heatmap_diff_direction == "down") {
        if ("log2FC" %in% names(filtered_results)) {
          filtered_results <- filtered_results[filtered_results$log2FC < 0, ]
        } else if ("fold_change" %in% names(filtered_results)) {
          filtered_results <- filtered_results[filtered_results$fold_change < 1, ]
        }
      }
      
      # Filter by group if specified
      if (!is.null(input$heatmap_diff_filter_group) && input$heatmap_diff_filter_group != "all") {
        if ("sign_group" %in% names(filtered_results)) {
          filtered_results <- filtered_results[filtered_results$sign_group == input$heatmap_diff_filter_group, ]
        }
      }
      
      # Get feature IDs to keep
      feature_ids <- filtered_results$feature
      
      if (length(feature_ids) == 0) {
        showNotification("No features match the filter criteria. Please adjust filters.", type = "error")
        return()
      }
      
      # Filter EMPT to only include these features
      emp_obj <- EMP_filter(
        obj = emp_obj,
        sample_condition = 1 == 1,
        feature_condition = 1 == 1,
        filterFeature = feature_ids,
        action = "select"
      )
      
      showNotification(paste("Using", length(feature_ids), "differentially expressed features for heatmap"), 
                      type = "message")
    } else {
      # Use topN method
      emp_obj <- get_empt(input$heatmap_experiment)
      if (is.null(emp_obj)) {
        showNotification("Could not convert data to EMPT format", type = "error")
        return()
      }
    }
    
    # Generate heatmap - EMP_heatmap_plot doesn't accept experiment, topN parameters
    # It only accepts obj and ... parameters
    # For topN, we need to filter the data first
    if (!is.null(input$heatmap_feature_source) && input$heatmap_feature_source == "topN") {
      # Filter to topN features by variance
      if (input$heatmap_topN > 0 && input$heatmap_topN < length(rownames(emp_obj))) {
        assay_data <- SummarizedExperiment::assays(emp_obj)[[1]]
        feature_vars <- apply(assay_data, 1, var, na.rm = TRUE)
        top_features <- names(sort(feature_vars, decreasing = TRUE)[1:input$heatmap_topN])
        
        # Filter to top features
        emp_obj <- EMP_filter(
          obj = emp_obj,
          sample_condition = 1 == 1,
          feature_condition = 1 == 1,
          filterFeature = top_features,
          action = "select"
        )
      }
    }
    
    # Call EMP_heatmap_plot with correct parameters
    plot_result <- EMP_heatmap_plot(
      obj = emp_obj,
      clust_row = as.logical(input$heatmap_cluster_rows),
      clust_col = as.logical(input$heatmap_cluster_cols)
    )
    
    values$plots$heatmap <- plot_result
    showNotification("Heatmap generated!", type = "message")
  }, error = function(e) {
    showNotification(paste("Heatmap error:", e$message), type = "error")
  })
})

output$heatmap_output <- renderPlot({
  if (is.null(values$plots$heatmap)) {
    return(NULL)
  }
  # EMP_heatmap_plot returns EMP_assay_heatmap object, need to extract actual plot
  tryCatch({
    if (inherits(values$plots$heatmap, "EMP_assay_heatmap")) {
      # Extract plot from plot_deposit
      plot_obj <- EasyMultiProfiler:::.get.plot_deposit.EMPT(values$plots$heatmap, info = 'EMP_assay_heatmap')
      if (!is.null(plot_obj)) {
        print(plot_obj)
      } else {
        # Fallback: try to show the object directly
        show(values$plots$heatmap)
      }
    } else {
      # If it's already a plot object
      print(values$plots$heatmap)
    }
  }, error = function(e) {
    # Fallback: try to show the object
    show(values$plots$heatmap)
  })
}, width = reactive(if(is.null(input$heatmap_width)) 1000 else input$heatmap_width),
   height = reactive(if(is.null(input$heatmap_height)) 800 else input$heatmap_height))

output$heatmap_download <- downloadHandler(
  filename = function() { "heatmap.pdf" },
  content = function(file) {
    if (!is.null(values$plots$heatmap)) {
      tryCatch({
        if (inherits(values$plots$heatmap, "EMP_assay_heatmap")) {
          # Extract plot from plot_deposit
          plot_obj <- EasyMultiProfiler:::.get.plot_deposit.EMPT(values$plots$heatmap, info = 'EMP_assay_heatmap')
          if (!is.null(plot_obj)) {
            ggsave(file, plot = plot_obj, width = input$heatmap_width/100, 
                   height = input$heatmap_height/100, device = "pdf")
          }
        } else {
          ggsave(file, plot = values$plots$heatmap, width = input$heatmap_width/100, 
                 height = input$heatmap_height/100, device = "pdf")
        }
      }, error = function(e) {
        showNotification(paste("Error saving heatmap:", e$message), type = "error")
      })
    }
  }
)

# Show current experiment info for volcano plot
output$volcano_experiment_info <- renderUI({
  if (is.null(values$current_experiment)) {
    return(
      helpText("Please run differential analysis first to select an experiment.", 
               style = "color: orange; font-weight: bold;")
    )
  }
  
  return(
    helpText(paste("Using experiment:", values$current_experiment, 
                   "(from differential analysis)"), 
             style = "color: green; font-weight: bold;")
  )
})

# Check if experiment has differential analysis results for volcano
output$volcano_diff_warning <- renderUI({
  if (is.null(values$current_experiment)) {
    return(
      helpText("Warning: No experiment selected. Please run differential analysis first.", 
               style = "color: orange;")
    )
  }
  
  # Try to get EMPT with differential results
  diff_key <- paste0("differential_", values$current_experiment)
  emp_obj <- NULL
  
  if (!is.null(values$analysis_results[[diff_key]])) {
    emp_obj <- values$analysis_results[[diff_key]]
  } else {
    emp_obj <- get_empt(values$current_experiment)
  }
  
  if (is.null(emp_obj)) {
    return(
      helpText("Warning: Could not access experiment data. Please run differential analysis first.", 
               style = "color: orange;")
    )
  }
  
  tryCatch({
    diff_results <- tryCatch({
      EMP_result(emp_obj, info = "diff_analysis_result")
    }, error = function(e) NULL)
    
    if (is.null(diff_results) || nrow(diff_results) == 0) {
      return(
        helpText("Warning: No differential analysis results found. Please run differential analysis first.", 
                 style = "color: orange;")
      )
    } else {
      return(
        helpText(paste("✓ Found", nrow(diff_results), "differential analysis results."), 
                 style = "color: green;")
      )
    }
  }, error = function(e) {
    return(
      helpText("Warning: Error checking differential analysis results.", 
               style = "color: orange;")
    )
  })
})

# Volcano Plot
observeEvent(input$volcano_btn, {
  if (is.null(values$current_experiment)) {
    showNotification("No experiment selected. Please run differential analysis first.", 
                    type = "error")
    return()
  }
  
  req(values$emp_data)
  
  tryCatch({
    # Try to get EMPT with differential analysis results
    diff_key <- paste0("differential_", values$current_experiment)
    emp_obj <- NULL
    
    if (!is.null(values$analysis_results[[diff_key]])) {
      # Use the saved EMPT that contains differential analysis results
      emp_obj <- values$analysis_results[[diff_key]]
    } else {
      # Fallback: try to get from MAE
      emp_obj <- get_empt(values$current_experiment)
    }
    
    if (is.null(emp_obj)) {
      showNotification("Could not access experiment data. Please run differential analysis first.", 
                      type = "error")
      return()
    }
    
    # Check if differential analysis results exist
    diff_results <- tryCatch({
      EMP_result(emp_obj, info = "diff_analysis_result")
    }, error = function(e) NULL)
    
    if (is.null(diff_results) || nrow(diff_results) == 0) {
      showNotification("No differential analysis results found. Please run differential analysis first.", 
                      type = "error")
      return()
    }
    
    # Build color palette: [upregulated, downregulated, non-significant]
    volcano_palette <- c(
      input$volcano_color_up %||% "#E74C3C",      # Red for upregulated
      input$volcano_color_down %||% "#3498DB",    # Blue for downregulated
      input$volcano_color_ns %||% "#636363"       # Gray for non-significant
    )
    
    plot_result <- EMP_volcanol_plot(
      obj = emp_obj,
      y = input$volcano_y,
      palette = volcano_palette,
      threshold_x = input$volcano_threshold_x %||% log2(input$volcano_fc %||% 1.5)
    )
    
    values$plots$volcano <- plot_result
    showNotification("Volcano plot generated!", type = "message")
  }, error = function(e) {
    showNotification(paste("Volcano plot error:", e$message), type = "error")
  })
})

output$volcano_output <- renderPlot({
  if (is.null(values$plots$volcano)) {
    return(NULL)
  }
  # EMP_volcanol_plot returns EMP_diff_volcanol_plot object, need to extract actual plot
  tryCatch({
    if (inherits(values$plots$volcano, "EMP_diff_volcanol_plot")) {
      # Extract plot from plot_deposit
      plot_obj <- EasyMultiProfiler:::.get.plot_deposit.EMPT(values$plots$volcano, info = 'EMP_diff_volcanol_plot')
      if (!is.null(plot_obj)) {
        print(plot_obj)
      } else {
        # Fallback: try to show the object directly
        show(values$plots$volcano)
      }
    } else {
      # If it's already a plot object
      print(values$plots$volcano)
    }
  }, error = function(e) {
    # Fallback: try to show the object
    show(values$plots$volcano)
  })
}, width = reactive(if(is.null(input$volcano_width)) 800 else input$volcano_width),
   height = reactive(if(is.null(input$volcano_height)) 600 else input$volcano_height))

output$volcano_download <- downloadHandler(
  filename = function() { "volcano_plot.pdf" },
  content = function(file) {
    if (!is.null(values$plots$volcano)) {
      tryCatch({
        if (inherits(values$plots$volcano, "EMP_diff_volcanol_plot")) {
          # Extract plot from plot_deposit
          plot_obj <- EasyMultiProfiler:::.get.plot_deposit.EMPT(values$plots$volcano, info = 'EMP_diff_volcanol_plot')
          if (!is.null(plot_obj)) {
            ggsave(file, plot = plot_obj, width = input$volcano_width/100, 
                   height = input$volcano_height/100, device = "pdf")
          }
        } else {
          ggsave(file, plot = values$plots$volcano, width = input$volcano_width/100, 
                 height = input$volcano_height/100, device = "pdf")
        }
      }, error = function(e) {
        showNotification(paste("Error saving volcano plot:", e$message), type = "error")
      })
    }
  }
)

# Show current experiment info for scatterplot
output$scatterplot_experiment_info <- renderUI({
  if (is.null(values$current_experiment)) {
    return(
      helpText("Please run dimension reduction analysis first to select an experiment.", 
               style = "color: orange; font-weight: bold;")
    )
  }
  
  return(
    helpText(paste("Using experiment:", values$current_experiment, 
                   "(from dimension reduction)"), 
             style = "color: green; font-weight: bold;")
  )
})

# Check if dimension analysis results exist for scatterplot
output$scatterplot_dimension_warning <- renderUI({
  if (is.null(values$analysis_results$dimension)) {
    return(
      helpText("Warning: No dimension reduction results found. Please run dimension reduction analysis first.", 
               style = "color: orange;")
    )
  }
  
  dim_result <- values$analysis_results$dimension
  if (!inherits(dim_result, "EMP_dimension_analysis")) {
    return(
      helpText("Warning: Dimension analysis result is not in correct format.", 
               style = "color: orange;")
    )
  }
  
  return(
    helpText("✓ Dimension reduction results found.", 
             style = "color: green;")
  )
})

# Scatterplot - requires dimension analysis result
observeEvent(input$scatterplot_btn, {
  if (is.null(values$current_experiment)) {
    showNotification("No experiment selected. Please run dimension reduction analysis first.", 
                    type = "error")
    return()
  }
  
  tryCatch({
    # EMP_scatterplot requires EMP_dimension_analysis result, not raw EMPT
    if (is.null(values$analysis_results$dimension)) {
      showNotification("Please run dimension reduction analysis first. Scatterplot requires dimension analysis results.", 
                      type = "error")
      return()
    }
    
    # Check if the dimension result is for the correct experiment
    dim_result <- values$analysis_results$dimension
    if (!inherits(dim_result, "EMP_dimension_analysis")) {
      showNotification("Dimension analysis result is not in correct format. Please run dimension reduction again.", 
                      type = "error")
      return()
    }
    
    # EMP_scatterplot accepts EMP_dimension_analysis object
    # It doesn't accept experiment, method, color_by parameters
    plot_result <- EMP_scatterplot(
      obj = dim_result,
      estimate_group = input$scatterplot_group,
      show = "p12"
    )
    
    values$plots$scatterplot <- plot_result
    showNotification("Scatterplot generated!", type = "message")
  }, error = function(e) {
    showNotification(paste("Scatterplot error:", e$message), type = "error")
  })
})

output$scatterplot_output <- renderPlot({
  if (is.null(values$plots$scatterplot)) {
    return(NULL)
  }
  print(values$plots$scatterplot)
}, width = reactive(if(is.null(input$scatterplot_width)) 800 else input$scatterplot_width),
   height = reactive(if(is.null(input$scatterplot_height)) 600 else input$scatterplot_height))

output$scatterplot_download <- downloadHandler(
  filename = function() { "scatterplot.pdf" },
  content = function(file) {
    if (!is.null(values$plots$scatterplot)) {
      tryCatch({
        if (inherits(values$plots$scatterplot, "EMP_dimension_analysis_scatterplot")) {
          # Extract plot from plot_deposit
          plot_obj <- EasyMultiProfiler:::.get.plot_deposit.EMPT(values$plots$scatterplot, info = 'EMP_dimension_analysis_scatterplot')
          if (!is.null(plot_obj)) {
            ggsave(file, plot = plot_obj, width = input$scatterplot_width/100, 
                   height = input$scatterplot_height/100, device = "pdf")
          }
        } else {
          ggsave(file, plot = values$plots$scatterplot, width = input$scatterplot_width/100, 
                 height = input$scatterplot_height/100, device = "pdf")
        }
      }, error = function(e) {
        showNotification(paste("Error saving scatterplot:", e$message), type = "error")
      })
    }
  }
)

# Sankey Plot
observeEvent(input$sankey_btn, {
  req(input$sankey_experiment)
  req(values$emp_data)
  
  tryCatch({
    emp_obj <- get_empt(input$sankey_experiment)
    if (is.null(emp_obj)) {
      emp_obj <- convert_mae_to_empt(values$emp_data, experiment = input$sankey_experiment)
      if (inherits(emp_obj, "EMP")) {
        emp_obj <- emp_obj[[input$sankey_experiment]]
      }
    }
    if (is.null(emp_obj)) {
      showNotification("Could not convert data to EMPT format", type = "error")
      return()
    }
    
    plot_result <- EMP_sankey_plot(
      obj = emp_obj,
      experiment = input$sankey_experiment,
      from = input$sankey_from,
      to = input$sankey_to
    )
    
    values$plots$sankey <- plot_result
    showNotification("Sankey plot generated!", type = "message")
  }, error = function(e) {
    showNotification(paste("Sankey plot error:", e$message), type = "error")
  })
})

output$sankey_output <- renderPlot({
  if (is.null(values$plots$sankey)) {
    return(NULL)
  }
  print(values$plots$sankey)
}, height = 600)

output$sankey_download <- downloadHandler(
  filename = function() { "sankey_plot.pdf" },
  content = function(file) {
    if (!is.null(values$plots$sankey)) {
      tryCatch({
        if (inherits(values$plots$sankey, "EMP_cor_sankey")) {
          # Extract plot from plot_deposit
          plot_obj <- EasyMultiProfiler:::.get.plot_deposit.EMPT(values$plots$sankey, info = 'EMP_cor_sankey')
          if (!is.null(plot_obj)) {
            ggsave(file, plot = plot_obj, width = 12, height = 8, device = "pdf")
          }
        } else {
          ggsave(file, plot = values$plots$sankey, width = 12, height = 8, device = "pdf")
        }
      }, error = function(e) {
        showNotification(paste("Error saving sankey plot:", e$message), type = "error")
      })
    }
  }
)

# Network Plot
observeEvent(input$network_plot_btn, {
  req(input$network_plot_experiment)
  req(values$emp_data)
  
  tryCatch({
    emp_obj <- get_empt(input$network_plot_experiment)
    if (is.null(emp_obj)) {
      emp_obj <- convert_mae_to_empt(values$emp_data, experiment = input$network_plot_experiment)
      if (inherits(emp_obj, "EMP")) {
        emp_obj <- emp_obj[[input$network_plot_experiment]]
      }
    }
    if (is.null(emp_obj)) {
      showNotification("Could not convert data to EMPT format", type = "error")
      return()
    }
    
    plot_result <- EMP_network_plot(
      obj = emp_obj,
      experiment = input$network_plot_experiment,
      threshold = input$network_plot_threshold,
      topN = input$network_plot_topN
    )
    
    values$plots$network_plot <- plot_result
    showNotification("Network plot generated!", type = "message")
  }, error = function(e) {
    showNotification(paste("Network plot error:", e$message), type = "error")
  })
})

output$network_plot_output <- renderPlot({
  if (is.null(values$plots$network_plot)) {
    return(NULL)
  }
  print(values$plots$network_plot)
}, width = reactive(if(is.null(input$network_plot_width)) 1000 else input$network_plot_width),
   height = reactive(if(is.null(input$network_plot_height)) 800 else input$network_plot_height))

output$network_plot_download <- downloadHandler(
  filename = function() { "network_plot.pdf" },
  content = function(file) {
    if (!is.null(values$plots$network_plot)) {
      tryCatch({
        if (inherits(values$plots$network_plot, "EMP_network_plot")) {
          # Extract plot from plot_deposit
          plot_obj <- EasyMultiProfiler:::.get.plot_deposit.EMPT(values$plots$network_plot, info = 'EMP_network_plot')
          if (!is.null(plot_obj)) {
            ggsave(file, plot = plot_obj, width = input$network_plot_width/100, 
                   height = input$network_plot_height/100, device = "pdf")
          }
        } else {
          ggsave(file, plot = values$plots$network_plot, width = input$network_plot_width/100, 
                 height = input$network_plot_height/100, device = "pdf")
        }
      }, error = function(e) {
        showNotification(paste("Error saving network plot:", e$message), type = "error")
      })
    }
  }
)

# Enrichment Plots
observeEvent(input$enrich_plots_btn, {
  req(input$enrich_plots_experiment)
  req(values$emp_data)
  
  tryCatch({
    emp_obj <- get_empt(input$enrich_plots_experiment)
    if (is.null(emp_obj)) {
      emp_obj <- convert_mae_to_empt(values$emp_data, experiment = input$enrich_plots_experiment)
      if (inherits(emp_obj, "EMP")) {
        emp_obj <- emp_obj[[input$enrich_plots_experiment]]
      }
    }
    if (is.null(emp_obj)) {
      showNotification("Could not convert data to EMPT format", type = "error")
      return()
    }
    
    if (input$enrich_plots_type == "dotplot") {
      plot_result <- EMP_enrich_dotplot(
        obj = emp_obj,
        experiment = input$enrich_plots_experiment,
        topN = input$enrich_plots_topN
      )
    } else if (input$enrich_plots_type == "netplot") {
      plot_result <- EMP_enrich_netplot(
        obj = emp_obj,
        experiment = input$enrich_plots_experiment,
        topN = input$enrich_plots_topN
      )
    } else {
      plot_result <- EMP_gsea_plot(
        obj = emp_obj,
        experiment = input$enrich_plots_experiment,
        topN = input$enrich_plots_topN
      )
    }
    
    values$plots$enrich_plots <- plot_result
    showNotification("Enrichment plot generated!", type = "message")
  }, error = function(e) {
    showNotification(paste("Enrichment plot error:", e$message), type = "error")
  })
})

output$enrich_plots_output <- renderPlot({
  if (is.null(values$plots$enrich_plots)) {
    return(NULL)
  }
  print(values$plots$enrich_plots)
}, width = reactive(if(is.null(input$enrich_plots_width)) 800 else input$enrich_plots_width),
   height = reactive(if(is.null(input$enrich_plots_height)) 600 else input$enrich_plots_height))

output$enrich_plots_download <- downloadHandler(
  filename = function() { "enrichment_plot.pdf" },
  content = function(file) {
    if (!is.null(values$plots$enrich_plots)) {
      tryCatch({
        # Check for different enrichment plot types
        plot_obj <- NULL
        if (inherits(values$plots$enrich_plots, "EMP_multi_diff_enrich_dotplot")) {
          plot_obj <- EasyMultiProfiler:::.get.plot_deposit.EMPT(values$plots$enrich_plots, info = 'EMP_multi_diff_enrich_dotplot')
        } else if (inherits(values$plots$enrich_plots, "EMP_multi_diff_enrich_netplot")) {
          plot_obj <- EasyMultiProfiler:::.get.plot_deposit.EMPT(values$plots$enrich_plots, info = 'EMP_multi_diff_enrich_netplot')
        } else if (inherits(values$plots$enrich_plots, "EMP_enrich_analysis_dotplot")) {
          plot_obj <- EasyMultiProfiler:::.get.plot_deposit.EMPT(values$plots$enrich_plots, info = 'EMP_enrich_analysis_dotplot')
        }
        
        if (!is.null(plot_obj)) {
          ggsave(file, plot = plot_obj, width = input$enrich_plots_width/100, 
                 height = input$enrich_plots_height/100, device = "pdf")
        } else {
          ggsave(file, plot = values$plots$enrich_plots, width = input$enrich_plots_width/100, 
                 height = input$enrich_plots_height/100, device = "pdf")
        }
      }, error = function(e) {
        showNotification(paste("Error saving enrichment plot:", e$message), type = "error")
      })
    }
  }
)

# Structure Plot
observeEvent(input$structure_plot_btn, {
  req(input$structure_plot_experiment)
  req(values$emp_data)
  
  tryCatch({
    emp_obj <- get_empt(input$structure_plot_experiment)
    if (is.null(emp_obj)) {
      emp_obj <- convert_mae_to_empt(values$emp_data, experiment = input$structure_plot_experiment)
      if (inherits(emp_obj, "EMP")) {
        emp_obj <- emp_obj[[input$structure_plot_experiment]]
      }
    }
    if (is.null(emp_obj)) {
      showNotification("Could not convert data to EMPT format", type = "error")
      return()
    }
    
    plot_result <- EMP_structure_plot(
      obj = emp_obj,
      experiment = input$structure_plot_experiment,
      level = input$structure_plot_level
    )
    
    values$plots$structure_plot <- plot_result
    showNotification("Structure plot generated!", type = "message")
  }, error = function(e) {
    showNotification(paste("Structure plot error:", e$message), type = "error")
  })
})

output$structure_plot_output <- renderPlot({
  if (is.null(values$plots$structure_plot)) {
    return(NULL)
  }
  print(values$plots$structure_plot)
}, width = reactive(if(is.null(input$structure_plot_width)) 1000 else input$structure_plot_width),
   height = reactive(if(is.null(input$structure_plot_height)) 600 else input$structure_plot_height))

output$structure_plot_download <- downloadHandler(
  filename = function() { "structure_plot.pdf" },
  content = function(file) {
    if (!is.null(values$plots$structure_plot)) {
      tryCatch({
        if (inherits(values$plots$structure_plot, "EMP_structure_plot")) {
          # Extract plot from plot_deposit
          plot_obj <- EasyMultiProfiler:::.get.plot_deposit.EMPT(values$plots$structure_plot, info = 'EMP_structure_plot')
          if (!is.null(plot_obj)) {
            ggsave(file, plot = plot_obj, width = input$structure_plot_width/100,
                   height = input$structure_plot_height/100, device = "pdf")
          }
        } else {
          ggsave(file, plot = values$plots$structure_plot, width = input$structure_plot_width/100,
                 height = input$structure_plot_height/100, device = "pdf")
        }
      }, error = function(e) {
        showNotification(paste("Error saving structure plot:", e$message), type = "error")
      })
    }
  }
)
