# Scientific and source-access contracts, using explicit small test fixtures.
source('webapp/backend/helpers/utils.R')
source('webapp/backend/helpers/plot_theme.R')
source('webapp/backend/helpers/viz_enrichment.R')
error <- function(expr, pattern) {
  e<-tryCatch({force(expr);NULL},error=identity)
  stopifnot(inherits(e,'error'),grepl(pattern,conditionMessage(e)))
}
input<-data.frame(ID=c('GO:1','GO:2'),Description=c('Pathway one','Pathway two'),GeneRatio=c('2/10','4/10'),Count=c(2,4),p.adjust=c(.01,.2),check.names=FALSE)
d<-.enrich_viz_normalize(input)
stopifnot(identical(d$gene_ratio,c(.2,.4)),identical(d[['p.adjust']],input[['p.adjust']]))
bad<-input;bad$Count[1]<-3;error(.enrich_viz_normalize(bad),'numerator')
bad<-input;bad[['p.adjust']][1]<-NA;error(.enrich_viz_normalize(bad),'Invalid')
bad<-input;bad$ID[2]<-bad$ID[1];error(.enrich_viz_normalize(bad),'unique')
text<-'gene_id,metric,in_set\na,3,TRUE\nb,2,FALSE\nc,-1,TRUE\nd,-2,FALSE'
r<-.enrich_viz_ranked(text,1)
stopifnot(isTRUE(all.equal(r$ES,c(.75,.25,.5,0))),identical(r$rank,1:4))
error(.enrich_viz_ranked(sub('b,2,FALSE','b,4,FALSE',text)),'sorted')
error(.enrich_viz_ranked(sub('b,2,FALSE','a,2,FALSE',text)),'unique')
error(.enrich_viz_ranked(gsub('FALSE','TRUE',text)),'proper subset')
error(.enrich_viz_ranked(sub('c,-1,TRUE','c,-1,maybe',text)),'TRUE/FALSE')
error(.enrich_viz_ranked(text,-1),'weight')
# Storage and ownership are mocked only in this isolated test process.
emp_assert_session_owner<-function(session_id,owner_id){if(!identical(session_id,'test-session')||owner_id!='test-owner')stop('access denied')}
emp_assert_job_owner<-function(id,owner_id)list(session_id=if(id=='foreign')'other-session' else 'test-session',experiment='test',status='done',kind='enrichment')
get_job_result<-function(id)list(data=input,database='GO_BP',organism='mmu')
list_jobs_for_session<-function(...)list(list(id='one',experiment='test',status='done',kind='enrichment'))
src<-enrich_viz_sources('test-session','test','test-owner');stopifnot(length(src$sources)==1L,src$sources[[1]]$kind=='ora')
error(enrich_viz_source(list(session_id='test-session',experiment='test',source_job='foreign'),'test-owner'),'does not belong')
error(enrich_viz_source(list(session_id='test-session',experiment='test',source_job='one'),'foreign-owner'),'access denied')
if(all(vapply(c('ggplot2','svglite','base64enc','jsonlite','patchwork'),requireNamespace,logical(1),quietly=TRUE))){
  output<-tempfile('enrichment-figure-test-');dir.create(output)
  session_path<-function(...)output
  b<-list(session_id='test-session',experiment='test',source_job='one',width=6,height=5,top_n=2,p_cutoff=1,highlight_terms='GO:1')
  out<-enrich_viz_dotplot(b,'test-owner')
  stopifnot(out$success,out$n_rows==2L,file.exists(file.path(output,'plots',out$pdf_name)),file.exists(file.path(output,'plots',out$svg_name)),nchar(out$plot)>100)
  gsea<-enrich_viz_gsea(list(session_id='test-session',experiment='test',ranked_csv=text,width=6,height=5),'test-owner')
  stopifnot(gsea$success,gsea$es==.75,gsea$source$inference=='ES only; no NES, P or FDR estimated')
  files<-list.files(file.path(output,'plots'));stopifnot(sum(grepl('manifest.json$',files))==2L,sum(grepl('[.]data.csv$',files))==2L)
  # A minimal S4 storage fixture verifies the saved-result branch; these test
  # statistics are not user findings or outputs from permutation analysis.
  if(!methods::isClass('gseaResult'))methods::setClass('gseaResult',slots=c(result='data.frame',geneList='numeric',geneSets='list',params='list'))
  object<-methods::new('gseaResult',result=data.frame(ID='setA',Description='Stored set',NES=1.7,p.adjust=.03,enrichmentScore=.75,check.names=FALSE),geneList=stats::setNames(c(3,2,-1,-2),letters[1:4]),geneSets=list(setA=c('a','c')),params=list(exponent=1))
  emp_load_gsea<-function(...)list(object=object,parameters=list(exponent=1,database='GO_BP'),gsea_id='fixture-gsea')
  saved<-enrich_viz_gsea(list(session_id='test-session',experiment='test',source_job='current_gsea',set_id='setA',ranked_csv='',width=6,height=5),'test-owner')
  stopifnot(saved$success,saved$source$kind=='gsea',saved$source$statistics$NES==1.7,saved$source$statistics[['p.adjust']]==.03,saved$parameters$weight==1,saved$es==.75)
  # Old clients sent a generic placeholder; saved result names take priority.
  original_export <- .enrich_viz_export
  .enrich_viz_export <- function(p,b,kind,parameters,source,data) list(title=p$patches$annotation$title,subtitle=p$patches$annotation$subtitle,parameters=parameters)
  args<-list(session_id='test-session',experiment='test',source_job='current_gsea',set_id='setA',set_label='Gene set')
  heading<-enrich_viz_gsea(args,'test-owner')
  stopifnot(heading$title=='Gene Set: Stored set',heading$parameters$set_label=='Stored set')
  args$title<-'Custom title'
  heading<-enrich_viz_gsea(args,'test-owner')
  stopifnot(heading$title=='Custom title',grepl('Gene Set: Stored set',heading$subtitle,fixed=TRUE))
  .enrich_viz_export <- original_export
  error(enrich_viz_gsea(list(session_id='test-session',experiment='test',source_job='current_gsea',set_id='missing'),'test-owner'),'Choose a gene set')

  message('Actual R PNG/PDF/SVG and provenance exports passed: ',output)
}
message('Enrichment scientific contracts passed.')
