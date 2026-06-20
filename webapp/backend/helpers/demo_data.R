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
  clinical_raw <- file.path(tests, "Clinical-test.csv")
  clinical_meta <- file.path(tests, "meta-test.csv")
  if (!file.exists(clinical_raw)) clinical_raw <- file.path(tests, "Clinical.csv")
  if (!file.exists(clinical_meta)) clinical_meta <- file.path(tests, "meta.csv")
  rnaseq_data <- file.path(tests, "RNAseq_output.csv")
  rnaseq_meta <- file.path(tests, "RNAseq_mapping.txt")
  if (!file.exists(rnaseq_data)) rnaseq_data <- file.path(src, "RNAseq_output.csv")
  if (!file.exists(rnaseq_meta)) rnaseq_meta <- file.path(src, "RNAseq_mapping.txt")

  datasets <- list(
    list(
      id = "m16s_course",
      label = "16S 微生物组（课程示例）",
      label_en = "16S Microbiome (Course Demo)",
      omics = "microbiome_16s",
      data_type = "tax",
      experiment_name = "m16s_course",
      assay_name = "counts",
      start_level = "Species",
      tax_sep = ";",
      data_file = file.path(tests, "level-7.csv"),
      metadata_file = file.path(tests, "meta.csv"),
      description = "Taxonomy abundance + sample metadata (UC/IBS-style cohort)."
    ),
    list(
      id = "rnaseq_course",
      label = "RNA-seq 转录组（课程示例）",
      label_en = "RNA-seq Transcriptomics (Course Demo)",
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
      label = "Clinical 临床表型（课程示例）",
      label_en = "Clinical Phenotypes (Course Demo)",
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

  ex <- mae[[exp_name]]
  list(
    success = TRUE,
    session_id = session_id,
    import_mode = "demo",
    demo_id = d$id,
    omics = d$omics,
    experiment_name = exp_name,
    samples = ncol(ex),
    features = nrow(ex),
    assay = assay
  )
}
