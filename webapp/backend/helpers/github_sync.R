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
  assignments <- c(weeks, projects)
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

github_get_assignment <- function(track_id, assignment_id,
                                  custom_track_name = NULL,
                                  custom_assignment_title = NULL) {
  data <- github_load_assignments()
  track <- NULL
  for (tr in data$tracks %||% list()) {
    if (identical(tr$id, track_id)) { track = tr; break }
  }
  if (is.null(track)) stop(sprintf("Unknown track: %s", track_id))

  expanded <- .github_expand_track(track, data)
  hit <- NULL
  for (a in expanded$assignments %||% list()) {
    if (identical(a$id, assignment_id)) { hit <- a; break }
  }
  if (is.null(hit)) stop(sprintf("Unknown assignment: %s / %s", track_id, assignment_id))

  # Folder / display overrides for customize track
  track_folder <- track$id
  track_title <- track$title %||% track$id
  if (isTRUE(track$custom)) {
    cname <- trimws(as.character(custom_track_name %||% ""))
    if (!nzchar(cname)) stop("自定义轨道请填写轨道名称。")
    track_title <- cname
    track_folder <- .github_slugify(cname, fallback = "customize")
  }

  title <- hit$title
  ctitle <- trimws(as.character(custom_assignment_title %||% ""))
  if (identical(hit$type, "custom") || identical(hit$id, "assignment_custom")) {
    if (!nzchar(ctitle)) stop("自定义作业请填写作业标题。")
    title <- ctitle
  } else if (nzchar(ctitle)) {
    # Optional student override for week / project title
    title <- ctitle
  }

  assignment_folder <- hit$id
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
    track_key = track$id,
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

github_register_student <- function(student_id, password, display_name = NULL) {
  student_id <- trimws(as.character(student_id %||% ""))
  password <- as.character(password %||% "")
  if (!.github_student_id_ok(student_id)) {
    stop("学号格式无效：3–32 位字母数字，可含 . _ -")
  }
  if (nchar(password, type = "chars") < 8L) stop("口令至少 8 位。")
  path <- .github_profile_path(student_id)
  if (file.exists(path)) stop("该学号已注册，请直接登录。")
  hashed <- .github_hash_password(password)
  profile <- list(
    student_id = student_id,
    display_name = if (nzchar(trimws(as.character(display_name %||% "")))) {
      trimws(as.character(display_name))
    } else student_id,
    password_hash = hashed$hash,
    password_salt = hashed$salt,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    github = list(bound = FALSE)
  )
  .github_save_profile(profile)
  github_login_student(student_id, password)
}

github_login_student <- function(student_id, password) {
  student_id <- trimws(as.character(student_id %||% ""))
  password <- as.character(password %||% "")
  profile <- tryCatch(.github_load_profile(student_id), error = function(e) NULL)
  if (is.null(profile) || !.github_check_password(password, profile$password_hash, profile$password_salt)) {
    stop("学号或口令错误。")
  }
  raw_token <- .github_new_session_token()
  th <- .github_token_hash(raw_token)
  .github_write_json(.github_session_path(th), list(
    student_id = student_id,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    expires_at = format(Sys.time() + 60 * 60 * 24 * 30, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  ))
  list(
    success = TRUE,
    student_token = raw_token,
    student = .github_public_profile(profile)
  )
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
  list(success = TRUE, student = .github_public_profile(identity$profile))
}

.github_get_pat <- function(profile) {
  gh <- profile$github %||% list()
  if (!isTRUE(gh$bound)) stop("尚未绑定 GitHub 仓库。")
  .github_decrypt(gh$token_ciphertext, gh$token_iv)
}

.github_run_id <- function() {
  format(Sys.time(), "%Y-%m-%dT%H-%M-%SZ", tz = "UTC")
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

.github_build_run_files <- function(identity, assignment, session_id, experiment = NULL,
                                    include_rds = FALSE, commit_message = NULL) {
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

  repo_root <- assignment$repo_root %||% EMP_COURSE_CODE
  track_folder <- assignment$track_id %||% "track"
  asg_folder <- assignment$folder_id %||% assignment$id %||% "assignment"
  base_rel <- file.path(
    repo_root, "assignments", track_folder, asg_folder, "runs", run_id
  )
  base_rel <- gsub("\\\\", "/", base_rel)

  # manifest
  if ("manifest" %in% include) {
    man <- list(
      course_code = assignment$course_code %||% EMP_COURSE_CODE,
      track_id = track_folder,
      track_key = assignment$track_key %||% track_folder,
      track_title = assignment$track_title %||% track_folder,
      assignment_id = assignment$id,
      assignment_folder = asg_folder,
      assignment_title = assignment$title,
      week = assignment$week,
      type = assignment$type %||% "weekly",
      case_id = assignment$case_id,
      task_ids = assignment$task_ids %||% list(),
      student_id = identity$student_id,
      display_name = identity$profile$display_name %||% identity$student_id,
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

  # analysis exports
  if (nzchar(session_id %||% "") && session_exists(session_id)) {
    exps <- tryCatch(list_experiments(session_id), error = function(e) character())
    if (nzchar(experiment %||% "")) {
      if (!(experiment %in% exps)) exps <- c(experiment, exps)
    }
    exps <- unique(as.character(exps))
    for (exp in exps) {
      if (!nzchar(exp)) next
      if ("assay" %in% include) {
        tryCatch({
          empt <- load_empt(session_id, exp)
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
          empt <- load_empt(session_id, exp)
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
          if (.github_try_export_result(session_id, exp, an, p)) {
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
      plots_dir <- file.path(session_path(session_id), "plots")
      if (dir.exists(plots_dir)) {
        pdfs <- list.files(plots_dir, pattern = "\\.pdf$", full.names = TRUE)
        for (pdf in pdfs) {
          add_file(file.path(base_rel, "plots", basename(pdf)), pdf)
        }
      }
    }
    if (isTRUE(include_rds) || ("rds" %in% include)) {
      mae_p <- mae_path(session_id)
      if (file.exists(mae_p)) {
        add_file(file.path(base_rel, "session", "EMP_session.rds"), mae_p)
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

  # LATEST pointer + profile snapshot at course root
  latest_rel <- file.path(repo_root, "assignments", track_folder, asg_folder, "LATEST")
  write_text(gsub("\\\\", "/", latest_rel), run_id)

  profile_rel <- file.path(repo_root, "profile.json")
  profile_pub <- list(
    student_id = identity$student_id,
    display_name = identity$profile$display_name %||% identity$student_id,
    course_code = assignment$course_code %||% EMP_COURSE_CODE,
    updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
  p_prof <- file.path(staging, "profile.json")
  jsonlite::write_json(profile_pub, p_prof, auto_unbox = TRUE, pretty = TRUE)
  add_file(gsub("\\\\", "/", profile_rel), p_prof)

  readme_rel <- file.path(repo_root, "README.md")
  readme <- paste(
    sprintf("# %s Course Submissions", assignment$course_code %||% EMP_COURSE_CODE),
    "",
    sprintf("Student: **%s** (%s)", profile_pub$display_name, profile_pub$student_id),
    "",
    "Synced from EasyMultiProfiler Web. Each assignment keeps historical `runs/`.",
    "",
    sprintf(
      "Latest sync: `%s / %s` -> `%s`",
      track_folder, asg_folder, run_id
    ),
    sep = "\n"
  )
  write_text(gsub("\\\\", "/", readme_rel), readme)

  msg <- if (nzchar(trimws(as.character(commit_message %||% "")))) {
    trimws(as.character(commit_message))
  } else {
    sprintf(
      "[EMP] sync %s/%s (%s) run %s",
      track_folder, asg_folder,
      assignment$title %||% asg_folder, run_id
    )
  }

  list(
    staging = staging,
    files = files,
    run_id = run_id,
    base_rel = base_rel,
    commit_message = msg,
    n_files = length(files)
  )
}

.github_push_files <- function(owner, repo, branch, token, files, commit_message) {
  if (!length(files)) stop("没有可同步的文件。请先完成分析或选择包含教学报告的作业。")

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
  } else if (ref$status != 404) {
    stop(sprintf("无法读取分支 %s：%s", branch, ref$body$message %||% ref$raw))
  }

  tree_items <- list()
  for (f in files) {
    raw <- readBin(f$abs, "raw", file.info(f$abs)$size)
    # GitHub rejects empty blobs in some flows; skip empty files
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
    # create branch ref
    created <- .github_api(
      "POST", sprintf("/repos/%s/%s/git/refs", owner, repo), token,
      list(ref = paste0("refs/heads/", branch), sha = new_sha)
    )
    if (created$status < 200 || created$status >= 300) {
      # empty repo may need different flow — try update
      upd <- .github_api(
        "PATCH", sprintf("/repos/%s/%s/git/refs/heads/%s", owner, repo, utils::URLencode(branch, reserved = TRUE)),
        token, list(sha = new_sha, force = TRUE)
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
    branch = branch
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
                                   custom_assignment_title = NULL) {
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

  bundle <- .github_build_run_files(
    identity = identity,
    assignment = assignment,
    session_id = session_id %||% "",
    experiment = experiment,
    include_rds = isTRUE(include_rds),
    commit_message = commit_message
  )
  on.exit(unlink(bundle$staging, recursive = TRUE, force = TRUE), add = TRUE)

  push <- .github_push_files(owner, repo, branch, token, bundle$files, bundle$commit_message)

  entry <- list(
    synced_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    track_id = assignment$track_id,
    track_key = assignment$track_key %||% track_id,
    track_title = assignment$track_title,
    assignment_id = assignment$id,
    assignment_folder = assignment$folder_id %||% assignment$id,
    assignment_title = assignment$title,
    run_id = bundle$run_id,
    n_files = bundle$n_files,
    commit_sha = push$commit_sha,
    html_url = push$html_url,
    branch = push$branch,
    session_id = session_id,
    repo = sprintf("%s/%s", owner, repo)
  )
  .github_append_sync_log(identity$student_id, entry)

  list(
    success = TRUE,
    sync = entry,
    path = bundle$base_rel,
    message = sprintf("已同步到 %s/%s（%d 个文件）", owner, repo, bundle$n_files)
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
    github_login_student(student_id = b$student_id, password = b$password)
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
      custom_assignment_title = b$custom_assignment_title
    )
  }, res)
}

plumber_github_syncs_get <- function(req, res) {
  safe_api({
    identity <- .github_identity_from_req(req)
    github_list_syncs(identity)
  }, res)
}
