# Live adapters to the administrator-configured Figure_Methods_Lab.
# Request data cannot select R sources/config files. Frozen input CSVs and code
# hashes are retained for each iteration; existing input/results are untouched.
emp_viz_method_catalog <- function() {
  list(schema='emp-figure-method-catalog-v1',available=nzchar(Sys.getenv('EMP_FIGURE_METHODS_ROOT',''))&&file.exists(file.path(Sys.getenv('EMP_FIGURE_METHODS_ROOT',''),'library/plot_methods.R')),status=if(nzchar(Sys.getenv('EMP_FIGURE_METHODS_ROOT',''))) 'configured' else 'not_configured',methods=list(
    list(id='ternary',omics=c('microbiome_16s','metagenomics'),label='Three-group composition bubbles',required_input='Nonnegative abundance assay with finite values and exactly three selected metadata groups',statistics='Descriptive composition; no differential or significance test'),
    list(id='de_scatter',omics=c('transcriptomics','proteomics','metabolomics'),label='Differential significance scatter',required_input='Existing reviewed differential result with unique feature IDs, finite log2FC and 0 < adjusted P <= 1',statistics='Frozen external statistics; no model refit or multiple-testing recomputation')))
}
.method_library_num <- function(x,default,min,max,name,integer=FALSE) {
  v<-suppressWarnings(as.numeric(x %||% default))
  if(length(v)!=1L||!is.finite(v)||v<min||v>max||(integer&&v!=floor(v)))stop(name,' must be ',if(integer)'an integer ' else '', 'between ',min,' and ',max)
  v
}
.method_library_text <- function(x,default='',limit=300L) {
  v<-as.character(x %||% default);if(length(v)!=1L||is.na(v)||nchar(v)>limit)stop('Invalid figure text');v
}
.method_library_colors <- function(x,defaults) {
  vals<-as.character(unlist(x %||% defaults));if(length(vals)!=length(defaults)||anyNA(vals))stop('Palette has an incorrect number of colors')
  for(v in vals)tryCatch(grDevices::col2rgb(v),error=function(e)stop('Invalid palette color'))
  stats::setNames(vals,names(defaults))
}
.method_library_load <- function(method) {
  root<-trimws(Sys.getenv('EMP_FIGURE_METHODS_ROOT',''));if(!nzchar(root))stop('Configure EMP_FIGURE_METHODS_ROOT to use the live methods library')
  root<-normalizePath(path.expand(root),winslash='/',mustWork=TRUE)
  skill<-switch(method,ternary='omics-ternary-bubbles',de_scatter='omics-de-significance-scatter',stop('Unsupported method'))
  paths<-file.path(root,c('AGENTS.md','METHODS.md','skills/figure-reproduction/SKILL.md',paste0('skills/',skill,'/SKILL.md'),'library/common.R','library/plot_methods.R'))
  if(any(!file.exists(paths)|dir.exists(paths)))stop('The configured methods library is incomplete')
  e<-new.env(parent=globalenv());sys.source(file.path(root,'library/common.R'),envir=e);sys.source(file.path(root,'library/plot_methods.R'),envir=e)
  if(!is.function(e[[paste0('plot_',method)]])||!is.function(e$export_figure))stop('The live library does not expose the selected method/export')
  list(environment=e,root=root,code_md5=as.list(tools::md5sum(paths)))
}
.method_library_ternary_data <- function(ad,cd,b) {
  if(!b$omics%in%c('microbiome_16s','metagenomics'))stop('Ternary composition is limited to microbiome and metagenomics abundance inputs')
  group_var<-.method_library_text(b$group_var,limit=100L);groups<-as.character(unlist(b$groups))
  if(length(groups)!=3L||anyNA(groups)||any(!nzchar(groups))||anyDuplicated(groups))stop('Select exactly three distinct groups, ordered top A, left B, right C')
  if(!group_var%in%names(cd))stop('Selected group variable is missing from sample metadata')
  ad<-as.matrix(ad)
  if(!is.numeric(ad)||!length(ad)||any(!is.finite(ad))||any(ad<0))stop('Ternary abundance requires finite nonnegative values; CLR/negative values and missing values are not repaired')
  if(is.null(rownames(ad))||anyDuplicated(rownames(ad))||any(!nzchar(rownames(ad))))stop('Feature IDs must be nonempty and unique')
  if(is.null(colnames(ad))||is.null(rownames(cd))||anyDuplicated(colnames(ad))||!all(colnames(ad)%in%rownames(cd)))stop('Assay samples must match unique metadata sample IDs')
  cd<-cd[match(colnames(ad),rownames(cd)),,drop=FALSE]
  group<-as.character(cd[[group_var]])
  if(anyNA(group)||any(!nzchar(group)))stop('Sample group labels contain missing values; resolve explicitly')
  n<-vapply(groups,function(g)sum(group==g),integer(1));if(any(n<1L))stop('Each selected group requires at least one sample')
  chosen<-group%in%groups;totals<-colSums(ad[,chosen,drop=FALSE]);if(any(!is.finite(totals)|totals<=0))stop('A selected sample has a zero or invalid library total')
  relative<-sweep(ad[,chosen,drop=FALSE],2,totals,'/');group<-group[chosen]
  means<-vapply(groups,function(g)rowMeans(relative[,group==g,drop=FALSE]),numeric(nrow(relative)))
  means<-matrix(means,nrow=nrow(relative),ncol=3L)
  rownames(means)<-rownames(ad);colnames(means)<-c('A','B','C')
  size<-rowMeans(means);present<-rowSums(means)>0
  omitted<-rownames(means)[!present];means<-means[present,,drop=FALSE];size<-size[present]
  if(!nrow(means))stop('No features have positive mean abundance in the selected groups')
  composition<-means/rowSums(means)
  dominant<-apply(means,1,function(x){w<-which(x==max(x));if(length(w)==1L)groups[w] else 'Unclassified'})
  d<-data.frame(feature_id=rownames(means),A=composition[,1],B=composition[,2],C=composition[,3],class=dominant,size=size,stringsAsFactors=FALSE,row.names=NULL)
  top<-.method_library_num(b$top_n,100,1,100,'top_n',TRUE)
  selected<-head(order(-d$size,d$feature_id),top);d<-d[selected,,drop=FALSE]
  list(data=d,groups=groups,source=list(group_var=group_var,vertex_groups=as.list(stats::setNames(groups,c('A_top','B_left','C_right'))),group_sample_counts=as.list(stats::setNames(n,groups)),normalization='Each selected sample divided by its original total abundance; feature means computed within groups; A/B/C are the three means normalized to sum to one',size_unit='Equal-weight mean of the three group mean relative abundances (fraction)',color_meaning='Dominant mean abundance group; tied maxima are Unclassified, not a taxonomic class',zero_feature_exclusions=omitted,top_n_display=nrow(d),n_positive_features=nrow(means),excluded_other_group_samples=sum(!chosen),raw_input_unchanged=TRUE))
}
.method_library_de_data <- function(raw,b) {
  if(!b$omics%in%c('transcriptomics','proteomics','metabolomics'))stop('This differential result view is available for transcriptomics, proteomics, and metabolomics')
  if(is.null(raw$data)||!is.data.frame(raw$data)||!nrow(raw$data))stop('Run and review differential analysis before using this plot')
  input<-raw$data
  if(!all(c('feature','log2FoldChange','padj')%in%names(input)))stop('Stored differential table needs feature, log2FoldChange and padj')
  d<-data.frame(gene_id=as.character(input$feature),log2FC=suppressWarnings(as.numeric(input$log2FoldChange)),padj=suppressWarnings(as.numeric(input$padj)),stringsAsFactors=FALSE)
  if(anyNA(d$gene_id)||any(!nzchar(d$gene_id))||anyDuplicated(d$gene_id))stop('Differential feature IDs must be nonempty and unique')
  full_input<-d
  missing_p<-is.na(d$padj)
  exclusions<-data.frame(feature_id=d$gene_id[missing_p],reason=rep('Adjusted P unavailable; not plotted, not imputed',sum(missing_p)),stringsAsFactors=FALSE)
  if(any(missing_p)&&isTRUE(b$exclude_unavailable_p))d<-d[!missing_p,,drop=FALSE]
  if(!nrow(d))stop('No features have available adjusted P values for plotting')
  bad<-!is.finite(d$log2FC)|!is.finite(d$padj)|d$padj<=0|d$padj>1
  if(any(bad))stop(sum(bad),' differential rows have nonfinite FC or adjusted P outside (0,1]; review these results explicitly. No rows or statistics were silently changed')
  list(data=d,full_input=full_input,exclusions=exclusions,source=list(input_rows=nrow(full_input),plotted_rows=nrow(d),excluded_unavailable_p=if(isTRUE(b$exclude_unavailable_p))sum(missing_p) else 0L,exclusion_policy=if(isTRUE(b$exclude_unavailable_p))'Explicit user option: exclude NA adjusted P only; preserve full input and exclusion CSV' else 'Strict validation; no exclusions',statistics='Frozen differential results; adjusted P and log2FC are unchanged; no fitting or BH recomputation',method=raw$method %||% NULL,reference_group=raw$ref_group %||% NULL,test_group=raw$test_group %||% NULL,group_var=raw$group_var %||% NULL,n_features=nrow(d),input_audit=raw$input_audit %||% NULL))
}
emp_viz_method_library <- function(b,owner_id) {
  emp_assert_session_owner(b$session_id,owner_id)
  method<-.method_library_text(b$method)
  b$omics<-.method_library_text(b$omics)
  if(!nzchar(b$omics))stop('Select the omics-specific visualization section first')
  library<-.method_library_load(method)
  # The current experiment is the only data source; no client-supplied path.
  if(method=='ternary'){
    empt<-get_empt(b$session_id,b$experiment)
    source<-.method_library_ternary_data(SummarizedExperiment::assays(empt)[[1]],as.data.frame(SummarizedExperiment::colData(empt)),b)
    colors<-.method_library_colors(b$group_colors,stats::setNames(c('#4E79A7','#F28E2B','#59A14F'),source$groups));colors<-c(colors,Unclassified='#999999')
    labels<-as.character(unlist(b$label_features %||% character()));if(length(setdiff(labels,source$data$feature_id)))stop('Label feature IDs must be present in the displayed top features')
    specific<-list(vertex_labels=vapply(source$groups,function(x)paste(strwrap(x,width=18),collapse='\n'),character(1)),label_features=if(length(labels))labels else NULL,max_point_size=.method_library_num(b$max_point_size,10,1,25,'max_point_size'),point_alpha=.method_library_num(b$point_alpha,.7,.05,1,'point_alpha'),size_label='Mean relative abundance\n(fraction; equal group weights)')
    filename<-'composition.csv';default_title<-'Three-group composition';input_name<-'ternary'
  }else if(method=='de_scatter'){
    raw<-load_diff_raw(b$session_id,b$experiment);source<-.method_library_de_data(raw,b)
    colors<-.method_library_colors(c(b$up_color %||% '#E6583D',b$down_color %||% '#2387B5',b$ns_color %||% '#879393'),c(Up='',Down='',NS=''))
    transform<-.method_library_text(b$x_transform,'sqrt');if(!transform%in%c('sqrt','linear'))stop('x_transform must be sqrt or linear')
    labels<-as.character(unlist(b$label_genes %||% character()));if(length(setdiff(labels,source$data$gene_id)))stop('Requested label IDs are absent from the differential result')
    specific<-list(padj_threshold=.method_library_num(b$p_cutoff %||% b$padj_threshold,.05,1e-12,1,'p_cutoff'),lfc_threshold=.method_library_num(b$fc_cutoff %||% b$lfc_threshold,1,1e-12,1000,'fc_cutoff'),x_transform=transform,point_size=.method_library_num(b$point_size,1.2,.1,8,'point_size'),n_labels=.method_library_num(b$n_labels,8,0,100,'n_labels',TRUE),label_genes=if(length(labels))labels else NULL)
    filename<-'de_results.csv';default_title<-'Differential significance scatter';input_name<-'de_scatter'
  }else stop('Unsupported live method')
  config<-list(method=input_name,seed=1,data_kind='user_supplied',title=.method_library_text(b$title,default_title),subtitle=.method_library_text(b$subtitle),width=.method_library_num(b$width,9,3,20,'width'),height=.method_library_num(b$height,7,3,20,'height'),dpi=300,base_size=.method_library_num(b$base_size,12,6,30,'base_size'),palette=colors,labels=list(),specific=specific)
  dir<-file.path(session_path(b$session_id),'plots');dir.create(dir,recursive=TRUE,showWarnings=FALSE)
  prefix<-basename(tempfile('method_plot_',tmpdir=dir));case<-file.path(dir,paste0(prefix,'_case'));dir.create(file.path(case,'data'),recursive=TRUE);output<-file.path(case,'output');dir.create(output)
  utils::write.csv(source$data,file.path(case,'data',filename),row.names=FALSE)
  if(method=='de_scatter'){
    utils::write.csv(source$full_input,file.path(case,'data','full_differential_input.csv'),row.names=FALSE)
    utils::write.csv(source$exclusions,file.path(output,'derived_excluded_unavailable_p.csv'),row.names=FALSE)
  }
  saveRDS(config,file.path(case,'config.rds'));writeLines(capture.output(dput(config)),file.path(case,'config.R'))
  # Calls the latest shared implementation at the configured trusted root.
  p<-library$environment[[paste0('plot_',input_name)]](case,config,output)
  p<-p+ggplot2::labs(title=paste(strwrap(config$title,width=48),collapse='\n'))+ggplot2::theme(plot.margin=ggplot2::margin(12,18,12,18),plot.caption=ggplot2::element_text(hjust=0,size=9))
  if(method=='de_scatter'&&source$source$excluded_unavailable_p>0)p<-p+ggplot2::labs(subtitle=sprintf('%d / %d features plotted; %d unavailable adjusted P values excluded (audited).',nrow(source$data),source$source$input_rows,source$source$excluded_unavailable_p))
  if(method=='ternary')p<-p+ggplot2::labs(color='Dominant group',caption='Color: highest group mean; not a taxonomic class.\nTied group means: Unclassified.')+ggplot2::theme(legend.position='bottom',legend.box='vertical',legend.title=ggplot2::element_text(size=config$base_size-1),legend.text=ggplot2::element_text(size=config$base_size-2))
  library$environment$export_figure(p,output,config)
  files<-stats::setNames(paste0(prefix,c('.png','.pdf','.svg','.manifest.json','.derived.csv')),c('png','pdf','svg','manifest','data'))
  paths<-file.path(dir,files);names(paths)<-names(files)
  expected<-file.path(output,paste0('figure.',c('png','pdf','svg')))
  if(!all(file.exists(expected))||any(file.info(expected)$size<=0))stop('The live method library did not produce all nonempty figure exports')
  for(ext in c('png','pdf','svg'))if(!file.copy(file.path(output,paste0('figure.',ext)),paths[ext],overwrite=FALSE))stop('Could not preserve exported ',ext)
  derived<-file.path(output,if(method=='ternary')'derived_ternary_coordinates.csv' else 'derived_de_classification.csv')
  if(!file.exists(derived)||!file.copy(derived,paths['data'],overwrite=FALSE))stop('Live library did not produce the expected derived table')
  audit<-c(list(session_id=b$session_id,experiment=b$experiment,omics=b$omics,method=method),source$source)
  manifest<-list(schema='emp-live-method-figure-v1',created_utc=format(Sys.time(),tz='UTC',usetz=TRUE),data_kind='user_supplied',source=audit,parameters=config,library_root=library$root,code_md5=library$code_md5,input_md5=as.list(tools::md5sum(list.files(file.path(case,'data'),full.names=TRUE))),derived_files=list.files(output,pattern='^derived_',full.names=FALSE),case_directory=basename(case),R_version=R.version.string,package_versions=as.list(vapply(c('ggplot2','ggrepel','svglite'),function(x)as.character(utils::packageVersion(x)),character(1))))
  jsonlite::write_json(manifest,paths['manifest'],auto_unbox=TRUE,pretty=TRUE,null='null');capture.output(utils::sessionInfo(),file=file.path(case,'sessionInfo.txt'))
  list(success=TRUE,plot=base64enc::base64encode(paths['png']),download_urls=lapply(files,function(f)paste0('/api/visualize/method-library/file/',b$session_id,'/',f)),parameters=config,source=audit,n_rows=nrow(source$data),pdf_available=TRUE,pdf_name=unname(files['pdf']),svg_available=TRUE,svg_name=unname(files['svg']))
}
