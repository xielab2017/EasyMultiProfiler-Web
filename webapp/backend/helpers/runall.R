# One-click "run everything" pipelines for transcriptomics (RNAseq) and 16S.
#
# Each run produces:
#   <session>/bundles/<run_id>/plots/*.pdf        - publication-ready figures
#   <session>/bundles/<run_id>/plots/*.{png,pdf,svg} - real R figure exports
#   <session>/bundles/<run_id>/manifest.json      - per-stage status and provenance
#   <session>/bundles/<run_id>/tables/*.xlsx      - Excel tables (one per step)
#   <session>/bundles/<run_id>/summary.txt        - human-readable step log
# and then zips the whole folder to:
#   <session>/bundles/<run_id>.zip                - single-file download
#
# The caller passes an `on_progress(pct, msg)` callback (injected by jobs.R)
# so the UI can render a unified progress bar.

.bundle_root <- function(session_id) file.path(session_path(session_id), "bundles")

.new_run_id <- function() paste0(format(Sys.time(), "%Y%m%d-%H%M%S"), "-", basename(tempfile("run")))

.bundle_init <- function(session_id) {
  run_id <- .new_run_id()
  base   <- file.path(.bundle_root(session_id), run_id)
  dir.create(file.path(base, "plots"),  recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(base, "tables"), recursive = TRUE, showWarnings = FALSE)
  list(run_id = run_id, base = base,
       plots  = file.path(base, "plots"),
       tables = file.path(base, "tables"),
       log    = file.path(base, "summary.txt"))
}

# Append a step line to summary.txt. Silently no-op if write fails.
.log_step <- function(bundle, step, elapsed_s, status = "ok", extra = NULL) {
  line <- sprintf("[%s] %-42s %6.2fs  %s%s\n",
                  format(Sys.time(), "%H:%M:%S"), step,
                  elapsed_s, status,
                  if (!is.null(extra)) paste0(" | ", extra) else "")
  try(cat(line, file = bundle$log, append = TRUE), silent = TRUE)
}

# Backward-compatible public pipelines; implementation and stage manifest below.
run_all_rnaseq <- function(session_id, experiment, group_var="Group", ref_group=NULL,
 test_group=NULL, organism="mmu", fc_cutoff=1, p_cutoff=.05, use_padj=TRUE,
 min_row_sum=0, do_enrichment=TRUE, on_progress=NULL, do_gsea=FALSE,
 gsea_database="GO_BP", gsea_top_n=3L, do_correlation=TRUE, do_cluster=TRUE,
 do_method_figures=TRUE, feature_top_n=100L, network_cutoff=.6, seed=1L) {
 .runall_complete(session_id,experiment,"transcriptomics",as.list(environment()))
}
run_all_m16s <- function(session_id, experiment, group_var=NULL, taxonomy_level="Genus",
 alpha_index="shannon", beta_method="bray", ord_method="PCoA", on_progress=NULL,
 do_correlation=TRUE, do_cluster=TRUE, do_method_figures=TRUE,
 ternary_groups=NULL, feature_top_n=100L, network_cutoff=.6, seed=1L) {
 .runall_complete(session_id,experiment,"microbiome_16s",as.list(environment()))
}

.make_volcano_plot <- function(session_id, experiment, fc_cutoff=1,p_cutoff=.05,use_padj=TRUE,label_top=15L) {
 env<-new.env(parent=environment(make_volcano));env$viz_emit_ggplot<-function(p,...)p
 builder<-make_volcano;environment(builder)<-env
 builder(session_id,experiment,fc_cutoff,p_cutoff,use_padj,label_top=label_top)
}

# Stage runner: errors never masquerade as successful missing plots. Disabled or
# inapplicable stages have explicit reasons, and each stage records new files.
.runall_skip <- function(reason) stop(structure(list(message=reason,call=NULL),class=c('emp_runall_skip','error','condition')))
.runall_engine <- function(bundle,parameters,on_progress=NULL) {
 e<-new.env(parent=emptyenv());e$stages<-list();e$parameters<-parameters
 e$stage<-function(id,fn,enabled=TRUE,reason='Disabled by run parameters') {
  start<-Sys.time();before<-list.files(bundle$base,recursive=TRUE)
  warnings<-character();value<-NULL;status<-'done';detail<-''
  if(!isTRUE(enabled)){status<-'skipped';detail<-reason}else{
   value<-tryCatch(withCallingHandlers(fn(),warning=function(w){warnings<<-c(warnings,conditionMessage(w));invokeRestart('muffleWarning')}),
    emp_runall_skip=function(c){status<<-'skipped';detail<<-conditionMessage(c);NULL},
    error=function(c){status<<-'error';detail<<-conditionMessage(c);NULL})
  }
  elapsed<-as.numeric(difftime(Sys.time(),start,units='secs'))
  files<-setdiff(list.files(bundle$base,recursive=TRUE),before)
  e$stages[[length(e$stages)+1L]]<-list(id=id,status=status,reason=detail,warnings=unique(warnings),elapsed_s=round(elapsed,3),files=files)
  .log_step(bundle,id,elapsed,status,detail)
  jsonlite::write_json(list(schema='emp-runall-stages-v2',parameters=parameters,stages=e$stages),file.path(bundle$base,'stages.json'),auto_unbox=TRUE,pretty=TRUE,null='null')
  if(is.function(on_progress))on_progress(min(94L,5L+length(e$stages)*4L),paste(id,status,detail))
  value
 }
 e
}
.runall_table <- function(d,b,name) {
 d<-as.data.frame(d);path<-file.path(b$tables,paste0(name,'.csv'));utils::write.csv(d,path,row.names=FALSE)
 if(requireNamespace('openxlsx',quietly=TRUE))save_df_xlsx(d,file.path(b$tables,paste0(name,'.xlsx')))
 invisible(path)
}
.runall_plot <- function(p,b,name,width=9,height=6) {
 if(is.null(p))stop('No plot object was produced')
 for(ext in c('png','pdf','svg')){
  path<-file.path(b$plots,paste0(name,'.',ext))
  if(file.exists(path))stop('Refusing to overwrite a figure')
  if(ext=='svg'&&!requireNamespace('svglite',quietly=TRUE))stop('SVG export requires svglite')
  device<-switch(ext,png=if(requireNamespace('ragg',quietly=TRUE))ragg::agg_png else 'png',pdf=grDevices::pdf,svg=svglite::svglite)
  args<-list(filename=path,plot=p,width=width,height=height,units='in',dpi=300,device=device,bg='white')
  if(ext=='pdf')args$useDingbats<-FALSE
  do.call(ggplot2::ggsave,args)
  if(!file.exists(path)||file.info(path)$size==0)stop('Figure export failed: ',ext)
 }
 invisible(TRUE)
}
.runall_copy_method <- function(out,b,name,session_id) {
 if(!isTRUE(out$success))stop('Method figure was not produced')
 for(key in names(out$download_urls)){
  filename<-basename(out$download_urls[[key]]);from<-file.path(session_path(session_id),'plots',filename)
  if(!file.exists(from))stop('Expected method artifact missing: ',filename)
  extension<-if(key=='manifest')'manifest.json' else if(key=='data')'derived.csv' else key
  if(!file.copy(from,file.path(if(key%in%c('png','pdf','svg'))b$plots else b$tables,paste0(name,'.',extension)),overwrite=FALSE))stop('Could not copy method output')
 }
}
.runall_matrix <- function(ad) {
 mat<-as.matrix(ad)
 if(!is.numeric(mat)||!length(mat)||any(!is.finite(mat))||any(mat<0))stop('One-click abundance/count input must be finite and nonnegative; no missing values or negative values are repaired')
 if(is.null(rownames(mat))||is.null(colnames(mat))||anyDuplicated(rownames(mat))||anyDuplicated(colnames(mat)))stop('Unique feature and sample IDs are required')
 if(any(colSums(mat)<=0))stop('A sample has zero total abundance')
 mat
}
.runall_heatmap <- function(mat,b,name,top_n=50,title='Top variable features') {
 vars<-apply(mat,1,stats::var);idx<-head(order(-vars,rownames(mat)),top_n);idx<-idx[vars[idx]>0]
 if(length(idx)<2L).runall_skip('Fewer than two nonconstant features are available')
 z<-t(scale(t(mat[idx,,drop=FALSE])));d<-as.data.frame(as.table(z));names(d)<-c('Feature','Sample','Z')
 .runall_table(data.frame(feature=rownames(z),z,check.names=FALSE),b,paste0(name,'_values'))
 p<-ggplot2::ggplot(d,ggplot2::aes(Sample,Feature,fill=Z))+ggplot2::geom_tile()+ggplot2::scale_fill_gradient2(low='#2166ac',mid='white',high='#b2182b',midpoint=0)+ggplot2::labs(title=title,subtitle=paste0('Row Z scores; ',nrow(z),' selected features; no value clipping'),x=NULL,y=NULL)+emp_pub_theme()+ggplot2::theme(axis.text.x=ggplot2::element_text(angle=60,hjust=1),axis.text.y=ggplot2::element_text(size=7))
 .runall_plot(p,b,name,10,max(6,min(14,nrow(z)*.15)))
}
.runall_corr <- function(mat,b,feature_top_n=100,cutoff=.6) {
 vars<-apply(mat,1,stats::var);idx<-head(order(-vars,rownames(mat)),feature_top_n);idx<-idx[vars[idx]>0]
 if(length(idx)<2L).runall_skip('Fewer than two nonconstant features available for correlation')
 m<-suppressWarnings(stats::cor(t(mat[idx,,drop=FALSE]),method='spearman'))
 if(any(!is.finite(m)))stop('Feature correlation contains undefined values')
 .runall_table(data.frame(feature=rownames(m),m,check.names=FALSE),b,'feature_spearman_matrix')
 pairs<-which(upper.tri(m)&abs(m)>=cutoff,arr.ind=TRUE)
 edges<-data.frame(from=rownames(m)[pairs[,1]],to=colnames(m)[pairs[,2]],rho=m[pairs],stringsAsFactors=FALSE)
 .runall_table(edges,b,'feature_network_edges')
 if(!nrow(edges)).runall_skip('No feature pairs pass the descriptive absolute-correlation display cutoff; correlation tables are retained')
 total_edges<-nrow(edges);edges<-head(edges[order(-abs(edges$rho),edges$from,edges$to),,drop=FALSE],500L)
 # The circular layout encodes connectivity only, never biological distance.
 ids<-unique(c(edges$from,edges$to));ang<-2*pi*seq_along(ids)/length(ids);nodes<-data.frame(id=ids,x=cos(ang),y=sin(ang))
 .runall_table(nodes,b,'network_display_nodes')
 edges$x<-nodes$x[match(edges$from,ids)];edges$y<-nodes$y[match(edges$from,ids)];edges$xend<-nodes$x[match(edges$to,ids)];edges$yend<-nodes$y[match(edges$to,ids)]
 p<-ggplot2::ggplot()+ggplot2::geom_segment(data=edges,ggplot2::aes(x,y,xend=xend,yend=yend,color=rho),alpha=.3)+ggplot2::geom_point(data=nodes,ggplot2::aes(x,y),size=2)+ggplot2::scale_color_gradient2(low='#2166ac',mid='white',high='#b2182b',limits=c(-1,1))+ggplot2::coord_equal()+ggplot2::theme_void()+ggplot2::labs(title='Feature correlation network',subtitle=paste0('Top ',length(idx),' variable features; |Spearman rho| >= ',cutoff),caption=paste0('Descriptive associations, no P threshold or causality. Circular positions are not distances.\nDisplaying ',nrow(edges),' / ',total_edges,' edges ranked by |rho|; full edges and node IDs are in tables.'))
 .runall_plot(p,b,'feature_correlation_network')
}
.runall_finish <- function(bundle,engine,session_id,experiment,started) {
 versions<-vapply(c('ggplot2','EasyMultiProfiler','DESeq2','clusterProfiler','vegan','svglite','openxlsx'),function(pkg)if(requireNamespace(pkg,quietly=TRUE))as.character(utils::packageVersion(pkg)) else 'unavailable',character(1))
 files<-list.files(bundle$base,recursive=TRUE,full.names=TRUE);files<-files[!dir.exists(files)]
 counts<-table(factor(vapply(engine$stages,`[[`,character(1),'status'),levels=c('done','skipped','error')))
 elapsed<-as.numeric(difftime(Sys.time(),started,units='secs'))
 cat(sprintf('\nElapsed: %.1fs; done=%d skipped=%d error=%d\n',elapsed,counts[1],counts[2],counts[3]),file=bundle$log,append=TRUE)
 manifest<-list(schema='emp-runall-complete-v2',run_id=bundle$run_id,experiment=experiment,parameters=engine$parameters,stages=engine$stages,counts=as.list(counts),partial=counts['error']>0L,software=as.list(versions),R_version=R.version.string,files=sub(paste0(bundle$base,'/'),'',files,fixed=TRUE),file_md5=as.list(tools::md5sum(files)),plots=list.files(bundle$plots),scientific_scope='Per-stage methods and transformations are recorded; errors and skipped methods do not represent completed analyses')
 jsonlite::write_json(manifest,file.path(bundle$base,'manifest.json'),auto_unbox=TRUE,pretty=TRUE,null='null');capture.output(utils::sessionInfo(),file=file.path(bundle$base,'sessionInfo.txt'))
 zip_path<-file.path(.bundle_root(session_id),paste0(bundle$run_id,'.zip'));zip_dir(bundle$base,zip_path)
 if(!file.exists(zip_path)||file.info(zip_path)$size<=0)stop('Run completed but bundle packaging failed')
 list(success=TRUE,partial=isTRUE(counts['error']>0L),session_id=session_id,experiment=experiment,run_id=bundle$run_id,bundle=bundle$base,zip_path=zip_path,zip_name=basename(zip_path),elapsed_s=round(elapsed,1),stages=engine$stages,counts=as.list(counts),figures=list.files(bundle$plots))
}
.runall_complete <- function(session_id,experiment,omics,parameters) {
 on_progress<-parameters$on_progress;parameters$on_progress<-NULL
 b<-.bundle_init(session_id);cat(paste('EasyMultiProfiler comprehensive',omics,'pipeline\nExperiment:',experiment,'\n'),file=b$log)
 started<-Sys.time();engine<-.runall_engine(b,parameters,on_progress);stage<-engine$stage
 # Keep the caller's RNG unchanged. Every stochastic display uses this seed.
 seed<-as.integer(parameters$seed);if(length(seed)!=1L||!is.finite(seed))stop('Invalid seed')
 old_seed<-if(exists('.Random.seed',.GlobalEnv,inherits=FALSE))get('.Random.seed',.GlobalEnv) else NULL
 on.exit(if(is.null(old_seed)){if(exists('.Random.seed',.GlobalEnv,inherits=FALSE))rm('.Random.seed',envir=.GlobalEnv)}else assign('.Random.seed',old_seed,.GlobalEnv),add=TRUE);set.seed(seed)
 top<-as.integer(parameters$feature_top_n);if(length(top)!=1L||!is.finite(top)||top<2L||top>300L)stop('feature_top_n must be 2–300')
 cutoff<-as.numeric(parameters$network_cutoff);if(length(cutoff)!=1L||!is.finite(cutoff)||cutoff<0||cutoff>1)stop('network_cutoff must be between zero and one')
 is_rna<-omics=='transcriptomics';owner<-tryCatch(emp_get_session_owner(session_id)$owner_id,error=function(e)'local');owner<-owner %||% 'local'
 input<-stage('qc',function(){
   empt<-get_empt_fresh(session_id,experiment);empt<-apply_merged_coldata(session_id,empt)
   audit<-list(source='current reviewed assay')
   if(is_rna){resolved<-.diff_count_input(empt,load_raw_empt(session_id,experiment));empt<-resolved$empt;audit$source<-resolved$source}
   ad<-.runall_matrix(SummarizedExperiment::assays(empt)[[1]]);cd<-as.data.frame(SummarizedExperiment::colData(empt));cd<-cd[colnames(ad),,drop=FALSE]
   .runall_table(data.frame(sample=colnames(ad),library_size=colSums(ad),detected_features=colSums(ad>0)),b,'sample_qc')
   .runall_table(data.frame(feature=rownames(ad),total=rowSums(ad),prevalence=rowMeans(ad>0)),b,'feature_qc')
   .runall_plot(ggplot2::ggplot(data.frame(sample=colnames(ad),total=colSums(ad)),ggplot2::aes(sample,total))+ggplot2::geom_col(fill='#4E79A7')+emp_pub_theme()+ggplot2::labs(title='Sample library size',x=NULL,y='Total abundance')+ggplot2::theme(axis.text.x=ggplot2::element_text(angle=60,hjust=1)),b,'sample_library_size')
   jsonlite::write_json(audit,file.path(b$base,'input_audit.json'),auto_unbox=TRUE,pretty=TRUE)
   list(ad=ad,cd=cd,empt=empt)
 })
 need<-function(){if(is.null(input)).runall_skip('Input QC failed; inspect the qc stage');input}
 stage('metadata',function(){x<-need();.runall_table(data.frame(sample=rownames(x$cd),x$cd,check.names=FALSE),b,'sample_metadata');.runall_table(data.frame(feature=rownames(x$ad)),b,'feature_identifiers')})
 group<-parameters$group_var;group_values<-if(!is.null(input)&&!is.null(group)&&nzchar(group)&&group%in%names(input$cd))as.character(input$cd[[group]]) else NULL
 working<-if(!is.null(input))if(is_rna)log2(sweep(input$ad,2,colSums(input$ad)/1e6,'/')+1) else sweep(input$ad,2,colSums(input$ad),'/') else NULL
 .ordination<-function(method){
   x<-need();mat<-t(working);if(nrow(mat)<3L||ncol(mat)<2L).runall_skip('At least three samples and two features are required')
   if(method=='PCA'){vars<-apply(mat,2,stats::var);fit<-stats::prcomp(mat[,vars>0,drop=FALSE],center=TRUE,scale.=FALSE);coords<-fit$x[,1:2,drop=FALSE];v<-fit$sdev^2/sum(fit$sdev^2);axis<-sprintf('PC%d (%.1f%%)',1:2,v[1:2]*100)}else{
    if(!requireNamespace('vegan',quietly=TRUE)).runall_skip('vegan is unavailable for Bray-Curtis beta diversity')
    if(!identical(tolower(parameters$beta_method),'bray')).runall_skip('This audited beta display currently supports explicit Bray-Curtis only')
    dist<-vegan::vegdist(mat,method='bray')
    if(method=='PCOA'){fit<-stats::cmdscale(dist,k=2,eig=TRUE);coords<-fit$points;axis<-c('PCo1','PCo2');.runall_table(data.frame(eigenvalue=fit$eig),b,'beta_pcoa_eigenvalues')}else{fit<-vegan::metaMDS(dist,k=2,trace=0,autotransform=FALSE);coords<-fit$points;axis<-c('NMDS1','NMDS2');.runall_table(data.frame(stress=fit$stress),b,'beta_nmds_stress')}
   }
   d<-data.frame(sample=rownames(coords),Axis1=coords[,1],Axis2=coords[,2],group=if(is.null(group_values))'All' else group_values)
   .runall_table(d,b,paste0(tolower(method),'_coordinates'))
   p<-ggplot2::ggplot(d,ggplot2::aes(Axis1,Axis2,color=group))+ggplot2::geom_point(size=3)+emp_pub_theme()+ggplot2::labs(title=method,subtitle=if(is_rna)'log2(CPM + 1); display only, raw counts used for differential analysis' else 'Sample relative abundance; no feature imputation',x=axis[1],y=axis[2],color=group)
   .runall_plot(p,b,paste0(tolower(method),'_scatter'));d
 }
 if(is_rna)stage('pca',function().ordination('PCA')) else for(m in c('PCA','PCOA','NMDS'))stage(paste0('beta_',tolower(m)),local({method<-m;function().ordination(method)}))
 stage('sample_correlation',function(){need();m<-suppressWarnings(stats::cor(working,method='spearman'));if(any(!is.finite(m)))stop('Undefined sample correlation; inspect constant sample profiles');.runall_table(data.frame(sample=rownames(m),m,check.names=FALSE),b,'sample_spearman');d<-as.data.frame(as.table(m));names(d)<-c('Sample1','Sample2','rho');.runall_plot(ggplot2::ggplot(d,ggplot2::aes(Sample1,Sample2,fill=rho))+ggplot2::geom_tile()+ggplot2::scale_fill_gradient2(low='#2166ac',mid='white',high='#b2182b',limits=c(-1,1))+emp_pub_theme()+ggplot2::theme(axis.text.x=ggplot2::element_text(angle=60,hjust=1))+ggplot2::labs(title='Sample Spearman correlation'),b,'sample_correlation')},parameters$do_correlation)
 stage('sample_clustering',function(){need();if(ncol(working)<3).runall_skip('Clustering requires at least three samples');vars<-apply(working,1,stats::var);idx<-head(order(-vars),top);idx<-idx[vars[idx]>0];if(length(idx)<2).runall_skip('Fewer than two varying features');hc<-stats::hclust(stats::dist(t(working[idx,,drop=FALSE])),method='ward.D2');saveRDS(hc,file.path(b$tables,'sample_hclust.rds'));.runall_table(data.frame(sample=names(stats::cutree(hc,k=2)),cluster=stats::cutree(hc,k=2)),b,'sample_clusters');for(ext in c('pdf','png','svg')){path<-file.path(b$plots,paste0('sample_dendrogram.',ext));if(ext=='pdf')grDevices::pdf(path,width=9,height=6)else if(ext=='svg'){if(!requireNamespace('svglite',quietly=TRUE))stop('svglite unavailable');svglite::svglite(path,width=9,height=6)}else if(requireNamespace('ragg',quietly=TRUE))ragg::agg_png(path,width=9,height=6,units='in',res=300)else grDevices::png(path,width=2700,height=1800);tryCatch(plot(hc,main=paste0('Sample clustering; Top ',length(idx),' varying features'),xlab='',sub='Ward D2 / Euclidean; descriptive clustering'),finally=grDevices::dev.off())}},parameters$do_cluster)
 stage('feature_correlation_network',function(){need();.runall_corr(working,b,top,cutoff)},parameters$do_correlation)
 stage('top_variance_heatmap',function(){need();.runall_heatmap(working,b,'top_variance_heatmap',min(top,50),'Top variable features; transformed display data')})
 if(!is_rna){
  taxonomy_result<-stage('taxonomy',function(){x<-need();prepared<-m16s_prepare_taxonomy(x$empt,collapse_level=parameters$taxonomy_level,keep_top_n=0L,drop_unassigned=FALSE);mat<-SummarizedExperiment::assays(prepared)[[1]];.runall_table(data.frame(taxon=rownames(mat),as.matrix(mat),check.names=FALSE),b,'taxonomy_abundance');list(matrix=as.matrix(mat),n_taxa=nrow(mat),scope='Local aggregation; full assay and raw counts unchanged')})
  stage('beta_group_test',function(){need();if(is.null(group_values)||anyNA(group_values)||length(unique(group_values))<2L||any(table(group_values)<2L)).runall_skip('PERMANOVA and dispersion require reviewed complete groups with at least two samples per group');if(!requireNamespace('vegan',quietly=TRUE)).runall_skip('vegan is unavailable');if(!identical(tolower(parameters$beta_method),'bray')).runall_skip('This group test uses explicit Bray-Curtis only');distance<-vegan::vegdist(t(working),method='bray');meta<-data.frame(group=factor(group_values));test<-vegan::adonis2(distance~group,data=meta,permutations=999);disp<-vegan::betadisper(distance,meta$group);disp_test<-vegan::permutest(disp,permutations=999);saveRDS(list(permanova=test,dispersion=disp,dispersion_test=disp_test,requested_permutations=999L,seed=seed),file.path(b$tables,'beta_group_test_objects.rds'));.runall_table(data.frame(term=rownames(as.data.frame(test)),as.data.frame(test),check.names=FALSE),b,'permanova_bray');.runall_table(data.frame(term=rownames(as.data.frame(disp_test$tab)),as.data.frame(disp_test$tab),check.names=FALSE),b,'beta_dispersion_test');writeLines('Up to 999 unrestricted permutations (complete enumeration for small permutation spaces); assumes independent exchangeable samples. No batch, pairing, repeated-measure, or covariate adjustment. PERMANOVA must be interpreted with dispersion results; not a causal test.',file.path(b$tables,'beta_test_assumptions.txt'))})
  stage('alpha',function(){x<-need();if(!requireNamespace('vegan',quietly=TRUE)).runall_skip('vegan package unavailable');mat<-t(x$ad);d<-data.frame(sample=rownames(mat),observed=rowSums(mat>0),shannon=vegan::diversity(mat,index='shannon'),simpson=vegan::diversity(mat,index='simpson'),invsimpson=vegan::diversity(mat,index='invsimpson'));d$pielou<-ifelse(d$observed>1,d$shannon/log(d$observed),NA_real_)
   if(all(mat==floor(mat))){rich<-t(vegan::estimateR(mat));d$chao1<-rich[,'S.chao1'];d$ace<-rich[,'S.ACE']}else warning('Chao1/ACE skipped because the input is not integer counts')
   .runall_table(d,b,'alpha_indices');for(metric in setdiff(names(d),'sample')){
    if(!any(is.finite(d[[metric]])))next
    plotdata<-data.frame(sample=d$sample,value=d[[metric]],group=if(is.null(group_values))'All' else group_values)
    .runall_plot(ggplot2::ggplot(plotdata,ggplot2::aes(group,value,color=group))+ggplot2::geom_boxplot(outlier.shape=NA)+ggplot2::geom_jitter(width=.15)+emp_pub_theme()+ggplot2::labs(title=paste('Alpha diversity:',metric),x=group,y=metric,caption='Descriptive values; no group test implied'),b,paste0('alpha_',metric),7,5)
   }
  })
  stage('composition',function(){x<-need();if(is.null(taxonomy_result)).runall_skip('Taxonomy aggregation failed; no taxonomic classifications are invented');mat<-sweep(taxonomy_result$matrix,2,colSums(taxonomy_result$matrix),'/');idx<-head(order(-rowMeans(mat)),min(top,15L));out<-mat[idx,,drop=FALSE];other<-1-colSums(out);out<-rbind(out,Other=other);d<-as.data.frame(as.table(out));names(d)<-c('Feature','Sample','RelativeAbundance');.runall_table(d,b,'composition_relative_abundance');.runall_plot(ggplot2::ggplot(d,ggplot2::aes(Sample,RelativeAbundance,fill=Feature))+ggplot2::geom_col()+ggplot2::labs(title='Top taxa and Other',y='Relative abundance',x=NULL)+emp_pub_theme()+ggplot2::theme(axis.text.x=ggplot2::element_text(angle=60,hjust=1)),b,'composition')})
  stage('ternary',function(){x<-need();if(is.null(group_values)||anyNA(group_values)).runall_skip('Reviewed sample groups are required');groups<-as.character(unlist(parameters$ternary_groups));if(!length(groups)){groups<-unique(group_values);if(length(groups)!=3L).runall_skip('Exactly three groups, or an explicit ternary_groups selection, are required; no groups were guessed')}
   if(length(groups)!=3L||anyDuplicated(groups)||any(!groups%in%group_values))stop('ternary_groups must select three distinct existing groups')
   if(!nzchar(Sys.getenv('EMP_FIGURE_METHODS_ROOT',''))).runall_skip('Live Figure Methods Lab is not configured')
   out<-emp_viz_method_library(list(method='ternary',session_id=session_id,experiment=experiment,omics=omics,group_var=group,groups=groups,top_n=min(top,100)),owner);.runall_copy_method(out,b,'ternary',session_id)
  },parameters$do_method_figures)
 }
 diff_result<-stage('differential',function(){need();if(is.null(group_values)||anyNA(group_values)||any(!nzchar(group_values))||length(unique(group_values))<2L).runall_skip('An explicitly selected reviewed group variable with at least two complete groups is required')
   if(is_rna){ref<-parameters$ref_group;test<-parameters$test_group
    if(length(unique(group_values))!=2L&&(is.null(ref)||is.null(test))).runall_skip('More than two groups: select explicit reference/test groups for this one-click contrast; use the analysis workspace for multiple contrasts')
    selected_groups<-if(!is.null(ref)&&!is.null(test))group_values[group_values%in%c(ref,test)] else group_values
    if(any(table(selected_groups)<2L)).runall_skip('Differential count analysis requires independent biological replicates; at least two samples per selected group')
    if(!requireNamespace('DESeq2',quietly=TRUE)).runall_skip('DESeq2 is not installed; no substitute differential method was run')
    result<-run_diff(session_id,experiment,method='DESeq2',group_var=group,ref_group=ref,test_group=test,filter_low=TRUE,subset_two_groups=TRUE,cores='auto')
   }else{
    # Explicit microbial tests avoid EMP's two-group routing/fallback when
    # three or more reviewed groups require an omnibus Kruskal-Wallis test.
    microbial<-.runall_microbial_diff(working,group_values)
    result<-microbial$data
    .save_diff_raw_cache(session_id,experiment,microbial$method,group,microbial$ref_group,microbial$test_group,result,comparison_mode=if(length(unique(group_values))==2L)'pairwise' else 'omnibus_kruskal')
   }
   .runall_table(as.data.frame(result),b,'differential_compact');raw<-load_diff_raw(session_id,experiment)
   if(!is.null(raw$data)) .runall_table(raw$data,b,'differential_raw')
   saveRDS(list(compact=result,raw=raw),file.path(b$tables,'differential_result.rds'));list(result=result,raw=raw)
 })
 need_diff<-function(){if(is.null(diff_result)).runall_skip('Differential analysis did not complete during this run; old cached results are not reused');if(is.null(diff_result$raw$data)||!nrow(diff_result$raw$data)).runall_skip('This differential method has no compatible feature/FC/P table');if(!any(is.finite(diff_result$raw$data$log2FoldChange))).runall_skip('Omnibus multi-group results have no single fold-change direction; no two-group volcano or DEG heatmap is inferred');diff_result$raw}
 stage('volcano',function(){need_diff();p<-.make_volcano_plot(session_id,experiment,fc_cutoff=parameters$fc_cutoff %||% 1,p_cutoff=parameters$p_cutoff %||% .05,use_padj=parameters$use_padj %||% TRUE);.runall_plot(p,b,'volcano',8,7)})
 stage('deg_heatmap',function(){raw<-need_diff();pv<-.viz_selected_p(raw$data,parameters$use_padj %||% TRUE);fc<-as.numeric(raw$data$log2FoldChange);ids<-raw$data$feature[is.finite(pv)&is.finite(fc)&pv<(parameters$p_cutoff %||% .05)&abs(fc)>=(parameters$fc_cutoff %||% 1)];ids<-intersect(ids,rownames(working));if(length(ids)<2L).runall_skip('Fewer than two features pass the selected FC/adjusted-P cutoffs; no raw-P fallback');.runall_heatmap(working[ids,,drop=FALSE],b,'deg_heatmap',50,'Differential-feature heatmap; row Z scores')})
 if(is_rna){
  stage('de_significance_scatter',function(){need_diff();if(!nzchar(Sys.getenv('EMP_FIGURE_METHODS_ROOT',''))).runall_skip('Live Figure Methods Lab is not configured');out<-emp_viz_method_library(list(method='de_scatter',session_id=session_id,experiment=experiment,omics=omics,p_cutoff=parameters$p_cutoff,fc_cutoff=parameters$fc_cutoff),owner);.runall_copy_method(out,b,'de_significance_scatter',session_id)},parameters$do_method_figures)
  for(database in c('KEGG','GO_BP')){
   stage_id<-if(database=='KEGG')'ora_kegg' else 'ora_go'
   result<-stage(stage_id,local({db<-database;id<-stage_id;function(){raw<-need_diff();selected<-.enrich_select_degs(raw,parameters$fc_cutoff,parameters$p_cutoff,parameters$use_padj);if(!nrow(selected)).runall_skip('No DEGs meet the selected FC/adjusted-P thresholds; no raw-P fallback');.runall_annotation_ready(parameters$organism);out<-run_enrichment(session_id,experiment,database=db,organism=parameters$organism,fc_cutoff=parameters$fc_cutoff,p_cutoff=parameters$p_cutoff,use_padj=parameters$use_padj,top_n=50L);.runall_table(out$data,b,id);saveRDS(out,file.path(b$tables,paste0(id,'.rds')));out}}),parameters$do_enrichment)
   stage(paste0(stage_id,'_plot'),local({value<-result;id<-stage_id;function(){if(is.null(value)).runall_skip('Enrichment analysis unavailable or disabled');if(!nrow(value$data)).runall_skip('No enriched terms were returned');d<-.enrich_viz_normalize(value$data);d<-head(d[order(d[['p.adjust']]),,drop=FALSE],20L);d$term<-factor(d$ID,levels=rev(d$ID));p<-ggplot2::ggplot(d,ggplot2::aes(gene_ratio,term,size=Count,color=-log10(pmax(p.adjust,1e-300))))+ggplot2::geom_point()+ggplot2::scale_size_area(max_size=10)+ggplot2::scale_color_gradient(low='#554A9A',high='#E52449')+ggplot2::scale_y_discrete(labels=stats::setNames(vapply(d$Description,function(x)paste(strwrap(x,40),collapse='\n'),character(1)),d$ID))+ggplot2::labs(title=paste(value$database,'enrichment'),x='Gene ratio',y=NULL,color='-log10 adjusted P',size='Gene count')+emp_pub_theme();.runall_plot(p,b,id,10,9)}}),parameters$do_enrichment)
  }
  gsea<-stage('gsea_analysis',function(){need_diff();.runall_annotation_ready(parameters$organism);out<-emp_run_gsea(session_id,experiment,database=parameters$gsea_database,organism=parameters$organism,seed=seed);d<-if(is.character(out$data))jsonlite::fromJSON(out$data) else out$data;.runall_table(d,b,'gsea_result');saveRDS(out,file.path(b$tables,'gsea_result.rds'));out},parameters$do_gsea,'Disabled by run parameters; full-rank GSEA can be slow and requires species annotation')
  stage('gsea_curves',function(){if(is.null(gsea)).runall_skip('GSEA analysis did not complete during this run');saved<-emp_load_gsea(session_id,experiment);d<-as.data.frame(methods::slot(saved$object,'result'));if(!nrow(d)).runall_skip('No GSEA gene sets available');d<-d[order(d[['p.adjust']]),,drop=FALSE];for(id in head(as.character(d$ID),min(10L,as.integer(parameters$gsea_top_n)))){out<-enrich_viz_gsea(list(session_id=session_id,experiment=experiment,source_job='current_gsea',set_id=id),owner);.runall_copy_method(out,b,paste0('gsea_',make.names(id)),session_id)}},parameters$do_gsea)
 }
 if(is.function(on_progress))on_progress(97L,'Writing per-stage manifest and packaging verified outputs')
 result<-.runall_finish(b,engine,session_id,experiment,started)
 if(is.function(on_progress))on_progress(100L,paste('Completed bundle;',result$counts$error,'stage errors;',result$counts$skipped,'skipped'))
 result
}

.runall_microbial_diff <- function(relative,groups) {
 if(any(!is.finite(relative))||anyNA(groups))stop('Microbial tests require complete finite data and groups')
 levels<-unique(as.character(groups));if(length(levels)<2L)stop('At least two groups required')
 method<-if(length(levels)==2L)'wilcox.test (relative abundance)' else 'kruskal.test (all reviewed groups; relative abundance)'
 tests<-lapply(seq_len(nrow(relative)),function(i){
  values<-relative[i,]
  if(length(unique(values))==1L)return(c(stat=NA_real_,pvalue=NA_real_))
  test<-if(length(levels)==2L)stats::wilcox.test(values[groups==levels[2]],values[groups==levels[1]],exact=FALSE) else stats::kruskal.test(values,as.factor(groups))
  c(stat=as.numeric(test$statistic),pvalue=test$p.value)
 })
 stats<-do.call(rbind,tests)
 fc<-if(length(levels)==2L)log2(rowMeans(relative[,groups==levels[2],drop=FALSE])/rowMeans(relative[,groups==levels[1],drop=FALSE])) else rep(NA_real_,nrow(relative))
 d<-data.frame(feature=rownames(relative),symbol=rownames(relative),baseMean=rowMeans(relative),log2FoldChange=fc,stat=stats[,'stat'],pvalue=stats[,'pvalue'],padj=stats::p.adjust(stats[,'pvalue'],'BH'),test_status=ifelse(is.finite(stats[,'pvalue']),'tested','constant or undefined; not tested'),stringsAsFactors=FALSE)
 list(data=d,method=method,ref_group=if(length(levels)==2L)levels[1] else NULL,test_group=if(length(levels)==2L)levels[2] else NULL)
}

.runall_annotation_ready <- function(organism) {
 if(!requireNamespace('clusterProfiler',quietly=TRUE)).runall_skip('clusterProfiler is unavailable; no analysis dependency was installed automatically')
 pkg<-.enrich_orgdb(normalize_species(organism))
 if(is.na(pkg)||!requireNamespace(pkg,quietly=TRUE)).runall_skip(paste('Species annotation package unavailable:',pkg))
}
