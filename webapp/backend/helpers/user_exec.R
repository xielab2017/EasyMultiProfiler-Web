# User-submitted R execution (local learning).
# Runs in the same R process as Plumber with access to globalenv() — equivalent
# to giving the caller arbitrary code execution. Intended ONLY for trusted
# localhost / single-user setups; never expose without authentication.

.exec_user_plot_string <- function(x) {
  if (is.null(x) || !is.character(x) || length(x) != 1L) return(NULL)
  out <- unname(as.character(x[[1L]]))
  if (!nzchar(out)) return(NULL)
  out
}

.exec_user_format_value <- function(v, plot_width, plot_height) {
  if (is.character(v) && length(v) == 1L && nzchar(v) && nchar(v) > 200L &&
        !grepl("\n", v, fixed = TRUE) && grepl("^[A-Za-z0-9+/=]+$", v)) {
    p <- .exec_user_plot_string(v)
    if (!is.null(p)) return(list(has_plot = TRUE, plot = p, text = NULL))
  }
  if (is.list(v) && !is.null(v$plot) && is.character(v$plot) && length(v$plot) == 1L &&
        nzchar(v$plot)) {
    p <- .exec_user_plot_string(v$plot)
    if (!is.null(p)) return(list(has_plot = TRUE, plot = p, text = NULL))
  }
  if (is.list(v) && !is.null(v$png) && is.character(v$png) && length(v$png) == 1L &&
        nzchar(v$png)) {
    p <- .exec_user_plot_string(v$png)
    if (!is.null(p)) return(list(has_plot = TRUE, plot = p, text = NULL))
  }
  if (inherits(v, "ggplot")) {
    if (!exists("plot_to_base64", mode = "function", inherits = TRUE)) {
      return(list(has_plot = FALSE, text = "ggplot object (plot_to_base64 unavailable)"))
    }
    img <- plot_to_base64(v, width = plot_width, height = plot_height) # nolint: object_usage_linter
    p <- .exec_user_plot_string(img)
    if (!is.null(p)) return(list(has_plot = TRUE, plot = p, text = NULL))
  }
  if (is.null(v)) return(list(has_plot = FALSE, text = "(NULL)", tables = list()))
  txt <- tryCatch({
    paste(utils::capture.output(utils::str(v, max.level = 2, vec.len = 2)), collapse = "\n")
  }, error = function(e) sprintf("<str() error: %s>", conditionMessage(e)))
  if (nchar(txt) > 12000L) txt <- paste0(substr(txt, 1, 12000L), "\n… [truncated]")
  list(has_plot = FALSE, text = txt, tables = .exec_user_extract_tables(v))
}

.exec_user_table_payload <- function(name, x, max_rows = 500L) {
  if (!is.data.frame(x)) return(NULL)
  df <- utils::head(as.data.frame(x, stringsAsFactors = FALSE), max_rows)
  list(
    name = as.character(name),
    n_rows = nrow(x),
    n_cols = ncol(x),
    json = jsonlite::toJSON(df, dataframe = "rows", na = "null", auto_unbox = TRUE)
  )
}

.exec_user_extract_tables <- function(v) {
  out <- list()
  add <- function(name, x) {
    tab <- .exec_user_table_payload(name, x)
    if (!is.null(tab)) out[[length(out) + 1L]] <<- tab
  }
  if (is.data.frame(v)) {
    add("result", v)
  } else if (is.list(v)) {
    for (nm in names(v)) {
      if (is.data.frame(v[[nm]])) add(nm, v[[nm]])
    }
  }
  out
}

.exec_user_safe_name <- function(x, fallback = "code_lab") {
  x <- paste(as.character(x %||% fallback), collapse = "_")
  x <- gsub("[^A-Za-z0-9_.-]+", "_", x)
  x <- gsub("^_+|_+$", "", x)
  if (!nzchar(x)) fallback else substr(x, 1L, 80L)
}

.exec_user_artifact_root <- function(session_id) {
  file.path(session_path(session_id), "code_lab_runs") # nolint: object_usage_linter
}

.exec_user_save_artifacts <- function(session_id, workflow, tab, label, code, source_code,
                                      stdout, value_text, plot, tables) {
  stamp <- format(Sys.time(), "%Y%m%d-%H%M%S")
  run_id <- paste(stamp, .exec_user_safe_name(workflow), .exec_user_safe_name(tab), sep = "_")
  base <- file.path(.exec_user_artifact_root(session_id), run_id)
  dir.create(file.path(base, "tables"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(base, "plots"), recursive = TRUE, showWarnings = FALSE)

  writeLines(code %||% "", file.path(base, "optimized_script.R"), useBytes = TRUE)
  writeLines(source_code %||% "", file.path(base, "system_source.R"), useBytes = TRUE)
  writeLines(stdout %||% "", file.path(base, "stdout.txt"), useBytes = TRUE)
  writeLines(value_text %||% "", file.path(base, "value.txt"), useBytes = TRUE)

  plot_file <- NULL
  p <- .exec_user_plot_string(plot)
  if (!is.null(p)) {
    p <- sub("^data:image/png;base64,", "", p)
    plot_file <- file.path(base, "plots", "plot.png")
    tryCatch(writeBin(base64enc::base64decode(p), plot_file), error = function(e) {
      plot_file <<- NULL
    })
  }

  table_files <- character(0)
  if (is.list(tables) && length(tables)) {
    for (i in seq_along(tables)) {
      tab_i <- tables[[i]]
      nm <- .exec_user_safe_name(tab_i$name %||% paste0("table_", i), paste0("table_", i))
      df <- tryCatch(jsonlite::fromJSON(tab_i$json %||% "[]"), error = function(e) NULL)
      if (is.data.frame(df)) {
        out <- file.path(base, "tables", paste0(sprintf("%02d_", i), nm, ".csv"))
        utils::write.csv(df, out, row.names = FALSE)
        table_files <- c(table_files, out)
      }
    }
  }

  manifest <- list(
    success = TRUE,
    run_id = run_id,
    label = label %||% "",
    workflow = workflow %||% "",
    tab = tab %||% "",
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    files = list(
      optimized_script = "optimized_script.R",
      system_source = "system_source.R",
      stdout = "stdout.txt",
      value = "value.txt",
      plot = if (!is.null(plot_file)) "plots/plot.png" else NULL,
      tables = file.path("tables", basename(table_files))
    )
  )
  writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE, null = "null"),
             file.path(base, "manifest.json"), useBytes = TRUE)
  zip_path <- file.path(.exec_user_artifact_root(session_id), paste0(run_id, ".zip"))
  tryCatch(zip_dir(base, zip_path), error = function(e) NULL) # nolint: object_usage_linter
  list(run_id = run_id, zip_name = basename(zip_path), zip_path = zip_path, dir = base)
}

exec_user_r_learning <- function(session_id, experiment, code, plot_width = 9, plot_height = 6,
                                 workflow = NULL, tab = NULL, label = NULL, source_code = NULL) {
  if (!nzchar(trimws(as.character(session_id %||% "")))) stop("session_id required")
  if (!session_exists(session_id)) stop("invalid or expired session_id") # nolint: object_usage_linter
  code <- paste(as.character(code), collapse = "\n")
  if (!nzchar(trimws(code))) stop("code is empty")
  if (nchar(code) > 500000L) stop("code exceeds 500 000 characters")

  env <- new.env(parent = globalenv())
  env$session_id <- session_id
  exp_chr <- NULL
  if (!is.null(experiment)) {
    exp_chr <- tryCatch(as.character(experiment)[[1]], error = function(e) NULL)
    if (!is.null(exp_chr) && nzchar(exp_chr)) env$experiment <- exp_chr
  }

  for (nm in c(
    "load_empt", "load_mae", "load_raw_empt", "save_empt", "save_mae",
    ".prepare_load_base",
    "list_clinical_vars", "list_clinical_vars_standalone",
    "make_clinical_three_line_table", "make_clinical_three_line_table_experiment",
    "run_clinical_systematic_summary", "run_clinical_cor",
    "make_fitline_scatter", "run_clinical_wgcna", "submit_job",
    "session_path",
    "make_barplot", "make_boxplot", "make_heatmap", "make_volcano",
    "make_scatter", "make_structure", "make_alpha_plot", "plot_to_base64",
    "save_prepare_snapshot", "emp_prepare_preview_rows"
  )) {
    if (exists(nm, mode = "function", inherits = TRUE)) {
      assign(nm, get(nm, mode = "function", inherits = TRUE), envir = env)
    }
  }
  # So pasted viz.R bodies (e.g. make_barplot) can run without rewriting helpers:
  for (nm in c(
    ".viz_group_levels", ".viz_feature_labels", ".viz_pick_group",
    ".viz_emp_dimension_bundle", ".heatmap_response", ".parse_feature_list",
    "emp_set_color_panel", "emp_restore_color_panel", "emp_pub_theme",
    "emp_pub_palette", "emp_normalize_color_panel", "emp_get_color_panel",
    "emp_scale_fill_pub", "emp_scale_color_pub", "emp_diverging_colors",
    "emp_conf_ellipse", "emp_pairwise_wilcox", "emp_permanova_p", "emp_permanova_bray",
    "emp_caption"
  )) {
    if (exists(nm, inherits = TRUE)) {
      assign(nm, get(nm, inherits = TRUE), envir = env)
    }
  }

  expr <- tryCatch(parse(text = code), error = function(e) stop(e$message))
  n <- length(expr)
  if (n < 1L) stop("nothing to parse")

  holder <- new.env(parent = emptyenv())
  holder$last <- NULL

  so <- tryCatch(
    utils::capture.output({
      if (n == 1L) {
        holder$last <- eval(expr[[1L]], envir = env)
      } else {
        for (i in seq_len(n - 1L)) eval(expr[[i]], envir = env)
        holder$last <- eval(expr[[n]], envir = env)
      }
    }),
    error = function(e) stop(e$message)
  )

  fmt <- .exec_user_format_value(holder$last, plot_width, plot_height)
  plot_out <- .exec_user_plot_string(fmt$plot)
  artifacts <- .exec_user_save_artifacts(
    session_id = session_id,
    workflow = workflow %||% "code_lab",
    tab = tab %||% "run",
    label = label %||% "Code Lab run",
    code = code,
    source_code = paste(as.character(source_code %||% ""), collapse = "\n"),
    stdout = paste(so, collapse = "\n"),
    value_text = fmt$text,
    plot = plot_out,
    tables = fmt$tables %||% list()
  )
  list(
    success       = TRUE,
    stdout        = paste(so, collapse = "\n"),
    plot          = plot_out,
    value_text    = fmt$text,
    tables        = fmt$tables %||% list(),
    artifact_id   = artifacts$run_id,
    artifact_name = artifacts$zip_name,
    has_plot      = !is.null(plot_out),
    experiment    = exp_chr
  )
}

# Plumber entry (safe_api from helpers/utils.R, sourced before this file).
plumber_user_r_post <- function(req, res) {
  safe_api({ # nolint: object_usage_linter
    b          <- jsonlite::fromJSON(req$postBody)
    session_id <- b$session_id
    code       <- as.character(b$code %||% "")
    experiment <- b$experiment %||% NULL
    workflow   <- b$workflow %||% NULL
    tab        <- b$tab %||% NULL
    label      <- b$label %||% NULL
    source_code <- b$source_code %||% NULL
    width      <- suppressWarnings(as.numeric(b$width %||% 9))
    height     <- suppressWarnings(as.numeric(b$height %||% 6))
    if (is.na(width)  || width  <= 0) width  <- 9
    if (is.na(height) || height <= 0) height <- 6
    exec_user_r_learning(
      session_id   = session_id,
      experiment   = experiment,
      code         = paste(code, collapse = "\n"),
      plot_width   = width,
      plot_height  = height,
      workflow     = workflow,
      tab          = tab,
      label        = label,
      source_code  = source_code
    )
  }, res)
}

plumber_code_lab_artifact_get <- function(session_id, artifact_name, res) {
  path <- file.path(.exec_user_artifact_root(session_id), basename(artifact_name))
  if (!file.exists(path) || !grepl("\\.zip$", artifact_name, ignore.case = TRUE)) {
    res$status <- 404
    return(charToRaw('{"success":false,"error":"Code Lab artifact not found"}'))
  }
  res$setHeader("Content-Disposition", sprintf('attachment; filename="%s"', basename(path)))
  readBin(path, what = "raw", n = file.info(path)$size)
}
