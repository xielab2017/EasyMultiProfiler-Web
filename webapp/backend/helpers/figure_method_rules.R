# Optional live bridge to the user's maintained Figure_Methods_Lab.
# This file does not copy statistical methods, load case configs or refit data.
emp_figure_methods_profile <- function() {
  root <- trimws(Sys.getenv("EMP_FIGURE_METHODS_ROOT", ""))
  if (!nzchar(root)) return(list(configured = FALSE, available = FALSE,
                                status = "not_configured", source = NULL, md5 = NULL))
  root <- normalizePath(path.expand(root), winslash = "/", mustWork = FALSE)
  source <- file.path(root, "library", "common.R")
  rules <- c("AGENTS.md", "METHODS.md", "library/common.R",
             "skills/omics-clustered-heatmap/SKILL.md",
             "skills/omics-volcano/SKILL.md", "skills/omics-pca-groups/SKILL.md")
  paths <- file.path(root, rules)
  available <- file.exists(source) && !dir.exists(source)
  hashes <- rep(NA_character_, length(paths)); names(hashes) <- rules
  present <- file.exists(paths) & !dir.exists(paths)
  hashes[present] <- unname(tools::md5sum(paths[present]))
  list(configured = TRUE, available = available,
       status = if (available) "available" else "unavailable",
       root = root, source = source, md5 = unname(hashes["library/common.R"]),
       rules_files = as.list(hashes),
       scope = "Live figure_theme from library/common.R; no statistical refit or case configuration executed")
}

emp_figure_methods_theme <- function(base_size = 12, font_family = "",
                                     legend_position = "right") {
  if (length(base_size) != 1L || !is.numeric(base_size) ||
      !is.finite(base_size) || base_size <= 0) stop("base_size must be positive and finite")
  if (length(font_family) != 1L || !is.character(font_family) || is.na(font_family)) {
    stop("font_family must be a single string")
  }
  if (length(legend_position) != 1L ||
      !legend_position %in% c("right", "left", "top", "bottom", "none", "inside")) {
    stop("Unsupported legend_position")
  }
  profile <- emp_figure_methods_profile()
  if (!profile$configured) return(NULL)
  if (!profile$available) {
    warning("Figure Methods Lab is unavailable; retaining the built-in EMP theme: ",
            profile$source, call. = FALSE)
    return(NULL)
  }
  tryCatch({
    # Only the explicit local administrator path is loaded. Never accept code
    # paths or source text from a web request, uploaded table, or model response.
    environment <- new.env(parent = baseenv())
    sys.source(profile$source, envir = environment)
    if (!is.function(environment$figure_theme)) stop("figure_theme is not exported")
    theme <- environment$figure_theme(list(base_size = base_size,
                  font_family = font_family, specific = list(legend_position = legend_position)))
    if (!inherits(theme, "theme")) stop("figure_theme did not return a ggplot2 theme")
    attr(theme, "emp_figure_methods") <- profile
    theme
  }, error = function(error) {
    warning("Figure Methods Lab theme could not be loaded; retaining the built-in EMP theme: ",
            conditionMessage(error), call. = FALSE)
    NULL
  })
}

emp_write_figure_methods_manifest <- function(path, width, height, dpi, extra = list()) {
  dimensions <- c(width, height, dpi)
  if (length(dimensions) != 3L || !is.numeric(dimensions) ||
      any(!is.finite(dimensions)) || any(dimensions <= 0)) {
    stop("width, height and dpi must be positive finite values")
  }
  if (file.exists(path)) stop("Figure manifest exists; choose a new output path")
  profile <- emp_figure_methods_profile()
  manifest <- list(schema = "emp-figure-methods-v1", created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
                   width_inches = width, height_inches = height, dpi = dpi,
                   figure_methods = profile, parameters = extra,
                   R_version = R.version.string,
                   ggplot2_version = as.character(utils::packageVersion("ggplot2")))
  jsonlite::write_json(manifest, path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  invisible(manifest)
}

# Export through the current methods library. This is an explicit export path,
# so a missing library is an error rather than a silent format/style fallback.
emp_export_figure_methods <- function(plot, output_dir, width, height, dpi = 300) {
  dimensions <- c(width, height, dpi)
  if (length(dimensions) != 3L || !is.numeric(dimensions) ||
      any(!is.finite(dimensions)) || any(dimensions <= 0)) {
    stop("width, height and dpi must be positive finite values")
  }
  profile <- emp_figure_methods_profile()
  if (!profile$configured || !profile$available) {
    stop("Figure Methods Lab export is unavailable; configure EMP_FIGURE_METHODS_ROOT")
  }
  targets <- file.path(output_dir, paste0("figure.", c("png", "svg", "pdf")))
  manifest_path <- file.path(output_dir, "figure_methods_manifest.json")
  if (any(file.exists(c(targets, manifest_path)))) {
    stop("Figure outputs or manifest exist; choose a new iteration directory")
  }
  environment <- new.env(parent = baseenv())
  sys.source(profile$source, envir = environment)
  if (!is.function(environment$export_figure)) stop("export_figure is not exported by Figure Methods Lab")
  config <- list(width = width, height = height, dpi = dpi,
                 data_kind = "user_supplied", font_family = NULL)
  environment$export_figure(plot, output_dir, config)
  if (!all(file.exists(targets)) || any(file.info(targets)$size <= 0)) {
    stop("Figure Methods Lab did not produce all non-empty PNG/SVG/PDF outputs")
  }
  emp_write_figure_methods_manifest(manifest_path, width, height, dpi,
                                  extra = list(data_kind = "user_supplied",
                                               statistics = "unchanged; export only",
                                               formats = c("png", "svg", "pdf"),
                                               style = getOption("emp.viz_style", list())))
  invisible(targets)
}
