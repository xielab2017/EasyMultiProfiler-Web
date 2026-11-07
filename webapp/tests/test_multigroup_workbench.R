# Synthetic software acceptance, not biological observations.
source("webapp/backend/helpers/omics_workbench.R")
stopifnot(requireNamespace("edgeR", quietly=TRUE), requireNamespace("DESeq2", quietly=TRUE))
set.seed(20261107)
labels <- rep(c("control / A", "treated-B", "treated B"), each=3)
counts <- matrix(rnbinom(400*9, mu=200, size=3), nrow=400)
counts[1:30,4:6] <- counts[1:30,4:6]*4L
counts[31:60,7:9] <- counts[31:60,7:9]*5L
counts <- rbind(counts, 0L)
rownames(counts) <- paste0("synthetic_gene_",seq_len(nrow(counts)))
colnames(counts) <- paste0("sample_",seq_len(ncol(counts)))
con <- textConnection("matrix_csv", "w", local=TRUE)
write.table(data.frame(feature_id=rownames(counts),counts,check.names=FALSE),con,sep=",",row.names=FALSE,col.names=TRUE,quote=TRUE)
close(con); matrix_csv <- paste0(paste(matrix_csv,collapse="\n"),"\n")
samples <- lapply(seq_len(ncol(counts)),function(i)list(id=colnames(counts)[i],group=labels[i]))
pairs <- list(list(test="treated-B",reference="control / A"),list(test="treated B",reference="control / A"),list(test="treated B",reference="treated-B"))
steps <- list(list(id="qc",operation="qc",parameters=list()),list(id="DESeq2",operation="deseq2",parameters=list(alpha=.05,min_count=10L,min_samples=3L)),list(id="edgeR",operation="edger",parameters=list(alpha=.05,min_count=10L,min_samples=3L)))
plan <- list(contract=EMP_WB_CONTRACT,version=1L,dataset_id="synthetic-multigroup",omics="bulk_rnaseq",data_type="raw_counts",samples=rev(samples),
 design=list(test=pairs[[1]]$test,reference=pairs[[1]]$reference,independent_samples=TRUE,contrasts=pairs),steps=steps,seed=20261107L,
 raw_counts_evidence="Synthetic negative-binomial integer test data; no biological inference.",source="Synthetic acceptance fixture only",excluded_columns=list(),raw_count_provenance_verified=FALSE,
 source_sha256=digest::digest(matrix_csv,algo="sha256",serialize=FALSE),input_sha256=digest::digest(matrix_csv,algo="sha256",serialize=FALSE))
plan$grouping_review <- list(confirmed=TRUE,method="manual",field="",metadata_sha256="",paper=list(),sample_rows=lapply(samples,function(row)c(row,list(gsm="",match="unmatched",evidence="Synthetic assigned label"))))
payload <- function(plan){value=jsonlite::toJSON(plan,auto_unbox=TRUE,null="null",digits=NA);list(plan_json=as.character(value),plan_sha256=digest::digest(as.character(value),algo="sha256",serialize=FALSE),matrix_csv=matrix_csv)}
input <- payload(plan)
result <- emp_wb_compute(input)
stopifnot(result$success,result$execution_performed,length(result$artifacts$differentials)==6L)
stopifnot(result$artifacts$qc$feature_count==401L,result$artifacts$differential$tested_features==400L)
keep <- rowSums(counts>=10)>=3
group <- factor(rep(c("G1","G2","G3"),each=3),levels=c("G1","G2","G3"))
dds <- DESeq2::DESeqDataSetFromMatrix(counts[keep,,drop=FALSE],data.frame(group=group,row.names=colnames(counts)),~group)
dds <- DESeq2::DESeq(dds,parallel=FALSE,quiet=TRUE)
model <- model.matrix(~0+group)
y <- edgeR::DGEList(counts=counts[keep,,drop=FALSE],group=group)
y <- edgeR::calcNormFactors(y,method="TMM")
y <- edgeR::estimateDisp(y,model,robust=FALSE)
fit <- edgeR::glmQLFit(y,model,robust=FALSE)
safe <- c("G1","G2","G3");original <- unique(labels)
for (i in seq_along(pairs)) {
 pair <- pairs[[i]]
 expected <- as.data.frame(DESeq2::results(dds,contrast=c("group",safe[match(pair$test,original)],safe[match(pair$reference,original)]),alpha=.05,pAdjustMethod="BH"))
 actual <- result$artifacts$differentials[[i]]
 for (column in names(expected)) {
  observed <- vapply(actual$rows,function(row)if(is.null(row[[column]]))NA_real_ else row[[column]],numeric(1))
  stopifnot(isTRUE(all.equal(unname(observed),unname(expected[[column]]),tolerance=1e-12)))
 }
 contrast <- numeric(3);contrast[match(pair$test,original)] <- 1;contrast[match(pair$reference,original)] <- -1
 expected <- edgeR::topTags(edgeR::glmQLFTest(fit,contrast=contrast),n=Inf,sort.by="none",adjust.method="BH")$table
 actual <- result$artifacts$differentials[[i+3]]
 stopifnot(actual$method=="edgeR",actual$test==pair$test,actual$reference==pair$reference)
 for (column in names(expected)) {
  observed <- vapply(actual$rows,function(row)row[[column]],numeric(1))
  stopifnot(isTRUE(all.equal(unname(observed),unname(expected[[column]]),tolerance=1e-12)))
 }
}
bad <- plan;bad$design$contrasts[[2]] <- bad$design$contrasts[[1]]
stopifnot(inherits(try(emp_wb_validate(payload(bad)),silent=TRUE),"try-error"))
bad <- plan;bad$grouping_review$sample_rows[[1]]$group <- "tampered"
stopifnot(inherits(try(emp_wb_validate(payload(bad)),silent=TRUE),"try-error"))
out <- commandArgs(trailingOnly=TRUE)
if(length(out)){
 if(file.exists(out[[1]]))stop("Choose a new output directory")
 dir.create(out[[1]],recursive=TRUE)
 writeLines(jsonlite::toJSON(input,auto_unbox=TRUE,digits=NA),file.path(out[[1]],"synthetic-input.json"))
 writeLines(jsonlite::toJSON(result,auto_unbox=TRUE,null="null",digits=NA),file.path(out[[1]],"results.json"))
}
cat("PASS: 3 groups x 3 replicates, shared fits, 3 contrasts x 2 methods; all statistics agree with direct package calls at 1e-12 tolerance.\n")
