# Execute only registered analysis/preparation handlers from the trusted local
# plumber source. Client input cannot supply R code, a function or a file path.
emp_background_handlers <- function() {
  path <- file.path(Sys.getenv("EMP_BACKEND_DIR", unset = "webapp/backend"), "plumber.R")
  lines <- readLines(path, warn = FALSE)
  expressions <- parse(path, keep.source = TRUE)
  refs <- attr(expressions, "srcref")
  handlers <- list()
  previous <- 0L
  for (i in seq_along(expressions)) {
    expression <- expressions[[i]]
    start <- refs[[i]][1]
    annotations <- lines[seq.int(previous + 1L, start)]
    previous <- refs[[i]][3]
    if (!is.call(expression) || !identical(expression[[1]], as.name("function"))) next
    tags <- grep("^#\\* @post /api/", annotations, value = TRUE)
    if (!length(tags)) next
    route <- sub("^#\\* @post /api", "", tail(tags, 1))
    allowed <- grepl("^/analyze/(alpha|differential|dimension|correlation|cluster|marker|enrichment|gsea|network)$", route) ||
      grepl("^/prepare/(filter|normalize|impute|rarefy|collapse|use_snapshot)$", route) ||
      grepl("^/workflows/[^/]+/(analyze/[^/]+|prepare/taxonomy|preprocess)$", route) ||
      grepl("^/clinical/(three_line|systematic_summary|cor|fitline|multiomics_joint|marker_model)$", route)
    if (!allowed) next
    handler <- eval(expression, envir = .GlobalEnv)
    required <- names(formals(handler))[vapply(formals(handler), function(x) identical(x, quote(expr = )), logical(1))]
    if (length(setdiff(required, c("req", "res")))) next
    handlers[[route]] <- handler
  }
  handlers
}

emp_run_background_request <- function(route, payload, principal, on_progress = NULL) {
  handlers <- emp_background_handlers()
  handler <- handlers[[route]]
  if (is.null(handler)) stop("Analysis route is not registered for background execution.")
  emp_assert_session_owner(payload$session_id, principal)
  req <- new.env(parent = emptyenv())
  req$postBody <- jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null", digits = NA)
  req$PATH_INFO <- paste0("/api", route)
  req$emp_principal <- principal
  req$emp_on_progress <- on_progress
  req$args <- list()
  res <- new.env(parent = emptyenv())
  res$status <- 200L
  res$setHeader <- function(...) invisible(NULL)
  if (is.function(on_progress)) on_progress(5, paste("Running", route))
  value <- handler(req = req, res = res)
  if (res$status >= 400L || isFALSE(value$success)) stop(value$error %||% "Analysis failed.")
  value
}
