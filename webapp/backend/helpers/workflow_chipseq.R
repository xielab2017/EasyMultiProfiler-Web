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

chip_bam_dir <- function(session_id) {
  d <- file.path(chip_session_dir(chip_require_session(session_id)), "bams")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

chip_manifest_path <- function(session_id) {
  file.path(chip_session_dir(chip_require_session(session_id)), "bam_manifest.json")
}

chip_load_manifest <- function(session_id) {
  mp <- chip_manifest_path(session_id)
  if (!file.exists(mp)) return(list(files = list()))
  out <- tryCatch(jsonlite::fromJSON(mp, simplifyVector = FALSE), error = function(e) list(files = list()))
  if (is.null(out$files)) out$files <- list()
  out
}

chip_save_manifest <- function(session_id, manifest) {
  mp <- chip_manifest_path(session_id)
  jsonlite::write_json(manifest, mp, auto_unbox = TRUE, pretty = TRUE)
  invisible(manifest)
}

chip_genome_config <- function(genome = "hs") {
  g <- tolower(substr(as.character(genome)[1], 1, 2))
  if (g %in% c("mm", "mu", "m")) {
    list(
      macs = "mm",
      txdb = "TxDb.Mmusculus.UCSC.mm10.knownGene",
      anno_db = "org.Mm.eg.db",
      kegg = "mmu"
    )
  } else {
    list(
      macs = "hs",
      txdb = "TxDb.Hsapiens.UCSC.hg19.knownGene",
      anno_db = "org.Hs.eg.db",
      kegg = "hsa"
    )
  }
}

chip_ensure_bam <- function(path, dest_dir = NULL) {
  path <- as.character(path)[1]
  if (!file.exists(path)) stop("File not found: ", path)
  ext <- tolower(tools::file_ext(path))
  if (ext == "bam") return(path)
  if (ext == "sam") {
    samtools <- Sys.which("samtools")
    if (!nzchar(samtools)) stop("samtools is required to convert SAM to BAM.")
    dest_dir <- dest_dir %||% dirname(path)
    dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
    out <- file.path(dest_dir, paste0(tools::file_path_sans_ext(basename(path)), ".bam"))
    if (!file.exists(out)) {
      status <- system2(samtools, c("view", "-bS", path, "-o", out))
      if (!identical(status, 0L)) stop("samtools view failed for ", basename(path))
    }
    return(out)
  }
  stop("Unsupported alignment format (use .bam or .sam): ", basename(path))
}

chip_bam_format_flag <- function(path) {
  ext <- tolower(tools::file_ext(as.character(path)[1]))
  if (ext == "sam") "SAM" else "BAM"
}

.chip_as_char_vec <- function(x) {
  if (is.null(x)) return(character(0))
  if (is.list(x)) x <- unlist(x, use.names = FALSE)
  v <- unique(trimws(as.character(x)))
  v[nzchar(v)]
}

chip_upload_bam <- function(session_id, src_path, original_name = NULL, group = "t") {
  session_id <- chip_require_session(session_id)
  src_path <- chip_require_string(src_path, "src_path")
  if (!file.exists(src_path)) stop("Uploaded file not found on server.")
  grp <- tolower(chip_require_string(group, "group"))
  if (!grp %in% c("t", "c", "control", "treatment")) stop("group must be 't' (treatment) or 'c' (control).")
  grp <- if (grp %in% c("c", "control")) "c" else "t"
  bdir <- chip_bam_dir(session_id)
  oname <- if (!is.null(original_name) && nzchar(as.character(original_name)[1])) {
    basename(as.character(original_name)[1])
  } else basename(src_path)
  oname <- make.names(oname, unique = TRUE)
  dest <- file.path(bdir, oname)
  if (!identical(normalizePath(src_path), normalizePath(dest, mustWork = FALSE))) {
    file.copy(src_path, dest, overwrite = TRUE)
  }
  bam_path <- chip_ensure_bam(dest, bdir)
  manifest <- chip_load_manifest(session_id)
  files <- manifest$files
  files <- Filter(function(f) !identical(f$name, oname), files)
  entry <- list(
    id = paste0("bam_", format(Sys.time(), "%Y%m%d%H%M%S"), "_", length(files) + 1L),
    name = oname,
    path = bam_path,
    group = grp,
    format = chip_bam_format_flag(bam_path)
  )
  files[[length(files) + 1L]] <- entry
  manifest$files <- files
  chip_save_manifest(session_id, manifest)
  list(success = TRUE, file = entry, manifest = manifest)
}

chip_register_bams <- function(session_id, entries) {
  session_id <- chip_require_session(session_id)
  if (is.null(entries) || !length(entries)) stop("entries is required (list of {path, group}).")
  manifest <- chip_load_manifest(session_id)
  files <- manifest$files
  for (e in entries) {
    p <- chip_require_string(e$path %||% e[["path"]], "path")
    if (!file.exists(p)) stop("BAM/SAM not found: ", p)
    grp <- tolower(as.character(e$group %||% e[["group"]] %||% "t")[1])
    grp <- if (grp %in% c("c", "control")) "c" else "t"
    bam_path <- chip_ensure_bam(p, chip_bam_dir(session_id))
    nm <- basename(bam_path)
    files <- Filter(function(f) !identical(f$path, bam_path), files)
    files[[length(files) + 1L]] <- list(
      id = paste0("reg_", length(files) + 1L),
      name = nm,
      path = bam_path,
      group = grp,
      format = chip_bam_format_flag(bam_path)
    )
  }
  manifest$files <- files
  chip_save_manifest(session_id, manifest)
  list(success = TRUE, n_files = length(files), manifest = manifest)
}

chip_scan_folder <- function(session_id, folder_path, default_group = "t") {
  session_id <- chip_require_session(session_id)
  folder_path <- chip_require_string(folder_path, "folder_path")
  if (!dir.exists(folder_path)) stop("folder_path does not exist.")
  hits <- list.files(folder_path, pattern = "\\.(bam|sam|BAM|SAM)$", full.names = TRUE)
  if (!length(hits)) stop("No BAM/SAM files found in folder.")
  grp <- tolower(as.character(default_group)[1])
  grp <- if (grp %in% c("c", "control")) "c" else "t"
  entries <- lapply(hits, function(p) list(path = p, group = grp))
  chip_register_bams(session_id, entries)
}

chip_list_bams <- function(session_id) {
  manifest <- chip_load_manifest(session_id)
  t_n <- sum(vapply(manifest$files, function(f) identical(f$group, "t"), logical(1)))
  c_n <- sum(vapply(manifest$files, function(f) identical(f$group, "c"), logical(1)))
  list(
    success = TRUE,
    files = manifest$files,
    n_treatment = t_n,
    n_control = c_n,
    last_peaks = manifest$last_peaks %||% NULL,
    last_annotation_csv = manifest$last_annotation_csv %||% ""
  )
}

chip_set_bam_group <- function(session_id, file_id, group) {
  session_id <- chip_require_session(session_id)
  manifest <- chip_load_manifest(session_id)
  grp <- tolower(chip_require_string(group, "group"))
  grp <- if (grp %in% c("c", "control")) "c" else "t"
  found <- FALSE
  for (i in seq_along(manifest$files)) {
    if (identical(manifest$files[[i]]$id, file_id) || identical(manifest$files[[i]]$name, file_id)) {
      manifest$files[[i]]$group <- grp
      found <- TRUE
      break
    }
  }
  if (!found) stop("BAM entry not found: ", file_id)
  chip_save_manifest(session_id, manifest)
  list(success = TRUE, manifest = manifest)
}

.chip_manifest_bams <- function(session_id) {
  manifest <- chip_load_manifest(session_id)
  t_bams <- character(0)
  c_bams <- character(0)
  for (f in manifest$files) {
    p <- f$path %||% ""
    if (!nzchar(p) || !file.exists(p)) next
    if (identical(f$group, "c")) c_bams <- c(c_bams, p) else t_bams <- c(t_bams, p)
  }
  list(treatment = unique(t_bams), control = unique(c_bams))
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

chip_call_peaks <- function(session_id, treatment_bam = NULL, control_bam = NULL,
                            treatment_bams = NULL, control_bams = NULL,
                            use_manifest = FALSE,
                            genome = "hs", run_id = NULL,
                            qvalue = 0.01, pvalue = NULL,
                            format = NULL, preset = NULL,
                            broad = FALSE, broad_cutoff = NULL,
                            keep_dup = "auto",
                            nomodel = FALSE, shift = NULL, extsize = NULL,
                            fix_bimodal = FALSE, tsize = NULL,
                            call_summits = FALSE, fe_cutoff = NULL,
                            min_length = NULL, max_gap = NULL,
                            nolambda = FALSE, slocal = NULL, llocal = NULL,
                            scale_to = NULL, cutoff_analysis = FALSE,
                            save_bdg = FALSE,
                            prefer_macs = "auto", extra_args = NULL) {
  session_id <- chip_require_session(session_id)
  gcfg <- chip_genome_config(genome)
  macs_genome <- gcfg$macs

  if (!is.null(preset) && nzchar(as.character(preset)[1]) &&
      !identical(tolower(as.character(preset)[1]), "custom")) {
    pr <- .chip_macs_preset(as.character(preset)[1])
    for (nm in names(pr)) {
      if (!nm %in% c("treatment_bam", "control_bam", "treatment_bams", "control_bams",
                     "use_manifest", "genome", "run_id", "prefer_macs", "extra_args")) {
        assign(nm, pr[[nm]], envir = environment())
      }
    }
  }

  t_bams <- .chip_as_char_vec(treatment_bams)
  c_bams <- .chip_as_char_vec(control_bams)
  if (!length(t_bams) && !is.null(treatment_bam)) t_bams <- .chip_as_char_vec(treatment_bam)
  if (!length(c_bams) && !is.null(control_bam)) c_bams <- .chip_as_char_vec(control_bam)
  if (isTRUE(use_manifest) || (!length(t_bams) && !length(c_bams))) {
    mb <- .chip_manifest_bams(session_id)
    if (!length(t_bams)) t_bams <- mb$treatment
    if (!length(c_bams)) c_bams <- mb$control
  }
  if (!length(t_bams)) {
    stop("At least one Treatment (IP/ChIP) BAM/SAM is required. Upload files to the Treatment section.")
  }
  for (p in c(t_bams, c_bams)) {
    if (!file.exists(p)) stop("BAM/SAM not found: ", p)
  }

  macs <- chip_find_macs(prefer_macs)
  if (is.null(macs)) {
    stop("MACS2/3 is not installed. Please install macs3 (recommended) or macs2.")
  }

  fmt <- if (!is.null(format) && nzchar(as.character(format)[1])) {
    toupper(as.character(format)[1])
  } else {
    chip_bam_format_flag(t_bams[1])
  }
  if (fmt %in% c("BAMPE", "BEDPE") && isTRUE(nomodel)) {
    if (!is.null(shift) && nzchar(as.character(shift)[1]) && as.character(shift)[1] != "0") {
      stop("--shift cannot be non-zero when format is BAMPE/BEDPE. Use BAM format for --nomodel workflows.")
    }
  }

  qv <- suppressWarnings(as.numeric(qvalue))
  if (!is.finite(qv) || qv <= 0 || qv >= 1) qv <- 0.01
  pv <- suppressWarnings(as.numeric(pvalue))
  use_p <- is.finite(pv) && pv > 0 && pv < 1

  out_dir <- chip_run_dir(session_id, run_id)
  run_name <- paste0("chipseq_", format(Sys.time(), "%H%M%S"))
  base_args <- c(
    "callpeak",
    "-t", t_bams,
    "-f", fmt,
    "-g", macs_genome,
    "-n", run_name,
    "--outdir", out_dir,
    "--keep-dup", chip_require_string(keep_dup, "keep_dup")
  )
  if (use_p) {
    base_args <- c(base_args, "-p", as.character(pv))
  } else {
    base_args <- c(base_args, "-q", as.character(qv))
  }
  if (length(c_bams)) base_args <- c(base_args, "-c", c_bams)
  if (isTRUE(broad)) base_args <- c(base_args, "--broad")
  if (!is.null(broad_cutoff) && nzchar(as.character(broad_cutoff)[1])) {
    bc <- suppressWarnings(as.numeric(broad_cutoff))
    if (is.finite(bc)) base_args <- c(base_args, "--broad-cutoff", as.character(bc))
  }
  if (isTRUE(nomodel)) base_args <- c(base_args, "--nomodel")
  if (!is.null(shift) && nzchar(as.character(shift)[1])) {
    base_args <- c(base_args, "--shift", as.character(shift)[1])
  }
  if (!is.null(extsize) && nzchar(as.character(extsize)[1])) {
    base_args <- c(base_args, "--extsize", as.character(extsize)[1])
  }
  if (isTRUE(fix_bimodal)) base_args <- c(base_args, "--fix-bimodal")
  if (!is.null(tsize) && nzchar(as.character(tsize)[1])) {
    base_args <- c(base_args, "-s", as.character(tsize)[1])
  }
  if (isTRUE(call_summits)) base_args <- c(base_args, "--call-summits")
  if (!is.null(fe_cutoff) && nzchar(as.character(fe_cutoff)[1])) {
    fe <- suppressWarnings(as.numeric(fe_cutoff))
    if (is.finite(fe)) base_args <- c(base_args, "--fe-cutoff", as.character(fe))
  }
  if (!is.null(min_length) && nzchar(as.character(min_length)[1])) {
    base_args <- c(base_args, "--min-length", as.character(min_length)[1])
  }
  if (!is.null(max_gap) && nzchar(as.character(max_gap)[1])) {
    base_args <- c(base_args, "--max-gap", as.character(max_gap)[1])
  }
  if (isTRUE(nolambda)) base_args <- c(base_args, "--nolambda")
  if (!is.null(slocal) && nzchar(as.character(slocal)[1])) {
    base_args <- c(base_args, "--slocal", as.character(slocal)[1])
  }
  if (!is.null(llocal) && nzchar(as.character(llocal)[1])) {
    base_args <- c(base_args, "--llocal", as.character(llocal)[1])
  }
  if (!is.null(scale_to) && nzchar(as.character(scale_to)[1])) {
    st <- tolower(as.character(scale_to)[1])
    if (st %in% c("large", "small")) base_args <- c(base_args, "--scale-to", st)
  }
  if (isTRUE(cutoff_analysis)) base_args <- c(base_args, "--cutoff-analysis")
  if (isTRUE(save_bdg)) base_args <- c(base_args, "-B")
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
  cutoff_txt <- list.files(out_dir, pattern = "_cutoff_analysis\\.txt$", full.names = TRUE)
  peak_file <- if (length(peaks)) peaks[[1]] else ""
  manifest <- chip_load_manifest(session_id)
  manifest$last_peaks <- list(
    run_dir = out_dir,
    peak_file = peak_file,
    summit_file = if (length(summits)) summits[[1]] else "",
    treatment_bams = t_bams,
    control_bams = c_bams,
    genome = macs_genome,
    preset = preset %||% "custom",
    macs_args = base_args
  )
  chip_save_manifest(session_id, manifest)

  list(
    success = TRUE,
    run_dir = out_dir,
    caller = macs$cmd,
    run_name = run_name,
    peak_file = peak_file,
    summit_file = if (length(summits)) summits[[1]] else "",
    xls_file = if (length(xls)) xls[[1]] else "",
    cutoff_analysis_file = if (length(cutoff_txt)) cutoff_txt[[1]] else "",
    log_file = log_file,
    err_file = err_file,
    treatment_bams = t_bams,
    control_bams = c_bams,
    n_treatment = length(t_bams),
    n_control = length(c_bams),
    genome = macs_genome,
    macs_command = paste(macs$cmd, paste(base_args, collapse = " "))
  )
}

.chip_macs_presets_catalog <- function() {
  list(
    chipseq_tf = list(
      label = "ChIP-seq TF (default model)",
      description = "Standard TF ChIP-seq: MACS builds shifting model automatically. -f BAM, -q 0.01.",
      format = "BAM", qvalue = 0.01, keep_dup = "auto", broad = FALSE,
      nomodel = FALSE, call_summits = FALSE
    ),
    chipseq_histone_broad = list(
      label = "Histone / broad marks",
      description = "Broad peak calling for H3K27me3, H3K36me3 etc. --broad --broad-cutoff 0.1.",
      format = "BAM", qvalue = 0.01, broad = TRUE, broad_cutoff = 0.1, keep_dup = "auto"
    ),
    atac_paired = list(
      label = "ATAC-seq (paired-end BAMPE)",
      description = "Use fragment length from paired-end alignments. -f BAMPE -q 0.01.",
      format = "BAMPE", qvalue = 0.05, keep_dup = "auto", broad = FALSE
    ),
    atac_cutting_site = list(
      label = "ATAC/CUT&Tag cutting site (single-end)",
      description = "Focus on Tn5/DNase cut sites: --nomodel --shift -75 --extsize 150 --keep-dup all.",
      format = "BAM", qvalue = 0.05, nomodel = TRUE, shift = -75, extsize = 150,
      keep_dup = "all", broad = FALSE
    ),
    cuttag_tn5 = list(
      label = "CUT&Tag / scATAC insertion (MACS3 doc)",
      description = "MACS3 example: --nomodel --shift -50 --extsize 100 on single-end BAM.",
      format = "BAM", qvalue = 0.01, nomodel = TRUE, shift = -50, extsize = 100,
      keep_dup = "auto"
    ),
    dnase_smoothed = list(
      label = "DNase-seq smoothed window",
      description = "MACS3 doc: --nomodel --shift -100 --extsize 200 for cutting-site enrichment.",
      format = "BAM", qvalue = 0.05, nomodel = TRUE, shift = -100, extsize = 200,
      keep_dup = "auto"
    ),
    no_control = list(
      label = "No control (treatment only)",
      description = "Treatment only; optional --nolambda for background. Use with caution.",
      format = "BAM", qvalue = 0.01, nolambda = TRUE, keep_dup = "auto"
    )
  )
}

.chip_macs_preset <- function(name) {
  cat <- .chip_macs_presets_catalog()
  key <- tolower(as.character(name)[1])
  if (!key %in% names(cat)) stop("Unknown MACS preset: ", name)
  cat[[key]]
}

chip_macs_presets <- function() {
  cat <- .chip_macs_presets_catalog()
  lapply(names(cat), function(k) {
    x <- cat[[k]]
    list(id = k, label = x$label, description = x$description)
  })
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
  manifest <- chip_load_manifest(session_id)
  manifest$last_annotation_csv <- out_csv
  chip_save_manifest(session_id, manifest)
  list(success = TRUE, n_peaks = nrow(df), annotation_csv = out_csv, top = utils::head(df, 20))
}

.chip_peak_score_col <- function(df) {
  intersect(c("score", "V5", "fold_enrichment", "signalValue", "FE"), names(df))[1]
}

.chip_promoter_labels <- function() {
  c("Promoter (<=1kb)", "Promoter (1-2kb)", "Promoter (2-3kb)")
}

.chip_enrich_symbol_set <- function(gene_symbols, anno_db_pkg, kegg_org, out_dir, prefix = "all",
                                   p_cutoff = 0.05) {
  gene_symbols <- unique(trimws(as.character(gene_symbols)))
  gene_symbols <- gene_symbols[nzchar(gene_symbols)]
  if (length(gene_symbols) < 3) {
    return(list(success = FALSE, message = "Fewer than 3 genes for enrichment.", plots = list(), tables = list()))
  }
  if (!requireNamespace("clusterProfiler", quietly = TRUE)) {
    stop("clusterProfiler is required for GO/KEGG enrichment.")
  }
  if (!suppressWarnings(requireNamespace(anno_db_pkg, quietly = TRUE))) {
    stop(sprintf("OrgDb package not installed: %s", anno_db_pkg))
  }
  orgdb <- getExportedValue(anno_db_pkg, anno_db_pkg)
  plots <- list()
  tables <- list()
  for (ont in c("BP", "CC", "MF")) {
    ego <- tryCatch(
      clusterProfiler::enrichGO(
        gene = gene_symbols, OrgDb = orgdb, keyType = "SYMBOL",
        ont = ont, pvalueCutoff = p_cutoff, qvalueCutoff = 1, pAdjustMethod = "BH"
      ),
      error = function(e) NULL
    )
    if (!is.null(ego) && nrow(as.data.frame(ego))) {
      tbl <- as.data.frame(ego)
      fn <- file.path(out_dir, sprintf("%s_GO_%s.csv", prefix, ont))
      utils::write.csv(tbl, fn, row.names = FALSE)
      tables[[paste0("GO_", ont)]] <- fn
      if (requireNamespace("enrichplot", quietly = TRUE)) {
        p <- tryCatch(
          enrichplot::dotplot(ego, showCategory = min(15L, nrow(tbl))) +
            ggplot2::labs(title = sprintf("GO-%s (%s genes)", ont, prefix)) +
            emp_pub_theme(base_size = 11),
          error = function(e) NULL
        )
        if (!is.null(p)) plots[[paste0("GO_", ont)]] <- plot_to_base64(p, width = 9, height = 6)
      }
    }
  }
  gene_df <- tryCatch(
    clusterProfiler::bitr(gene_symbols, fromType = "SYMBOL",
                          toType = c("ENSEMBL", "ENTREZID"), OrgDb = orgdb),
    error = function(e) data.frame()
  )
  if (nrow(gene_df)) {
    gene_df <- gene_df[!duplicated(gene_df[[1]]), , drop = FALSE]
    entrez <- unique(gene_df$ENTREZID)
    entrez <- entrez[!is.na(entrez) & nzchar(as.character(entrez))]
    if (length(entrez) >= 3) {
      kk <- tryCatch(
        clusterProfiler::enrichKEGG(
          gene = entrez, organism = kegg_org, keyType = "ncbi-geneid",
          minGSSize = 1, pAdjustMethod = "BH", pvalueCutoff = 1
        ),
        error = function(e) NULL
      )
      if (!is.null(kk) && nrow(as.data.frame(kk))) {
        tbl <- as.data.frame(kk)
        fn <- file.path(out_dir, sprintf("%s_KEGG.csv", prefix))
        utils::write.csv(tbl, fn, row.names = FALSE)
        tables$KEGG <- fn
        if (requireNamespace("enrichplot", quietly = TRUE)) {
          p <- tryCatch(
            enrichplot::dotplot(kk, showCategory = min(15L, nrow(tbl))) +
              ggplot2::labs(title = sprintf("KEGG (%s genes)", prefix)) +
              emp_pub_theme(base_size = 11),
            error = function(e) NULL
          )
          if (!is.null(p)) plots$KEGG <- plot_to_base64(p, width = 9, height = 6)
        }
      }
    }
  }
  list(success = TRUE, plots = plots, tables = tables, n_genes = length(gene_symbols))
}

chip_annotate_peaks_full <- function(session_id, peak_file = NULL,
                                     genome = "hs",
                                     tss_upstream = -3000, tss_downstream = 3000,
                                     score_cutoff = 5,
                                     promoter_only = FALSE) {
  session_id <- chip_require_session(session_id)
  gcfg <- chip_genome_config(genome)
  if (is.null(peak_file) || !nzchar(as.character(peak_file)[1])) {
    manifest <- chip_load_manifest(session_id)
    peak_file <- manifest$last_peaks$peak_file %||% ""
  }
  peak_file <- chip_require_string(peak_file, "peak_file")
  if (!file.exists(peak_file)) stop("peak_file not found.")

  base <- chip_annotate_peaks(
    session_id = session_id,
    peak_file = peak_file,
    txdb = gcfg$txdb,
    anno_db = gcfg$anno_db,
    tss_upstream = tss_upstream,
    tss_downstream = tss_downstream
  )
  anno_csv <- base$annotation_csv
  df <- read.csv(anno_csv, stringsAsFactors = FALSE, check.names = FALSE)
  out_dir <- dirname(anno_csv)
  plots <- list()
  tables <- list(annotation_all = anno_csv)

  if (requireNamespace("ChIPseeker", quietly = TRUE)) {
    peak_obj <- tryCatch(ChIPseeker::readPeakFile(peak_file), error = function(e) NULL)
    if (!is.null(peak_obj)) {
      txdb_obj <- getExportedValue(gcfg$txdb, gcfg$txdb)
      anno_db_use <- getExportedValue(gcfg$anno_db, gcfg$anno_db)
      peak_anno <- ChIPseeker::annotatePeak(
        peak = peak_obj,
        TxDb = txdb_obj,
        annoDb = anno_db_use,
        tssRegion = c(as.integer(tss_upstream), as.integer(tss_downstream))
      )
      p_pie <- tryCatch({
        ChIPseeker::plotAnnoPie(peak_anno)
      }, error = function(e) NULL)
      if (!is.null(p_pie)) plots$annotation_pie <- plot_to_base64(p_pie, width = 7, height = 6)
    }
  }

  sc_col <- .chip_peak_score_col(df)
  sc_cut <- suppressWarnings(as.numeric(score_cutoff))
  if (is.finite(sc_cut) && !is.na(sc_col)) {
    df_filt <- df[!is.na(suppressWarnings(as.numeric(df[[sc_col]]))) &
                    suppressWarnings(as.numeric(df[[sc_col]])) >= sc_cut, , drop = FALSE]
    if (nrow(df_filt)) {
      fn <- file.path(out_dir, sprintf("peaks_score_ge_%s.csv", sc_cut))
      utils::write.csv(df_filt, fn, row.names = FALSE)
      tables$high_confidence <- fn
    }
  }

  promo <- df[df$annotation %in% .chip_promoter_labels(), , drop = FALSE]
  if (nrow(promo)) {
    fn <- file.path(out_dir, "peaks_promoter.csv")
    utils::write.csv(promo, fn, row.names = FALSE)
    tables$promoter <- fn
    promo_1kb <- promo[promo$annotation == "Promoter (<=1kb)", , drop = FALSE]
    if (nrow(promo_1kb)) {
      fn1 <- file.path(out_dir, "peaks_promoter_1kb.csv")
      utils::write.csv(promo_1kb, fn1, row.names = FALSE)
      tables$promoter_1kb <- fn1
    }
  }

  gene_col <- intersect(c("SYMBOL", "geneSymbol", "geneId"), names(df))[1]
  genes_all <- if (!is.na(gene_col)) unique(df[[gene_col]]) else character(0)
  enrich_all <- .chip_enrich_symbol_set(genes_all, gcfg$anno_db, gcfg$kegg, out_dir, "all_peaks")
  plots <- c(plots, enrich_all$plots)
  tables <- c(tables, enrich_all$tables)

  if (nrow(promo)) {
    genes_promo <- unique(promo[[gene_col]])
    enrich_promo <- .chip_enrich_symbol_set(genes_promo, gcfg$anno_db, gcfg$kegg, out_dir, "promoter")
    for (nm in names(enrich_promo$plots)) plots[[paste0("promoter_", nm)]] <- enrich_promo$plots[[nm]]
    for (nm in names(enrich_promo$tables)) tables[[paste0("promoter_", nm)]] <- enrich_promo$tables[[nm]]
  }

  manifest <- chip_load_manifest(session_id)
  manifest$last_annotation_csv <- anno_csv
  manifest$last_annotation_full <- list(tables = tables, n_peaks = nrow(df))
  chip_save_manifest(session_id, manifest)

  list(
    success = TRUE,
    n_peaks = nrow(df),
    annotation_csv = anno_csv,
    plots = plots,
    tables = tables,
    top = utils::head(df, 20)
  )
}

chip_rnaseq_coanalysis <- function(session_id,
                                     rnaseq_experiment,
                                     peak_annotation_csv = NULL,
                                     genome = "hs",
                                     score_cutoff = 10,
                                     min_total_counts = 100,
                                     rnaseq_p_cutoff = 0.05,
                                     promoter_filter = TRUE) {
  session_id <- chip_require_session(session_id)
  rnaseq_experiment <- chip_require_string(rnaseq_experiment, "rnaseq_experiment")
  if (is.null(peak_annotation_csv) || !nzchar(as.character(peak_annotation_csv)[1])) {
    manifest <- chip_load_manifest(session_id)
    peak_annotation_csv <- manifest$last_annotation_csv %||% ""
  }
  peak_annotation_csv <- chip_require_string(peak_annotation_csv, "peak_annotation_csv")
  if (!file.exists(peak_annotation_csv)) stop("peak_annotation_csv not found. Run ChIPseeker annotation first.")

  gcfg <- chip_genome_config(genome)
  anno <- read.csv(peak_annotation_csv, stringsAsFactors = FALSE, check.names = FALSE)
  gene_col <- intersect(c("SYMBOL", "geneSymbol", "geneId"), names(anno))[1]
  if (is.na(gene_col)) stop("No gene symbol column in peak annotation.")
  sc_col <- .chip_peak_score_col(anno)
  sc_cut <- suppressWarnings(as.numeric(score_cutoff))

  chip_df <- anno
  if (is.finite(sc_cut) && !is.na(sc_col)) {
    chip_df <- chip_df[!is.na(suppressWarnings(as.numeric(chip_df[[sc_col]]))) &
                         suppressWarnings(as.numeric(chip_df[[sc_col]])) >= sc_cut, , drop = FALSE]
  }
  if (isTRUE(promoter_filter)) {
    chip_df <- chip_df[chip_df$annotation %in% .chip_promoter_labels(), , drop = FALSE]
  }
  chip_genes <- unique(trimws(as.character(chip_df[[gene_col]])))
  chip_genes <- chip_genes[nzchar(chip_genes)]
  if (!length(chip_genes)) stop("No peak-associated genes after filtering. Relax score_cutoff or promoter_filter.")

  out_dir <- chip_run_dir(session_id, "rnaseq_coanalysis")
  plots <- list()
  tables <- list()

  empt <- load_empt(session_id, rnaseq_experiment)
  ad <- as.data.frame(SummarizedExperiment::assays(empt)[[1]], check.names = FALSE)
  if (!nrow(ad)) stop("RNA-seq expression matrix is empty.")
  feat_col <- intersect(c("feature", "GeneID", "gene", "SYMBOL"), names(ad))[1]
  if (!is.na(feat_col) && feat_col != "feature") {
    rownames(ad) <- as.character(ad[[feat_col]])
    ad[[feat_col]] <- NULL
  }
  sample_cols <- setdiff(names(ad), c("feature", "GeneID", "gene", "SYMBOL", "gene_name"))
  if (!length(sample_cols)) sample_cols <- names(ad)

  expr_sub <- ad[rownames(ad) %in% chip_genes, sample_cols, drop = FALSE]
  min_cnt <- suppressWarnings(as.numeric(min_total_counts))
  if (!is.finite(min_cnt)) min_cnt <- 100
  if (nrow(expr_sub)) {
    rs <- rowSums(expr_sub, na.rm = TRUE)
    expr_sub <- expr_sub[is.finite(rs) & rs >= min_cnt, , drop = FALSE]
  }
  if (nrow(expr_sub) >= 2 && ncol(expr_sub) >= 2) {
    mat <- log10(as.matrix(expr_sub) + 1)
    if (requireNamespace("pheatmap", quietly = TRUE)) {
      hp <- tryCatch({
        pheatmap::pheatmap(
          mat, scale = "row", cluster_rows = TRUE, cluster_cols = FALSE,
          show_rownames = nrow(mat) <= 60, border_color = NA,
          silent = TRUE
        )
      }, error = function(e) NULL)
      if (!is.null(hp)) plots$expression_heatmap <- plot_to_base64(hp$gtable, width = 9, height = max(5, nrow(mat) * 0.15 + 3))
    }
    fn <- file.path(out_dir, "chip_gene_expression.csv")
    utils::write.csv(cbind(GeneID = rownames(expr_sub), expr_sub), fn, row.names = FALSE)
    tables$expression <- fn
  }

  raw <- tryCatch(ensure_diff_raw(session_id, rnaseq_experiment), error = function(e) NULL)
  if (!is.null(raw) && nrow(raw)) {
    gcol <- intersect(c("feature", "gene", "SYMBOL", "GeneID", "id"), names(raw))[1]
    pcol <- intersect(c("padj", "p_val_adj", "P.Value", "pvalue", "p"), names(raw))[1]
    if (!is.na(gcol)) {
      diff_sub <- raw[as.character(raw[[gcol]]) %in% chip_genes, , drop = FALSE]
      if (nrow(diff_sub)) {
        fn <- file.path(out_dir, "chip_genes_diff.csv")
        utils::write.csv(diff_sub, fn, row.names = FALSE)
        tables$diff <- fn
        pcut <- suppressWarnings(as.numeric(rnaseq_p_cutoff))
        if (!is.finite(pcut)) pcut <- 0.05
        if (!is.na(pcol)) {
          pv <- suppressWarnings(as.numeric(diff_sub[[pcol]]))
          diff_sig <- diff_sub[!is.na(pv) & pv <= pcut, , drop = FALSE]
          if (nrow(diff_sig)) {
            fn2 <- file.path(out_dir, "chip_genes_diff_sig.csv")
            utils::write.csv(diff_sig, fn2, row.names = FALSE)
            tables$diff_sig <- fn2
          }
        }
        vplot <- tryCatch(
          make_volcano(session_id, rnaseq_experiment,
                       fc_cutoff = 0.5, p_cutoff = pcut,
                       use_padj = identical(pcol, "padj") || grepl("adj", pcol, ignore.case = TRUE)),
          error = function(e) NULL
        )
        if (!is.null(vplot) && nzchar(vplot)) plots$volcano_all <- vplot
      }
    }
  }

  enrich_co <- .chip_enrich_symbol_set(chip_genes, gcfg$anno_db, gcfg$kegg, out_dir, "coanalysis")
  plots <- c(plots, enrich_co$plots)
  tables <- c(tables, enrich_co$tables)

  if (requireNamespace("ChIPseeker", quietly = TRUE) && nrow(chip_df)) {
    gr <- tryCatch({
      GenomicRanges::GRanges(
        seqnames = chip_df$seqnames,
        ranges = IRanges::IRanges(start = as.integer(chip_df$start), end = as.integer(chip_df$end)),
        strand = chip_df$strand
      )
    }, error = function(e) NULL)
    if (!is.null(gr)) {
      txdb_obj <- getExportedValue(gcfg$txdb, gcfg$txdb)
      anno_db_use <- getExportedValue(gcfg$anno_db, gcfg$anno_db)
      peak_anno_f <- tryCatch(
        ChIPseeker::annotatePeak(gr, TxDb = txdb_obj, annoDb = anno_db_use, tssRegion = c(-3000, 3000)),
        error = function(e) NULL
      )
      if (!is.null(peak_anno_f)) {
        p_pie <- tryCatch(ChIPseeker::plotAnnoPie(peak_anno_f), error = function(e) NULL)
        if (!is.null(p_pie)) plots$filtered_annotation_pie <- plot_to_base64(p_pie, width = 7, height = 6)
      }
    }
  }

  list(
    success = TRUE,
    chip_genes_n = length(chip_genes),
    rnaseq_experiment = rnaseq_experiment,
    plots = plots,
    tables = tables,
    chip_genes = utils::head(chip_genes, 500)
  )
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
