# repro_report.R - EMP Web v9.1.0 analysis upgrade D.
#
# Reproducibility manifest + report for an analysis run: EMP version,
# platform, R version, a small fixed set of package versions, the UI
# locale, and the R session info captured as text. Values are recorded
# from the live session only; a package that is not installed is
# recorded as NA, never invented.

#' Build a reproducibility manifest for the current session.
#' @param extra Named list of caller-supplied entries (run parameters,
#'   input checksums, ...) merged into the manifest.
#' @param locale UI locale active for the run (used for report titles).
emp_repro_manifest <- function(extra = list(), locale = "en") {
  pkg_versions <- vapply(
    c("ggplot2", "DESeq2", "limma"),
    function(pkg) {
      v <- tryCatch(as.character(utils::packageVersion(pkg)),
                    error = function(e) NA_character_)
      if (length(v) == 0) NA_character_ else v
    },
    character(1)
  )
  session_lines <- tryCatch(
    utils::capture.output(utils::sessionInfo()),
    error = function(e) character(0)
  )
  platform <- if (exists("emp_platform_info", inherits = TRUE)) {
    tryCatch(emp_platform_info(), error = function(e) list())
  } else {
    list()
  }
  manifest <- list(
    emp_version = "9.1.0",
    created = format(Sys.time(), tz = "UTC", format = "%Y-%m-%dT%H:%M:%SZ"),
    platform = platform,
    r_version = as.character(getRversion()),
    packages = as.list(pkg_versions),
    locale = locale,
    session = session_lines
  )
  if (length(extra) > 0) {
    for (nm in names(extra)) manifest[[nm]] <- extra[[nm]]
  }
  manifest
}

#' Write manifest.json and a localized REPORT.md into `dir`.
#' @return list(json = <path>, report = <path>) (invisibly on failure of
#'   the JSON writer, the markdown report is still attempted).
emp_write_repro_report <- function(dir, manifest, locale = "en") {
  if (!dir.exists(dir)) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  }
  json_path <- file.path(dir, "manifest.json")
  json_ok <- tryCatch({
    json <- jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE,
                             na = "null")
    writeLines(json, json_path, useBytes = TRUE)
    TRUE
  }, error = function(e) FALSE)

  title <- if (exists("emp_msg", inherits = TRUE)) {
    emp_msg(locale, "report.title")
  } else {
    "Reproducible Analysis Report"
  }
  generated <- if (exists("emp_msg", inherits = TRUE)) {
    emp_msg(locale, "report.generated_with")
  } else {
    "Generated with EasyMultiProfiler Web"
  }
  pkg <- manifest$packages
  pkg_line <- function(name) {
    v <- pkg[[name]]
    if (is.null(v) || length(v) == 0 || is.na(v)) "not installed" else v
  }
  plat <- manifest$platform
  lines <- c(
    paste0("# ", title),
    "",
    paste0(generated, " v", manifest$emp_version, " - ", manifest$created),
    "",
    "## Version",
    "",
    paste0("- EMP Web: ", manifest$emp_version),
    "",
    "## Platform",
    "",
    paste0("- OS: ", ifelse(is.null(plat$os), "unknown", plat$os)),
    paste0("- Arch: ", ifelse(is.null(plat$arch), "unknown", plat$arch)),
    paste0("- Detail: ", ifelse(is.null(plat$os_detail), "", plat$os_detail)),
    "",
    "## R",
    "",
    paste0("- R version: ", manifest$r_version),
    "",
    "## Packages",
    "",
    paste0("- ggplot2: ", pkg_line("ggplot2")),
    paste0("- DESeq2: ", pkg_line("DESeq2")),
    paste0("- limma: ", pkg_line("limma")),
    "",
    "## Notes",
    "",
    "- Versions were recorded from the live R session at run time.",
    "- Packages listed as not installed were absent from that session.",
    "- Full session info is in manifest.json (field: session)."
  )
  report_path <- file.path(dir, "REPORT.md")
  writeLines(lines, report_path, useBytes = TRUE)
  list(json = if (json_ok) json_path else NULL, report = report_path)
}
