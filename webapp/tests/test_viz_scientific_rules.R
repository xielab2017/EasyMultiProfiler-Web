# Lightweight scientific plotting contracts; does not start EMP or fit a model.
source('webapp/backend/helpers/viz.R')
expect_error <- function(expr, pattern) {
  err <- tryCatch({force(expr); NULL}, error = identity)
  stopifnot(inherits(err, 'error'), grepl(pattern, conditionMessage(err)))
}
df <- data.frame(padj=c(.2,.5),pvalue=c(.001,.01))
stopifnot(identical(.viz_selected_p(df, TRUE), df$padj))
stopifnot(identical(.viz_selected_p(df, FALSE), df$pvalue))
expect_error(.viz_selected_p(data.frame(pvalue=.01),TRUE), 'unavailable')
expect_error(.viz_selected_p(data.frame(padj=1.2),TRUE), 'between 0 and 1')
warn <- NULL
values <- withCallingHandlers(.viz_selected_p(data.frame(padj=c(.1,NA))), warning=function(w){warn <<- conditionMessage(w);invokeRestart('muffleWarning')})
stopifnot(identical(values,c(.1,NA_real_)),grepl('1 rows',warn))
fc <- c(-100,-1,0,1,100)
stopifnot(identical(.viz_finite_fc(fc), fc))
expect_error(.viz_finite_fc(c(1,Inf)), 'not replaced or clipped')
expect_error(.viz_finite_fc(c(1,NA)), 'non-finite')
mat <- matrix(c(1,2,3,4),nrow=2)
stopifnot(identical(.viz_heatmap_matrix(mat,FALSE),mat))
stopifnot(identical(.viz_heatmap_matrix(mat,TRUE),log1p(mat)))
expect_error(.viz_heatmap_matrix(matrix(c(NA,1,2,3),nrow=2)), 'not replaced with zero')
expect_error(.viz_heatmap_matrix(-mat), 'non-negative')
expect_error(.viz_heatmap_matrix(matrix(1,2,2)), 'zero-variance')
message('Scientific plotting contracts passed.')
if (requireNamespace('ggplot2',quietly=TRUE)) {
  `%||%` <- function(x,y) if(is.null(x)||!length(x))y else x
  emp_set_color_panel <- function(...) NULL
  emp_restore_color_panel <- function(...) NULL
  .viz_load_empt <- function(...) list()
  load_diff_raw <- function(...) list(data=data.frame(feature=c('a','b','c'),symbol=c('a','b','c'),log2FoldChange=c(-100,0,100),padj=c(.2,.5,.8),pvalue=c(.0001,.01,.001)))
  emp_diverging_colors <- function(...) grDevices::colorRampPalette(c('blue','white','red'))(256)
  emp_pub_theme <- function(...) ggplot2::theme_classic()
  viz_emit_ggplot <- function(p,...)p
  p <- make_volcano('test','test')
  stopifnot(identical(p$data$fc,c(-100,0,100)),all(as.character(p$data$change)=='NS'),identical(p$data$p_plot,c(.2,.5,.8)))
  message('Volcano integration contract passed with mocked storage and output.')
}
