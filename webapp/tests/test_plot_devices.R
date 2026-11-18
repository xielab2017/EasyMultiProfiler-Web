# Run against the same R and project library as the API.
source("webapp/backend/helpers/utils.R")
source("webapp/backend/helpers/viz.R")
source("webapp/backend/helpers/viz_qc.R")

test_plot_devices <- function() {
  root <- tempfile()
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE))
  before <- grDevices::dev.list()
  p <- ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) + ggplot2::geom_point()
  pdf <- file.path(root, "plot.pdf")
  out <- render_plot_artefacts(p, pdf, width = 4, height = 3, dpi = 96)
  png <- base64enc::base64decode(out$png_b64)
  stopifnot(identical(png[1:8], as.raw(c(137, 80, 78, 71, 13, 10, 26, 10))),
            identical(readBin(png[17:24], integer(), n = 2, endian = "big"), c(384L, 288L)),
            identical(rawToChar(readBin(pdf, "raw", n = 5)), "%PDF-"))

  ph <- if (requireNamespace("pheatmap", quietly = TRUE)) {
    pheatmap::pheatmap(matrix(seq_len(16), 4), silent = TRUE)
  } else {
    structure(list(gtable = grid::textGrob("Group A")), class = "pheatmap")
  }
  stopifnot(identical(.pheatmap_to_outputs(ph, pdf, 4, 3)$pdf, pdf))
  # A file cannot contain child files. The heatmap still has a usable preview.
  invalid <- suppressWarnings(.pheatmap_to_outputs(ph, file.path(pdf, "bad.pdf"), 4, 3))
  stopifnot(is.null(invalid$pdf), nzchar(invalid$png))

  for (ext in c("png", "pdf")) {
    file <- file.path(root, paste0("qc.", ext))
    emp_save_plot_i18n(p, file, width = 4, height = 3)
    stopifnot(file.size(file) > 0)
  }
  stopifnot(identical(before, grDevices::dev.list()))
}

test_plot_devices()
cat("Plot device checks passed.\n")
