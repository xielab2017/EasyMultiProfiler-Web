root<-normalizePath('.');target<-tempfile('emp-publication-worker-');dir.create(target)
Sys.setenv(EMP_DATA_DIR=target,EMP_JOB_DIR=file.path(target,'jobs'),EMP_BACKEND_DIR=file.path(root,'webapp/backend'),BACKEND_DIR=file.path(root,'webapp/backend'),EMP_ROOT=root)
source('webapp/backend/helpers/utils.R');source('webapp/backend/helpers/storage.R');source('webapp/backend/helpers/auth.R');source('webapp/backend/helpers/jobs.R');source('webapp/backend/helpers/plot_theme.R')
profile<-list(font_pt=10,min_font_pt=8,label_mode='auto')
emp_viz_style_begin(list(publication=profile,export_size=list(width_mm=87,height_mm=87,dpi=150)))
fn<-function(on_progress){
 p<-ggplot2::ggplot(mtcars,ggplot2::aes(wt,mpg))+ggplot2::geom_point()+ggplot2::theme_minimal(base_size=5)
 path<-file.path(Sys.getenv('EMP_DATA_DIR'),'worker.pdf');save_plot_pdf(p,path,4,3)
 list(success=TRUE,profile=emp_publication_profile(),size=emp_figure_size(4,3),pdf=path)
}
id<-submit_job('count_workbench',fn,owner_id='local')
# Change the dispatcher after submission: workers must keep their submitted style.
options(emp.viz_style=NULL)
for(i in 1:120){Sys.sleep(.2);st<-get_job_status(id);if(st$status%in%c('done','error'))break}
if(st$status!='done'){cat(readLines(.job_log_path(id)),sep='\n');stop(st$error%||%st$status)}
r<-get_job_result(id)
stopifnot(r$success,r$profile$font_pt==10,abs(r$size$width-87/25.4)<1e-10,file.size(r$pdf)>0,r$figure_layout$font_pt==10)
cat('PASS actual isolated worker retains submitted canvas / font and emits publication metadata\n')
unlink(target,recursive=TRUE)
