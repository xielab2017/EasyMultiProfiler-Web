# Teaching mode: learning trace, case progress, reflections (session-bound, no login).

TEACHING_DIR <- Sys.getenv("EMP_TEACHING_DIR", "/tmp/emp_teaching")
.teaching_data_path <- function(name) {
  backend <- Sys.getenv("EMP_BACKEND_DIR", Sys.getenv("BACKEND_DIR", unset = ""))
  if (!nzchar(backend)) backend <- getwd()
  data_dir <- normalizePath(file.path(backend, "..", "data"), mustWork = FALSE)
  file.path(data_dir, name)
}

.teaching_ensure_dir <- function() {
  dirs <- c(
    TEACHING_DIR,
    file.path(TEACHING_DIR, "traces"),
    file.path(TEACHING_DIR, "progress"),
    file.path(TEACHING_DIR, "reflections")
  )
  for (d in dirs) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  invisible(TRUE)
}

.teaching_read_json <- function(path, default = list()) {
  if (!file.exists(path)) return(default)
  tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) default)
}

.teaching_write_json <- function(path, obj) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(obj, path, auto_unbox = TRUE, pretty = TRUE)
}

EMP_COURSE_CODE <- Sys.getenv("EMP_COURSE_CODE", "EMP2026")

.teaching_trace_path <- function(user_id) {
  file.path(TEACHING_DIR, "traces", paste0(make.names(user_id), ".jsonl"))
}

.teaching_progress_path <- function(user_id) {
  file.path(TEACHING_DIR, "progress", paste0(make.names(user_id), ".json"))
}

.teaching_reflection_path <- function(user_id, case_id, task_id) {
  file.path(
    TEACHING_DIR, "reflections",
    paste0(make.names(user_id), "__", make.names(case_id), "__", make.names(task_id), ".json")
  )
}

.teaching_identity_from_req <- function(req) {
  sid <- trimws(as.character(
    req$HTTP_X_SESSION_ID %||% req$headers[["x-session-id"]] %||% ""
  ))
  if (!nzchar(sid)) sid <- "local"
  list(user_id = sid, role = "local", display_name = sid)
}

teaching_load_cases <- function() {
  path <- .teaching_data_path("teaching_cases.json")
  if (!file.exists(path)) stop("teaching_cases.json not found.")
  .teaching_read_json(path)
}

teaching_load_prompts <- function() {
  path <- .teaching_data_path("prompt_templates.json")
  if (!file.exists(path)) stop("prompt_templates.json not found.")
  .teaching_read_json(path)
}

teaching_get_case <- function(case_id) {
  data <- teaching_load_cases()
  cases <- data$cases %||% list()
  hit <- NULL
  for (c in cases) {
    if (identical(c$id, case_id)) { hit <- c; break }
  }
  if (is.null(hit)) stop(sprintf("Unknown case: %s", case_id))
  hit
}

teaching_load_videos <- function() {
  path <- .teaching_data_path("teaching_videos.json")
  if (!file.exists(path)) stop("teaching_videos.json not found.")
  .teaching_read_json(path)
}

teaching_get_video_module <- function(module_id) {
  data <- teaching_load_videos()
  mods <- data$modules %||% list()
  hit <- mods[[module_id]]
  if (is.null(hit)) stop(sprintf("Unknown video module: %s", module_id))
  hit
}

teaching_get_quiz <- function(quiz_id) {
  data <- teaching_load_videos()
  quizzes <- data$quizzes %||% list()
  hit <- quizzes[[quiz_id]]
  if (is.null(hit)) stop(sprintf("Unknown quiz: %s", quiz_id))
  hit
}

.teaching_strip_quiz_answers <- function(quiz) {
  qs <- quiz$questions %||% list()
  stripped <- lapply(qs, function(q) {
    list(id = q$id, question = q$question, options = q$options)
  })
  list(questions = stripped)
}

.teaching_task_key <- function(case_id, task_id) {
  paste(case_id, task_id, sep = "::")
}

.teaching_task_unlocked <- function(case_id, tasks, task_idx, passed_quizzes) {
  if (task_idx <= 1L) return(TRUE)
  prev <- tasks[[task_idx - 1L]]
  quiz_id <- prev$quiz %||% ""
  if (!nzchar(quiz_id)) return(TRUE)
  key <- .teaching_task_key(case_id, prev$id)
  !is.null(passed_quizzes[[key]])
}

teaching_get_case_for_user <- function(case_id, identity) {
  c <- teaching_get_case(case_id)
  prog <- .teaching_read_json(
    .teaching_progress_path(identity$user_id),
    default = list(user_id = identity$user_id, completed_tasks = list(), passed_quizzes = list())
  )
  passed <- prog$passed_quizzes %||% list()
  done <- prog$completed_tasks %||% list()
  vdata <- teaching_load_videos()
  aspect_labels <- vdata$aspect_labels %||% list()
  step_labels <- vdata$step_labels %||% list()
  tasks_out <- lapply(seq_along(c$tasks %||% list()), function(i) {
    t <- c$tasks[[i]]
    key <- .teaching_task_key(case_id, t$id)
    unlocked <- .teaching_task_unlocked(case_id, c$tasks, as.integer(i), passed)
    quiz_passed <- is.null(t$quiz) || !nzchar(t$quiz %||% "") || !is.null(passed[[key]])
    videos <- lapply(t$videos %||% list(), function(mid) {
      m <- teaching_get_video_module(mid)
      list(
        id = mid,
        title = m$title,
        aspect = m$aspect,
        aspect_label = aspect_labels[[m$aspect]] %||% m$aspect,
        step = m$step %||% "",
        step_label = step_labels[[m$step %||% ""]] %||% (m$step %||% ""),
        objective = m$objective %||% "",
        script = m$script %||% "",
        storyboard = m$storyboard %||% list(),
        takeaways = m$takeaways %||% list(),
        local_video = m$local_video %||% "",
        youtube_id = m$youtube_id,
        clip_start = m$clip_start %||% NULL,
        clip_end = m$clip_end %||% NULL,
        duration = m$duration,
        source_note = m$source_note %||% "",
        description = m$description
      )
    })
    quiz <- if (nzchar(t$quiz %||% "")) {
      .teaching_strip_quiz_answers(teaching_get_quiz(t$quiz))
    } else NULL
    list(
      id = t$id,
      phase = t$phase,
      title = t$title,
      instructions = t$instructions,
      emp_page = t$emp_page,
      reflection_prompt = t$reflection_prompt,
      required = t$required,
      videos = videos,
      quiz = quiz,
      quiz_id = t$quiz %||% "",
      unlocked = unlocked,
      quiz_passed = quiz_passed,
      reflection_done = !is.null(done[[key]])
    )
  })
  c$tasks <- tasks_out
  c
}

teaching_submit_quiz <- function(identity, case_id, task_id, answers) {
  meta <- identity
  c <- teaching_get_case(case_id)
  task <- NULL
  for (t in c$tasks %||% list()) {
    if (identical(t$id, task_id)) { task <- t; break }
  }
  if (is.null(task)) stop(sprintf("Unknown task: %s", task_id))
  quiz_id <- task$quiz %||% ""
  if (!nzchar(quiz_id)) stop("This task has no quiz.")
  quiz <- teaching_get_quiz(quiz_id)
  qs <- quiz$questions %||% list()
  if (!length(qs)) stop("Quiz has no questions.")
  ans_list <- answers
  if (is.data.frame(ans_list)) ans_list <- jsonlite::fromJSON(jsonlite::toJSON(ans_list), simplifyVector = FALSE)
  if (!is.list(ans_list)) stop("Invalid answers payload.")
  wrong <- character()
  for (q in qs) {
    qid <- q$id
    chosen <- NULL
    for (a in ans_list) {
      aid <- a$id %||% a$question_id
      if (identical(aid, qid)) {
        chosen <- as.integer(a$choice %||% a$choice_index)
        break
      }
    }
    if (is.null(chosen) || is.na(chosen) || chosen != as.integer(q$correct)) {
      wrong <- c(wrong, qid)
    }
  }
  passed <- length(wrong) == 0L
  key <- .teaching_task_key(case_id, task_id)
  if (passed) {
    .teaching_ensure_dir()
    prog <- .teaching_read_json(.teaching_progress_path(meta$user_id), default = list())
    if (is.null(prog$passed_quizzes)) prog$passed_quizzes <- list()
    prog$passed_quizzes[[key]] <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z")
    prog$user_id <- meta$user_id
    prog$updated_at <- prog$passed_quizzes[[key]]
    .teaching_write_json(.teaching_progress_path(meta$user_id), prog)
    teaching_append_trace(identity, list(event_type = "quiz_pass", case_id = case_id, task_id = task_id))
  } else {
    teaching_append_trace(identity, list(
      event_type = "quiz_fail",
      case_id = case_id,
      task_id = task_id,
      wrong = wrong
    ))
  }
  list(
    success = TRUE,
    passed = passed,
    total = length(qs),
    correct = length(qs) - length(wrong),
    wrong_ids = wrong
  )
}

teaching_append_trace <- function(identity, event) {
  meta <- identity
  .teaching_ensure_dir()
  ev <- as.list(event %||% list())
  ev$user_id <- meta$user_id
  ev$role <- meta$role
  ev$ts <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z")
  line <- jsonlite::toJSON(ev, auto_unbox = TRUE, null = "null")
  cat(line, "\n", file = .teaching_trace_path(meta$user_id), append = TRUE)
  list(success = TRUE, recorded = ev)
}

teaching_list_traces <- function(identity, user_id = NULL, limit = 200L) {
  meta <- identity
  target <- meta$user_id
  if (!is.null(user_id) && nzchar(user_id)) target <- user_id
  path <- .teaching_trace_path(target)
  if (!file.exists(path)) return(list(success = TRUE, user_id = target, events = list()))
  lines <- readLines(path, warn = FALSE)
  lines <- lines[nzchar(trimws(lines))]
  n <- length(lines)
  if (n > limit) lines <- tail(lines, limit)
  events <- lapply(lines, function(ln) {
    tryCatch(jsonlite::fromJSON(ln, simplifyVector = FALSE), error = function(e) list(raw = ln))
  })
  list(success = TRUE, user_id = target, events = events)
}

teaching_save_reflection <- function(identity, case_id, task_id, reflection, ai_declaration = NULL) {
  meta <- identity
  if (!nzchar(trimws(as.character(reflection %||% "")))) stop("Reflection text is required.")
  prog <- .teaching_read_json(.teaching_progress_path(meta$user_id), default = list())
  passed <- prog$passed_quizzes %||% list()
  c <- teaching_get_case(case_id)
  task <- NULL
  for (t in c$tasks %||% list()) {
    if (identical(t$id, task_id)) { task <- t; break }
  }
  if (!is.null(task) && nzchar(task$quiz %||% "")) {
    key <- .teaching_task_key(case_id, task_id)
    if (is.null(passed[[key]])) stop("请先观看教学视频并通过测验，再提交反思。")
  }
  .teaching_ensure_dir()
  rec <- list(
    user_id = meta$user_id,
    case_id = case_id,
    task_id = task_id,
    reflection = as.character(reflection),
    ai_declaration = ai_declaration %||% "",
    updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z")
  )
  .teaching_write_json(.teaching_reflection_path(meta$user_id, case_id, task_id), rec)
  prog <- .teaching_read_json(.teaching_progress_path(meta$user_id), default = list())
  if (is.null(prog$completed_tasks)) prog$completed_tasks <- list()
  key <- paste(case_id, task_id, sep = "::")
  prog$completed_tasks[[key]] <- rec$updated_at
  prog$user_id <- meta$user_id
  prog$updated_at <- rec$updated_at
  .teaching_write_json(.teaching_progress_path(meta$user_id), prog)
  teaching_append_trace(identity, list(
    event_type = "reflection_submit",
    case_id = case_id,
    task_id = task_id
  ))
  list(success = TRUE, progress = prog)
}

teaching_get_progress <- function(identity, user_id = NULL) {
  meta <- identity
  target <- meta$user_id
  if (!is.null(user_id) && nzchar(user_id)) target <- user_id
  prog <- .teaching_read_json(.teaching_progress_path(target), default = list(user_id = target, completed_tasks = list()))
  refs <- list.files(file.path(TEACHING_DIR, "reflections"),
                     pattern = paste0("^", make.names(target), "__"), full.names = TRUE)
  reflections <- lapply(refs, function(p) .teaching_read_json(p, default = list()))
  list(success = TRUE, user_id = target, progress = prog, reflections = reflections)
}

.teaching_user_note_path <- function(user_id, kind) {
  file.path(TEACHING_DIR, "notes", paste0(make.names(user_id), "__", make.names(kind), ".json"))
}

teaching_preclass_template <- function() {
  path <- .teaching_data_path("preclass_template.json")
  if (!file.exists(path)) stop("preclass_template.json not found.")
  .teaching_read_json(path)
}

teaching_submit_preclass <- function(identity, fields) {
  meta <- identity
  tpl <- teaching_preclass_template()
  required <- vapply(tpl$fields %||% list(), function(f) isTRUE(f$required), logical(1))
  ids <- vapply(tpl$fields %||% list(), function(f) f$id, character(1))
  for (i in seq_along(ids)) {
    if (!required[i]) next
    val <- trimws(as.character(fields[[ids[i]]] %||% ""))
    if (!nzchar(val)) stop(sprintf("Field '%s' is required.", ids[i]))
  }
  .teaching_ensure_dir()
  dir.create(file.path(TEACHING_DIR, "notes"), recursive = TRUE, showWarnings = FALSE)
  rec <- list(user_id = meta$user_id, fields = fields, updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z"))
  .teaching_write_json(.teaching_user_note_path(meta$user_id, "preclass"), rec)
  teaching_append_trace(identity, list(event_type = "preclass_submit"))
  list(success = TRUE, saved = rec)
}

teaching_critique_cases <- function() {
  path <- .teaching_data_path("ai_critique_cases.json")
  if (!file.exists(path)) stop("ai_critique_cases.json not found.")
  data <- .teaching_read_json(path)
  list(success = TRUE, cases = data$cases %||% list())
}

teaching_submit_critique <- function(identity, case_id, error_types, correction, prompt_reflection) {
  meta <- identity
  if (!nzchar(trimws(as.character(correction %||% "")))) stop("Correction text is required.")
  rec <- list(
    user_id = meta$user_id,
    case_id = case_id,
    error_types = error_types,
    correction = as.character(correction),
    prompt_reflection = as.character(prompt_reflection %||% ""),
    updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z")
  )
  .teaching_ensure_dir()
  dir.create(file.path(TEACHING_DIR, "notes"), recursive = TRUE, showWarnings = FALSE)
  .teaching_write_json(.teaching_user_note_path(meta$user_id, paste0("critique_", case_id)), rec)
  teaching_append_trace(identity, list(event_type = "critique_submit", case_id = case_id))
  list(success = TRUE, saved = rec)
}

teaching_save_journal <- function(identity, interpretation, hypothesis, limitations, ai_declaration) {
  meta <- identity
  rec <- list(
    user_id = meta$user_id,
    interpretation = as.character(interpretation %||% ""),
    hypothesis = as.character(hypothesis %||% ""),
    limitations = as.character(limitations %||% ""),
    ai_declaration = as.character(ai_declaration %||% ""),
    updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z")
  )
  .teaching_ensure_dir()
  dir.create(file.path(TEACHING_DIR, "notes"), recursive = TRUE, showWarnings = FALSE)
  .teaching_write_json(.teaching_user_note_path(meta$user_id, "journal"), rec)
  teaching_append_trace(identity, list(event_type = "journal_save"))
  list(success = TRUE, saved = rec)
}

teaching_build_report <- function(identity) {
  meta <- identity
  prog <- teaching_get_progress(identity)
  journal <- .teaching_read_json(.teaching_user_note_path(meta$user_id, "journal"), default = list())
  traces <- teaching_list_traces(identity, limit = 500L)
  lines <- c(
    "# EMP-Web 课程项目报告",
    "",
    sprintf("会话 ID: %s", meta$user_id),
    sprintf("生成时间: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    "",
    "## 视频测验进度",
    sprintf("已通过 %d 个步骤测验。", length(prog$progress$passed_quizzes %||% list())),
    "",
    "## 科学解读与假设",
    ""
  )
  if (nzchar(journal$interpretation %||% "")) lines <- c(lines, "### 结果解读", "", journal$interpretation, "")
  if (nzchar(journal$hypothesis %||% "")) lines <- c(lines, "### 可验证假设", "", journal$hypothesis, "")
  if (nzchar(journal$limitations %||% "")) lines <- c(lines, "### 局限性", "", journal$limitations, "")
  if (nzchar(journal$ai_declaration %||% "")) lines <- c(lines, "### AI 使用声明", "", journal$ai_declaration, "")
  lines <- c(lines, "## 任务反思", "")
  refs <- prog$reflections %||% list()
  if (length(refs)) {
    for (r in refs) {
      lines <- c(lines,
        sprintf("- **%s / %s**", r$case_id %||% "?", r$task_id %||% "?"),
        sprintf("  %s", r$reflection %||% ""),
        ""
      )
    }
  } else {
    lines <- c(lines, "（无）", "")
  }
  lines <- c(lines, "## Learning Trace 摘要", sprintf("共 %d 条事件。", length(traces$events %||% list())), "")
  md <- paste(lines, collapse = "\n")
  list(success = TRUE, markdown = md, progress = prog$progress)
}

plumber_teaching_cases_get <- function(res) {
  safe_api({
    data <- teaching_load_cases()
    list(success = TRUE, course_code = data$course_code %||% EMP_COURSE_CODE, cases = data$cases %||% list())
  }, res)
}

plumber_teaching_case_get <- function(case_id, req, res) {
  safe_api({
    identity <- .teaching_identity_from_req(req)
    list(success = TRUE, case = teaching_get_case_for_user(case_id, identity))
  }, res)
}

plumber_teaching_quiz_post <- function(req, res) {
  safe_api({
    identity <- .teaching_identity_from_req(req)
    b <- jsonlite::fromJSON(req$postBody, simplifyVector = FALSE)
    teaching_submit_quiz(
      identity,
      case_id = b$case_id,
      task_id = b$task_id,
      answers = b$answers
    )
  }, res)
}

plumber_teaching_prompts_get <- function(res) {
  safe_api({
    data <- teaching_load_prompts()
    list(success = TRUE, categories = data$categories %||% list())
  }, res)
}

plumber_teaching_trace_post <- function(req, res) {
  safe_api({
    identity <- .teaching_identity_from_req(req)
    b <- jsonlite::fromJSON(req$postBody)
    teaching_append_trace(identity, b)
  }, res)
}

plumber_teaching_trace_get <- function(req, res, user_id = NULL, limit = 200) {
  safe_api({
    identity <- .teaching_identity_from_req(req)
    teaching_list_traces(identity, user_id = user_id, limit = as.integer(limit %||% 200L))
  }, res)
}

plumber_teaching_reflection_post <- function(req, res) {
  safe_api({
    identity <- .teaching_identity_from_req(req)
    b <- jsonlite::fromJSON(req$postBody)
    teaching_save_reflection(
      identity,
      case_id = b$case_id,
      task_id = b$task_id,
      reflection = b$reflection,
      ai_declaration = b$ai_declaration
    )
  }, res)
}

plumber_teaching_progress_get <- function(req, res, user_id = NULL) {
  safe_api({
    identity <- .teaching_identity_from_req(req)
    teaching_get_progress(identity, user_id = user_id)
  }, res)
}

plumber_teaching_preclass_get <- function(res) {
  safe_api({
    list(success = TRUE, template = teaching_preclass_template())
  }, res)
}

plumber_teaching_preclass_post <- function(req, res) {
  safe_api({
    identity <- .teaching_identity_from_req(req)
    b <- jsonlite::fromJSON(req$postBody)
    teaching_submit_preclass(identity, b$fields)
  }, res)
}

plumber_teaching_critique_get <- function(res) {
  safe_api({
    teaching_critique_cases()
  }, res)
}

plumber_teaching_critique_post <- function(req, res) {
  safe_api({
    identity <- .teaching_identity_from_req(req)
    b <- jsonlite::fromJSON(req$postBody)
    teaching_submit_critique(
      identity,
      case_id = b$case_id,
      error_types = b$error_types,
      correction = b$correction,
      prompt_reflection = b$prompt_reflection
    )
  }, res)
}

plumber_teaching_journal_post <- function(req, res) {
  safe_api({
    identity <- .teaching_identity_from_req(req)
    b <- jsonlite::fromJSON(req$postBody)
    teaching_save_journal(
      identity,
      interpretation = b$interpretation,
      hypothesis = b$hypothesis,
      limitations = b$limitations,
      ai_declaration = b$ai_declaration
    )
  }, res)
}

plumber_teaching_report_get <- function(req, res) {
  safe_api({
    identity <- .teaching_identity_from_req(req)
    teaching_build_report(identity)
  }, res)
}
