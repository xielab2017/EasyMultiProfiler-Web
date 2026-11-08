# Preranked GO/KEGG GSEA. Input ranks are never filtered by DEG significance.
emp_gsea_ranks <- function(raw, metric = "stat", id_column = "symbol") {
  df <- as.data.frame(raw$data)
  if (!nrow(df) || !id_column %in% names(df)) stop("GSEA requires a complete differential table with gene identifiers.")
  if (!metric %in% c("stat", "log2FoldChange", "signed_log10p")) stop("Unsupported GSEA rank metric.")
  if (metric == "signed_log10p") {
    if (!all(c("log2FoldChange", "pvalue") %in% names(df))) stop("Signed P ranking requires log2FoldChange and pvalue.")
    pv <- as.numeric(df$pvalue)
    if (any(is.finite(pv) & (pv < 0 | pv > 1))) stop("Invalid P values for GSEA ranking.")
    score <- sign(as.numeric(df$log2FoldChange)) * -log10(pmax(pv, 1e-300))
  } else {
    if (!metric %in% names(df)) stop("Selected GSEA ranking column unavailable; explicitly select another metric.")
    score <- as.numeric(df[[metric]])
  }
  ids <- trimws(as.character(df[[id_column]]))
  valid <- is.finite(score) & !is.na(ids) & nzchar(ids)
  ranks <- data.frame(gene_id = ids[valid], metric = score[valid], stringsAsFactors = FALSE)
  if (anyDuplicated(ranks$gene_id)) stop("Duplicate input gene identifiers; resolve duplicates before GSEA.")
  if (nrow(ranks) < 20) stop("GSEA requires at least 20 valid ranked genes.")
  list(ranks = ranks, audit = list(input_rows = nrow(df), valid_rows = nrow(ranks),
    excluded_invalid = sum(!valid), metric = metric, significance_filter = "none",
    p_zero_display_floor = if (metric == "signed_log10p") 1e-300 else NULL))
}

emp_gsea_path <- function(session_id, experiment, id = NULL) {
  dir <- file.path(session_path(session_id), "gsea")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  if (is.null(id)) return(file.path(dir, paste0(make.names(experiment), "_current.rds")))
  if (length(id) != 1 || !grepl("^[A-Za-z0-9_.-]+$", id)) stop("Invalid GSEA result ID.")
  file.path(dir, paste0(id, ".rds"))
}

emp_load_gsea <- function(session_id, experiment, source_job = NULL) {
  id <- NULL
  if (!is.null(source_job) && nzchar(source_job) && source_job != "current_gsea") {
    job <- .read_state(validate_job_id(source_job))
    if (is.null(job) || !identical(job$session_id, session_id)) stop("Access denied: GSEA job belongs to another session.")
    if (!file.exists(.job_result_path(source_job))) stop("GSEA task result unavailable.")
    value <- readRDS(.job_result_path(source_job)); id <- value$gsea_id
    if (is.null(id)) stop("Selected job is not a GSEA result.")
  }
  path <- emp_gsea_path(session_id, experiment, id)
  if (!file.exists(path)) stop("No GSEA result: run GSEA analysis first.")
  value <- readRDS(path)
  if (is.null(id)) value <- readRDS(emp_gsea_path(session_id, experiment, value$gsea_id))
  if (!identical(value$experiment, experiment)) stop("GSEA experiment mismatch.")
  value
}

emp_run_gsea <- function(session_id, experiment, database = "GO_BP", organism = "hsa",
                         metric = "stat", id_type = "SYMBOL", exponent = 1,
                         min_size = 15L, max_size = 500L, seed = 20261108L,
                         on_progress = NULL) {
  database <- match.arg(database, c("GO_BP", "GO_CC", "GO_MF", "KEGG"))
  id_type <- match.arg(id_type, c("SYMBOL", "ENTREZID", "ENSEMBL"))
  exponent <- as.numeric(exponent); min_size <- as.integer(min_size); max_size <- as.integer(max_size); seed <- as.integer(seed)
  if (length(exponent) != 1 || !is.finite(exponent) || exponent < 0 || exponent > 2 ||
      !is.finite(min_size) || !is.finite(max_size) || min_size < 5 || max_size < min_size || max_size > 10000 || !is.finite(seed)) stop("Invalid GSEA parameters.")
  bump <- function(p, text) if (is.function(on_progress)) on_progress(p, text)
  bump(5, "Loading full differential ranks")
  raw <- load_diff_raw(session_id, experiment)
  if (is.null(raw)) stop("Run differential analysis before GSEA; a full ranking is required.")
  id_column <- if (id_type == "SYMBOL" && "symbol" %in% names(raw$data)) "symbol" else "feature"
  prep <- emp_gsea_ranks(raw, metric, id_column)
  org <- normalize_species(organism, default = "hsa")
  pkg <- .enrich_orgdb(org)
  if (is.na(pkg) || !requireNamespace(pkg, quietly = TRUE)) stop("Required species OrgDb unavailable.")
  if (!requireNamespace("clusterProfiler", quietly = TRUE)) stop("clusterProfiler is required for GSEA.")
  target <- .enrich_keytype(org)
  db <- get(pkg, envir = asNamespace(pkg))
  bump(15, "Mapping ranked gene identifiers")
  ids <- prep$ranks$gene_id
  mapped <- if (id_type == target) data.frame(input = ids, target = ids) else {
    z <- AnnotationDbi::select(db, keys = ids, keytype = id_type, columns = target)
    data.frame(input = z[[id_type]], target = z[[target]])
  }
  mapped <- mapped[!is.na(mapped$target) & nzchar(mapped$target), , drop = FALSE]
  # Keep only unambiguous 1:1 mappings, recording exclusions instead of selecting a favorable score.
  ambiguous <- unique(mapped$input[duplicated(mapped$input) | duplicated(mapped$input, fromLast = TRUE)])
  mapped <- mapped[!mapped$input %in% ambiguous, , drop = FALSE]
  collisions <- unique(mapped$target[duplicated(mapped$target) | duplicated(mapped$target, fromLast = TRUE)])
  mapped <- mapped[!mapped$target %in% collisions, , drop = FALSE]
  scores <- prep$ranks$metric[match(mapped$input, prep$ranks$gene_id)]
  names(scores) <- as.character(mapped$target)
  scores <- scores[order(-scores, names(scores))]
  if (length(scores) < 20 || !any(scores != 0)) stop("Insufficient mapped nonzero-ranked genes for GSEA.")
  prep$audit$mapped_genes <- length(scores)
  prep$audit$excluded_mapping <- nrow(prep$ranks) - length(scores)
  prep$audit$ambiguous_mapping <- length(ambiguous)
  prep$audit$colliding_targets <- length(collisions)
  prep$audit$tied_scores <- sum(duplicated(unname(scores)))
  bump(30, "Running preranked GSEA; no DEG significance filter")
  had_seed <- exists(".Random.seed", .GlobalEnv, inherits = FALSE)
  old_seed <- if (had_seed) get(".Random.seed", .GlobalEnv) else NULL
  on.exit(if (had_seed) assign(".Random.seed", old_seed, .GlobalEnv) else if (exists(".Random.seed", .GlobalEnv)) rm(".Random.seed", envir = .GlobalEnv), add = TRUE)
  set.seed(seed)
  args <- list(geneList = scores, exponent = exponent, minGSSize = min_size, maxGSSize = max_size,
               pvalueCutoff = 1, pAdjustMethod = "BH", verbose = FALSE)
  fn <- if (database == "KEGG") clusterProfiler::gseKEGG else clusterProfiler::gseGO
  # Support both the installed multilevel interface and standard fgsea-based releases.
  if ("method" %in% names(formals(fn))) args$method <- "multilevel" else {args$by <- "fgsea"; args$seed <- TRUE}
  if (database == "KEGG") {args$organism <- org; args$keyType <- if (target == "ENTREZID") "ncbi-geneid" else "kegg"}
  else {args$ont <- sub("GO_", "", database); args$OrgDb <- db; args$keyType <- target}
  object <- do.call(fn, args)
  tab <- as.data.frame(object)
  id <- basename(tempfile(pattern = paste0("gsea_", format(Sys.time(), "%Y%m%d%H%M%S"), "_")))
  parameters <- list(database = database, organism = org, metric = metric, id_type = id_type,
    exponent = exponent, min_size = min_size, max_size = max_size, seed = seed,
    p_adjust = "BH", analysis_cutoff = 1, comparison = raw[c("method", "ref_group", "test_group", "created")],
    clusterProfiler_version = as.character(utils::packageVersion("clusterProfiler")))
  value <- list(gsea_id = id, experiment = experiment, object = object, parameters = parameters,
    input_audit = prep$audit, mapping = mapped, created = Sys.time())
  saveRDS(value, emp_gsea_path(session_id, experiment, id))
  pointer <- emp_gsea_path(session_id, experiment)
  tmp <- tempfile(tmpdir = dirname(pointer)); saveRDS(list(gsea_id = id), tmp); file.rename(tmp, pointer)
  bump(100, "GSEA complete; full result and ranked list saved")
  list(success = TRUE, gsea_id = id, database = database, organism = org,
       n_rows = nrow(tab), data = jsonlite::toJSON(tab, na = "null", auto_unbox = TRUE),
       input_audit = prep$audit, parameters = parameters)
}
