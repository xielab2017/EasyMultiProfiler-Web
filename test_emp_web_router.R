#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# test_emp_web_router.R — functional test for EasyMultiProfiler-Web
#
# Drives the plumber router directly through its Rook interface (pr$call()),
# so every request goes through the real filter chain, the real endpoint
# handlers and the real serializers — status codes, headers and JSON bodies
# are the ones a browser would receive. No listening socket is needed, which
# means this runs in CI, in a container, and in environments that forbid
# binding a port.
#
#   Rscript test_emp_web_router.R [--repo <path>] [--out report.csv]
#
# Environment:
#   EMP_WEB_REPO   repository root (default: current directory)
#   R_LIBS_USER    library holding EasyMultiProfiler and its dependencies
#
# Exits non-zero if any check fails.
# ---------------------------------------------------------------------------

args <- commandArgs(TRUE)
getarg <- function(flag, default) {
  i <- match(flag, args)
  if (!is.na(i) && length(args) > i) args[[i + 1L]] else default
}
repo <- normalizePath(getarg("--repo", Sys.getenv("EMP_WEB_REPO", unset = getwd())), mustWork = TRUE)
out_path <- getarg("--out", "router_test_report.csv")

state <- file.path(tempdir(), paste0("emp-router-", as.integer(Sys.time())))
for (d in c("sessions", "jobs", "projects")) dir.create(file.path(state, d), recursive = TRUE, showWarnings = FALSE)
Sys.setenv(EMP_SESSION_DIR = file.path(state, "sessions"),
           EMP_JOB_DIR     = file.path(state, "jobs"),
           EMP_PROJECT_DIR = file.path(state, "projects"),
           API_HOST        = "127.0.0.1",
           BACKEND_DIR     = file.path(repo, "webapp", "backend"))
Sys.unsetenv("EMP_ENABLE_USER_R")

suppressMessages(suppressWarnings({ library(plumber); library(jsonlite) }))
pr <- suppressMessages(suppressWarnings(plumber::plumb(file.path(repo, "webapp", "backend", "plumber.R"))))

# ---- Rook request construction -------------------------------------------
mk <- function(method, path, body = NULL, headers = list(), query = "") {
  env <- new.env(parent = emptyenv())
  env$REQUEST_METHOD <- method; env$PATH_INFO <- path; env$QUERY_STRING <- query
  env$SCRIPT_NAME <- ""; env$SERVER_NAME <- "127.0.0.1"; env$SERVER_PORT <- "8000"
  env$HTTP_HOST <- "127.0.0.1:8000"; env$REMOTE_ADDR <- "127.0.0.1"
  b <- if (is.null(body)) "" else if (is.character(body)) body else
       as.character(jsonlite::toJSON(body, auto_unbox = TRUE, null = "null"))
  env$CONTENT_TYPE <- "application/json"
  env$CONTENT_LENGTH <- as.character(nchar(b, type = "bytes"))
  env[["rook.input"]] <- list(
    read_lines = function(n = -1L) strsplit(b, "\n", fixed = TRUE)[[1]],
    read = function(l = -1L) charToRaw(b),
    rewind = function() invisible(NULL))
  for (nm in names(headers)) env[[paste0("HTTP_", toupper(gsub("-", "_", nm)))]] <- headers[[nm]]
  env
}

req <- function(method, path, body = NULL, headers = list(), query = "") {
  t0 <- Sys.time()
  r <- tryCatch(pr$call(mk(method, path, body, headers, query)),
                error = function(e) list(status = -1L, headers = list(), body = conditionMessage(e)))
  el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  raw_body <- if (is.raw(r$body)) rawToChar(r$body) else as.character(r$body %||% "")
  parsed <- tryCatch(jsonlite::fromJSON(raw_body, simplifyVector = TRUE), error = function(e) NULL)
  list(status = r$status, ctype = r$headers[["Content-Type"]] %||% NA_character_,
       raw = raw_body, json = parsed, elapsed = el)
}
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

# ---- assertions -----------------------------------------------------------
rows <- list(); pass <- 0L; fail <- 0L
chk <- function(area, name, cond, detail = "", elapsed = NA_real_) {
  ok <- isTRUE(cond)
  if (ok) pass <<- pass + 1L else fail <<- fail + 1L
  rows[[length(rows) + 1L]] <<- data.frame(
    area = area, check = name, status = if (ok) "pass" else "fail",
    detail = substr(gsub("[\r\n]+", " ", as.character(detail)), 1, 240),
    wall_s = round(elapsed, 3), stringsAsFactors = FALSE)
  cat(if (ok) "PASS " else "FAIL ", sprintf("%-9s %-54s", area, name),
      if (nzchar(detail)) paste("|", substr(detail, 1, 110)) else "", "\n")
}

# ---- 1. service and catalogue --------------------------------------------
r <- req("GET", "/api/health")
chk("service", "GET /api/health returns 200 and a version",
    r$status == 200 && identical(r$json$version, "9.0.4"), r$raw, r$elapsed)
r <- req("GET", "/api/demo_datasets")
n_demo <- if (is.data.frame(r$json$datasets)) nrow(r$json$datasets) else length(r$json$datasets)
chk("service", "GET /api/demo_datasets lists the bundled datasets",
    r$status == 200 && n_demo >= 3, paste(n_demo, "datasets"), r$elapsed)

# ---- 2. session and import ------------------------------------------------
r <- req("POST", "/api/session")
sid <- r$json$session_id %||% NA_character_
chk("import", "a session can be created over the router",
    !is.na(sid) && grepl("^[A-Za-z0-9]{24}$", sid), sid %||% r$raw, r$elapsed)

r <- req("POST", "/api/import/demo", list(session_id = sid, dataset_id = "m16s_course"))
exp_name <- r$json$experiment %||% "m16s_course"
chk("import", "POST /api/import/demo loads the 16S demo",
    r$status == 200 && isTRUE(r$json$success), paste(exp_name, r$raw_short <- substr(r$raw, 1, 80)), r$elapsed)

# ---- 3. prepare: the D1/D2 path that could not succeed before -------------
r <- req("POST", "/api/prepare/collapse",
         list(session_id = sid, experiment = exp_name, taxa_level = "Genus"))
chk("prepare", "POST /api/prepare/collapse to Genus succeeds (D1/D2)",
    r$status == 200 && isTRUE(r$json$success), substr(r$raw, 1, 120), r$elapsed)
r <- req("POST", "/api/prepare/collapse",
         list(session_id = sid, experiment = exp_name, taxa_level = "Kingdom"))
chk("prepare", "collapse accepts the 'Kingdom' spelling (C9)",
    r$status == 200 && isTRUE(r$json$success), substr(r$raw, 1, 120), r$elapsed)
r <- req("POST", "/api/prepare/collapse",
         list(session_id = sid, experiment = exp_name, taxa_level = "Banana"))
chk("prepare", "an unknown rank is refused with a usable message",
    r$status >= 400 || isFALSE(r$json$success), substr(r$raw, 1, 150), r$elapsed)

for (m in c("zero", "min", "mean")) {
  r <- req("POST", "/api/prepare/impute", list(session_id = sid, experiment = exp_name, method = m))
  chk("prepare", sprintf("impute '%s' runs and reports what executed (N1)", m),
      r$status == 200 && isTRUE(r$json$success) &&
        identical(as.character(r$json$executed_method %||% r$json$method), m),
      substr(r$raw, 1, 120), r$elapsed)
}
r <- req("POST", "/api/prepare/impute", list(session_id = sid, experiment = exp_name, method = "banana"))
chk("prepare", "an unknown imputation method is refused (N1)",
    r$status >= 400 || isFALSE(r$json$success), substr(r$raw, 1, 150), r$elapsed)

# ---- 4. analyse -----------------------------------------------------------
# A fresh session, so the analysis block is not affected by the rank collapses above.
r <- req("POST", "/api/session")
sid2 <- r$json$session_id
stopifnot(!is.null(sid2), !identical(sid2, sid))
r <- req("POST", "/api/import/demo", list(session_id = sid2, dataset_id = "m16s_course"))
exp2 <- r$json$experiment %||% "m16s_course"
r <- req("POST", "/api/prepare/collapse", list(session_id = sid2, experiment = exp2, taxa_level = "Genus"))
chk("analyze", "analysis session prepared at genus level",
    r$status == 200 && identical(r$json$n_features, 289L), substr(r$raw, 1, 110), r$elapsed)

r <- req("POST", "/api/analyze/alpha", list(session_id = sid2, experiment = exp2))
chk("analyze", "alpha diversity returns a table", r$status == 200 && isTRUE(r$json$success),
    substr(r$raw, 1, 90), r$elapsed)
r <- req("POST", "/api/analyze/dimension", list(session_id = sid2, experiment = exp2, method = "PCoA"))
chk("analyze", "PCoA returns coordinates", r$status == 200 && isTRUE(r$json$success),
    paste(r$json$columns %||% "", collapse = ","), r$elapsed)
r <- req("POST", "/api/analyze/dimension", list(session_id = sid2, experiment = exp2, method = "tSNE"))
chk("analyze", "t-SNE is refused, not answered with UMAP (C1)",
    (r$status >= 400 || isFALSE(r$json$success)) && grepl("not implemented", r$raw, ignore.case = TRUE),
    substr(r$raw, 1, 150), r$elapsed)
r <- req("POST", "/api/analyze/marker",
         list(session_id = sid2, experiment = exp2, method = "LEfSe", group_var = "Group"))
chk("analyze", "LEfSe is refused, not silently random forest (C3)",
    (r$status >= 400 || isFALSE(r$json$success)) && grepl("not implemented", r$raw, ignore.case = TRUE),
    substr(r$raw, 1, 150), r$elapsed)
r <- req("POST", "/api/analyze/cluster",
         list(session_id = sid2, experiment = exp2, method = "banana", k = 3))
chk("analyze", "an unknown clustering method is refused (C4)",
    (r$status >= 400 || isFALSE(r$json$success)) && grepl("Unsupported", r$raw),
    substr(r$raw, 1, 150), r$elapsed)
r <- req("POST", "/api/analyze/differential",
         list(session_id = sid2, experiment = exp2, method = "wilcox.test", group_var = "Group",
              ref_group = "UC_before", test_group = "UC_after", subset_two_groups = TRUE))
chk("analyze", "differential analysis runs and declares its method (N4/C5)",
    r$status == 200 && isTRUE(r$json$success) && (r$json$n_rows %||% 0) > 0,
    sprintf("rows=%s requested=%s executed=%s", r$json$n_rows %||% "-",
            r$json$requested_method %||% "-", r$json$executed_method %||% "-"), r$elapsed)

# ---- 5. security ----------------------------------------------------------
r <- req("POST", "/api/user_r/run", list(session_id = sid, code = "1+1"))
chk("security", "caller-supplied R is disabled by default (S8)",
    r$status == 403, substr(r$raw, 1, 120), r$elapsed)
r <- req("POST", "/api/workflows/chipseq/bams/scan_folder", list(session_id = sid, folder_path = "/etc"))
chk("security", "a server folder outside the allow-list is refused (S3)",
    (r$status >= 400 || isFALSE(r$json$success)) &&
      grepl("EMP_ALLOWED_ROOTS|outside|disabled", r$raw), substr(r$raw, 1, 150), r$elapsed)
r <- req("POST", "/api/analyze/alpha", list(session_id = "AAAAAAAAAAAAAAAAAAAAAAAA", experiment = exp_name))
chk("security", "an unknown session id is rejected",
    r$status >= 400 || isFALSE(r$json$success), substr(r$raw, 1, 120), r$elapsed)

# ---- 6. error contract on the binary/download routes (R7) -----------------
r <- req("GET", "/api/export/session_rds", query = paste0("session_id=", "AAAAAAAAAAAAAAAAAAAAAAAA"))
chk("errors", "a failing download answers JSON, not a bare string (R7)",
    r$status >= 400 && grepl("json", tolower(r$ctype %||% "")) && !is.null(r$json),
    paste(r$status, r$ctype, substr(r$raw, 1, 80)), r$elapsed)

df <- do.call(rbind, rows)
utils::write.csv(df, out_path, row.names = FALSE)
cat(sprintf("\n%d checks: %d pass, %d fail (%.0f%%)\nreport: %s\n",
            nrow(df), pass, fail, 100 * pass / max(1L, nrow(df)), out_path))
unlink(state, recursive = TRUE)
if (fail > 0L) quit(status = 1L)
