# Self-evolution layer: collect anonymized usage signals, build per-user profiles,
# and feed personalization hints back into AI interpret / Code Lab.

EVOLUTION_DIR <- "/tmp/emp_evolution"
EVOLUTION_MAX_EVENTS <- 5000L
EVOLUTION_MAX_EVENT_BYTES <- 8192L

.evolution_safe_id <- function(x, fallback = "anonymous") {
  s <- trimws(as.character(x %||% ""))
  if (!nzchar(s)) return(fallback)
  s <- gsub("[^a-zA-Z0-9._-]", "_", s)
  if (nchar(s) > 64L) substr(s, 1L, 64L) else s
}

.evolution_user_dir <- function(user_id) {
  file.path(EVOLUTION_DIR, "users", .evolution_safe_id(user_id))
}

.evolution_ensure_dir <- function(user_id) {
  dir <- .evolution_user_dir(user_id)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  dir
}

.evolution_profile_path <- function(user_id) {
  file.path(.evolution_user_dir(user_id), "profile.json")
}

.evolution_events_path <- function(user_id) {
  file.path(.evolution_user_dir(user_id), "events.jsonl")
}

.evolution_sanitize_payload <- function(payload) {
  if (is.null(payload)) return(list())
  if (!is.list(payload)) return(list(value = as.character(payload)[1L]))
  keys <- names(payload)
  out <- list()
  for (k in keys) {
    if (!nzchar(k)) next
    v <- payload[[k]]
    if (is.list(v)) {
      out[[k]] <- .evolution_sanitize_payload(v)
    } else if (length(v) > 20L) {
      out[[k]] <- as.character(v)[seq_len(20L)]
    } else {
      out[[k]] <- v
    }
  }
  raw <- jsonlite::toJSON(out, auto_unbox = TRUE, null = "null")
  if (nchar(raw) > EVOLUTION_MAX_EVENT_BYTES) {
    return(list(truncated = TRUE, preview = substr(raw, 1L, EVOLUTION_MAX_EVENT_BYTES)))
  }
  out
}

.evolution_read_profile <- function(user_id) {
  p <- .evolution_profile_path(user_id)
  if (!file.exists(p)) {
    return(list(
      user_id = .evolution_safe_id(user_id),
      created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
      updated_at = NULL,
      locale = "zh",
      omics_counts = list(),
      analysis_counts = list(),
      copilot_uses = 0L,
      prompt_button_clicks = 0L,
      pages_visited = list(),
      errors = list(),
      personalization = list()
    ))
  }
  tryCatch(jsonlite::fromJSON(readLines(p, warn = FALSE), simplifyVector = FALSE),
           error = function(e) .evolution_read_profile(NULL))
}

.evolution_write_profile <- function(user_id, profile) {
  .evolution_ensure_dir(user_id)
  profile$user_id <- .evolution_safe_id(user_id)
  profile$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
  jsonlite::write_json(profile, .evolution_profile_path(user_id), auto_unbox = TRUE, pretty = TRUE)
  invisible(profile)
}

.evolution_bump_counter <- function(counts, key) {
  counts <- counts %||% list()
  k <- trimws(as.character(key %||% ""))
  if (!nzchar(k)) return(counts)
  counts[[k]] <- as.integer(counts[[k]] %||% 0L) + 1L
  counts
}

.evolution_aggregate_personalization <- function(profile) {
  locale <- profile$locale %||% "zh"
  omics <- profile$omics_counts %||% list()
  analysis <- profile$analysis_counts %||% list()
  top_omics <- names(sort(unlist(omics), decreasing = TRUE))[1L]
  top_analysis <- names(sort(unlist(analysis), decreasing = TRUE))[1L]
  en <- grepl("^en", tolower(as.character(locale)))
  hints <- list(
    preferred_locale = locale,
    top_omics = top_omics %||% NULL,
    top_analysis = top_analysis %||% NULL,
    copilot_uses = as.integer(profile$copilot_uses %||% 0L),
    experience_level = if (as.integer(profile$copilot_uses %||% 0L) >= 10L) "advanced" else "beginner",
    focus_areas = unique(c(top_omics, top_analysis)),
    summary = if (en) {
      paste("User often works on", top_omics %||% "multi-omics", "with", top_analysis %||% "mixed analyses", ".")
    } else {
      paste0("用户常用 ", top_omics %||% "多组学", "，频繁进行 ", top_analysis %||% "多种分析", "。")
    }
  )
  profile$personalization <- hints
  profile
}

evolution_record_event <- function(user_id, session_id = NULL, event_type = "generic", payload = list()) {
  user_id <- .evolution_safe_id(user_id)
  event_type <- trimws(as.character(event_type %||% "generic"))
  if (!nzchar(event_type)) event_type <- "generic"
  .evolution_ensure_dir(user_id)

  event <- list(
    ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
    type = event_type,
    session_id = .evolution_safe_id(session_id, "no_session"),
    payload = .evolution_sanitize_payload(payload)
  )
  cat(jsonlite::toJSON(event, auto_unbox = TRUE, null = "null"), "\n",
      file = .evolution_events_path(user_id), append = TRUE)

  profile <- .evolution_read_profile(user_id)
  profile$locale <- payload$locale %||% profile$locale %||% "zh"
  if (!is.null(payload$omics)) profile$omics_counts <- .evolution_bump_counter(profile$omics_counts, payload$omics)
  if (!is.null(payload$analysis_type)) {
    profile$analysis_counts <- .evolution_bump_counter(profile$analysis_counts, payload$analysis_type)
  }
  if (!is.null(payload$page)) profile$pages_visited <- .evolution_bump_counter(profile$pages_visited, payload$page)
  if (identical(event_type, "ai_interpret")) profile$copilot_uses <- as.integer(profile$copilot_uses %||% 0L) + 1L
  if (identical(event_type, "prompt_button_click")) {
    profile$prompt_button_clicks <- as.integer(profile$prompt_button_clicks %||% 0L) + 1L
  }
  if (identical(event_type, "analysis_error") && !is.null(payload$message)) {
    errs <- profile$errors %||% list()
    errs[[length(errs) + 1L]] <- list(
      at = event$ts,
      message = substr(as.character(payload$message)[1L], 1L, 240L)
    )
    if (length(errs) > 50L) errs <- errs[(length(errs) - 49L):length(errs)]
    profile$errors <- errs
  }
  profile <- .evolution_aggregate_personalization(profile)
  .evolution_write_profile(user_id, profile)
  list(success = TRUE, event = event, profile = profile)
}

evolution_get_profile <- function(user_id) {
  user_id <- .evolution_safe_id(user_id)
  profile <- .evolution_read_profile(user_id)
  .evolution_aggregate_personalization(profile)
}

plumber_evolution_event_post <- function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody, simplifyVector = FALSE)
    user_id <- b$user_id %||% req$HTTP_X_EMP_USER_ID %||% "anonymous"
    session_id <- b$session_id %||% req$HTTP_X_SESSION_ID %||% NULL
    evolution_record_event(
      user_id = user_id,
      session_id = session_id,
      event_type = b$event_type %||% b$type %||% "generic",
      payload = b$payload %||% b
    )
  }, res)
}

plumber_evolution_profile_get <- function(user_id, req, res) {
  safe_api({
    uid <- user_id %||% req$HTTP_X_EMP_USER_ID %||% "anonymous"
    list(success = TRUE, profile = evolution_get_profile(uid))
  }, res)
}
