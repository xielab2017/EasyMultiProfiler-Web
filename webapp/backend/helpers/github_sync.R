# Course GitHub sync: student accounts (学号 + 口令), PAT bind, weekly/project runs.

.github_sync_data_path <- function(name) {
  backend <- Sys.getenv("EMP_BACKEND_DIR", Sys.getenv("BACKEND_DIR", unset = ""))
  if (!nzchar(backend)) backend <- getwd()
  data_dir <- normalizePath(file.path(backend, "..", "data"), mustWork = FALSE)
  file.path(data_dir, name)
}

.github_students_root <- function() {
  override <- trimws(Sys.getenv("EMP_STUDENTS_DIR", unset = ""))
  if (nzchar(override)) {
    target <- path.expand(override)
  } else {
    target <- file.path(.emp_platform_data_root(), "students")
  }
  dir.create(target, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(target, "sessions"), recursive = TRUE, showWarnings = FALSE)
  normalizePath(target, winslash = "/", mustWork = FALSE)
}

.github_read_json <- function(path, default = list()) {
  if (!file.exists(path)) return(default)
  tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) default)
}

.github_write_json <- function(path, obj) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  jsonlite::write_json(obj, tmp, auto_unbox = TRUE, pretty = TRUE, null = "null")
  file.rename(tmp, path)
}

.github_student_id_ok <- function(student_id) {
  grepl("^[A-Za-z0-9][A-Za-z0-9._-]{2,31}$", as.character(student_id %||% ""))
}

.github_profile_path <- function(student_id) {
  file.path(.github_students_root(), make.names(student_id), "profile.json")
}

.github_sync_log_path <- function(student_id) {
  file.path(.github_students_root(), make.names(student_id), "sync_log.jsonl")
}

.github_session_path <- function(token_hash) {
  file.path(.github_students_root(), "sessions", paste0(token_hash, ".json"))
}

.github_secret_key <- function() {
  key <- trimws(Sys.getenv("EMP_GITHUB_SECRET_KEY", unset = ""))
  if (!nzchar(key)) key <- trimws(Sys.getenv("EMP_API_TOKEN", unset = ""))
  if (!nzchar(key)) key <- "emp-local-dev-github-secret-change-me"
  openssl::sha256(charToRaw(key))
}

.github_encrypt <- function(plaintext) {
  iv <- openssl::rand_bytes(16L)
  raw_pt <- charToRaw(enc2utf8(as.character(plaintext)))
  enc <- openssl::aes_cbc_encrypt(raw_pt, key = .github_secret_key(), iv = iv)
  list(
    ciphertext = openssl::base64_encode(enc),
    iv = openssl::base64_encode(iv)
  )
}

.github_decrypt <- function(ciphertext_b64, iv_b64) {
  enc <- openssl::base64_decode(ciphertext_b64)
  iv <- openssl::base64_decode(iv_b64)
  raw_pt <- openssl::aes_cbc_decrypt(enc, key = .github_secret_key(), iv = iv)
  rawToChar(raw_pt)
}

.github_hash_password <- function(password, salt_b64 = NULL) {
  if (is.null(salt_b64) || !nzchar(salt_b64)) {
    salt <- openssl::rand_bytes(16L)
    salt_b64 <- openssl::base64_encode(salt)
  } else {
    salt <- openssl::base64_decode(salt_b64)
  }
  material <- c(salt, charToRaw(enc2utf8(as.character(password))))
  digest_hex <- digest::digest(material, algo = "sha256", serialize = FALSE)
  list(hash = digest_hex, salt = salt_b64)
}

.github_check_password <- function(password, hash, salt_b64) {
  got <- .github_hash_password(password, salt_b64)
  isTRUE(.emp_constant_time_equal(got$hash, as.character(hash %||% "")))
}

.github_new_session_token <- function() {
  paste0("empstu_", openssl::base64_encode(openssl::rand_bytes(24L)))
}

.github_token_hash <- function(token) {
  digest::digest(as.character(token), algo = "sha256", serialize = FALSE)
}

github_load_assignments <- function() {
  path <- .github_sync_data_path("course_assignments.json")
  if (!file.exists(path)) stop("course_assignments.json not found.")
  .github_read_json(path)
}

.github_slugify <- function(text, fallback = "custom") {
  raw <- trimws(as.character(text %||% ""))
  if (!nzchar(raw)) return(fallback)
  # Keep ASCII letters/digits/_/- ; map spaces to _
  ascii <- iconv(raw, to = "ASCII//TRANSLIT", sub = "")
  if (is.na(ascii) || !nzchar(ascii)) ascii <- raw
  slug <- gsub("[^A-Za-z0-9._-]+", "_", ascii)
  slug <- gsub("^_+|_+$", "", slug)
  slug <- substr(slug, 1L, 48L)
  if (!nzchar(slug) || !grepl("^[A-Za-z0-9]", slug)) {
    # Chinese / non-ASCII titles: stable hash suffix
    hx <- substr(digest::digest(raw, algo = "sha1", serialize = FALSE), 1L, 8L)
    slug <- paste0(fallback, "_", hx)
  }
  slug
}

.github_phase_for_week <- function(week) {
  week <- as.integer(week)
  if (week <= 1L) return("import")
  if (week == 2L) return("prepare")
  if (week == 3L) return("analysis")
  if (week == 4L) return("visualization")
  if (week == 5L) return("interpretation")
  "weekly"
}

.github_build_week_assignment <- function(week, track, data) {
  week <- as.integer(week)
  titles <- track$week_titles %||% list()
  key <- as.character(week)
  named <- if (!is.null(titles[[key]])) titles[[key]] else NULL
  title <- if (nzchar(as.character(named %||% ""))) {
    sprintf("第%d周 · %s", week, named)
  } else {
    sprintf("第%d周", week)
  }
  task_map <- track$week_task_ids %||% list()
  tasks <- if (!is.null(task_map[[key]])) task_map[[key]] else list()
  include <- data$default_week_include %||% list(
    "manifest", "assay", "coldata", "results", "plots", "teaching"
  )
  list(
    id = sprintf("week_%02d", week),
    week = week,
    type = "weekly",
    title = title,
    task_ids = tasks,
    phase = .github_phase_for_week(week),
    include = include
  )
}

.github_expand_track <- function(track, data) {
  week_count <- as.integer(data$week_count %||% 16L)
  if (!is.finite(week_count) || week_count < 1L) week_count <- 16L
  if (week_count > 32L) week_count <- 32L
  weeks <- lapply(seq_len(week_count), function(w) .github_build_week_assignment(w, track, data))
  projects <- data$projects %||% list()
  # append keeps list-of-lists; c() can flatten in edge cases
  assignments <- append(weeks, projects)
  list(
    id = track$id,
    case_id = track$case_id %||% NULL,
    title = track$title %||% track$id,
    custom = isTRUE(track$custom),
    assignments = assignments
  )
}

github_list_assignments <- function() {
  data <- github_load_assignments()
  tracks <- lapply(data$tracks %||% list(), function(tr) .github_expand_track(tr, data))
  list(
    success = TRUE,
    course_code = data$course_code %||% EMP_COURSE_CODE,
    repo_root = data$repo_root %||% (data$course_code %||% EMP_COURSE_CODE),
    week_count = as.integer(data$week_count %||% 16L),
    tracks = tracks
  )
}

.github_synthesize_assignment <- function(assignment_id, track, data) {
  assignment_id <- trimws(as.character(assignment_id %||% ""))
  m <- regexec("^week_([0-9]{1,2})$", assignment_id)
  parts <- regmatches(assignment_id, m)[[1]]
  if (length(parts) == 2L) {
    week <- as.integer(parts[[2]])
    if (is.finite(week) && week >= 1L && week <= 32L) {
      return(.github_build_week_assignment(week, track, data))
    }
  }
  if (identical(assignment_id, "project_major")) {
    return(list(
      id = "project_major",
      week = NULL,
      type = "project",
      title = "项目大作业",
      task_ids = list(),
      phase = "project",
      include = data$default_week_include %||% list(
        "manifest", "assay", "coldata", "results", "plots", "teaching", "report"
      )
    ))
  }
  if (identical(assignment_id, "project_final")) {
    return(list(
      id = "project_final",
      week = NULL,
      type = "project",
      title = "期末项目",
      task_ids = list(),
      phase = "project",
      include = data$default_week_include %||% list(
        "manifest", "assay", "coldata", "results", "plots", "teaching", "report"
      )
    ))
  }
  NULL
}

github_get_assignment <- function(track_id, assignment_id,
                                  custom_track_name = NULL,
                                  custom_assignment_title = NULL) {
  track_id <- trimws(as.character(track_id %||% ""))
  assignment_id <- trimws(as.character(assignment_id %||% ""))
  if (!nzchar(track_id) || !nzchar(assignment_id)) {
    stop("track_id and assignment_id are required.")
  }

  data <- tryCatch(github_load_assignments(), error = function(e) {
    list(
      course_code = EMP_COURSE_CODE,
      repo_root = EMP_COURSE_CODE,
      week_count = 16L,
      projects = list(),
      default_week_include = list("manifest", "assay", "coldata", "results", "plots", "teaching"),
      tracks = list()
    )
  })

  track <- NULL
  for (tr in data$tracks %||% list()) {
    if (identical(as.character(tr$id %||% ""), track_id)) { track <- tr; break }
  }
  # Allow unknown track ids (e.g. stale UI) by synthesizing a bare track
  if (is.null(track)) {
    track <- list(
      id = track_id,
      title = track_id,
      custom = identical(track_id, "customize"),
      case_id = NULL,
      week_titles = list()
    )
  }

  expanded <- tryCatch(.github_expand_track(track, data), error = function(e) list(assignments = list()))
  hit <- NULL
  for (a in expanded$assignments %||% list()) {
    if (is.list(a) && identical(as.character(a$id %||% ""), assignment_id)) {
      hit <- a
      break
    }
  }
  if (is.null(hit)) hit <- .github_synthesize_assignment(assignment_id, track, data)
  if (is.null(hit)) stop(sprintf("Unknown assignment: %s / %s", track_id, assignment_id))

  # Folder / display overrides for customize track
  track_folder <- as.character(track$id %||% track_id)
  track_title <- as.character(track$title %||% track$id %||% track_id)
  if (isTRUE(track$custom) || identical(track_id, "customize")) {
    cname <- trimws(as.character(custom_track_name %||% ""))
    if (!nzchar(cname)) stop("自定义轨道请填写轨道名称。")
    track_title <- cname
    track_folder <- .github_slugify(cname, fallback = "customize")
  }

  title <- as.character(hit$title %||% hit$id)
  ctitle <- trimws(as.character(custom_assignment_title %||% ""))
  if (identical(hit$type, "custom") || identical(hit$id, "assignment_custom")) {
    if (!nzchar(ctitle)) stop("自定义作业请填写作业标题。")
    title <- ctitle
  } else if (nzchar(ctitle)) {
    title <- ctitle
  }

  assignment_folder <- as.character(hit$id)
  if (identical(hit$type, "custom") || identical(hit$id, "assignment_custom")) {
    assignment_folder <- paste0("custom_", .github_slugify(title, fallback = "assignment"))
  }

  list(
    id = hit$id,
    folder_id = assignment_folder,
    week = hit$week %||% NULL,
    type = hit$type %||% "weekly",
    title = title,
    task_ids = hit$task_ids %||% list(),
    phase = hit$phase %||% "weekly",
    include = hit$include %||% list("manifest", "teaching"),
    track_id = track_folder,
    track_key = as.character(track$id %||% track_id),
    case_id = track$case_id %||% NULL,
    track_title = track_title,
    course_code = data$course_code %||% EMP_COURSE_CODE,
    repo_root = data$repo_root %||% (data$course_code %||% EMP_COURSE_CODE)
  )
}

.github_public_profile <- function(profile) {
  gh <- profile$github %||% list()
  bound <- isTRUE(gh$bound) && nzchar(gh$owner %||% "") && nzchar(gh$repo %||% "")
  list(
    student_id = profile$student_id,
    display_name = profile$display_name %||% profile$student_id,
    created_at = profile$created_at %||% NULL,
    github = list(
      bound = bound,
      owner = if (bound) gh$owner else NULL,
      repo = if (bound) gh$repo else NULL,
      branch = if (bound) (gh$branch %||% "main") else NULL,
      html_url = if (bound) sprintf("https://github.com/%s/%s", gh$owner, gh$repo) else NULL,
      bound_at = if (bound) gh$bound_at else NULL
    )
  )
}

.github_load_profile <- function(student_id) {
  if (!.github_student_id_ok(student_id)) stop("Invalid student_id.")
  path <- .github_profile_path(student_id)
  if (!file.exists(path)) stop("Student account not found. Please register first.")
  profile <- .github_read_json(path)
  if (!nzchar(profile$student_id %||% "")) stop("Corrupt student profile.")
  profile
}

.github_save_profile <- function(profile) {
  .github_write_json(.github_profile_path(profile$student_id), profile)
}

.github_class_homework_repo_url <- function() {
  trimws(Sys.getenv("EMP_CLASS_HOMEWORK_REPO", unset = ""))
}

.github_class_github_token <- function() {
  trimws(Sys.getenv("EMP_CLASS_GITHUB_TOKEN", unset = ""))
}

github_class_config <- function() {
  class_url <- .github_class_homework_repo_url()
  if (!nzchar(class_url)) {
    return(list(
      class_homework_repo = "",
      owner = NULL,
      repo = NULL,
      has_class_token = FALSE,
      configured = FALSE
    ))
  }
  parsed <- .github_parse_repo(class_url)
  list(
    class_homework_repo = class_url,
    owner = parsed$owner,
    repo = parsed$repo,
    has_class_token = nzchar(.github_class_github_token()),
    configured = TRUE
  )
}

.github_is_class_repo_bound <- function(gh, cfg = NULL) {
  cfg <- cfg %||% github_class_config()
  isTRUE(cfg$configured) && isTRUE(gh$bound) &&
    identical(as.character(gh$owner %||% ""), as.character(cfg$owner)) &&
    identical(as.character(gh$repo %||% ""), as.character(cfg$repo))
}

.github_push_connection_artifact <- function(identity) {
  profile <- identity$profile
  gh <- profile$github %||% list()
  if (!isTRUE(gh$bound)) stop("尚未绑定课堂仓库。")
  token <- .github_get_pat(profile)
  owner <- gh$owner
  repo <- gh$repo
  branch <- gh$branch %||% "main"
  conn <- list(
    event = "connection",
    student_id = identity$student_id,
    display_name = profile$display_name %||% identity$student_id,
    connected_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    class_homework_repo = sprintf("%s/%s", owner, repo),
    emp_version = .github_emp_version()
  )
  staging <- tempfile(pattern = "emp-gh-conn-")
  dir.create(staging, recursive = TRUE)
  on.exit(unlink(staging, recursive = TRUE, force = TRUE), add = TRUE)
  abs_path <- file.path(staging, "connection.json")
  jsonlite::write_json(conn, abs_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  rel <- sprintf(
    "EMP2026/students/%s/connection.json",
    make.names(identity$student_id)
  )
  push <- .github_push_files(
    owner, repo, branch, token,
    list(list(path = gsub("\\\\", "/", rel), abs = abs_path)),
    sprintf("[EMP] connect %s to class homework repo", identity$student_id)
  )
  list(success = TRUE, html_url = push$html_url, path = rel, commit_sha = push$commit_sha)
}

github_ensure_class_repo <- function(identity) {
  cfg <- github_class_config()
  class_url <- cfg$class_homework_repo
  profile <- .github_load_profile(identity$student_id)
  identity$profile <- profile
  gh <- profile$github %||% list()
  auto_bound <- FALSE
  need_pat <- FALSE
  connection_pushed <- FALSE
  connection_error <- NULL

  if (!isTRUE(cfg$configured)) {
    bound <- isTRUE(gh$bound)
    return(list(
      success = TRUE,
      class_homework_repo = "",
      github_bound = bound,
      auto_bound = FALSE,
      need_pat = !bound,
      connection_pushed = FALSE,
      student = .github_public_profile(profile)
    ))
  }

  push_conn <- function(idty) {
    tryCatch({
      .github_push_connection_artifact(idty)
      connection_pushed <<- TRUE
      NULL
    }, error = function(e) {
      connection_error <<- conditionMessage(e)
      NULL
    })
  }

  if (.github_is_class_repo_bound(gh, cfg)) {
    # Already on class repo — keep bind; connection push is best-effort once.
    need_pat <- FALSE
  } else if (nzchar(.github_class_github_token())) {
    github_bind_repo(identity, class_url, .github_class_github_token(), branch = NULL)
    identity$profile <- .github_load_profile(identity$student_id)
    auto_bound <- TRUE
    push_conn(identity)
  } else if (isTRUE(gh$bound) && nzchar(gh$token_ciphertext %||% "")) {
    token <- tryCatch(.github_get_pat(profile), error = function(e) "")
    if (!nzchar(token)) {
      need_pat <- TRUE
    } else {
      ok <- tryCatch({
        github_bind_repo(identity, class_url, token, branch = gh$branch)
        TRUE
      }, error = function(e) FALSE)
      if (isTRUE(ok)) {
        identity$profile <- .github_load_profile(identity$student_id)
        auto_bound <- TRUE
        push_conn(identity)
      } else {
        need_pat <- TRUE
      }
    }
  } else {
    need_pat <- TRUE
  }

  profile <- .github_load_profile(identity$student_id)
  bound <- isTRUE((profile$github %||% list())$bound)
  out <- list(
    success = TRUE,
    class_homework_repo = class_url,
    github_bound = bound,
    auto_bound = auto_bound,
    need_pat = isTRUE(need_pat) && !bound,
    connection_pushed = connection_pushed,
    student = .github_public_profile(profile)
  )
  if (!is.null(connection_error)) out$connection_error <- connection_error
  out
}

.github_auth_with_class_repo <- function(student_token, profile) {
  identity <- list(
    student_id = profile$student_id,
    profile = profile,
    token_hash = .github_token_hash(student_token)
  )
  ensure <- tryCatch(
    github_ensure_class_repo(identity),
    error = function(e) {
      list(
        class_homework_repo = .github_class_homework_repo_url(),
        github_bound = isTRUE((profile$github %||% list())$bound),
        auto_bound = FALSE,
        need_pat = !isTRUE((profile$github %||% list())$bound),
        connection_pushed = FALSE,
        student = .github_public_profile(profile),
        ensure_error = conditionMessage(e)
      )
    }
  )
  list(
    success = TRUE,
    student_token = student_token,
    student = ensure$student %||% .github_public_profile(profile),
    class_homework_repo = ensure$class_homework_repo %||% .github_class_homework_repo_url(),
    github_bound = isTRUE(ensure$github_bound),
    auto_bound = isTRUE(ensure$auto_bound),
    need_pat = isTRUE(ensure$need_pat),
    connection_pushed = isTRUE(ensure$connection_pushed),
    connection_error = ensure$connection_error %||% NULL,
    ensure_error = ensure$ensure_error %||% NULL
  )
}

github_register_student <- function(student_id, password, display_name = NULL) {
  student_id <- trimws(as.character(student_id %||% ""))
  password <- as.character(password %||% "")
  display_name <- trimws(as.character(display_name %||% ""))
  if (!.github_student_id_ok(student_id)) {
    stop("学号格式无效：3–32 位字母数字，可含 . _ -")
  }
  if (!nzchar(display_name)) stop("请填写姓名（显示名不能为空）。")
  if (nchar(password, type = "chars") < 8L) stop("口令至少 8 位。")
  path <- .github_profile_path(student_id)
  if (file.exists(path)) stop("该学号已注册，请直接登录。")
  hashed <- .github_hash_password(password)
  profile <- list(
    student_id = student_id,
    display_name = display_name,
    password_hash = hashed$hash,
    password_salt = hashed$salt,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    github = list(bound = FALSE)
  )
  .github_save_profile(profile)
  github_login_student(student_id, password, display_name = display_name)
}

github_login_student <- function(student_id, password, display_name = NULL) {
  student_id <- trimws(as.character(student_id %||% ""))
  password <- as.character(password %||% "")
  profile <- tryCatch(.github_load_profile(student_id), error = function(e) NULL)
  if (is.null(profile) || !.github_check_password(password, profile$password_hash, profile$password_salt)) {
    stop("学号或口令错误。")
  }
  dn <- trimws(as.character(display_name %||% ""))
  if (nzchar(dn)) {
    profile$display_name <- dn
    .github_save_profile(profile)
  }
  raw_token <- .github_new_session_token()
  th <- .github_token_hash(raw_token)
  .github_write_json(.github_session_path(th), list(
    student_id = student_id,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    expires_at = format(Sys.time() + 60 * 60 * 24 * 30, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  ))
  .github_auth_with_class_repo(raw_token, profile)
}

github_logout_student <- function(student_token) {
  th <- .github_token_hash(student_token)
  path <- .github_session_path(th)
  if (file.exists(path)) unlink(path)
  list(success = TRUE)
}

.github_identity_from_req <- function(req) {
  token <- trimws(as.character(
    req$HTTP_X_STUDENT_TOKEN %||% req$headers[["x-student-token"]] %||% ""
  ))
  if (!nzchar(token)) stop("请先用学号登录（缺少 X-Student-Token）。")
  th <- .github_token_hash(token)
  sess <- .github_read_json(.github_session_path(th), default = NULL)
  if (is.null(sess) || !nzchar(sess$student_id %||% "")) stop("学生登录已失效，请重新登录。")
  expires <- sess$expires_at %||% ""
  if (nzchar(expires)) {
    exp_t <- tryCatch(as.POSIXct(expires, tz = "UTC"), error = function(e) NULL)
    if (!is.null(exp_t) && exp_t < Sys.time()) {
      unlink(.github_session_path(th))
      stop("学生登录已过期，请重新登录。")
    }
  }
  profile <- .github_load_profile(sess$student_id)
  list(student_id = profile$student_id, profile = profile, token_hash = th)
}

.github_parse_repo <- function(repo_url) {
  raw <- trimws(as.character(repo_url %||% ""))
  if (!nzchar(raw)) stop("请填写 GitHub 仓库地址。")
  raw <- sub("\\.git$", "", raw)
  m <- regexec("github\\.com[/:]([^/]+)/([^/#?]+)", raw, ignore.case = TRUE)
  parts <- regmatches(raw, m)[[1]]
  if (length(parts) == 3L) {
    return(list(owner = parts[[2]], repo = parts[[3]]))
  }
  m2 <- regexec("^([^/]+)/([^/]+)$", raw)
  parts2 <- regmatches(raw, m2)[[1]]
  if (length(parts2) == 3L) {
    return(list(owner = parts2[[2]], repo = parts2[[3]]))
  }
  stop("仓库地址格式应为 https://github.com/user/repo 或 user/repo")
}

.github_api <- function(method, path, token, body = NULL) {
  url <- paste0("https://api.github.com", path)
  req <- httr2::request(url) |>
    httr2::req_method(method) |>
    httr2::req_headers(
      Authorization = paste("Bearer", token),
      Accept = "application/vnd.github+json",
      `X-GitHub-Api-Version` = "2022-11-28",
      `User-Agent` = "EasyMultiProfiler-Web-CourseSync"
    ) |>
    httr2::req_error(is_error = function(resp) FALSE)
  if (!is.null(body)) {
    req <- httr2::req_body_json(req, body, auto_unbox = TRUE)
  }
  resp <- httr2::req_perform(req)
  status <- httr2::resp_status(resp)
  text <- httr2::resp_body_string(resp)
  parsed <- tryCatch(jsonlite::fromJSON(text, simplifyVector = FALSE), error = function(e) list(message = text))
  list(status = status, body = parsed, raw = text)
}

.github_validate_token_repo <- function(token, owner, repo) {
  me <- .github_api("GET", "/user", token)
  if (me$status < 200 || me$status >= 300) {
    stop("GitHub Token 无效或无权访问。请使用 classic PAT（repo 权限）或 fine-grained（Contents: Read and write）。")
  }
  repo_info <- .github_api("GET", sprintf("/repos/%s/%s", owner, repo), token)
  if (repo_info$status == 404) stop(sprintf("找不到仓库 %s/%s，或 Token 无权访问。", owner, repo))
  if (repo_info$status < 200 || repo_info$status >= 300) {
    stop(sprintf("无法读取仓库：%s", repo_info$body$message %||% repo_info$raw))
  }
  perms <- repo_info$body$permissions %||% list()
  if (!isTRUE(perms$push) && !isTRUE(perms$admin)) {
    stop("Token 对该仓库没有写权限（需要 push）。")
  }
  list(
    login = me$body$login %||% "",
    default_branch = repo_info$body$default_branch %||% "main",
    html_url = repo_info$body$html_url %||% sprintf("https://github.com/%s/%s", owner, repo)
  )
}

github_bind_repo <- function(identity, repo_url, github_token, branch = NULL) {
  # Bind the repository explicitly provided by the user. A configured class
  # repository still uses this function by passing its URL during auto-bind.
  parsed <- .github_parse_repo(repo_url)
  token <- trimws(as.character(github_token %||% ""))
  if (!nzchar(token)) stop("请提供 GitHub Personal Access Token。")
  info <- .github_validate_token_repo(token, parsed$owner, parsed$repo)
  use_branch <- if (nzchar(trimws(as.character(branch %||% "")))) {
    trimws(as.character(branch))
  } else info$default_branch
  enc <- .github_encrypt(token)
  profile <- identity$profile
  profile$github <- list(
    bound = TRUE,
    owner = parsed$owner,
    repo = parsed$repo,
    branch = use_branch,
    token_ciphertext = enc$ciphertext,
    token_iv = enc$iv,
    bound_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    github_login = info$login
  )
  .github_save_profile(profile)
  list(success = TRUE, student = .github_public_profile(profile))
}

github_unbind_repo <- function(identity) {
  profile <- identity$profile
  profile$github <- list(bound = FALSE)
  .github_save_profile(profile)
  list(success = TRUE, student = .github_public_profile(profile))
}

github_status <- function(identity) {
  cfg <- github_class_config()
  list(
    success = TRUE,
    student = .github_public_profile(identity$profile),
    class_homework_repo = cfg$class_homework_repo,
    has_class_token = cfg$has_class_token,
    github_bound = isTRUE((identity$profile$github %||% list())$bound)
  )
}

.github_get_pat <- function(profile) {
  gh <- profile$github %||% list()
  if (!isTRUE(gh$bound)) stop("尚未绑定 GitHub 仓库。")
  .github_decrypt(gh$token_ciphertext, gh$token_iv)
}

.github_run_id <- function() {
  # Second-precision alone can collide when two syncs share a wall-clock second;
  # append ms + short random suffix so concurrent syncs always get unique run dirs.
  ts <- format(Sys.time(), "%Y-%m-%dT%H-%M-%OS3Z", tz = "UTC")
  ts <- gsub("\\.", "-", ts) # keep path-friendly (no dots in the fractional part)
  suffix <- paste0(sample(c(letters, 0:9), 6L, replace = TRUE), collapse = "")
  paste0(ts, "-", suffix)
}

# Copy a session artifact into staging with retry (handles mid-write / file-busy races).
.github_copy_with_retry <- function(src, dest, retries = 3L, sleep_sec = 0.25) {
  retries <- max(1L, as.integer(retries))
  last_err <- NULL
  for (i in seq_len(retries)) {
    ok <- tryCatch({
      if (!file.exists(src)) return(FALSE)
      dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
      # Atomic-ish: copy to temp then rename into place
      tmp <- paste0(dest, ".partial")
      if (file.exists(tmp)) unlink(tmp, force = TRUE)
      copied <- file.copy(src, tmp, overwrite = TRUE)
      if (!isTRUE(copied) || !file.exists(tmp)) stop("file.copy failed")
      if (isTRUE(file.info(tmp)$size <= 0)) stop("copied file is empty")
      if (grepl("\\.rds$", src, ignore.case = TRUE)) {
        # Validate RDS is readable (reject half-written objects)
        tryCatch(readRDS(tmp), error = function(e) stop(e$message))
      }
      if (file.exists(dest)) unlink(dest, force = TRUE)
      if (!isTRUE(file.rename(tmp, dest))) {
        file.copy(tmp, dest, overwrite = TRUE)
        unlink(tmp, force = TRUE)
      }
      TRUE
    }, error = function(e) {
      last_err <<- conditionMessage(e)
      FALSE
    })
    if (isTRUE(ok) && file.exists(dest)) return(TRUE)
    Sys.sleep(sleep_sec * i)
  }
  if (!is.null(last_err)) {
    stop(sprintf(
      "Could not snapshot session file `%s` (busy or incomplete write). Wait for analysis to finish, then sync again. Detail: %s",
      basename(src), last_err
    ))
  }
  FALSE
}

# Consistent snapshot of session MAE / empt / plots into staging (never mutate session).
.github_snapshot_session_artifacts <- function(session_id, staging, include_rds = FALSE, retries = 3L) {
  snap_dir <- file.path(staging, "_session_snap")
  dir.create(snap_dir, recursive = TRUE, showWarnings = FALSE)
  sess <- session_path(session_id)
  result <- list(
    snap_dir = snap_dir,
    mae = NULL,
    empt = list(), # named by experiment
    plots = character()
  )
  if (!dir.exists(sess)) return(result)

  mae_src <- mae_path(session_id)
  if (file.exists(mae_src)) {
    mae_dest <- file.path(snap_dir, "mae.rds")
    if (.github_copy_with_retry(mae_src, mae_dest, retries = retries)) {
      result$mae <- mae_dest
    }
  }

  empt_files <- list.files(sess, pattern = "^empt_.*\\.rds$", full.names = TRUE)
  for (ep in empt_files) {
    dest <- file.path(snap_dir, basename(ep))
    if (.github_copy_with_retry(ep, dest, retries = retries)) {
      # empt_<make.names(exp)>.rds → recover experiment key as best-effort from filename
      key <- sub("^empt_", "", sub("\\.rds$", "", basename(ep)))
      result$empt[[key]] <- dest
    }
  }

  plots_dir <- file.path(sess, "plots")
  if (dir.exists(plots_dir)) {
    plot_snap <- file.path(snap_dir, "plots")
    dir.create(plot_snap, recursive = TRUE, showWarnings = FALSE)
    pdfs <- list.files(plots_dir, pattern = "\\.pdf$", full.names = TRUE)
    for (pdf in pdfs) {
      dest <- file.path(plot_snap, basename(pdf))
      if (.github_copy_with_retry(pdf, dest, retries = retries)) {
        result$plots <- c(result$plots, dest)
      }
    }
  }

  invisible(result)
}

.github_load_empt_from_snap <- function(snap, session_id, experiment) {
  key <- make.names(experiment)
  path <- snap$empt[[key]] %||% snap$empt[[experiment]] %||% NULL
  if (is.null(path) || !file.exists(path)) {
    # Fall back to live load with retry (e.g. experiment name mismatch)
    last_err <- NULL
    for (i in 1:3) {
      out <- tryCatch(load_empt(session_id, experiment), error = function(e) {
        last_err <<- conditionMessage(e)
        NULL
      })
      if (!is.null(out)) return(out)
      Sys.sleep(0.2 * i)
    }
    stop(last_err %||% sprintf("EMPT missing for experiment `%s` (may still be writing).", experiment))
  }
  obj <- tryCatch(readRDS(path), error = function(e) {
    stop(sprintf("Failed reading snapped EMPT for `%s`: %s", experiment, conditionMessage(e)))
  })
  if (exists(".is_proper_empt", mode = "function") && isTRUE(.is_proper_empt(obj))) {
    return(obj)
  }
  # Non-EMPT snapshot: try live promote path
  tryCatch(load_empt(session_id, experiment), error = function(e) obj)
}

.github_session_active_jobs <- function(session_id, owner_id = NULL) {
  if (!nzchar(session_id %||% "")) return(list())
  if (!exists("list_jobs_for_session", mode = "function")) return(list())
  jobs <- tryCatch(
    list_jobs_for_session(session_id, owner_id %||% "local"),
    error = function(e) list()
  )
  Filter(function(st) {
    status <- as.character(st$status %||% "")
    status %in% c("queued", "running", "cancel_requested")
  }, jobs)
}

.github_safe_write_csv <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(df, path, row.names = FALSE)
}

.github_try_export_result <- function(session_id, experiment, analysis, dest) {
  tryCatch({
    empt <- load_empt(session_id, experiment)
    result_info_map <- c(
      alpha = "EMP_alpha_analysis",
      alpha_analysis = "EMP_alpha_analysis",
      diff = "EMP_diff_analysis",
      differential = "EMP_diff_analysis",
      diff_analysis = "EMP_diff_analysis",
      dimension = "EMP_dimension_analysis",
      enrich = "EMP_enrich_analysis",
      enrichment = "EMP_enrich_analysis",
      network = "EMP_network_analysis"
    )
    result_info <- unname(result_info_map[[analysis]])
    if (is.null(result_info) || !nzchar(result_info)) result_info <- paste0(analysis, "_result")
    result <- EasyMultiProfiler::EMP_result(empt, info = result_info)
    df <- as.data.frame(result)
    .github_safe_write_csv(df, dest)
    TRUE
  }, error = function(e) FALSE)
}

.github_emp_version <- function() {
  Sys.getenv(
    "EMP_WEB_VERSION",
    unset = tryCatch(
      as.character(utils::packageVersion("EasyMultiProfiler")),
      error = function(e) "9.0.4"
    )
  )
}

.github_week_dir <- function(assignment) {
  w <- suppressWarnings(as.integer(assignment$week %||% NA_integer_))
  if (is.finite(w) && w >= 1L) return(sprintf("Week_%02d", w))
  id <- as.character(assignment$id %||% "")
  m <- regexec("^week_([0-9]{1,2})$", id)
  parts <- regmatches(id, m)[[1]]
  if (length(parts) == 2L) {
    n <- as.integer(parts[[2]])
    if (is.finite(n)) return(sprintf("Week_%02d", n))
  }
  if (identical(id, "project_major")) return("Project_Major")
  if (identical(id, "project_final")) return("Project_Final")
  "Project_Other"
}

.github_type_dir <- function(assignment) {
  typ <- as.character(assignment$type %||% "weekly")
  if (identical(typ, "project")) return("project")
  if (identical(typ, "custom")) return("custom")
  "weekly"
}

.github_layout_paths <- function(assignment) {
  repo_root <- assignment$repo_root %||% EMP_COURSE_CODE
  track_folder <- assignment$track_id %||% "track"
  week_dir <- .github_week_dir(assignment)
  type_dir <- .github_type_dir(assignment)
  # EMP2026/Week_01/<track>/<type>/
  slot_rel <- file.path(repo_root, week_dir, track_folder, type_dir)
  list(
    repo_root = repo_root,
    week_dir = week_dir,
    track_folder = track_folder,
    type_dir = type_dir,
    slot_rel = gsub("\\\\", "/", slot_rel)
  )
}

.github_build_run_files <- function(identity, assignment, session_id, experiment = NULL,
                                    include_rds = FALSE, commit_message = NULL,
                                    github_meta = NULL) {
  include <- unlist(assignment$include %||% list("manifest", "teaching"))
  run_id <- .github_run_id()
  staging <- tempfile(pattern = "emp-gh-")
  dir.create(staging, recursive = TRUE)
  files <- list() # list of list(path=, abs=)

  add_file <- function(rel, abs_path) {
    if (!file.exists(abs_path)) return(invisible(NULL))
    files[[length(files) + 1L]] <<- list(path = rel, abs = abs_path)
    invisible(NULL)
  }

  write_text <- function(rel, text) {
    abs_path <- file.path(staging, basename(rel))
    # keep unique names under staging while preserving repo-relative path in `rel`
    abs_path <- file.path(staging, gsub("/", "__", rel, fixed = TRUE))
    dir.create(dirname(abs_path), recursive = TRUE, showWarnings = FALSE)
    writeLines(text, abs_path, useBytes = TRUE)
    add_file(rel, abs_path)
  }

  layout <- .github_layout_paths(assignment)
  repo_root <- layout$repo_root
  track_folder <- layout$track_folder
  week_dir <- layout$week_dir
  type_dir <- layout$type_dir
  emp_version <- .github_emp_version()
  gh_meta <- github_meta %||% list()
  # EMP2026/Week_01/<track>/<type>/runs/<run_id>/
  base_rel <- file.path(layout$slot_rel, "runs", run_id)
  base_rel <- gsub("\\\\", "/", base_rel)
  git_path <- base_rel

  # manifest
  if ("manifest" %in% include) {
    man <- list(
      course_code = assignment$course_code %||% EMP_COURSE_CODE,
      emp_version = emp_version,
      layout = "week_first",
      week_dir = week_dir,
      track_id = track_folder,
      track_key = assignment$track_key %||% track_folder,
      track_title = assignment$track_title %||% track_folder,
      assignment_type = type_dir,
      assignment_id = assignment$id,
      assignment_title = assignment$title,
      week = assignment$week,
      type = assignment$type %||% "weekly",
      case_id = assignment$case_id,
      task_ids = assignment$task_ids %||% list(),
      student_id = identity$student_id,
      display_name = identity$profile$display_name %||% identity$student_id,
      github_login = gh_meta$github_login %||% NULL,
      github_repo = gh_meta$github_repo %||% NULL,
      github_branch = gh_meta$github_branch %||% NULL,
      git_path = git_path,
      session_id = session_id,
      experiment = experiment,
      run_id = run_id,
      synced_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      include_rds = isTRUE(include_rds)
    )
    if (nzchar(session_id) && exists("session_manifest_path", mode = "function")) {
      man$session_manifest <- tryCatch({
        mp <- session_manifest_path(session_id)
        if (file.exists(mp)) jsonlite::read_json(mp, simplifyVector = FALSE) else list(session_id = session_id)
      }, error = function(e) list(note = conditionMessage(e)))
    }
    man_path <- file.path(staging, "manifest.json")
    jsonlite::write_json(man, man_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
    add_file(file.path(base_rel, "manifest.json"), man_path)
  }

  # analysis exports — snapshot session artifacts first so packaging never races
  # with async jobs writing mae.rds / empt_*.rds / plots.
  if (nzchar(session_id %||% "") && session_exists(session_id)) {
    snap <- .github_snapshot_session_artifacts(
      session_id, staging,
      include_rds = isTRUE(include_rds) || ("rds" %in% include),
      retries = 3L
    )
    exps <- tryCatch(list_experiments(session_id), error = function(e) character())
    if (nzchar(experiment %||% "")) {
      if (!(experiment %in% exps)) exps <- c(experiment, exps)
    }
    # Also include experiments discovered from snapped empt files
    snap_exps <- names(snap$empt %||% list())
    if (length(snap_exps)) {
      # Map make.names keys back when possible; keep raw keys as fallbacks
      exps <- unique(c(as.character(exps), snap_exps))
    }
    exps <- unique(as.character(exps))
    for (exp in exps) {
      if (!nzchar(exp)) next
      if ("assay" %in% include) {
        tryCatch({
          empt <- .github_load_empt_from_snap(snap, session_id, exp)
          ad <- SummarizedExperiment::assays(empt)[[1]]
          df <- as.data.frame(ad)
          df <- cbind(feature = rownames(df), df)
          p <- file.path(staging, paste0(make.names(exp), "_assay.csv"))
          .github_safe_write_csv(df, p)
          add_file(file.path(base_rel, "data", paste0(exp, "_assay.csv")), p)
        }, error = function(e) NULL)
      }
      if ("coldata" %in% include) {
        tryCatch({
          empt <- .github_load_empt_from_snap(snap, session_id, exp)
          cd <- as.data.frame(SummarizedExperiment::colData(empt))
          cd <- cbind(sample = rownames(cd), cd)
          p <- file.path(staging, paste0(make.names(exp), "_coldata.csv"))
          .github_safe_write_csv(cd, p)
          add_file(file.path(base_rel, "data", paste0(exp, "_metadata.csv")), p)
        }, error = function(e) NULL)
      }
      if ("results" %in% include) {
        for (an in c("diff_analysis", "alpha", "enrichment", "dimension")) {
          p <- file.path(staging, paste0(make.names(exp), "_", an, ".csv"))
          # Prefer snapped EMPT; fall back to live export helper with retry
          exported <- FALSE
          tryCatch({
            empt <- .github_load_empt_from_snap(snap, session_id, exp)
            result_info_map <- c(
              alpha = "EMP_alpha_analysis",
              diff_analysis = "EMP_diff_analysis",
              enrichment = "EMP_enrich_analysis",
              dimension = "EMP_dimension_analysis"
            )
            result_info <- unname(result_info_map[[an]])
            if (!is.null(result_info) && nzchar(result_info)) {
              result <- EasyMultiProfiler::EMP_result(empt, info = result_info)
              df <- as.data.frame(result)
              .github_safe_write_csv(df, p)
              exported <- TRUE
            }
          }, error = function(e) NULL)
          if (!exported) {
            exported <- isTRUE(.github_try_export_result(session_id, exp, an, p))
          }
          if (exported) {
            add_file(file.path(base_rel, "results", paste0(exp, "_", an, ".csv")), p)
          }
        }
        tryCatch({
          if (exists("mbx_export_diff_csv", mode = "function")) {
            df <- mbx_export_diff_csv(session_id, exp)
            p <- file.path(staging, paste0(make.names(exp), "_mbx_diff.csv"))
            .github_safe_write_csv(df, p)
            add_file(file.path(base_rel, "results", paste0(exp, "_metabolomics_differential.csv")), p)
          }
        }, error = function(e) NULL)
        tryCatch({
          if (exists("mgx_export_diff_csv", mode = "function")) {
            df <- mgx_export_diff_csv(session_id, exp)
            p <- file.path(staging, paste0(make.names(exp), "_mgx_diff.csv"))
            .github_safe_write_csv(df, p)
            add_file(file.path(base_rel, "results", paste0(exp, "_metagenomics_differential.csv")), p)
          }
        }, error = function(e) NULL)
      }
    }
    if ("plots" %in% include) {
      for (pdf in snap$plots %||% character()) {
        add_file(file.path(base_rel, "plots", basename(pdf)), pdf)
      }
    }
    if (isTRUE(include_rds) || ("rds" %in% include)) {
      if (!is.null(snap$mae) && file.exists(snap$mae)) {
        add_file(file.path(base_rel, "session", "EMP_session.rds"), snap$mae)
      }
    }
  }

  # teaching artifacts (use analysis session_id as teaching user when available)
  teach_uid <- session_id
  if (!nzchar(teach_uid %||% "")) teach_uid <- identity$student_id
  teach_identity <- list(user_id = teach_uid, role = "local", display_name = identity$student_id)

  if ("teaching" %in% include || "report" %in% include) {
    tryCatch({
      prog <- teaching_get_progress(teach_identity)
      p <- file.path(staging, "progress.json")
      jsonlite::write_json(prog, p, auto_unbox = TRUE, pretty = TRUE, null = "null")
      add_file(file.path(base_rel, "teaching", "progress.json"), p)
    }, error = function(e) NULL)
    tryCatch({
      traces <- teaching_list_traces(teach_identity, limit = 500L)
      p <- file.path(staging, "learning_trace.json")
      jsonlite::write_json(traces, p, auto_unbox = TRUE, pretty = TRUE, null = "null")
      add_file(file.path(base_rel, "teaching", "learning_trace.json"), p)
    }, error = function(e) NULL)
  }
  if ("report" %in% include || "teaching" %in% include) {
    tryCatch({
      report <- teaching_build_report(teach_identity)
      p <- file.path(staging, "report.md")
      writeLines(report$markdown %||% "", p, useBytes = TRUE)
      add_file(file.path(base_rel, "teaching", "report.md"), p)
    }, error = function(e) NULL)
  }

  # LATEST pointer under Week_XX/<track>/<type>/
  latest_rel <- file.path(layout$slot_rel, "LATEST")
  write_text(gsub("\\\\", "/", latest_rel), run_id)

  # Student + GitHub + version registry (visible in GitHub UI)
  profile_rel <- file.path(repo_root, "profile.json")
  profile_pub <- list(
    student_id = identity$student_id,
    display_name = identity$profile$display_name %||% identity$student_id,
    course_code = assignment$course_code %||% EMP_COURSE_CODE,
    emp_version = emp_version,
    github_login = gh_meta$github_login %||% NULL,
    github_repo = gh_meta$github_repo %||% NULL,
    github_branch = gh_meta$github_branch %||% NULL,
    github_html_url = gh_meta$github_html_url %||% NULL,
    last_git_path = git_path,
    last_week_dir = week_dir,
    last_track = track_folder,
    last_assignment_type = type_dir,
    last_run_id = run_id,
    updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
  p_prof <- file.path(staging, "profile.json")
  jsonlite::write_json(profile_pub, p_prof, auto_unbox = TRUE, pretty = TRUE, null = "null")
  add_file(gsub("\\\\", "/", profile_rel), p_prof)

  # Per-sync ledger entry (additive file; does not erase prior ledger rows)
  ledger <- list(
    event = "sync",
    synced_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    student_id = identity$student_id,
    display_name = identity$profile$display_name %||% identity$student_id,
    emp_version = emp_version,
    github_login = gh_meta$github_login %||% NULL,
    github_repo = gh_meta$github_repo %||% NULL,
    github_branch = gh_meta$github_branch %||% NULL,
    week_dir = week_dir,
    track = track_folder,
    assignment_type = type_dir,
    assignment_id = assignment$id,
    assignment_title = assignment$title,
    git_path = git_path,
    run_id = run_id
  )
  ledger_rel <- file.path(repo_root, "_ledger", paste0(run_id, ".json"))
  p_ledger <- file.path(staging, paste0("ledger__", run_id, ".json"))
  jsonlite::write_json(ledger, p_ledger, auto_unbox = TRUE, pretty = TRUE, null = "null")
  add_file(gsub("\\\\", "/", ledger_rel), p_ledger)

  readme_rel <- file.path(repo_root, "README.md")
  readme <- paste(
    sprintf("# %s Course Submissions", assignment$course_code %||% EMP_COURSE_CODE),
    "",
    sprintf("- Student ID: `%s`", profile_pub$student_id),
    sprintf("- Display name: **%s**", profile_pub$display_name),
    sprintf("- EMP version: `%s`", emp_version),
    sprintf("- GitHub: `%s` / `%s`", profile_pub$github_login %||% "-", profile_pub$github_repo %||% "-"),
    "",
    "## Layout",
    "",
    "Week folders use `Week_01` … `Week_16` (sortable; UI labels show Week 1–16).",
    "Under each week: analysis track → assignment type (`weekly` / `project`) → `runs/<timestamp>/`.",
    "",
    "```text",
    "EMP2026/",
    "  Week_01/<track>/weekly/runs/...",
    "  Week_02/<track>/weekly/runs/...",
    "  Project_Major/<track>/project/runs/...",
    "  profile.json",
    "  _ledger/<run_id>.json",
    "  README.md",
    "```",
    "",
    "Sync is additive: new runs are created; existing files are not deleted.",
    "",
    sprintf("Latest sync: `%s` (run `%s`)", git_path, run_id),
    sep = "\n"
  )
  write_text(gsub("\\\\", "/", readme_rel), readme)

  msg <- if (nzchar(trimws(as.character(commit_message %||% "")))) {
    trimws(as.character(commit_message))
  } else {
    sprintf(
      "[EMP] sync %s/%s/%s (%s) v%s run %s",
      week_dir, track_folder, type_dir,
      assignment$title %||% assignment$id,
      emp_version, run_id
    )
  }

  list(
    staging = staging,
    files = files,
    run_id = run_id,
    base_rel = base_rel,
    git_path = git_path,
    week_dir = week_dir,
    type_dir = type_dir,
    emp_version = emp_version,
    commit_message = msg,
    n_files = length(files)
  )
}

.github_push_files <- function(owner, repo, branch, token, files, commit_message) {
  if (!length(files)) stop("没有可同步的文件。请先完成分析或选择包含教学报告的作业。")

  # Additive merge: always build on the current branch tree so existing
  # files/folders are kept. We only add/update paths present in `files`.
  ref <- .github_api("GET", sprintf("/repos/%s/%s/git/ref/heads/%s", owner, repo, utils::URLencode(branch, reserved = TRUE)), token)
  parent_sha <- NULL
  base_tree <- NULL
  if (ref$status == 200) {
    parent_sha <- ref$body$object$sha
    commit <- .github_api("GET", sprintf("/repos/%s/%s/git/commits/%s", owner, repo, parent_sha), token)
    if (commit$status < 200 || commit$status >= 300) {
      stop(sprintf("无法读取分支提交：%s", commit$body$message %||% commit$raw))
    }
    base_tree <- commit$body$tree$sha
  } else if (ref$status == 404) {
    # Branch missing — first commit will create folders/files from scratch.
    parent_sha <- NULL
    base_tree <- NULL
  } else {
    stop(sprintf("无法读取分支 %s：%s", branch, ref$body$message %||% ref$raw))
  }

  tree_items <- list()
  for (f in files) {
    raw <- readBin(f$abs, "raw", file.info(f$abs)$size)
    if (!length(raw)) next
    is_text <- grepl("\\.(csv|json|md|txt|tsv|html|r|R)$", f$path, ignore.case = TRUE)
    if (is_text) {
      content <- rawToChar(raw)
      Encoding(content) <- "UTF-8"
      blob_body <- list(content = content, encoding = "utf-8")
    } else {
      blob_body <- list(content = openssl::base64_encode(raw), encoding = "base64")
    }
    blob <- .github_api("POST", sprintf("/repos/%s/%s/git/blobs", owner, repo), token, blob_body)
    if (blob$status < 200 || blob$status >= 300) {
      stop(sprintf("创建 blob 失败 (%s)：%s", f$path, blob$body$message %||% blob$raw))
    }
    tree_items[[length(tree_items) + 1L]] <- list(
      path = gsub("\\\\", "/", f$path),
      mode = "100644",
      type = "blob",
      sha = blob$body$sha
    )
  }
  if (!length(tree_items)) stop("没有有效文件可提交。")

  tree_body <- list(tree = tree_items)
  # Critical: base_tree keeps all untouched paths (no wipe of existing repo content).
  if (!is.null(base_tree)) tree_body$base_tree <- base_tree
  tree <- .github_api("POST", sprintf("/repos/%s/%s/git/trees", owner, repo), token, tree_body)
  if (tree$status < 200 || tree$status >= 300) {
    stop(sprintf("创建 tree 失败：%s", tree$body$message %||% tree$raw))
  }

  commit_body <- list(
    message = commit_message,
    tree = tree$body$sha
  )
  if (!is.null(parent_sha)) commit_body$parents <- list(parent_sha)
  commit <- .github_api("POST", sprintf("/repos/%s/%s/git/commits", owner, repo), token, commit_body)
  if (commit$status < 200 || commit$status >= 300) {
    stop(sprintf("创建 commit 失败：%s", commit$body$message %||% commit$raw))
  }
  new_sha <- commit$body$sha

  if (is.null(parent_sha)) {
    created <- .github_api(
      "POST", sprintf("/repos/%s/%s/git/refs", owner, repo), token,
      list(ref = paste0("refs/heads/", branch), sha = new_sha)
    )
    if (created$status < 200 || created$status >= 300) {
      upd <- .github_api(
        "PATCH", sprintf("/repos/%s/%s/git/refs/heads/%s", owner, repo, utils::URLencode(branch, reserved = TRUE)),
        token, list(sha = new_sha)
      )
      if (upd$status < 200 || upd$status >= 300) {
        stop(sprintf("无法写入分支：%s", created$body$message %||% created$raw))
      }
    }
  } else {
    upd <- .github_api(
      "PATCH",
      sprintf("/repos/%s/%s/git/refs/heads/%s", owner, repo, utils::URLencode(branch, reserved = TRUE)),
      token,
      list(sha = new_sha)
    )
    if (upd$status < 200 || upd$status >= 300) {
      stop(sprintf("更新分支失败：%s", upd$body$message %||% upd$raw))
    }
  }

  list(
    commit_sha = new_sha,
    html_url = commit$body$html_url %||% sprintf("https://github.com/%s/%s/commit/%s", owner, repo, new_sha),
    branch = branch,
    merge_mode = if (is.null(base_tree)) "create" else "additive"
  )
}

.github_append_sync_log <- function(student_id, entry) {
  path <- .github_sync_log_path(student_id)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  line <- jsonlite::toJSON(entry, auto_unbox = TRUE, null = "null")
  cat(line, "\n", file = path, append = TRUE, sep = "")
}

github_list_syncs <- function(identity, limit = 30L) {
  path <- .github_sync_log_path(identity$student_id)
  if (!file.exists(path)) return(list(success = TRUE, syncs = list()))
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  lines <- lines[nzchar(lines)]
  if (!length(lines)) return(list(success = TRUE, syncs = list()))
  items <- lapply(rev(tail(lines, as.integer(limit))), function(ln) {
    tryCatch(jsonlite::fromJSON(ln, simplifyVector = FALSE), error = function(e) NULL)
  })
  items <- Filter(Negate(is.null), items)
  list(success = TRUE, syncs = items)
}

github_sync_assignment <- function(identity, track_id, assignment_id, session_id = NULL,
                                   experiment = NULL, include_rds = FALSE, commit_message = NULL,
                                   owner_id = NULL, custom_track_name = NULL,
                                   custom_assignment_title = NULL,
                                   allow_partial = FALSE) {
  assignment <- github_get_assignment(
    track_id, assignment_id,
    custom_track_name = custom_track_name,
    custom_assignment_title = custom_assignment_title
  )
  profile <- identity$profile
  gh <- profile$github %||% list()
  if (!isTRUE(gh$bound)) stop("请先绑定 GitHub 仓库与 Token。")
  token <- .github_get_pat(profile)
  owner <- gh$owner
  repo <- gh$repo
  branch <- gh$branch %||% "main"

  if (nzchar(session_id %||% "") && exists("emp_assert_session_owner", mode = "function")) {
    principal <- owner_id %||% "local"
    emp_assert_session_owner(session_id, principal)
  }

  active_jobs <- .github_session_active_jobs(session_id, owner_id %||% "local")
  partial <- FALSE
  if (length(active_jobs) > 0L) {
    if (!isTRUE(allow_partial)) {
      kinds <- unique(vapply(active_jobs, function(j) as.character(j$kind %||% j$status %||% "job"), character(1)))
      stop(sprintf(
        "Homework sync blocked: analysis job is still running (%s). Wait for it to finish, then sync again.",
        paste(kinds, collapse = ", ")
      ))
    }
    partial <- TRUE
  }

  bundle <- .github_build_run_files(
    identity = identity,
    assignment = assignment,
    session_id = session_id %||% "",
    experiment = experiment,
    include_rds = isTRUE(include_rds),
    commit_message = commit_message,
    github_meta = list(
      github_login = gh$github_login %||% NULL,
      github_repo = sprintf("%s/%s", owner, repo),
      github_branch = branch,
      github_html_url = sprintf("https://github.com/%s/%s", owner, repo)
    )
  )
  on.exit(unlink(bundle$staging, recursive = TRUE, force = TRUE), add = TRUE)

  push <- .github_push_files(owner, repo, branch, token, bundle$files, bundle$commit_message)

  entry <- list(
    synced_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    student_id = identity$student_id,
    emp_version = bundle$emp_version %||% .github_emp_version(),
    track_id = assignment$track_id,
    track_key = assignment$track_key %||% track_id,
    track_title = assignment$track_title,
    week_dir = bundle$week_dir,
    assignment_type = bundle$type_dir,
    assignment_id = assignment$id,
    assignment_title = assignment$title,
    git_path = bundle$git_path %||% bundle$base_rel,
    run_id = bundle$run_id,
    n_files = bundle$n_files,
    commit_sha = push$commit_sha,
    html_url = push$html_url,
    branch = push$branch,
    session_id = session_id,
    repo = sprintf("%s/%s", owner, repo),
    github_login = gh$github_login %||% NULL
  )
  entry$partial <- isTRUE(partial)
  .github_append_sync_log(identity$student_id, entry)

  msg <- sprintf(
    "已同步到 %s/%s → `%s`（%d 个文件，%s，v%s）",
    owner, repo,
    bundle$git_path %||% bundle$base_rel,
    bundle$n_files,
    if (identical(push$merge_mode, "create")) "新建" else "增量写入",
    bundle$emp_version %||% .github_emp_version()
  )
  if (isTRUE(partial)) {
    msg <- paste0(msg, "（部分同步：仍有分析任务在运行，仅包含已完成的结果）")
  }

  list(
    success = TRUE,
    sync = entry,
    partial = isTRUE(partial),
    path = bundle$base_rel,
    git_path = bundle$git_path %||% bundle$base_rel,
    merge_mode = push$merge_mode %||% "additive",
    message = msg
  )
}

# ── Plumber wrappers ──────────────────────────────────────

plumber_github_assignments_get <- function(res) {
  safe_api({ github_list_assignments() }, res)
}

plumber_github_register_post <- function(req, res) {
  safe_api({
    b <- emp_json_request_body(req)
    github_register_student(
      student_id = b$student_id,
      password = b$password,
      display_name = b$display_name
    )
  }, res)
}

plumber_github_login_post <- function(req, res) {
  safe_api({
    b <- emp_json_request_body(req)
    github_login_student(
      student_id = b$student_id,
      password = b$password,
      display_name = b$display_name
    )
  }, res)
}

plumber_github_logout_post <- function(req, res) {
  safe_api({
    token <- trimws(as.character(
      req$HTTP_X_STUDENT_TOKEN %||% req$headers[["x-student-token"]] %||% ""
    ))
    if (!nzchar(token)) {
      b <- emp_json_request_body(req)
      token <- trimws(as.character(b$student_token %||% ""))
    }
    if (!nzchar(token)) stop("缺少 student token。")
    github_logout_student(token)
  }, res)
}

plumber_github_status_get <- function(req, res) {
  safe_api({
    identity <- .github_identity_from_req(req)
    github_status(identity)
  }, res)
}

plumber_github_ensure_class_repo_post <- function(req, res) {
  safe_api({
    identity <- .github_identity_from_req(req)
    github_ensure_class_repo(identity)
  }, res)
}

plumber_github_bind_post <- function(req, res) {
  safe_api({
    identity <- .github_identity_from_req(req)
    b <- emp_json_request_body(req)
    github_bind_repo(
      identity,
      repo_url = b$repo_url,
      github_token = b$github_token,
      branch = b$branch
    )
  }, res)
}

plumber_github_unbind_post <- function(req, res) {
  safe_api({
    identity <- .github_identity_from_req(req)
    github_unbind_repo(identity)
  }, res)
}

plumber_github_sync_post <- function(req, res) {
  safe_api({
    identity <- .github_identity_from_req(req)
    b <- emp_json_request_body(req)
    github_sync_assignment(
      identity,
      track_id = b$track_id,
      assignment_id = b$assignment_id,
      session_id = b$session_id,
      experiment = b$experiment,
      include_rds = isTRUE(b$include_rds),
      commit_message = b$commit_message,
      owner_id = emp_request_principal(req),
      custom_track_name = b$custom_track_name,
      custom_assignment_title = b$custom_assignment_title,
      allow_partial = isTRUE(b$allow_partial)
    )
  }, res)
}

plumber_github_syncs_get <- function(req, res) {
  safe_api({
    identity <- .github_identity_from_req(req)
    github_list_syncs(identity)
  }, res)
}
