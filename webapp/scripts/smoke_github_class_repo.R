# Smoke: required display_name + optional class repository configuration.
# SKIP: live GitHub validation/push (no PAT is used).

`%||%` <- function(x, y) if (is.null(x)) y else x

backend <- Sys.getenv("BACKEND_DIR", unset = "")
stopifnot(nzchar(backend))
runtime_dir <- tempfile("emp-github-runtime-")
students_dir <- file.path(runtime_dir, "students")
dir.create(students_dir, recursive = TRUE)
Sys.setenv(
  EMP_DATA_DIR = runtime_dir,
  EMP_SESSION_DIR = file.path(runtime_dir, "sessions"),
  EMP_JOB_DIR = file.path(runtime_dir, "jobs"),
  EMP_PROJECT_DIR = file.path(runtime_dir, "projects"),
  EMP_STUDENTS_DIR = students_dir
)
Sys.unsetenv(c("EMP_CLASS_HOMEWORK_REPO", "EMP_CLASS_GITHUB_TOKEN"))
for (f in c(
  "helpers/storage.R", "helpers/utils.R", "helpers/auth.R",
  "helpers/session.R", "helpers/projects.R", "helpers/teaching.R",
  "helpers/github_sync.R"
)) {
  source(file.path(backend, f))
}

cfg <- github_class_config()
stopifnot(identical(cfg$class_homework_repo, ""))
stopifnot(is.null(cfg$owner), is.null(cfg$repo), isFALSE(cfg$configured))
stopifnot(isFALSE(cfg$has_class_token))
cat("OK blank_class_config\n")

Sys.setenv(EMP_CLASS_HOMEWORK_REPO = "https://github.com/example/course-work")
cfg_optional <- github_class_config()
stopifnot(isTRUE(cfg_optional$configured))
stopifnot(identical(cfg_optional$owner, "example"))
stopifnot(identical(cfg_optional$repo, "course-work"))
Sys.unsetenv("EMP_CLASS_HOMEWORK_REPO")
cat("OK optional_class_config\n")

err <- tryCatch(
  github_register_student("stu_smoke01", "password123", display_name = ""),
  error = function(e) conditionMessage(e)
)
stopifnot(is.character(err), grepl("姓名|显示名", err))
cat("OK empty_name_rejected:", err, "\n")

res <- github_register_student("stu_smoke01", "password123", display_name = "测试同学")
stopifnot(isTRUE(res$success), nzchar(res$student_token))
stopifnot(identical(res$student$display_name, "测试同学"))
stopifnot(identical(res$class_homework_repo, ""))
stopifnot(isTRUE(res$need_pat), !isTRUE(res$github_bound), !isTRUE(res$auto_bound))
cat("OK register_blank_repo\n")

res2 <- github_login_student("stu_smoke01", "password123")
stopifnot(isTRUE(res2$need_pat), identical(res2$class_homework_repo, ""))
cat("OK login_blank_repo\n")

res3 <- github_login_student("stu_smoke01", "password123", display_name = "新名字")
stopifnot(identical(res3$student$display_name, "新名字"))
cat("OK login_update_name\n")

id <- list(student_id = "stu_smoke01", profile = .github_load_profile("stu_smoke01"))
ens <- github_ensure_class_repo(id)
stopifnot(isTRUE(ens$need_pat), !isTRUE(ens$github_bound))
stopifnot(identical(ens$class_homework_repo, ""))
cat("OK ensure_blank_repo\n")

identity <- list(student_id = "stu_smoke01", profile = .github_load_profile("stu_smoke01"))
st <- github_status(identity)
stopifnot(identical(st$class_homework_repo, ""))
cat("OK status_blank_repo\n")

# Stub only the live GitHub/encryption edges and verify the submitted URL is used.
.github_validate_token_repo <- function(token, owner, repo) {
  list(login = "smoke-user", default_branch = "main")
}
.github_encrypt <- function(token) list(ciphertext = "test", iv = "test")
github_bind_repo(
  identity,
  "https://github.com/example/student-homework",
  "test-token"
)
bound_profile <- .github_load_profile("stu_smoke01")
stopifnot(identical(bound_profile$github$owner, "example"))
stopifnot(identical(bound_profile$github$repo, "student-homework"))
cat("OK bind_uses_submitted_repo\n")
cat("ALL_SMOKE_OK\n")
unlink(runtime_dir, recursive = TRUE, force = TRUE)
