# Authentication and deployment-boundary helpers.

emp_truthy <- function(value) {
  tolower(trimws(as.character(value %||% ""))) %in% c("1", "true", "yes", "on")
}

emp_is_loopback_host <- function(host) {
  normalized <- tolower(trimws(as.character(host %||% "")))
  normalized %in% c("127.0.0.1", "::1", "localhost")
}

emp_api_token <- function() trimws(Sys.getenv("EMP_API_TOKEN", unset = ""))

emp_token_hashes <- function() {
  raw <- trimws(Sys.getenv("EMP_API_TOKEN_SHA256S", unset = ""))
  if (!nzchar(raw)) return(list())
  values <- tryCatch(jsonlite::fromJSON(raw, simplifyVector = TRUE), error = function(e) stop("Invalid EMP_API_TOKEN_SHA256S JSON."))
  if (is.null(names(values)) || any(!grepl("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$", names(values)))) {
    stop("EMP token owner identifiers are invalid.")
  }
  hashes <- as.list(tolower(as.character(unlist(values, use.names = FALSE))))
  names(hashes) <- names(values)
  if (any(!grepl("^[0-9a-f]{64}$", unlist(hashes, use.names = FALSE)))) stop("EMP token hashes must be SHA-256 hex.")
  hashes
}

emp_endpoint_id <- function() {
  value <- trimws(Sys.getenv("EMP_ENDPOINT_ID", unset = "local-default"))
  if (!grepl("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$", value)) {
    stop("EMP_ENDPOINT_ID must contain only letters, numbers, dot, underscore or hyphen.")
  }
  value
}

emp_auth_required <- function() {
  nzchar(emp_api_token()) || length(emp_token_hashes()) > 0L || !emp_is_loopback_host(Sys.getenv("API_HOST", unset = "127.0.0.1"))
}

emp_validate_deployment <- function() {
  host <- Sys.getenv("API_HOST", unset = "127.0.0.1")
  if (!emp_is_loopback_host(host) && !nzchar(emp_api_token()) && length(emp_token_hashes()) == 0L) {
    stop("EMP_API_TOKEN or EMP_API_TOKEN_SHA256S is required when API_HOST is not a loopback address.")
  }
  cors_origin <- trimws(Sys.getenv("EMP_CORS_ORIGIN", unset = "*"))
  if (!emp_is_loopback_host(host) && (!nzchar(cors_origin) || identical(cors_origin, "*"))) {
    stop("EMP_CORS_ORIGIN must be an explicit trusted origin for non-loopback deployment.")
  }
  invisible(TRUE)
}

.emp_constant_time_equal <- function(actual, expected) {
  a <- as.integer(charToRaw(enc2utf8(as.character(actual %||% ""))))
  b <- as.integer(charToRaw(enc2utf8(as.character(expected %||% ""))))
  width <- max(length(a), length(b), 1L)
  length_diff <- bitwXor(length(a), length(b))
  length(a) <- width
  length(b) <- width
  a[is.na(a)] <- 0L
  b[is.na(b)] <- 0L
  mismatch <- length_diff
  for (i in seq_len(width)) mismatch <- bitwOr(mismatch, bitwXor(a[[i]], b[[i]]))
  identical(mismatch, 0L)
}

emp_request_bearer <- function(req) {
  header <- trimws(as.character(req$HTTP_AUTHORIZATION %||% ""))
  match <- regexec("^Bearer[[:space:]]+(.+)$", header, ignore.case = TRUE)
  parts <- regmatches(header, match)[[1]]
  if (length(parts) != 2L) return("")
  trimws(parts[[2]])
}

emp_request_principal <- function(req) {
  if (!is.null(req$emp_principal) && nzchar(req$emp_principal)) return(req$emp_principal)
  if (!emp_auth_required()) return("local")
  ""
}

emp_authenticate_request <- function(req) {
  if (!emp_auth_required()) {
    req$emp_principal <- "local"
    return("local")
  }
  expected <- emp_api_token()
  supplied <- emp_request_bearer(req)
  if (!nzchar(supplied)) {
    stop("Authentication required.")
  }
  hashes <- emp_token_hashes()
  if (length(hashes)) {
    supplied_hash <- digest::digest(supplied, algo = "sha256", serialize = FALSE)
    owners <- names(hashes)[vapply(hashes, function(value) .emp_constant_time_equal(supplied_hash, value), logical(1))]
    if (length(owners) != 1L) stop("Authentication required.")
    req$emp_principal <- owners[[1]]
    return(owners[[1]])
  }
  if (!nzchar(expected) || !.emp_constant_time_equal(supplied, expected)) stop("Authentication required.")
  owner <- trimws(Sys.getenv("EMP_API_OWNER_ID", unset = "token-owner"))
  if (!grepl("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$", owner)) stop("Invalid EMP_API_OWNER_ID.")
  req$emp_principal <- owner
  owner
}

emp_public_api_path <- function(path) {
  identical(path, "/api/health")
}

emp_json_request_body <- function(req) {
  raw <- as.character(req$postBody %||% "")
  if (nchar(raw, type = "bytes") > 1048576L) return(list())
  if (!nzchar(trimws(raw)) || !grepl("^[[:space:]]*\\{", raw)) return(list())
  tryCatch(jsonlite::fromJSON(raw, simplifyVector = FALSE), error = function(e) list())
}

emp_authorize_request_resources <- function(req, principal) {
  path <- as.character(req$PATH_INFO %||% "")
  body <- emp_json_request_body(req)

  project_match <- regexec("^/api/projects/([^/]+)", path)
  project_parts <- regmatches(path, project_match)[[1]]
  if (length(project_parts) == 2L) emp_assert_project_owner(project_parts[[2]], principal)

  job_match <- regexec("^/api/jobs/([^/]+)", path)
  job_parts <- regmatches(path, job_match)[[1]]
  if (length(job_parts) == 2L) emp_assert_job_owner(job_parts[[2]], principal)

  session_ids <- character()
  path_parts <- strsplit(path, "/", fixed = TRUE)[[1]]
  session_ids <- c(session_ids, path_parts[grepl("^[A-Za-z0-9]{24}$", path_parts)])
  header_session <- trimws(as.character(req$HTTP_X_SESSION_ID %||% ""))
  query_session <- trimws(as.character(req$args$session_id %||% ""))
  if (nzchar(header_session)) session_ids <- c(session_ids, header_session)
  if (nzchar(query_session)) session_ids <- c(session_ids, query_session)
  body_session <- body$session_id %||% NULL
  if (!is.null(body_session) && length(body_session) == 1L && nzchar(as.character(body_session))) {
    session_ids <- c(session_ids, as.character(body_session))
  }
  for (session_id in unique(session_ids)) emp_assert_session_owner(session_id, principal)
  invisible(TRUE)
}
