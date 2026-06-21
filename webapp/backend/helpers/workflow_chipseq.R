# ChIP-seq workflow helpers: BAM -> MACS2/3 peak calling -> annotation -> cross-omics bridge.

chip_require_string <- function(x, name) {
  v <- as.character(x %||% "")[1]
  if (!nzchar(trimws(v))) stop(sprintf("%s is required.", name))
  trimws(v)
}

chip_require_session <- function(session_id) {
  session_id <- chip_require_string(session_id, "session_id")
  ensure_session_dir(session_id)
  session_id
}

chip_session_dir <- function(session_id) {
  file.path(session_path(session_id), "chipseq")
}

chip_run_dir <- function(session_id, run_id = NULL) {
  sid <- chip_require_session(session_id)
  root <- chip_session_dir(sid)
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  if (is.null(run_id) || !nzchar(run_id)) {
    run_id <- format(Sys.time(), "%Y%m%d_%H%M%S")
  }
  out <- file.path(root, make.names(run_id))
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  out
}

chip_find_macs <- function(prefer = c("auto", "macs3", "macs2")) {
  prefer <- tolower(chip_require_string(prefer[1], "prefer"))
  candidates <- switch(prefer,
    macs3 = c("macs3", "macs2"),
    macs2 = c("macs2", "macs3"),
    c("macs3", "macs2")
  )
  for (cmd in candidates) {
    p <- Sys.which(cmd)
    if (nzchar(p)) return(list(cmd = cmd, path = p))
  }
  NULL
}

chip_profile <- function(session_id, experiment = NULL) {
  session_id <- chip_require_session(session_id)
  out <- list(
    has_macs3 = nzchar(Sys.which("macs3")),
    has_macs2 = nzchar(Sys.which("macs2")),
    has_chipseeker = requireNamespace("ChIPseeker", quietly = TRUE),
    has_genomicfeatures = requireNamespace("GenomicFeatures", quietly = TRUE),
    has_orgdb_hs = requireNamespace("org.Hs.eg.db", quietly = TRUE),
    has_orgdb_mm = requireNamespace("org.Mm.eg.db", quietly = TRUE)
  )
  if (!is.null(experiment) && nzchar(as.character(experiment)[1])) {
    empt <- load_empt(session_id, as.character(experiment)[1])
    ad <- SummarizedExperiment::assays(empt)[[1]]
    out$experiment <- as.character(experiment)[1]
    out$n_features <- nrow(ad)
    out$n_samples <- ncol(ad)
  }
  out
}

chip_validate <- function(session_id, experiment = NULL) {
  p <- chip_profile(session_id, experiment)
  checks <- list(
    has_peak_caller = isTRUE(p$has_macs3) || isTRUE(p$has_macs2),
    has_annotation_stack = isTRUE(p$has_chipseeker) && isTRUE(p$has_genomicfeatures)
  )
  if (!is.null(experiment) && nzchar(as.character(experiment)[1])) {
    checks$has_features <- isTRUE((p$n_features %||% 0) > 0)
    checks$has_samples <- isTRUE((p$n_samples %||% 0) > 1)
  }
  list(success = TRUE, checks = checks, profile = p)
}

chip_call_peaks <- function(session_id, treatment_bam, control_bam = NULL,
                            genome = "hs", run_id = NULL, qvalue = 0.01,
                            broad = FALSE, keep_dup = "auto",
                            shift = NULL, extsize = NULL,
                            prefer_macs = "auto", extra_args = NULL) {
  session_id <- chip_require_session(session_id)
  treatment_bam <- chip_require_string(treatment_bam, "treatment_bam")
  if (!file.exists(treatment_bam)) stop("treatment_bam not found on server path.")
  if (!is.null(control_bam) && nzchar(as.character(control_bam)[1]) && !file.exists(control_bam)) {
    stop("control_bam not found on server path.")
  }

  macs <- chip_find_macs(prefer_macs)
  if (is.null(macs)) {
    stop("MACS2/3 is not installed. Please install macs3 (recommended) or macs2.")
  }

  qv <- suppressWarnings(as.numeric(qvalue))
  if (!is.finite(qv) || qv <= 0 || qv >= 1) qv <- 0.01
  out_dir <- chip_run_dir(session_id, run_id)
  run_name <- paste0("chipseq_", format(Sys.time(), "%H%M%S"))
  base_args <- c(
    "callpeak",
    "-t", treatment_bam,
    "-f", "BAM",
    "-g", chip_require_string(genome, "genome"),
    "-n", run_name,
    "--outdir", out_dir,
    "-q", as.character(qv),
    "--keep-dup", chip_require_string(keep_dup, "keep_dup")
  )
  if (!is.null(control_bam) && nzchar(as.character(control_bam)[1])) {
    base_args <- c(base_args, "-c", as.character(control_bam)[1])
  }
  if (isTRUE(broad)) base_args <- c(base_args, "--broad")
  if (!is.null(shift) && nzchar(as.character(shift)[1])) base_args <- c(base_args, "--shift", as.character(shift)[1])
  if (!is.null(extsize) && nzchar(as.character(extsize)[1])) base_args <- c(base_args, "--extsize", as.character(extsize)[1])
  if (!is.null(extra_args) && nzchar(as.character(extra_args)[1])) {
    extra <- strsplit(as.character(extra_args)[1], "\\s+", perl = TRUE)[[1]]
    extra <- extra[nzchar(extra)]
    if (length(extra)) base_args <- c(base_args, extra)
  }

  log_file <- file.path(out_dir, "macs_callpeak.log")
  err_file <- file.path(out_dir, "macs_callpeak.err.log")
  status <- system2(macs$path, args = base_args, stdout = log_file, stderr = err_file)
  if (!identical(status, 0L)) {
    err <- if (file.exists(err_file)) paste(readLines(err_file, warn = FALSE), collapse = "\n") else ""
    stop(sprintf("MACS peak calling failed (%s). %s", macs$cmd, err))
  }

  peaks <- list.files(out_dir, pattern = "(_peaks\\.narrowPeak|_peaks\\.broadPeak)$", full.names = TRUE)
  summits <- list.files(out_dir, pattern = "_summits\\.bed$", full.names = TRUE)
  xls <- list.files(out_dir, pattern = "_peaks\\.xls$", full.names = TRUE)
  list(
    success = TRUE,
    run_dir = out_dir,
    caller = macs$cmd,
    run_name = run_name,
    peak_file = if (length(peaks)) peaks[[1]] else "",
    summit_file = if (length(summits)) summits[[1]] else "",
    xls_file = if (length(xls)) xls[[1]] else "",
    log_file = log_file,
    err_file = err_file
  )
}

chip_annotate_peaks <- function(session_id, peak_file,
                                txdb = "TxDb.Hsapiens.UCSC.hg38.knownGene",
                                anno_db = "org.Hs.eg.db",
                                tss_upstream = -3000, tss_downstream = 3000) {
  session_id <- chip_require_session(session_id)
  peak_file <- chip_require_string(peak_file, "peak_file")
  if (!file.exists(peak_file)) stop("peak_file not found.")
  if (!requireNamespace("ChIPseeker", quietly = TRUE)) {
    stop("ChIPseeker is not installed. Please install Bioconductor package ChIPseeker.")
  }
  if (!requireNamespace("GenomicFeatures", quietly = TRUE)) {
    stop("GenomicFeatures is required for TxDb loading.")
  }

  if (!suppressWarnings(requireNamespace(txdb, quietly = TRUE))) {
    stop(sprintf("TxDb package not installed: %s", txdb))
  }
  txdb_obj <- getExportedValue(txdb, txdb)

  anno_db_use <- NULL
  if (!is.null(anno_db) && nzchar(as.character(anno_db)[1]) &&
      suppressWarnings(requireNamespace(as.character(anno_db)[1], quietly = TRUE))) {
    nm <- as.character(anno_db)[1]
    anno_db_use <- getExportedValue(nm, nm)
  }

  tss_up <- suppressWarnings(as.integer(tss_upstream))
  tss_dn <- suppressWarnings(as.integer(tss_downstream))
  if (!is.finite(tss_up)) tss_up <- -3000L
  if (!is.finite(tss_dn)) tss_dn <- 3000L

  anno <- ChIPseeker::annotatePeak(
    peak = peak_file,
    TxDb = txdb_obj,
    annoDb = anno_db_use,
    tssRegion = c(tss_up, tss_dn)
  )
  df <- as.data.frame(anno)
  out_dir <- chip_run_dir(session_id, "annotation")
  out_csv <- file.path(out_dir, paste0("chipseq_annotation_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".csv"))
  utils::write.csv(df, out_csv, row.names = FALSE)
  list(success = TRUE, n_peaks = nrow(df), annotation_csv = out_csv, top = utils::head(df, 20))
}

chip_cross_integrate <- function(session_id, peak_annotation_csv,
                                 rnaseq_experiment = NULL, proteomics_experiment = NULL,
                                 rnaseq_p_cutoff = 0.05, rnaseq_fc_cutoff = 1,
                                 proteomics_p_cutoff = 0.05, proteomics_fc_cutoff = 0.5) {
  session_id <- chip_require_session(session_id)
  peak_annotation_csv <- chip_require_string(peak_annotation_csv, "peak_annotation_csv")
  if (!file.exists(peak_annotation_csv)) stop("peak_annotation_csv not found.")
  anno <- read.csv(peak_annotation_csv, stringsAsFactors = FALSE, check.names = FALSE)
  gene_cols <- intersect(c("SYMBOL", "geneId", "GENEID", "geneSymbol"), names(anno))
  if (!length(gene_cols)) stop("No gene identifier column found in peak annotation.")
  chip_genes <- unique(trimws(as.character(anno[[gene_cols[1]]])))
  chip_genes <- chip_genes[nzchar(chip_genes)]

  mk_sig <- function(exp_name, p_cut, fc_cut) {
    if (is.null(exp_name) || !nzchar(as.character(exp_name)[1])) return(NULL)
    raw <- tryCatch(ensure_diff_raw(session_id, as.character(exp_name)[1]), error = function(e) NULL)
    if (is.null(raw) || !nrow(raw)) return(NULL)
    pcol <- intersect(c("padj", "p_val_adj", "P.Value", "pvalue", "p"), names(raw))
    fcol <- intersect(c("avg_log2FC", "log2FoldChange", "logFC", "effect"), names(raw))
    gcol <- intersect(c("feature", "gene", "SYMBOL", "id"), names(raw))
    if (!length(gcol)) return(NULL)
    pcut <- suppressWarnings(as.numeric(p_cut)); if (!is.finite(pcut)) pcut <- 0.05
    fcut <- suppressWarnings(as.numeric(fc_cut)); if (!is.finite(fcut)) fcut <- 1
    idx <- rep(TRUE, nrow(raw))
    if (length(pcol)) {
      pv <- suppressWarnings(as.numeric(raw[[pcol[1]]]))
      idx <- idx & !is.na(pv) & pv <= pcut
    }
    if (length(fcol)) {
      fv <- suppressWarnings(as.numeric(raw[[fcol[1]]]))
      idx <- idx & !is.na(fv) & abs(fv) >= fcut
    }
    sig <- unique(trimws(as.character(raw[[gcol[1]]][idx])))
    sig[nzchar(sig)]
  }

  rna_sig <- mk_sig(rnaseq_experiment, rnaseq_p_cutoff, rnaseq_fc_cutoff)
  pro_sig <- mk_sig(proteomics_experiment, proteomics_p_cutoff, proteomics_fc_cutoff)
  overlap_rna <- if (length(rna_sig)) intersect(chip_genes, rna_sig) else character(0)
  overlap_pro <- if (length(pro_sig)) intersect(chip_genes, pro_sig) else character(0)
  overlap_all <- if (length(overlap_rna) && length(overlap_pro)) intersect(overlap_rna, overlap_pro) else character(0)

  list(
    success = TRUE,
    chip_genes_n = length(chip_genes),
    rnaseq_sig_n = length(rna_sig %||% character(0)),
    proteomics_sig_n = length(pro_sig %||% character(0)),
    overlap_chip_rnaseq_n = length(overlap_rna),
    overlap_chip_proteomics_n = length(overlap_pro),
    overlap_triplet_n = length(overlap_all),
    overlap_chip_rnaseq = utils::head(overlap_rna, 300),
    overlap_chip_proteomics = utils::head(overlap_pro, 300),
    overlap_triplet = utils::head(overlap_all, 300),
    recommendation = c(
      "1) Prioritize peaks within promoter/enhancer windows of differential genes.",
      "2) Stratify by gain/loss peaks and direction of RNA/protein changes.",
      "3) Run motif enrichment (HOMER/MEME/ChIPseeker) on overlapping peak sets.",
      "4) Build TF-target regulatory graph from peak-gene links + RNA/protein evidence."
    )
  )
}
