source('webapp/backend/helpers/utils.R');source('webapp/backend/helpers/plot_theme.R');source('webapp/backend/helpers/runall.R')
profile<-list(font_pt=10,min_font_pt=8,label_mode='auto')
profiles<-list(deg_heatmap=list(export_size=list(width_mm=180,height_mm=220,dpi=150),publication=profile),volcano=list(export_size=list(width_mm=120,height_mm=100,dpi=150),publication=profile))
emp_viz_style_begin(list(publication=profile,figure_profiles=profiles))
out<-Sys.getenv('EMP_FIGURE_STANDARD_PROOF_DIR',tempfile());dir.create(out,recursive=TRUE,showWarnings=FALSE)
p<-ggplot2::ggplot(mtcars,ggplot2::aes(wt,mpg))+ggplot2::geom_point()
for(name in c('deg_heatmap','volcano')){
 .runall_plot(p,list(plots=out),name)
 stopifnot(is.null(getOption('emp.viz_style')$export_size))
}
bad<-profiles;bad$volcano$export_size$width_mm<-0
stopifnot(inherits(tryCatch(emp_viz_style_begin(list(publication=profile,figure_profiles=bad)),error=identity),'error'))
cat('PASS per-type background export, profile validation and style restoration:',out,'\n')
