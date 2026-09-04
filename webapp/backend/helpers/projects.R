# Persistent projects and endpoint-scoped session ownership.

PROJECT_DIR <- emp_storage_dir("projects")

.emp_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z")

.emp_write_json_atomic <- function(path, value) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- tempfile(".emp-json-", tmpdir = dirname(path))
  on.exit(unlink(tmp, force = TRUE), add = TRUE)
  jsonlite::write_json(value, tmp, auto_unbox = TRUE, null = "null", pretty = TRUE)
  if (!isTRUE(file.rename(tmp, path))) stop(sprintf("Unable to persist EMP state: %s", path))
  try(Sys.chmod(path, mode = "0600"), silent = TRUE)
  invisible(value)
}

validate_project_id <- function(project_id) {
  value <- trimws(as.character(project_id %||% ""))
  if (length(value) != 1L || !grepl("^prj_[A-Za-z0-9]{24}$", value)) stop("Invalid project_id")
  value
}

new_project_id <- function() {
  # Ownership of a project is asserted on this identifier, so it must not come from R's global
  # (seedable) RNG. See .emp_random_id() in utils.R.
  if (exists(".emp_random_id", mode = "function")) return(paste0("prj_", .emp_random_id(24L)))
  paste0("prj_", paste0(sample(c(letters, LETTERS, 0:9), 24, replace = TRUE), collapse = ""))
}

project_path <- function(project_id) file.path(PROJECT_DIR, paste0(validate_project_id(project_id), ".json"))
.session_owner_dir <- function() file.path(PROJECT_DIR, "session_owners")
session_owner_path <- function(session_id) file.path(.session_owner_dir(), paste0(validate_session_id(session_id), ".json"))
session_manifest_path <- function(session_id) file.path(session_path(session_id), "session_manifest.json")

emp_create_project <- function(owner_id, name = NULL) {
  if (!nzchar(owner_id %||% "")) stop("Project owner is required.")
  id <- new_project_id()
  now <- .emp_now()
  project <- list(
    project_id = id,
    endpoint_id = emp_endpoint_id(),
    owner_id = owner_id,
    name = trimws(as.character(name %||% "")),
    session_ids = list(),
    created_at = now,
    updated_at = now
  )
  .emp_write_json_atomic(project_path(id), project)
  project
}

emp_get_project <- function(project_id) {
  path <- project_path(project_id)
  if (!file.exists(path)) stop("Project not found.")
  jsonlite::read_json(path, simplifyVector = FALSE)
}

emp_assert_project_owner <- function(project_id, owner_id) {
  project <- emp_get_project(project_id)
  if (!identical(project$endpoint_id, emp_endpoint_id()) || !identical(project$owner_id, owner_id)) {
    stop("Project access denied.")
  }
  invisible(project)
}

emp_register_session_owner <- function(session_id, owner_id, project_id = NULL) {
  session_id <- validate_session_id(session_id)
  if (!nzchar(owner_id %||% "")) stop("Session owner is required.")
  if (!is.null(project_id)) emp_assert_project_owner(project_id, owner_id)
  existing_path <- session_owner_path(session_id)
  if (file.exists(existing_path)) {
    existing <- jsonlite::read_json(existing_path, simplifyVector = FALSE)
    if (!identical(existing$endpoint_id, emp_endpoint_id()) || !identical(existing$owner_id, owner_id)) {
      stop("Session access denied.")
    }
    if (!is.null(project_id) && !is.null(existing$project_id) && !identical(existing$project_id, project_id)) {
      stop("Session already belongs to another project.")
    }
    if (is.null(project_id)) project_id <- existing$project_id %||% NULL
  }
  record <- list(
    session_id = session_id,
    endpoint_id = emp_endpoint_id(),
    owner_id = owner_id,
    project_id = project_id,
    updated_at = .emp_now()
  )
  .emp_write_json_atomic(existing_path, record)

  if (!is.null(project_id)) {
    project <- emp_get_project(project_id)
    ids <- unique(c(unlist(project$session_ids, use.names = FALSE), session_id))
    project$session_ids <- as.list(ids)
    project$updated_at <- .emp_now()
    .emp_write_json_atomic(project_path(project_id), project)
  }
  invisible(record)
}

emp_get_session_owner <- function(session_id) {
  path <- session_owner_path(session_id)
  if (!file.exists(path)) return(NULL)
  jsonlite::read_json(path, simplifyVector = FALSE)
}

emp_assert_session_owner <- function(session_id, owner_id) {
  session_id <- validate_session_id(session_id)
  record <- emp_get_session_owner(session_id)
  if (is.null(record)) {
    if (identical(owner_id, "local") && !emp_auth_required() && session_exists(session_id)) {
      return(emp_register_session_owner(session_id, owner_id))
    }
    stop("Session ownership is not registered.")
  }
  if (!identical(record$endpoint_id, emp_endpoint_id()) || !identical(record$owner_id, owner_id)) {
    stop("Session access denied.")
  }
  invisible(record)
}

emp_delete_session_ownership <- function(session_id) {
  record <- emp_get_session_owner(session_id)
  if (!is.null(record$project_id)) {
    project <- tryCatch(emp_get_project(record$project_id), error = function(e) NULL)
    if (!is.null(project)) {
      ids <- setdiff(unlist(project$session_ids, use.names = FALSE), session_id)
      project$session_ids <- as.list(ids)
      project$updated_at <- .emp_now()
      .emp_write_json_atomic(project_path(record$project_id), project)
    }
  }
  unlink(session_owner_path(session_id), force = TRUE)
  invisible(TRUE)
}

emp_record_session_import <- function(session_id, input_files = NULL, experiment = NULL, data_type = NULL) {
  manifest <- if (file.exists(session_manifest_path(session_id))) {
    jsonlite::read_json(session_manifest_path(session_id), simplifyVector = FALSE)
  } else {
    list(session_id = session_id, imports = list(), created_at = .emp_now())
  }
  manifest$imports <- c(manifest$imports %||% list(), list(list(
    experiment = experiment,
    data_type = data_type,
    input_files = input_files,
    imported_at = .emp_now()
  )))
  manifest$updated_at <- .emp_now()
  .emp_write_json_atomic(session_manifest_path(session_id), manifest)
}

emp_session_manifest <- function(session_id, owner_id) {
  ownership <- emp_assert_session_owner(session_id, owner_id)
  stored <- if (file.exists(session_manifest_path(session_id))) {
    jsonlite::read_json(session_manifest_path(session_id), simplifyVector = FALSE)
  } else list(session_id = session_id, imports = list())
  stored$endpoint_id <- emp_endpoint_id()
  stored$project_id <- ownership$project_id %||% NULL
  stored$ownership <- list(
    endpoint_id = ownership$endpoint_id,
    owner_id = ownership$owner_id
  )
  stored$experiments <- if (file.exists(mae_path(session_id))) list_experiments_info(session_id) else list()
  stored$jobs <- if (exists("list_jobs_for_session", mode = "function")) {
    list_jobs_for_session(session_id, owner_id)
  } else list()
  stored$versions <- list(
    emp_web = Sys.getenv("EMP_WEB_VERSION", unset = "9.0.5"),
    emp_package = tryCatch(as.character(utils::packageVersion("EasyMultiProfiler")), error = function(e) "unknown"),
    r = as.character(getRversion())
  )
  stored
}

emp_create_project_session <- function(project_id, owner_id) {
  emp_assert_project_owner(project_id, owner_id)
  session_id <- emp_create_owned_session(owner_id, project_id)
  list(session_id = session_id, project_id = project_id, endpoint_id = emp_endpoint_id())
}

emp_create_owned_session <- function(owner_id, project_id = NULL) {
  if (!is.null(project_id)) emp_assert_project_owner(project_id, owner_id)
  session_id <- create_session()
  emp_register_session_owner(session_id, owner_id, project_id)
  session_id
}
