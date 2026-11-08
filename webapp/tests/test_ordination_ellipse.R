source('webapp/backend/helpers/plot_theme.R')
# Three non-collinear points produce a descriptive covariance ellipse.
e <- emp_conf_ellipse(c(0,1,0),c(0,0,1),rep('A',3))
stopifnot(nrow(e)==60L,all(is.finite(e$x)),all(is.finite(e$y)))
stopifnot(is.null(emp_conf_ellipse(c(0,1),c(0,1),rep('A',2))))
stopifnot(is.null(emp_conf_ellipse(c(0,1,2),c(0,1,2),rep('A',3))))
message('Ellipse small-group and degenerate-covariance checks passed.')
