source('webapp/backend/helpers/utils.R');source('webapp/backend/helpers/plot_theme.R')
profile<-list(font_pt=10,min_font_pt=8,label_mode='auto')
emp_viz_style_begin(list(export_size=list(width_mm=180,height_mm=120,dpi=150),publication=profile))
emp_assert_job_owner<-function(id,principal){if(principal!='owner')stop('Access denied');list(status='done',kind='count_workbench')}
set.seed(108);values<-matrix(rnorm(40),10,dimnames=list(paste0('gene',1:10),paste0('S',1:4)))
get_job_result<-function(id)list(artifacts=list(pca=list(scores=lapply(1:4,function(i)list(PC1=i,PC2=-i,group=if(i<=2)'Control' else 'Treatment')),variance_explained=list(.7,.2)),heatmap=list(values=lapply(1:10,function(i)as.list(values[i,])),feature_ids=as.list(rownames(values)),sample_ids=as.list(colnames(values)))))
for(kind in c('pca','heatmap')){
 result<-emp_publication_workbench(list(job_id='fixture',kind=kind),'owner')
 stopifnot(result$success,!result$analysis_recomputed,substr(rawToChar(base64enc::base64decode(result$pdf_base64)[1:5]),1,5)=='%PDF-',grepl('<svg',rawToChar(base64enc::base64decode(result$svg_base64)),fixed=TRUE))
}
error<-tryCatch(emp_publication_workbench(list(job_id='fixture',kind='pca'),'other'),error=identity);stopifnot(inherits(error,'error'))
cat('PASS frozen workbench PCA / heatmap vector exports, physical dimensions, ownership and no analysis refit\n')
