# Analysis Server Logic

# Update experiment choices for all analysis modules
observe({
  if (!is.null(values$emp_data)) {
    exp_names <- names(values$emp_data)
    updateSelectInput(session, "alpha_experiment", choices = exp_names)
    updateSelectInput(session, "cor_experiment", choices = exp_names)
    updateSelectInput(session, "diff_experiment", choices = exp_names)
    updateSelectInput(session, "dimension_experiment", choices = exp_names)
    updateSelectInput(session, "cluster_experiment", choices = exp_names)
    updateSelectInput(session, "marker_experiment", choices = exp_names)
    # Enrichment and GSEA don't need experiment selection - they use current experiment from differential analysis
    updateSelectInput(session, "wgcna_experiment", choices = exp_names)
    updateSelectInput(session, "network_experiment", choices = exp_names)
    
    # Update current experiment
    if (is.null(values$current_experiment) && length(exp_names) > 0) {
      values$current_experiment <- exp_names[1]
    }
  }
})

# Update current experiment when user selects in analysis modules
observeEvent(input$alpha_experiment, {
  if (!is.null(input$alpha_experiment)) values$current_experiment <- input$alpha_experiment
})
observeEvent(input$cor_experiment, {
  if (!is.null(input$cor_experiment)) values$current_experiment <- input$cor_experiment
})
observeEvent(input$diff_experiment, {
  if (!is.null(input$diff_experiment)) values$current_experiment <- input$diff_experiment
})
observeEvent(input$dimension_experiment, {
  if (!is.null(input$dimension_experiment)) values$current_experiment <- input$dimension_experiment
})
observeEvent(input$cluster_experiment, {
  if (!is.null(input$cluster_experiment)) values$current_experiment <- input$cluster_experiment
})
observeEvent(input$marker_experiment, {
  if (!is.null(input$marker_experiment)) values$current_experiment <- input$marker_experiment
})
# Enrichment and GSEA use current experiment from differential analysis - no need to observe
observeEvent(input$wgcna_experiment, {
  if (!is.null(input$wgcna_experiment)) values$current_experiment <- input$wgcna_experiment
})
observeEvent(input$network_experiment, {
  if (!is.null(input$network_experiment)) values$current_experiment <- input$network_experiment
})

# Update group variable choices
observe({
  req(input$diff_experiment)
  req(values$emp_data)
  
  tryCatch({
    emp_obj <- get_empt(input$diff_experiment)
    if (is.null(emp_obj)) {
      return()
    }
    col_data <- SummarizedExperiment::colData(emp_obj)
    group_vars <- names(col_data)[sapply(col_data, function(x) length(unique(x)) < nrow(col_data) && length(unique(x)) >= 2)]
    updateSelectInput(session, "diff_group", choices = group_vars)
  }, error = function(e) {
    # Silently fail
  })
})

# Update available groups when group variable is selected
observe({
  req(input$diff_experiment)
  req(input$diff_group)
  req(values$emp_data)
  
  tryCatch({
    emp_obj <- get_empt(input$diff_experiment)
    if (is.null(emp_obj)) {
      return()
    }
    col_data <- SummarizedExperiment::colData(emp_obj)
    
    if (input$diff_group %in% names(col_data)) {
      groups <- unique(col_data[[input$diff_group]])
      groups <- groups[!is.na(groups)]
      groups <- sort(as.character(groups))
      
      # Update control group choices
      updateSelectInput(session, "diff_control_group", choices = groups)
    }
  }, error = function(e) {
    # Silently fail
  })
})

# Display groups info and comparison groups
output$diff_groups_info <- renderUI({
  req(input$diff_experiment)
  req(input$diff_group)
  req(values$emp_data)
  
  tryCatch({
    emp_obj <- get_empt(input$diff_experiment)
    if (is.null(emp_obj)) {
      return(NULL)
    }
    col_data <- SummarizedExperiment::colData(emp_obj)
    
    if (input$diff_group %in% names(col_data)) {
      groups <- unique(col_data[[input$diff_group]])
      groups <- groups[!is.na(groups)]
      groups <- sort(as.character(groups))
      
      if (length(groups) < 2) {
        return(helpText("Warning: Selected group variable has less than 2 groups. Please select another variable."))
      }
      
      group_counts <- table(col_data[[input$diff_group]])
      group_info <- paste0(names(group_counts), " (n=", group_counts, ")", collapse = ", ")
      
      return(
        helpText(paste0("Available groups: ", group_info))
      )
    }
  }, error = function(e) {
    return(NULL)
  })
  
  return(NULL)
})

# Display comparison group selector (when multiple groups exist)
output$diff_comparison_group_selector <- renderUI({
  req(input$diff_control_group)
  req(input$diff_experiment)
  req(input$diff_group)
  req(values$emp_data)
  
  tryCatch({
    emp_obj <- get_empt(input$diff_experiment)
    if (is.null(emp_obj)) {
      return(NULL)
    }
    col_data <- SummarizedExperiment::colData(emp_obj)
    
    if (input$diff_group %in% names(col_data)) {
      groups <- unique(col_data[[input$diff_group]])
      groups <- groups[!is.na(groups)]
      groups <- sort(as.character(groups))
      
      comparison_groups <- groups[groups != input$diff_control_group]
      
      if (length(comparison_groups) == 0) {
        return(NULL)
      }
      
      # If multiple comparison groups, show selector
      if (length(comparison_groups) > 1) {
        # Check if method requires exactly 2 groups
        method <- input$diff_method
        two_group_methods <- c("DESeq2", "edgeR_quasi_likelihood", "edgeR_likelihood_ratio", 
                               "edger_robust_likelihood_ratio", "limma_voom", "limma_voom_sample_weights",
                               "t.test", "wilcox.test")
        
        if (method %in% two_group_methods) {
          return(
            selectInput("diff_comparison_group", "Comparison Group (vs Control):",
              choices = comparison_groups,
              width = "100%",
              selected = comparison_groups[1]
            )
          )
        }
      }
    }
  }, error = function(e) {
    return(NULL)
  })
  
  return(NULL)
})

# Display comparison groups (non-control groups)
output$diff_comparison_groups <- renderUI({
  req(input$diff_control_group)
  req(input$diff_experiment)
  req(input$diff_group)
  req(values$emp_data)
  
  tryCatch({
    emp_obj <- get_empt(input$diff_experiment)
    if (is.null(emp_obj)) {
      return(NULL)
    }
    col_data <- SummarizedExperiment::colData(emp_obj)
    
    if (input$diff_group %in% names(col_data)) {
      groups <- unique(col_data[[input$diff_group]])
      groups <- groups[!is.na(groups)]
      groups <- sort(as.character(groups))
      
      comparison_groups <- groups[groups != input$diff_control_group]
      
      if (length(comparison_groups) == 0) {
        return(helpText("No comparison groups available."))
      }
      
      # Determine which comparison group will be used
      selected_comparison <- if (!is.null(input$diff_comparison_group)) {
        input$diff_comparison_group
      } else {
        comparison_groups[1]
      }
      
      if (length(comparison_groups) == 1) {
        return(
          helpText(paste0("Will compare: ", selected_comparison, " vs ", input$diff_control_group))
        )
      } else {
        return(
          helpText(paste0("Will compare: ", selected_comparison, " vs ", input$diff_control_group, 
                         " (", length(comparison_groups), " comparison groups available)"))
        )
      }
    }
  }, error = function(e) {
    return(NULL)
  })
  
  return(NULL)
})

# Alpha Diversity Analysis
observeEvent(input$alpha_btn, {
  req(input$alpha_experiment)
  req(values$emp_data)
  
  tryCatch({
    emp_obj <- get_empt(input$alpha_experiment)
    if (is.null(emp_obj)) {
      emp_obj <- convert_mae_to_empt(values$emp_data, experiment = input$alpha_experiment)
      if (inherits(emp_obj, "EMP")) {
        emp_obj <- emp_obj[[input$alpha_experiment]]
      }
    }
    if (is.null(emp_obj)) {
      showNotification("Could not convert data to EMPT format", type = "error")
      return()
    }
    
    result <- EMP_alpha_analysis(
      obj = emp_obj,
      experiment = input$alpha_experiment,
      use_cached = input$alpha_use_cached
    )
    
    values$analysis_results$alpha <- result
    showNotification("Alpha diversity analysis completed!", type = "message")
  }, error = function(e) {
    showNotification(paste("Alpha diversity error:", e$message), type = "error")
  })
})

output$alpha_results_table <- DT::renderDataTable({
  if (is.null(values$analysis_results$alpha)) {
    return(data.frame())
  }
  # Extract alpha diversity results
  # This would need to be adapted based on actual EMP_alpha_analysis output
  return(data.frame())
}, options = list(pageLength = 10, scrollX = TRUE))

output$alpha_plot <- renderPlot({
  if (is.null(values$analysis_results$alpha)) {
    return(NULL)
  }
  # Plot alpha diversity
  # This would need to be implemented based on actual plotting functions
  return(NULL)
})

# Correlation Analysis
observeEvent(input$cor_btn, {
  req(input$cor_experiment)
  req(values$emp_data)
  
  tryCatch({
    emp_obj <- get_empt(input$cor_experiment)
    if (is.null(emp_obj)) {
      emp_obj <- convert_mae_to_empt(values$emp_data, experiment = input$cor_experiment)
      if (inherits(emp_obj, "EMP")) {
        emp_obj <- emp_obj[[input$cor_experiment]]
      }
    }
    if (is.null(emp_obj)) {
      showNotification("Could not convert data to EMPT format", type = "error")
      return()
    }
    
    result <- EMP_cor_analysis(
      obj = emp_obj,
      experiment = input$cor_experiment,
      method = input$cor_method,
      use_cached = input$cor_use_cached
    )
    
    values$analysis_results$correlation <- result
    showNotification("Correlation analysis completed!", type = "message")
  }, error = function(e) {
    showNotification(paste("Correlation error:", e$message), type = "error")
  })
})

output$cor_results_table <- DT::renderDataTable({
  if (is.null(values$analysis_results$correlation)) {
    return(data.frame())
  }
  return(data.frame())
}, options = list(pageLength = 10, scrollX = TRUE))

output$cor_heatmap <- renderPlot({
  if (is.null(values$analysis_results$correlation)) {
    return(NULL)
  }
  return(NULL)
})

# Differential Analysis
observeEvent(input$diff_btn, {
  req(input$diff_experiment)
  req(input$diff_group)
  req(input$diff_control_group)
  req(values$emp_data)
  
  tryCatch({
    # Get EMPT object
    emp_obj <- get_empt(input$diff_experiment)
    if (is.null(emp_obj)) {
      showNotification("Could not convert data to EMPT format", type = "error")
      return()
    }
    
    # Get all groups and determine comparison groups
    col_data <- SummarizedExperiment::colData(emp_obj)
    if (!input$diff_group %in% names(col_data)) {
      showNotification("Selected group variable not found in metadata", type = "error")
      return()
    }
    
    all_groups <- unique(col_data[[input$diff_group]])
    all_groups <- all_groups[!is.na(all_groups)]
    all_groups <- sort(as.character(all_groups))
    
    if (!input$diff_control_group %in% all_groups) {
      showNotification("Selected control group not found", type = "error")
      return()
    }
    
    comparison_groups <- all_groups[all_groups != input$diff_control_group]
    
    if (length(comparison_groups) == 0) {
      showNotification("No comparison groups available. Please select a different control group.", type = "error")
      return()
    }
    
    # Determine which comparison group to use
    selected_comparison <- if (!is.null(input$diff_comparison_group) && 
                               input$diff_comparison_group %in% comparison_groups) {
      input$diff_comparison_group
    } else {
      comparison_groups[1]  # Default to first comparison group
    }
    
    # For methods that require exactly 2 groups (DESeq2, edgeR, limma, t.test, wilcox.test),
    # filter the data to only include the two selected groups
    method <- input$diff_method
    two_group_methods <- c("DESeq2", "edgeR_quasi_likelihood", "edgeR_likelihood_ratio", 
                           "edger_robust_likelihood_ratio", "limma_voom", "limma_voom_sample_weights",
                           "t.test", "wilcox.test")
    
    if (method %in% two_group_methods) {
      # Filter to only include the two groups
      groups_to_keep <- c(selected_comparison, input$diff_control_group)
      
      # Get sample IDs for these groups
      sample_ids <- rownames(col_data)[col_data[[input$diff_group]] %in% groups_to_keep]
      
      if (length(sample_ids) == 0) {
        showNotification("No samples found for selected groups", type = "error")
        return()
      }
      
      # Filter the EMPT object to only include these samples
      emp_obj <- EMP_filter(
        obj = emp_obj,
        sample_condition = 1 == 1,  # Dummy condition
        feature_condition = 1 == 1,  # Dummy condition
        filterSample = sample_ids,
        action = "select"
      )
      
      # Verify we now have exactly 2 groups
      col_data_filtered <- SummarizedExperiment::colData(emp_obj)
      filtered_groups <- unique(col_data_filtered[[input$diff_group]])
      filtered_groups <- filtered_groups[!is.na(filtered_groups)]
      
      if (length(filtered_groups) != 2) {
        showNotification(paste("Error: After filtering, found", length(filtered_groups), 
                              "groups. Expected 2 groups."), type = "error")
        return()
      }
    }
    
    if (method %in% c("deseq2", "DESeq2", "edgeR_quasi_likelihood", "edgeR_likelihood_ratio", 
                      "edger_robust_likelihood_ratio", "limma_voom", "limma_voom_sample_weights")) {
      # Use formula-based approach
      # Set up group_level with comparison first, then control (for proper comparison direction)
      group_level <- c(selected_comparison, input$diff_control_group)
      
      # For edgeR and limma with group_level, use ~0+Group format
      if (method %in% c("edgeR_quasi_likelihood", "edgeR_likelihood_ratio", 
                       "edger_robust_likelihood_ratio", "limma_voom", "limma_voom_sample_weights")) {
        formula_str <- paste0("~0+", input$diff_group)
        .formula <- as.formula(formula_str)
      } else {
        # For DESeq2, use standard formula
        formula_str <- paste0("~", input$diff_group)
        .formula <- as.formula(formula_str)
      }
      
      result <- EMP_diff_analysis(
        obj = emp_obj,
        experiment = input$diff_experiment,
        method = method,
        .formula = .formula,
        group_level = group_level,
        p.adjust = "fdr",
        use_cached = input$diff_use_cached
      )
    } else {
      # Use estimate_group for simple methods
      # For t.test and wilcox.test, we already filtered to 2 groups above
      # For other methods (kruskal.test, oneway.test), they can handle multiple groups
      if (method %in% c("t.test", "wilcox.test")) {
        # These methods also need exactly 2 groups, so use filtered data
        result <- EMP_diff_analysis(
          obj = emp_obj,
          experiment = input$diff_experiment,
          method = method,
          estimate_group = input$diff_group,
          p.adjust = "fdr",
          use_cached = input$diff_use_cached
        )
      } else {
        # For methods that can handle multiple groups, use all data
        result <- EMP_diff_analysis(
          obj = get_empt(input$diff_experiment),  # Use original unfiltered data
          experiment = input$diff_experiment,
          method = method,
          estimate_group = input$diff_group,
          p.adjust = "fdr",
          use_cached = input$diff_use_cached
        )
      }
    }
    
    # Store the result EMPT object
    values$analysis_results$differential <- result
    
    # Set current experiment so enrichment and GSEA can use it
    values$current_experiment <- input$diff_experiment
    
    # Store the EMPT with differential results for easy access by downstream analyses
    values$analysis_results[[paste0("differential_", input$diff_experiment)]] <- result
    
    # Update MAE with the differential analysis results so they're available for downstream analysis
    # The EMPT object contains the diff results in its deposit, so we need to update the MAE experiment
    if (inherits(result, "EMPT") && inherits(values$emp_data, "MultiAssayExperiment")) {
      # Update the experiment in MAE with the EMPT that contains diff results
      # Extract updated data from EMPT
      new_assay <- SummarizedExperiment::assays(result)[[1]]
      new_rowdata <- SummarizedExperiment::rowData(result)
      new_coldata <- SummarizedExperiment::colData(result)
      
      # Update the experiment in MAE
      exp_obj <- values$emp_data[[input$diff_experiment]]
      SummarizedExperiment::assays(exp_obj)[[1]] <- new_assay
      SummarizedExperiment::rowData(exp_obj) <- new_rowdata
      SummarizedExperiment::colData(exp_obj) <- new_coldata
      
      # Store the EMPT object in a way that preserves the deposit (diff results)
      # We'll store it in analysis_results and also try to preserve it in MAE
      values$emp_data[[input$diff_experiment]] <- exp_obj
    }
    
    showNotification(paste("Differential analysis completed! Comparing", 
                          selected_comparison, "vs", input$diff_control_group, 
                          ". Results are now available for enrichment and GSEA analysis."), 
                    type = "message")
  }, error = function(e) {
    showNotification(paste("Differential analysis error:", e$message), type = "error")
  })
})

output$diff_results_table <- DT::renderDataTable({
  if (is.null(values$analysis_results$differential)) {
    return(data.frame())
  }
  
  tryCatch({
    # Extract differential results using EMP_result
    diff_results <- EMP_result(values$analysis_results$differential, info = "diff_analysis_result")
    
    if (is.null(diff_results) || nrow(diff_results) == 0) {
      return(data.frame())
    }
    
    # Filter by thresholds if provided
    if (!is.null(input$diff_pvalue) && input$diff_pvalue > 0) {
      p_col <- names(diff_results)[grepl("fdr|p.adjust|padj", names(diff_results), ignore.case = TRUE)][1]
      if (!is.null(p_col)) {
        diff_results <- diff_results[diff_results[[p_col]] <= input$diff_pvalue, ]
      }
    }
    
    if (!is.null(input$diff_fc) && input$diff_fc > 0) {
      if ("fold_change" %in% names(diff_results)) {
        diff_results <- diff_results[abs(diff_results$fold_change - 1) >= (input$diff_fc - 1), ]
      } else if ("log2FC" %in% names(diff_results)) {
        diff_results <- diff_results[abs(diff_results$log2FC) >= log2(input$diff_fc), ]
      }
    }
    
    # Convert to data.frame for DT
    as.data.frame(diff_results)
  }, error = function(e) {
    return(data.frame())
  })
}, options = list(pageLength = 10, scrollX = TRUE))

output$diff_volcano_plot <- renderPlot({
  if (is.null(values$analysis_results$differential)) {
    return(NULL)
  }
  
  tryCatch({
    # Extract differential results
    diff_results <- EMP_result(values$analysis_results$differential, info = "diff_analysis_result")
    
    if (is.null(diff_results) || nrow(diff_results) == 0) {
      return(NULL)
    }
    
    # Get p-value and log2FC columns
    p_col <- names(diff_results)[grepl("fdr|p.adjust|padj", names(diff_results), ignore.case = TRUE)][1]
    if (is.null(p_col)) {
      p_col <- "pvalue"
    }
    
    if (!"log2FC" %in% names(diff_results)) {
      if ("fold_change" %in% names(diff_results)) {
        diff_results$log2FC <- log2(diff_results$fold_change)
      } else {
        return(NULL)
      }
    }
    
    # Create volcano plot
    diff_results$neg_log10_p <- -log10(diff_results[[p_col]])
    
    # Determine significance thresholds
    p_thresh <- if (!is.null(input$diff_pvalue) && input$diff_pvalue > 0) input$diff_pvalue else 0.05
    fc_thresh <- if (!is.null(input$diff_fc) && input$diff_fc > 0) log2(input$diff_fc) else log2(1.5)
    
    # Get user-defined colors or use defaults
    color_up <- if (!is.null(input$diff_color_up) && nchar(trimws(input$diff_color_up)) > 0) {
      trimws(input$diff_color_up)
    } else {
      "#E74C3C"  # Red
    }
    
    color_down <- if (!is.null(input$diff_color_down) && nchar(trimws(input$diff_color_down)) > 0) {
      trimws(input$diff_color_down)
    } else {
      "#3498DB"  # Blue
    }
    
    color_ns <- if (!is.null(input$diff_color_ns) && nchar(trimws(input$diff_color_ns)) > 0) {
      trimws(input$diff_color_ns)
    } else {
      "#BDC3C7"  # Gray
    }
    
    # Classify genes: upregulated, downregulated, or not significant
    diff_results$regulation <- "Not significant"
    diff_results$regulation[diff_results[[p_col]] <= p_thresh & diff_results$log2FC >= fc_thresh] <- "Upregulated"
    diff_results$regulation[diff_results[[p_col]] <= p_thresh & diff_results$log2FC <= -fc_thresh] <- "Downregulated"
    diff_results$regulation <- factor(diff_results$regulation, 
                                      levels = c("Not significant", "Downregulated", "Upregulated"))
    
    # Check if we have sign_group for multi-group coloring
    has_sign_group <- "sign_group" %in% names(diff_results)
    unique_groups <- if (has_sign_group) {
      unique(diff_results$sign_group[!is.na(diff_results$sign_group)])
    } else {
      character(0)
    }
    n_groups <- length(unique_groups)
    
    if (has_sign_group && n_groups > 1) {
      # Multi-group: combine regulation and sign_group for coloring
      diff_results$color_group <- paste0(diff_results$regulation, "_", diff_results$sign_group)
      diff_results$color_group[is.na(diff_results$sign_group)] <- as.character(diff_results$regulation[is.na(diff_results$sign_group)])
      
      # Create color palette with user-defined base colors
      # Generate color variations for multiple groups
      color_values <- c("Not significant" = color_ns)
      
      # Generate color shades for upregulated (red tones) and downregulated (blue tones)
      if (n_groups <= 3) {
        # For few groups, use distinct colors
        up_colors <- c("#FF6B6B", "#FF4757", "#EE5A6F")[1:n_groups]  # Red shades
        down_colors <- c("#4ECDC4", "#45B7B8", "#3498DB")[1:n_groups]  # Blue/cyan shades
      } else {
        # For many groups, generate color gradients using base R
        up_colors <- grDevices::colorRampPalette(c("#FFE5E5", color_up))(n_groups)
        down_colors <- grDevices::colorRampPalette(c("#E5F3FF", color_down))(n_groups)
      }
      
      # Assign colors to each group
      for (i in seq_along(unique_groups)) {
        color_values[paste0("Upregulated_", unique_groups[i])] <- up_colors[i]
        color_values[paste0("Downregulated_", unique_groups[i])] <- down_colors[i]
      }
      
      # Plot with group-based coloring
      p <- ggplot2::ggplot(diff_results, ggplot2::aes(x = log2FC, y = neg_log10_p, color = color_group)) +
        ggplot2::geom_point(alpha = 0.7, size = 1.8) +
        ggplot2::geom_hline(yintercept = -log10(p_thresh), linetype = "dashed", color = "gray50", linewidth = 0.8) +
        ggplot2::geom_vline(xintercept = c(-fc_thresh, fc_thresh), linetype = "dashed", color = "gray50", linewidth = 0.8) +
        ggplot2::scale_color_manual(
          values = color_values,
          name = "Regulation by Group",
          guide = ggplot2::guide_legend(override.aes = list(size = 4, alpha = 1), ncol = 1)
        ) +
        ggplot2::labs(
          x = "Log2 Fold Change",
          y = paste0("-Log10 ", if(p_col == "pvalue") "P-value" else "Adjusted P-value"),
          title = "Volcano Plot - Differential Expression Analysis",
          subtitle = paste0("Upregulated: ", color_up, " | Downregulated: ", color_down, " | Non-significant: ", color_ns)
        ) +
        ggplot2::theme_minimal(base_size = 12) +
        ggplot2::theme(
          legend.position = "right",
          legend.title = ggplot2::element_text(face = "bold"),
          plot.title = ggplot2::element_text(hjust = 0.5, size = 16, face = "bold"),
          plot.subtitle = ggplot2::element_text(hjust = 0.5, size = 10, color = "gray50"),
          panel.grid.minor = ggplot2::element_blank()
        )
    } else {
      # Single group: simple up/down/non-significant coloring with user-defined colors
      color_values <- c(
        "Not significant" = color_ns,
        "Downregulated" = color_down,
        "Upregulated" = color_up
      )
      
      p <- ggplot2::ggplot(diff_results, ggplot2::aes(x = log2FC, y = neg_log10_p, color = regulation)) +
        ggplot2::geom_point(alpha = 0.7, size = 1.8) +
        ggplot2::geom_hline(yintercept = -log10(p_thresh), linetype = "dashed", color = "gray50", linewidth = 0.8) +
        ggplot2::geom_vline(xintercept = c(-fc_thresh, fc_thresh), linetype = "dashed", color = "gray50", linewidth = 0.8) +
        ggplot2::scale_color_manual(
          values = color_values,
          name = "Regulation",
          labels = c("Not significant" = "Not significant", 
                    "Downregulated" = "Downregulated", 
                    "Upregulated" = "Upregulated"),
          guide = ggplot2::guide_legend(override.aes = list(size = 4, alpha = 1))
        ) +
        ggplot2::labs(
          x = "Log2 Fold Change",
          y = paste0("-Log10 ", if(p_col == "pvalue") "P-value" else "Adjusted P-value"),
          title = "Volcano Plot - Differential Expression Analysis",
          caption = paste0("Thresholds: P-value ≤ ", p_thresh, ", |Log2FC| ≥ ", round(fc_thresh, 2))
        ) +
        ggplot2::theme_minimal(base_size = 12) +
        ggplot2::theme(
          legend.position = "right",
          legend.title = ggplot2::element_text(face = "bold"),
          plot.title = ggplot2::element_text(hjust = 0.5, size = 16, face = "bold"),
          plot.caption = ggplot2::element_text(hjust = 0.5, size = 9, color = "gray50"),
          panel.grid.minor = ggplot2::element_blank()
        )
    }
    
    return(p)
  }, error = function(e) {
    return(NULL)
  })
})

# Show current experiment info for dimension reduction
output$dimension_experiment_info <- renderUI({
  if (is.null(values$current_experiment)) {
    return(
      helpText("Please select an experiment from Data Summary or run an analysis first.", 
               style = "color: orange; font-weight: bold;")
    )
  }
  
  return(
    helpText(paste("Using experiment:", values$current_experiment), 
             style = "color: green; font-weight: bold;")
  )
})

# Update dimension group choices
observe({
  if (is.null(values$current_experiment) || is.null(values$emp_data)) {
    return()
  }
  
  tryCatch({
    emp_obj <- get_empt(values$current_experiment)
    if (is.null(emp_obj)) {
      return()
    }
    
    col_data <- SummarizedExperiment::colData(emp_obj)
    group_cols <- names(col_data)[sapply(col_data, function(x) {
      is.character(x) || is.factor(x)
    })]
    
    updateSelectInput(session, "dimension_group", choices = group_cols)
  }, error = function(e) {
    return()
  })
})

# Dimension Reduction
observeEvent(input$dimension_btn, {
  if (is.null(values$current_experiment)) {
    showNotification("No experiment selected. Please select an experiment first.", type = "error")
    return()
  }
  
  req(values$emp_data)
  
  tryCatch({
    emp_obj <- get_empt(values$current_experiment)
    if (is.null(emp_obj)) {
      showNotification("Could not convert data to EMPT format", type = "error")
      return()
    }
    
    # EMP_dimension_analysis accepts experiment parameter
    # For PCOA, need distance parameter
    if (input$dimension_method == "pcoa") {
      result <- EMP_dimension_analysis(
        obj = emp_obj,
        experiment = values$current_experiment,
        method = input$dimension_method,
        distance = "bray",  # Default distance for PCOA
        estimate_group = input$dimension_group,  # Group variable for coloring
        use_cached = input$dimension_use_cached
      )
    } else {
      result <- EMP_dimension_analysis(
        obj = emp_obj,
        experiment = values$current_experiment,
        method = input$dimension_method,
        estimate_group = input$dimension_group,  # Group variable for coloring
        use_cached = input$dimension_use_cached
      )
    }
    
    values$analysis_results$dimension <- result
    showNotification("Dimension reduction completed!", type = "message")
  }, error = function(e) {
    showNotification(paste("Dimension reduction error:", e$message), type = "error")
  })
})

# Cluster Analysis
observeEvent(input$cluster_btn, {
  req(input$cluster_experiment)
  req(values$emp_data)
  
  tryCatch({
    emp_obj <- get_empt(input$cluster_experiment)
    if (is.null(emp_obj)) {
      emp_obj <- convert_mae_to_empt(values$emp_data, experiment = input$cluster_experiment)
      if (inherits(emp_obj, "EMP")) {
        emp_obj <- emp_obj[[input$cluster_experiment]]
      }
    }
    if (is.null(emp_obj)) {
      showNotification("Could not convert data to EMPT format", type = "error")
      return()
    }
    
    result <- EMP_cluster_analysis(
      obj = emp_obj,
      experiment = input$cluster_experiment,
      method = input$cluster_method,
      use_cached = input$cluster_use_cached
    )
    
    values$analysis_results$cluster <- result
    showNotification("Cluster analysis completed!", type = "message")
  }, error = function(e) {
    showNotification(paste("Cluster analysis error:", e$message), type = "error")
  })
})

# Show current experiment info for enrichment
output$enrichment_experiment_info <- renderUI({
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

# Check if experiment has differential analysis results
output$enrichment_diff_warning <- renderUI({
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
    # Use the saved EMPT with diff results
    emp_obj <- values$analysis_results[[diff_key]]
  } else {
    # Fallback: try to get from MAE
    emp_obj <- get_empt(values$current_experiment)
  }
  
  if (is.null(emp_obj)) {
    return(
      helpText("Warning: Could not access experiment data. Please run differential analysis first.", 
               style = "color: orange;")
    )
  }
  
  tryCatch({
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

# Show group filter options if differential results have sign_group
output$enrichment_group_filter <- renderUI({
  if (is.null(values$current_experiment)) {
    return(NULL)
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
    return(NULL)
  }
  
  tryCatch({
    diff_results <- tryCatch({
      EMP_result(emp_obj, info = "diff_analysis_result")
    }, error = function(e) NULL)
    
    if (is.null(diff_results) || !"sign_group" %in% names(diff_results)) {
      return(NULL)
    }
    
    # Get available groups
    available_groups <- unique(diff_results$sign_group)
    available_groups <- available_groups[!is.na(available_groups)]
    
    if (length(available_groups) > 0) {
      return(
        selectInput("enrichment_filter_group", "Filter by Group (optional):",
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

# Enrichment Analysis
observeEvent(input$enrichment_btn, {
  if (is.null(values$current_experiment)) {
    showNotification("No experiment selected. Please run differential analysis first.", 
                    type = "error")
    return()
  }
  
  tryCatch({
    # Get EMPT object with differential analysis results
    # First try to get the saved EMPT with diff results
    diff_key <- paste0("differential_", values$current_experiment)
    emp_obj <- NULL
    
    if (!is.null(values$analysis_results[[diff_key]])) {
      # Use the saved EMPT that contains differential analysis results
      emp_obj <- values$analysis_results[[diff_key]]
    } else {
      # Fallback: try to get from MAE (less preferred, may not have diff results)
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
    
    # Build condition expression based on user filters
    conditions <- c()
    
    # P-value filter
    p_col <- if (input$enrichment_pvalue_type == "fdr") {
      # Find FDR column
      fdr_col <- names(diff_results)[grepl("fdr|p.adjust|padj", names(diff_results), ignore.case = TRUE)][1]
      if (is.null(fdr_col)) "pvalue" else fdr_col
    } else {
      "pvalue"
    }
    
    conditions <- c(conditions, paste0(p_col, " < ", input$enrichment_pvalue_threshold))
    
    # Fold change filter
    if (input$enrichment_fc_threshold > 0) {
      if ("log2FC" %in% names(diff_results)) {
        conditions <- c(conditions, paste0("abs(log2FC) >= ", log2(input$enrichment_fc_threshold)))
      } else if ("fold_change" %in% names(diff_results)) {
        conditions <- c(conditions, paste0("abs(fold_change - 1) >= ", (input$enrichment_fc_threshold - 1)))
      }
    }
    
    # Direction filter (up/downregulated)
    if (input$enrichment_direction == "up") {
      if ("log2FC" %in% names(diff_results)) {
        conditions <- c(conditions, "log2FC > 0")
      } else if ("fold_change" %in% names(diff_results)) {
        conditions <- c(conditions, "fold_change > 1")
      }
    } else if (input$enrichment_direction == "down") {
      if ("log2FC" %in% names(diff_results)) {
        conditions <- c(conditions, "log2FC < 0")
      } else if ("fold_change" %in% names(diff_results)) {
        conditions <- c(conditions, "fold_change < 1")
      }
    }
    
    # Group filter
    if (!is.null(input$enrichment_filter_group) && input$enrichment_filter_group != "all") {
      if ("sign_group" %in% names(diff_results)) {
        conditions <- c(conditions, paste0("sign_group == '", input$enrichment_filter_group, "'"))
      }
    }
    
    # Build condition expression
    # EMP_enrich_analysis uses dplyr::enquo, so we need to build the call with substitute
    condition_str <- paste(conditions, collapse = " & ")
    condition_parsed <- parse(text = condition_str)[[1]]
    
    # Set up organism-specific parameters
    organism <- input$enrichment_organism
    method <- tolower(input$enrichment_method)
    
    # Prepare parameters based on method
    if (method == "go") {
      # Load appropriate OrgDb
      if (organism == "human") {
        if (!requireNamespace("org.Hs.eg.db", quietly = TRUE)) {
          showNotification("Please install org.Hs.eg.db: BiocManager::install('org.Hs.eg.db')", 
                         type = "error")
          return()
        }
        OrgDb <- org.Hs.eg.db::org.Hs.eg.db
      } else if (organism == "mouse") {
        if (!requireNamespace("org.Mm.eg.db", quietly = TRUE)) {
          showNotification("Please install org.Mm.eg.db: BiocManager::install('org.Mm.eg.db')", 
                         type = "error")
          return()
        }
        OrgDb <- org.Mm.eg.db::org.Mm.eg.db
      } else if (organism == "rat") {
        if (!requireNamespace("org.Rn.eg.db", quietly = TRUE)) {
          showNotification("Please install org.Rn.eg.db: BiocManager::install('org.Rn.eg.db')", 
                         type = "error")
          return()
        }
        OrgDb <- org.Rn.eg.db::org.Rn.eg.db
      }
      
      # Build call with substitute to pass condition unevaluated
      enrich_call <- substitute(
        EMP_enrich_analysis(
          obj = emp_obj,
          condition = cond,
          method = "go",
          OrgDb = OrgDb,
          ont = ont_val,
          keyType = "ENTREZID",
          minGSSize = minGS,
          maxGSSize = maxGS,
          pvalueCutoff = qval,
          use_cached = cached
        ),
        list(
          cond = condition_parsed,
          ont_val = input$enrichment_ontology,
          minGS = input$enrichment_minGSSize,
          maxGS = input$enrichment_maxGSSize,
          qval = input$enrichment_qvalue,
          cached = input$enrichment_use_cached
        )
      )
      result <- eval(enrich_call)
    } else if (method == "kegg") {
      # KEGG species codes
      species_map <- list(
        "human" = "hsa",
        "mouse" = "mmu",
        "rat" = "rno"
      )
      species <- species_map[[organism]]
      
      enrich_call <- substitute(
        EMP_enrich_analysis(
          obj = emp_obj,
          condition = cond,
          method = "kegg",
          species = sp,
          keyType = "entrezid",
          minGSSize = minGS,
          maxGSSize = maxGS,
          pvalueCutoff = qval,
          use_cached = cached
        ),
        list(
          cond = condition_parsed,
          sp = species,
          minGS = input$enrichment_minGSSize,
          maxGS = input$enrichment_maxGSSize,
          qval = input$enrichment_qvalue,
          cached = input$enrichment_use_cached
        )
      )
      result <- eval(enrich_call)
    } else if (method == "reactome") {
      enrich_call <- substitute(
        EMP_enrich_analysis(
          obj = emp_obj,
          condition = cond,
          method = "reactome",
          organism = org,
          minGSSize = minGS,
          maxGSSize = maxGS,
          pvalueCutoff = qval,
          use_cached = cached
        ),
        list(
          cond = condition_parsed,
          org = organism,
          minGS = input$enrichment_minGSSize,
          maxGS = input$enrichment_maxGSSize,
          qval = input$enrichment_qvalue,
          cached = input$enrichment_use_cached
        )
      )
      result <- eval(enrich_call)
    } else if (method == "do") {
      # DOSE organism codes
      organism_map <- list(
        "human" = "hsa",
        "mouse" = "mmu",
        "rat" = "hsa"  # Rat not directly supported, use human as fallback
      )
      do_organism <- organism_map[[organism]]
      
      enrich_call <- substitute(
        EMP_enrich_analysis(
          obj = emp_obj,
          condition = cond,
          method = "do",
          ont = "HDO",
          organism = do_org,
          minGSSize = minGS,
          maxGSSize = maxGS,
          pvalueCutoff = qval,
          use_cached = cached
        ),
        list(
          cond = condition_parsed,
          do_org = do_organism,
          minGS = input$enrichment_minGSSize,
          maxGS = input$enrichment_maxGSSize,
          qval = input$enrichment_qvalue,
          cached = input$enrichment_use_cached
        )
      )
      result <- eval(enrich_call)
    }
    
    values$analysis_results$enrichment <- result
    showNotification("Enrichment analysis completed!", type = "message")
  }, error = function(e) {
    showNotification(paste("Enrichment analysis error:", e$message), type = "error")
  })
})

# Enrichment Results Table
output$enrichment_results_table <- DT::renderDataTable({
  if (is.null(values$analysis_results$enrichment)) {
    return(data.frame())
  }
  
  tryCatch({
    # Extract enrichment results
    enrich_results <- EMP_result(values$analysis_results$enrichment, info = "enrich_data")
    
    if (is.null(enrich_results)) {
      return(data.frame())
    }
    
    # Handle different result types (compareClusterResult or enrichResult)
    if (inherits(enrich_results, "compareClusterResult")) {
      result_df <- enrich_results@compareClusterResult
    } else if (inherits(enrich_results, "enrichResult")) {
      result_df <- enrich_results@result
    } else {
      return(data.frame())
    }
    
    if (is.null(result_df) || nrow(result_df) == 0) {
      return(data.frame())
    }
    
    # Convert to data.frame for DT
    as.data.frame(result_df)
  }, error = function(e) {
    return(data.frame())
  })
}, options = list(pageLength = 10, scrollX = TRUE))

# Enrichment Dotplot
output$enrichment_dotplot <- renderPlot({
  if (is.null(values$analysis_results$enrichment)) {
    return(NULL)
  }
  
  tryCatch({
    # Use EMP_enrich_dotplot if available
    if (exists("EMP_enrich_dotplot", where = asNamespace("EasyMultiProfiler"), mode = "function")) {
      plot_result <- EMP_enrich_dotplot(values$analysis_results$enrichment)
      return(plot_result)
    } else {
      # Fallback: extract results and create basic plot
      enrich_results <- EMP_result(values$analysis_results$enrichment, info = "enrich_data")
      
      if (is.null(enrich_results)) {
        return(NULL)
      }
      
      if (inherits(enrich_results, "compareClusterResult")) {
        result_df <- enrich_results@compareClusterResult
      } else if (inherits(enrich_results, "enrichResult")) {
        result_df <- enrich_results@result
      } else {
        return(NULL)
      }
      
      if (is.null(result_df) || nrow(result_df) == 0) {
        return(NULL)
      }
      
      # Create a simple dotplot
      # This is a basic implementation - EMP_enrich_dotplot would be better
      return(NULL)
    }
  }, error = function(e) {
    return(NULL)
  })
})

# Show current experiment info for GSEA
output$gsea_experiment_info <- renderUI({
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

# Check if experiment has differential analysis results for GSEA
output$gsea_diff_warning <- renderUI({
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

# GSEA Analysis
observeEvent(input$gsea_btn, {
  if (is.null(values$current_experiment)) {
    showNotification("No experiment selected. Please run differential analysis first.", 
                    type = "error")
    return()
  }
  
  tryCatch({
    # Get EMPT object with differential analysis results
    # First try to get the saved EMPT with diff results
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
    
    # Map organism to OrgDb format
    organism_map <- list(
      "human" = "org.Hs.eg.db",
      "mouse" = "org.Mm.eg.db",
      "rat" = "org.Rn.eg.db"
    )
    organism_db <- organism_map[[input$gsea_organism]]
    
    # EMP_GSEA_analysis requires condition and experiment parameters
    # Build condition expression from differential results
    condition_str <- paste0("pvalue < ", input$gsea_pvalue)
    condition_expr <- parse(text = condition_str)[[1]]
    
    # Map organism for GSEA (organism parameter expects species name)
    organism_map <- list(
      "human" = "Homo sapiens",
      "mouse" = "Mus musculus",
      "rat" = "Rattus norvegicus"
    )
    organism_name <- organism_map[[input$gsea_organism]]
    
    result <- EMP_GSEA_analysis(
      obj = emp_obj,
      condition = condition_expr,
      experiment = values$current_experiment,
      method = "log2FC",  # Use log2FC method for ranking genes
      enrich_method = "kegg",  # Default enrichment method
      organism = organism_name,
      use_cached = input$gsea_use_cached
    )
    
    values$analysis_results$gsea <- result
    showNotification("GSEA analysis completed!", type = "message")
  }, error = function(e) {
    showNotification(paste("GSEA error:", e$message), type = "error")
  })
})

# WGCNA Analysis
observeEvent(input$wgcna_btn, {
  req(input$wgcna_experiment)
  req(values$emp_data)
  
  tryCatch({
    emp_obj <- get_empt(input$wgcna_experiment)
    if (is.null(emp_obj)) {
      emp_obj <- convert_mae_to_empt(values$emp_data, experiment = input$wgcna_experiment)
      if (inherits(emp_obj, "EMP")) {
        emp_obj <- emp_obj[[input$wgcna_experiment]]
      }
    }
    if (is.null(emp_obj)) {
      showNotification("Could not convert data to EMPT format", type = "error")
      return()
    }
    
    result <- EMP_WGCNA_cluster_analysis(
      obj = emp_obj,
      experiment = input$wgcna_experiment,
      use_cached = input$wgcna_use_cached
    )
    
    values$analysis_results$wgcna <- result
    showNotification("WGCNA analysis completed!", type = "message")
  }, error = function(e) {
    showNotification(paste("WGCNA error:", e$message), type = "error")
  })
})

# Network Analysis
observeEvent(input$network_btn, {
  req(input$network_experiment)
  req(values$emp_data)
  
  tryCatch({
    emp_obj <- get_empt(input$network_experiment)
    if (is.null(emp_obj)) {
      emp_obj <- convert_mae_to_empt(values$emp_data, experiment = input$network_experiment)
      if (inherits(emp_obj, "EMP")) {
        emp_obj <- emp_obj[[input$network_experiment]]
      }
    }
    if (is.null(emp_obj)) {
      showNotification("Could not convert data to EMPT format", type = "error")
      return()
    }
    
    result <- EMP_network_analysis(
      obj = emp_obj,
      experiment = input$network_experiment,
      use_cached = input$network_use_cached
    )
    
    values$analysis_results$network <- result
    showNotification("Network analysis completed!", type = "message")
  }, error = function(e) {
    showNotification(paste("Network analysis error:", e$message), type = "error")
  })
})
