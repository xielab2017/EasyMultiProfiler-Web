# Stable, constrained API surface used by external workflow agents.

.emp_env_int <- function(name, default, minimum = 1L) {
  value <- suppressWarnings(as.integer(Sys.getenv(name, unset = as.character(default))))
  if (is.na(value) || value < minimum) as.integer(default) else value
}

.emp_allowed_roots <- function() {
  raw <- trimws(Sys.getenv("EMP_ALLOWED_ROOTS", unset = ""))
  if (!nzchar(raw)) return(character())
  roots <- trimws(strsplit(raw, .Platform$path.sep, fixed = TRUE)[[1]])
  roots <- roots[nzchar(roots)]
  normalized <- vapply(roots, function(root) {
    normalizePath(path.expand(root), winslash = "/", mustWork = TRUE)
  }, character(1), USE.NAMES = FALSE)
  unique(normalized[file.info(normalized)$isdir %in% TRUE])
}

.emp_is_within_root <- function(candidate, root) {
  candidate <- sub("/+$", "", candidate)
  root <- sub("/+$", "", root)
  if (.Platform$OS.type == "windows") {
    candidate <- tolower(candidate)
    root <- tolower(root)
  }
  identical(candidate, root) || startsWith(candidate, paste0(root, "/"))
}

emp_resolve_allowed_file <- function(path, label = "file") {
  raw <- trimws(as.character(path %||% ""))
  if (!nzchar(raw)) stop(sprintf("%s path is required.", label))
  roots <- .emp_allowed_roots()
  if (!length(roots)) stop("EMP_ALLOWED_ROOTS is not configured; path import is disabled.")

  resolved <- normalizePath(path.expand(raw), winslash = "/", mustWork = TRUE)
  info <- file.info(resolved)
  if (!nrow(info) || is.na(info$isdir) || isTRUE(info$isdir) || !isTRUE(file_test("-f", resolved))) {
    stop(sprintf("%s must be a regular file.", label))
  }
  if (!any(vapply(roots, function(root) .emp_is_within_root(resolved, root), logical(1)))) {
    stop(sprintf("%s is outside EMP_ALLOWED_ROOTS.", label))
  }
  resolved
}

# Directory-flavoured sibling of emp_resolve_allowed_file(), for endpoints that take a server
# folder rather than a server file (ChIP-seq BAM folder scan). Same EMP_ALLOWED_ROOTS contract:
# with no roots configured, server-path access is disabled rather than unrestricted.
emp_resolve_allowed_dir <- function(path, label = "folder") {
  raw <- trimws(as.character(path %||% ""))
  if (!nzchar(raw)) stop(sprintf("%s path is required.", label))
  roots <- .emp_allowed_roots()
  if (!length(roots)) stop("EMP_ALLOWED_ROOTS is not configured; server-path access is disabled.")

  resolved <- normalizePath(path.expand(raw), winslash = "/", mustWork = TRUE)
  if (!isTRUE(file_test("-d", resolved))) {
    stop(sprintf("%s must be a directory.", label))
  }
  if (!any(vapply(roots, function(root) .emp_is_within_root(resolved, root), logical(1)))) {
    stop(sprintf("%s is outside EMP_ALLOWED_ROOTS.", label))
  }
  resolved
}

.emp_file_sha256 <- function(path) {
  if (!requireNamespace("digest", quietly = TRUE)) return(NULL)
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}

.emp_table_preview <- function(path, max_rows = NULL) {
  max_rows <- max_rows %||% .emp_env_int("EMP_PREVIEW_MAX_ROWS", 100L)
  info <- file.info(path)
  max_bytes <- .emp_env_int("EMP_PATH_IMPORT_MAX_BYTES", 2147483647L)
  if (!is.finite(info$size) || info$size > max_bytes) {
    stop(sprintf("File exceeds EMP_PATH_IMPORT_MAX_BYTES (%s bytes).", max_bytes))
  }
  table <- read_table_auto(path, nrows = max_rows)
  lines <- readLines(path, n = max_rows + 1L, warn = FALSE)
  mean_bytes <- if (length(lines)) mean(pmax(1L, nchar(lines, type = "bytes") + 1L)) else NA_real_
  estimated_rows <- if (is.finite(mean_bytes) && mean_bytes > 0) {
    max(0L, as.integer(round(info$size / mean_bytes)) - 1L)
  } else {
    nrow(table)
  }
  list(
    table = table,
    rows_estimate = estimated_rows,
    size = unname(info$size),
    truncated = length(lines) > max_rows
  )
}

.emp_metadata_id_column <- function(metadata) {
  if (is.null(metadata) || !ncol(metadata)) return(NULL)
  candidates <- names(metadata)[grepl("sample|(^|_)id($|_)|primary", names(metadata), ignore.case = TRUE)]
  if (length(candidates)) candidates[[1]] else names(metadata)[[1]]
}

emp_path_import_preview <- function(data_path, metadata_path = NULL,
                                    data_type = "normal", tax_sep = ";") {
  data_file <- emp_resolve_allowed_file(data_path, "data")
  metadata_file <- NULL
  if (!is.null(metadata_path) && nzchar(trimws(as.character(metadata_path)))) {
    metadata_file <- emp_resolve_allowed_file(metadata_path, "metadata")
  }

  data_preview <- .emp_table_preview(data_file)
  metadata_max_rows <- .emp_env_int("EMP_PREVIEW_METADATA_MAX_ROWS", 5000L)
  metadata_preview <- if (!is.null(metadata_file)) {
    .emp_table_preview(metadata_file, max_rows = metadata_max_rows)
  } else {
    NULL
  }
  metadata <- metadata_preview$table %||% NULL
  id_column <- .emp_metadata_id_column(metadata)
  metadata_ids <- if (!is.null(id_column)) trimws(as.character(metadata[[id_column]])) else character()
  metadata_ids <- metadata_ids[nzchar(metadata_ids)]

  sample_rows <- should_transpose_sample_rows(
    data_preview$table, unique(metadata_ids), data_type = data_type, tax_sep = tax_sep
  )
  data_ids <- if (sample_rows) {
    trimws(as.character(data_preview$table[[1]]))
  } else {
    trimws(names(data_preview$table)[-1])
  }
  data_ids <- data_ids[nzchar(data_ids)]
  matched <- intersect(unique(data_ids), unique(metadata_ids))
  warnings <- character()
  if (!is.null(metadata_preview) && isTRUE(metadata_preview$truncated)) {
    warnings <- c(warnings, sprintf("Metadata preview was limited to %d rows.", nrow(metadata)))
  }
  if (anyDuplicated(data_ids)) warnings <- c(warnings, "Assay contains duplicate sample IDs.")
  if (anyDuplicated(metadata_ids)) warnings <- c(warnings, "Metadata contains duplicate sample IDs.")
  if (length(metadata_ids) && !length(matched)) warnings <- c(warnings, "No sample IDs match between assay and metadata preview.")

  list(
    success = TRUE,
    data = list(
      path = data_file,
      size = data_preview$size,
      sha256 = .emp_file_sha256(data_file),
      rows_estimate = data_preview$rows_estimate,
      rows_previewed = nrow(data_preview$table),
      columns = ncol(data_preview$table),
      orientation = if (sample_rows) "samples_in_rows" else "features_in_rows"
    ),
    metadata = if (is.null(metadata_file)) NULL else list(
      path = metadata_file,
      size = metadata_preview$size,
      sha256 = .emp_file_sha256(metadata_file),
      rows_estimate = metadata_preview$rows_estimate,
      rows_previewed = nrow(metadata),
      columns = ncol(metadata),
      sample_id_column = id_column
    ),
    sample_overlap = list(
      assay = length(unique(data_ids)),
      metadata = length(unique(metadata_ids)),
      matched = length(matched),
      assay_only = setdiff(unique(data_ids), unique(metadata_ids)),
      metadata_only = setdiff(unique(metadata_ids), unique(data_ids))
    ),
    warnings = warnings
  )
}

emp_path_import <- function(data_path, metadata_path = NULL,
                            experiment_name = "experiment", data_type = "normal",
                            assay_name = "counts", start_level = "Species",
                            tax_sep = ";", session_id = NULL,
                            owner_id = NULL, project_id = NULL) {
  preview <- emp_path_import_preview(data_path, metadata_path, data_type, tax_sep)
  result <- import_omics_files(
    data_file = preview$data$path,
    metadata_file = preview$metadata$path %||% NULL,
    experiment_name = experiment_name,
    data_type = data_type,
    assay_name = assay_name,
    start_level = start_level,
    tax_sep = tax_sep,
    session_id = session_id,
    owner_id = owner_id,
    project_id = project_id
  )
  result$input_files <- list(data = preview$data, metadata = preview$metadata)
  result$sample_overlap <- preview$sample_overlap
  result$warnings <- preview$warnings
  result
}

emp_agent_capabilities <- function() {
  package_version <- tryCatch(as.character(utils::packageVersion("EasyMultiProfiler")), error = function(e) "unknown")
  workflows <- c("microbiome_16s", "transcriptomics", "metabolomics", "metagenomics", "clinical", "chipseq")
  agent_tools <- c(
    "emp.workflow.validate",
    "emp.prepare.taxonomy",
    "emp.prepare.normalize",
    "emp.analyze.alpha",
    "emp.visualize.alpha",
    "emp.analyze.differential",
    "emp.analyze.enrichment",
    "emp.analyze.association"
  )
  user_r_enabled <- emp_user_r_enabled()
  list(
    success = TRUE,
    api_version = "1.0",
    emp_version = Sys.getenv("EMP_WEB_VERSION", unset = "9.0.5"),
    package_version = package_version,
    features = list(
      path_import = length(.emp_allowed_roots()) > 0,
      async_jobs = TRUE,
      job_cancel = TRUE,
      bundles = TRUE,
      persistent_sessions = TRUE,
      persistent_projects = TRUE,
      bearer_auth = emp_auth_required(),
      arbitrary_r = user_r_enabled
    ),
    workflows = workflows,
    tools = agent_tools,
    limits = list(
      max_upload_bytes = .emp_env_int("EMP_PATH_IMPORT_MAX_BYTES", 2147483647L),
      preview_max_rows = .emp_env_int("EMP_PREVIEW_MAX_ROWS", 100L),
      metadata_preview_max_rows = .emp_env_int("EMP_PREVIEW_METADATA_MAX_ROWS", 5000L)
    )
  )
}
