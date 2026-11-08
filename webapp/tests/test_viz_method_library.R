# Explicit deterministic fixtures: not biological research results.
source('webapp/backend/helpers/utils.R');source('webapp/backend/helpers/viz_method_library.R')
error<-function(expr,pattern){e<-tryCatch({force(expr);NULL},error=identity);stopifnot(inherits(e,'error'),grepl(pattern,conditionMessage(e)))}
b<-list(omics='microbiome_16s',group_var='Group',groups=c('control','treatA','treatB'),top_n=8)
ad<-matrix(c(10,20,30,20,10,30,5,25,30,5,15,40,25,5,30,20,10,30),nrow=3,dimnames=list(paste0('fixture_',1:3),paste0('sample_',1:6)))
cd<-data.frame(Group=rep(b$groups,each=2),row.names=colnames(ad))
r<-.method_library_ternary_data(ad,cd,b)
stopifnot(max(abs(rowSums(r$data[,c('A','B','C')])-1))<1e-12,all(r$data$size>0),identical(as.integer(unlist(r$source$group_sample_counts)),c(2L,2L,2L)))
relative<-sweep(ad,2,colSums(ad),'/');stopifnot(isTRUE(all.equal(sort(r$data$size),sort(rowMeans(relative)),check.attributes=FALSE)))
bad<-ad;bad[1,1]<-NA;error(.method_library_ternary_data(bad,cd,b),'missing')
bad<-ad;bad[1,1]<--1;error(.method_library_ternary_data(bad,cd,b),'nonnegative')
bad<-ad;bad[,1]<-0;error(.method_library_ternary_data(bad,cd,b),'zero')
bb<-b;bb$groups<-c('control','control','treatB');error(.method_library_ternary_data(ad,cd,bb),'distinct')
bb<-b;bb$omics<-'transcriptomics';error(.method_library_ternary_data(ad,cd,bb),'limited')
raw<-list(data=data.frame(feature=paste0('fixture_gene_',1:5),log2FoldChange=c(-3,-1,0,1,3),padj=c(.001,.1,.6,.1,.002)),method='fixture_external_stats',ref_group='control',test_group='treated')
d<-.method_library_de_data(raw,list(omics='transcriptomics'))
stopifnot(identical(d$data$log2FC,raw$data$log2FoldChange),identical(d$data$padj,raw$data$padj))
bad<-raw;bad$data$padj[1]<-0;error(.method_library_de_data(bad,list(omics='proteomics')),'No rows')
bad<-raw;bad$data$feature[2]<-bad$data$feature[1];error(.method_library_de_data(bad,list(omics='proteomics')),'unique')
missing<-raw;missing$data$padj[1]<-NA
error(.method_library_de_data(missing,list(omics='proteomics')),'No rows')
selected<-.method_library_de_data(missing,list(omics='proteomics',exclude_unavailable_p=TRUE))
stopifnot(nrow(selected$data)==4L,nrow(selected$full_input)==5L,nrow(selected$exclusions)==1L,selected$source$excluded_unavailable_p==1L,is.na(missing$data$padj[1]))
root<-Sys.getenv('EMP_FIGURE_METHODS_ROOT','/Users/mac/Documents/ChatGPT/多组学数据分析/Figure_Methods_Lab');Sys.setenv(EMP_FIGURE_METHODS_ROOT=root)
if(dir.exists(root)&&requireNamespace('SummarizedExperiment',quietly=TRUE)){
  proof<-file.path(getwd(),'.local_run/verification/method-library',format(Sys.time(),'%Y%m%d-%H%M%S'));dir.create(proof,recursive=TRUE)
  session_path<-function(...)proof
  emp_assert_session_owner<-function(s,o){if(s!='fixture-session'||o!='fixture-owner')stop('Forbidden')}
  get_empt<-function(...)SummarizedExperiment::SummarizedExperiment(assays=list(counts=ad),colData=cd)
  load_diff_raw<-function(...)raw
  b$method<-'ternary';b$session_id<-'fixture-session';b$experiment<-'fixture';b$title<-'FIXTURE / synthetic counts: three-group composition';b$width<-7;b$height<-6
  one<-emp_viz_method_library(b,'fixture-owner')
  two<-emp_viz_method_library(list(method='de_scatter',session_id='fixture-session',experiment='fixture',omics='transcriptomics',title='FIXTURE / external synthetic differential statistics',width=7,height=6),'fixture-owner')
  stopifnot(one$success,two$success,file.exists(file.path(proof,'plots',one$pdf_name)),file.exists(file.path(proof,'plots',two$svg_name)))
  files<-list.files(file.path(proof,'plots'),full.names=TRUE);stopifnot(sum(grepl('[.]manifest.json$',files))==2L,sum(grepl('[.]derived.csv$',files))==2L)
  writeLines(c('Test fixtures only; no research findings.',list.files(file.path(proof,'plots'),pattern='[.]png$',full.names=TRUE)),file.path(proof,'FIXTURE_PROOFS.txt'))
  message('Live library export proofs: ',proof)
}
message('Method library scientific and export contracts passed.')
