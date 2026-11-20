# Immutable analysis outputs: rendering reads saved results, never reruns a model.
.af_kinds<-c('dimension','correlation','cluster','marker')
.af_axes<-function(d)grep('^(PC|PCoA|UMAP|MDS|tSNE|Dim|Axis|Comp)[._ -]?[0-9]+$',names(d),ignore.case=TRUE,value=TRUE)
.af_dir<-function(sid)file.path(session_path(sid),'analysis_results')
.af_id<-function(id){if(length(id)!=1L||is.na(id)||!grepl('^[A-Za-z0-9_-]{1,80}$',id))stop('Invalid analysis result ID');id}
.af_rows<-function(result){d<-result$data;if(is.character(d)&&length(d)==1L)d<-jsonlite::fromJSON(d);if(!is.data.frame(d))stop('Saved analysis has no result table');d}
.af_actual<-function(kind,method){m<-tolower(method %||% '');if(kind=='marker'&&m%in%c('lefse','ancom','rf','randomforest'))return('Random Forest');switch(m,pca='PCA',pcoa='PCoA',mds='PCoA',umap='UMAP',tsne='t-SNE',lasso='LASSO',xgboost='XGBoost',xgb='XGBoost',hclust='Hierarchical',kmeans='K-means',pam='PAM',spearman='Spearman',pearson='Pearson',kendall='Kendall',method)}
.af_info<-function(x){
 d<-x$data;m<-x$metadata %||% list();if(x$kind=='dimension'&&is.null(m$actual_method)&&any(grepl('^UMAP',.af_axes(d),ignore.case=TRUE))&&tolower(x$parameters$method %||% '')%in%c('tsne','t-sne'))m$actual_method<-'UMAP (legacy t-SNE fallback)';scores<-intersect(c('coefficient','lasso_coe','rf_MDA','rf_MDG','Gain','importance','Overall','rf_IncMSE','rf_IncNodePurity','MeanDecreaseAccuracy','MeanDecreaseGini'),names(d))
 groups<-names(m$coldata)[vapply(m$coldata %||% list(),function(v){n<-length(unique(na.omit(as.character(v))));n>1&&n<=20&&n<length(v)},logical(1))]
 group_names<-setdiff(groups,c('primary','sample','sample_id'));group_values<-stats::setNames(lapply(group_names,function(k){v<-as.character(m$coldata[[k]]);v[!is.na(m$coldata[[k]])&nzchar(trimws(v))]}),group_names)
 list(source_id=x$source_id,kind=x$kind,experiment=x$experiment,requested_method=x$parameters$method %||% x$parameters$use,actual_method=m$actual_method %||% .af_actual(x$kind,x$parameters$method %||% x$parameters$use),created=x$created,n_rows=nrow(d),axes=.af_axes(d),groups=group_names,scores=scores,group_levels=lapply(group_values,function(v)sort(unique(v))),group_counts=lapply(group_values,function(v)as.list(table(v))),has_projection=is.data.frame(m$projection),has_tree=inherits(m$tree,'hclust'),source_job=x$source_job %||% NULL,analysis_parameters=x$parameters,algorithm_parameters=m$algorithm_parameters %||% NULL,coefficient_direction=m$coefficient_direction %||% NULL,software=x$software %||% NULL)
}
emp_save_analysis_result<-function(sid,experiment,kind,result,parameters=list()){
 if(!kind%in%.af_kinds)stop('Unsupported analysis result')
 d<-as.data.frame(result,stringsAsFactors=FALSE);meta<-attr(result,'emp.figure_metadata') %||% list()
 meta$sample_ids<-rownames(d)
 empt<-tryCatch(get_empt(sid,experiment),error=function(e)NULL)
 if(!is.null(empt)){
  meta$coldata<-as.data.frame(SummarizedExperiment::colData(empt))
  if(kind=='dimension'){
   bundle<-tryCatch(EasyMultiProfiler::EMP_result(empt,info='EMP_dimension_analysis'),error=function(e)NULL)
   if(is.list(bundle))meta$axis_percent<-bundle$dimension_axis
  }
 }
 id<-basename(tempfile('result_',tmpdir=tempdir()));dir<- .af_dir(sid);dir.create(dir,recursive=TRUE,showWarnings=FALSE)
 x<-list(source_id=paste0('snapshot:',id),kind=kind,experiment=experiment,created=as.numeric(Sys.time()),parameters=parameters,data=d,metadata=meta,software=list(web=emp_web_version(),R=as.character(getRversion()),EasyMultiProfiler=as.character(utils::packageVersion('EasyMultiProfiler'))),source_job=getOption('emp.analysis_job_id',NULL))
 path<-file.path(dir,paste0(id,'.rds'));tmp<-tempfile(tmpdir=dir);saveRDS(x,tmp);if(!file.rename(tmp,path))stop('Cannot preserve analysis result')
 tmp<-tempfile(tmpdir=dir);jsonlite::write_json(.af_info(x),tmp,auto_unbox=TRUE,null='null');if(!file.rename(tmp,file.path(dir,paste0(id,'.json'))))stop('Cannot publish analysis result')
 id
}
emp_analysis_figure_sources<-function(sid,experiment,owner){
 emp_assert_session_owner(sid,owner);out<-list();seen<-character()
 for(path in list.files(.af_dir(sid),pattern='[.]json$',full.names=TRUE)){
  x<-tryCatch(jsonlite::read_json(path,simplifyVector=TRUE),error=function(e)NULL)
  if(is.null(x)||!identical(x$experiment,experiment))next
  out[[length(out)+1L]]<-x;seen<-c(seen,x$source_job %||% character())
 }
 for(j in list_jobs_for_session(sid,owner)){
  kind<-sub('^analysis:/analyze/','',j$kind %||% '')
  if(j$status!='done'||!kind%in%.af_kinds||!identical(j$experiment,experiment)||j$id%in%seen)next
  out[[length(out)+1L]]<-list(source_id=paste0('job:',j$id),kind=kind,experiment=experiment,requested_method=j$parameters$method %||% j$parameters$use,actual_method=if(kind=='dimension'&&tolower(j$parameters$method %||% '')%in%c('tsne','t-sne'))'Legacy result; inspect retained axes' else .af_actual(kind,j$parameters$method %||% j$parameters$use),created=j$finished %||% j$started,source_job=j$id)
 }
 if(length(out))out<-out[order(vapply(out,function(x)x$created %||% 0,numeric(1)),decreasing=TRUE)]
 list(success=TRUE,sources=out)
}
.af_source<-function(b,owner){
 emp_assert_session_owner(b$session_id,owner);id<-as.character(b$source_id %||% '')
 if(length(id)!=1L||is.na(id))stop('Invalid analysis source ID')
 if(startsWith(id,'snapshot:')){
  name<-.af_id(sub('^snapshot:','',id));path<-file.path(.af_dir(b$session_id),paste0(name,'.rds'));if(!file.exists(path))stop('Saved analysis result not found')
  x<-readRDS(path)
 }else if(startsWith(id,'job:')){
  job<-emp_assert_job_owner(sub('^job:','',id),owner);kind<-sub('^analysis:/analyze/','',job$kind %||% '')
  if(!identical(job$status,'done')||!kind%in%.af_kinds||!identical(job$session_id,b$session_id)||!identical(job$experiment,b$experiment))stop('Analysis source ownership or type mismatch')
  result<-get_job_result(job$id)
  if(!is.null(result$analysis_result_id))return(.af_source(utils::modifyList(b,list(source_id=paste0('snapshot:',result$analysis_result_id))),owner))
  x<-list(source_id=id,kind=kind,experiment=job$experiment,created=job$finished,parameters=job$parameters,data=.af_rows(result),metadata=list(),source_job=job$id);path<-.job_result_path(job$id)
 }
 else stop('Select a saved analysis result first')
 if(!identical(x$experiment,b$experiment))stop('Analysis result belongs to another experiment')
 x$source_file<-path;x
}
emp_analysis_figure_describe<-function(b,owner){x<-.af_source(b,owner);c(list(success=TRUE),.af_info(x))}
.af_num<-function(x,default,low,high){v<-suppressWarnings(as.numeric(x %||% default));if(length(v)!=1L||!is.finite(v)||v<low||v>high)stop('Invalid figure parameter');v}
.af_col<-function(d,candidates){hit<-intersect(candidates,names(d));if(!length(hit))stop('Saved result does not contain required columns: ',paste(candidates,collapse='/'));hit[1]}
.af_cor<-function(d){
 a<-.af_col(d,c('var1','feature_1','cor_p.var1'));b<-.af_col(d,c('var2','feature_2','cor_p.var2'));r<-.af_col(d,c('coefficient','correlation','r','cor_p.coefficient'))
 data.frame(a=as.character(d[[a]]),b=as.character(d[[b]]),r=as.numeric(d[[r]]),stringsAsFactors=FALSE)
}
emp_plot_analysis_result<-function(b,owner){
 src<-.af_source(b,owner);kind<-src$kind;d<-src$data;m<-src$metadata %||% list();info<-.af_info(src)
 if(!is.null(b$kind)&&!identical(b$kind,kind))stop('Figure type does not match saved analysis')
 method<-info$actual_method %||% 'Saved result';view<-b$view %||% 'default';note<-'Saved analysis result; no model refit. / 已保存结果，不重新运行分析。'
 title<-paste(method,switch(kind,dimension='ordination',correlation='correlation',cluster='clustering',marker='feature importance'))
 plotted<-d;axis_statistics<-NULL;pairwise_statistics<-NULL;ellipse_metadata<-NULL;group_colors<-NULL;test_scope<-NULL;pairwise_annotations<-NULL
 if(kind=='dimension'){
  axes<-.af_axes(d);if(length(axes)<2L)stop('Saved result lacks two ordination axes; metadata cannot replace coordinates')
  x<-b$x_axis %||% axes[1];y<-b$y_axis %||% axes[2];if(!all(c(x,y)%in%axes)||x==y)stop('Select two different saved coordinate axes')
  if(any(!is.finite(d[[x]])|!is.finite(d[[y]])))stop('Saved coordinates contain nonfinite values')
  ids<-if('primary'%in%names(d))as.character(d$primary) else m$sample_ids %||% paste0('Result row ',seq_len(nrow(d)))
  plotted<-data.frame(sample=ids,x=d[[x]],y=d[[y]],group='All samples',group_missing=FALSE,stringsAsFactors=FALSE)
  group<-b$group %||% '';if(nzchar(group)){
   cd<-m$coldata;if(is.null(cd)||!group%in%names(cd)||!all(ids%in%rownames(cd)))stop('This result did not retain the selected group metadata; choose ungrouped or a newer result')
   raw_group<-cd[ids,group];plotted$group<-as.character(raw_group);plotted$group_missing<-is.na(raw_group)|!nzchar(trimws(plotted$group));plotted$group[plotted$group_missing]<-'Missing group'
  }
  lab<-function(axis){i<-match(axis,axes);pct<-m$axis_percent;if(isTRUE(m$variance_verified)&&length(pct)>=i&&is.finite(pct[i]))sprintf('%s (%.2f%%)',axis,pct[i]) else axis}
  figure<-emp_ordination_figure(plotted,b,c(x,y),c(lab(x),lab(y)),title);p<-figure$plot;plotted<-figure$data;axis_statistics<-figure$statistics;pairwise_statistics<-figure$pairwise;test_scope<-figure$test_scope;pairwise_annotations<-figure$pairwise_annotations;ellipse_metadata<-figure$ellipses;group_colors<-figure$colors;note<-paste(c(note,figure$notes),collapse='\n')
 }else if(kind=='correlation'){
  pairs<-.af_cor(d);if(any(is.finite(pairs$r)&abs(pairs$r)>1+1e-10))stop('Saved correlation coefficients outside [-1,1]')
  all<-unique(c(pairs$a,pairs$b));requested<-as.character(unlist(b$features %||% character()));limit<-as.integer(.af_num(b$max_features,24,2,80))
  if(length(requested)&&any(!requested%in%all))stop('Selected features are absent from saved correlation results')
  keep<-if(length(requested))requested else head(all,limit);pairs<-pairs[pairs$a%in%keep&pairs$b%in%keep,,drop=FALSE]
  note<-paste(note,sprintf('%d / %d features displayed; unrecorded cells remain NA. / 显示 %d / %d 个变量，未保存的单元格保持 NA。',length(keep),length(all),length(keep),length(all)))
  if(view=='network'){
   pairs<-pairs[is.finite(pairs$r)&pairs$a!=pairs$b&abs(pairs$r)>=.af_num(b$min_abs_r,.7,0,1),,drop=FALSE]
   key<-vapply(seq_len(nrow(pairs)),function(i)paste(sort(c(pairs$a[i],pairs$b[i])),collapse='\r'),character(1));pairs<-pairs[!duplicated(key),,drop=FALSE]
   nodes<-data.frame(name=keep,x=cos(seq(0,2*pi,length.out=length(keep)+1)[-1]),y=sin(seq(0,2*pi,length.out=length(keep)+1)[-1]))
   pairs$x<-nodes$x[match(pairs$a,keep)];pairs$y<-nodes$y[match(pairs$a,keep)];pairs$xend<-nodes$x[match(pairs$b,keep)];pairs$yend<-nodes$y[match(pairs$b,keep)];pairs$sign<-ifelse(pairs$r>=0,'Positive','Negative')
   p<-ggplot2::ggplot()+ggplot2::geom_segment(data=pairs,ggplot2::aes(x,y,xend=xend,yend=yend,color=sign),alpha=.6)+ggplot2::geom_point(data=nodes,ggplot2::aes(x,y),size=2)+ggrepel::geom_text_repel(data=nodes,ggplot2::aes(x,y,label=name),seed=1,max.overlaps=Inf)+ggplot2::coord_equal()+ggplot2::labs(color='Saved correlation')+ggplot2::theme_void();plotted<-pairs
   note<-paste(note,'Circular layout; positions are not biological distances. / 圆形布局不代表生物学距离。')
  }else{
   mat<-matrix(NA_real_,length(keep),length(keep),dimnames=list(keep,keep))
   for(i in seq_len(nrow(pairs)))if(is.finite(pairs$r[i])){a<-pairs$a[i];z<-pairs$b[i];if(is.finite(mat[a,z])&&abs(mat[a,z]-pairs$r[i])>1e-8)stop('Conflicting saved correlation coefficients');mat[a,z]<-mat[z,a]<-pairs$r[i]}
   if(!any(is.finite(mat)))stop('No saved coefficients for the selected features')
   p<-emp_publication_pheatmap(mat,cluster_rows=FALSE,cluster_cols=FALSE,na_col='grey92',breaks=seq(-1,1,length.out=101),color=grDevices::colorRampPalette(c('#2166AC','white','#B2182B'))(100),main=title,silent=TRUE);plotted<-pairs
  }
 }else if(kind=='cluster'){
  cluster<-.af_col(d,c('cluster'));ids<-if('primary'%in%names(d))as.character(d$primary) else m$sample_ids %||% paste0('Result row ',seq_len(nrow(d)))
  plotted<-data.frame(sample=ids,cluster=as.character(d[[cluster]]));if(anyNA(plotted$cluster))stop('Saved cluster assignments contain missing labels')
  if(view=='tree'||(view=='default'&&inherits(m$tree,'hclust'))){
   hc<-m$tree;if(!inherits(hc,'hclust'))stop('This older result retained assignments only, not a hierarchy. Use membership/counts, or explicitly rerun hierarchical analysis to save its tree')
   n<-length(hc$order);xx<-numeric(n-1);yy<-hc$height;leaf<-numeric(n);leaf[hc$order]<-seq_len(n);segments<-list()
   for(i in seq_len(n-1)){
    children<-hc$merge[i,];cx<-vapply(children,function(v)if(v<0)leaf[-v] else xx[v],numeric(1));cy<-vapply(children,function(v)if(v<0)0 else yy[v],numeric(1));xx[i]<-mean(cx)
    segments[[i]]<-data.frame(x=c(cx[1],cx[2],cx[1]),y=c(cy[1],cy[2],yy[i]),xend=c(cx[1],cx[2],cx[2]),yend=rep(yy[i],3))
   }
   branches<-do.call(rbind,segments);p<-ggplot2::ggplot(branches,ggplot2::aes(x,y,xend=xend,yend=yend))+ggplot2::geom_segment()+ggplot2::scale_x_continuous(breaks=seq_len(n),labels=hc$labels[hc$order])+ggplot2::labs(x='Samples',y=paste('Saved',hc$method,'height'))+ggplot2::theme(axis.text.x=ggplot2::element_text(angle=90,hjust=1,vjust=.5))
  }else if(view=='projection'||(view=='default'&&is.data.frame(m$projection))){
   projection<-m$projection;if(!is.data.frame(projection))stop('This older result did not save a projection; select membership/counts or explicitly rerun clustering')
   projection$cluster<-plotted$cluster[match(projection$sample,plotted$sample)];if(anyNA(projection$cluster))stop('Saved projection sample IDs do not match cluster assignments')
   plotted<-projection;labels<-c('PC1','PC2');if(length(m$projection_variance)>=2)labels<-sprintf('%s (%.2f%%)',labels,m$projection_variance[1:2])
   p<-ggplot2::ggplot(plotted,ggplot2::aes(PC1,PC2,color=cluster))+ggplot2::geom_point(size=2.5)+ggplot2::labs(x=labels[1],y=labels[2],color='Saved cluster')
   note<-paste(note,'Saved descriptive PCA projection of the clustering input; assignments unchanged. / 显示聚类输入的已保存 PCA 投影，分组不变。')
  }else if(view=='counts'){
   plotted<-as.data.frame(table(plotted$cluster),stringsAsFactors=FALSE);names(plotted)<-c('cluster','count');p<-ggplot2::ggplot(plotted,ggplot2::aes(cluster,count,fill=cluster))+ggplot2::geom_col()+ggplot2::labs(x='Saved cluster',y='Samples',fill='Cluster')
  }else{
   plotted$position<-seq_len(nrow(plotted));p<-ggplot2::ggplot(plotted,ggplot2::aes(position,'Assignment',fill=cluster))+ggplot2::geom_tile()+ggplot2::scale_x_continuous(breaks=plotted$position,labels=plotted$sample)+ggplot2::labs(x='Samples',y=NULL,fill='Cluster')+ggplot2::theme(axis.text.x=ggplot2::element_text(angle=90,hjust=1,vjust=.5))
  }
 }else{
  feature<-.af_col(d,c('feature','Feature','gene_id'));score<-b$score %||% info$scores[1];if(length(score)!=1||!score%in%info$scores)stop('Select a retained importance or coefficient column')
  plotted<-data.frame(feature=as.character(d[[feature]]),score=as.numeric(d[[score]]));if(any(!is.finite(plotted$score)))stop('Saved marker scores contain nonfinite values')
  top<-as.integer(.af_num(b$top_n,20,1,100));plotted<-head(plotted[order(if(score%in%c('coefficient','lasso_coe'))-abs(plotted$score) else -plotted$score),],top)
  if(!nrow(plotted))stop('This model retained no marker scores to plot')
  plotted$label<-factor(plotted$feature,levels=rev(plotted$feature));p<-ggplot2::ggplot(plotted,ggplot2::aes(score,label))+ggplot2::geom_col(fill='#3B6FB6')+ggplot2::labs(x=switch(score,coefficient='Coefficient',lasso_coe='LASSO coefficient',rf_MDA='Mean decrease accuracy',rf_MDG='Mean decrease Gini',Gain='XGBoost Gain',importance='Saved importance',score),y='Saved feature')
  requested<-tolower(info$requested_method %||% '');if(requested%in%c('lefse','ancom'))note<-paste(note,'Requested',info$requested_method,'used Random Forest fallback; not LEfSe LDA / ANCOM W.')
  if(!is.null(m$coefficient_direction))note<-paste(note,'Coefficient direction:',m$coefficient_direction)
  note<-paste(note,sprintf('%d / %d features shown.',nrow(plotted),nrow(d)))
  note<-paste(note,'Feature scores only; no validation ROC was retained. / 此处展示特征分数，不生成未保存的验证 ROC。')
 }
 if(inherits(p,'ggplot')&&!inherits(p,'patchwork'))p<-p+emp_pub_theme(base_size=emp_publication_profile()$font_pt %||% 10)+ggplot2::labs(title=title)
 # Reapply view-specific axis styling after the common theme.
 if(kind=='cluster'&&view!='counts'&&view!='projection'&&!(view=='default'&&!inherits(m$tree,'hclust')&&is.data.frame(m$projection)))p<-p+ggplot2::theme(axis.text.x=ggplot2::element_text(angle=90,hjust=1,vjust=.5))
 size<-emp_figure_size(180/25.4,140/25.4);dir<-file.path(session_path(b$session_id),'plots');dir.create(dir,recursive=TRUE,showWarnings=FALSE);prefix<-basename(tempfile('analysis_plot_',tmpdir=dir))
 files<-stats::setNames(paste0(prefix,c('.png','.pdf','.svg','.data.csv','.manifest.json')),c('png','pdf','svg','data','manifest'));if(!is.null(axis_statistics))files<-c(files,stats=paste0(prefix,'.stats.csv'));if(!is.null(pairwise_statistics)&&nrow(pairwise_statistics))files<-c(files,pairwise=paste0(prefix,'.pairwise.csv'));paths<-file.path(dir,files);names(paths)<-names(files);done<-FALSE;on.exit(if(!done)unlink(paths),add=TRUE)
 for(ext in c('png','pdf','svg'))emp_publication_export(p,paths[ext],size$width,size$height,size$dpi)
 utils::write.csv(plotted,paths['data'],row.names=FALSE)
 if(!is.null(axis_statistics))utils::write.csv(axis_statistics,paths['stats'],row.names=FALSE)
 if(!is.null(pairwise_statistics)&&nrow(pairwise_statistics))utils::write.csv(pairwise_statistics,paths['pairwise'],row.names=FALSE)
 manifest<-list(schema='emp-analysis-figure-v1',source=.af_info(src),source_md5=unname(tools::md5sum(src$source_file)),parameters=b[setdiff(names(b),'figure_profiles')],note=note,axis_statistics=axis_statistics,pairwise_statistics=pairwise_statistics,pairwise_annotations=pairwise_annotations,test_scope=test_scope,ellipses=ellipse_metadata,group_colors=as.list(group_colors),analysis_recomputed=FALSE,plotted_rows=nrow(plotted),full_rows=nrow(d),web_version=emp_web_version())
 jsonlite::write_json(manifest,paths['manifest'],auto_unbox=TRUE,pretty=TRUE,null='null',digits=NA);done<-TRUE
 list(success=TRUE,plot=base64enc::base64encode(paths['png']),download_urls=lapply(files,function(f)paste0('/api/visualize/analysis-result/file/',b$session_id,'/',f)),source=.af_info(src),n_rows=nrow(plotted),full_rows=nrow(d),note=note,axis_statistics=axis_statistics,pairwise_statistics=pairwise_statistics,pairwise_annotations=pairwise_annotations,test_scope=test_scope,ellipses=ellipse_metadata,group_colors=as.list(group_colors),parameters=list(width=size$width,height=size$height,dpi=size$dpi),analysis_recomputed=FALSE)
}
