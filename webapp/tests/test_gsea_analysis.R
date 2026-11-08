# Contract tests use explicit fixtures, not biological results.
source('webapp/backend/helpers/analysis_gsea.R')
fixture <- data.frame(symbol=paste0('g',1:30),stat=seq(-3,3,length.out=30),
  log2FoldChange=seq(-1,1,length.out=30),pvalue=rep(.5,30),padj=rep(.9,30))
x <- emp_gsea_ranks(list(data=fixture))
stopifnot(nrow(x$ranks)==30, x$audit$significance_filter=='none')
err <- tryCatch(emp_gsea_ranks(list(data=fixture[,-2])),error=identity)
stopifnot(inherits(err,'error'))
fixture$stat[1]<-NA
stopifnot(emp_gsea_ranks(list(data=fixture))$audit$excluded_invalid==1)
fixture$symbol[2]<-fixture$symbol[3]
stopifnot(inherits(tryCatch(emp_gsea_ranks(list(data=fixture)),error=identity),'error'))
message('GSEA full-rank, metric and invalid-input contracts passed.')

# Opt-in actual GO integration, independent local fixture and output directory.
if(Sys.getenv('EMP_TEST_REAL_GSEA')=='1') {
  source('webapp/backend/helpers/utils.R')
  source('webapp/backend/helpers/analysis.R')
  source('webapp/backend/helpers/analysis_gsea.R')
  root <- tempfile('emp-gsea-fixture-');dir.create(root)
  session_path <- function(id)root
  db<-get('org.Mm.eg.db',asNamespace('org.Mm.eg.db'))
  ids<-head(AnnotationDbi::keys(db,keytype='ENTREZID'),1500)
  set.seed(23)
  fixture<-data.frame(feature=ids,symbol=ids,stat=rnorm(length(ids)))
  load_diff_raw<-function(...)list(data=fixture,method='fixture',ref_group='A',test_group='B')
  result<-emp_run_gsea('fixture','test',database='GO_BP',organism='mmu',id_type='ENTREZID',min_size=10,max_size=200,seed=23)
  saved<-emp_load_gsea('fixture','test')
  stopifnot(methods::is(saved$object,'gseaResult'),length(saved$object@geneList)==length(ids),
    all(c('NES','p.adjust','enrichmentScore')%in%names(as.data.frame(saved$object))))
  message('Actual GO GSEA fixture passed: ',result$n_rows,' terms. Artifacts: ',root)
}
