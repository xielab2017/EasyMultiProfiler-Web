# Run from the repository root: Rscript webapp/tests/test_figure_method_rules.R
source("webapp/backend/helpers/figure_method_rules.R")
local({
  previous <- Sys.getenv("EMP_FIGURE_METHODS_ROOT", unset = NA_character_)
  on.exit(if (is.na(previous)) Sys.unsetenv("EMP_FIGURE_METHODS_ROOT") else
            Sys.setenv(EMP_FIGURE_METHODS_ROOT = previous), add = TRUE)
  Sys.unsetenv("EMP_FIGURE_METHODS_ROOT")
  stopifnot(is.null(emp_figure_methods_theme()), !emp_figure_methods_profile()$configured)
  Sys.setenv(EMP_FIGURE_METHODS_ROOT = tempfile("missing-methods-"))
  messages <- character()
  missing <- withCallingHandlers(emp_figure_methods_theme(), warning = function(w) {
    messages <<- c(messages, conditionMessage(w)); invokeRestart("muffleWarning")
  })
  stopifnot(is.null(missing), length(messages) == 1L,
            grepl("retaining the built-in", messages))
  root <- if (!is.na(previous) && nzchar(previous)) previous else tempfile("figure-methods-fixture-")
  if (is.na(previous) || !nzchar(previous)) {
    dir.create(file.path(root, "library"), recursive = TRUE)
    on.exit(unlink(root, recursive = TRUE), add = TRUE)
    # Explicit bridge fixture; no dependency on a developer's private checkout.
    writeLines(c(
      'figure_theme <- function(config) ggplot2::theme_classic(base_size=config$base_size) + ggplot2::theme(legend.position=config$specific$legend_position)',
      'export_figure <- function(plot, output_dir, config) {',
      '  dir.create(output_dir, recursive=TRUE, showWarnings=FALSE)',
      '  for (format in c("png","svg","pdf")) ggplot2::ggsave(file.path(output_dir,paste0("figure.",format)),plot=plot,width=config$width,height=config$height,dpi=config$dpi)',
      '}'
    ), file.path(root, "library", "common.R"))
  }
  Sys.setenv(EMP_FIGURE_METHODS_ROOT = root)
  theme <- emp_figure_methods_theme(base_size = 14, legend_position = "bottom")
  stopifnot(inherits(theme, "theme"), theme$legend.position == "bottom",
            theme$axis.title$size == 14,
            identical(attr(theme, "emp_figure_methods")$md5,
                      unname(tools::md5sum(file.path(root, "library", "common.R")))))
  file <- tempfile(fileext = ".json")
  on.exit(unlink(file), add = TRUE)
  emp_write_figure_methods_manifest(file, 9, 6, 300, list(source = "validation only; no scientific data"))
  manifest <- jsonlite::read_json(file, simplifyVector = TRUE)
  stopifnot(manifest$width_inches == 9, manifest$dpi == 300,
            manifest$figure_methods$available)
  failure <- tryCatch({emp_write_figure_methods_manifest(file, 9, 6, 300); FALSE}, error = function(e) TRUE)
  stopifnot(failure)
  failure <- tryCatch({emp_figure_methods_theme(base_size = NA_real_); FALSE}, error = function(e) TRUE)
  stopifnot(failure)
  export_dir <- tempfile("figure-export-test-")
  on.exit(unlink(export_dir, recursive = TRUE), add = TRUE)
  fixture <- data.frame(x = c(1, 2, 3), y = c(3, 1, 2))
  plot <- ggplot2::ggplot(fixture, ggplot2::aes(x, y)) + ggplot2::geom_point() +
    ggplot2::labs(title = "Export test fixture; no scientific result")
  paths <- emp_export_figure_methods(plot, export_dir, width = 5, height = 4)
  stopifnot(length(paths) == 3L, all(file.exists(paths)),
            all(file.info(paths)$size > 0),
            file.exists(file.path(export_dir, "figure_methods_manifest.json")))
  original_hashes <- tools::md5sum(paths)
  failure <- tryCatch({emp_export_figure_methods(plot, export_dir, 5, 4); FALSE}, error = function(e) TRUE)
  stopifnot(failure, identical(original_hashes, tools::md5sum(paths)))
  cat("Figure methods live theme, fallback, provenance, dimensions, PNG/SVG/PDF export and no-overwrite checks passed.\n")
})
