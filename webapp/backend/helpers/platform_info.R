# platform_info.R - EMP Web v9.1.0 platform auto-detection (base R only).
#
# Backend counterpart of webapp/scripts/detect_platform.sh / .ps1: one
# shared contract for "which OS / architecture / R is this system on".

#' Detect the operating system family: "windows", "macos" or "linux".
emp_detect_os <- function() {
  if (identical(.Platform$OS.type, "windows")) return("windows")
  sys <- tryCatch(Sys.info()[["sysname"]], error = function(e) "")
  if (identical(sys, "Darwin")) return("macos")
  "linux"
}

#' Structured platform info for /api/system/info and repro manifests.
emp_platform_info <- function() {
  arch <- ""
  version_string <- ""
  try({
    arch <- R.version$arch
    version_string <- R.version$version.string
  }, silent = TRUE)
  os_detail <- ""
  try({
    info <- Sys.info()
    os_detail <- paste(info[["sysname"]], info[["release"]])
  }, silent = TRUE)
  is_arm <- grepl("arm|aarch", tolower(arch))
  list(
    os = emp_detect_os(),
    arch = arch,
    os_detail = trimws(paste(version_string, "|", os_detail)),
    r_version = as.character(getRversion()),
    is_arm = is_arm
  )
}
