suppressPackageStartupMessages(library(EasyMultiProfiler))
root<-tempfile('emp-analysis-figures-');dir.create(root);Sys.setenv(EMP_DATA_DIR=root,EMP_SESSION_DIR=file.path(root,'sessions'))
for(helper in c('storage','utils','session','import','analysis','clinical','figure_method_rules','plot_theme','analysis_figures','ordination_figures'))source(file.path('webapp/backend/helpers',paste0(helper,'.R')))
set.seed(712);ids<-paste0('S',1:18);groups<-rep(c('A','B','C'),each=6);counts<-matrix(rpois(36*18,20),36,dimnames=list(paste0('Gene',1:36),ids));counts[1:10,groups=='A']<-counts[1:10,groups=='A']+60;counts[11:20,groups=='B']<-counts[11:20,groups=='B']+60
write.csv(counts,file.path(root,'counts.csv'));write.csv(data.frame(sample=ids,Group=groups),file.path(root,'meta.csv'),row.names=FALSE)
mae<-build_mae(file.path(root,'counts.csv'),file.path(root,'meta.csv'),'fixture',data_type='normal');sid<-create_session();save_mae(sid,mae)
emp_assert_session_owner<-function(s,o){if(!identical(s,sid)||o!='owner')stop('access denied')};list_jobs_for_session<-function(...)list()
proof<-'.local_run/verification/integrated-analysis-figures';dir.create(proof,recursive=TRUE,showWarnings=FALSE)
all_ids<-list()
check<-function(kind,method,result,views='default',extra=list()){
 id<-emp_save_analysis_result(sid,'fixture',kind,result,list(method=method,use=method));source<-paste0('snapshot:',id);all_ids[[paste(kind,method)]]<<-id
 path<-file.path(.af_dir(sid),paste0(id,'.rds'));before<-tools::md5sum(path)
 info<-emp_analysis_figure_describe(list(session_id=sid,experiment='fixture',source_id=source),'owner');stopifnot(info$n_rows==nrow(result))
 for(view in views){
  emp_viz_style_begin(list(export_size=list(width_mm=180,height_mm=160,dpi=150),publication=list(font_pt=8,min_font_pt=8,label_mode='manual')))
  b<-c(list(session_id=sid,experiment='fixture',source_id=source,kind=kind,view=view,max_features=12,top_n=10),extra)
  out<-emp_plot_analysis_result(b,'owner');stopifnot(out$success,!out$analysis_recomputed,identical(tools::md5sum(path),before))
  png<-file.path(proof,paste0(kind,'-',method,'-',view,'.png'));writeBin(base64enc::base64decode(out$plot),png)
  for(ext in c('pdf','svg','manifest','data')){file<-basename(out$download_urls[[ext]]);file.copy(file.path(session_path(sid),'plots',file),file.path(proof,paste0(kind,'-',method,'-',view,'.',switch(ext,manifest='json',data='csv',ext))),overwrite=TRUE)}
  plotted<-read.csv(file.path(session_path(sid),'plots',basename(out$download_urls$data)))
  if(kind=='dimension'){axes<-.af_axes(result);stopifnot(isTRUE(all.equal(plotted$x,as.numeric(result[[axes[1]]]))),isTRUE(all.equal(plotted$y,as.numeric(result[[axes[2]]]))))}
 }
 cat('PASS',kind,method,':',nrow(result),'frozen rows;',length(views),'figure types; no refit / source mutation\n')
}
for(method in c('PCA','PCoA','UMAP','tSNE','MDS')){
 result<-run_dimension(sid,'fixture',method);check('dimension',method,result,extra=list(group='Group',labels=TRUE))
 if(method=='tSNE')stopifnot(all(c('tSNE1','tSNE2')%in%names(result)),attr(result,'emp.figure_metadata')$actual_method=='t-SNE')
}
for(method in c('spearman','pearson','kendall'))check('correlation',method,run_correlation(sid,'fixture',method),views=c('default','network'))
for(method in c('hclust','kmeans','pam'))check('cluster',method,run_cluster(sid,'fixture',method,3),views=if(method=='hclust')c('default','tree','projection','membership','counts') else c('default','projection','membership','counts'))
for(method in c('randomForest','LEfSe','ANCOM','lasso','xgboost')){
 result<-run_marker(sid,'fixture',method,'Group',ref_group='A',test_group='B');stopifnot(nrow(result)>0)
 check('marker',method,result)
}
sources<-emp_analysis_figure_sources(sid,'fixture','owner');stopifnot(length(sources$sources)==16L)
error<-tryCatch(emp_analysis_figure_describe(list(session_id=sid,experiment='another',source_id=sources$sources[[1]]$source_id),'owner'),error=identity);stopifnot(inherits(error,'error'))
error<-tryCatch(emp_analysis_figure_describe(list(session_id=sid,experiment='fixture',source_id='snapshot:../../outside'),'owner'),error=identity);stopifnot(inherits(error,'error'))
cat('PASS all 16 requested methods, immutable source catalog, experiment isolation and source-ID validation; proofs:',proof,'\n')

# Historical jobs retain their actual columns and cannot synthesize a missing tree.
legacy_path<-file.path(root,'legacy.json');writeLines('{}',legacy_path)
legacy_kind<-'dimension';legacy_method<-'tSNE';legacy_data<-data.frame(primary=ids,UMAP1=seq_along(ids),UMAP2=-seq_along(ids))
emp_assert_job_owner<-function(id,owner){if(owner!='owner')stop('access denied');list(id=id,status='done',kind=paste0('analysis:/analyze/',legacy_kind),session_id=sid,experiment='fixture',finished=1,parameters=list(method=legacy_method))}
get_job_result<-function(id)list(data=jsonlite::toJSON(legacy_data,dataframe='rows',auto_unbox=TRUE))
.job_result_path<-function(id)legacy_path
b<-list(session_id=sid,experiment='fixture',source_id='job:legacy')
stopifnot(emp_analysis_figure_describe(b,'owner')$actual_method=='UMAP (legacy t-SNE fallback)')
legacy_kind<-'cluster';legacy_method<-'hclust';legacy_data<-data.frame(primary=ids,cluster=rep(1:3,each=6))
stopifnot(!emp_analysis_figure_describe(b,'owner')$has_tree,!emp_analysis_figure_describe(b,'owner')$has_projection)
error<-tryCatch(emp_plot_analysis_result(c(b,list(view='tree')),'owner'),error=identity);stopifnot(inherits(error,'error'),grepl('retained assignments only',conditionMessage(error)))
error<-tryCatch(emp_analysis_figure_describe(b,'foreign'),'error'=identity);stopifnot(inherits(error,'error'))
x<-readRDS(file.path(.af_dir(sid),paste0(all_ids[['dimension PCA']],'.rds')))
stopifnot(!is.null(.af_info(x)$software$R),.af_info(x)$analysis_parameters$method=='PCA')
cat('PASS legacy t-SNE identity, absent-tree guards, owner isolation and frozen analysis provenance\n')
