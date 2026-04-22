# Server Utility Functions

# Helper function to get EMPT object from MAE
get_empt_from_mae <- function(mae_obj, experiment) {
  if (is.null(mae_obj) || is.null(experiment)) {
    return(NULL)
  }
  
  # Check if experiment exists
  if (!experiment %in% names(mae_obj)) {
    return(NULL)
  }
  
  # Use as.EMP to convert MAE to EMP, then extract EMPT
  # Or use the internal .as.EMPT function if available
  # For now, we'll try to use EMP functions that work with MAE directly
  # If that doesn't work, we'll need to convert
  
  # Use .as.EMPT directly (internal function used throughout the package)
  # This is the standard way to convert MAE to EMPT in EasyMultiProfiler
  tryCatch({
    empt <- EasyMultiProfiler:::.as.EMPT(mae_obj, experiment = experiment)
    if (is.null(empt)) {
      return(NULL)
    }
    # Verify it's an EMPT object
    if (!inherits(empt, "EMPT")) {
      return(NULL)
    }
    return(empt)
  }, error = function(e) {
    # Log error for debugging (but don't show to user in helper function)
    # The calling function will handle user notifications
    return(NULL)
  })
}

# Helper to check if object is MAE or EMPT
is_mae_or_empt <- function(obj) {
  if (is.null(obj)) return(FALSE)
  return(inherits(obj, "MultiAssayExperiment") || inherits(obj, "EMPT") || inherits(obj, "EMP"))
}

# Helper to get experiment names
get_experiment_names <- function(obj) {
  if (is.null(obj)) return(character(0))
  
  if (inherits(obj, "MultiAssayExperiment")) {
    return(names(obj))
  } else if (inherits(obj, "EMP")) {
    return(names(obj))
  }
  return(character(0))
}
