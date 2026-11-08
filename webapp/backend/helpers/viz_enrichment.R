# Publication figures from frozen ORA results or an explicit complete ranked list.
# Plotting never converts ORA geneID hits into a GSEA universe or estimates NES/FDR.
.enrich_viz_num <- function(x, default, lower, upper, name) {
  v <- suppressWarnings(as.numeric(x %||% default))
  if(length(v)!=1L || !is.finite(v) || v<lower || v>upper) stop(name, ' must be between ',lower,' and ',upper)
  v
}
.enrich_viz_text <- function(x, default='', max_length=300L) {
  v <- as.character(x %||% default)
  if(length(v)!=1L || is.na(v) || nchar(v)>max_length) stop('Invalid figure text')
  v
}
.enrich_viz_color <- function(x, default) {
  v <- .enrich_viz_text(x,default,30L)
  tryCatch(grDevices::col2rgb(v),error=function(e)stop('Invalid color: ',v));v
}
.enrich_viz_rows <- function(result) {
  d <- if(is.data.frame(result))result else result$data
  if(is.character(d)&&length(d)==1L) d <- jsonlite::fromJSON(d)
  if(!is.data.frame(d)) stop('Saved enrichment source has no result table')
  d
}
.enrich_viz_canonical_omics <- function(x) {
  value<-tolower(trimws(as.character(x %||% '')))
  known<-c('transcriptomics','proteomics','metabolomics','microbiome_16s','metagenomics','chipseq','epigenomics','clinical','single_cell','spatial')
  if(length(value)==1L&&!is.na(value)&&value%in%known)value else 'unknown'
}
.enrich_viz_registry_omics <- function(registry,experiment) {
  meta<-registry[[experiment]]
  type<-.enrich_viz_canonical_omics(meta$omics)
  # Only explicit registry classifications are trusted. Generic "normal" is
  # ambiguous across RNA/protein/metabolite assays and is never inferred here.
  if(type=='unknown'&&identical(meta$data_type,'tax'))type<-'microbiome_16s'
  if(type=='unknown'&&identical(meta$data_type,'chipseq'))type<-'chipseq'
  type
}
enrich_viz_sources <- function(session_id, experiment, owner_id, omics='', scope='single') {
  emp_assert_session_owner(session_id,owner_id)
  scope<-.enrich_viz_text(scope,'single',30L)
  if(!scope%in%c('single','multiomics'))stop('Source scope must be single or multiomics')
  registry<-if(exists('read_experiment_registry',mode='function'))read_experiment_registry(session_id) else list()
  target<-if(nzchar(omics %||% '')) .enrich_viz_canonical_omics(omics) else .enrich_viz_registry_omics(registry,experiment)
  explicit<-nzchar(omics %||% '')
  if(explicit&&target=='unknown'&&scope!='multiomics')stop('Choose a recognized omics type or the explicit multiomics source scope')
  eligible<-function(exp,type) {
    if(scope=='multiomics')return(TRUE)
    if(target!='unknown')return(type!='unknown'&&identical(type,target))
    !explicit&&nzchar(experiment %||% '')&&identical(exp,experiment)
  }
  jobs <- list_jobs_for_session(session_id,owner_id)
  out <- list()
  for(st in jobs) {
    if(!identical(st$status,'done') || !grepl('enrich|gsea',st$kind %||% '',ignore.case=TRUE))next
    exp<-st$experiment
    if(length(exp)!=1L||is.na(exp)||!nzchar(exp))next
    # The registry is the current experiment source of truth. Historical jobs
    # may carry trusted registry metadata captured when they were submitted.
    type<-.enrich_viz_registry_omics(registry,exp)
    if(type=='unknown')type<-.enrich_viz_canonical_omics(st$omics)
    if(!eligible(exp,type))next
    src <- tryCatch(enrich_viz_source(list(session_id=session_id,experiment=exp,source_job=st$id),owner_id),error=function(e)NULL)
    if(is.null(src)||!nrow(src$data))next
    out[[length(out)+1L]] <- list(source_job=st$id,experiment=exp,omics=type,
      n_terms=nrow(src$data),kind=src$source$kind,database=src$source$database %||% '',
      label=paste0('[',type,'] ',paste(src$source$database %||% 'Enrichment',toupper(src$source$kind),exp,st$id,sep=' · ')))
  }
  # Current GSEA pointers are per experiment; their source IDs are intentionally
  # combined with experiment in the client, never merged across experiments.
  candidates<-unique(c(names(registry),vapply(jobs,function(st){v<-st$experiment;if(length(v)==1L&&!is.na(v))as.character(v) else ''},character(1)),experiment %||% ''))
  candidates<-candidates[nzchar(candidates)]
  if(exists('emp_load_gsea',mode='function'))for(exp in candidates) {
    type<-.enrich_viz_registry_omics(registry,exp)
    if(!eligible(exp,type))next
    src<-tryCatch(enrich_viz_source(list(session_id=session_id,experiment=exp,source_job='current_gsea'),owner_id),error=function(e)NULL)
    if(!is.null(src)&&nrow(src$data))out<-c(list(list(source_job='current_gsea',experiment=exp,omics=type,n_terms=nrow(src$data),kind='gsea',database=src$source$database,label=paste0('[',type,'] ',paste('Current GSEA',src$source$database,exp,src$source$gsea_id,sep=' · ')))),out)
  }
  list(success=TRUE,sources=out,omics=target,scope=scope,classification_source='Experiment registry or trusted job submission metadata; experiment names are not classified')
}
.enrich_viz_gsea_source <- function(b) {
  if(!exists('emp_load_gsea',mode='function'))stop('GSEA analysis storage is unavailable; run a genuine GSEA analysis first')
  saved<-emp_load_gsea(b$session_id,b$experiment,source_job=b$source_job)
  if(is.null(saved$object)||!methods::is(saved$object,'gseaResult'))stop('Saved source is not a genuine gseaResult')
  d<-as.data.frame(methods::slot(saved$object,'result'),stringsAsFactors=FALSE)
  list(data=d,source=list(source_job=b$source_job,gsea_id=saved$gsea_id,kind='gsea',experiment=b$experiment,
       database=saved$parameters$database %||% 'GSEA',organism=saved$parameters$organism %||% '',
       scope='Saved ranked-list GSEA; statistics are not recomputed during plotting'))
}
enrich_viz_source <- function(b,owner_id) {
  emp_assert_session_owner(b$session_id,owner_id)
  id <- .enrich_viz_text(b$source_job,max_length=150L)
  if(!nzchar(id))stop('Choose a completed enrichment task first')
  if(identical(id,'current_gsea'))return(.enrich_viz_gsea_source(b))
  st <- emp_assert_job_owner(id,owner_id)
  if(!identical(st$session_id,b$session_id)||!identical(st$experiment,b$experiment))stop('Source task does not belong to this session and experiment')
  if(!identical(st$status,'done')||!grepl('enrich|gsea',st$kind %||% '',ignore.case=TRUE))stop('Source must be a completed enrichment task')
  result <- get_job_result(id)
  if(!is.null(result$gsea_id))return(.enrich_viz_gsea_source(b))
  list(data=.enrich_viz_rows(result),source=list(source_job=id,kind='ora',experiment=st$experiment,
       database=result$database %||% '',organism=result$organism %||% '',
       scope='Frozen saved ORA result; only terms retained by the original analysis are available'))
}
.enrich_viz_normalize <- function(d) {
  required <- c('ID','Description','GeneRatio','Count','p.adjust')
  if(!all(required %in% names(d))) stop('Enrichment table requires ID, Description, GeneRatio, Count and p.adjust')
  if(!nrow(d))stop('Enrichment result is empty')
  d$ID <- as.character(d$ID);d$Description <- as.character(d$Description)
  if(anyNA(d$ID)||any(!nzchar(d$ID))||anyDuplicated(d$ID)||anyNA(d$Description))stop('Term IDs must be nonempty and unique; descriptions cannot be missing')
  raw <- as.character(d$GeneRatio)
  ratio <- vapply(raw,function(x){
    if(is.na(x))return(NA_real_)
    pieces <- strsplit(x,'/',fixed=TRUE)[[1]]
    values <- suppressWarnings(as.numeric(pieces))
    if(length(values)==1L)return(values)
    if(length(values)!=2L||any(!is.finite(values))||values[2]<=0)return(NA_real_)
    values[1]/values[2]
  },numeric(1))
  count <- suppressWarnings(as.numeric(d$Count));padj <- suppressWarnings(as.numeric(d[['p.adjust']]))
  if(any(!is.finite(ratio))||any(ratio<0|ratio>1)||any(!is.finite(count))||any(count<0|count!=floor(count))||any(!is.finite(padj))||any(padj<0|padj>1))stop('Invalid GeneRatio, integer Count, or adjusted P values')
  for(i in which(grepl('/',raw,fixed=TRUE))){parts<-as.numeric(strsplit(raw[i],'/',fixed=TRUE)[[1]]);if(parts[1]!=count[i])stop('GeneRatio numerator must equal Count')}
  d$gene_ratio <- unname(ratio);d$Count<-count;d[['p.adjust']]<-padj;d
}
.enrich_viz_style <- function(b) {
  list(width=.enrich_viz_num(b$width,9,3,24,'width'),height=.enrich_viz_num(b$height,7,3,24,'height'),
       base_size=.enrich_viz_num(b$base_size,12,6,30,'base_size'),
       title=.enrich_viz_text(b$title),font_family=.enrich_viz_text(b$font_family,'',100))
}
.enrich_viz_theme <- function(style) {
  # emp_pub_theme dynamically consults Figure_Methods_Lab when enabled by .viz_api_style.
  emp_pub_theme(base_size=style$base_size) + ggplot2::theme(text=ggplot2::element_text(family=style$font_family))
}
enrich_viz_dotplot <- function(b,owner_id) {
  src<-enrich_viz_source(b,owner_id)
  if(!identical(src$source$kind,'ora'))stop('GeneRatio/count dotplots require an ORA source; use the GSEA running-score panel for GSEA results')
  d<-.enrich_viz_normalize(src$data);total<-nrow(d)
  s<-.enrich_viz_style(b)
  top_n<-.enrich_viz_num(b$top_n,20,1,100,'top_n');if(top_n!=floor(top_n))stop('top_n must be an integer')
  cutoff<-.enrich_viz_num(b$p_cutoff,1,0,1,'p_cutoff')
  sort_by<-.enrich_viz_text(b$sort_by,'p.adjust');if(!sort_by%in%c('p.adjust','GeneRatio','Count'))stop('Unsupported sort_by')
  wrap<-.enrich_viz_num(b$label_wrap,45,10,150,'label_wrap')
  size<-.enrich_viz_num(b$max_point_size,10,1,25,'max_point_size')
  low<-.enrich_viz_color(b$low_color,'#554A9A');high<-.enrich_viz_color(b$high_color,'#E52449')
  selected<-as.character(unlist(b$selected_terms %||% character()));highlights<-as.character(unlist(b$highlight_terms %||% character()))
  if(length(setdiff(c(selected,highlights),d$ID)))stop('Selected/highlighted term IDs are absent from the saved source')
  if(length(selected))d<-d[d$ID%in%selected,,drop=FALSE]
  d<-d[d[['p.adjust']]<=cutoff,,drop=FALSE]
  if(!nrow(d))stop('No saved terms pass the selected adjusted-P filter')
  key<-switch(sort_by,'p.adjust'=d[['p.adjust']],'GeneRatio'=-d$gene_ratio,'Count'=-d$Count)
  d<-head(d[order(key,d$ID),,drop=FALSE],top_n)
  d$display_label<-vapply(d$Description,function(x)paste(strwrap(x,width=wrap),collapse='\n'),character(1))
  # Duplicate descriptions retain separate term IDs rather than merge categories.
  if(anyDuplicated(d$display_label))d$display_label<-paste0(d$display_label,' [',d$ID,']')
  d$term<-factor(d$ID,levels=rev(d$ID));d$neg_log10_padj<--log10(pmax(d[['p.adjust']],1e-300))
  labels<-stats::setNames(d$display_label,d$ID)
  note<-paste0('Area: gene count; color: adjusted P. ',nrow(d),' of ',total,' saved terms. ',if(any(d[['p.adjust']]==0))'Zero adjusted P displayed at 1e-300. ' else '', 'No enrichment test was rerun.')
  p<-ggplot2::ggplot(d,ggplot2::aes(x=gene_ratio,y=term,size=Count,color=neg_log10_padj))+
    ggplot2::geom_point(alpha=.95)+ggplot2::scale_size_area(max_size=size)+
    ggplot2::scale_color_gradient(low=low,high=high)+ggplot2::scale_y_discrete(labels=labels)+
    ggplot2::labs(title=if(nzchar(s$title))s$title else 'Enrichment',x='Gene ratio (count / query size)',y=NULL,size='Gene count',color=expression(-log[10](adjusted~italic(P))),caption=note)+.enrich_viz_theme(s)
  if(any(d$ID%in%highlights))p<-p+ggplot2::geom_point(data=d[d$ID%in%highlights,,drop=FALSE],shape=21,fill=NA,colour='#111111',stroke=1)
  pars<-c(s,list(top_n=top_n,sort_by=sort_by,p_cutoff=cutoff,label_wrap=wrap,max_point_size=size,low_color=low,high_color=high,selected_terms=selected,highlight_terms=highlights))
  .enrich_viz_export(p,b,'enrichment_dotplot',pars,src$source,d)
}
.enrich_viz_ranked <- function(text,weight=1) {
  if(length(text)!=1L||is.na(text)||nchar(text,type='bytes')>15*1024^2)stop('Provide ranked CSV/TSV text up to 15 MiB')
  separator<-if(grepl('\t',strsplit(text,'\n',fixed=TRUE)[[1]][1],fixed=TRUE))'\t' else ','
  d<-utils::read.table(text=text,header=TRUE,sep=separator,quote='"',comment.char='',check.names=FALSE,stringsAsFactors=FALSE)
  if(!all(c('gene_id','metric','in_set')%in%names(d))||nrow(d)<2L||nrow(d)>200000L)stop('Ranked input requires gene_id, metric, in_set and 2–200000 genes')
  d$gene_id<-as.character(d$gene_id)
  if(anyNA(d$gene_id)||any(!nzchar(d$gene_id))||anyDuplicated(d$gene_id))stop('Ranked gene IDs must be nonempty and unique')
  d$metric<-suppressWarnings(as.numeric(d$metric))
  if(any(!is.finite(d$metric))||any(diff(d$metric)>1e-10))stop('Rank metric must be finite and sorted decreasingly; upload the complete ranked list')
  if('rank'%in%names(d)&&!identical(suppressWarnings(as.numeric(d$rank)),as.numeric(seq_len(nrow(d)))))stop('Rank must be consecutive from 1')
  hit<-tolower(as.character(d$in_set))
  if(anyNA(hit)||any(!hit%in%c('true','false','1','0')))stop('in_set must be TRUE/FALSE or 1/0')
  d$in_set<-hit%in%c('true','1');d$rank<-seq_len(nrow(d))
  if(!any(d$in_set)||all(d$in_set))stop('Gene set must be a nonempty proper subset of the complete ranked list')
  weight<-.enrich_viz_num(weight,1,0,10,'weight')
  w<-abs(d$metric)^weight
  if(any(!is.finite(w))||sum(w[d$in_set])<=0)stop('Invalid or zero gene-set weight sum')
  d$ES<-cumsum(ifelse(d$in_set,w/sum(w[d$in_set]),-1/sum(!d$in_set)))
  d
}
enrich_viz_gsea <- function(b,owner_id) {
  emp_assert_session_owner(b$session_id,owner_id)
  s<-.enrich_viz_style(b)
  saved_source<-NULL;statistics<-NULL
  if(!is.null(b$source_job)&&nzchar(b$source_job)&&(is.null(b$ranked_csv)||identical(b$ranked_csv,''))) {
    src<-enrich_viz_source(b,owner_id)
    if(!identical(src$source$kind,'gsea'))stop('ORA results do not contain a complete ranked universe; run ranked-list GSEA or supply a complete ranked list')
    saved<-emp_load_gsea(b$session_id,b$experiment,source_job=b$source_job)
    id<-.enrich_viz_text(b$set_id,max_length=200L)
    row<-src$data[as.character(src$data$ID)==id,,drop=FALSE]
    if(!nzchar(id)||nrow(row)!=1L)stop('Choose a gene set ID from the selected saved GSEA result')
    ranks<-methods::slot(saved$object,'geneList');sets<-methods::slot(saved$object,'geneSets');set<-sets[[id]]
    if(is.null(names(ranks))||is.null(set))stop('Saved GSEA object lacks ranked gene identities or the selected gene set')
    weight<-.enrich_viz_num(saved$parameters$exponent %||% methods::slot(saved$object,'params')$exponent,1,0,10,'saved GSEA exponent')
    ranked<-data.frame(gene_id=names(ranks),metric=as.numeric(ranks),in_set=names(ranks)%in%set)
    text<-paste(utils::capture.output(utils::write.csv(ranked,row.names=FALSE)),collapse='\n')
    d<-.enrich_viz_ranked(text,weight)
    saved_source<-src$source;statistics<-row
    label<-.enrich_viz_text(as.character(row$Description),id)
    if(!nzchar(trimws(label)))label<-id
  } else {
    weight<-.enrich_viz_num(b$weight,1,0,10,'weight');d<-.enrich_viz_ranked(b$ranked_csv,weight)
    label<-trimws(.enrich_viz_text(b$set_label))
    if(!nzchar(label)||tolower(label)=='gene set')label<-'User supplied gene set'
  }
  if(!requireNamespace('patchwork',quietly=TRUE))stop('patchwork is required for the running-score/hit/rank panels')
  color<-.enrich_viz_color(b$line_color,'#67AE50')
  p1<-ggplot2::ggplot(d,ggplot2::aes(x=rank,y=ES))+ggplot2::geom_hline(yintercept=0,color='grey60')+ggplot2::geom_line(color=color,linewidth=1)+ggplot2::labs(x=NULL,y='Running enrichment score')+.enrich_viz_theme(s)+ggplot2::theme(axis.text.x=ggplot2::element_blank())
  p2<-ggplot2::ggplot(d[d$in_set,,drop=FALSE],ggplot2::aes(x=rank,xend=rank,y=0,yend=1))+ggplot2::geom_segment(linewidth=.3)+ggplot2::theme_void()
  p3<-ggplot2::ggplot(d,ggplot2::aes(x=rank,y=1,fill=metric))+ggplot2::geom_raster()+ggplot2::scale_fill_gradient2(low='#395AA6',mid='white',high='#CC3B3B',midpoint=0)+ggplot2::labs(x='Rank in complete ordered gene list',y=NULL,fill='Rank metric')+.enrich_viz_theme(s)+ggplot2::theme(axis.text.y=ggplot2::element_blank(),axis.ticks.y=ggplot2::element_blank())
  limits<-c(.5,nrow(d)+.5);scale<-ggplot2::scale_x_continuous(limits=limits,expand=c(0,0));p1<-p1+scale;p2<-p2+scale;p3<-p3+scale
  es<-d$ES[which.max(abs(d$ES))]
  subtitle<-if(is.null(statistics))sprintf('ES = %.4f; NES / FDR not estimated; no permutation inference',es) else
    sprintf('ES = %.4f; saved NES = %.4g; saved adjusted P = %.4g',es,as.numeric(statistics$NES),as.numeric(statistics[['p.adjust']]))
  gene_set_heading<-paste0('Gene Set: ',label)
  if(nzchar(s$title))subtitle<-paste(gene_set_heading,subtitle,sep='\n')
  p<-patchwork::wrap_plots(p1,p2,p3,ncol=1,heights=c(4,.65,.75))+patchwork::plot_annotation(title=if(nzchar(s$title))s$title else gene_set_heading,subtitle=subtitle)
  origin<-saved_source %||% list(kind='user_supplied_ranked_list',n_genes=nrow(d),set_size=sum(d$in_set),inference='ES only; no NES, P or FDR estimated')
  if(!is.null(statistics))origin$statistics<-as.list(statistics[1,intersect(c('ID','enrichmentScore','NES','pvalue','p.adjust','qvalue'),names(statistics)),drop=FALSE])
  out<-.enrich_viz_export(p,b,'gsea_running_es',c(s,list(weight=weight,line_color=color,set_label=label,set_id=b$set_id %||% NULL)),origin,d)
  out$es<-es;out
}
.enrich_viz_export <- function(p,b,kind,parameters,source,data) {
  # Unique prefixes keep every iteration and its source table reproducible.
  dir<-file.path(session_path(b$session_id),'plots');dir.create(dir,recursive=TRUE,showWarnings=FALSE)
  prefix<-basename(tempfile(pattern=paste0(kind,'_'),tmpdir=dir))
  files<-stats::setNames(paste0(prefix,c('.png','.pdf','.svg','.manifest.json','.data.csv')),c('png','pdf','svg','manifest','data'))
  paths<-file.path(dir,files);names(paths)<-names(files)
  ggplot2::ggsave(paths['png'],p,width=parameters$width,height=parameters$height,units='in',dpi=300,bg='white',limitsize=TRUE)
  ggplot2::ggsave(paths['pdf'],p,width=parameters$width,height=parameters$height,units='in',device=grDevices::pdf,useDingbats=FALSE,bg='white')
  if(!requireNamespace('svglite',quietly=TRUE))stop('svglite is required for editable SVG export')
  ggplot2::ggsave(paths['svg'],p,width=parameters$width,height=parameters$height,units='in',device=svglite::svglite,bg='white')
  if(!all(file.exists(paths[c('png','pdf','svg')]))||any(file.info(paths[c('png','pdf','svg')])$size<=0))stop('One or more figure exports were not produced')
  utils::write.csv(data,paths['data'],row.names=FALSE)
  provenance<-if(exists('emp_figure_methods_profile',mode='function'))emp_figure_methods_profile() else NULL
  rules_root<-Sys.getenv('EMP_FIGURE_METHODS_ROOT','')
  paths_rules<-c(file.path(Sys.getenv('EMP_ROOT',getwd()),'webapp/backend/helpers/viz_enrichment.R'),if(nzchar(rules_root))file.path(rules_root,c('skills/omics-enrichment-dotplot/SKILL.md','skills/omics-gsea-running-score/SKILL.md','library/plot_methods.R')) else character())
  paths_rules<-paths_rules[file.exists(paths_rules)]
  code_md5<-as.list(tools::md5sum(paths_rules))
  manifest<-list(schema='emp-enrichment-figure-v1',kind=kind,created_utc=format(Sys.time(),tz='UTC',usetz=TRUE),parameters=parameters,source=source,figure_methods=provenance,code_md5=code_md5,input_md5=unname(tools::md5sum(paths['data'])),R_version=R.version.string,ggplot2_version=as.character(utils::packageVersion('ggplot2')),dpi=300)
  jsonlite::write_json(manifest,paths['manifest'],auto_unbox=TRUE,pretty=TRUE,null='null')
  urls<-lapply(files,function(f)paste0('/api/visualize/enrichment/file/',b$session_id,'/',f))
  list(success=TRUE,plot=base64enc::base64encode(paths['png']),pdf_available=TRUE,pdf_name=unname(files['pdf']),svg_available=TRUE,svg_name=unname(files['svg']),download_urls=urls,parameters=parameters,source=source,n_rows=nrow(data))
}
