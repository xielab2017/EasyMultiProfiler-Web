# Bundled demo datasets for course / first-run onboarding (paths under webapp/)

.backend_dir <- function() {
  d <- Sys.getenv("BACKEND_DIR", unset = "")
  if (nzchar(d)) return(normalizePath(d, winslash = "/", mustWork = FALSE))
  normalizePath(file.path(getwd(), "webapp", "backend"), winslash = "/", mustWork = FALSE)
}

.webapp_root <- function() {
  normalizePath(file.path(.backend_dir(), ".."), winslash = "/", mustWork = FALSE)
}

.repo_root <- function() {
  normalizePath(file.path(.webapp_root(), ".."), winslash = "/", mustWork = FALSE)
}

.tests_dir <- function() {
  root <- .repo_root()
  td <- file.path(root, "tests")
  if (dir.exists(td)) return(td)
  file.path(.webapp_root(), "tests")
}

demo_dataset_catalog <- function() {
  root <- .webapp_root()
  tests <- .tests_dir()
  src <- file.path(root, "test_outputs", "latest", "source_files")
  m16s_latest <- file.path(root, "test_outputs", "latest", "microbiome_16s")
  tx_latest <- file.path(root, "test_outputs", "latest", "transcriptomics")

  first_existing <- function(...) {
    cands <- c(...)
    hit <- cands[file.exists(cands)]
    if (length(hit)) hit[[1]] else cands[[1]]
  }

  clinical_raw <- first_existing(
    file.path(tests, "Clinical-test.csv"),
    file.path(tests, "Clinical.csv")
  )
  clinical_meta <- first_existing(
    file.path(tests, "meta-test.csv"),
    file.path(tests, "meta.csv"),
    file.path(tests, "meta-formal.csv")
  )
  rnaseq_data <- first_existing(
    file.path(tests, "RNAseq_output.csv"),
    file.path(src, "RNAseq_output.csv"),
    file.path(tx_latest, "RNAseq_test_assay.csv")
  )
  rnaseq_meta <- first_existing(
    file.path(tests, "RNAseq_mapping.txt"),
    file.path(tests, "RNAseq_mapping.csv"),
    file.path(src, "RNAseq_mapping.txt"),
    file.path(tx_latest, "RNAseq_test_metadata.csv")
  )
  m16s_data <- first_existing(
    file.path(tests, "level-7.csv"),
    file.path(tests, "16S_level-7.csv"),
    file.path(src, "16S_level-7.csv"),
    file.path(m16s_latest, "16S_test_assay.csv")
  )
  m16s_meta <- first_existing(
    file.path(tests, "meta.csv"),
    file.path(tests, "16S_mapping.csv"),
    file.path(tests, "meta-test.csv"),
    file.path(src, "16S_mapping.txt"),
    file.path(m16s_latest, "16S_test_metadata.csv")
  )

  datasets <- list(
    list(
      id = "m16s_course",
      label = "16S Microbiome (Course Demo)",
      label_en = "16S Microbiome (Course Demo)",
      label_zh = "16S Microbiome (Course Demo)",
      omics = "microbiome_16s",
      data_type = "tax",
      experiment_name = "m16s_course",
      assay_name = "counts",
      start_level = "Species",
      tax_sep = ";",
      data_file = m16s_data,
      metadata_file = m16s_meta,
      description = "Taxonomy abundance + sample metadata (UC/IBS-style cohort)."
    ),
    list(
      id = "rnaseq_course",
      label = "RNA-seq Transcriptomics (Course Demo)",
      label_en = "RNA-seq Transcriptomics (Course Demo)",
      label_zh = "RNA-seq Transcriptomics (Course Demo)",
      omics = "transcriptomics",
      data_type = "normal",
      experiment_name = "rnaseq_course",
      assay_name = "counts",
      start_level = "Species",
      tax_sep = ";",
      data_file = rnaseq_data,
      metadata_file = rnaseq_meta,
      description = "24-sample DMSO vs treatment count matrix + group metadata."
    ),
    list(
      id = "clinical_course",
      label = "Clinical Phenotypes (Course Demo)",
      label_en = "Clinical Phenotypes (Course Demo)",
      label_zh = "Clinical Phenotypes (Course Demo)",
      omics = "clinical",
      data_type = "clinical_raw",
      experiment_name = "clinical_course",
      assay_name = "counts",
      start_level = "Species",
      tax_sep = ";",
      data_file = clinical_raw,
      metadata_file = clinical_meta,
      description = "Longitudinal UC/IBS clinical table + companion metadata."
    )
  )

  lapply(datasets, function(d) {
    d$available <- file.exists(d$data_file)
    if (!is.null(d$metadata_file) && nzchar(d$metadata_file)) {
      d$available <- isTRUE(d$available) && file.exists(d$metadata_file)
    }
    d
  })
}

resolve_demo_dataset <- function(dataset_id) {
  id <- as.character(dataset_id %||% "")
  if (!nzchar(id)) stop("dataset_id is required")
  hits <- Filter(function(d) identical(d$id, id), demo_dataset_catalog())
  if (!length(hits)) stop("Unknown demo dataset: ", id)
  d <- hits[[1]]
  if (!isTRUE(d$available)) stop("Demo dataset files missing on server: ", id)
  d
}

import_demo_dataset <- function(session_id, dataset_id,
                                experiment_name = NULL,
                                assay_name = NULL) {
  d <- resolve_demo_dataset(dataset_id)
  exp_name <- experiment_name %||% d$experiment_name
  assay <- assay_name %||% d$assay_name
  data_type <- d$data_type
  data_file <- d$data_file
  meta_file <- d$metadata_file

  if (is.null(session_id) || !nzchar(session_id)) {
    session_id <- create_session()
  } else {
    ensure_session_dir(session_id)
  }

  mae_exists <- file.exists(mae_path(session_id))

  if (data_type %in% c("clinical_meta", "clinical_raw")) {
    meta_upload <- read_metadata_table(data_file)
    paired_meta_upload <- if (identical(data_type, "clinical_raw") && !is.null(meta_file)) {
      read_metadata_table(meta_file)
    } else {
      NULL
    }
    standalone_path <- if (identical(data_type, "clinical_meta")) {
      file.path(dirname(mae_path(session_id)), "clinical_uploaded_meta.csv")
    } else {
      file.path(dirname(mae_path(session_id)), "clinical_uploaded_raw.csv")
    }
    standalone_meta_path <- file.path(dirname(mae_path(session_id)), "clinical_uploaded_meta.csv")
    write_standalone_clinical <- function(meta, path) {
      utils::write.csv(meta, path, row.names = FALSE)
    }

    if (!mae_exists) {
      meta <- meta_upload
      write_standalone_clinical(meta, standalone_path)
      if (!is.null(paired_meta_upload) && nrow(paired_meta_upload)) {
        write_standalone_clinical(paired_meta_upload, standalone_meta_path)
      }
      merged_preview <- tryCatch(.clin_merge_external_tables(meta, paired_meta_upload), error = function(e) meta)
      return(list(
        success = TRUE,
        session_id = session_id,
        import_mode = "clinical_standalone",
        demo_id = d$id,
        omics = d$omics,
        updated_experiments = 0L,
        columns = setdiff(names(merged_preview), "primary"),
        orientation = attr(meta, "orientation_note") %||% "samples in rows"
      ))
    }

    mae <- load_mae(session_id)
    write_standalone_clinical(meta_upload, standalone_path)
    if (!is.null(paired_meta_upload) && nrow(paired_meta_upload)) {
      write_standalone_clinical(paired_meta_upload, standalone_meta_path)
    }
    merged <- merge_metadata_into_mae(mae, if (!is.null(paired_meta_upload)) meta_file else data_file)
    mae <- merged$mae
    save_mae(session_id, mae)
    exp_names <- names(as.list(MultiAssayExperiment::experiments(mae)))
    for (exn in exp_names) {
      tryCatch(save_raw_empt(session_id, exn, .promote_to_empt(mae, exn)), error = function(e) NULL)
    }
    return(list(
      success = TRUE,
      session_id = session_id,
      import_mode = "clinical_merge",
      demo_id = d$id,
      omics = d$omics,
      updated_experiments = merged$touched,
      columns = merged$columns,
      orientation = attr(meta_upload, "orientation_note") %||% "samples in rows"
    ))
  }

  if (mae_exists) {
    mae <- load_mae(session_id)
    mae <- add_experiment_to_mae(mae, data_file, meta_file,
                                exp_name, data_type,
                                assay, d$start_level, d$tax_sep)
  } else {
    mae <- build_mae(data_file, meta_file,
                     exp_name, data_type,
                     assay, d$start_level, d$tax_sep)
  }

  save_mae(session_id, mae)
  tryCatch({
    save_raw_empt(session_id, exp_name, .promote_to_empt(mae, exp_name))
  }, error = function(e) NULL)
  register_experiment_meta(session_id, exp_name, data_type, d$omics)
  write_experiments_meta(session_id, mae)

  ex <- mae[[exp_name]]
  list(
    success = TRUE,
    session_id = session_id,
    import_mode = if (mae_exists) "demo_add" else "demo_new",
    demo_id = d$id,
    omics = d$omics,
    experiment_name = exp_name,
    samples = ncol(ex),
    features = nrow(ex),
    assay = assay,
    experiment_count = length(mae)
  )
}
