# Source scoping uses explicit registry metadata, never suggestive names.
source('webapp/backend/helpers/utils.R')
source('webapp/backend/helpers/viz_enrichment.R')
registry<-list(rna_one=list(omics='transcriptomics'),rna_two=list(omics='transcriptomics'),RNAseq_protein_name=list(omics='proteomics'),microbe=list(data_type='tax'),RNAseq_unknown=list(data_type='normal'),old_unknown=list())
read_experiment_registry<-function(...)registry
emp_assert_session_owner<-function(...)invisible(TRUE)
jobs<-lapply(names(registry),function(exp)list(id=paste0('job_',exp),experiment=exp,status='done',kind='enrichment'))
list_jobs_for_session<-function(...)jobs
# Source loading/ownership has separate integration contracts. The scope test
# supplies a two-row saved table without fitting or claiming enrichment.
enrich_viz_source<-function(b,owner_id){
 if(b$source_job=='current_gsea'&&!b$experiment%in%c('rna_one','rna_two','RNAseq_protein_name'))stop('no GSEA pointer')
 list(data=data.frame(ID=c('fixture1','fixture2')),source=list(kind=if(b$source_job=='current_gsea')'gsea' else 'ora',database='GO_BP',gsea_id=paste0('fixture_',b$experiment)))
}
emp_load_gsea<-function(...)NULL
experiments<-function(out)unique(vapply(out$sources,`[[`,character(1),'experiment'))
one<-enrich_viz_sources('s','rna_one','o')
stopifnot(setequal(experiments(one),c('rna_one','rna_two')),all(vapply(one$sources,function(x)x$omics=='transcriptomics',logical(1))),sum(vapply(one$sources,function(x)x$source_job=='current_gsea',logical(1)))==2L)
protein<-enrich_viz_sources('s','rna_one','o',omics='proteomics')
stopifnot(identical(experiments(protein),'RNAseq_protein_name'),all(vapply(protein$sources,function(x)x$omics=='proteomics',logical(1))))
unknown<-enrich_viz_sources('s','RNAseq_unknown','o')
stopifnot(identical(experiments(unknown),'RNAseq_unknown'),all(vapply(unknown$sources,function(x)x$omics=='unknown',logical(1))))
multi<-enrich_viz_sources('s','rna_one','o',scope='multiomics')
stopifnot(setequal(experiments(multi),names(registry)))
# Trusted job metadata can classify a legacy experiment missing registry data;
# unknown legacy jobs are excluded from explicit single-omics selections.
jobs[[length(jobs)+1L]]<-list(id='legacy',experiment='missing_registry',omics='metabolomics',status='done',kind='enrichment')
meta<-enrich_viz_sources('s','rna_one','o',omics='metabolomics')
stopifnot(identical(experiments(meta),'missing_registry'))
error<-tryCatch(enrich_viz_sources('s','rna_one','o',scope='all'),error=identity)
stopifnot(inherits(error,'error'))
message('Enrichment source omics scoping contracts passed.')
