# Export Server Logic

# Update experiment choices
observe({
  if (!is.null(values$emp_data)) {
    exp_names <- names(values$emp_data)
    updateSelectInput(session, "export_experiment", choices = exp_names)
  }
})

# Export Data
output$export_data_btn <- downloadHandler(
  filename = function() {
    paste0("emp_data_", Sys.Date(), ".", input$export_format)
  },
  content = function(file) {
    req(input$export_experiment)
    req(values$emp_data)
    
    tryCatch({
      emp_obj <- get_empt(input$export_experiment)
      if (is.null(emp_obj)) {
        emp_obj <- convert_mae_to_empt(values$emp_data, experiment = input$export_experiment)
        if (inherits(emp_obj, "EMP")) {
          emp_obj <- emp_obj[[input$export_experiment]]
        }
      }
      if (is.null(emp_obj)) {
        showNotification("Could not convert data to EMPT format", type = "error")
        return()
      }
      assay_data <- as.data.frame(SummarizedExperiment::assay(emp_obj))
      
      if (input$export_format == "csv") {
        write.csv(assay_data, file, row.names = TRUE)
      } else if (input$export_format == "tsv") {
        write.table(assay_data, file, sep = "\t", row.names = TRUE)
      } else if (input$export_format == "xlsx") {
        if (requireNamespace("writexl", quietly = TRUE)) {
          writexl::write_xlsx(assay_data, file)
        } else {
          showNotification("writexl package required for Excel export", type = "error")
        }
      } else if (input$export_format == "rds") {
        saveRDS(values$emp_data, file)
      }
    }, error = function(e) {
      showNotification(paste("Export error:", e$message), type = "error")
    })
  }
)

# Export Analysis Results
output$export_results_btn <- downloadHandler(
  filename = function() {
    paste0("analysis_", input$export_analysis_type, "_", Sys.Date(), ".", input$export_results_format)
  },
  content = function(file) {
    req(input$export_analysis_type)
    
    analysis_result <- values$analysis_results[[input$export_analysis_type]]
    
    if (is.null(analysis_result)) {
      showNotification("No results available for this analysis type", type = "warning")
      return()
    }
    
    tryCatch({
      # Extract results as data frame
      # This would need to be adapted based on actual result structure
      if (is.data.frame(analysis_result)) {
        result_df <- analysis_result
      } else {
        # Try to extract from result object
        result_df <- as.data.frame(analysis_result)
      }
      
      if (input$export_results_format == "csv") {
        write.csv(result_df, file, row.names = TRUE)
      } else if (input$export_results_format == "tsv") {
        write.table(result_df, file, sep = "\t", row.names = TRUE)
      } else if (input$export_results_format == "xlsx") {
        if (requireNamespace("writexl", quietly = TRUE)) {
          writexl::write_xlsx(result_df, file)
        } else {
          showNotification("writexl package required for Excel export", type = "error")
        }
      }
    }, error = function(e) {
      showNotification(paste("Export error:", e$message), type = "error")
    })
  }
)

# Export Plot
output$export_plot_btn <- downloadHandler(
  filename = function() {
    paste0("plot_", input$export_plot_type, "_", Sys.Date(), ".", input$export_plot_format)
  },
  content = function(file) {
    req(input$export_plot_type)
    
    plot_obj <- values$plots[[input$export_plot_type]]
    
    if (is.null(plot_obj)) {
      showNotification("No plot available for this type", type = "warning")
      return()
    }
    
    tryCatch({
      width_in <- input$export_plot_width / input$export_plot_dpi
      height_in <- input$export_plot_height / input$export_plot_dpi
      
      if (input$export_plot_format == "png") {
        png(file, width = input$export_plot_width, height = input$export_plot_height, 
            res = input$export_plot_dpi)
        print(plot_obj)
        dev.off()
      } else if (input$export_plot_format == "pdf") {
        pdf(file, width = width_in, height = height_in)
        print(plot_obj)
        dev.off()
      } else if (input$export_plot_format == "svg") {
        svg(file, width = width_in, height = height_in)
        print(plot_obj)
        dev.off()
      } else if (input$export_plot_format == "eps") {
        postscript(file, width = width_in, height = height_in)
        print(plot_obj)
        dev.off()
      }
    }, error = function(e) {
      showNotification(paste("Export error:", e$message), type = "error")
    })
  }
)

# Export Complete Session
output$export_session_btn <- downloadHandler(
  filename = function() {
    paste0("emp_session_", Sys.Date(), ".rds")
  },
  content = function(file) {
    session_data <- list(
      emp_data = values$emp_data,
      analysis_results = values$analysis_results,
      plots = values$plots,
      timestamp = Sys.time()
    )
    saveRDS(session_data, file)
  }
)
