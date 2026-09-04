#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# test_emp_web_platform.R — platform-portability checks for EasyMultiProfiler-Web
#
# Dependency-light on purpose: needs only `jsonlite`. It does NOT load the
# EasyMultiProfiler engine, so it runs in ~10 seconds on a bare R install and is
# the right thing to run first on a new platform (Windows in particular).
#
# What it checks, all of it platform-sensitive:
#   1. every backend R source parses
#   2. the per-user data root resolves to the platform's own convention
#      (%LOCALAPPDATA% on Windows, Application Support on macOS, XDG on Linux)
#      and the teaching / evolution directories sit under it rather than /tmp
#   3. environment overrides still win over that default
#   4. allow-list path containment behaves with native separators and, on
#      Windows, case-insensitively
#   5. the session-ownership scan sees ids anywhere in a large request body
#   6. binary endpoints answer with JSON rather than a bare string
#
# Usage:
#   Rscript test_emp_web_platform.R [--repo <path>] [--out platform_report.csv]
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
getarg <- function(flag, default) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) default else args[[i + 1L]]
}
repo <- normalizePath(getarg("--repo", "."), winslash = "/", mustWork = TRUE)
out_path <- getarg("--out", "platform_report.csv")

H <- file.path(repo, "webapp", "backend", "helpers")
if (!dir.exists(H)) stop("Not an EasyMultiProfiler-Web checkout: ", H, " not found.")

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
rows <- list()
pass <- 0L; fail <- 0L
skip <- 0L
chk <- function(area, name, ok, detail = "", skip_reason = NULL) {
  # skip_reason turns a negative result into "skip" rather than "fail": used where the
  # environment, not the code, is what prevents the check (e.g. a sandbox with no home dir).
  st <- if (isTRUE(ok)) "pass" else if (!is.null(skip_reason)) "skip" else "fail"
  if (st == "pass") pass <<- pass + 1L else if (st == "skip") skip <<- skip + 1L else fail <<- fail + 1L
  cat(sprintf("%-5s %-9s %-56s %s\n", toupper(st), area, name,
              substr(gsub("[\r\n]+", " ", if (st == "skip") skip_reason else detail), 1, 90)))
  rows[[length(rows) + 1L]] <<- data.frame(
    area = area, check = name, status = st,
    detail = substr(if (st == "skip") skip_reason else detail, 1, 300), stringsAsFactors = FALSE)
}

os <- if (.Platform$OS.type == "windows") "windows" else
      if (identical(Sys.info()[["sysname"]], "Darwin")) "macos" else "linux"
cat(sprintf("platform: %s | R %s | %s\n\n", os, getRversion(), R.version$platform))

## 1 ---- every backend source parses -----------------------------------------
srcs <- c(list.files(H, pattern = "\\.R$", full.names = TRUE),
          file.path(repo, "webapp", "backend", c("plumber.R", "run_api.R")))
srcs <- srcs[file.exists(srcs)]
bad <- character()
for (f in srcs) {
  ok <- tryCatch({ parse(f); TRUE }, error = function(e) { bad <<- c(bad, basename(f)); FALSE })
}
chk("parse", sprintf("all %d backend R sources parse", length(srcs)), length(bad) == 0,
    if (length(bad)) paste(bad, collapse = ", ") else "")

## 2 ---- per-user data root ---------------------------------------------------
for (v in c("EMP_DATA_DIR", "EMP_TEACHING_DIR", "EMP_EVOLUTION_DIR")) Sys.unsetenv(v)
source(file.path(H, "storage.R"), keep.source = FALSE)
root <- .emp_platform_data_root()
expected <- switch(os,
  windows = Sys.getenv("LOCALAPPDATA", unset = path.expand("~/AppData/Local")),
  macos   = path.expand("~/Library/Application Support"),
  linux   = Sys.getenv("XDG_DATA_HOME", unset = file.path(path.expand("~"), ".local", "share")))
chk("paths", "data root follows the platform convention",
    startsWith(normalizePath(root, winslash = "/", mustWork = FALSE),
               normalizePath(expected, winslash = "/", mustWork = FALSE)), root)

source(file.path(H, "teaching.R"), keep.source = FALSE)
source(file.path(H, "user_evolution.R"), keep.source = FALSE)
chk("paths", "TEACHING_DIR is not under /tmp", !grepl("^/tmp", TEACHING_DIR), TEACHING_DIR)
chk("paths", "EVOLUTION_DIR is not under /tmp", !grepl("^/tmp", EVOLUTION_DIR), EVOLUTION_DIR)
chk("paths", "both sit under the per-user data root",
    startsWith(TEACHING_DIR, root) && startsWith(EVOLUTION_DIR, root),
    paste(TEACHING_DIR, EVOLUTION_DIR, sep = " | "))

td <- file.path(tempdir(), "emp_teach_override")
ed <- file.path(tempdir(), "emp_evo_override")
Sys.setenv(EMP_TEACHING_DIR = td, EMP_EVOLUTION_DIR = ed)
source(file.path(H, "teaching.R"), keep.source = FALSE)
source(file.path(H, "user_evolution.R"), keep.source = FALSE)
chk("paths", "environment overrides still win",
    identical(normalizePath(TEACHING_DIR, "/", FALSE), normalizePath(td, "/", FALSE)) &&
    identical(normalizePath(EVOLUTION_DIR, "/", FALSE), normalizePath(ed, "/", FALSE)),
    paste(TEACHING_DIR, EVOLUTION_DIR, sep = " | "))
Sys.unsetenv("EMP_TEACHING_DIR"); Sys.unsetenv("EMP_EVOLUTION_DIR")

## 3 ---- writability at the real location ------------------------------------
probe <- file.path(root, "platform_probe")
made <- suppressWarnings(tryCatch({
  dir.create(probe, recursive = TRUE, showWarnings = FALSE)
  f <- file.path(probe, "x.txt"); writeLines("ok", f)
  r <- identical(readLines(f, warn = FALSE), "ok"); unlink(probe, recursive = TRUE); r
}, error = function(e) FALSE, warning = function(w) FALSE))
parent_writable <- file.access(dirname(root), 2) == 0 || file.access(root, 2) == 0
chk("paths", "the data root is creatable and writable", made, root,
    skip_reason = if (!made && !parent_writable)
      paste("home directory is not writable in this environment:", root) else NULL)

## 4 ---- allow-list containment with native separators ------------------------
source(file.path(H, "utils.R"), keep.source = FALSE)
suppressWarnings(try(source(file.path(H, "auth.R"), keep.source = FALSE), silent = TRUE))
suppressWarnings(try(source(file.path(H, "agent_api.R"), keep.source = FALSE), silent = TRUE))
if (exists(".emp_is_within_root", mode = "function")) {
  base <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
  inside <- paste0(base, "/sub/file.csv")
  chk("allowlist", "a path inside the root is accepted", .emp_is_within_root(inside, base), inside)
  chk("allowlist", "a sibling with a shared prefix is rejected",
      !.emp_is_within_root(paste0(base, "_evil/x.csv"), base), paste0(base, "_evil/x.csv"))
  chk("allowlist", "a parent path is rejected",
      !.emp_is_within_root(dirname(base), base), dirname(base))
  if (os == "windows") {
    chk("allowlist", "Windows comparison is case-insensitive",
        .emp_is_within_root(toupper(inside), base), toupper(inside))
  }
} else {
  chk("allowlist", "containment helper is available", FALSE, ".emp_is_within_root not found")
}

## 5 ---- ownership scan over a large body -------------------------------------
if (exists("emp_scan_session_ids_raw", mode = "function")) {
  sid <- paste(sample(c(letters, LETTERS, 0:9), 24, replace = TRUE), collapse = "")
  body <- paste0('{"pad":"', strrep("x", 3e6), '","session_id":"', sid, '"}')
  t0 <- Sys.time()
  hit <- emp_scan_session_ids_raw(list(postBody = body))
  el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  chk("auth", "session id found at the far end of a 3 MB body", sid %in% hit,
      sprintf("%.2f s, %d match(es)", el, length(hit)))
} else {
  chk("auth", "ownership scan helper is available", FALSE, "emp_scan_session_ids_raw not found")
}

## 6 ---- binary endpoints answer JSON -----------------------------------------
if (exists("emp_binary_error", mode = "function") && requireNamespace("jsonlite", quietly = TRUE)) {
  res <- new.env(); res$status <- 200L
  raw_out <- emp_binary_error(res, simpleError("boom"))
  parsed <- tryCatch(jsonlite::fromJSON(rawToChar(raw_out)), error = function(e) NULL)
  chk("errors", "a failing download answers parseable JSON",
      is.raw(raw_out) && !is.null(parsed) && isFALSE(parsed$success) && grepl("boom", parsed$error),
      if (is.raw(raw_out)) rawToChar(raw_out) else "not raw")
} else {
  chk("errors", "binary error helper is available", FALSE, "emp_binary_error not found")
}

df <- do.call(rbind, rows)
utils::write.csv(df, out_path, row.names = FALSE)
cat(sprintf("\n%d checks: %d pass, %d fail, %d skip (%.0f%% of executed)\nplatform: %s\nreport: %s\n",
            nrow(df), pass, fail, skip, 100 * pass / max(1L, pass + fail), os, out_path))
if (fail > 0L) quit(status = 1L)
