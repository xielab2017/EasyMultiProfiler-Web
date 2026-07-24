# Smoke: required display_name + class homework repo ensure (no live GitHub PAT).
# SKIP: live GitHub push / connection.json when EMP_CLASS_GITHUB_TOKEN unset.

`%||%` <- function(x, y) if (is.null(x)) y else x

backend <- Sys.getenv("BACKEND_DIR", unset = "")
stopifnot(nzchar(backend))
for (f in c(
  "helpers/storage.R", "helpers/utils.R", "helpers/auth.R",
  "helpers/session.R", "helpers/projects.R", "helpers/teaching.R",
  "helpers/github_sync.R"
)) {
  source(file.path(backend, f))
}

cfg <- github_class_config()
stopifnot(identical(cfg$owner, "xielab2017"))
stopifnot(identical(cfg$repo, "Bioinformatics_homework_XieLiwei"))
stopifnot(isFALSE(cfg$has_class_token))
cat("OK class_config\n")

err <- tryCatch(
  github_register_student("stu_smoke01", "password123", display_name = ""),
  error = function(e) conditionMessage(e)
)
stopifnot(is.character(err), grepl("姓名|显示名", err))
cat("OK empty_name_rejected:", err, "\n")

res <- github_register_student("stu_smoke01", "password123", display_name = "测试同学")
stopifnot(isTRUE(res$success), nzchar(res$student_token))
stopifnot(identical(res$student$display_name, "测试同学"))
stopifnot(identical(res$class_homework_repo, cfg$class_homework_repo))
stopifnot(isTRUE(res$need_pat), !isTRUE(res$github_bound), !isTRUE(res$auto_bound))
cat("OK register_need_pat\n")

res2 <- github_login_student("stu_smoke01", "password123")
stopifnot(isTRUE(res2$need_pat), identical(res2$class_homework_repo, cfg$class_homework_repo))
cat("OK login_need_pat\n")

res3 <- github_login_student("stu_smoke01", "password123", display_name = "新名字")
stopifnot(identical(res3$student$display_name, "新名字"))
cat("OK login_update_name\n")

id <- list(student_id = "stu_smoke01", profile = .github_load_profile("stu_smoke01"))
ens <- github_ensure_class_repo(id)
stopifnot(isTRUE(ens$need_pat), !isTRUE(ens$github_bound))
cat("OK ensure_need_pat (SKIP live GitHub push — no EMP_CLASS_GITHUB_TOKEN)\n")

identity <- list(student_id = "stu_smoke01", profile = .github_load_profile("stu_smoke01"))
st <- github_status(identity)
stopifnot(identical(st$class_homework_repo, cfg$class_homework_repo))
cat("OK status_class_repo\n")
cat("ALL_SMOKE_OK\n")
