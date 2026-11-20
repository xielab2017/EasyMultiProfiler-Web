# Export physical canvas contracts; no changes to the input statistics.
source('webapp/backend/helpers/utils.R')
source('webapp/backend/helpers/plot_theme.R')
source('webapp/backend/helpers/viz_enrichment.R')
original <- getOption('emp.viz_style')
old <- emp_viz_style_begin(list(figure_scale=.75,export_size=list(width_mm=180,height_mm=120,dpi=150)))
stopifnot(isTRUE(all.equal(emp_figure_size(9,6),list(width=180/25.4,height=120/25.4,dpi=150))))
p <- ggplot2::ggplot(mtcars,ggplot2::aes(wt,mpg))+ggplot2::geom_point()
output <- Sys.getenv('EMP_FIGURE_PROOF_DIR',tempfile('emp-figure-size-'))
dir.create(output,recursive=TRUE,showWarnings=FALSE)
session_path <- function(...) output
result <- .enrich_viz_export(p,list(session_id='fixture'),'physical_enrichment',list(width=9,height=6),list(kind='synthetic'),mtcars)
stopifnot(abs(result$parameters$width-180/25.4)<1e-10,result$parameters$dpi==150)
jsonlite::write_json(list(pdf=file.path(output,'plots',result$pdf_name),png=file.path(output,'plots',sub('[.]pdf$','.png',result$pdf_name))),file.path(output,'proof.json'),auto_unbox=TRUE)
for(size in list(list(width_mm=NA,height_mm=120,dpi=150),list(width_mm=0,height_mm=120,dpi=150),list(width_mm=180,height_mm=120,dpi=96),list(width_mm=900,height_mm=900,dpi=600),list(width_mm=180,height_mm=120,dpi=150,extra=1))) {
 error <- tryCatch({emp_viz_style_begin(list(export_size=size));NULL},error=identity)
 stopifnot(inherits(error,'error'))
}
emp_viz_style_begin(list())
stopifnot(identical(emp_figure_size(9,6,96),list(width=9,height=6,dpi=96)))
emp_viz_style_end(original)
cat('PASS physical export override, enrichment size / manifest, validation, option reset\n')
