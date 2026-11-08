# Deterministic pipeline fixtures: no external enrichment claims.
source('webapp/backend/helpers/utils.R');source('webapp/backend/helpers/plot_theme.R')
source('webapp/backend/helpers/viz.R');source('webapp/backend/helpers/viz_enrichment.R');source('webapp/backend/helpers/runall.R')
root<-tempfile('runall-unit-');dir.create(root)
session_path<-function(...)root
b<-.bundle_init('fixture');e<-.runall_engine(b,list(seed=1))
stopifnot(e$stage('done',function(){writeLines('fixture',file.path(b$tables,'fixture.txt'));42})==42)
e$stage('disabled',function()stop('must not execute'),FALSE)
e$stage('unavailable',function().runall_skip('missing fixture input'))
e$stage('failure',function()stop('expected fixture failure'))
stopifnot(identical(vapply(e$stages,`[[`,character(1),'status'),c('done','skipped','skipped','error')),e$stages[[1]]$files=='tables/fixture.txt',grepl('expected fixture',e$stages[[4]]$reason))
stopifnot(.bundle_init('fixture')$run_id!=b$run_id)
if(requireNamespace('SummarizedExperiment',quietly=TRUE)&&requireNamespace('svglite',quietly=TRUE)){
 proof<-file.path(getwd(),'.local_run/verification/runall-complete',format(Sys.time(),'%Y%m%d-%H%M%S'));dir.create(proof,recursive=TRUE)
 session_path<-function(...)proof
 set.seed(725);mat<-matrix(rpois(24*6,lambda=20),nrow=24,dimnames=list(paste0('fixture_feature_',1:24),paste0('fixture_sample_',1:6)))
 cd<-data.frame(Group=rep(c('control','treated'),each=3),row.names=colnames(mat))
 fixture<-SummarizedExperiment::SummarizedExperiment(assays=list(counts=mat),colData=cd)
 get_empt_fresh<-function(...)fixture
 get_empt<-function(...)fixture
 apply_merged_coldata<-function(s,e)e
 load_raw_empt<-function(...)fixture
 .diff_count_input<-function(current,raw){stopifnot(identical(SummarizedExperiment::assay(current),mat));list(empt=current,source='fixture_original_counts')}
 emp_get_session_owner<-function(...)list(owner_id='fixture-owner')
 load_empt<-function(...)fixture
 raw<-list(data=data.frame(feature=rownames(mat),symbol=rownames(mat),log2FoldChange=seq(-3,3,length.out=nrow(mat)),padj=rep(.5,nrow(mat)),pvalue=rep(.001,nrow(mat))))
 run_diff<-function(...){stopifnot(identical(SummarizedExperiment::assay(fixture),mat));raw$data}
 load_diff_raw<-function(...)raw
 output<-run_all_rnaseq('fixture','fixture',group_var='Group',ref_group='control',test_group='treated',do_enrichment=FALSE,do_gsea=FALSE,do_method_figures=FALSE,feature_top_n=12,network_cutoff=.1)
 statuses<-stats::setNames(vapply(output$stages,`[[`,character(1),'status'),vapply(output$stages,`[[`,character(1),'id'))
 stopifnot(file.exists(output$zip_path),statuses['qc']=='done',statuses['pca']=='done',statuses['differential']=='done',statuses['volcano']=='done',statuses['deg_heatmap']=='skipped',statuses['gsea_analysis']=='skipped')
 manifest<-jsonlite::read_json(file.path(output$bundle,'manifest.json'),simplifyVector=FALSE)
 stopifnot(length(manifest$stages)==length(output$stages),all(c('sample_library_size.png','pca_scatter.pdf','volcano.svg')%in%output$figures))
 stopifnot(identical(SummarizedExperiment::assay(fixture),mat))
 message('Fixture bundle and actual R figures: ',output$bundle)
 # Exercise actual 16S taxonomy aggregation, vegan diversity and a genuine
 # three-group omnibus test on clearly synthetic counts.
 source('webapp/backend/helpers/workflow_microbiome_16s.R')
 source('webapp/backend/helpers/viz_method_library.R')
 rownames(mat)<-paste0('Bacteria;Bacteria;P;C;O;F;fixture_Genus',seq_len(nrow(mat)))
 cd$Group<-rep(c('control','treatedA','treatedB'),each=2)
 fixture<-SummarizedExperiment::SummarizedExperiment(assays=list(counts=mat),colData=cd)
 .save_diff_raw_cache<-function(session_id,experiment,method,group_var,ref_group,test_group,raw_df,comparison_mode)raw<<-list(data=raw_df,method=method)
 emp_assert_session_owner<-function(...)invisible(TRUE)
 library_root<-'/Users/mac/Documents/ChatGPT/多组学数据分析/Figure_Methods_Lab'
 if(dir.exists(library_root))Sys.setenv(EMP_FIGURE_METHODS_ROOT=library_root)
 out16<-run_all_m16s('fixture','fixture16',group_var='Group',feature_top_n=12,network_cutoff=.1,do_method_figures=dir.exists(library_root))
 st16<-stats::setNames(vapply(out16$stages,`[[`,character(1),'status'),vapply(out16$stages,`[[`,character(1),'id'))
 stopifnot(file.exists(out16$zip_path),st16['taxonomy']=='done',st16['alpha']=='done',st16['composition']=='done',st16['differential']=='done',st16['volcano']=='skipped',st16['deg_heatmap']=='skipped')
 if(dir.exists(library_root))stopifnot(st16['ternary']=='done')
 stopifnot(grepl('kruskal',raw$method),all(is.na(raw$data$log2FoldChange)),identical(SummarizedExperiment::assay(fixture),mat))
 message('16S fixture bundle and actual R figures: ',out16$bundle)

}
message('Run-all stage and fixture contracts passed; no actual GO/KEGG/GSEA network queries were performed.')
