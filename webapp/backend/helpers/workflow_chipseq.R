# ChIP-seq workflow helpers: BAM -> MACS2/3 peak calling -> annotation -> cross-omics bridge.

chip_require_string <- function(x, name) {
  if (is.null(x)) stop(sprintf("%s is required.", name))
  # Unwrap accidental length-1 JSON lists; never as.character() an environment/S4.
  while (is.list(x) && !is.object(x) && length(x) == 1L) x <- x[[1L]]
  if (is.environment(x) || isS4(x) ||
      !(is.character(x) || is.numeric(x) || is.logical(x) || is.factor(x))) {
    stop(sprintf("%s must be a string (got %s).", name, paste(class(x), collapse = ",")))
  }
  v <- trimws(as.character(x)[[1L]])
  if (length(v) < 1L || is.na(v) || !nzchar(v)) stop(sprintf("%s is required.", name))
  v
}

# Optional form/JSON scalar → single string or NULL (never coerce environments).
.chip_form_scalar <- function(x) {
  if (is.null(x)) return(NULL)
  while (is.list(x) && !is.object(x) && length(x) == 1L) x <- x[[1L]]
  if (is.environment(x) || isS4(x)) return(NULL)
  if (is.raw(x)) x <- rawToChar(x)
  if (is.factor(x)) x <- as.character(x)
  if (!is.character(x) && !is.numeric(x) && !is.logical(x)) return(NULL)
  x <- trimws(as.character(x))
  if (length(x) != 1L || is.na(x) || !nzchar(x)) return(NULL)
  x
}

# UI placeholders like "/path/to/rep2.bed" must never be treated as real peak paths.
.chip_is_placeholder_path <- function(p) {
  p <- trimws(as.character(p %||% "")[1])
  if (!nzchar(p)) return(TRUE)
  pl <- tolower(gsub("\\\\", "/", p, fixed = TRUE))
  if (startsWith(pl, "/path/to/") || startsWith(pl, "c:/path/to/")) return(TRUE)
  if (grepl("(rep2_or_markb|markc)\\.bed$", pl) && grepl("path", pl, fixed = TRUE)) {
    return(TRUE)
  }
  FALSE
}

.chip_path_scalar <- function(x) {
  p <- .chip_form_scalar(x)
  if (is.null(p) || .chip_is_placeholder_path(p)) return(NULL)
  p
}

.chip_missing_peaks_error <- function() {
  paste0(
    "未找到可用峰文件（manifest 无 last_peaks）。",
    "请在 ChIPseq 页上传 BED/narrowPeak，或先运行 MACS；",
    "亦可在「当前峰文件」下拉中选择已有条目。"
  )
}

.chip_empty_peaks_error <- function(path = "", n = 0L) {
  paste0(
    "当前峰文件峰数为 0（真正空文件）: ",
    basename(as.character(path %||% "")[1]),
    "。请在「当前峰文件」下拉中切换到其他上传/MACS 结果，或重新 callpeak。"
  )
}

.chip_unreadable_peaks_error <- function(path = "", detail = "") {
  paste0(
    "峰文件无法读取: ",
    basename(as.character(path %||% "")[1]),
    if (nzchar(as.character(detail %||% "")[1])) paste0(" — ", detail) else "",
    "。请确认路径存在且为 BED/narrowPeak，或改选其他峰文件。"
  )
}

.chip_count_peak_lines <- function(path) {
  path <- as.character(path %||% "")[1]
  if (!nzchar(path) || !file.exists(path)) return(0L)
  lines <- tryCatch(readLines(path, warn = FALSE, encoding = "UTF-8"), error = function(e) character())
  if (!length(lines)) return(0L)
  keep <- !grepl("^\\s*(#|$|track\\s|browser\\s)", lines, ignore.case = TRUE)
  as.integer(sum(keep))
}

.chip_new_peak_id <- function() {
  paste0(
    "pk_",
    format(Sys.time(), "%Y%m%d%H%M%S"),
    "_",
    paste(sample(c(letters, 0:9), 6L, replace = TRUE), collapse = "")
  )
}

.chip_normalize_peak_source <- function(source) {
  s <- tolower(trimws(as.character(source %||% "")[1]))
  if (!nzchar(s)) return("upload")
  if (s %in% c("preimported", "upload", "uploaded", "user")) return("upload")
  if (s %in% c("macs", "macs2", "macs3", "callpeak")) return("macs")
  if (startsWith(s, "ops_") || s %in% c(
    "blacklist", "merge", "summit", "idr_approx", "promoter",
    "enhancer", "super_enhancer", "broad_domains", "overlap"
  )) {
    return(paste0("ops_", sub("^ops_", "", s)))
  }
  s
}

.chip_peak_display_name <- function(entry) {
  nm <- as.character(entry$name %||% entry$display_name %||% "")[1]
  if (nzchar(nm)) return(nm)
  basename(as.character(entry$peak_file %||% entry$path %||% "")[1])
}

.chip_peak_label <- function(entry) {
  src <- .chip_normalize_peak_source(entry$source %||% "upload")
  src_zh <- switch(
    src,
    upload = "上传",
    macs = "MACS",
    paste0("衍生/", sub("^ops_", "", src))
  )
  name <- .chip_peak_display_name(entry)
  n <- suppressWarnings(as.integer(entry$n_peaks %||% NA_integer_)[1])
  n_txt <- if (is.finite(n)) {
    if (n == 1L) "1 peak" else paste0(n, " peaks")
  } else {
    "?"
  }
  paste0(src_zh, ": ", name, " (", n_txt, ")")
}

.chip_infer_peak_source <- function(path, source = NULL) {
  raw <- trimws(as.character(source %||% "")[1])
  if (nzchar(raw)) return(.chip_normalize_peak_source(raw))
  p <- as.character(path %||% "")[1]
  if (grepl("/preimported_", p, fixed = TRUE)) return("upload")
  if (grepl("_peaks\\.(narrowPeak|broadPeak)$", p, ignore.case = TRUE)) return("macs")
  if (grepl("/peaks_ops_", p) || grepl("/(blacklist|merge|summit|promoter|enhancer)", p)) {
    return("ops_derived")
  }
  "upload"
}

.chip_peak_entry_from_last <- function(lp) {
  if (is.null(lp) || !is.list(lp)) return(NULL)
  path <- .chip_path_scalar(lp$peak_file %||% "")
  if (is.null(path) || !nzchar(path)) return(NULL)
  n <- suppressWarnings(as.integer(lp$n_peaks %||% NA_integer_)[1])
  if (!is.finite(n) && file.exists(path)) n <- .chip_count_peak_lines(path)
  list(
    id = as.character(lp$id %||% .chip_new_peak_id())[1],
    path = path,
    peak_file = path,
    name = as.character(lp$display_name %||% lp$name %||% basename(path))[1],
    source = .chip_infer_peak_source(path, lp$source),
    genome = as.character(lp$genome %||% "hs")[1],
    assembly = as.character(lp$assembly %||% .chip_assembly_from_genome(lp$genome %||% "hs"))[1],
    n_peaks = if (is.finite(n)) as.integer(n) else NULL,
    created_at = as.character(lp$created_at %||% lp$updated_at %||% Sys.time())[1],
    run_dir = as.character(lp$run_dir %||% "")[1],
    summit_file = as.character(lp$summit_file %||% "")[1],
    format_hint = as.character(lp$format_hint %||% "")[1],
    preset = as.character(lp$preset %||% "")[1]
  )
}

.chip_discover_peak_files_on_disk <- function(session_id) {
  root <- chip_session_dir(session_id)
  if (!dir.exists(root)) return(list())
  macs_hits <- list.files(
    root,
    pattern = "(_peaks\\.narrowPeak|_peaks\\.broadPeak)$",
    recursive = TRUE,
    full.names = TRUE
  )
  bed_hits <- list.files(
    root,
    pattern = "\\.(bed|BED)$",
    recursive = TRUE,
    full.names = TRUE
  )
  # Prefer real peak products; skip HOMER/deeptools staging beds.
  bed_hits <- bed_hits[!grepl(
    "/(homer_|deeptools_|peaks_ops_|annotation)/|peaks_for_|_summits\\.bed$",
    bed_hits,
    ignore.case = TRUE
  )]
  # Keep preimported beds + MACS outputs.
  bed_hits <- bed_hits[grepl("/preimported_|/peaks_ops_", bed_hits) | grepl("_peaks\\.bed$", bed_hits)]
  paths <- unique(c(macs_hits, bed_hits))
  paths <- paths[file.exists(paths)]
  if (!length(paths)) return(list())
  # Newest first by mtime.
  info <- file.info(paths)
  paths <- paths[order(info$mtime, decreasing = TRUE, na.last = TRUE)]
  lapply(paths, function(p) {
    src <- if (grepl("_peaks\\.(narrowPeak|broadPeak)$", p, ignore.case = TRUE)) "macs" else "upload"
    list(
      id = .chip_new_peak_id(),
      path = p,
      peak_file = p,
      name = basename(p),
      source = src,
      genome = "mm",
      assembly = .chip_assembly_from_genome("mm"),
      n_peaks = .chip_count_peak_lines(p),
      created_at = as.character(info[p, "mtime"]),
      run_dir = dirname(p),
      summit_file = "",
      format_hint = if (grepl("narrowPeak$", p, ignore.case = TRUE)) "narrowPeak" else "BED",
      preset = ""
    )
  })
}

.chip_ensure_peak_files_registry <- function(session_id, manifest = NULL, persist = TRUE) {
  session_id <- chip_require_session(session_id)
  if (is.null(manifest)) manifest <- chip_load_manifest(session_id)
  entries <- manifest$peak_files
  if (is.null(entries) || !is.list(entries)) entries <- list()
  # jsonlite may return named list of scalars; normalize to list-of-lists.
  if (length(entries) && !is.null(names(entries)) &&
      !is.list(entries[[1]]) && !"peak_file" %in% names(entries) && !"path" %in% names(entries)) {
    entries <- list()
  }
  if (length(entries) && !is.null(names(entries)) &&
      (is.null(entries[[1]]) || !is.list(entries[[1]]))) {
    # Single object encoded as named list
    if (!is.null(entries$peak_file) || !is.null(entries$path)) entries <- list(entries)
  }

  by_path <- list()
  for (e in entries) {
    if (!is.list(e)) next
    path <- .chip_path_scalar(e$peak_file %||% e$path %||% "")
    if (is.null(path) || !nzchar(path)) next
    e$path <- path
    e$peak_file <- path
    if (is.null(e$id) || !nzchar(as.character(e$id)[1])) e$id <- .chip_new_peak_id()
    e$source <- .chip_infer_peak_source(path, e$source)
    if (is.null(e$name) || !nzchar(as.character(e$name)[1])) e$name <- basename(path)
    if (is.null(e$n_peaks) || !is.finite(suppressWarnings(as.numeric(e$n_peaks)[1]))) {
      if (file.exists(path)) e$n_peaks <- .chip_count_peak_lines(path)
    }
    by_path[[normalizePath(path, winslash = "/", mustWork = FALSE)]] <- e
  }

  # Seed from last_peaks (backward compatible).
  lp_entry <- .chip_peak_entry_from_last(manifest$last_peaks)
  if (!is.null(lp_entry)) {
    key <- normalizePath(lp_entry$path, winslash = "/", mustWork = FALSE)
    if (is.null(by_path[[key]])) by_path[[key]] <- lp_entry
  }

  # Auto-discover on-disk peaks not yet registered (upload + MACS).
  for (d in .chip_discover_peak_files_on_disk(session_id)) {
    key <- normalizePath(d$path, winslash = "/", mustWork = FALSE)
    if (is.null(by_path[[key]])) {
      # Prefer genome from last_peaks when discovering.
      if (!is.null(manifest$last_peaks$genome)) {
        d$genome <- as.character(manifest$last_peaks$genome)[1]
        d$assembly <- as.character(
          manifest$last_peaks$assembly %||% .chip_assembly_from_genome(d$genome)
        )[1]
      }
      by_path[[key]] <- d
    }
  }

  out <- unname(by_path)
  # Stable order: newest created_at first.
  if (length(out)) {
    ts <- vapply(out, function(e) as.character(e$created_at %||% "")[1], character(1))
    out <- out[order(ts, decreasing = TRUE, na.last = TRUE)]
  }
  manifest$peak_files <- out

  # Ensure last_peaks points at an entry; prefer existing last_peaks path if still listed.
  active_path <- .chip_path_scalar(manifest$last_peaks$peak_file %||% "")
  active <- NULL
  if (!is.null(active_path) && nzchar(active_path)) {
    for (e in out) {
      if (identical(
        normalizePath(e$peak_file, winslash = "/", mustWork = FALSE),
        normalizePath(active_path, winslash = "/", mustWork = FALSE)
      )) {
        active <- e
        break
      }
    }
  }
  # If last_peaks missing/stale, pick newest non-empty; else newest.
  if (is.null(active) && length(out)) {
    nonempty <- Filter(function(e) {
      n <- suppressWarnings(as.integer(e$n_peaks %||% 0L)[1])
      is.finite(n) && n > 0L && file.exists(e$peak_file)
    }, out)
    active <- if (length(nonempty)) nonempty[[1]] else out[[1]]
  }
  if (!is.null(active)) {
    manifest$last_peaks <- modifyList(
      as.list(manifest$last_peaks %||% list()),
      list(
        id = active$id,
        peak_file = active$peak_file,
        path = active$peak_file,
        name = active$name,
        display_name = active$name,
        source = active$source,
        genome = active$genome,
        assembly = active$assembly %||% .chip_assembly_from_genome(active$genome),
        n_peaks = active$n_peaks,
        run_dir = active$run_dir %||% dirname(active$peak_file),
        summit_file = active$summit_file %||% "",
        created_at = active$created_at,
        updated_at = as.character(Sys.time())
      )
    )
  }
  if (isTRUE(persist)) chip_save_manifest(session_id, manifest)
  manifest
}

.chip_register_peak_file <- function(session_id,
                                     peak_file,
                                     name = NULL,
                                     source = "upload",
                                     genome = "mm",
                                     assembly = NULL,
                                     n_peaks = NULL,
                                     run_dir = NULL,
                                     summit_file = "",
                                     format_hint = "",
                                     preset = "",
                                     extra = NULL,
                                     set_active = TRUE) {
  session_id <- chip_require_session(session_id)
  peak_file <- chip_require_string(peak_file, "peak_file")
  if (.chip_is_placeholder_path(peak_file)) {
    stop("占位路径无效（/path/to/...），请选择真实峰文件。")
  }
  if (!file.exists(peak_file)) stop(.chip_unreadable_peaks_error(peak_file, "文件不存在"))

  manifest <- .chip_ensure_peak_files_registry(session_id, persist = FALSE)
  src <- .chip_normalize_peak_source(source)
  gcfg <- chip_genome_config(genome)
  asm <- as.character(assembly %||% .chip_assembly_from_genome(genome))[1]
  nm <- as.character(name %||% basename(peak_file))[1]
  n <- suppressWarnings(as.integer(n_peaks %||% NA_integer_)[1])
  if (!is.finite(n)) n <- .chip_count_peak_lines(peak_file)
  key <- normalizePath(peak_file, winslash = "/", mustWork = FALSE)
  existing_id <- NULL
  for (e in manifest$peak_files %||% list()) {
    if (identical(normalizePath(e$peak_file, winslash = "/", mustWork = FALSE), key)) {
      existing_id <- e$id
      break
    }
  }
  entry <- list(
    id = existing_id %||% .chip_new_peak_id(),
    path = peak_file,
    peak_file = peak_file,
    name = nm,
    source = src,
    genome = gcfg$macs,
    assembly = asm,
    n_peaks = as.integer(n),
    created_at = as.character(Sys.time()),
    run_dir = as.character(run_dir %||% dirname(peak_file))[1],
    summit_file = as.character(summit_file %||% "")[1],
    format_hint = as.character(format_hint %||% "")[1],
    preset = as.character(preset %||% "")[1]
  )
  if (is.list(extra) && length(extra)) {
    for (nm2 in names(extra)) entry[[nm2]] <- extra[[nm2]]
  }

  kept <- list()
  for (e in manifest$peak_files %||% list()) {
    if (!identical(normalizePath(e$peak_file, winslash = "/", mustWork = FALSE), key)) {
      kept[[length(kept) + 1L]] <- e
    }
  }
  # Newest first.
  manifest$peak_files <- c(list(entry), kept)

  if (isTRUE(set_active)) {
    lp <- list(
      id = entry$id,
      peak_file = entry$peak_file,
      path = entry$peak_file,
      name = entry$name,
      display_name = entry$name,
      source = entry$source,
      genome = entry$genome,
      assembly = entry$assembly,
      n_peaks = entry$n_peaks,
      run_dir = entry$run_dir,
      summit_file = entry$summit_file,
      format_hint = entry$format_hint,
      preset = entry$preset,
      created_at = entry$created_at,
      updated_at = as.character(Sys.time())
    )
    if (is.list(extra) && length(extra)) {
      for (nm2 in names(extra)) lp[[nm2]] <- extra[[nm2]]
    }
    manifest$last_peaks <- lp
  }
  chip_save_manifest(session_id, manifest)
  list(entry = entry, last_peaks = manifest$last_peaks, peak_files = manifest$peak_files)
}

chip_list_peaks <- function(session_id) {
  session_id <- chip_require_session(session_id)
  manifest <- .chip_ensure_peak_files_registry(session_id, persist = TRUE)
  entries <- lapply(manifest$peak_files %||% list(), function(e) {
    e$label <- .chip_peak_label(e)
    e$exists <- file.exists(as.character(e$peak_file %||% "")[1])
    e
  })
  active_id <- as.character(manifest$last_peaks$id %||% "")[1]
  if (!nzchar(active_id) && length(entries)) {
    ap <- .chip_path_scalar(manifest$last_peaks$peak_file %||% "")
    if (!is.null(ap)) {
      for (e in entries) {
        if (identical(
          normalizePath(e$peak_file, winslash = "/", mustWork = FALSE),
          normalizePath(ap, winslash = "/", mustWork = FALSE)
        )) {
          active_id <- e$id
          break
        }
      }
    }
  }
  list(
    success = TRUE,
    peak_files = entries,
    active_peak_id = active_id,
    last_peaks = manifest$last_peaks %||% NULL
  )
}

chip_select_peak <- function(session_id, peak_id = NULL, peak_file = NULL) {
  session_id <- chip_require_session(session_id)
  manifest <- .chip_ensure_peak_files_registry(session_id, persist = TRUE)
  pid <- .chip_form_scalar(peak_id)
  pfile <- .chip_path_scalar(peak_file)
  hit <- NULL
  for (e in manifest$peak_files %||% list()) {
    if (!is.null(pid) && identical(as.character(e$id)[1], pid)) {
      hit <- e
      break
    }
    if (!is.null(pfile) && identical(
      normalizePath(e$peak_file, winslash = "/", mustWork = FALSE),
      normalizePath(pfile, winslash = "/", mustWork = FALSE)
    )) {
      hit <- e
      break
    }
  }
  if (is.null(hit)) {
    stop("未找到指定峰文件。请刷新「当前峰文件」列表后重选。")
  }
  if (!file.exists(hit$peak_file)) {
    stop(.chip_unreadable_peaks_error(hit$peak_file, "文件不存在"))
  }
  n <- suppressWarnings(as.integer(hit$n_peaks %||% NA_integer_)[1])
  if (!is.finite(n)) {
    n <- .chip_count_peak_lines(hit$peak_file)
    hit$n_peaks <- n
  }
  # Refresh entry in registry
  for (i in seq_along(manifest$peak_files)) {
    if (identical(manifest$peak_files[[i]]$id, hit$id)) {
      manifest$peak_files[[i]]$n_peaks <- as.integer(n)
      break
    }
  }
  manifest$last_peaks <- list(
    id = hit$id,
    peak_file = hit$peak_file,
    path = hit$peak_file,
    name = hit$name,
    display_name = hit$name,
    source = hit$source,
    genome = hit$genome,
    assembly = hit$assembly %||% .chip_assembly_from_genome(hit$genome),
    n_peaks = as.integer(n),
    run_dir = hit$run_dir %||% dirname(hit$peak_file),
    summit_file = hit$summit_file %||% "",
    format_hint = hit$format_hint %||% "",
    preset = hit$preset %||% "",
    created_at = hit$created_at,
    updated_at = as.character(Sys.time())
  )
  chip_save_manifest(session_id, manifest)
  list(
    success = TRUE,
    last_peaks = manifest$last_peaks,
    peak_files = lapply(manifest$peak_files, function(e) {
      e$label <- .chip_peak_label(e)
      e
    }),
    active_peak_id = hit$id,
    warning = if (is.finite(n) && n < 1L) .chip_empty_peaks_error(hit$peak_file, n) else NULL
  )
}

# Update genome/assembly on active (or specified) peak without re-upload.
# Authoritative when UI Genome mapping changes after BED is already uploaded.
chip_update_peak_genome <- function(session_id, genome = "mm", peak_id = NULL) {
  session_id <- chip_require_session(session_id)
  g_in <- .chip_form_scalar(genome) %||% "mm"
  gcfg <- chip_genome_config(g_in)
  asm <- .chip_assembly_from_genome(g_in)
  manifest <- .chip_ensure_peak_files_registry(session_id, persist = FALSE)
  pid <- .chip_form_scalar(peak_id) %||% as.character(manifest$last_peaks$id %||% "")[1]
  active_path <- .chip_path_scalar(manifest$last_peaks$peak_file %||% "")
  updated <- FALSE
  for (i in seq_along(manifest$peak_files %||% list())) {
    e <- manifest$peak_files[[i]]
    eid <- as.character(e$id %||% "")[1]
    epath <- .chip_path_scalar(e$peak_file %||% e$path %||% "")
    match_id <- nzchar(pid) && identical(eid, pid)
    match_path <- !is.null(active_path) && !is.null(epath) && identical(
      normalizePath(epath, winslash = "/", mustWork = FALSE),
      normalizePath(active_path, winslash = "/", mustWork = FALSE)
    )
    if (match_id || (!nzchar(pid) && match_path)) {
      manifest$peak_files[[i]]$genome <- gcfg$macs
      manifest$peak_files[[i]]$assembly <- asm
      updated <- TRUE
      if (!nzchar(pid)) pid <- eid
    }
  }
  if (!is.null(manifest$last_peaks) && is.list(manifest$last_peaks)) {
    lp_id <- as.character(manifest$last_peaks$id %||% "")[1]
    if (!nzchar(as.character(pid %||% "")[1]) || identical(lp_id, pid) || !nzchar(lp_id)) {
      manifest$last_peaks$genome <- gcfg$macs
      manifest$last_peaks$assembly <- asm
      manifest$last_peaks$updated_at <- as.character(Sys.time())
      updated <- TRUE
    }
  }
  if (!isTRUE(updated)) {
    stop("未找到可更新基因组的峰文件。请先上传峰文件，再选择物种。")
  }
  chip_save_manifest(session_id, manifest)
  list(
    success = TRUE,
    genome = gcfg$macs,
    assembly = asm,
    last_peaks = manifest$last_peaks,
    peak_files = lapply(manifest$peak_files %||% list(), function(e) {
      e$label <- .chip_peak_label(e)
      e
    }),
    active_peak_id = as.character(manifest$last_peaks$id %||% pid %||% "")[1]
  )
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
  rid <- .chip_form_scalar(run_id)
  if (is.null(rid)) {
    rid <- format(Sys.time(), "%Y%m%d_%H%M%S")
  }
  out <- file.path(root, make.names(rid))
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
  dir.create(dirname(mp), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(manifest, mp, auto_unbox = TRUE, pretty = TRUE)
  invisible(manifest)
}

.chip_first_installed_pkg <- function(candidates, fallback) {
  for (p in candidates) {
    if (suppressWarnings(requireNamespace(p, quietly = TRUE))) return(p)
  }
  fallback
}

chip_genome_config <- function(genome = "hs") {
  g <- tolower(trimws(as.character(genome %||% "hs")[1]))
  # Accept short codes (hs/mm) or UCSC-style aliases (hg38/hg19/mm10).
  if (g %in% c("mm", "mu", "m", "mm10", "mm39", "mouse")) {
    tx_prefer <- if (identical(g, "mm39")) {
      c("TxDb.Mmusculus.UCSC.mm39.refGene", "TxDb.Mmusculus.UCSC.mm10.knownGene")
    } else {
      c("TxDb.Mmusculus.UCSC.mm10.knownGene", "TxDb.Mmusculus.UCSC.mm39.refGene")
    }
    list(
      macs = "mm",
      txdb = .chip_first_installed_pkg(tx_prefer, "TxDb.Mmusculus.UCSC.mm10.knownGene"),
      anno_db = "org.Mm.eg.db",
      kegg = "mmu"
    )
  } else if (g %in% c("hg19", "grch37")) {
    list(
      macs = "hs",
      txdb = .chip_first_installed_pkg(
        c("TxDb.Hsapiens.UCSC.hg19.knownGene", "TxDb.Hsapiens.UCSC.hg38.knownGene"),
        "TxDb.Hsapiens.UCSC.hg19.knownGene"
      ),
      anno_db = "org.Hs.eg.db",
      kegg = "hsa"
    )
  } else {
    # Prefer hg38 when installed; fall back to hg19 (common lab install).
    list(
      macs = "hs",
      txdb = .chip_first_installed_pkg(
        c("TxDb.Hsapiens.UCSC.hg38.knownGene", "TxDb.Hsapiens.UCSC.hg19.knownGene"),
        "TxDb.Hsapiens.UCSC.hg38.knownGene"
      ),
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
    samtools <- .chip_tool_on_path(c("samtools"))
    if (!nzchar(samtools)) samtools <- Sys.which("samtools")
    if (!nzchar(samtools)) stop("samtools is required to convert SAM to BAM.")
    dest_dir <- dest_dir %||% dirname(path)
    dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
    out <- file.path(dest_dir, paste0(tools::file_path_sans_ext(basename(path)), ".bam"))
    if (!file.exists(out)) {
      status <- .chip_system2(samtools, c("view", "-bS", path, "-o", out), stdout = FALSE, stderr = FALSE)
      if (!identical(status, 0L)) stop("samtools view failed for ", basename(path))
    }
    return(out)
  }
  stop("Unsupported alignment format (use .bam or .sam): ", basename(path))
}

#' Candidate BAM index paths (.bai / .csi; bam.bai and stem.bai layouts).
.chip_bam_index_candidates <- function(bam_path) {
  bam_path <- as.character(bam_path)[1]
  stem <- sub("\\.bam$", "", bam_path, ignore.case = TRUE)
  unique(c(
    paste0(bam_path, ".bai"),
    paste0(stem, ".bai"),
    paste0(bam_path, ".csi"),
    paste0(stem, ".csi")
  ))
}

.chip_bam_has_index <- function(bam_path) {
  any(file.exists(.chip_bam_index_candidates(bam_path)))
}

#' Ensure a BAM has a .bai/.csi index (samtools index, else Rsamtools::indexBam).
#' Returns list(success=, path=, index=, created=, method=, error=).
.chip_ensure_bam_index <- function(bam_path) {
  bam_path <- as.character(bam_path)[1]
  if (!nzchar(bam_path) || !file.exists(bam_path)) {
    return(list(success = FALSE, path = bam_path, error = paste0("BAM not found: ", bam_path)))
  }
  existing <- .chip_bam_index_candidates(bam_path)
  hit <- existing[file.exists(existing)]
  if (length(hit)) {
    return(list(
      success = TRUE,
      path = bam_path,
      index = hit[[1]],
      created = FALSE,
      method = "existing"
    ))
  }

  # Prefer CLI samtools (htslib) when available under PATH / .local_run/bin.
  samtools <- .chip_tool_on_path(c("samtools"))
  if (!nzchar(samtools)) samtools <- unname(Sys.which("samtools"))
  if (nzchar(samtools)) {
    # .chip_system2 quotes args — required for Application Support / Liwei Xie paths.
    st <- .chip_system2(samtools, c("index", "-b", bam_path), stdout = TRUE, stderr = TRUE)
    if (!inherits(st, "error")) {
      status <- attr(st, "status")
      if (is.null(status) || identical(as.integer(status), 0L)) {
        hit <- existing[file.exists(existing)]
        if (length(hit)) {
          return(list(
            success = TRUE,
            path = bam_path,
            index = hit[[1]],
            created = TRUE,
            method = "samtools"
          ))
        }
      }
      # Fall through to Rsamtools with samtools stderr attached.
      sam_err <- paste(st, collapse = "\n")
    } else {
      sam_err <- conditionMessage(st)
    }
  } else {
    sam_err <- "samtools not on PATH / .local_run/bin"
  }

  if (requireNamespace("Rsamtools", quietly = TRUE)) {
    idx <- tryCatch(Rsamtools::indexBam(bam_path), error = function(e) e)
    if (!inherits(idx, "error")) {
      idx_path <- as.character(idx)[1]
      if (!nzchar(idx_path) || !file.exists(idx_path)) {
        hit <- existing[file.exists(existing)]
        idx_path <- if (length(hit)) hit[[1]] else paste0(bam_path, ".bai")
      }
      if (file.exists(idx_path)) {
        return(list(
          success = TRUE,
          path = bam_path,
          index = idx_path,
          created = TRUE,
          method = "Rsamtools"
        ))
      }
    }
    rs_err <- if (inherits(idx, "error")) conditionMessage(idx) else "Rsamtools::indexBam produced no .bai"
  } else {
    rs_err <- "Rsamtools package not installed"
  }

  list(
    success = FALSE,
    path = bam_path,
    error = paste0(
      "无法为 BAM 建立索引 / Failed to index BAM (", basename(bam_path), "). ",
      "samtools: ", sam_err, " | Rsamtools: ", rs_err,
      "。请确认 BAM 完整（BGZF）后重新上传，或手动运行: samtools index \"", bam_path, "\""
    )
  )
}

#' Run bamCoverage into session run dir; capture stderr; bedGraph→bigWig fallback.
.chip_bamcoverage_to_bw <- function(bam_path, out_bw, bam_coverage_bin,
                                    bin_size = 50L, normalize_using = "RPKM") {
  bam_path <- as.character(bam_path)[1]
  out_bw <- as.character(out_bw)[1]
  dir.create(dirname(out_bw), recursive = TRUE, showWarnings = FALSE)

  idx <- .chip_ensure_bam_index(bam_path)
  if (!isTRUE(idx$success)) {
    return(list(success = FALSE, path = out_bw, error = idx$error %||% "BAM index missing", log = idx$error))
  }

  # .chip_system2 quotes each arg — required for Application Support paths.
  # -p 1: bamCoverage defaults to all cores and can OOM plumber after HOMER/DiffBind.
  args <- c(
    "-b", bam_path,
    "-o", out_bw,
    "--binSize", as.character(bin_size),
    "--normalizeUsing", as.character(normalize_using),
    "-p", "1"
  )
  st <- .chip_system2(bam_coverage_bin, args = args, stdout = TRUE, stderr = TRUE)
  log1 <- if (inherits(st, "error")) conditionMessage(st) else paste(st, collapse = "\n")
  status1 <- if (inherits(st, "error")) 1L else {
    s <- attr(st, "status"); if (is.null(s)) 0L else as.integer(s)
  }
  if (file.exists(out_bw) && file.info(out_bw)$size > 0) {
    return(list(success = TRUE, path = out_bw, format = "bigwig", log = log1, indexed = idx))
  }

  # Fallback: bedGraph then convert with pyBigWig (deepTools venv) when bigWig write fails.
  stem <- tools::file_path_sans_ext(out_bw)
  bg <- paste0(stem, ".bedgraph")
  args2 <- c(
    "-b", bam_path,
    "-o", bg,
    "--outFileFormat", "bedgraph",
    "--binSize", as.character(bin_size),
    "--normalizeUsing", as.character(normalize_using),
    "-p", "1"
  )
  st2 <- .chip_system2(bam_coverage_bin, args = args2, stdout = TRUE, stderr = TRUE)
  log2 <- if (inherits(st2, "error")) conditionMessage(st2) else paste(st2, collapse = "\n")
  if (!file.exists(bg) || !isTRUE(file.info(bg)$size > 0)) {
    # Second known fallback: drop normalization (BPM/RPKM can fail on odd BAMs).
    args3 <- c(
      "-b", bam_path, "-o", out_bw, "--binSize", as.character(bin_size),
      "--normalizeUsing", "None", "-p", "1"
    )
    st3 <- .chip_system2(bam_coverage_bin, args = args3, stdout = TRUE, stderr = TRUE)
    log3 <- if (inherits(st3, "error")) conditionMessage(st3) else paste(st3, collapse = "\n")
    if (file.exists(out_bw) && file.info(out_bw)$size > 0) {
      return(list(success = TRUE, path = out_bw, format = "bigwig", log = log3, indexed = idx, fallback = "normalizeNone"))
    }
    err <- paste0(
      "bamCoverage 未能生成 bigWig / failed to create bigWig for ", basename(bam_path), ". ",
      "stderr: ", paste(utils::head(strsplit(log1, "\n")[[1]], 8), collapse = " | "),
      if (nzchar(log2)) paste0(" | bedgraph: ", paste(utils::head(strsplit(log2, "\n")[[1]], 4), collapse = " | ")) else "",
      if (nzchar(log3)) paste0(" | None: ", paste(utils::head(strsplit(log3, "\n")[[1]], 4), collapse = " | ")) else ""
    )
    return(list(success = FALSE, path = out_bw, error = err, log = log1, status = status1))
  }

  conv <- .chip_bedgraph_to_bigwig(bg, out_bw, bam_path)
  if (isTRUE(conv$success) && file.exists(out_bw)) {
    return(list(
      success = TRUE, path = out_bw, format = "bigwig",
      log = paste(log2, conv$log %||% "", sep = "\n"),
      indexed = idx, fallback = "bedgraph"
    ))
  }
  # If conversion failed, still return bedgraph path for coverage mode callers.
  list(
    success = TRUE,
    path = bg,
    format = "bedgraph",
    log = paste(log2, conv$error %||% "", sep = "\n"),
    indexed = idx,
    fallback = "bedgraph_only",
    warning = conv$error %||% "bedGraph→bigWig conversion failed; using bedGraph"
  )
}

#' Convert bedGraph to bigWig via pyBigWig (uses BAM header chrom sizes).
.chip_bedgraph_to_bigwig <- function(bedgraph, out_bw, bam_path = NULL) {
  root <- .chip_repo_root()
  py <- ""
  if (nzchar(root)) {
    vpy <- file.path(root, ".local_run", "deeptools_venv", "bin", "python")
    if (file.exists(vpy)) py <- vpy
  }
  if (!nzchar(py)) py <- .chip_tool_on_path(c("python3", "python"))
  if (!nzchar(py) || !file.exists(py)) {
    return(list(success = FALSE, error = "python/pyBigWig unavailable for bedGraph→bigWig"))
  }
  script_file <- tempfile(fileext = ".py")
  writeLines(c(
    "import sys",
    "bg, out = sys.argv[1], sys.argv[2]",
    "bam = sys.argv[3] if len(sys.argv) > 3 else ''",
    "import pyBigWig",
    "chroms = {}",
    "if bam:",
    "    try:",
    "        import pysam",
    "        bf = pysam.AlignmentFile(bam, 'rb')",
    "        chroms = {r: bf.get_reference_length(r) for r in bf.references}",
    "        bf.close()",
    "    except Exception:",
    "        chroms = {}",
    "if not chroms:",
    "    with open(bg) as fh:",
    "        for line in fh:",
    "            if not line.strip() or line.startswith('#') or line.startswith('track'):",
    "                continue",
    "            p = line.split()",
    "            if len(p) < 4:",
    "                continue",
    "            chroms[p[0]] = max(chroms.get(p[0], 0), int(p[2]))",
    "header = list(chroms.items())",
    "if not header:",
    "    raise SystemExit('no chrom sizes')",
    "bw = pyBigWig.open(out, 'w')",
    "bw.addHeader(header)",
    "cur = None",
    "starts, ends, vals = [], [], []",
    "def flush():",
    "    nonlocal cur, starts, ends, vals",
    "    if cur and starts:",
    "        bw.addEntries([cur] * len(starts), starts, ends=ends, values=vals)",
    "    starts, ends, vals = [], [], []",
    "with open(bg) as fh:",
    "    for line in fh:",
    "        if not line.strip() or line.startswith('#') or line.startswith('track'):",
    "            continue",
    "        p = line.split()",
    "        if len(p) < 4:",
    "            continue",
    "        c, s, e, v = p[0], int(p[1]), int(p[2]), float(p[3])",
    "        if cur is None:",
    "            cur = c",
    "        if c != cur:",
    "            flush()",
    "            cur = c",
    "        starts.append(s); ends.append(e); vals.append(v)",
    "flush()",
    "bw.close()",
    "print('ok')"
  ), script_file)
  on.exit(unlink(script_file), add = TRUE)
  args <- c(script_file, bedgraph, out_bw)
  if (!is.null(bam_path) && nzchar(as.character(bam_path)[1])) {
    args <- c(args, as.character(bam_path)[1])
  }
  st <- .chip_system2(py, args = args, stdout = TRUE, stderr = TRUE)
  log <- if (inherits(st, "error")) conditionMessage(st) else paste(st, collapse = "\n")
  if (file.exists(out_bw) && isTRUE(file.info(out_bw)$size > 0)) {
    return(list(success = TRUE, path = out_bw, log = log))
  }
  list(success = FALSE, error = paste0("bedGraph→bigWig failed: ", log), log = log)
}

.chip_bam_is_paired <- function(path, n_sample = 2000L) {
  path <- as.character(path %||% "")[1]
  if (!nzchar(path) || !file.exists(path)) return(FALSE)
  samtools <- .chip_tool_on_path(c("samtools"))
  if (!nzchar(samtools)) samtools <- as.character(Sys.which("samtools"))[1]
  if (!nzchar(samtools)) return(FALSE)
  # Sample first N alignments — full `view -c -f 1` on multi-GB BAMs is too slow for UI.
  n_sample <- max(100L, as.integer(n_sample)[1])
  cmd <- sprintf(
    "%s view %s 2>/dev/null | head -n %d | cut -f2",
    shQuote(samtools), shQuote(path), n_sample
  )
  flags <- tryCatch({
    suppressWarnings(as.integer(system(cmd, intern = TRUE)))
  }, error = function(e) integer(0))
  flags <- flags[is.finite(flags)]
  if (!length(flags)) return(FALSE)
  frac <- mean(bitwAnd(flags, 1L) == 1L, na.rm = TRUE)
  isTRUE(is.finite(frac)) && isTRUE(frac >= 0.5)
}

chip_bam_format_flag <- function(path, prefer_pe = TRUE) {
  path <- as.character(path %||% "")[1]
  ext <- tolower(tools::file_ext(path))
  if (identical(ext, "sam")) return("SAM")
  if (isTRUE(prefer_pe) && isTRUE(.chip_bam_is_paired(path))) return("BAMPE")
  "BAM"
}

.chip_as_char_vec <- function(x) {
  if (is.null(x)) return(character(0))
  if (is.environment(x) || isS4(x)) return(character(0))
  if (is.list(x)) {
    x <- unlist(lapply(x, function(el) {
      if (is.null(el) || is.environment(el) || isS4(el)) return(character(0))
      as.character(el)
    }), use.names = FALSE)
  }
  v <- unique(trimws(as.character(x)))
  v[nzchar(v) & !is.na(v)]
}

.chip_safe_oname <- function(original_name, src_path, default = "upload.bin") {
  cand <- ""
  if (!is.null(original_name)) {
    cand <- as.character(original_name)[1]
    if (length(cand) < 1L || is.na(cand)) cand <- ""
  }
  if (!nzchar(cand)) {
    cand <- basename(as.character(src_path)[1])
    if (length(cand) < 1L || is.na(cand)) cand <- ""
  }
  if (!nzchar(cand)) cand <- default
  # Sanitize stem but keep a real extension (.bam/.bed/…) for downstream checks.
  ext <- tools::file_ext(cand)
  stem <- tools::file_path_sans_ext(basename(cand))
  stem <- gsub("[^A-Za-z0-9._-]+", "_", stem)
  if (!nzchar(stem) || is.na(stem)) stem <- "upload"
  if (nzchar(ext) && !is.na(ext)) paste0(stem, ".", ext) else stem
}

# Max safe single-shot multipart body for R/plumber (~2GiB long-vector limit,
# leave headroom for multipart wrappers). Over this → use chunked upload.
CHIP_BAM_SINGLESHOT_MAX_BYTES <- as.numeric(Sys.getenv(
  "EMP_CHIP_BAM_SINGLESHOT_MAX_BYTES",
  unset = as.character(1800L * 1024L * 1024L)
))

.chip_move_upload_file <- function(src_path, dest) {
  src_norm <- tryCatch(normalizePath(src_path, mustWork = TRUE), error = function(e) src_path)
  dest_norm <- normalizePath(dest, mustWork = FALSE)
  if (identical(src_norm, dest_norm)) return(invisible(TRUE))
  # Prefer rename (same filesystem). Fall back to copy+unlink across volumes
  # (e.g. /tmp → ~/Library/Application Support/...).
  moved <- FALSE
  if (!file.exists(dest)) {
    moved <- isTRUE(tryCatch(file.rename(src_path, dest), error = function(e) FALSE))
  }
  if (!moved) {
    ok <- isTRUE(tryCatch(file.copy(src_path, dest, overwrite = TRUE), error = function(e) FALSE))
    if (!ok || !file.exists(dest)) {
      stop(paste0(
        "无法保存上传的 BAM/SAM（跨磁盘复制失败）。",
        " Failed to store uploaded BAM/SAM (rename/copy to session storage failed)."
      ))
    }
    tryCatch(unlink(src_path), error = function(e) invisible(NULL))
  }
  invisible(TRUE)
}

.chip_upload_meta_path <- function(session_id, upload_id) {
  file.path(chip_bam_dir(session_id), paste0(".upload_", upload_id, ".json"))
}

.chip_upload_partial_path <- function(session_id, upload_id) {
  file.path(chip_bam_dir(session_id), paste0(".upload_", upload_id, ".partial"))
}

chip_bam_upload_init <- function(session_id, original_name, group = "t", total_bytes = NULL) {
  session_id <- chip_require_session(session_id)
  grp <- tolower(chip_require_string(group, "group"))
  if (!grp %in% c("t", "c", "control", "treatment")) {
    stop("group 必须是 t（处理组）或 c（对照组）。 group must be 't' or 'c'.")
  }
  grp <- if (grp %in% c("c", "control")) "c" else "t"
  oname <- .chip_safe_oname(original_name, original_name %||% "alignment.bam", default = "alignment.bam")
  if (!tolower(tools::file_ext(oname)) %in% c("bam", "sam")) {
    oname <- paste0(tools::file_path_sans_ext(oname), ".bam")
  }
  tb <- suppressWarnings(as.numeric(total_bytes %||% NA_real_)[1])
  if (!is.finite(tb) || tb < 0) tb <- NA_real_
  upload_id <- paste0(
    format(Sys.time(), "%Y%m%d%H%M%S"),
    "_",
    paste(sample(c(letters, 0:9), 10, replace = TRUE), collapse = "")
  )
  bdir <- chip_bam_dir(session_id)
  partial <- .chip_upload_partial_path(session_id, upload_id)
  if (file.exists(partial)) unlink(partial)
  # Create empty partial in session dir (same FS as final dest → rename-safe).
  if (!isTRUE(file.create(partial))) {
    stop("无法在会话目录创建上传临时文件。 Cannot create upload staging file.")
  }
  meta <- list(
    upload_id = upload_id,
    session_id = session_id,
    name = oname,
    group = grp,
    total_bytes = if (is.finite(tb)) tb else NULL,
    received_bytes = 0,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")
  )
  meta_path <- .chip_upload_meta_path(session_id, upload_id)
  jsonlite::write_json(meta, meta_path, auto_unbox = TRUE, pretty = TRUE)
  list(
    success = TRUE,
    upload_id = upload_id,
    name = oname,
    group = grp,
    staging_dir = bdir,
    max_singleshot_bytes = CHIP_BAM_SINGLESHOT_MAX_BYTES
  )
}

# Reliable chunk append without loading multi-GB BAM into an R raw vector.
.chip_append_chunk_file <- function(chunk_path, partial) {
  # Note: base::file.append() is unreliable on some macOS/R builds (returns TRUE
  # but does not grow the destination). Always stream-append via connections.
  con_in <- file(chunk_path, "rb")
  on.exit(try(close(con_in), silent = TRUE), add = TRUE)
  con_out <- file(partial, "ab")
  on.exit(try(close(con_out), silent = TRUE), add = TRUE)
  repeat {
    buf <- readBin(con_in, what = "raw", n = 8L * 1024L * 1024L)
    if (!length(buf)) break
    writeBin(buf, con_out)
  }
  invisible(TRUE)
}

chip_bam_upload_chunk <- function(session_id, upload_id, chunk_path, chunk_index = NULL) {
  session_id <- chip_require_session(session_id)
  upload_id <- chip_require_string(upload_id, "upload_id")
  chunk_path <- chip_require_string(chunk_path, "chunk_path")
  if (!file.exists(chunk_path)) {
    stop("分片文件不存在。 Uploaded chunk file not found on server.")
  }
  meta_path <- .chip_upload_meta_path(session_id, upload_id)
  partial <- .chip_upload_partial_path(session_id, upload_id)
  if (!file.exists(meta_path) || !file.exists(partial)) {
    stop("上传会话无效或已过期，请重新开始分片上传。 Invalid/expired chunked upload; re-init.")
  }
  meta <- tryCatch(
    jsonlite::fromJSON(meta_path, simplifyVector = FALSE),
    error = function(e) stop("上传元数据损坏。 Corrupt upload metadata.")
  )
  chunk_size <- as.numeric(file.info(chunk_path)$size %||% 0)
  .chip_append_chunk_file(chunk_path, partial)
  tryCatch(unlink(chunk_path), error = function(e) invisible(NULL))
  received <- as.numeric(file.info(partial)$size %||% 0)
  meta$received_bytes <- received
  meta$last_chunk_index <- chunk_index
  meta$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")
  jsonlite::write_json(meta, meta_path, auto_unbox = TRUE, pretty = TRUE)
  list(
    success = TRUE,
    upload_id = upload_id,
    received_bytes = received,
    chunk_bytes = chunk_size,
    chunk_index = chunk_index
  )
}

chip_bam_upload_complete <- function(session_id, upload_id) {
  session_id <- chip_require_session(session_id)
  upload_id <- chip_require_string(upload_id, "upload_id")
  meta_path <- .chip_upload_meta_path(session_id, upload_id)
  partial <- .chip_upload_partial_path(session_id, upload_id)
  if (!file.exists(meta_path) || !file.exists(partial)) {
    stop("上传会话无效或已过期。 Invalid/expired chunked upload.")
  }
  meta <- jsonlite::fromJSON(meta_path, simplifyVector = FALSE)
  expected <- suppressWarnings(as.numeric(meta$total_bytes %||% NA_real_)[1])
  got <- as.numeric(file.info(partial)$size %||% 0)
  if (is.finite(expected) && expected > 0 && got != expected) {
    stop(sprintf(
      "分片上传不完整：期望 %s 字节，实际 %s。 Chunked upload incomplete: expected %s bytes, got %s.",
      expected, got, expected, got
    ))
  }
  if (got <= 0) stop("上传文件为空。 Uploaded BAM is empty.")
  oname <- meta$name %||% "alignment.bam"
  grp <- meta$group %||% "t"
  # Stage as a named tempfile then register via chip_upload_bam (same-dir rename).
  staged <- file.path(dirname(partial), paste0(".complete_", upload_id, "_", oname))
  if (file.exists(staged)) unlink(staged)
  if (!isTRUE(file.rename(partial, staged))) {
    if (!isTRUE(file.copy(partial, staged, overwrite = TRUE))) {
      stop("无法完成分片合并。 Failed to finalize chunked BAM.")
    }
    unlink(partial)
  }
  out <- chip_upload_bam(session_id, staged, original_name = oname, group = grp)
  tryCatch(unlink(meta_path), error = function(e) invisible(NULL))
  out$upload_id <- upload_id
  out$received_bytes <- got
  out
}

chip_bam_upload_cancel <- function(session_id, upload_id) {
  session_id <- chip_require_session(session_id)
  upload_id <- chip_require_string(upload_id, "upload_id")
  meta_path <- .chip_upload_meta_path(session_id, upload_id)
  partial <- .chip_upload_partial_path(session_id, upload_id)
  bdir <- chip_bam_dir(session_id)
  # upload_id is alphanumeric + underscore from chip_bam_upload_init.
  staged <- list.files(bdir, pattern = paste0("^\\.complete_", upload_id), full.names = TRUE)
  tryCatch(unlink(c(partial, meta_path, staged)), error = function(e) invisible(NULL))
  list(success = TRUE, cancelled = TRUE, upload_id = upload_id)
}

chip_upload_bam <- function(session_id, src_path, original_name = NULL, group = "t") {
  session_id <- chip_require_session(session_id)
  src_path <- chip_require_string(src_path, "src_path")
  if (!file.exists(src_path)) {
    stop("服务器上找不到上传文件。 Uploaded file not found on server.")
  }
  grp <- tolower(chip_require_string(group, "group"))
  if (!grp %in% c("t", "c", "control", "treatment")) {
    stop("group 必须是 t（处理组）或 c（对照组）。 group must be 't' or 'c'.")
  }
  grp <- if (grp %in% c("c", "control")) "c" else "t"
  bdir <- chip_bam_dir(session_id)
  oname <- .chip_safe_oname(original_name, src_path, default = "alignment.bam")
  # If tempfile lost the .bam/.sam suffix, force from original_name / default.
  if (!tolower(tools::file_ext(oname)) %in% c("bam", "sam")) {
    orig_ext <- tolower(tools::file_ext(as.character(original_name %||% "")[1]))
    if (orig_ext %in% c("bam", "sam")) {
      oname <- paste0(tools::file_path_sans_ext(oname), ".", orig_ext)
    } else {
      oname <- paste0(tools::file_path_sans_ext(oname), ".bam")
    }
  }
  dest <- file.path(bdir, oname)
  .chip_move_upload_file(src_path, dest)
  bam_path <- chip_ensure_bam(dest, bdir)
  # Ensure .bai/.csi so deepTools bamCoverage / MACS can use the BAM immediately.
  idx <- .chip_ensure_bam_index(bam_path)
  manifest <- chip_load_manifest(session_id)
  files <- manifest$files
  files <- Filter(function(f) !identical(f$name, oname), files)
  entry <- list(
    id = paste0("bam_", format(Sys.time(), "%Y%m%d%H%M%S"), "_", length(files) + 1L),
    name = oname,
    path = bam_path,
    group = grp,
    format = chip_bam_format_flag(bam_path),
    indexed = isTRUE(idx$success),
    index_path = idx$index %||% "",
    index_method = idx$method %||% "",
    index_error = if (!isTRUE(idx$success)) (idx$error %||% "") else ""
  )
  files[[length(files) + 1L]] <- entry
  manifest$files <- files
  chip_save_manifest(session_id, manifest)
  list(
    success = TRUE,
    file = entry,
    manifest = manifest,
    indexed = isTRUE(idx$success),
    index_warning = if (!isTRUE(idx$success)) (idx$error %||% "") else NULL
  )
}

chip_register_bams <- function(session_id, entries) {
  session_id <- chip_require_session(session_id)
  if (is.null(entries) || !length(entries)) stop("entries is required (list of {path, group}).")
  manifest <- chip_load_manifest(session_id)
  files <- manifest$files
  index_warnings <- character(0)
  for (e in entries) {
    p <- chip_require_string(e$path %||% e[["path"]], "path")
    # Both callers of this function take the path from the client: POST
    # /api/workflows/chipseq/bams/register directly, and chip_scan_folder() from a directory that
    # emp_resolve_allowed_dir() has already validated. Gate here so neither can reach a file
    # outside EMP_ALLOWED_ROOTS. Uploaded BAMs do not pass through this function.
    p <- emp_resolve_allowed_file(p, "BAM/SAM path")
    if (!file.exists(p)) stop("BAM/SAM not found: ", p)
    grp <- tolower(as.character(e$group %||% e[["group"]] %||% "t")[1])
    grp <- if (grp %in% c("c", "control")) "c" else "t"
    bam_path <- chip_ensure_bam(p, chip_bam_dir(session_id))
    idx <- .chip_ensure_bam_index(bam_path)
    if (!isTRUE(idx$success)) {
      index_warnings <- c(index_warnings, idx$error %||% basename(bam_path))
    }
    nm <- basename(bam_path)
    files <- Filter(function(f) !identical(f$path, bam_path), files)
    files[[length(files) + 1L]] <- list(
      id = paste0("reg_", length(files) + 1L),
      name = nm,
      path = bam_path,
      group = grp,
      format = chip_bam_format_flag(bam_path),
      indexed = isTRUE(idx$success),
      index_path = idx$index %||% ""
    )
  }
  manifest$files <- files
  chip_save_manifest(session_id, manifest)
  list(
    success = TRUE,
    n_files = length(files),
    manifest = manifest,
    index_warnings = if (length(index_warnings)) index_warnings else NULL
  )
}

chip_scan_folder <- function(session_id, folder_path, default_group = "t") {
  session_id <- chip_require_session(session_id)
  folder_path <- chip_require_string(folder_path, "folder_path")
  # Server-supplied directories go through the same EMP_ALLOWED_ROOTS gate as /api/import/path.
  # Without this the endpoint enumerated any directory the API process could read.
  folder_path <- emp_resolve_allowed_dir(folder_path, "folder_path")
  if (!dir.exists(folder_path)) stop("folder_path does not exist.")
  hits <- list.files(folder_path, pattern = "\\.(bam|sam|BAM|SAM)$", full.names = TRUE)
  if (!length(hits)) stop("No BAM/SAM files found in folder.")
  grp <- tolower(as.character(default_group)[1])
  grp <- if (grp %in% c("c", "control")) "c" else "t"
  entries <- lapply(hits, function(p) list(path = p, group = grp))
  chip_register_bams(session_id, entries)
}

chip_list_bams <- function(session_id) {
  manifest <- .chip_ensure_peak_files_registry(session_id, persist = TRUE)
  t_n <- sum(vapply(manifest$files %||% list(), function(f) identical(f$group, "t"), logical(1)))
  c_n <- sum(vapply(manifest$files %||% list(), function(f) identical(f$group, "c"), logical(1)))
  peak_list <- chip_list_peaks(session_id)
  list(
    success = TRUE,
    files = manifest$files %||% list(),
    n_treatment = t_n,
    n_control = c_n,
    last_peaks = peak_list$last_peaks %||% NULL,
    peak_files = peak_list$peak_files %||% list(),
    active_peak_id = peak_list$active_peak_id %||% "",
    last_annotation_csv = manifest$last_annotation_csv %||% ""
  )
}

# Accept a pre-called peak file (BED / narrowPeak / broadPeak / gff) and
# register it in the manifest as `last_peaks`, so downstream annotation
# and cross-omics analysis can run directly without re-calling.
chip_upload_peaks <- function(session_id, src_path, original_name = NULL,
                              genome = "mm", preset = "chipseq_tf") {
  session_id <- chip_require_session(session_id)
  src_path <- chip_require_string(src_path, "src_path")
  if (!file.exists(src_path)) stop("Uploaded peak file not found on server.")
  ok_ext <- c("bed", "narrowpeak", "broadpeak", "gff", "gff3", "txt", "csv", "tsv")
  ext <- tolower(tools::file_ext(src_path))
  orig_ext <- tolower(tools::file_ext(as.character(original_name %||% "")[1]))
  if (is.na(orig_ext)) orig_ext <- ""
  if (!(ext %in% ok_ext) && !(orig_ext %in% ok_ext)) {
    stop("Unsupported peak file extension: .", if (nzchar(ext)) ext else orig_ext,
         " (use .bed / .narrowPeak / .broadPeak / .gff)")
  }
  oname <- .chip_safe_oname(original_name, src_path, default = "peaks.bed")
  if (!(tolower(tools::file_ext(oname)) %in% ok_ext)) {
    oname <- paste0(tools::file_path_sans_ext(oname), ".bed")
  }

  # Tiny header sanity check so we can hint at BED vs GFF without the user
  # having to re-specify; actual parsing happens in chip_annotate_peaks().
  hdr <- tryCatch(readLines(src_path, n = 1L, warn = FALSE), error = function(e) "")
  format_hint <- if (length(hdr) && grepl("^track", hdr[1])) "UCSC track" else
                 if (identical(tolower(tools::file_ext(oname)), "gff3") || identical(tolower(tools::file_ext(oname)), "gff")) "gff" else
                 if (identical(tolower(tools::file_ext(oname)), "narrowpeak")) "narrowPeak" else
                 if (identical(tolower(tools::file_ext(oname)), "broadpeak")) "broadPeak" else
                 "BED"

  run_dir <- chip_run_dir(session_id,
                          paste0("preimported_", tools::file_path_sans_ext(oname)))
  dest <- file.path(run_dir, basename(oname))
  src_norm <- tryCatch(normalizePath(src_path, mustWork = TRUE), error = function(e) src_path)
  dest_norm <- normalizePath(dest, mustWork = FALSE)
  if (!identical(src_norm, dest_norm)) {
    ok <- file.copy(src_path, dest, overwrite = TRUE)
    if (!isTRUE(ok) || !file.exists(dest)) stop("Failed to store uploaded peak file on server.")
  }

  gcfg <- chip_genome_config(genome)
  assembly <- .chip_assembly_from_genome(genome)
  n_peaks <- .chip_count_peak_lines(dest)
  reg <- .chip_register_peak_file(
    session_id = session_id,
    peak_file = dest,
    name = oname,
    source = "upload",
    genome = genome,
    assembly = assembly,
    n_peaks = n_peaks,
    run_dir = run_dir,
    summit_file = "",
    format_hint = format_hint,
    preset = preset %||% "custom",
    extra = list(
      treatment_bams = character(0),
      control_bams = character(0),
      macs_args = character(0)
    ),
    set_active = TRUE
  )

  list(
    success = TRUE,
    peak_file = dest,
    run_dir = run_dir,
    format_hint = format_hint,
    genome = gcfg$macs,
    assembly = assembly,
    preset = preset %||% "custom",
    n_peaks = as.integer(n_peaks),
    peak_id = reg$entry$id,
    last_peaks = reg$last_peaks,
    peak_files = reg$peak_files
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
    p <- .chip_path_scalar(f$path %||% NULL)
    if (is.null(p) || !isTRUE(file.exists(p))) next
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
  # Explicit override: EMP_MACS (file) or EMP_MACS_BIN (dir containing macs3/macs2).
  for (env_key in c("EMP_MACS", "EMP_MACS_BIN")) {
    override <- Sys.getenv(env_key, unset = "")
    if (!nzchar(override)) next
    for (cmd in candidates) {
      p <- if (dir.exists(override)) {
        file.path(override, cmd)
      } else if (file.exists(override) && grepl(paste0(cmd, "(\\.(exe|bat|cmd))?$"),
                                                basename(override), ignore.case = TRUE)) {
        override
      } else {
        ""
      }
      if (nzchar(p) && file.exists(p) && file.access(p, 1) == 0) {
        return(list(cmd = cmd, path = normalizePath(p, winslash = "/", mustWork = FALSE)))
      }
    }
  }
  for (cmd in candidates) {
    p <- .chip_tool_on_path(cmd)
    if (nzchar(p)) return(list(cmd = cmd, path = p))
  }
  NULL
}

chip_profile <- function(session_id, experiment = NULL) {
  session_id <- chip_require_session(session_id)
  out <- list(
    has_macs3 = nzchar(.chip_tool_on_path("macs3")),
    has_macs2 = nzchar(.chip_tool_on_path("macs2")),
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

# Coerce optional numeric form fields: NULL / "" / length-0 → NA_real_ (never numeric(0)).
.chip_as_num1 <- function(x) {
  if (is.null(x)) return(NA_real_)
  while (is.list(x) && !is.object(x) && length(x) == 1L) x <- x[[1L]]
  if (length(x) < 1L) return(NA_real_)
  suppressWarnings(as.numeric(x[[1L]]))
}

# Optional string-ish form field → single non-empty string or NULL (NA-safe).
.chip_opt_str1 <- function(x) {
  s <- .chip_form_scalar(x)
  if (is.null(s)) return(NULL)
  s
}

chip_call_peaks <- function(session_id, treatment_bam = NULL, control_bam = NULL,
                            treatment_bams = NULL, control_bams = NULL,
                            use_manifest = FALSE,
                            genome = "hs", run_id = NULL,
                            qvalue = 0.01, pvalue = NULL,
                            format = NULL, preset = NULL,
                            gsize = NULL,
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

  # Coerce checkbox / JSON flags once (never leave logical NA in if()).
  use_manifest <- isTRUE(use_manifest)
  broad <- isTRUE(broad)
  nomodel <- isTRUE(nomodel)
  fix_bimodal <- isTRUE(fix_bimodal)
  call_summits <- isTRUE(call_summits)
  nolambda <- isTRUE(nolambda)
  cutoff_analysis <- isTRUE(cutoff_analysis)
  save_bdg <- isTRUE(save_bdg)

  preset_key <- .chip_opt_str1(preset)
  if (!is.null(preset_key) && !identical(tolower(preset_key), "custom")) {
    pr <- .chip_macs_preset(preset_key)
    # Skip UI-only metadata; never overwrite BAM / genome / prefer_macs selectors.
    skip_nm <- c(
      "treatment_bam", "control_bam", "treatment_bams", "control_bams",
      "use_manifest", "genome", "run_id", "prefer_macs", "extra_args",
      "label", "description"
    )
    for (nm in names(pr)) {
      if (nm %in% skip_nm) next
      assign(nm, pr[[nm]], envir = environment())
    }
    # Re-coerce flags after preset overwrite (presets store plain TRUE/FALSE).
    broad <- isTRUE(broad)
    nomodel <- isTRUE(nomodel)
    fix_bimodal <- isTRUE(fix_bimodal)
    call_summits <- isTRUE(call_summits)
    nolambda <- isTRUE(nolambda)
    cutoff_analysis <- isTRUE(cutoff_analysis)
    save_bdg <- isTRUE(save_bdg)
    # p-value presets must not fall through to default -q.
    pv_preset <- .chip_as_num1(pvalue)
    if (isTRUE(is.finite(pv_preset)) && isTRUE(pv_preset > 0) && isTRUE(pv_preset < 1)) {
      qvalue <- NULL
    }
  }

  # --call-summits is for narrow peaks; drop it quietly under --broad.
  if (isTRUE(broad) && isTRUE(call_summits)) {
    call_summits <- FALSE
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
    stop(
      "请先在 ChIP-seq 第 2 节上传至少一个 Treatment（IP/ChIP）BAM/SAM。",
      " / At least one Treatment (IP/ChIP) BAM/SAM is required before Call peaks."
    )
  }
  for (p in c(t_bams, c_bams)) {
    if (!isTRUE(nzchar(p)) || !isTRUE(file.exists(p))) {
      stop("BAM/SAM 文件不存在 / BAM/SAM not found: ", p)
    }
  }

  macs <- chip_find_macs(prefer_macs %||% "auto")
  if (is.null(macs)) {
    stop("MACS2/3 is not installed. Please install macs3 (recommended) or macs2.")
  }

  fmt_s <- .chip_opt_str1(format)
  fmt <- if (!is.null(fmt_s) && !identical(toupper(fmt_s), "AUTO")) {
    toupper(fmt_s)
  } else {
    # AUTO / unset: prefer BAMPE when alignments are paired (Cut&Run / PE ChIP).
    chip_bam_format_flag(t_bams[1], prefer_pe = TRUE)
  }
  if (fmt %in% c("BAMPE", "BEDPE") && isTRUE(nomodel)) {
    sh <- .chip_opt_str1(shift)
    if (!is.null(sh) && !identical(sh, "0")) {
      stop("--shift cannot be non-zero when format is BAMPE/BEDPE. Use BAM format for --nomodel workflows.")
    }
  }

  # CRITICAL: as.numeric(NULL) → numeric(0); logical(0) && x → NA → if() crash.
  qv <- .chip_as_num1(qvalue)
  if (!isTRUE(is.finite(qv)) || !isTRUE(qv > 0) || !isTRUE(qv < 1)) qv <- 0.01
  pv <- .chip_as_num1(pvalue)
  use_p <- isTRUE(is.finite(pv)) && isTRUE(pv > 0) && isTRUE(pv < 1)

  # Optional numeric -g override (e.g. classic MACS2 mm = 1.87e9).
  # MACS3 short code mm maps to ~2.65e9 (deeptools GRCm38), which differs from MACS2.
  gsize_s <- .chip_opt_str1(gsize)
  g_arg <- if (!is.null(gsize_s) && nzchar(gsize_s)) gsize_s else macs_genome

  out_dir <- chip_run_dir(session_id, run_id)
  run_name <- paste0("chipseq_", format(Sys.time(), "%H%M%S"))
  kd <- .chip_opt_str1(keep_dup) %||% "auto"
  base_args <- c(
    "callpeak",
    "-t", t_bams,
    "-f", fmt,
    "-g", g_arg,
    "-n", run_name,
    "--outdir", out_dir,
    "--keep-dup", chip_require_string(kd, "keep_dup")
  )
  if (isTRUE(use_p)) {
    base_args <- c(base_args, "-p", as.character(pv))
  } else {
    base_args <- c(base_args, "-q", as.character(qv))
  }
  if (length(c_bams)) base_args <- c(base_args, "-c", c_bams)
  if (isTRUE(broad)) base_args <- c(base_args, "--broad")
  bc <- .chip_as_num1(broad_cutoff)
  if (isTRUE(is.finite(bc))) base_args <- c(base_args, "--broad-cutoff", as.character(bc))
  if (isTRUE(nomodel)) base_args <- c(base_args, "--nomodel")
  sh <- .chip_opt_str1(shift)
  if (!is.null(sh)) base_args <- c(base_args, "--shift", sh)
  ex <- .chip_opt_str1(extsize)
  if (!is.null(ex)) base_args <- c(base_args, "--extsize", ex)
  if (isTRUE(fix_bimodal)) base_args <- c(base_args, "--fix-bimodal")
  ts <- .chip_opt_str1(tsize)
  if (!is.null(ts)) base_args <- c(base_args, "-s", ts)
  if (isTRUE(call_summits)) base_args <- c(base_args, "--call-summits")
  fe <- .chip_as_num1(fe_cutoff)
  if (isTRUE(is.finite(fe))) base_args <- c(base_args, "--fe-cutoff", as.character(fe))
  ml <- .chip_opt_str1(min_length)
  if (!is.null(ml)) base_args <- c(base_args, "--min-length", ml)
  mg <- .chip_opt_str1(max_gap)
  if (!is.null(mg)) base_args <- c(base_args, "--max-gap", mg)
  if (isTRUE(nolambda)) base_args <- c(base_args, "--nolambda")
  sl <- .chip_opt_str1(slocal)
  if (!is.null(sl)) base_args <- c(base_args, "--slocal", sl)
  ll <- .chip_opt_str1(llocal)
  if (!is.null(ll)) base_args <- c(base_args, "--llocal", ll)
  st <- .chip_opt_str1(scale_to)
  if (!is.null(st)) {
    stl <- tolower(st)
    if (stl %in% c("large", "small")) base_args <- c(base_args, "--scale-to", stl)
  }
  if (isTRUE(cutoff_analysis)) base_args <- c(base_args, "--cutoff-analysis")
  if (isTRUE(save_bdg)) base_args <- c(base_args, "-B")
  ea <- .chip_opt_str1(extra_args)
  if (!is.null(ea)) {
    extra <- strsplit(ea, "\\s+", perl = TRUE)[[1]]
    extra <- extra[nzchar(extra) & !is.na(extra)]
    if (length(extra)) base_args <- c(base_args, extra)
  }

  log_file <- file.path(out_dir, "macs_callpeak.log")
  err_file <- file.path(out_dir, "macs_callpeak.err.log")
  # system2 redirects via the shell and does not quote args; paths under
  # "~/Library/Application Support/..." would split on spaces without shQuote.
  macs_args <- if (.Platform$OS.type == "windows") {
    base_args
  } else {
    vapply(base_args, shQuote, "", type = "sh")
  }
  cmd_preview <- paste(c(shQuote(macs$path), macs_args), collapse = " ")
  message(sprintf("[chipseq] MACS start (%s) → %s", macs$cmd %||% macs$path, out_dir))
  message(sprintf("[chipseq] MACS cmd: %s", cmd_preview))
  # MACS writes INFO/WARNING to stderr; tee both streams into the same log so
  # api.log / session dirs show progress (stdout alone was often empty).
  status <- system2(macs$path, args = macs_args, stdout = log_file, stderr = log_file)
  # Keep a symlink-style copy name for older UI / docs that look for .err.log.
  tryCatch({
    if (isTRUE(file.exists(log_file))) {
      file.copy(log_file, err_file, overwrite = TRUE)
    }
  }, error = function(e) invisible(NULL))
  .chip_macs_tail <- function(path, n = 40L) {
    if (!isTRUE(file.exists(path))) return("")
    lines <- tryCatch(readLines(path, warn = FALSE), error = function(e) character())
    if (!length(lines)) return("")
    paste(utils::tail(lines, n), collapse = "\n")
  }
  if (!identical(as.integer(status)[1], 0L)) {
    err <- .chip_macs_tail(log_file, 60L)
    if (!nzchar(err)) err <- .chip_macs_tail(err_file, 60L)
    message(sprintf("[chipseq] MACS failed status=%s\n%s", as.character(status)[1], err))
    stop(sprintf("MACS peak calling failed (%s). %s", macs$cmd, err))
  }
  message(sprintf(
    "[chipseq] MACS done status=0 log=%s\n%s",
    log_file,
    .chip_macs_tail(log_file, 12L)
  ))

  peaks <- list.files(out_dir, pattern = "(_peaks\\.narrowPeak|_peaks\\.broadPeak)$", full.names = TRUE)
  summits <- list.files(out_dir, pattern = "_summits\\.bed$", full.names = TRUE)
  xls <- list.files(out_dir, pattern = "_peaks\\.xls$", full.names = TRUE)
  cutoff_txt <- list.files(out_dir, pattern = "_cutoff_analysis\\.txt$", full.names = TRUE)
  peak_file <- if (length(peaks)) peaks[[1]] else ""
  summit_file <- if (length(summits)) summits[[1]] else ""
  n_peaks <- .chip_count_peak_lines(peak_file)
  n_summits <- .chip_count_peak_lines(summit_file)
  # Surface MACS model / fragment-length warnings for the UI.
  macs_warnings <- character()
  log_lines <- tryCatch(readLines(log_file, warn = FALSE), error = function(e) character())
  if (length(log_lines)) {
    macs_warnings <- log_lines[grepl("WARNING", log_lines, fixed = TRUE)]
    frag_hit <- grepl("predicted fragment length is", log_lines, fixed = TRUE)
    if (any(frag_hit)) {
      macs_warnings <- c(
        macs_warnings,
        sub("^.*INFO[^:]*:\\s*", "", log_lines[frag_hit][[1]])
      )
    }
  }
  macs_warnings <- unique(trimws(macs_warnings))
  macs_warnings <- macs_warnings[nzchar(macs_warnings)]
  low_peak_hint <- if (n_peaks < 50L) {
    paste(
      "Only", n_peaks, "peak(s) called — unusual for ChIP-seq / Cut&Run.",
      "For paired-end Cut&Run match local MACS2: use preset「Cut&Run BAMPE (p=0.05)」,",
      "pool all treatment vs control BAMs, -f BAMPE, -p 0.05 (not -q), -g 1.87e9.",
      "Or try --nomodel --extsize 200 / Histone broad if this is a histone mark.",
      "Previous uploaded / MACS peaks remain selectable in 「当前峰文件」."
    )
  } else {
    ""
  }
  peak_id <- NULL
  last_peaks <- NULL
  peak_files <- NULL
  if (nzchar(peak_file) && file.exists(peak_file)) {
    reg <- .chip_register_peak_file(
      session_id = session_id,
      peak_file = peak_file,
      name = basename(peak_file),
      source = "macs",
      genome = macs_genome,
      assembly = .chip_assembly_from_genome(macs_genome),
      n_peaks = n_peaks,
      run_dir = out_dir,
      summit_file = summit_file,
      format_hint = if (grepl("broadPeak$", peak_file, ignore.case = TRUE)) "broadPeak" else "narrowPeak",
      preset = preset %||% "custom",
      extra = list(
        n_summits = n_summits,
        treatment_bams = t_bams,
        control_bams = c_bams,
        macs_args = base_args
      ),
      set_active = TRUE
    )
    peak_id <- reg$entry$id
    last_peaks <- reg$last_peaks
    peak_files <- reg$peak_files
  } else {
    # Keep prior registry intact when MACS produced no peak file.
    manifest <- .chip_ensure_peak_files_registry(session_id, persist = TRUE)
    last_peaks <- manifest$last_peaks
    peak_files <- manifest$peak_files
  }

  list(
    success = TRUE,
    run_dir = out_dir,
    caller = macs$cmd,
    run_name = run_name,
    peak_file = peak_file,
    summit_file = summit_file,
    n_peaks = n_peaks,
    n_summits = n_summits,
    peak_id = peak_id,
    last_peaks = last_peaks,
    peak_files = peak_files,
    xls_file = if (length(xls)) xls[[1]] else "",
    cutoff_analysis_file = if (length(cutoff_txt)) cutoff_txt[[1]] else "",
    log_file = log_file,
    err_file = err_file,
    macs_warnings = macs_warnings,
    low_peak_hint = low_peak_hint,
    treatment_bams = t_bams,
    control_bams = c_bams,
    n_treatment = length(t_bams),
    n_control = length(c_bams),
    genome = macs_genome,
    gsize = g_arg,
    format = fmt,
    cutoff = if (isTRUE(use_p)) paste0("p=", pv) else paste0("q=", qv),
    macs_command = paste(macs$cmd, paste(base_args, collapse = " "))
  )
}

.chip_macs_presets_catalog <- function() {
  # Lab-aligned core (吴丹 LIPUS Cut-Run macs2.sh):
  #   macs2 callpeak -t ... -c ... -f BAMPE -g mm -n NAME --bdg -B -p 0.05
  # TF Cut&Run and Histone Cut&Run use the SAME BAMPE + -p recipe (not --broad).
  # gsize 1.87e9 = classic MACS2 mm (MACS3 short-code mm ≈ 2.65e9).
  # Use modifyList (not c()) so NULL fields like qvalue=NULL are preserved.
  cutrun_core_p05 <- list(
    format = "BAMPE", pvalue = 0.05, qvalue = NULL, keep_dup = "auto",
    broad = FALSE, nomodel = FALSE, call_summits = FALSE, save_bdg = TRUE,
    gsize = "1.87e9"
  )
  cutrun_core_p01 <- modifyList(cutrun_core_p05, list(pvalue = 0.01))
  .with_meta <- function(core, label, description) {
    modifyList(core, list(label = label, description = description))
  }
  list(
    # ── Primary lab assays ──────────────────────────────────────────
    cutrun_tf_p05 = .with_meta(
      cutrun_core_p05,
      "TF Cut&Run (BAMPE, p=0.05) ★",
      "Lab default for TF Cut&Run (Nr4a1/HA vs IgG): pool -t/-c, -f BAMPE -p 0.05 -g 1.87e9 -B. Prefer uploading local narrowPeak when BAM is large."
    ),
    cutrun_tf_p01 = .with_meta(
      cutrun_core_p01,
      "TF Cut&Run (BAMPE, p=0.01)",
      "Stricter TF Cut&Run: same as local macs2.sh -p 0.01."
    ),
    cutrun_histone_p05 = .with_meta(
      cutrun_core_p05,
      "Histone Cut&Run (BAMPE, p=0.05) ★",
      "Lab histone Cut&Run (e.g. His163 vs IgG): same BAMPE -p 0.05 -B as TF — lab scripts do NOT use --broad."
    ),
    cutrun_histone_p01 = .with_meta(
      cutrun_core_p01,
      "Histone Cut&Run (BAMPE, p=0.01)",
      "Stricter histone Cut&Run: BAMPE -p 0.01 -g 1.87e9 -B."
    ),
    atac_bampe_p05 = .with_meta(
      cutrun_core_p05,
      "ATAC-seq (BAMPE, p=0.05) ★",
      "Paired-end ATAC with lab-style -p 0.05 + -B. Pool replicates; optional IgG/input as -c. gsize 1.87e9 for mm parity."
    ),
    atac_bampe_q05 = list(
      label = "ATAC-seq (BAMPE, q=0.05)",
      description = "Paired-end ATAC with FDR -q 0.05 (ENCODE-ish). -f BAMPE -B -g 1.87e9.",
      format = "BAMPE", qvalue = 0.05, keep_dup = "auto", broad = FALSE,
      nomodel = FALSE, call_summits = FALSE, save_bdg = TRUE, gsize = "1.87e9"
    ),
    # ── Aliases (backward compatible) ───────────────────────────────
    cutrun_pe_p05 = .with_meta(cutrun_core_p05, "Cut&Run / PE (alias → TF p=0.05)", "Alias of cutrun_tf_p05."),
    cutrun_pe_p01 = .with_meta(cutrun_core_p01, "Cut&Run / PE (alias → TF p=0.01)", "Alias of cutrun_tf_p01."),
    atac_paired = list(
      label = "ATAC-seq BAMPE (alias → q=0.05)",
      description = "Alias of atac_bampe_q05.",
      format = "BAMPE", qvalue = 0.05, keep_dup = "auto", broad = FALSE,
      save_bdg = TRUE, gsize = "1.87e9"
    ),
    # ── Secondary / advanced ────────────────────────────────────────
    chipseq_tf = list(
      label = "ChIP-seq TF SE (BAM, q=0.01)",
      description = "Classic single-end ChIP-seq TF: -f BAM -q 0.01. Not for Cut&Run — use cutrun_tf_p05.",
      format = "BAM", qvalue = 0.01, keep_dup = "auto", broad = FALSE,
      nomodel = FALSE, call_summits = FALSE, save_bdg = FALSE
    ),
    histone_broad = list(
      label = "Histone broad domains (--broad)",
      description = "Optional broad calling for diffuse marks (H3K27me3 etc.). Lab histone Cut&Run default is cutrun_histone_p05 (narrow BAMPE), not this.",
      format = "BAMPE", pvalue = 0.05, qvalue = NULL, broad = TRUE, broad_cutoff = 0.1,
      keep_dup = "auto", save_bdg = TRUE, gsize = "1.87e9"
    ),
    chipseq_histone_broad = list(
      label = "Histone broad (legacy SE)",
      description = "Legacy: -f BAM --broad -q 0.01. Prefer histone_broad or cutrun_histone_p05.",
      format = "BAM", qvalue = 0.01, broad = TRUE, broad_cutoff = 0.1, keep_dup = "auto"
    ),
    atac_cutting_site = list(
      label = "ATAC cutting site (SE nomodel)",
      description = "Tn5 cut sites on single-end BAM: --nomodel --shift -75 --extsize 150 --keep-dup all.",
      format = "BAM", qvalue = 0.05, nomodel = TRUE, shift = -75, extsize = 150,
      keep_dup = "all", broad = FALSE
    ),
    cuttag_tn5 = list(
      label = "CUT&Tag insertion (MACS3 doc)",
      description = "MACS3 example: --nomodel --shift -50 --extsize 100 on single-end BAM.",
      format = "BAM", qvalue = 0.01, nomodel = TRUE, shift = -50, extsize = 100,
      keep_dup = "auto"
    ),
    dnase_smoothed = list(
      label = "DNase-seq smoothed window",
      description = "MACS3 doc: --nomodel --shift -100 --extsize 200.",
      format = "BAM", qvalue = 0.05, nomodel = TRUE, shift = -100, extsize = 200,
      keep_dup = "auto"
    ),
    no_control = list(
      label = "No control (treatment only)",
      description = "Treatment only; optional --nolambda. Use with caution.",
      format = "BAMPE", pvalue = 0.05, qvalue = NULL, nolambda = TRUE,
      keep_dup = "auto", save_bdg = TRUE, gsize = "1.87e9"
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

.chip_annotate_peak_args <- function(txdb, anno_db,
                                     tss_upstream = -3000, tss_downstream = 3000,
                                     level = "transcript",
                                     overlap = "TSS",
                                     flank_distance = 5000,
                                     add_flank_gene_info = FALSE,
                                     same_strand = FALSE,
                                     ignore_overlap = FALSE,
                                     ignore_upstream = FALSE,
                                     ignore_downstream = FALSE) {
  txdb <- chip_require_string(txdb, "txdb")
  if (!suppressWarnings(requireNamespace(txdb, quietly = TRUE))) {
    stop(sprintf("TxDb package not installed: %s", txdb))
  }
  txdb_obj <- getExportedValue(txdb, txdb)

  # ChIPseeker::getGeneAnno does require(annoDb, character.only=TRUE) —
  # MUST pass the package name string, never the OrgDb environment/object.
  anno_db_name <- .chip_form_scalar(anno_db)
  if (!is.null(anno_db_name)) {
    if (!suppressWarnings(requireNamespace(anno_db_name, quietly = TRUE))) {
      stop(sprintf("OrgDb / annoDb package not installed: %s", anno_db_name))
    }
  }

  tss_up <- suppressWarnings(as.integer(tss_upstream))
  tss_dn <- suppressWarnings(as.integer(tss_downstream))
  if (!is.finite(tss_up)) tss_up <- -3000L
  if (!is.finite(tss_dn)) tss_dn <- 3000L

  lvl <- tolower(.chip_form_scalar(level) %||% "transcript")
  if (!lvl %in% c("transcript", "gene")) lvl <- "transcript"

  ov <- .chip_form_scalar(overlap) %||% "TSS"
  if (!ov %in% c("TSS", "all")) ov <- "TSS"

  fd <- suppressWarnings(as.integer(flank_distance))
  if (!is.finite(fd) || fd < 0L) fd <- 5000L

  list(
    TxDb = txdb_obj,
    annoDb = anno_db_name,
    tssRegion = c(tss_up, tss_dn),
    level = lvl,
    overlap = ov,
    flankDistance = fd,
    addFlankGeneInfo = isTRUE(add_flank_gene_info),
    sameStrand = isTRUE(same_strand),
    ignoreOverlap = isTRUE(ignore_overlap),
    ignoreUpstream = isTRUE(ignore_upstream),
    ignoreDownstream = isTRUE(ignore_downstream)
  )
}

chip_annotate_peaks <- function(session_id, peak_file = NULL,
                                txdb = NULL,
                                anno_db = NULL,
                                genome = "hs",
                                tss_upstream = -3000, tss_downstream = 3000,
                                level = "transcript",
                                overlap = "TSS",
                                flank_distance = 5000,
                                add_flank_gene_info = FALSE,
                                same_strand = FALSE,
                                ignore_overlap = FALSE,
                                ignore_upstream = FALSE,
                                ignore_downstream = FALSE) {
  session_id <- chip_require_session(session_id)
  if (is.null(peak_file) || is.null(.chip_form_scalar(peak_file))) {
    manifest <- chip_load_manifest(session_id)
    peak_file <- manifest$last_peaks$peak_file %||% ""
  }
  peak_file <- chip_require_string(peak_file, "peak_file")
  if (!file.exists(peak_file)) stop("peak_file not found.")
  if (!requireNamespace("ChIPseeker", quietly = TRUE)) {
    stop("ChIPseeker is not installed. Please install Bioconductor package ChIPseeker.")
  }
  if (!requireNamespace("GenomicFeatures", quietly = TRUE)) {
    stop("GenomicFeatures is required for TxDb loading.")
  }

  gcfg <- chip_genome_config(genome)
  txdb <- .chip_form_scalar(txdb) %||% gcfg$txdb
  anno_db <- .chip_form_scalar(anno_db) %||% gcfg$anno_db

  ap <- .chip_annotate_peak_args(
    txdb = txdb, anno_db = anno_db,
    tss_upstream = tss_upstream, tss_downstream = tss_downstream,
    level = level, overlap = overlap, flank_distance = flank_distance,
    add_flank_gene_info = add_flank_gene_info, same_strand = same_strand,
    ignore_overlap = ignore_overlap, ignore_upstream = ignore_upstream,
    ignore_downstream = ignore_downstream
  )

  # Prefer an explicit call over do.call(): under SummarizedExperiment /
  # BiocGenerics the masked do.call can mishandle S4 TxDb / OrgDb-related args
  # and surface as: cannot coerce type 'environment' to vector of type 'character'.
  anno_db_chr <- ap$annoDb
  if (!is.null(anno_db_chr) && !is.character(anno_db_chr)) {
    stop(sprintf(
      "Internal error: annoDb must be a package name string (got %s). Pass e.g. 'org.Hs.eg.db'.",
      paste(class(anno_db_chr), collapse = ",")
    ))
  }
  anno <- tryCatch(
    ChIPseeker::annotatePeak(
      peak = peak_file,
      tssRegion = ap$tssRegion,
      TxDb = ap$TxDb,
      level = ap$level,
      annoDb = anno_db_chr,
      addFlankGeneInfo = ap$addFlankGeneInfo,
      flankDistance = ap$flankDistance,
      sameStrand = ap$sameStrand,
      ignoreOverlap = ap$ignoreOverlap,
      ignoreUpstream = ap$ignoreUpstream,
      ignoreDownstream = ap$ignoreDownstream,
      overlap = ap$overlap,
      verbose = FALSE
    ),
    error = function(e) {
      msg <- conditionMessage(e)
      # Last-resort retry: genomic annotation only (no OrgDb gene symbols).
      if (grepl("environment|character|annoDb|OrgDb|require\\(", msg, ignore.case = TRUE) &&
          !is.null(anno_db_chr)) {
        warning(sprintf(
          "ChIPseeker gene ID annotation failed (%s); retrying without annoDb.",
          msg
        ), call. = FALSE)
        return(ChIPseeker::annotatePeak(
          peak = peak_file,
          tssRegion = ap$tssRegion,
          TxDb = ap$TxDb,
          level = ap$level,
          annoDb = NULL,
          addFlankGeneInfo = FALSE,
          flankDistance = ap$flankDistance,
          sameStrand = ap$sameStrand,
          ignoreOverlap = ap$ignoreOverlap,
          ignoreUpstream = ap$ignoreUpstream,
          ignoreDownstream = ap$ignoreDownstream,
          overlap = ap$overlap,
          verbose = FALSE
        ))
      }
      stop(e)
    }
  )
  df <- as.data.frame(anno)
  out_dir <- chip_run_dir(session_id, "annotation")
  out_csv <- file.path(out_dir, paste0("chipseq_annotation_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".csv"))
  utils::write.csv(df, out_csv, row.names = FALSE)
  manifest <- chip_load_manifest(session_id)
  manifest$last_annotation_csv <- out_csv
  chip_save_manifest(session_id, manifest)
  list(
    success = TRUE,
    n_peaks = nrow(df),
    annotation_csv = out_csv,
    txdb = txdb,
    anno_db = ap$annoDb,
    level = ap$level,
    tssRegion = ap$tssRegion,
    top = utils::head(df, 20)
  )
}

.chip_peak_score_col <- function(df) {
  intersect(c("score", "V5", "fold_enrichment", "signalValue", "FE"), names(df))[1]
}

.chip_promoter_labels <- function() {
  c("Promoter (<=1kb)", "Promoter (1-2kb)", "Promoter (2-3kb)")
}

.chip_enrich_symbol_set <- function(gene_symbols, anno_db_pkg, kegg_org, out_dir, prefix = "all",
                                   p_cutoff = 0.05, max_genes = 2000L) {
  gene_symbols <- unique(trimws(as.character(gene_symbols)))
  gene_symbols <- gene_symbols[nzchar(gene_symbols) & !is.na(gene_symbols)]
  if (length(gene_symbols) < 3) {
    return(list(success = FALSE, message = "Fewer than 3 genes for enrichment.", plots = list(), tables = list()))
  }
  # Cap gene set size to keep GO/KEGG from exhausting memory on large peak sets.
  max_genes <- suppressWarnings(as.integer(max_genes)[1])
  if (!is.finite(max_genes) || max_genes < 50L) max_genes <- 2000L
  if (length(gene_symbols) > max_genes) {
    gene_symbols <- gene_symbols[seq_len(max_genes)]
  }
  if (!requireNamespace("clusterProfiler", quietly = TRUE)) {
    return(list(success = FALSE, message = "clusterProfiler is required for GO/KEGG enrichment.", plots = list(), tables = list()))
  }
  if (!suppressWarnings(requireNamespace(anno_db_pkg, quietly = TRUE))) {
    return(list(
      success = FALSE,
      message = sprintf("OrgDb package not installed: %s", anno_db_pkg),
      plots = list(),
      tables = list()
    ))
  }
  orgdb <- tryCatch(getExportedValue(anno_db_pkg, anno_db_pkg), error = function(e) NULL)
  if (is.null(orgdb)) {
    return(list(success = FALSE, message = paste0("Cannot load OrgDb: ", anno_db_pkg), plots = list(), tables = list()))
  }
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
        if (!is.null(p)) {
          plots[[paste0("GO_", ont)]] <- tryCatch(
            plot_to_base64(p, width = 9, height = 6),
            error = function(e) NULL
          )
        }
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
          if (!is.null(p)) {
            plots$KEGG <- tryCatch(plot_to_base64(p, width = 9, height = 6), error = function(e) NULL)
          }
        }
      }
    }
  }
  list(success = TRUE, plots = plots, tables = tables, n_genes = length(gene_symbols))
}

chip_annotate_peaks_full <- function(session_id, peak_file = NULL,
                                     genome = "hs",
                                     txdb = NULL, anno_db = NULL,
                                     tss_upstream = -3000, tss_downstream = 3000,
                                     score_cutoff = 5,
                                     promoter_only = FALSE,
                                     level = "transcript",
                                     overlap = "TSS",
                                     flank_distance = 5000,
                                     add_flank_gene_info = FALSE,
                                     same_strand = FALSE,
                                     ignore_overlap = FALSE,
                                     ignore_upstream = FALSE,
                                     ignore_downstream = FALSE,
                                     do_enrichment = TRUE) {
  session_id <- chip_require_session(session_id)
  gcfg <- chip_genome_config(genome)
  txdb_use <- .chip_form_scalar(txdb) %||% gcfg$txdb
  anno_db_use <- .chip_form_scalar(anno_db) %||% gcfg$anno_db
  if (is.null(peak_file) || is.null(.chip_form_scalar(peak_file))) {
    manifest <- chip_load_manifest(session_id)
    peak_file <- manifest$last_peaks$peak_file %||% ""
  }
  peak_file <- chip_require_string(peak_file, "peak_file")
  if (!file.exists(peak_file)) stop("peak_file not found.")

  base <- chip_annotate_peaks(
    session_id = session_id,
    peak_file = peak_file,
    txdb = txdb_use,
    anno_db = anno_db_use,
    tss_upstream = tss_upstream,
    tss_downstream = tss_downstream,
    level = level,
    overlap = overlap,
    flank_distance = flank_distance,
    add_flank_gene_info = add_flank_gene_info,
    same_strand = same_strand,
    ignore_overlap = ignore_overlap,
    ignore_upstream = ignore_upstream,
    ignore_downstream = ignore_downstream
  )
  anno_csv <- base$annotation_csv
  df <- read.csv(anno_csv, stringsAsFactors = FALSE, check.names = FALSE)
  out_dir <- dirname(anno_csv)
  plots <- list()
  tables <- list(annotation_all = anno_csv)

  if (requireNamespace("ChIPseeker", quietly = TRUE)) {
    peak_obj <- tryCatch(ChIPseeker::readPeakFile(peak_file), error = function(e) NULL)
    if (!is.null(peak_obj)) {
      ap <- .chip_annotate_peak_args(
        txdb = txdb_use, anno_db = anno_db_use,
        tss_upstream = tss_upstream, tss_downstream = tss_downstream,
        level = level, overlap = overlap, flank_distance = flank_distance,
        add_flank_gene_info = add_flank_gene_info, same_strand = same_strand,
        ignore_overlap = ignore_overlap, ignore_upstream = ignore_upstream,
        ignore_downstream = ignore_downstream
      )
      peak_anno <- tryCatch(
        ChIPseeker::annotatePeak(
          peak = peak_obj,
          tssRegion = ap$tssRegion,
          TxDb = ap$TxDb,
          level = ap$level,
          annoDb = if (!is.null(ap$annoDb) && is.character(ap$annoDb)) ap$annoDb else NULL,
          addFlankGeneInfo = ap$addFlankGeneInfo,
          flankDistance = ap$flankDistance,
          sameStrand = ap$sameStrand,
          ignoreOverlap = ap$ignoreOverlap,
          ignoreUpstream = ap$ignoreUpstream,
          ignoreDownstream = ap$ignoreDownstream,
          overlap = ap$overlap,
          verbose = FALSE
        ),
        error = function(e) NULL
      )
      if (!is.null(peak_anno)) {
        # plotAnnoPie draws to the active device and returns a layout list;
        # capture via pdf(NULL) so plumber stdout is not flooded / crashed.
        plots$annotation_pie <- tryCatch({
          grDevices::pdf(NULL)
          on.exit(try(grDevices::dev.off(), silent = TRUE), add = TRUE)
          invisible(ChIPseeker::plotAnnoPie(peak_anno))
          # Re-draw into a raster via recordPlot is unreliable; skip base64 pie
          # when ggplot alternatives exist. Prefer bar / TSS distance.
          NULL
        }, error = function(e) NULL)
        p_bar <- tryCatch({
          pb <- ChIPseeker::plotAnnoBar(peak_anno)
          plot_to_base64(pb, width = 8, height = 5)
        }, error = function(e) NULL)
        if (!is.null(p_bar) && nzchar(p_bar)) plots$annotation_bar <- p_bar
        p_dist <- tryCatch({
          pd <- ChIPseeker::plotDistToTSS(peak_anno)
          plot_to_base64(pd, width = 8, height = 5)
        }, error = function(e) NULL)
        if (!is.null(p_dist) && nzchar(p_dist)) plots$dist_to_tss <- p_dist
      }
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
  enrich_note <- NULL
  if (isTRUE(do_enrichment)) {
    enrich_all <- tryCatch(
      .chip_enrich_symbol_set(genes_all, anno_db_use, gcfg$kegg, out_dir, "all_peaks"),
      error = function(e) list(success = FALSE, message = conditionMessage(e), plots = list(), tables = list())
    )
    plots <- c(plots, enrich_all$plots %||% list())
    tables <- c(tables, enrich_all$tables %||% list())
    if (!isTRUE(enrich_all$success)) enrich_note <- enrich_all$message %||% "enrichment failed"

    if (nrow(promo) && !is.na(gene_col)) {
      genes_promo <- unique(promo[[gene_col]])
      enrich_promo <- tryCatch(
        .chip_enrich_symbol_set(genes_promo, anno_db_use, gcfg$kegg, out_dir, "promoter"),
        error = function(e) list(success = FALSE, message = conditionMessage(e), plots = list(), tables = list())
      )
      for (nm in names(enrich_promo$plots %||% list())) plots[[paste0("promoter_", nm)]] <- enrich_promo$plots[[nm]]
      for (nm in names(enrich_promo$tables %||% list())) tables[[paste0("promoter_", nm)]] <- enrich_promo$tables[[nm]]
    }
  } else {
    enrich_note <- "enrichment skipped (do_enrichment=FALSE)"
  }

  manifest <- chip_load_manifest(session_id)
  manifest$last_annotation_csv <- anno_csv
  manifest$last_annotation_full <- list(tables = tables, n_peaks = nrow(df))
  chip_save_manifest(session_id, manifest)

  list(
    success = TRUE,
    n_peaks = nrow(df),
    annotation_csv = anno_csv,
    txdb = txdb_use,
    anno_db = anno_db_use,
    level = base$level %||% level,
    tssRegion = base$tssRegion,
    plots = plots,
    tables = tables,
    enrichment_note = enrich_note,
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
  if (is.null(gene_col) || length(gene_col) < 1L || is.na(gene_col)) {
    stop("No gene symbol column in peak annotation.")
  }
  sc_col <- .chip_peak_score_col(anno)
  sc_cut <- suppressWarnings(as.numeric(.chip_form_scalar(score_cutoff) %||% score_cutoff))[1]

  chip_df <- anno
  # Guard: is.finite(numeric(0)) / !is.na(NULL) → logical(0) crashes `&&`.
  if (isTRUE(is.finite(sc_cut)) && isTRUE(!is.null(sc_col)) &&
      isTRUE(length(sc_col) >= 1L) && isTRUE(!is.na(sc_col[[1]])) &&
      isTRUE(sc_col[[1]] %in% names(chip_df))) {
    scv <- suppressWarnings(as.numeric(chip_df[[sc_col[[1]]]]))
    chip_df <- chip_df[is.finite(scv) & scv >= sc_cut, , drop = FALSE]
  }
  if (isTRUE(promoter_filter)) {
    lab <- .chip_promoter_labels()
    if ("annotation" %in% names(chip_df)) {
      chip_df <- chip_df[chip_df$annotation %in% lab, , drop = FALSE]
    }
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
  if (!is.null(feat_col) && length(feat_col) && !is.na(feat_col) && feat_col != "feature") {
    rownames(ad) <- as.character(ad[[feat_col]])
    ad[[feat_col]] <- NULL
  }
  sample_cols <- setdiff(names(ad), c("feature", "GeneID", "gene", "SYMBOL", "gene_name"))
  if (!length(sample_cols)) sample_cols <- names(ad)

  expr_sub <- ad[rownames(ad) %in% chip_genes, sample_cols, drop = FALSE]
  min_cnt <- suppressWarnings(as.numeric(.chip_form_scalar(min_total_counts) %||% min_total_counts))[1]
  if (!isTRUE(is.finite(min_cnt))) min_cnt <- 100
  if (nrow(expr_sub)) {
    rs <- rowSums(expr_sub, na.rm = TRUE)
    expr_sub <- expr_sub[is.finite(rs) & rs >= min_cnt, , drop = FALSE]
  }
  if (isTRUE(nrow(expr_sub) >= 2L) && isTRUE(ncol(expr_sub) >= 2L)) {
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
  if (!is.null(raw) && isTRUE(nrow(raw) > 0L)) {
    gcol <- intersect(c("feature", "gene", "SYMBOL", "GeneID", "id"), names(raw))[1]
    pcol <- intersect(c("padj", "p_val_adj", "P.Value", "pvalue", "p"), names(raw))[1]
    if (!is.null(gcol) && length(gcol) && !is.na(gcol)) {
      diff_sub <- raw[as.character(raw[[gcol]]) %in% chip_genes, , drop = FALSE]
      if (isTRUE(nrow(diff_sub) > 0L)) {
        fn <- file.path(out_dir, "chip_genes_diff.csv")
        utils::write.csv(diff_sub, fn, row.names = FALSE)
        tables$diff <- fn
        pcut <- suppressWarnings(as.numeric(.chip_form_scalar(rnaseq_p_cutoff) %||% rnaseq_p_cutoff))[1]
        if (!isTRUE(is.finite(pcut))) pcut <- 0.05
        if (!is.null(pcol) && length(pcol) && !is.na(pcol)) {
          pv <- suppressWarnings(as.numeric(diff_sub[[pcol]]))
          diff_sig <- diff_sub[!is.na(pv) & pv <= pcut, , drop = FALSE]
          if (isTRUE(nrow(diff_sig) > 0L)) {
            fn2 <- file.path(out_dir, "chip_genes_diff_sig.csv")
            utils::write.csv(diff_sig, fn2, row.names = FALSE)
            tables$diff_sig <- fn2
          }
        }
        use_padj <- isTRUE(identical(as.character(pcol)[1], "padj")) ||
          isTRUE(grepl("adj", as.character(pcol)[1], ignore.case = TRUE))
        vplot <- tryCatch(
          make_volcano(session_id, rnaseq_experiment,
                       fc_cutoff = 0.5, p_cutoff = pcut,
                       use_padj = use_padj),
          error = function(e) NULL
        )
        vplot_b64 <- viz_plot_b64(vplot)
        if (!is.null(vplot_b64) && isTRUE(nzchar(vplot_b64))) plots$volcano_all <- vplot_b64
      }
    }
  }

  enrich_co <- tryCatch(
    .chip_enrich_symbol_set(chip_genes, gcfg$anno_db, gcfg$kegg, out_dir, "coanalysis"),
    error = function(e) list(success = FALSE, message = conditionMessage(e), plots = list(), tables = list())
  )
  if (is.list(enrich_co)) {
    if (length(enrich_co$plots)) plots <- c(plots, enrich_co$plots)
    if (length(enrich_co$tables)) tables <- c(tables, enrich_co$tables)
  }

  if (isTRUE(requireNamespace("ChIPseeker", quietly = TRUE)) && isTRUE(nrow(chip_df) > 0L)) {
    gr <- tryCatch({
      GenomicRanges::GRanges(
        seqnames = chip_df$seqnames,
        ranges = IRanges::IRanges(start = as.integer(chip_df$start), end = as.integer(chip_df$end)),
        strand = if ("strand" %in% names(chip_df)) chip_df$strand else "*"
      )
    }, error = function(e) NULL)
    if (!is.null(gr)) {
      ap <- tryCatch(
        .chip_annotate_peak_args(txdb = gcfg$txdb, anno_db = gcfg$anno_db),
        error = function(e) NULL
      )
      peak_anno_f <- if (!is.null(ap)) {
        tryCatch(
          ChIPseeker::annotatePeak(
            peak = gr,
            tssRegion = ap$tssRegion,
            TxDb = ap$TxDb,
            level = ap$level,
            annoDb = if (!is.null(ap$annoDb) && is.character(ap$annoDb)) ap$annoDb else NULL,
            addFlankGeneInfo = ap$addFlankGeneInfo,
            flankDistance = ap$flankDistance,
            sameStrand = ap$sameStrand,
            ignoreOverlap = ap$ignoreOverlap,
            ignoreUpstream = ap$ignoreUpstream,
            ignoreDownstream = ap$ignoreDownstream,
            overlap = ap$overlap,
            verbose = FALSE
          ),
          error = function(e) NULL
        )
      } else NULL
      if (!is.null(peak_anno_f)) {
        # Avoid plotAnnoPie writing to the plumber graphics device / stdout.
        p_pie <- tryCatch({
          grDevices::pdf(NULL)
          on.exit(grDevices::dev.off(), add = TRUE)
          ChIPseeker::plotAnnoPie(peak_anno_f)
        }, error = function(e) NULL)
        if (!is.null(p_pie)) {
          plots$filtered_annotation_pie <- tryCatch(
            plot_to_base64(p_pie, width = 7, height = 6),
            error = function(e) NULL
          )
        }
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

chip_cross_integrate <- function(session_id, peak_annotation_csv = NULL,
                                 rnaseq_experiment = NULL, proteomics_experiment = NULL,
                                 rnaseq_p_cutoff = 0.05, rnaseq_fc_cutoff = 1,
                                 proteomics_p_cutoff = 0.05, proteomics_fc_cutoff = 0.5) {
  session_id <- chip_require_session(session_id)
  if (is.null(peak_annotation_csv) || !nzchar(as.character(peak_annotation_csv %||% "")[1])) {
    manifest <- chip_load_manifest(session_id)
    peak_annotation_csv <- manifest$last_annotation_csv %||% ""
  }
  peak_annotation_csv <- chip_require_string(peak_annotation_csv, "peak_annotation_csv")
  if (!file.exists(peak_annotation_csv)) stop("peak_annotation_csv not found. Run ChIPseeker annotation first.")
  anno <- read.csv(peak_annotation_csv, stringsAsFactors = FALSE, check.names = FALSE)
  gene_cols <- intersect(c("SYMBOL", "geneId", "GENEID", "geneSymbol"), names(anno))
  if (!length(gene_cols)) stop("No gene identifier column found in peak annotation.")
  chip_genes <- unique(trimws(as.character(anno[[gene_cols[1]]])))
  chip_genes <- chip_genes[nzchar(chip_genes)]

  mk_sig <- function(exp_name, p_cut, fc_cut) {
    exp_name <- .chip_form_scalar(exp_name)
    if (is.null(exp_name) || !isTRUE(nzchar(exp_name))) return(character(0))
    raw <- tryCatch(ensure_diff_raw(session_id, exp_name), error = function(e) NULL)
    if (is.null(raw) || !isTRUE(nrow(raw) > 0L)) return(character(0))
    pcols <- intersect(c("padj", "p_val_adj", "P.Value", "pvalue", "p"), names(raw))
    fcol <- intersect(c("avg_log2FC", "log2FoldChange", "logFC", "effect"), names(raw))
    gcol <- intersect(c("feature", "gene", "SYMBOL", "id"), names(raw))
    if (!length(gcol)) return(character(0))
    pcut <- suppressWarnings(as.numeric(.chip_form_scalar(p_cut) %||% p_cut))[1]
    if (!isTRUE(is.finite(pcut))) pcut <- 0.05
    fcut <- suppressWarnings(as.numeric(.chip_form_scalar(fc_cut) %||% fc_cut))[1]
    if (!isTRUE(is.finite(fcut))) fcut <- 1

    .pick <- function(pcol) {
      idx <- rep(TRUE, nrow(raw))
      if (!is.null(pcol) && nzchar(pcol)) {
        pv <- suppressWarnings(as.numeric(raw[[pcol]]))
        idx <- idx & !is.na(pv) & pv <= pcut
      }
      if (length(fcol)) {
        fv <- suppressWarnings(as.numeric(raw[[fcol[1]]]))
        idx <- idx & !is.na(fv) & abs(fv) >= fcut
      }
      sig <- unique(trimws(as.character(raw[[gcol[1]]][idx])))
      sig[nzchar(sig)]
    }

    # Prefer padj when it yields hits; otherwise fall back to raw p (course demos often have padj DEGs=0).
    sig <- character(0)
    for (pc in pcols) {
      sig <- .pick(pc)
      if (length(sig)) break
    }
    if (!length(sig) && !length(pcols)) sig <- .pick(NULL)
    sig
  }

  rna_sig <- mk_sig(rnaseq_experiment, rnaseq_p_cutoff, rnaseq_fc_cutoff)
  pro_sig <- mk_sig(proteomics_experiment, proteomics_p_cutoff, proteomics_fc_cutoff)
  overlap_rna <- if (length(rna_sig)) intersect(chip_genes, rna_sig) else character(0)
  overlap_pro <- if (length(pro_sig)) intersect(chip_genes, pro_sig) else character(0)
  overlap_all <- if (length(overlap_rna) && length(overlap_pro)) {
    intersect(overlap_rna, overlap_pro)
  } else {
    character(0)
  }

  list(
    success = TRUE,
    chip_genes_n = length(chip_genes),
    rnaseq_sig_n = length(rna_sig),
    proteomics_sig_n = length(pro_sig),
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

# Read BED / narrowPeak / broadPeak / simple TSV peak tables for QC (no ChIPseeker required).
.chip_read_peak_table <- function(peak_file) {
  peak_file <- chip_require_string(peak_file, "peak_file")
  if (!file.exists(peak_file)) stop("peak_file not found.")

  # Prefer ChIPseeker when available (handles UCSC track lines / GFF cleanly).
  # Fall through on empty results: MACS summits (start==end) can yield 0 ranges.
  if (requireNamespace("ChIPseeker", quietly = TRUE)) {
    gr <- tryCatch(ChIPseeker::readPeakFile(peak_file), error = function(e) NULL)
    if (!is.null(gr) && length(gr) > 0L) {
      df <- as.data.frame(gr)
      # Standardize genomic columns when present.
      ren <- c(seqnames = "chrom", start = "start", end = "end", width = "width")
      for (nm in names(ren)) {
        if (nm %in% names(df) && !(ren[[nm]] %in% names(df))) {
          names(df)[names(df) == nm] <- ren[[nm]]
        }
      }
      if (!("width" %in% names(df)) && all(c("start", "end") %in% names(df))) {
        df$width <- as.numeric(df$end) - as.numeric(df$start) + 1
      }
      # Tag as 1-based inclusive (IRanges) so writers can expand summits safely.
      df$coord_system <- "iranges_1based"
      return(df)
    }
  }

  lines <- tryCatch(readLines(peak_file, warn = FALSE, encoding = "UTF-8"), error = function(e) character(0))
  if (!length(lines)) stop(.chip_empty_peaks_error(peak_file, 0L))
  keep <- !grepl("^(track|browser|#)", lines, ignore.case = TRUE)
  body <- lines[keep]
  body <- body[nzchar(trimws(body))]
  if (!length(body)) stop(.chip_empty_peaks_error(peak_file, 0L))

  first <- body[[1]]
  sep <- if (grepl("\t", first, fixed = TRUE)) "\t" else
    if (grepl(",", first, fixed = TRUE)) "," else ""
  con <- textConnection(body)
  on.exit(close(con), add = TRUE)
  df <- tryCatch(
    utils::read.table(
      con, header = FALSE, sep = sep, quote = "", comment.char = "",
      stringsAsFactors = FALSE, fill = TRUE, check.names = FALSE
    ),
    error = function(e) stop("Failed to parse peak table: ", conditionMessage(e))
  )
  if (!nrow(df) || ncol(df) < 3L) stop("Peak table must have at least chrom/start/end columns.")

  # Detect header row (non-numeric start/end).
  start_ok <- suppressWarnings(!anyNA(as.numeric(df[[2]][seq_len(min(5L, nrow(df)))])))
  if (!start_ok && nrow(df) > 1L) {
    hdr <- as.character(unlist(df[1, , drop = TRUE]))
    df <- df[-1, , drop = FALSE]
    names(df) <- make.unique(gsub("[^A-Za-z0-9._]+", "_", hdr))
  } else {
    nms <- paste0("V", seq_len(ncol(df)))
    # ENCODE narrowPeak / broadPeak / BED6+ column names when no header.
    std <- c("chrom", "start", "end", "name", "score", "strand",
             "signalValue", "pValue", "qValue", "peak")
    n_std <- min(length(std), length(nms))
    nms[seq_len(n_std)] <- std[seq_len(n_std)]
    names(df) <- nms
  }

  # Normalize common chrom/start/end aliases.
  cn <- tolower(names(df))
  chrom_i <- which(cn %in% c("chrom", "chr", "chromosome", "seqnames", "v1"))[1]
  start_i <- which(cn %in% c("start", "chromstart", "chrom_start", "txstart", "v2"))[1]
  end_i <- which(cn %in% c("end", "chromend", "chrom_end", "txend", "v3"))[1]
  if (is.na(chrom_i) || is.na(start_i) || is.na(end_i)) {
    chrom_i <- 1L; start_i <- 2L; end_i <- 3L
  }
  out <- data.frame(
    chrom = as.character(df[[chrom_i]]),
    start = suppressWarnings(as.numeric(df[[start_i]])),
    end = suppressWarnings(as.numeric(df[[end_i]])),
    stringsAsFactors = FALSE
  )
  if ("score" %in% names(df)) out$score <- suppressWarnings(as.numeric(df$score))
  else if ("signalValue" %in% names(df)) out$score <- suppressWarnings(as.numeric(df$signalValue))
  else if ("V5" %in% names(df)) out$score <- suppressWarnings(as.numeric(df$V5))
  # Keep extra columns for preview (capped later).
  extra <- setdiff(names(df), c(names(df)[c(chrom_i, start_i, end_i)], "score"))
  for (nm in head(extra, 8L)) out[[nm]] <- df[[nm]]
  # BED 0-based half-open. MACS summits often have start==end (0-width) or width 1.
  # Expand zero-width to 1 bp so downstream GRanges / BED writers keep them.
  eq <- is.finite(out$start) & is.finite(out$end) & out$end <= out$start
  if (any(eq)) out$end[eq] <- out$start[eq] + 1
  out$width <- out$end - out$start
  out$width <- ifelse(is.finite(out$width) & out$width > 0, out$width, 1)
  out$coord_system <- "bed_0based"
  out <- out[!is.na(out$start) & !is.na(out$end) & nzchar(out$chrom), , drop = FALSE]
  if (!nrow(out)) stop("No valid peak intervals after parsing.")
  out
}

.chip_numeric_summary <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (!length(x)) return(NULL)
  list(
    min = min(x),
    median = stats::median(x),
    mean = mean(x),
    max = max(x),
    n = length(x)
  )
}

# Peak QC summary for preimported / MACS peak files (downstream checklist hook).
chip_peak_qc <- function(session_id, peak_file = NULL) {
  session_id <- chip_require_session(session_id)
  used_path <- .chip_path_scalar(peak_file)
  if (is.null(used_path) || !nzchar(used_path)) {
    resolved <- .chip_resolve_peaks(session_id, NULL)
    used_path <- .chip_path_scalar(resolved$path %||% "")
  }
  if (is.null(used_path) || !nzchar(as.character(used_path)[1])) {
    return(list(
      success = FALSE,
      error = .chip_missing_peaks_error(),
      error_code = "missing_last_peaks",
      n_peaks = 0L,
      path = ""
    ))
  }
  used_path <- as.character(used_path)[1]
  if (!file.exists(used_path)) {
    return(list(
      success = FALSE,
      error = .chip_unreadable_peaks_error(used_path, "文件不存在"),
      error_code = "not_found",
      n_peaks = 0L,
      path = used_path
    ))
  }

  n_raw <- .chip_count_peak_lines(used_path)
  if (identical(n_raw, 0L)) {
    return(list(
      success = FALSE,
      error = .chip_empty_peaks_error(used_path, 0L),
      error_code = "empty_peaks",
      n_peaks = 0L,
      path = used_path
    ))
  }

  df <- tryCatch(
    .chip_read_peak_table(used_path),
    error = function(e) {
      list(.parse_error = conditionMessage(e))
    }
  )
  if (is.list(df) && !is.null(df$.parse_error)) {
    return(list(
      success = FALSE,
      error = .chip_unreadable_peaks_error(used_path, df$.parse_error),
      error_code = "unreadable",
      n_peaks = 0L,
      path = used_path
    ))
  }

  n_peaks <- nrow(df)
  chrom_tab <- sort(table(as.character(df$chrom)), decreasing = TRUE)
  chrom_top_n <- min(20L, length(chrom_tab))
  chrom_counts <- lapply(seq_len(chrom_top_n), function(i) {
    list(chrom = names(chrom_tab)[i], n = as.integer(chrom_tab[[i]]))
  })

  width_vec <- if ("width" %in% names(df)) df$width else (as.numeric(df$end) - as.numeric(df$start))
  width_summary <- .chip_numeric_summary(width_vec)

  score_col <- .chip_peak_score_col(df)
  has_score <- is.character(score_col) && length(score_col) == 1L &&
    !is.na(score_col) && nzchar(score_col) && score_col %in% names(df)
  score_summary <- if (has_score) {
    .chip_numeric_summary(df[[score_col]])
  } else {
    NULL
  }

  preview_n <- min(20L, n_peaks)
  preview <- df[seq_len(preview_n), , drop = FALSE]
  # JSON-safe: convert factors; keep atomic columns only.
  preview_list <- lapply(seq_len(nrow(preview)), function(i) {
    row <- lapply(preview[i, , drop = FALSE], function(v) {
      if (is.factor(v)) as.character(v) else v
    })
    as.list(row)
  })

  list(
    success = TRUE,
    n_peaks = as.integer(n_peaks),
    chrom_counts = chrom_counts,
    width_summary = width_summary,
    score_summary = score_summary,
    score_column = if (!is.null(score_summary)) score_col else NULL,
    preview = preview_list,
    path = used_path,
    columns = names(df)
  )
}

# Resolve a chipseq table path for download (must stay under session chipseq/).
chip_resolve_table_file <- function(session_id, file_path) {
  session_id <- chip_require_session(session_id)
  file_path <- chip_require_string(file_path, "file_path")
  root <- normalizePath(chip_session_dir(session_id), winslash = "/", mustWork = TRUE)
  target <- normalizePath(file_path, winslash = "/", mustWork = FALSE)
  if (!file.exists(target)) stop("Table file not found.")
  root_slash <- paste0(root, "/")
  if (!(identical(target, root) || startsWith(target, root_slash))) {
    stop("Table file is outside the session ChIP-seq directory.")
  }
  target
}

# ── Downstream tools: HOMER / DiffBind / deepTools ─────────────────

.chip_repo_root <- function() {
  # Prefer env set by start scripts; fall back to backend helpers -> webapp -> repo.
  for (k in c("EMP_ROOT", "EMP_REPO_ROOT", "ROOT_DIR")) {
    v <- Sys.getenv(k, unset = "")
    if (nzchar(v) && dir.exists(v)) return(normalizePath(v, winslash = "/", mustWork = FALSE))
  }
  backend <- Sys.getenv("BACKEND_DIR", unset = "")
  if (nzchar(backend) && dir.exists(backend)) {
    # .../webapp/backend -> repo root
    root <- normalizePath(file.path(backend, "..", ".."), winslash = "/", mustWork = FALSE)
    if (dir.exists(root)) return(root)
  }
  here <- tryCatch(normalizePath(getwd(), winslash = "/", mustWork = FALSE), error = function(e) "")
  if (nzchar(here)) {
    cand <- normalizePath(file.path(here, "..", ".."), winslash = "/", mustWork = FALSE)
    if (dir.exists(file.path(cand, "webapp"))) return(cand)
    if (dir.exists(file.path(here, "webapp"))) return(here)
  }
  ""
}

.chip_tool_on_path <- function(names) {
  for (nm in names) {
    p <- Sys.which(nm)
    if (nzchar(p)) return(unname(p))
  }
  # Explicit deepTools / MACS / tool bin overrides (dir or file).
  for (env_key in c("EMP_DEEPTOOLS_BIN", "DEEPTOOLS_BIN", "EMP_MACS_BIN", "EMP_MACS", "EMP_TOOLS_BIN")) {
    override <- Sys.getenv(env_key, unset = "")
    if (!nzchar(override)) next
    for (nm in names) {
      p <- if (dir.exists(override)) {
        file.path(override, nm)
      } else if (file.exists(override) && (basename(override) == nm ||
                 grepl(paste0("^", nm, "(\\.(exe|bat|cmd))?$"), basename(override), ignore.case = TRUE))) {
        override
      } else {
        ""
      }
      if (nzchar(p) && file.exists(p) && file.access(p, 1) == 0) {
        return(normalizePath(p, winslash = "/", mustWork = FALSE))
      }
    }
  }
  # Project-local installs: .local_run/bin and tool venvs (deeptools / macs).
  root <- .chip_repo_root()
  local_bins <- character(0)
  if (nzchar(root)) {
    local_bins <- c(
      file.path(root, ".local_run", "bin"),
      file.path(root, ".local_run", "deeptools_venv", "bin"),
      file.path(root, ".local_run", "macs_venv", "bin")
    )
  }
  # Common HOMER install locations (education lab machines).
  homer_home <- Sys.getenv("HOMER_HOME", unset = "")
  candidates <- character(0)
  for (d in local_bins) {
    candidates <- c(candidates, file.path(d, names))
  }
  if (nzchar(homer_home)) {
    candidates <- c(candidates, file.path(homer_home, "bin", names))
  }
  candidates <- c(
    candidates,
    file.path(path.expand("~"), "Documents", "HOMER", "bin", names),
    file.path(path.expand("~"), "homer", "bin", names),
    file.path("/opt/homer/bin", names),
    file.path("/usr/local/homer/bin", names)
  )
  for (p in candidates) {
    if (file.exists(p) && file.access(p, 1) == 0) return(normalizePath(p, winslash = "/", mustWork = FALSE))
  }
  ""
}

#' system2 wrapper that quotes args when capturing output.
#' R's system2 quotes `command` but NOT `args`; with stdout/stderr capture it
#' runs via a shell, so unquoted paths with spaces ("Application Support") split.
.chip_system2 <- function(command, args = character(), stdout = TRUE, stderr = TRUE) {
  command <- as.character(command)[1]
  args <- as.character(args)
  if (!length(args)) args <- character(0)
  capture <- !is.null(stdout) && !identical(stdout, FALSE) && !identical(stdout, "")
  capture <- capture || (!is.null(stderr) && !identical(stderr, FALSE) && !identical(stderr, ""))
  use_args <- if (capture) shQuote(args) else args
  tryCatch(
    system2(command, args = use_args, stdout = stdout, stderr = stderr),
    error = function(e) e
  )
}

.chip_file_to_base64 <- function(path) {
  if (is.null(path) || !nzchar(as.character(path)[1]) || !file.exists(path)) return(NULL)
  tryCatch(base64enc::base64encode(path), error = function(e) NULL)
}

.chip_df_preview <- function(df, n = 30L) {
  if (is.null(df) || !nrow(df)) return(list())
  preview <- utils::head(df, n)
  lapply(seq_len(nrow(preview)), function(i) {
    row <- lapply(preview[i, , drop = FALSE], function(v) {
      if (is.factor(v)) as.character(v) else if (is.numeric(v)) {
        if (length(v) == 1L && is.finite(v) && abs(v) < 1e-3 && v != 0) format(v, scientific = TRUE, digits = 3)
        else v
      } else v
    })
    as.list(row)
  })
}

.chip_resolve_peaks <- function(session_id, peak_file = NULL) {
  used <- .chip_path_scalar(peak_file)
  genome <- "hs"
  # Ensure registry (may auto-bind last_peaks when missing/stale).
  manifest <- tryCatch(
    .chip_ensure_peak_files_registry(session_id, persist = TRUE),
    error = function(e) chip_load_manifest(session_id)
  )
  if (is.null(used) || !nzchar(used)) {
    used <- .chip_path_scalar(manifest$last_peaks$peak_file %||% "") %||% ""
  }
  # Prefer assembly (hg38/mm10) over MACS shorthand (hs/mm) for HOMER / UI sync.
  if (!is.null(manifest$last_peaks$assembly) && nzchar(as.character(manifest$last_peaks$assembly)[1])) {
    genome <- as.character(manifest$last_peaks$assembly)[1]
  } else if (!is.null(manifest$last_peaks$genome) && nzchar(as.character(manifest$last_peaks$genome)[1])) {
    genome <- as.character(manifest$last_peaks$genome)[1]
  }
  path <- as.character(used %||% "")[1]
  if (nzchar(path) && !file.exists(path)) {
    # Stale manifest path — try registry / disk discovery.
    path <- ""
  }
  if (!nzchar(path)) {
    # Prefer newest non-empty registered peak.
    for (e in manifest$peak_files %||% list()) {
      pf <- .chip_path_scalar(e$peak_file %||% "")
      if (is.null(pf) || !file.exists(pf)) next
      n <- suppressWarnings(as.integer(e$n_peaks %||% .chip_count_peak_lines(pf))[1])
      if (is.finite(n) && n > 0L) {
        path <- pf
        if (!is.null(e$assembly) && nzchar(as.character(e$assembly)[1])) {
          genome <- as.character(e$assembly)[1]
        } else if (!is.null(e$genome) && nzchar(as.character(e$genome)[1])) {
          genome <- as.character(e$genome)[1]
        }
        break
      }
    }
  }
  list(path = path, genome = genome, manifest = manifest)
}

.chip_peaks_to_bed <- function(peak_path, out_bed, max_peaks = 50000L) {
  peak_path <- as.character(peak_path %||% "")[1]
  if (!nzchar(peak_path) || !file.exists(peak_path)) {
    stop(.chip_missing_peaks_error())
  }

  # Prefer GenomicRanges path: ChIPseeker returns 1-based inclusive coords where
  # 1 bp peaks have start==end; writing those as BED with end>start filter wiped
  # all MACS summit intervals ("No valid intervals to write as BED").
  if (requireNamespace("GenomicRanges", quietly = TRUE) &&
      requireNamespace("IRanges", quietly = TRUE)) {
    gr <- tryCatch(.chip_path_to_gr(peak_path), error = function(e) e)
    if (!inherits(gr, "error") && length(gr) > 0L) {
      if (length(gr) > max_peaks) gr <- gr[seq_len(as.integer(max_peaks))]
      # Guarantee positive width (summit / empty BED rows).
      w <- GenomicRanges::width(gr)
      thin <- which(!is.finite(w) | w < 1L)
      if (length(thin)) {
        GenomicRanges::end(gr)[thin] <- GenomicRanges::start(gr)[thin]
      }
      .chip_write_gr_bed(gr, out_bed)
      return(list(bed = out_bed, n = length(gr)))
    }
  }

  df <- .chip_read_peak_table(peak_path)
  if (!nrow(df)) stop(.chip_missing_peaks_error())
  if (nrow(df) > max_peaks) df <- df[seq_len(max_peaks), , drop = FALSE]
  name <- if ("name" %in% names(df)) as.character(df$name) else paste0("peak", seq_len(nrow(df)))
  score <- if ("score" %in% names(df)) {
    sc <- suppressWarnings(as.numeric(df$score))
    ifelse(is.finite(sc), sc, 0)
  } else {
    rep(0, nrow(df))
  }
  start_raw <- suppressWarnings(as.numeric(df$start))
  end_raw <- suppressWarnings(as.numeric(df$end))
  coord <- as.character(df$coord_system %||% "bed_0based")[1]
  if (identical(coord, "iranges_1based")) {
    # Convert 1-based inclusive → BED 0-based half-open; expand summits (start==end).
    start0 <- as.integer(pmax(0, floor(start_raw) - 1L))
    end0 <- as.integer(pmax(start0 + 1L, ceiling(end_raw)))
  } else {
    start0 <- as.integer(pmax(0, floor(start_raw)))
    end0 <- as.integer(ceiling(end_raw))
    # MACS summits: start==end or end<start → keep as 1 bp BED.
    thin <- !is.finite(end0) | end0 <= start0
    end0[thin] <- start0[thin] + 1L
  }
  bed <- data.frame(
    chrom = as.character(df$chrom),
    start = start0,
    end = end0,
    name = name,
    score = score,
    stringsAsFactors = FALSE
  )
  bed <- bed[!is.na(bed$start) & !is.na(bed$end) & bed$end > bed$start & nzchar(bed$chrom), , drop = FALSE]
  if (!nrow(bed)) stop("No valid intervals to write as BED (after summit expansion). Check peak file format.")
  utils::write.table(bed, out_bed, sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
  list(bed = out_bed, n = nrow(bed))
}

.chip_homer_genome_id <- function(genome = "hs") {
  g <- tolower(trimws(as.character(genome %||% "hs")[1]))
  if (g %in% c("mm", "mu", "m", "mm10", "mouse")) return("mm10")
  if (identical(g, "mm39")) return("mm39")
  if (g %in% c("hg19", "grch37")) return("hg19")
  # Human: MACS "hs" / aliases → hg38. Never silently default to legacy hg18.
  if (g %in% c("hg38", "grch38", "hs", "human", "h", "hg18", "ncbi36")) return("hg38")
  # Pass through custom HOMER genome names (installed via configureHomer.pl).
  if (nzchar(g)) return(g)
  "hg38"
}

#' Resolve HOMER install root from findMotifsGenome.pl / HOMER_HOME / common paths.
.chip_homer_home <- function() {
  env <- Sys.getenv("HOMER_HOME", unset = "")
  if (nzchar(env) && dir.exists(env)) {
    return(normalizePath(env, winslash = "/", mustWork = FALSE))
  }
  find_pl <- .chip_tool_on_path(c("findMotifsGenome.pl"))
  if (nzchar(find_pl)) {
    # .../HOMER/bin/findMotifsGenome.pl → .../HOMER
    home <- normalizePath(file.path(dirname(find_pl), ".."), winslash = "/", mustWork = FALSE)
    if (dir.exists(home)) return(home)
  }
  for (cand in c(
    file.path(path.expand("~"), "Documents", "HOMER"),
    file.path(path.expand("~"), "homer"),
    "/opt/homer",
    "/usr/local/homer"
  )) {
    if (dir.exists(cand)) return(normalizePath(cand, winslash = "/", mustWork = FALSE))
  }
  ""
}

#' Parse GENOMES section of HOMER config.txt (officially installed packages).
.chip_homer_config_genomes <- function(homer_home = NULL) {
  home <- as.character(homer_home %||% .chip_homer_home())[1]
  if (!nzchar(home) || !dir.exists(home)) return(character(0))
  cfg <- file.path(home, "config.txt")
  if (!file.exists(cfg)) return(character(0))
  lines <- tryCatch(readLines(cfg, warn = FALSE), error = function(e) character(0))
  if (!length(lines)) return(character(0))
  mode <- ""
  out <- character(0)
  for (ln in lines) {
    if (grepl("^SOFTWARE\\b", ln)) { mode <- "SOFTWARE"; next }
    if (grepl("^ORGANISMS\\b", ln)) { mode <- "ORGANISMS"; next }
    if (grepl("^PROMOTERS\\b", ln)) { mode <- "PROMOTERS"; next }
    if (grepl("^GENOMES\\b", ln)) { mode <- "GENOMES"; next }
    if (grepl("^SETTINGS\\b", ln)) { mode <- "SETTINGS"; next }
    if (!identical(mode, "GENOMES")) next
    if (!nzchar(trimws(ln)) || grepl("^\\s*#", ln)) next
    parts <- strsplit(ln, "\t", fixed = TRUE)[[1]]
    if (length(parts) >= 1L && nzchar(parts[[1]])) out <- c(out, parts[[1]])
  }
  unique(out)
}

#' Genomes that look present on disk (data/genomes/<id> or <home>/<id> with chrom.sizes).
.chip_homer_disk_genomes <- function(homer_home = NULL) {
  home <- as.character(homer_home %||% .chip_homer_home())[1]
  if (!nzchar(home) || !dir.exists(home)) return(character(0))
  out <- character(0)
  dg <- file.path(home, "data", "genomes")
  if (dir.exists(dg)) {
    kids <- list.dirs(dg, full.names = FALSE, recursive = FALSE)
    out <- c(out, kids[nzchar(kids)])
  }
  # Orphan / manual copies at HOMER root (e.g. mm10/) — useful for diagnostics
  # but NOT sufficient for findMotifsGenome unless also in config.txt.
  top <- list.dirs(home, full.names = FALSE, recursive = FALSE)
  for (d in top) {
    if (!nzchar(d) || d %in% c("bin", "cpp", "data", "motifs", "update", "output", "bed_file")) next
    p <- file.path(home, d)
    if (file.exists(file.path(p, "chrom.sizes")) ||
        length(list.files(p, pattern = "\\.fa$", full.names = FALSE)) > 0L) {
      out <- c(out, d)
    }
  }
  unique(out)
}

#' Full HOMER genome inventory for tools/status and preflight checks.
.chip_homer_genome_status <- function() {
  home <- .chip_homer_home()
  cfg_path <- if (nzchar(home)) file.path(home, "config.txt") else ""
  cfg_genomes <- .chip_homer_config_genomes(home)
  disk_genomes <- .chip_homer_disk_genomes(home)
  # Only config-registered genomes are usable by findMotifsGenome.pl.
  list(
    homer_home = home,
    config_path = if (nzchar(cfg_path) && file.exists(cfg_path)) cfg_path else "",
    genomes_installed = cfg_genomes,
    genomes_on_disk = disk_genomes,
    genomes_usable = cfg_genomes
  )
}

.chip_homer_genome_usable <- function(genome_id, status = NULL) {
  st <- status %||% .chip_homer_genome_status()
  gid <- .chip_homer_genome_id(genome_id)
  gid %in% (st$genomes_usable %||% character(0))
}

.chip_install_hint_homer_genome <- function(genome_id, homer_home = NULL) {
  home <- as.character(homer_home %||% .chip_homer_home())[1]
  gid <- .chip_homer_genome_id(genome_id)
  cfg_pl <- if (nzchar(home)) file.path(home, "configureHomer.pl") else "configureHomer.pl"
  paste0(
    "HOMER 基因组「", gid, "」未安装（未写入 config.txt GENOMES）。",
    "请执行：perl ", cfg_pl, " -install ", gid,
    " （例如：perl ~/Documents/HOMER/configureHomer.pl -install ", gid, "）。",
    "仅有磁盘目录但未注册到 config.txt 时 findMotifsGenome.pl 仍会失败（exit=0）。"
  )
}

#' Best-effort background install of a HOMER genome package (long-running).
.chip_homer_try_install_genome <- function(genome_id, wait = FALSE, timeout_sec = 120L) {
  home <- .chip_homer_home()
  gid <- .chip_homer_genome_id(genome_id)
  cfg_pl <- if (nzchar(home)) file.path(home, "configureHomer.pl") else ""
  if (!nzchar(cfg_pl) || !file.exists(cfg_pl)) {
    return(list(started = FALSE, error = "configureHomer.pl not found", genome = gid))
  }
  log_dir <- file.path(tempdir(), "emp_homer_install")
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  log_file <- file.path(log_dir, paste0("install_", gid, ".log"))
  cmd <- paste("perl", shQuote(cfg_pl), "-install", shQuote(gid))
  if (isTRUE(wait)) {
    status <- tryCatch(
      system2("perl", args = c(cfg_pl, "-install", gid),
              stdout = log_file, stderr = log_file, timeout = as.integer(timeout_sec %||% 120L)),
      error = function(e) -1L
    )
    usable <- .chip_homer_genome_usable(gid)
    return(list(
      started = TRUE, waited = TRUE, exit_status = status, genome = gid,
      log_file = log_file, usable_after = usable, command = cmd
    ))
  }
  # Non-blocking: nohup so API request returns immediately.
  sh <- paste0("nohup perl ", shQuote(cfg_pl), " -install ", shQuote(gid),
               " > ", shQuote(log_file), " 2>&1 & echo $!")
  pid <- tryCatch(system(sh, intern = TRUE), error = function(e) character(0))
  list(
    started = length(pid) > 0L && nzchar(pid[[1]]),
    waited = FALSE,
    pid = if (length(pid)) pid[[1]] else NULL,
    genome = gid,
    log_file = log_file,
    command = cmd,
    hint = .chip_install_hint_homer_genome(gid, home)
  )
}

#' Quote argv for system2 (R docs: args with spaces must use shQuote).
.chip_system2_args <- function(...) {
  raw <- unlist(list(...), use.names = FALSE)
  raw <- as.character(raw)
  raw <- raw[nzchar(raw) & !is.na(raw)]
  if (!length(raw)) return(character(0))
  vapply(raw, shQuote, character(1), USE.NAMES = FALSE)
}

.chip_install_hint_homer <- function() {
  paste(
    "HOMER 未安装或不在 PATH 上 / HOMER not found on PATH.",
    "Install: http://homer.ucsd.edu/homer/  (configureHomer.pl -install), then add $HOMER/bin to PATH,",
    "or set HOMER_HOME. Required: findMotifsGenome.pl.",
    sep = " "
  )
}

.chip_install_hint_diffbind <- function() {
  paste(
    "DiffBind 未安装 / DiffBind package not installed.",
    'Install in R: BiocManager::install("DiffBind")',
    sep = " "
  )
}

.chip_install_hint_deeptools <- function(missing = character(0)) {
  miss <- if (length(missing)) paste(missing, collapse = ", ") else "bamCoverage/computeMatrix/plotHeatmap/..."
  paste0(
    "deepTools 未安装或不完整 / deepTools missing (", miss, "). ",
    "Install: conda install -c bioconda deeptools  OR  pip install deeptools"
  )
}

#' Ensure project-local .local_run/R_libs is on .libPaths (DiffBind etc.).
.chip_ensure_local_r_libs <- function() {
  root <- .chip_repo_root()
  if (!nzchar(root)) return(invisible(FALSE))
  local_libs <- file.path(root, ".local_run", "R_libs")
  if (!dir.exists(local_libs)) return(invisible(FALSE))
  local_libs <- normalizePath(local_libs, winslash = "/", mustWork = FALSE)
  paths <- .libPaths()
  if (!(local_libs %in% paths)) {
    .libPaths(c(local_libs, paths))
  }
  # Also surface via env for child processes / diagnostics.
  cur <- Sys.getenv("R_LIBS", unset = "")
  if (!nzchar(cur) || !grepl(local_libs, cur, fixed = TRUE)) {
    Sys.setenv(R_LIBS = if (nzchar(cur)) paste(local_libs, cur, sep = ":") else local_libs)
  }
  invisible(TRUE)
}

#' Detect HOMER / DiffBind / deepTools availability (no session required).
chip_tools_status <- function() {
  .chip_ensure_local_r_libs()
  find_motifs <- .chip_tool_on_path(c("findMotifsGenome.pl"))
  annotate_peaks <- .chip_tool_on_path(c("annotatePeaks.pl"))
  bam_cov <- .chip_tool_on_path(c("bamCoverage"))
  compute_matrix <- .chip_tool_on_path(c("computeMatrix"))
  plot_heatmap <- .chip_tool_on_path(c("plotHeatmap"))
  multi_bam <- .chip_tool_on_path(c("multiBamSummary"))
  plot_corr <- .chip_tool_on_path(c("plotCorrelation"))
  macs3_bin <- .chip_tool_on_path(c("macs3"))
  macs2_bin <- .chip_tool_on_path(c("macs2"))
  samtools_bin <- .chip_tool_on_path(c("samtools"))
  has_diffbind <- suppressWarnings(requireNamespace("DiffBind", quietly = TRUE))
  has_motifmatchr <- suppressWarnings(requireNamespace("motifmatchr", quietly = TRUE))
  has_tfbstools <- suppressWarnings(requireNamespace("TFBSTools", quietly = TRUE))
  has_granges <- suppressWarnings(requireNamespace("GenomicRanges", quietly = TRUE)) &&
    suppressWarnings(requireNamespace("IRanges", quietly = TRUE))
  has_chipseeker <- suppressWarnings(requireNamespace("ChIPseeker", quietly = TRUE))
  has_txdb_hs <- suppressWarnings(requireNamespace("TxDb.Hsapiens.UCSC.hg38.knownGene", quietly = TRUE)) ||
    suppressWarnings(requireNamespace("TxDb.Hsapiens.UCSC.hg19.knownGene", quietly = TRUE))
  has_txdb_mm <- suppressWarnings(requireNamespace("TxDb.Mmusculus.UCSC.mm10.knownGene", quietly = TRUE))
  bedtools <- Sys.which("bedtools")
  homer_gen <- .chip_homer_genome_status()

  deeptools_bins <- list(
    bamCoverage = bam_cov,
    computeMatrix = compute_matrix,
    plotHeatmap = plot_heatmap,
    multiBamSummary = multi_bam,
    plotCorrelation = plot_corr
  )
  deeptools_ok <- all(vapply(deeptools_bins, nzchar, logical(1)))
  macs_ok <- nzchar(macs3_bin) || nzchar(macs2_bin)

  homer_hint <- ""
  if (!nzchar(find_motifs)) {
    homer_hint <- .chip_install_hint_homer()
  } else if (!length(homer_gen$genomes_usable)) {
    homer_hint <- paste0(
      "HOMER CLI 已找到，但 config.txt 中尚无已注册基因组。",
      "安装示例：perl ",
      if (nzchar(homer_gen$homer_home)) file.path(homer_gen$homer_home, "configureHomer.pl") else "configureHomer.pl",
      " -install hg38"
    )
  }

  list(
    success = TRUE,
    tools = list(
      homer = list(
        available = nzchar(find_motifs),
        findMotifsGenome = find_motifs,
        annotatePeaks = annotate_peaks,
        homer_home = homer_gen$homer_home,
        config_path = homer_gen$config_path,
        # I() keeps length-0/1 character vectors as JSON arrays (not scalar/null).
        genomes_installed = I(as.character(homer_gen$genomes_installed %||% character(0))),
        genomes_on_disk = I(as.character(homer_gen$genomes_on_disk %||% character(0))),
        genomes_usable = I(as.character(homer_gen$genomes_usable %||% character(0))),
        install_hint = homer_hint
      ),
      diffbind = list(
        available = isTRUE(has_diffbind),
        lib_paths = I(as.character(.libPaths())),
        install_hint = if (!isTRUE(has_diffbind)) .chip_install_hint_diffbind() else ""
      ),
      deeptools = list(
        available = deeptools_ok,
        binaries = deeptools_bins,
        install_hint = if (!deeptools_ok) {
          miss <- names(deeptools_bins)[!vapply(deeptools_bins, nzchar, logical(1))]
          .chip_install_hint_deeptools(miss)
        } else {
          ""
        }
      ),
      macs = list(
        available = macs_ok,
        macs3 = macs3_bin,
        macs2 = macs2_bin,
        install_hint = if (!macs_ok) {
          "Install macs3 (recommended): python3 -m venv .local_run/macs_venv && .local_run/macs_venv/bin/pip install macs3; symlink/wrapper into .local_run/bin/"
        } else {
          ""
        }
      ),
      samtools = list(
        available = nzchar(samtools_bin),
        path = samtools_bin,
        note = if (!nzchar(samtools_bin)) {
          "samtools missing; BAM indexing falls back to Rsamtools::indexBam when available."
        } else {
          ""
        }
      ),
      genomicranges = list(
        available = isTRUE(has_granges),
        chipseeker = isTRUE(has_chipseeker),
        txdb_hs = isTRUE(has_txdb_hs),
        txdb_mm = isTRUE(has_txdb_mm)
      ),
      bedtools = list(
        available = nzchar(bedtools),
        path = unname(bedtools),
        note = if (!nzchar(bedtools)) {
          "bedtools not installed; peak set ops use pure-R GenomicRanges instead."
        } else {
          ""
        }
      ),
      motifmatchr_fallback = list(
        available = isTRUE(has_motifmatchr) && isTRUE(has_tfbstools)
      )
    )
  )
}

#' HOMER findMotifsGenome.pl motif enrichment on session peaks.
chip_homer_motifs <- function(session_id,
                              peak_file = NULL,
                              genome = NULL,
                              size = 200,
                              motif_length = "8,10,12",
                              annotate = FALSE,
                              max_peaks = 20000L,
                              auto_install = FALSE,
                              noknown = FALSE) {
  session_id <- chip_require_session(session_id)
  .chip_ensure_local_r_libs()
  resolved <- .chip_resolve_peaks(session_id, peak_file)
  peak_path <- resolved$path
  if (!nzchar(peak_path) || !file.exists(peak_path)) {
    return(list(
      success = FALSE,
      error = .chip_missing_peaks_error()
    ))
  }

  find_pl <- .chip_tool_on_path(c("findMotifsGenome.pl"))
  if (!nzchar(find_pl)) {
    # Optional light fallback: only if motifmatchr+TFBSTools already installed.
    mm_ok <- suppressWarnings(requireNamespace("motifmatchr", quietly = TRUE)) &&
      suppressWarnings(requireNamespace("TFBSTools", quietly = TRUE))
    if (!mm_ok) {
      return(list(success = FALSE, tool = "HOMER", error = .chip_install_hint_homer()))
    }
    return(list(
      success = FALSE,
      tool = "HOMER",
      error = paste(
        .chip_install_hint_homer(),
        "motifmatchr/TFBSTools detected but HOMER CLI is preferred for education runs;",
        "full motifmatchr fallback requires BSgenome + JASPAR and is not auto-run here.",
        sep = " "
      ),
      motifmatchr_available = TRUE
    ))
  }

  g_in <- .chip_form_scalar(genome) %||% resolved$genome %||% "hs"
  homer_g <- .chip_homer_genome_id(g_in)
  # Echo UI dropdown value (hg38/hg19/mm10/mm39) — never legacy hg18 for hs/human.
  genome_ui <- homer_g
  size <- suppressWarnings(as.integer(size %||% 200L))[1]
  if (!is.finite(size) || size < 50L) size <- 200L
  motif_length <- .chip_form_scalar(motif_length) %||% "8,10,12"
  max_peaks <- suppressWarnings(as.integer(max_peaks %||% 20000L))[1]
  if (!is.finite(max_peaks) || max_peaks < 100L) max_peaks <- 20000L

  homer_st <- .chip_homer_genome_status()
  install_attempt <- NULL
  if (!.chip_homer_genome_usable(homer_g, homer_st)) {
    # Optional auto-install (long-running; off by default unless EMP_HOMER_AUTO_INSTALL=1).
    do_auto <- isTRUE(auto_install) ||
      identical(tolower(Sys.getenv("EMP_HOMER_AUTO_INSTALL", unset = "")), "1")
    if (do_auto) {
      install_attempt <- .chip_homer_try_install_genome(homer_g, wait = FALSE)
      # Re-check once in case a previous install just finished.
      homer_st <- .chip_homer_genome_status()
    }
    if (!.chip_homer_genome_usable(homer_g, homer_st)) {
      return(list(
        success = FALSE,
        tool = "HOMER",
        error = .chip_install_hint_homer_genome(homer_g, homer_st$homer_home),
        genome = genome_ui,
        genome_homer = homer_g,
        genome_input = g_in,
        genomes_installed = homer_st$genomes_installed,
        genomes_on_disk = homer_st$genomes_on_disk,
        genomes_usable = homer_st$genomes_usable,
        install_attempt = install_attempt,
        exit_status = NULL
      ))
    }
  }

  out_dir <- chip_run_dir(session_id, paste0("homer_", format(Sys.time(), "%H%M%S")))
  # HOMER's internal Perl (ls/rm/open of tmp files) breaks on spaces in paths
  # (e.g. ".../Application Support/..."). Always execute under a space-free
  # staging dir, then copy results back into the session folder.
  work_root <- file.path(tempdir(), paste0("emp_homer_", gsub("[^A-Za-z0-9_-]", "", session_id), "_", format(Sys.time(), "%H%M%S")))
  if (grepl(" ", work_root, fixed = TRUE) || grepl("[[:space:]]", work_root)) {
    work_root <- file.path("/tmp", paste0("emp_homer_", gsub("[^A-Za-z0-9_-]", "", session_id), "_", as.integer(Sys.time())))
  }
  dir.create(work_root, recursive = TRUE, showWarnings = FALSE)
  bed_path <- file.path(work_root, "peaks_for_homer.bed")
  bed_info <- tryCatch(
    .chip_peaks_to_bed(peak_path, bed_path, max_peaks = max_peaks),
    error = function(e) list(error = conditionMessage(e))
  )
  if (!is.null(bed_info$error)) {
    return(list(success = FALSE, error = bed_info$error))
  }
  # Keep a copy under session out_dir for user download / audit.
  tryCatch(file.copy(bed_path, file.path(out_dir, "peaks_for_homer.bed"), overwrite = TRUE), error = function(e) NULL)

  motif_dir <- file.path(work_root, "motifs")
  dir.create(motif_dir, recursive = TRUE, showWarnings = FALSE)
  log_file <- file.path(work_root, "homer_stdout.log")
  # R system2 requires shQuote on every arg that may contain spaces.
  homer_args <- .chip_system2_args(
    bed_path, homer_g, motif_dir, "-size", as.character(size), "-len", motif_length
  )
  # Education / smoke runs: skip known-motif scan (often 10–30+ min).
  if (isTRUE(noknown)) {
    homer_args <- c(homer_args, "-noknown")
  }
  cmd <- paste(c(shQuote(find_pl), homer_args), collapse = " ")
  status <- tryCatch(
    system2(find_pl, args = homer_args, stdout = log_file, stderr = log_file),
    error = function(e) -1L
  )

  # Mirror HOMER outputs into the session run directory.
  motif_dir_session <- file.path(out_dir, "motifs")
  dir.create(motif_dir_session, recursive = TRUE, showWarnings = FALSE)
  if (dir.exists(motif_dir)) {
    tryCatch({
      for (f in list.files(motif_dir, full.names = TRUE)) {
        file.copy(f, file.path(motif_dir_session, basename(f)), recursive = TRUE, overwrite = TRUE)
      }
    }, error = function(e) NULL)
  }
  tryCatch(file.copy(log_file, file.path(out_dir, "homer_stdout.log"), overwrite = TRUE), error = function(e) NULL)
  motif_dir <- motif_dir_session
  log_file <- file.path(out_dir, "homer_stdout.log")
  bed_path <- file.path(out_dir, "peaks_for_homer.bed")
  # Best-effort cleanup of staging (keep if copy failed).
  tryCatch(unlink(work_root, recursive = TRUE), error = function(e) NULL)

  known_path <- file.path(motif_dir, "knownResults.txt")
  denovo_html <- file.path(motif_dir, "homerResults.html")
  denovo_motifs <- file.path(motif_dir, "homerMotifs.all.motifs")
  top_motifs <- list()
  known_df <- NULL
  if (file.exists(known_path)) {
    known_df <- tryCatch(
      utils::read.delim(known_path, check.names = FALSE, stringsAsFactors = FALSE),
      error = function(e) NULL
    )
    if (!is.null(known_df) && nrow(known_df)) {
      top_motifs <- .chip_df_preview(known_df, 25L)
    }
  }
  # When -noknown is used, surface de novo motif table if present.
  if (!length(top_motifs) && file.exists(denovo_motifs)) {
    denovo_df <- tryCatch(
      utils::read.delim(denovo_motifs, header = FALSE, comment.char = "", stringsAsFactors = FALSE),
      error = function(e) NULL
    )
    if (!is.null(denovo_df) && nrow(denovo_df)) {
      top_motifs <- .chip_df_preview(denovo_df, 25L)
    }
  }

  annotate_out <- NULL
  annotate_pl <- .chip_tool_on_path(c("annotatePeaks.pl"))
  if (isTRUE(annotate) && nzchar(annotate_pl)) {
    ann_file <- file.path(out_dir, "annotatePeaks.txt")
    tryCatch({
      system2(annotate_pl, args = .chip_system2_args(bed_path, homer_g),
              stdout = ann_file, stderr = log_file)
      if (file.exists(ann_file) && file.info(ann_file)$size > 0) {
        ann_df <- tryCatch(
          utils::read.delim(ann_file, check.names = FALSE, stringsAsFactors = FALSE),
          error = function(e) NULL
        )
        annotate_out <- list(
          path = ann_file,
          preview = if (!is.null(ann_df)) .chip_df_preview(ann_df, 20L) else list(),
          n = if (!is.null(ann_df)) nrow(ann_df) else NULL
        )
      }
    }, error = function(e) NULL)
  }

  log_txt <- tryCatch(paste(readLines(log_file, warn = FALSE), collapse = "\n"), error = function(e) "")
  # HOMER often exits 0 while only printing Usage when argv was mis-parsed
  # (e.g. unquoted path with spaces → "Genome = Support/..." nonsense).
  usage_only <- grepl("Program will find de novo and known motifs", log_txt, fixed = TRUE) &&
    grepl("Usage:\\s*findMotifsGenome\\.pl", log_txt) &&
    !file.exists(known_path)
  bad_genome_parse <- grepl("Genome\\s*=\\s*Support/", log_txt) ||
    grepl("not recognized!!", log_txt, fixed = TRUE)
  genome_missing <- grepl("!!!!Genome\\s+\\S+\\s+not found", log_txt) ||
    grepl("not found in .+config\\.txt", log_txt)
  ok <- file.exists(known_path) || file.exists(denovo_html) || file.exists(denovo_motifs) || (length(top_motifs) > 0L)
  if (!ok || usage_only || bad_genome_parse || genome_missing) {
    log_tail <- tryCatch(paste(utils::tail(strsplit(log_txt, "\n", fixed = TRUE)[[1]], 40), collapse = "\n"),
                         error = function(e) "")
    err_msg <- if (genome_missing || !.chip_homer_genome_usable(homer_g)) {
      .chip_install_hint_homer_genome(homer_g, homer_st$homer_home)
    } else {
      paste0(
        "HOMER motif 运行失败（未生成 knownResults；exit=", as.character(status), "）。",
        "这通常不是成功——HOMER 在 Usage/配置错误时仍可能返回 exit=0。",
        if (bad_genome_parse) {
          " 提示：峰路径可能含空格，参数需 shell 引号。"
        } else {
          ""
        },
        if (nzchar(log_tail)) paste0(" Log tail:\n", log_tail) else ""
      )
    }
    return(list(
      success = FALSE,
      tool = "HOMER",
      error = err_msg,
      genome = genome_ui,
      genome_homer = homer_g,
      genome_input = g_in,
      genomes_installed = homer_st$genomes_installed,
      genomes_on_disk = homer_st$genomes_on_disk,
      command = cmd,
      output_dir = motif_dir,
      log_file = log_file,
      exit_status = status
    ))
  }

  html_path <- file.path(motif_dir, "homerResults.html")
  list(
    success = TRUE,
    tool = "HOMER",
    n_peaks = bed_info$n,
    genome = genome_ui,
    genome_homer = homer_g,
    genome_input = g_in,
    size = size,
    motif_length = motif_length,
    peak_file = peak_path,
    bed_file = bed_path,
    output_dir = motif_dir,
    known_results = known_path,
    homer_results_html = if (file.exists(html_path)) html_path else NULL,
    top_motifs = top_motifs,
    n_known_motifs = if (!is.null(known_df)) nrow(known_df) else 0L,
    annotate = annotate_out,
    command = cmd,
    log_file = log_file,
    exit_status = status
  )
}

#' DiffBind differential binding from manifest BAM groups + peaks.
chip_diffbind <- function(session_id,
                          peak_file = NULL,
                          genome = NULL,
                          fdr = 0.05,
                          top_n = 200L,
                          method = "DESeq2",
                          summit_size = 200L) {
  session_id <- chip_require_session(session_id)
  .chip_ensure_local_r_libs()
  if (!suppressWarnings(requireNamespace("DiffBind", quietly = TRUE))) {
    return(list(success = FALSE, tool = "DiffBind", error = .chip_install_hint_diffbind()))
  }

  resolved <- .chip_resolve_peaks(session_id, peak_file)
  peak_path <- resolved$path
  if (!nzchar(peak_path) || !file.exists(peak_path)) {
    return(list(
      success = FALSE,
      error = .chip_missing_peaks_error()
    ))
  }

  bams <- .chip_manifest_bams(session_id)
  t_bams <- bams$treatment
  c_bams <- bams$control
  if (length(t_bams) < 2L || length(c_bams) < 2L) {
    return(list(
      success = FALSE,
      tool = "DiffBind",
      error = sprintf(
        paste0(
          "DiffBind needs ≥2 treatment and ≥2 control BAMs (got treatment=%d, control=%d). ",
          "在 ChIP-seq 页上传 BAM 并设置 treatment/control 分组。 / ",
          "Upload BAMs on the ChIP-seq page and assign groups."
        ),
        length(t_bams), length(c_bams)
      ),
      n_treatment = length(t_bams),
      n_control = length(c_bams)
    ))
  }

  out_dir <- chip_run_dir(session_id, paste0("diffbind_", format(Sys.time(), "%H%M%S")))
  # Stage under a space-free work dir — DiffBind peak IO is fragile with spaces
  # (e.g. ".../Application Support/...").
  work_root <- file.path(tempdir(), paste0("emp_diffbind_", gsub("[^A-Za-z0-9_-]", "", session_id), "_", format(Sys.time(), "%H%M%S")))
  if (grepl("[[:space:]]", work_root)) {
    work_root <- file.path("/tmp", paste0("emp_diffbind_", gsub("[^A-Za-z0-9_-]", "", session_id), "_", as.integer(Sys.time())))
  }
  dir.create(work_root, recursive = TRUE, showWarnings = FALSE)
  bed_path <- file.path(work_root, "consensus_peaks.bed")
  # IMPORTANT (DiffBind 3.16): do NOT pre-expand to summit±N windows.
  # Wide intervals make dba(sampleSheet=...) fail with
  # "missing value where TRUE/FALSE needed". Keep 1-bp / narrow peaks and let
  # dba.count() re-center summits (same as the working CLI smoke test).
  bed_info <- tryCatch(
    .chip_peaks_to_bed(peak_path, bed_path, max_peaks = 100000L),
    error = function(e) list(error = conditionMessage(e))
  )
  if (!is.null(bed_info$error)) return(list(success = FALSE, error = bed_info$error))
  # DiffBind 3.16: BED with score column all-zeros triggers
  # "missing value where TRUE/FALSE needed" inside dba(). Use BED3 only.
  tryCatch({
    bed_df <- utils::read.table(bed_path, header = FALSE, sep = "\t", quote = "",
                                comment.char = "", stringsAsFactors = FALSE,
                                colClasses = "character")
    if (ncol(bed_df) >= 3L) {
      utils::write.table(
        bed_df[, 1:3, drop = FALSE], bed_path,
        sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE
      )
    }
  }, error = function(e) NULL)
  # Audit copy into session out_dir
  tryCatch(file.copy(bed_path, file.path(out_dir, "consensus_peaks.bed"), overwrite = TRUE), error = function(e) NULL)

  # Build sample sheet (one peak set shared — education-friendly consensus).
  # Match CLI-proven 2x2 layout (treatment vs control, ≥2 reps each).
  rows <- list()
  for (i in seq_along(t_bams)) {
    rows[[length(rows) + 1L]] <- data.frame(
      SampleID = paste0("T", i),
      bamReads = t_bams[[i]],
      Peaks = bed_path,
      PeakCaller = "bed",
      Condition = "Treatment",
      Replicate = i,
      stringsAsFactors = FALSE
    )
  }
  for (i in seq_along(c_bams)) {
    rows[[length(rows) + 1L]] <- data.frame(
      SampleID = paste0("C", i),
      bamReads = c_bams[[i]],
      Peaks = bed_path,
      PeakCaller = "bed",
      Condition = "Control",
      Replicate = i,
      stringsAsFactors = FALSE
    )
  }
  sheet <- do.call(rbind, rows)
  sheet_path <- file.path(work_root, "diffbind_samplesheet.csv")
  utils::write.csv(sheet, sheet_path, row.names = FALSE)
  tryCatch(file.copy(sheet_path, file.path(out_dir, "diffbind_samplesheet.csv"), overwrite = TRUE), error = function(e) NULL)

  fdr <- suppressWarnings(as.numeric(fdr %||% 0.05))[1]
  if (!is.finite(fdr) || fdr <= 0 || fdr > 1) fdr <- 0.05
  top_n <- suppressWarnings(as.integer(top_n %||% 200L))[1]
  if (!is.finite(top_n) || top_n < 10L) top_n <- 200L
  method <- .chip_form_scalar(method) %||% "DESeq2"
  dba_method <- if (identical(toupper(method), "EDGER")) DiffBind::DBA_EDGER else DiffBind::DBA_DESEQ2

  run <- tryCatch({
    dba_obj <- DiffBind::dba(sampleSheet = sheet_path)
    # CLI-proven options (paired-end Cut&Run / ChIP BAMs).
    dba_obj <- DiffBind::dba.count(
      dba_obj,
      bUseSummarizeOverlaps = TRUE,
      score = DiffBind::DBA_SCORE_READS
    )
    dba_obj <- DiffBind::dba.contrast(dba_obj, categories = DiffBind::DBA_CONDITION, minMembers = 2L)
    dba_obj <- DiffBind::dba.analyze(dba_obj, method = dba_method)
    list(
      dba = dba_obj,
      report = DiffBind::dba.report(dba_obj, method = dba_method, th = 1),
      error = NULL
    )
  }, error = function(e) list(dba = NULL, report = NULL, error = conditionMessage(e)))

  if (!is.null(run$error)) {
    return(list(
      success = FALSE,
      tool = "DiffBind",
      error = paste0("DiffBind failed: ", run$error),
      samplesheet = sheet_path,
      output_dir = out_dir
    ))
  }

  dba <- run$dba
  report <- run$report
  rdf <- tryCatch({
    if (inherits(report, "GRanges")) {
      as.data.frame(report)
    } else if (is.data.frame(report)) {
      report
    } else {
      as.data.frame(report)
    }
  }, error = function(e) NULL)

  if (is.null(rdf) || !nrow(rdf)) {
    return(list(
      success = FALSE,
      tool = "DiffBind",
      error = "DiffBind produced an empty report.",
      samplesheet = sheet_path,
      output_dir = out_dir
    ))
  }

  # Standardize FDR / Fold columns when present.
  fdr_col <- intersect(c("FDR", "padj", "p.adjust", "AdjP"), names(rdf))[1]
  fold_col <- intersect(c("Fold", "log2FoldChange", "Conc_Treatment", "FoldChange"), names(rdf))[1]
  if (!is.na(fdr_col) && fdr_col %in% names(rdf)) {
    rdf <- rdf[order(suppressWarnings(as.numeric(rdf[[fdr_col]]))), , drop = FALSE]
  }

  n_db <- if (!is.na(fdr_col)) {
    sum(suppressWarnings(as.numeric(rdf[[fdr_col]])) < fdr, na.rm = TRUE)
  } else {
    NA_integer_
  }

  report_csv <- file.path(out_dir, "diffbind_report.csv")
  utils::write.csv(rdf, report_csv, row.names = FALSE)

  plots <- list()
  # MA plot
  ma_png <- file.path(out_dir, "diffbind_ma.png")
  tryCatch({
    grDevices::png(ma_png, width = 900, height = 700, res = 120)
    DiffBind::dba.plotMA(dba, th = fdr)
    grDevices::dev.off()
    b64 <- .chip_file_to_base64(ma_png)
    if (!is.null(b64)) plots$ma <- b64
  }, error = function(e) {
    if (grDevices::dev.cur() > 1) try(grDevices::dev.off(), silent = TRUE)
  })

  # Volcano-like from report if Fold + FDR exist
  if (!is.na(fdr_col) && !is.na(fold_col) && requireNamespace("ggplot2", quietly = TRUE)) {
    vol_png <- file.path(out_dir, "diffbind_volcano.png")
    tryCatch({
      plot_df <- data.frame(
        Fold = suppressWarnings(as.numeric(rdf[[fold_col]])),
        FDR = suppressWarnings(as.numeric(rdf[[fdr_col]])),
        stringsAsFactors = FALSE
      )
      plot_df <- plot_df[is.finite(plot_df$Fold) & is.finite(plot_df$FDR) & plot_df$FDR > 0, , drop = FALSE]
      if (nrow(plot_df)) {
        plot_df$neglog10FDR <- -log10(pmax(plot_df$FDR, 1e-300))
        plot_df$sig <- plot_df$FDR < fdr
        p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = Fold, y = neglog10FDR, color = sig)) +
          ggplot2::geom_point(alpha = 0.55, size = 1.4) +
          ggplot2::scale_color_manual(values = c(`FALSE` = "#94a3b8", `TRUE` = "#dc2626")) +
          ggplot2::labs(title = "DiffBind volcano", x = fold_col, y = "-log10(FDR)", color = "DB") +
          ggplot2::theme_bw(base_size = 12)
        ggplot2::ggsave(vol_png, p, width = 7, height = 5.5, dpi = 140)
        b64 <- .chip_file_to_base64(vol_png)
        if (!is.null(b64)) plots$volcano <- b64
      }
    }, error = function(e) NULL)
  }

  list(
    success = TRUE,
    tool = "DiffBind",
    n_peaks_input = bed_info$n,
    n_sites_tested = nrow(rdf),
    n_db = as.integer(n_db),
    fdr_threshold = fdr,
    method = method,
    summit_size = NA_integer_,
    peaks_expanded = 0L,
    n_treatment = length(t_bams),
    n_control = length(c_bams),
    samplesheet = sheet_path,
    report_csv = report_csv,
    output_dir = out_dir,
    peak_file = peak_path,
    top_sites = .chip_df_preview(rdf, top_n),
    plots = plots,
    summary = list(
      n_db = as.integer(n_db),
      n_not_db = if (!is.na(n_db)) as.integer(nrow(rdf) - n_db) else NA_integer_,
      n_total = nrow(rdf)
    )
  )
}

.chip_deeptools_bins <- function() {
  list(
    bamCoverage = .chip_tool_on_path(c("bamCoverage")),
    computeMatrix = .chip_tool_on_path(c("computeMatrix")),
    plotHeatmap = .chip_tool_on_path(c("plotHeatmap")),
    multiBamSummary = .chip_tool_on_path(c("multiBamSummary")),
    plotCorrelation = .chip_tool_on_path(c("plotCorrelation"))
  )
}

#' deepTools coverage / heatmap / correlation wrappers.
chip_deeptools <- function(session_id,
                           mode = c("coverage", "heatmap", "corr"),
                           peak_file = NULL,
                           genome = NULL,
                           bin_size = 50L,
                           before_region = 1000L,
                           after_region = 1000L,
                           normalize_using = "RPKM") {
  session_id <- chip_require_session(session_id)
  mode <- tolower(.chip_form_scalar(mode) %||% "heatmap")
  if (!mode %in% c("coverage", "heatmap", "corr")) {
    return(list(success = FALSE, error = "mode must be coverage|heatmap|corr"))
  }

  bins <- .chip_deeptools_bins()
  if (identical(mode, "coverage") && !nzchar(bins$bamCoverage)) {
    return(list(success = FALSE, tool = "deepTools", error = .chip_install_hint_deeptools("bamCoverage")))
  }
  if (identical(mode, "corr")) {
    need <- c("multiBamSummary", "plotCorrelation")
    miss <- need[!vapply(bins[need], nzchar, logical(1))]
    if (length(miss)) {
      return(list(success = FALSE, tool = "deepTools", error = .chip_install_hint_deeptools(miss)))
    }
  }
  if (identical(mode, "heatmap")) {
    need <- c("bamCoverage", "computeMatrix", "plotHeatmap")
    miss <- need[!vapply(bins[need], nzchar, logical(1))]
    if (length(miss)) {
      return(list(success = FALSE, tool = "deepTools", error = .chip_install_hint_deeptools(miss)))
    }
  }

  bams <- .chip_manifest_bams(session_id)
  all_bams <- unique(c(bams$treatment, bams$control))
  if (!length(all_bams)) {
    return(list(
      success = FALSE,
      tool = "deepTools",
      error = "No BAM files in session manifest. Upload/register BAMs on ChIP-seq page. / 会话中无 BAM。"
    ))
  }

  out_dir <- chip_run_dir(session_id, paste0("deeptools_", mode, "_", format(Sys.time(), "%H%M%S")))
  bin_size <- suppressWarnings(as.integer(bin_size %||% 50L))[1]
  if (!is.finite(bin_size) || bin_size < 10L) bin_size <- 50L
  before_region <- suppressWarnings(as.integer(before_region %||% 1000L))[1]
  after_region <- suppressWarnings(as.integer(after_region %||% 1000L))[1]
  normalize_using <- .chip_form_scalar(normalize_using) %||% "RPKM"

  if (identical(mode, "coverage")) {
    bw_files <- character(0)
    logs <- character(0)
    # Education/smoke: large multi-GB BAMs — floor bin size so coverage cannot OOM plumber.
    cov_bin <- max(as.integer(bin_size), if (length(all_bams) >= 3L) 1000L else 200L)
    for (bam in all_bams) {
      stem <- tools::file_path_sans_ext(basename(bam))
      bw <- file.path(out_dir, paste0(stem, ".bw"))
      cov <- .chip_bamcoverage_to_bw(
        bam, bw, bins$bamCoverage,
        bin_size = cov_bin, normalize_using = normalize_using
      )
      if (isTRUE(cov$success) && nzchar(cov$path %||% "") && file.exists(cov$path)) {
        bw_files <- c(bw_files, cov$path)
      } else {
        logs <- c(logs, cov$error %||% cov$log %||% paste("bamCoverage failed for", basename(bam)))
      }
      # Release peak RAM between BAMs (plumber is single-process).
      suppressWarnings(gc(verbose = FALSE))
    }
    if (!length(bw_files)) {
      return(list(
        success = FALSE,
        tool = "deepTools",
        error = paste0(
          "bamCoverage 未能生成覆盖度文件 / produced no output. ",
          paste(utils::head(logs, 3), collapse = " | ")
        ),
        output_dir = out_dir,
        bigwig_files = character(0)
      ))
    }
    return(list(
      success = TRUE,
      tool = "deepTools",
      mode = "coverage",
      n_bams = length(all_bams),
      coverage_files = bw_files,
      bigwig_files = bw_files,
      output_dir = out_dir,
      bin_size = cov_bin,
      normalize_using = normalize_using,
      command_hint = "bamCoverage -b <bam> -o <bw> --binSize ... --normalizeUsing RPKM -p 1"
    ))
  }

  if (identical(mode, "corr")) {
    if (length(all_bams) < 2L) {
      return(list(
        success = FALSE,
        error = "Correlation needs ≥2 BAM files. / 相关性分析至少需要 2 个 BAM。"
      ))
    }
    for (bam in all_bams) {
      idx <- .chip_ensure_bam_index(bam)
      if (!isTRUE(idx$success)) {
        return(list(
          success = FALSE,
          tool = "deepTools",
          error = idx$error %||% paste0("BAM index missing: ", basename(bam)),
          output_dir = out_dir
        ))
      }
    }
    npz <- file.path(out_dir, "multiBamSummary.npz")
    # args as vector — Application Support paths with spaces stay intact.
    args_sum <- c("bins", "--bamfiles", all_bams, "-o", npz, "--binSize", as.character(max(bin_size, 10000L)))
    st <- .chip_system2(bins$multiBamSummary, args = args_sum, stdout = TRUE, stderr = TRUE)
    if (inherits(st, "error") || (!is.null(attr(st, "status")) && attr(st, "status") != 0) || !file.exists(npz)) {
      msg <- if (inherits(st, "error")) conditionMessage(st) else paste(st, collapse = "\n")
      return(list(success = FALSE, tool = "deepTools", error = paste0("multiBamSummary failed: ", msg), output_dir = out_dir))
    }
    corr_png <- file.path(out_dir, "plotCorrelation.png")
    labels <- tools::file_path_sans_ext(basename(all_bams))
    args_corr <- c(
      "-in", npz, "--corMethod", "spearman", "--whatToPlot", "heatmap",
      "-o", corr_png, "--plotNumbers", "--labels", labels
    )
    st2 <- .chip_system2(bins$plotCorrelation, args = args_corr, stdout = TRUE, stderr = TRUE)
    plots <- list()
    if (file.exists(corr_png)) {
      b64 <- .chip_file_to_base64(corr_png)
      if (!is.null(b64)) plots$correlation <- b64
    } else {
      msg <- if (inherits(st2, "error")) conditionMessage(st2) else paste(st2, collapse = "\n")
      return(list(success = FALSE, tool = "deepTools", error = paste0("plotCorrelation failed: ", msg), output_dir = out_dir))
    }
    return(list(
      success = TRUE,
      tool = "deepTools",
      mode = "corr",
      n_bams = length(all_bams),
      npz = npz,
      plot_path = corr_png,
      plots = plots,
      output_dir = out_dir,
      bam_labels = labels
    ))
  }

  # heatmap
  resolved <- .chip_resolve_peaks(session_id, peak_file)
  peak_path <- resolved$path
  if (!nzchar(peak_path) || !file.exists(peak_path)) {
    return(list(
      success = FALSE,
      error = .chip_missing_peaks_error()
    ))
  }
  bed_path <- file.path(out_dir, "peaks_for_matrix.bed")
  bed_info <- tryCatch(
    .chip_peaks_to_bed(peak_path, bed_path, max_peaks = 5000L),
    error = function(e) list(error = conditionMessage(e))
  )
  if (!is.null(bed_info$error)) return(list(success = FALSE, error = bed_info$error))

  # Build bigWigs for treatment BAMs (cap at 4 for education runtime).
  # Write into session run dir; ensure .bai first (bamCoverage requires index).
  use_bams <- utils::head(if (length(bams$treatment)) bams$treatment else all_bams, 4L)
  bw_files <- character(0)
  bw_logs <- character(0)
  for (bam in use_bams) {
    stem <- tools::file_path_sans_ext(basename(bam))
    bw <- file.path(out_dir, paste0(stem, ".bw"))
    cov <- .chip_bamcoverage_to_bw(
      bam, bw, bins$bamCoverage,
      bin_size = bin_size, normalize_using = normalize_using
    )
    if (isTRUE(cov$success) && identical(cov$format %||% "bigwig", "bigwig") &&
        nzchar(cov$path %||% "") && file.exists(cov$path)) {
      bw_files <- c(bw_files, cov$path)
    } else if (isTRUE(cov$success) && identical(cov$format, "bedgraph")) {
      bw_logs <- c(bw_logs, paste0(
        basename(bam), ": only bedGraph available (computeMatrix needs bigWig). ",
        cov$warning %||% cov$log %||% ""
      ))
    } else {
      bw_logs <- c(bw_logs, cov$error %||% cov$log %||% paste("bamCoverage failed:", basename(bam)))
    }
  }
  if (!length(bw_files)) {
    detail <- if (length(bw_logs)) paste(utils::head(bw_logs, 4), collapse = " || ") else "unknown error"
    return(list(
      success = FALSE,
      tool = "deepTools",
      error = paste0(
        "bamCoverage 未能生成 bigWig（computeMatrix 需要）/ failed to create bigWig inputs for computeMatrix. ",
        detail
      ),
      output_dir = out_dir,
      bigwig_files = character(0),
      bamcoverage_log = bw_logs
    ))
  }

  matrix_gz <- file.path(out_dir, "matrix.gz")
  # Character-vector args keep spaces in Application Support paths intact.
  args_m <- c(
    "reference-point", "--referencePoint", "center",
    "-S", bw_files, "-R", bed_path,
    "-a", as.character(after_region), "-b", as.character(before_region),
    "-o", matrix_gz, "--skipZeros"
  )
  st_m <- .chip_system2(bins$computeMatrix, args = args_m, stdout = TRUE, stderr = TRUE)
  if (inherits(st_m, "error") || !file.exists(matrix_gz)) {
    msg <- if (inherits(st_m, "error")) conditionMessage(st_m) else paste(st_m, collapse = "\n")
    return(list(success = FALSE, tool = "deepTools", error = paste0("computeMatrix failed: ", msg), output_dir = out_dir))
  }

  heat_png <- file.path(out_dir, "plotHeatmap.png")
  args_h <- c("-m", matrix_gz, "-o", heat_png, "--dpi", "150")
  st_h <- .chip_system2(bins$plotHeatmap, args = args_h, stdout = TRUE, stderr = TRUE)
  plots <- list()
  if (file.exists(heat_png)) {
    b64 <- .chip_file_to_base64(heat_png)
    if (!is.null(b64)) plots$heatmap <- b64
  } else {
    msg <- if (inherits(st_h, "error")) conditionMessage(st_h) else paste(st_h, collapse = "\n")
    return(list(success = FALSE, tool = "deepTools", error = paste0("plotHeatmap failed: ", msg), output_dir = out_dir))
  }

  list(
    success = TRUE,
    tool = "deepTools",
    mode = "heatmap",
    n_peaks = bed_info$n,
    n_bigwigs = length(bw_files),
    bigwig_files = bw_files,
    peak_file = peak_path,
    bed_file = bed_path,
    matrix = matrix_gz,
    plot_path = heat_png,
    plots = plots,
    output_dir = out_dir,
    before_region = before_region,
    after_region = after_region
  )
}

chip_deeptools_coverage <- function(session_id, ...) {
  chip_deeptools(session_id, mode = "coverage", ...)
}
chip_deeptools_heatmap <- function(session_id, ...) {
  chip_deeptools(session_id, mode = "heatmap", ...)
}
chip_deeptools_corr <- function(session_id, ...) {
  chip_deeptools(session_id, mode = "corr", ...)
}

# ── Peak set ops (GenomicRanges; no bedtools) ───────────────────────

.chip_require_genomicranges <- function() {
  if (!requireNamespace("GenomicRanges", quietly = TRUE) ||
      !requireNamespace("IRanges", quietly = TRUE) ||
      !requireNamespace("S4Vectors", quietly = TRUE)) {
    stop(paste(
      "GenomicRanges / IRanges / S4Vectors are required for peak set operations.",
      'Install: BiocManager::install(c("GenomicRanges","IRanges","S4Vectors"))'
    ))
  }
  invisible(TRUE)
}

.chip_webapp_data_dir <- function() {
  # Prefer webapp/data (plumber usually runs with cwd = webapp/backend).
  candidates <- c(
    file.path(getwd(), "..", "data"),
    file.path(getwd(), "data"),
    file.path(Sys.getenv("EMP_WEBAPP_ROOT", unset = ""), "data"),
    file.path(dirname(getwd()), "data")
  )
  for (d in candidates) {
    if (!nzchar(as.character(d)[1])) next
    d <- suppressWarnings(normalizePath(d, winslash = "/", mustWork = FALSE))
    if (nzchar(d) && dir.exists(d)) return(d)
  }
  d <- normalizePath(file.path(getwd(), "..", "data"), winslash = "/", mustWork = FALSE)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

.chip_blacklist_dir <- function() {
  d <- file.path(.chip_webapp_data_dir(), "blacklists")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

.chip_assembly_from_genome <- function(genome = "hs") {
  g <- tolower(trimws(as.character(genome %||% "hs")[1]))
  if (g %in% c("mm", "mu", "m", "mm10", "mouse")) return("mm10")
  if (identical(g, "mm39")) return("mm10") # use mm10 blacklist as closest
  if (g %in% c("hg19", "grch37")) return("hg19")
  if (g %in% c("hg38", "grch38", "hs", "human", "h", "hg18", "ncbi36")) return("hg38")
  "hg38"
}

.chip_df_to_gr <- function(df) {
  .chip_require_genomicranges()
  if (is.null(df) || !nrow(df)) {
    return(GenomicRanges::GRanges())
  }
  chrom <- as.character(df$chrom %||% df$seqnames)
  start_raw <- suppressWarnings(as.numeric(df$start))
  end_raw <- suppressWarnings(as.numeric(df$end))
  coord <- as.character(df$coord_system %||% "")[1]
  if (identical(coord, "bed_0based")) {
    # BED 0-based half-open → 1-based inclusive IRanges
    start <- as.integer(pmax(1L, floor(start_raw) + 1L))
    end <- as.integer(pmax(start, ceiling(end_raw)))
  } else {
    # Default / ChIPseeker: already 1-based inclusive (or unknown — treat as 1-based)
    start <- as.integer(pmax(1L, floor(start_raw)))
    end <- as.integer(ceiling(end_raw))
  }
  # Expand zero-width / inverted (MACS summits often start==end in BED or after parse)
  thin <- !is.finite(end) | end < start
  end[thin] <- start[thin]
  start[!is.finite(start)] <- 1L
  end[!is.finite(end)] <- start[!is.finite(end)]
  score <- if ("score" %in% names(df)) {
    suppressWarnings(as.numeric(df$score))
  } else if ("signalValue" %in% names(df)) {
    suppressWarnings(as.numeric(df$signalValue))
  } else {
    rep(NA_real_, length(start))
  }
  name <- if ("name" %in% names(df)) as.character(df$name) else paste0("peak", seq_along(start))
  summit <- if ("peak" %in% names(df)) {
    suppressWarnings(as.numeric(df$peak))
  } else {
    rep(NA_real_, length(start))
  }
  GenomicRanges::GRanges(
    seqnames = chrom,
    ranges = IRanges::IRanges(start = start, end = end),
    score = score,
    name = name,
    summit_offset = summit
  )
}

.chip_path_to_gr <- function(path) {
  df <- .chip_read_peak_table(path)
  .chip_df_to_gr(df)
}

.chip_gr_to_bed_df <- function(gr) {
  .chip_require_genomicranges()
  if (length(gr) < 1L) {
    return(data.frame(
      chrom = character(0), start = integer(0), end = integer(0),
      name = character(0), score = numeric(0), stringsAsFactors = FALSE
    ))
  }
  mc <- tryCatch(S4Vectors::mcols(gr), error = function(e) NULL)
  score <- if (!is.null(mc) && "score" %in% names(mc)) {
    suppressWarnings(as.numeric(mc$score))
  } else {
    rep(0, length(gr))
  }
  if (length(score) != length(gr)) score <- rep(0, length(gr))
  score[!is.finite(score)] <- 0
  name <- if (!is.null(mc) && "name" %in% names(mc)) {
    as.character(mc$name)
  } else {
    paste0("peak", seq_along(gr))
  }
  if (length(name) != length(gr)) name <- paste0("peak", seq_along(gr))
  name[is.na(name) | !nzchar(name)] <- paste0("peak", which(is.na(name) | !nzchar(name)))
  data.frame(
    chrom = as.character(GenomicRanges::seqnames(gr)),
    start = as.integer(GenomicRanges::start(gr) - 1L), # write BED 0-based
    end = as.integer(GenomicRanges::end(gr)),
    name = name,
    score = score,
    stringsAsFactors = FALSE
  )
}

.chip_write_gr_bed <- function(gr, path) {
  df <- .chip_gr_to_bed_df(gr)
  utils::write.table(df, path, sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
  invisible(path)
}

.chip_resolve_peak_b <- function(session_id, peak_b = NULL, peak_file_b = NULL) {
  p <- .chip_path_scalar(peak_b) %||% .chip_path_scalar(peak_file_b)
  if (!is.null(p) && nzchar(p)) {
    if (!file.exists(p)) stop("peak_b file not found: ", p)
    return(p)
  }
  # Optional second peak registered on manifest
  manifest <- chip_load_manifest(session_id)
  alt <- .chip_path_scalar(manifest$last_peaks_b$peak_file %||% manifest$peak_b %||% "")
  if (!is.null(alt) && nzchar(alt) && file.exists(alt)) {
    return(alt)
  }
  NULL
}

.chip_download_blacklist <- function(assembly = "hg38") {
  assembly <- tolower(as.character(assembly)[1])
  bl_dir <- .chip_blacklist_dir()
  dest <- file.path(bl_dir, paste0(assembly, "-blacklist.v2.bed"))
  if (file.exists(dest) && file.info(dest)$size > 100) return(dest)

  urls <- list(
    hg38 = c(
      "https://raw.githubusercontent.com/Boyle-Lab/Blacklist/master/lists/hg38-blacklist.v2.bed.gz",
      "https://github.com/Boyle-Lab/Blacklist/raw/master/lists/hg38-blacklist.v2.bed.gz"
    ),
    hg19 = c(
      "https://raw.githubusercontent.com/Boyle-Lab/Blacklist/master/lists/hg19-blacklist.v2.bed.gz",
      "https://github.com/Boyle-Lab/Blacklist/raw/master/lists/hg19-blacklist.v2.bed.gz"
    ),
    mm10 = c(
      "https://raw.githubusercontent.com/Boyle-Lab/Blacklist/master/lists/mm10-blacklist.v2.bed.gz",
      "https://github.com/Boyle-Lab/Blacklist/raw/master/lists/mm10-blacklist.v2.bed.gz"
    )
  )
  uvec <- urls[[assembly]]
  if (is.null(uvec)) uvec <- urls$hg38
  gz_tmp <- paste0(dest, ".gz")
  ok <- FALSE
  for (u in uvec) {
    dl <- tryCatch({
      utils::download.file(u, gz_tmp, mode = "wb", quiet = TRUE, timeout = 30)
      TRUE
    }, error = function(e) FALSE, warning = function(w) FALSE)
    if (isTRUE(dl) && file.exists(gz_tmp) && file.info(gz_tmp)$size > 100) {
      ok <- TRUE
      break
    }
  }
  if (ok) {
    con <- gzfile(gz_tmp, "rt")
    on.exit(try(close(con), silent = TRUE), add = TRUE)
    lines <- readLines(con, warn = FALSE)
    writeLines(lines, dest)
    unlink(gz_tmp)
    if (file.exists(dest) && file.info(dest)$size > 100) return(dest)
  }
  # Fallback minimal embed
  fb <- file.path(bl_dir, paste0(if (assembly == "mm10") "mm10" else "hg38", "_minimal.bed"))
  if (file.exists(fb)) return(fb)
  # Write tiny inline fallback
  if (assembly == "mm10") {
    writeLines(c("chr1\t0\t10000\tEMP_fallback", "chrM\t0\t16299\tEMP_fallback_chrM"), fb)
  } else {
    writeLines(c("chr1\t0\t10000\tEMP_fallback", "chrM\t0\t16569\tEMP_fallback_chrM"), fb)
  }
  fb
}

.chip_get_txdb <- function(genome = "hs") {
  gcfg <- chip_genome_config(genome)
  pkg <- gcfg$txdb
  if (!suppressWarnings(requireNamespace(pkg, quietly = TRUE))) {
    stop(sprintf(
      "TxDb package '%s' is not installed. Install with BiocManager::install(\"%s\"). Cannot call promoters without TxDb.",
      pkg, pkg
    ))
  }
  if (!requireNamespace("GenomicFeatures", quietly = TRUE)) {
    stop('GenomicFeatures is required. Install: BiocManager::install("GenomicFeatures")')
  }
  getExportedValue(pkg, pkg)
}

.chip_promoter_gr <- function(genome = "hs", upstream = 2000L, downstream = 2000L) {
  .chip_require_genomicranges()
  txdb <- .chip_get_txdb(genome)
  upstream <- as.integer(upstream %||% 2000L)[1]
  downstream <- as.integer(downstream %||% 2000L)[1]
  if (!is.finite(upstream) || upstream < 0L) upstream <- 2000L
  if (!is.finite(downstream) || downstream < 0L) downstream <- 2000L
  GenomicFeatures::promoters(txdb, upstream = upstream, downstream = downstream)
}

.chip_jaccard_stats <- function(gr_a, gr_b) {
  .chip_require_genomicranges()
  inter <- GenomicRanges::intersect(GenomicRanges::reduce(gr_a), GenomicRanges::reduce(gr_b))
  uni <- GenomicRanges::union(GenomicRanges::reduce(gr_a), GenomicRanges::reduce(gr_b))
  inter_bp <- sum(as.numeric(GenomicRanges::width(inter)))
  uni_bp <- sum(as.numeric(GenomicRanges::width(uni)))
  a_bp <- sum(as.numeric(GenomicRanges::width(GenomicRanges::reduce(gr_a))))
  b_bp <- sum(as.numeric(GenomicRanges::width(GenomicRanges::reduce(gr_b))))
  list(
    jaccard = if (uni_bp > 0) inter_bp / uni_bp else 0,
    intersection_bp = inter_bp,
    union_bp = uni_bp,
    a_bp = a_bp,
    b_bp = b_bp,
    coverage_a = if (a_bp > 0) inter_bp / a_bp else 0,
    coverage_b = if (b_bp > 0) inter_bp / b_bp else 0
  )
}

.chip_reciprocal_overlap <- function(gr_a, gr_b, min_re = 0.5) {
  .chip_require_genomicranges()
  if (!length(gr_a) || !length(gr_b)) return(GenomicRanges::GRanges())
  hits <- GenomicRanges::findOverlaps(gr_a, gr_b)
  if (!length(hits)) return(GenomicRanges::GRanges())
  qi <- S4Vectors::queryHits(hits)
  si <- S4Vectors::subjectHits(hits)
  ov <- GenomicRanges::pintersect(gr_a[qi], gr_b[si])
  w_ov <- as.numeric(GenomicRanges::width(ov))
  w_a <- as.numeric(GenomicRanges::width(gr_a[qi]))
  w_b <- as.numeric(GenomicRanges::width(gr_b[si]))
  keep <- (w_ov / pmax(w_a, 1) >= min_re) & (w_ov / pmax(w_b, 1) >= min_re)
  if (!any(keep)) return(GenomicRanges::GRanges())
  GenomicRanges::reduce(gr_a[unique(qi[keep])])
}

.chip_rose_inflection <- function(scores) {
  scores <- sort(as.numeric(scores), decreasing = TRUE)
  scores <- scores[is.finite(scores)]
  n <- length(scores)
  if (n < 3L) return(list(cutoff_index = n, cutoff_score = if (n) scores[n] else 0))
  x <- seq_len(n)
  # Normalize to unit square; distance from diagonal
  xn <- (x - 1) / (n - 1)
  yn <- (scores - min(scores)) / max(max(scores) - min(scores), .Machine$double.eps)
  # Line from first to last
  dist <- abs((yn[n] - yn[1]) * xn - (xn[n] - xn[1]) * yn + xn[n] * yn[1] - yn[n] * xn[1]) /
    sqrt((yn[n] - yn[1])^2 + (xn[n] - xn[1])^2)
  idx <- which.max(dist)
  list(cutoff_index = as.integer(idx), cutoff_score = scores[idx])
}

.chip_ops_update_last_peaks <- function(session_id, peak_file, genome, n_peaks, source_tag) {
  reg <- .chip_register_peak_file(
    session_id = session_id,
    peak_file = peak_file,
    name = basename(peak_file),
    source = paste0("ops_", source_tag),
    genome = genome,
    assembly = .chip_assembly_from_genome(genome),
    n_peaks = n_peaks,
    run_dir = dirname(peak_file),
    format_hint = "BED",
    set_active = TRUE
  )
  invisible(reg$last_peaks)
}

#' Filter peaks against ENCODE blacklist (GenomicRanges setdiff).
chip_peaks_blacklist <- function(session_id, peak_file = NULL, genome = NULL,
                                 blacklist_file = NULL) {
  session_id <- chip_require_session(session_id)
  .chip_require_genomicranges()
  resolved <- .chip_resolve_peaks(session_id, peak_file)
  peak_path <- resolved$path
  if (!nzchar(peak_path) || !file.exists(peak_path)) {
    return(list(success = FALSE, error = .chip_missing_peaks_error()))
  }
  g_in <- .chip_form_scalar(genome) %||% resolved$genome %||% "hs"
  assembly <- .chip_assembly_from_genome(g_in)
  bl_path <- .chip_form_scalar(blacklist_file)
  bl_note <- NULL
  if (is.null(bl_path) || !nzchar(bl_path) || !file.exists(bl_path)) {
    bl_path <- tryCatch(
      .chip_download_blacklist(assembly),
      error = function(e) {
        bl_note <<- conditionMessage(e)
        .chip_download_blacklist(assembly)
      }
    )
  }
  if (grepl("_minimal\\.bed$", as.character(bl_path)[1])) {
    bl_note <- paste(
      trimws(paste(bl_note %||% "", collapse = " ")),
      "Using embedded minimal blacklist (full ENCODE download unavailable).",
      "Prefer caching hg38/mm10 Boyle-Lab blacklist under webapp/data/blacklists/."
    )
  }
  gr <- .chip_path_to_gr(peak_path)
  bl <- .chip_path_to_gr(bl_path)
  n_before <- length(gr)
  # Drop peaks overlapping blacklist
  if (length(bl) && length(gr)) {
    hits <- GenomicRanges::findOverlaps(gr, bl, ignore.strand = TRUE)
    drop_idx <- unique(S4Vectors::queryHits(hits))
    kept <- if (length(drop_idx)) gr[-drop_idx] else gr
  } else {
    kept <- gr
    drop_idx <- integer(0)
  }
  out_dir <- chip_run_dir(session_id, paste0("peaks_blacklist_", format(Sys.time(), "%H%M%S")))
  out_bed <- file.path(out_dir, "blacklist_filtered_peaks.bed")
  .chip_write_gr_bed(kept, out_bed)
  lp <- .chip_ops_update_last_peaks(session_id, out_bed, g_in, length(kept), "blacklist")
  list(
    success = TRUE,
    op = "blacklist",
    n_before = as.integer(n_before),
    n_after = as.integer(length(kept)),
    n_removed = as.integer(n_before - length(kept)),
    removed_fraction = if (n_before > 0) (n_before - length(kept)) / n_before else 0,
    blacklist_file = bl_path,
    assembly = assembly,
    note = bl_note,
    output_bed = out_bed,
    last_peaks = lp,
    preview = .chip_df_preview(.chip_gr_to_bed_df(utils::head(kept, 20L)))
  )
}

#' Sort / reduce / merge peaks within gap.
chip_peaks_merge <- function(session_id, peak_file = NULL, genome = NULL, merge_gap = 0L) {
  session_id <- chip_require_session(session_id)
  .chip_require_genomicranges()
  resolved <- .chip_resolve_peaks(session_id, peak_file)
  peak_path <- resolved$path
  if (!nzchar(peak_path) || !file.exists(peak_path)) {
    return(list(success = FALSE, error = .chip_missing_peaks_error()))
  }
  g_in <- .chip_form_scalar(genome) %||% resolved$genome %||% "hs"
  gap <- suppressWarnings(as.integer(merge_gap %||% 0L)[1])
  if (!is.finite(gap) || gap < 0L) gap <- 0L
  gr <- .chip_path_to_gr(peak_path)
  n_before <- length(gr)
  # reduce with min.gapwidth = gap+1 merges intervals within `gap` bp
  merged <- GenomicRanges::reduce(gr, min.gapwidth = as.integer(gap) + 1L, ignore.strand = TRUE)
  out_dir <- chip_run_dir(session_id, paste0("peaks_merge_", format(Sys.time(), "%H%M%S")))
  out_bed <- file.path(out_dir, "merged_peaks.bed")
  .chip_write_gr_bed(merged, out_bed)
  lp <- .chip_ops_update_last_peaks(session_id, out_bed, g_in, length(merged), "merge")
  list(
    success = TRUE,
    op = "merge",
    merge_gap = gap,
    n_before = as.integer(n_before),
    n_after = as.integer(length(merged)),
    output_bed = out_bed,
    last_peaks = lp,
    width_summary = .chip_numeric_summary(GenomicRanges::width(merged)),
    preview = .chip_df_preview(.chip_gr_to_bed_df(utils::head(merged, 20L)))
  )
}

#' Summit-centered fixed windows (center±size).
chip_peaks_summit_window <- function(session_id, peak_file = NULL, genome = NULL, summit_size = 250L) {
  session_id <- chip_require_session(session_id)
  .chip_require_genomicranges()
  resolved <- .chip_resolve_peaks(session_id, peak_file)
  peak_path <- resolved$path
  if (!nzchar(peak_path) || !file.exists(peak_path)) {
    return(list(success = FALSE, error = .chip_missing_peaks_error()))
  }
  g_in <- .chip_form_scalar(genome) %||% resolved$genome %||% "hs"
  half <- suppressWarnings(as.integer(summit_size %||% 250L)[1])
  if (!is.finite(half) || half < 10L) half <- 250L
  gr <- .chip_path_to_gr(peak_path)
  # Prefer narrowPeak summit offset; else geometric center
  off <- S4Vectors::mcols(gr)$summit_offset
  centers <- GenomicRanges::start(gr) + floor(GenomicRanges::width(gr) / 2) - 1L
  if (!is.null(off) && length(off) == length(gr)) {
    use <- is.finite(off) & off >= 0
    centers[use] <- GenomicRanges::start(gr)[use] + as.integer(off[use])
  }
  new_start <- pmax(1L, as.integer(centers - half))
  new_end <- as.integer(centers + half)
  windows <- GenomicRanges::GRanges(
    seqnames = GenomicRanges::seqnames(gr),
    ranges = IRanges::IRanges(start = new_start, end = new_end),
    score = S4Vectors::mcols(gr)$score,
    name = S4Vectors::mcols(gr)$name
  )
  out_dir <- chip_run_dir(session_id, paste0("peaks_summit_", format(Sys.time(), "%H%M%S")))
  out_bed <- file.path(out_dir, sprintf("summit_pm%dbp.bed", half))
  .chip_write_gr_bed(windows, out_bed)
  lp <- .chip_ops_update_last_peaks(session_id, out_bed, g_in, length(windows), "summit")
  list(
    success = TRUE,
    op = "summit",
    summit_size = half,
    window_bp = half * 2L,
    n_peaks = as.integer(length(windows)),
    output_bed = out_bed,
    last_peaks = lp,
    preview = .chip_df_preview(.chip_gr_to_bed_df(utils::head(windows, 20L)))
  )
}

#' Jaccard / overlap / shared-gain-loss between two peak sets.
chip_peaks_overlap <- function(session_id, peak_file = NULL, peak_b = NULL, genome = NULL,
                               min_overlap = 1L) {
  session_id <- chip_require_session(session_id)
  .chip_require_genomicranges()
  resolved <- .chip_resolve_peaks(session_id, peak_file)
  peak_path <- resolved$path
  if (!nzchar(peak_path) || !file.exists(peak_path)) {
    return(list(success = FALSE, error = .chip_missing_peaks_error()))
  }
  pb <- tryCatch(.chip_resolve_peak_b(session_id, peak_b), error = function(e) NULL)
  if (is.null(pb) || !nzchar(pb) || !file.exists(pb)) {
    return(list(
      success = FALSE,
      error = "peak_b is required (path to second peak BED). Provide peak_b in request body."
    ))
  }
  g_in <- .chip_form_scalar(genome) %||% resolved$genome %||% "hs"
  gr_a <- .chip_path_to_gr(peak_path)
  gr_b <- .chip_path_to_gr(pb)
  jac <- .chip_jaccard_stats(gr_a, gr_b)
  ov_a <- GenomicRanges::countOverlaps(gr_a, gr_b) > 0
  ov_b <- GenomicRanges::countOverlaps(gr_b, gr_a) > 0
  shared_a <- gr_a[ov_a]
  unique_a <- gr_a[!ov_a]  # loss relative to B / A-only
  unique_b <- gr_b[!ov_b]  # gain relative to A / B-only
  out_dir <- chip_run_dir(session_id, paste0("peaks_overlap_", format(Sys.time(), "%H%M%S")))
  shared_bed <- file.path(out_dir, "shared_peaks.bed")
  gain_bed <- file.path(out_dir, "gain_B_only.bed")
  loss_bed <- file.path(out_dir, "loss_A_only.bed")
  .chip_write_gr_bed(GenomicRanges::reduce(shared_a), shared_bed)
  .chip_write_gr_bed(unique_b, gain_bed)
  .chip_write_gr_bed(unique_a, loss_bed)
  list(
    success = TRUE,
    op = "overlap",
    peak_a = peak_path,
    peak_b = pb,
    n_a = as.integer(length(gr_a)),
    n_b = as.integer(length(gr_b)),
    n_shared_a = as.integer(sum(ov_a)),
    n_unique_a = as.integer(sum(!ov_a)),
    n_unique_b = as.integer(sum(!ov_b)),
    jaccard = jac$jaccard,
    coverage_a = jac$coverage_a,
    coverage_b = jac$coverage_b,
    intersection_bp = jac$intersection_bp,
    files = list(shared = shared_bed, gain = gain_bed, loss = loss_bed),
    output_dir = out_dir,
    counts = list(
      shared = as.integer(sum(ov_a)),
      gain = as.integer(sum(!ov_b)),
      loss = as.integer(sum(!ov_a)),
      unique_a = as.integer(sum(!ov_a)),
      unique_b = as.integer(sum(!ov_b))
    )
  )
}

#' IDR approximation via stringent reciprocal overlap of two peak files.
chip_idr_approx <- function(session_id, peak_file = NULL, peak_b = NULL, genome = NULL,
                            min_re = 0.5) {
  session_id <- chip_require_session(session_id)
  .chip_require_genomicranges()
  resolved <- .chip_resolve_peaks(session_id, peak_file)
  peak_path <- resolved$path
  if (!nzchar(peak_path) || !file.exists(peak_path)) {
    return(list(success = FALSE, error = .chip_missing_peaks_error()))
  }
  pb <- tryCatch(.chip_resolve_peak_b(session_id, peak_b), error = function(e) NULL)
  if (is.null(pb) || !file.exists(pb)) {
    return(list(success = FALSE, error = "peak_b (replicate 2) is required for IDR approximation."))
  }
  g_in <- .chip_form_scalar(genome) %||% resolved$genome %||% "hs"
  min_re <- suppressWarnings(as.numeric(min_re %||% 0.5)[1])
  if (!is.finite(min_re) || min_re <= 0 || min_re > 1) min_re <- 0.5
  gr_a <- .chip_path_to_gr(peak_path)
  gr_b <- .chip_path_to_gr(pb)
  kept <- .chip_reciprocal_overlap(gr_a, gr_b, min_re = min_re)
  out_dir <- chip_run_dir(session_id, paste0("idr_approx_", format(Sys.time(), "%H%M%S")))
  out_bed <- file.path(out_dir, "idr_approx_peaks.bed")
  .chip_write_gr_bed(kept, out_bed)
  lp <- .chip_ops_update_last_peaks(session_id, out_bed, g_in, length(kept), "idr_approx")
  list(
    success = TRUE,
    op = "idr",
    note = paste(
      "IDR近似 / approximation: stringent reciprocal overlap (≥",
      min_re, ") between two peak sets — NOT the official IDR statistical model.",
      "Use ENCODE idr tool for publication-grade IDR."
    ),
    min_reciprocal_overlap = min_re,
    n_a = as.integer(length(gr_a)),
    n_b = as.integer(length(gr_b)),
    n_kept = as.integer(length(kept)),
    output_bed = out_bed,
    last_peaks = lp,
    peak_a = peak_path,
    peak_b = pb,
    preview = .chip_df_preview(.chip_gr_to_bed_df(utils::head(kept, 20L)))
  )
}

#' Promoter-candidate peaks (TxDb promoters ± window).
chip_promoter_call <- function(session_id, peak_file = NULL, genome = NULL,
                               promoter_window = 2000L) {
  session_id <- chip_require_session(session_id)
  .chip_require_genomicranges()
  resolved <- .chip_resolve_peaks(session_id, peak_file)
  peak_path <- resolved$path
  if (!nzchar(peak_path) || !file.exists(peak_path)) {
    return(list(success = FALSE, error = .chip_missing_peaks_error()))
  }
  g_in <- .chip_form_scalar(genome) %||% resolved$genome %||% "hs"
  win <- suppressWarnings(as.integer(promoter_window %||% 2000L)[1])
  if (!is.finite(win) || win < 100L) win <- 2000L
  prom <- tryCatch(
    .chip_promoter_gr(g_in, upstream = win, downstream = win),
    error = function(e) e
  )
  if (inherits(prom, "error")) {
    return(list(success = FALSE, error = conditionMessage(prom), op = "promoter"))
  }
  gr <- .chip_path_to_gr(peak_path)
  keep <- GenomicRanges::countOverlaps(gr, prom, ignore.strand = TRUE) > 0
  promo_peaks <- gr[keep]
  out_dir <- chip_run_dir(session_id, paste0("promoter_call_", format(Sys.time(), "%H%M%S")))
  out_bed <- file.path(out_dir, "promoter_candidate_peaks.bed")
  .chip_write_gr_bed(promo_peaks, out_bed)
  lp <- .chip_ops_update_last_peaks(session_id, out_bed, g_in, length(promo_peaks), "promoter")
  list(
    success = TRUE,
    op = "promoter",
    promoter_window = win,
    n_peaks = as.integer(length(gr)),
    n_promoter = as.integer(length(promo_peaks)),
    fraction = if (length(gr)) length(promo_peaks) / length(gr) else 0,
    output_bed = out_bed,
    last_peaks = lp,
    txdb = chip_genome_config(g_in)$txdb,
    preview = .chip_df_preview(.chip_gr_to_bed_df(utils::head(promo_peaks, 20L)))
  )
}

#' Distal non-promoter peaks as enhancer candidates + distance bins.
chip_enhancer_call <- function(session_id, peak_file = NULL, genome = NULL,
                               promoter_window = 2000L) {
  session_id <- chip_require_session(session_id)
  .chip_require_genomicranges()
  resolved <- .chip_resolve_peaks(session_id, peak_file)
  peak_path <- resolved$path
  if (!nzchar(peak_path) || !file.exists(peak_path)) {
    return(list(success = FALSE, error = .chip_missing_peaks_error()))
  }
  g_in <- .chip_form_scalar(genome) %||% resolved$genome %||% "hs"
  win <- suppressWarnings(as.integer(promoter_window %||% 2000L)[1])
  if (!is.finite(win) || win < 100L) win <- 2000L
  prom <- tryCatch(
    .chip_promoter_gr(g_in, upstream = win, downstream = win),
    error = function(e) e
  )
  if (inherits(prom, "error")) {
    return(list(success = FALSE, error = conditionMessage(prom), op = "enhancer"))
  }
  gr <- .chip_path_to_gr(peak_path)
  is_promo <- GenomicRanges::countOverlaps(gr, prom, ignore.strand = TRUE) > 0
  enh <- gr[!is_promo]
  # Distance to nearest promoter
  d <- if (length(enh) && length(prom)) {
    dn <- GenomicRanges::distanceToNearest(enh, prom, ignore.strand = TRUE)
    as.numeric(S4Vectors::mcols(dn)$distance)
  } else {
    numeric(0)
  }
  bins <- cut(
    d,
    breaks = c(-Inf, 5000, 20000, 50000, 100000, Inf),
    labels = c("0-5kb", "5-20kb", "20-50kb", "50-100kb", ">100kb"),
    right = TRUE
  )
  bin_tab <- as.list(table(bins))
  out_dir <- chip_run_dir(session_id, paste0("enhancer_call_", format(Sys.time(), "%H%M%S")))
  out_bed <- file.path(out_dir, "enhancer_candidate_peaks.bed")
  .chip_write_gr_bed(enh, out_bed)
  if (length(enh) && length(d)) {
    utils::write.csv(
      data.frame(
        chrom = as.character(GenomicRanges::seqnames(enh)),
        start = GenomicRanges::start(enh),
        end = GenomicRanges::end(enh),
        distance_to_promoter = d,
        distance_bin = as.character(bins),
        stringsAsFactors = FALSE
      ),
      file.path(out_dir, "enhancer_distance_bins.csv"),
      row.names = FALSE
    )
  }
  lp <- .chip_ops_update_last_peaks(session_id, out_bed, g_in, length(enh), "enhancer")
  list(
    success = TRUE,
    op = "enhancer",
    promoter_window = win,
    n_peaks = as.integer(length(gr)),
    n_promoter = as.integer(sum(is_promo)),
    n_enhancer = as.integer(length(enh)),
    distance_bins = bin_tab,
    output_bed = out_bed,
    distance_csv = file.path(out_dir, "enhancer_distance_bins.csv"),
    last_peaks = lp,
    preview = .chip_df_preview(.chip_gr_to_bed_df(utils::head(enh, 20L)))
  )
}

#' ROSE-style super-enhancer: stitch (gap 12.5kb) + score rank + inflection.
chip_super_enhancer <- function(session_id, peak_file = NULL, genome = NULL,
                                stitch_gap = 12500L, promoter_window = 2000L,
                                exclude_promoter = TRUE) {
  session_id <- chip_require_session(session_id)
  .chip_require_genomicranges()
  resolved <- .chip_resolve_peaks(session_id, peak_file)
  peak_path <- resolved$path
  if (!nzchar(peak_path) || !file.exists(peak_path)) {
    return(list(success = FALSE, error = .chip_missing_peaks_error()))
  }
  g_in <- .chip_form_scalar(genome) %||% resolved$genome %||% "hs"
  gap <- suppressWarnings(as.integer(stitch_gap %||% 12500L)[1])
  if (!is.finite(gap) || gap < 0L) gap <- 12500L
  win <- suppressWarnings(as.integer(promoter_window %||% 2000L)[1])
  if (!is.finite(win) || win < 100L) win <- 2000L
  gr <- .chip_path_to_gr(peak_path)
  note_txdb <- NULL
  if (isTRUE(exclude_promoter)) {
    prom <- tryCatch(.chip_promoter_gr(g_in, upstream = win, downstream = win), error = function(e) e)
    if (inherits(prom, "error")) {
      note_txdb <- paste("Promoter exclusion skipped:", conditionMessage(prom))
    } else {
      gr <- gr[GenomicRanges::countOverlaps(gr, prom, ignore.strand = TRUE) == 0]
    }
  }
  if (!length(gr)) {
    return(list(success = FALSE, error = "No peaks left after promoter exclusion.", op = "super_enhancer"))
  }
  # Stitch
  stitched <- GenomicRanges::reduce(gr, min.gapwidth = gap + 1L, ignore.strand = TRUE)
  # Score = sum of overlapping peak scores (or width if no score)
  hits <- GenomicRanges::findOverlaps(stitched, gr)
  scores <- numeric(length(stitched))
  pk_score <- S4Vectors::mcols(gr)$score
  if (is.null(pk_score) || !any(is.finite(pk_score))) {
    pk_score <- as.numeric(GenomicRanges::width(gr))
  }
  pk_score[!is.finite(pk_score)] <- 0
  for (i in seq_along(stitched)) {
    idx <- S4Vectors::subjectHits(hits)[S4Vectors::queryHits(hits) == i]
    scores[i] <- sum(pk_score[idx])
  }
  S4Vectors::mcols(stitched)$score <- scores
  S4Vectors::mcols(stitched)$name <- paste0("SE_cand_", seq_along(stitched))
  ord <- order(scores, decreasing = TRUE)
  stitched <- stitched[ord]
  scores <- scores[ord]
  infl <- .chip_rose_inflection(scores)
  se <- stitched[seq_len(infl$cutoff_index)]
  typical <- if (infl$cutoff_index < length(stitched)) stitched[seq.int(infl$cutoff_index + 1L, length(stitched))] else GenomicRanges::GRanges()
  out_dir <- chip_run_dir(session_id, paste0("super_enhancer_", format(Sys.time(), "%H%M%S")))
  se_bed <- file.path(out_dir, "super_enhancers.bed")
  all_bed <- file.path(out_dir, "stitched_enhancers_ranked.bed")
  .chip_write_gr_bed(se, se_bed)
  .chip_write_gr_bed(stitched, all_bed)
  rank_csv <- file.path(out_dir, "se_rank_table.csv")
  utils::write.csv(
    data.frame(
      rank = seq_along(scores),
      chrom = as.character(GenomicRanges::seqnames(stitched)),
      start = GenomicRanges::start(stitched),
      end = GenomicRanges::end(stitched),
      score = scores,
      is_super = seq_along(scores) <= infl$cutoff_index,
      stringsAsFactors = FALSE
    ),
    rank_csv, row.names = FALSE
  )
  # Simple rank plot
  plots <- list()
  if (requireNamespace("ggplot2", quietly = TRUE) && length(scores) >= 2L) {
    pdf <- data.frame(rank = seq_along(scores), score = scores, is_se = seq_along(scores) <= infl$cutoff_index)
    p <- ggplot2::ggplot(pdf, ggplot2::aes(x = rank, y = score, color = is_se)) +
      ggplot2::geom_point(size = 1.2) +
      ggplot2::geom_vline(xintercept = infl$cutoff_index, linetype = 2) +
      ggplot2::scale_color_manual(values = c("FALSE" = "#888888", "TRUE" = "#c0392b")) +
      ggplot2::labs(title = "ROSE-style SE rank (inflection)", x = "Rank", y = "Stitched score") +
      emp_pub_theme(base_size = 11)
    plots$se_rank <- tryCatch(plot_to_base64(p, width = 7, height = 5), error = function(e) NULL)
  }
  lp <- .chip_ops_update_last_peaks(session_id, se_bed, g_in, length(se), "super_enhancer")
  list(
    success = TRUE,
    op = "super_enhancer",
    stitch_gap = gap,
    n_input_peaks = as.integer(length(.chip_path_to_gr(peak_path))),
    n_stitched = as.integer(length(stitched)),
    n_super = as.integer(length(se)),
    n_typical = as.integer(length(typical)),
    cutoff_index = infl$cutoff_index,
    cutoff_score = infl$cutoff_score,
    note = paste(
      "ROSE-style approximation using peak scores (not BAM signal).",
      note_txdb %||% ""
    ),
    output_bed = se_bed,
    ranked_bed = all_bed,
    rank_csv = rank_csv,
    plots = plots,
    last_peaks = lp,
    preview = .chip_df_preview(.chip_gr_to_bed_df(utils::head(se, 20L)))
  )
}

#' Merge nearby peaks into broad domains.
chip_broad_domains <- function(session_id, peak_file = NULL, genome = NULL,
                               merge_gap = 5000L, min_width = 5000L) {
  session_id <- chip_require_session(session_id)
  .chip_require_genomicranges()
  resolved <- .chip_resolve_peaks(session_id, peak_file)
  peak_path <- resolved$path
  if (!nzchar(peak_path) || !file.exists(peak_path)) {
    return(list(success = FALSE, error = .chip_missing_peaks_error()))
  }
  g_in <- .chip_form_scalar(genome) %||% resolved$genome %||% "hs"
  gap <- suppressWarnings(as.integer(merge_gap %||% 5000L)[1])
  if (!is.finite(gap) || gap < 0L) gap <- 5000L
  min_w <- suppressWarnings(as.integer(min_width %||% 5000L)[1])
  if (!is.finite(min_w) || min_w < 0L) min_w <- 5000L
  gr <- .chip_path_to_gr(peak_path)
  dom <- GenomicRanges::reduce(gr, min.gapwidth = gap + 1L, ignore.strand = TRUE)
  dom <- dom[GenomicRanges::width(dom) >= min_w]
  # Rank by width
  dom <- dom[order(GenomicRanges::width(dom), decreasing = TRUE)]
  S4Vectors::mcols(dom)$score <- as.numeric(GenomicRanges::width(dom))
  S4Vectors::mcols(dom)$name <- paste0("domain_", seq_along(dom))
  out_dir <- chip_run_dir(session_id, paste0("broad_domains_", format(Sys.time(), "%H%M%S")))
  out_bed <- file.path(out_dir, "broad_domains.bed")
  .chip_write_gr_bed(dom, out_bed)
  lp <- .chip_ops_update_last_peaks(session_id, out_bed, g_in, length(dom), "broad_domains")
  list(
    success = TRUE,
    op = "broad",
    merge_gap = gap,
    min_width = min_w,
    n_input = as.integer(length(gr)),
    n_domains = as.integer(length(dom)),
    width_summary = .chip_numeric_summary(GenomicRanges::width(dom)),
    output_bed = out_bed,
    last_peaks = lp,
    preview = .chip_df_preview(.chip_gr_to_bed_df(utils::head(dom, 20L)))
  )
}

#' Bivalent promoters: intersect two mark peak files at promoters.
chip_bivalent <- function(session_id, peak_file = NULL, peak_b = NULL, genome = NULL,
                          promoter_window = 2000L) {
  session_id <- chip_require_session(session_id)
  .chip_require_genomicranges()
  resolved <- .chip_resolve_peaks(session_id, peak_file)
  peak_path <- resolved$path
  if (!nzchar(peak_path) || !file.exists(peak_path)) {
    return(list(success = FALSE, error = .chip_missing_peaks_error()))
  }
  pb <- tryCatch(.chip_resolve_peak_b(session_id, peak_b), error = function(e) NULL)
  if (is.null(pb) || !file.exists(pb)) {
    return(list(success = FALSE, error = "peak_b is required (e.g. H3K27me3 peak BED)."))
  }
  g_in <- .chip_form_scalar(genome) %||% resolved$genome %||% "hs"
  win <- suppressWarnings(as.integer(promoter_window %||% 2000L)[1])
  if (!is.finite(win) || win < 100L) win <- 2000L
  prom <- tryCatch(.chip_promoter_gr(g_in, upstream = win, downstream = win), error = function(e) e)
  if (inherits(prom, "error")) {
    return(list(success = FALSE, error = conditionMessage(prom), op = "bivalent"))
  }
  gr_a <- .chip_path_to_gr(peak_path)
  gr_b <- .chip_path_to_gr(pb)
  # Collapse to unique promoters for classification
  prom_u <- GenomicRanges::reduce(prom, ignore.strand = TRUE)
  has_a <- GenomicRanges::countOverlaps(prom_u, gr_a) > 0
  has_b <- GenomicRanges::countOverlaps(prom_u, gr_b) > 0
  state <- rep("unmarked", length(prom_u))
  state[has_a & !has_b] <- "active"
  state[!has_a & has_b] <- "repressed"
  state[has_a & has_b] <- "bivalent"
  biv <- prom_u[state == "bivalent"]
  out_dir <- chip_run_dir(session_id, paste0("bivalent_", format(Sys.time(), "%H%M%S")))
  out_bed <- file.path(out_dir, "bivalent_promoters.bed")
  .chip_write_gr_bed(biv, out_bed)
  state_csv <- file.path(out_dir, "promoter_states.csv")
  utils::write.csv(
    data.frame(
      chrom = as.character(GenomicRanges::seqnames(prom_u)),
      start = GenomicRanges::start(prom_u),
      end = GenomicRanges::end(prom_u),
      state = state,
      stringsAsFactors = FALSE
    ),
    state_csv, row.names = FALSE
  )
  counts <- as.list(table(state))
  list(
    success = TRUE,
    op = "bivalent",
    peak_a = peak_path,
    peak_b = pb,
    promoter_window = win,
    n_promoters = as.integer(length(prom_u)),
    state_counts = counts,
    n_bivalent = as.integer(sum(state == "bivalent")),
    output_bed = out_bed,
    state_csv = state_csv,
    preview = .chip_df_preview(.chip_gr_to_bed_df(utils::head(biv, 20L)))
  )
}

#' Combinatorial chromatin-state proxy from 2–3 mark BEDs (+ optional condition B).
chip_chromatin_states_proxy <- function(session_id,
                                        peak_file = NULL,
                                        peak_b = NULL,
                                        peak_c = NULL,
                                        peak_a2 = NULL,
                                        peak_b2 = NULL,
                                        peak_c2 = NULL,
                                        genome = NULL,
                                        mark_names = NULL,
                                        merge_gap = 0L) {
  session_id <- chip_require_session(session_id)
  .chip_require_genomicranges()
  resolved <- .chip_resolve_peaks(session_id, peak_file)
  peak_path <- resolved$path
  if (!nzchar(peak_path) || !file.exists(peak_path)) {
    return(list(success = FALSE, error = "peak_file (mark A) is required."))
  }
  pb <- tryCatch(.chip_resolve_peak_b(session_id, peak_b), error = function(e) NULL)
  if (is.null(pb) || !file.exists(pb)) {
    return(list(success = FALSE, error = "peak_b (mark B) is required for chromatin proxy."))
  }
  pc <- .chip_form_scalar(peak_c)
  g_in <- .chip_form_scalar(genome) %||% resolved$genome %||% "hs"
  gap <- suppressWarnings(as.integer(merge_gap %||% 0L)[1])
  if (!is.finite(gap) || gap < 0L) gap <- 0L

  marks_a <- list(A = .chip_path_to_gr(peak_path), B = .chip_path_to_gr(pb))
  if (!is.null(pc) && nzchar(pc) && file.exists(pc)) marks_a$C <- .chip_path_to_gr(pc)
  nm <- mark_names
  if (is.character(nm) && length(nm) >= length(marks_a)) {
    names(marks_a) <- nm[seq_along(marks_a)]
  }

  .chip_state_label <- function(bits, nms) {
    present <- nms[bits]
    if (!length(present)) return("empty")
    paste(present, collapse = "+")
  }

  build_states <- function(marks) {
    union_gr <- GenomicRanges::reduce(
      do.call(c, unname(marks)),
      min.gapwidth = gap + 1L,
      ignore.strand = TRUE
    )
    mat <- sapply(marks, function(g) GenomicRanges::countOverlaps(union_gr, g) > 0)
    if (is.null(dim(mat))) mat <- cbind(mat)
    labels <- apply(mat, 1L, function(row) .chip_state_label(as.logical(row), names(marks)))
    list(regions = union_gr, states = labels, matrix = mat)
  }

  st_a <- build_states(marks_a)
  out_dir <- chip_run_dir(session_id, paste0("chromatin_proxy_", format(Sys.time(), "%H%M%S")))
  state_bed <- file.path(out_dir, "chromatin_states_conditionA.bed")
  df_a <- data.frame(
    chrom = as.character(GenomicRanges::seqnames(st_a$regions)),
    start = as.integer(GenomicRanges::start(st_a$regions) - 1L),
    end = as.integer(GenomicRanges::end(st_a$regions)),
    name = st_a$states,
    score = 0,
    stringsAsFactors = FALSE
  )
  utils::write.table(df_a, state_bed, sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
  counts_a <- as.list(sort(table(st_a$states), decreasing = TRUE))

  # Optional condition B transition
  transition <- NULL
  pa2 <- .chip_form_scalar(peak_a2)
  pb2 <- .chip_form_scalar(peak_b2)
  pc2 <- .chip_form_scalar(peak_c2)
  if (!is.null(pa2) && nzchar(pa2) && file.exists(pa2) &&
      !is.null(pb2) && nzchar(pb2) && file.exists(pb2)) {
    marks_b <- list(A = .chip_path_to_gr(pa2), B = .chip_path_to_gr(pb2))
    if (!is.null(pc2) && nzchar(pc2) && file.exists(pc2)) marks_b$C <- .chip_path_to_gr(pc2)
    if (!is.null(names(marks_a)) && length(names(marks_a)) == length(marks_b)) {
      names(marks_b) <- names(marks_a)
    }
    st_b <- build_states(marks_b)
    # Compare on union of both condition segmentations
    both <- GenomicRanges::reduce(c(st_a$regions, st_b$regions), ignore.strand = TRUE)
    lab_a <- character(length(both))
    lab_b <- character(length(both))
    for (i in seq_along(both)) {
      ha <- GenomicRanges::findOverlaps(both[i], st_a$regions)
      hb <- GenomicRanges::findOverlaps(both[i], st_b$regions)
      lab_a[i] <- if (length(ha)) st_a$states[S4Vectors::subjectHits(ha)[1]] else "empty"
      lab_b[i] <- if (length(hb)) st_b$states[S4Vectors::subjectHits(hb)[1]] else "empty"
    }
    trans_tab <- table(from = lab_a, to = lab_b)
    trans_csv <- file.path(out_dir, "state_transitions.csv")
    utils::write.csv(as.data.frame(trans_tab), trans_csv, row.names = FALSE)
    changed <- both[lab_a != lab_b]
    change_bed <- file.path(out_dir, "state_changed_regions.bed")
    if (length(changed)) {
      utils::write.table(
        data.frame(
          chrom = as.character(GenomicRanges::seqnames(changed)),
          start = as.integer(GenomicRanges::start(changed) - 1L),
          end = as.integer(GenomicRanges::end(changed)),
          name = paste0(lab_a[lab_a != lab_b], "->", lab_b[lab_a != lab_b]),
          score = 0,
          stringsAsFactors = FALSE
        ),
        change_bed, sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE
      )
    }
    transition <- list(
      n_regions = as.integer(length(both)),
      n_changed = as.integer(sum(lab_a != lab_b)),
      transition_csv = trans_csv,
      changed_bed = if (file.exists(change_bed)) change_bed else NULL,
      top_transitions = utils::head(
        as.data.frame(sort(trans_tab, decreasing = TRUE)), 20
      )
    )
  }

  list(
    success = TRUE,
    op = "chromatin_proxy",
    note = paste(
      "ChromHMM-style proxy: combinatorial presence/absence of 2–3 peak sets",
      "(not a trained HMM). Optional condition-B peaks enable transition matrix."
    ),
    n_marks = length(marks_a),
    mark_names = names(marks_a),
    state_counts = counts_a,
    output_bed = state_bed,
    transition = transition,
    output_dir = out_dir,
    preview = utils::head(df_a, 20)
  )
}

#' Dispatcher for consolidated peaks_ops API.
chip_peaks_ops <- function(session_id, op, ...) {
  session_id <- chip_require_session(session_id)
  op <- tolower(trimws(as.character(op %||% "")[1]))
  args <- list(...)
  # Normalize common aliases from JSON body
  if (!is.null(args$peak_file_b) && is.null(args$peak_b)) args$peak_b <- args$peak_file_b
  dispatch <- list(
    blacklist = chip_peaks_blacklist,
    merge = chip_peaks_merge,
    summit = chip_peaks_summit_window,
    overlap = chip_peaks_overlap,
    idr = chip_idr_approx,
    promoter = chip_promoter_call,
    enhancer = chip_enhancer_call,
    super_enhancer = chip_super_enhancer,
    broad = chip_broad_domains,
    bivalent = chip_bivalent,
    chromatin_proxy = chip_chromatin_states_proxy
  )
  if (!nzchar(op) || !op %in% names(dispatch)) {
    return(list(
      success = FALSE,
      error = paste0(
        "Unknown op. Use one of: ",
        paste(names(dispatch), collapse = ", ")
      ),
      available_ops = names(dispatch)
    ))
  }
  fn <- dispatch[[op]]
  # Build call with known formals
  fml <- names(formals(fn))
  call_args <- list(session_id = session_id)
  for (nm in setdiff(fml, "session_id")) {
    if (!is.null(args[[nm]])) call_args[[nm]] <- args[[nm]]
  }
  do.call(fn, call_args)
}

# ── Joint co-analysis bridges (ChIP × other omics) ───────────────────

.chip_unwrap_diff_df <- function(raw) {
  if (is.null(raw)) return(NULL)
  if (is.data.frame(raw)) return(raw)
  if (is.list(raw) && is.data.frame(raw$data)) return(raw$data)
  NULL
}

.chip_annotation_genes <- function(session_id, peak_annotation_csv = NULL) {
  if (is.null(peak_annotation_csv) || !nzchar(as.character(peak_annotation_csv)[1])) {
    manifest <- chip_load_manifest(session_id)
    peak_annotation_csv <- manifest$last_annotation_csv %||% ""
  }
  peak_annotation_csv <- chip_require_string(peak_annotation_csv, "peak_annotation_csv")
  if (!file.exists(peak_annotation_csv)) {
    stop("peak_annotation_csv not found. Run ChIPseeker annotation first.")
  }
  anno <- read.csv(peak_annotation_csv, stringsAsFactors = FALSE, check.names = FALSE)
  gene_col <- intersect(c("SYMBOL", "geneSymbol", "geneId", "GENEID", "gene"), names(anno))[1]
  if (is.null(gene_col) || is.na(gene_col)) stop("No gene symbol column in peak annotation.")
  genes <- unique(trimws(as.character(anno[[gene_col]])))
  genes <- genes[nzchar(genes)]
  list(anno = anno, genes = genes, peak_annotation_csv = peak_annotation_csv, gene_col = gene_col)
}

.chip_diff_sig_ids <- function(session_id, experiment, p_cutoff = 0.05, fc_cutoff = 0) {
  experiment <- .chip_form_scalar(experiment)
  if (is.null(experiment) || !nzchar(experiment)) return(character(0))
  raw <- .chip_unwrap_diff_df(tryCatch(ensure_diff_raw(session_id, experiment), error = function(e) NULL))
  if (is.null(raw) || !nrow(raw)) return(character(0))
  gcol <- intersect(c("feature", "gene", "SYMBOL", "GeneID", "id", "symbol"), names(raw))[1]
  if (is.null(gcol) || is.na(gcol)) return(character(0))
  pcols <- intersect(c("padj", "p_val_adj", "P.Value", "pvalue", "p"), names(raw))
  fcol <- intersect(c("avg_log2FC", "log2FoldChange", "logFC", "effect", "score"), names(raw))[1]
  pcut <- suppressWarnings(as.numeric(p_cutoff)[1]); if (!is.finite(pcut)) pcut <- 0.05
  fcut <- suppressWarnings(as.numeric(fc_cutoff)[1]); if (!is.finite(fcut)) fcut <- 0
  idx <- rep(TRUE, nrow(raw))
  if (length(pcols)) {
    pv <- suppressWarnings(as.numeric(raw[[pcols[1]]]))
    idx <- idx & !is.na(pv) & pv <= pcut
  }
  if (!is.null(fcol) && !is.na(fcol) && isTRUE(fcut > 0)) {
    fv <- suppressWarnings(as.numeric(raw[[fcol]]))
    idx <- idx & !is.na(fv) & abs(fv) >= fcut
  }
  ids <- unique(trimws(as.character(raw[[gcol]][idx])))
  ids[nzchar(ids)]
}

.chip_empt_sample_ids <- function(session_id, experiment) {
  experiment <- .chip_form_scalar(experiment)
  if (is.null(experiment) || !nzchar(experiment)) return(character(0))
  empt <- tryCatch(load_empt(session_id, experiment), error = function(e) NULL)
  if (is.null(empt)) return(character(0))
  cd <- tryCatch(as.data.frame(SummarizedExperiment::colData(empt)), error = function(e) NULL)
  if (is.null(cd) || !nrow(cd)) {
    ad <- tryCatch(SummarizedExperiment::assays(empt)[[1]], error = function(e) NULL)
    if (!is.null(ad)) return(colnames(ad))
    return(character(0))
  }
  rownames(cd)
}

.chip_simple_corr_summary <- function(session_id, exp_a, exp_b, min_n = 5L) {
  sa <- .chip_empt_sample_ids(session_id, exp_a)
  sb <- .chip_empt_sample_ids(session_id, exp_b)
  shared <- intersect(sa, sb)
  if (length(shared) < min_n) {
    return(list(
      shared_n = length(shared),
      message = paste0("Shared samples < ", min_n, "; skip correlation.")
    ))
  }
  ea <- tryCatch(load_empt(session_id, exp_a), error = function(e) NULL)
  eb <- tryCatch(load_empt(session_id, exp_b), error = function(e) NULL)
  if (is.null(ea) || is.null(eb)) {
    return(list(shared_n = length(shared), message = "Could not load both assays for correlation."))
  }
  ma <- as.matrix(SummarizedExperiment::assays(ea)[[1]])
  mb <- as.matrix(SummarizedExperiment::assays(eb)[[1]])
  shared <- intersect(intersect(colnames(ma), colnames(mb)), shared)
  if (length(shared) < min_n) {
    return(list(shared_n = length(shared), message = "Shared assay columns < threshold."))
  }
  # Correlate sample-level mean signal as a lightweight alignment check.
  va <- colMeans(ma[, shared, drop = FALSE], na.rm = TRUE)
  vb <- colMeans(mb[, shared, drop = FALSE], na.rm = TRUE)
  ok <- is.finite(va) & is.finite(vb)
  if (sum(ok) < min_n) {
    return(list(shared_n = length(shared), message = "Too few finite sample means for correlation."))
  }
  ct <- suppressWarnings(stats::cor.test(va[ok], vb[ok], method = "spearman"))
  list(
    shared_n = length(shared),
    method = "spearman",
    rho = unname(ct$estimate),
    p_value = ct$p.value,
    message = "Sample-mean Spearman correlation between assays."
  )
}

chip_microbiome_coanalysis <- function(session_id,
                                       peak_annotation_csv = NULL,
                                       m16s_experiment = NULL,
                                       mgx_experiment = NULL,
                                       p_cutoff = 0.05,
                                       genome = "hs") {
  session_id <- chip_require_session(session_id)
  ann <- .chip_annotation_genes(session_id, peak_annotation_csv)
  chip_genes <- ann$genes
  if (!length(chip_genes)) stop("No peak-associated genes after annotation.")

  m16s_experiment <- .chip_form_scalar(m16s_experiment)
  mgx_experiment <- .chip_form_scalar(mgx_experiment)
  if ((is.null(m16s_experiment) || !nzchar(m16s_experiment)) &&
      (is.null(mgx_experiment) || !nzchar(mgx_experiment))) {
    stop("Provide m16s_experiment and/or mgx_experiment with cached diff_raw.")
  }

  out_dir <- chip_run_dir(session_id, "microbiome_coanalysis")
  tables <- list()
  m16s_sig <- .chip_diff_sig_ids(session_id, m16s_experiment, p_cutoff = p_cutoff)
  mgx_sig <- .chip_diff_sig_ids(session_id, mgx_experiment, p_cutoff = p_cutoff)
  if (!length(m16s_sig) && !length(mgx_sig)) {
    stop("No significant features in 16S/MGX diff_raw. Import DE results or run differential analysis first.")
  }

  # List-level overlap: peak genes vs MGX feature ids when they share nomenclature;
  # always export both DE lists for downstream mapping.
  overlap_gene_mgx <- if (length(mgx_sig)) intersect(toupper(chip_genes), toupper(mgx_sig)) else character(0)

  gene_fn <- file.path(out_dir, "chip_peak_genes.csv")
  utils::write.csv(data.frame(gene = chip_genes, stringsAsFactors = FALSE), gene_fn, row.names = FALSE)
  tables$chip_genes <- gene_fn

  if (length(m16s_sig)) {
    fn <- file.path(out_dir, "m16s_sig_taxa.csv")
    utils::write.csv(data.frame(feature = m16s_sig, stringsAsFactors = FALSE), fn, row.names = FALSE)
    tables$m16s_sig <- fn
  }
  if (length(mgx_sig)) {
    fn <- file.path(out_dir, "mgx_sig_features.csv")
    utils::write.csv(data.frame(feature = mgx_sig, stringsAsFactors = FALSE), fn, row.names = FALSE)
    tables$mgx_sig <- fn
  }
  if (length(overlap_gene_mgx)) {
    fn <- file.path(out_dir, "overlap_chip_genes_mgx.csv")
    utils::write.csv(data.frame(feature = overlap_gene_mgx, stringsAsFactors = FALSE), fn, row.names = FALSE)
    tables$overlap_chip_mgx <- fn
  }

  corr <- list()
  if (!is.null(m16s_experiment) && nzchar(m16s_experiment) &&
      !is.null(mgx_experiment) && nzchar(mgx_experiment)) {
    corr$m16s_mgx <- .chip_simple_corr_summary(session_id, m16s_experiment, mgx_experiment, min_n = 5L)
  }
  # Optional: correlate a proxy empt if ChIP has expression-like companion — skip when absent.

  list(
    success = TRUE,
    chip_genes_n = length(chip_genes),
    m16s_experiment = m16s_experiment %||% "",
    mgx_experiment = mgx_experiment %||% "",
    m16s_sig_n = length(m16s_sig),
    mgx_sig_n = length(mgx_sig),
    overlap_chip_mgx_n = length(overlap_gene_mgx),
    overlap_chip_mgx = utils::head(overlap_gene_mgx, 300),
    m16s_sig = utils::head(m16s_sig, 300),
    mgx_sig = utils::head(mgx_sig, 300),
    correlation = corr,
    tables = tables,
    note = "Peak genes vs 16S DE taxa (list export) and optional MGX feature overlap; correlation when ≥5 shared samples."
  )
}

chip_metabolomics_coanalysis <- function(session_id,
                                         peak_annotation_csv = NULL,
                                         mbx_experiment = NULL,
                                         p_cutoff = 0.05,
                                         genome = "hs") {
  session_id <- chip_require_session(session_id)
  ann <- .chip_annotation_genes(session_id, peak_annotation_csv)
  chip_genes <- ann$genes
  if (!length(chip_genes)) stop("No peak-associated genes after annotation.")

  mbx_experiment <- chip_require_string(mbx_experiment, "mbx_experiment")
  mbx_sig <- .chip_diff_sig_ids(session_id, mbx_experiment, p_cutoff = p_cutoff)
  if (!length(mbx_sig)) {
    stop("No significant metabolites in MBX diff_raw. Import DE results or run differential analysis first.")
  }

  out_dir <- chip_run_dir(session_id, "metabolomics_coanalysis")
  tables <- list()
  gene_fn <- file.path(out_dir, "chip_peak_genes.csv")
  utils::write.csv(data.frame(gene = chip_genes, stringsAsFactors = FALSE), gene_fn, row.names = FALSE)
  tables$chip_genes <- gene_fn
  mbx_fn <- file.path(out_dir, "mbx_sig_metabolites.csv")
  utils::write.csv(data.frame(feature = mbx_sig, stringsAsFactors = FALSE), mbx_fn, row.names = FALSE)
  tables$mbx_sig <- mbx_fn

  # Name-level overlap when metabolite ids coincidentally match gene symbols (rare but useful).
  overlap <- intersect(toupper(chip_genes), toupper(mbx_sig))
  if (length(overlap)) {
    fn <- file.path(out_dir, "overlap_chip_mbx_ids.csv")
    utils::write.csv(data.frame(feature = overlap, stringsAsFactors = FALSE), fn, row.names = FALSE)
    tables$overlap_ids <- fn
  }

  corr <- list(message = "No RNA companion for sample correlation; MBX-only session.")
  # If an RNA experiment exists in session with shared samples, report alignment.
  # Keep thin: only when mbx empt loads.
  corr <- .chip_simple_corr_summary(session_id, mbx_experiment, mbx_experiment, min_n = 5L)
  corr$message <- paste0(
    "MBX self-check / sample count. Pathway-level gene↔metabolite mapping is list-export based (",
    length(mbx_sig), " DE metabolites vs ", length(chip_genes), " peak genes)."
  )

  list(
    success = TRUE,
    chip_genes_n = length(chip_genes),
    mbx_experiment = mbx_experiment,
    mbx_sig_n = length(mbx_sig),
    overlap_id_n = length(overlap),
    overlap_ids = utils::head(overlap, 200),
    mbx_sig = utils::head(mbx_sig, 300),
    correlation = corr,
    tables = tables,
    note = "Peak annotation genes/pathways exported alongside MBX DE list for pathway mapping."
  )
}

chip_clinical_coanalysis <- function(session_id,
                                     peak_annotation_csv = NULL,
                                     clinical_source = "standalone",
                                     companion_experiment = NULL,
                                     p_cutoff = 0.05) {
  session_id <- chip_require_session(session_id)
  ann <- .chip_annotation_genes(session_id, peak_annotation_csv)
  chip_genes <- ann$genes
  if (!length(chip_genes)) stop("No peak-associated genes after annotation.")

  clin <- tryCatch(.clin_read_external(session_id), error = function(e) NULL)
  if (is.null(clin) || !nrow(clin)) {
    stop("No clinical raw/meta table in session. Upload clinical_raw or clinical_meta on Import.")
  }

  out_dir <- chip_run_dir(session_id, "clinical_coanalysis")
  tables <- list()

  # Variable dictionary
  dict <- data.frame(
    variable = names(clin),
    n_non_na = vapply(clin, function(x) sum(!(is.na(x) | (is.character(x) & !nzchar(trimws(x))))), integer(1)),
    n_unique = vapply(clin, function(x) length(unique(x[!is.na(x)])), integer(1)),
    is_numeric = vapply(clin, function(x) {
      xx <- suppressWarnings(as.numeric(as.character(x)))
      mean(is.finite(xx)) >= 0.5
    }, logical(1)),
    stringsAsFactors = FALSE
  )
  dict_fn <- file.path(out_dir, "clinical_variable_dictionary.csv")
  utils::write.csv(dict, dict_fn, row.names = FALSE)
  tables$clinical_dictionary <- dict_fn

  gene_fn <- file.path(out_dir, "chip_peak_genes.csv")
  utils::write.csv(data.frame(gene = chip_genes, stringsAsFactors = FALSE), gene_fn, row.names = FALSE)
  tables$chip_genes <- gene_fn

  peak_summary <- data.frame(
    n_peaks = nrow(ann$anno),
    n_genes = length(chip_genes),
    annotation_csv = ann$peak_annotation_csv,
    stringsAsFactors = FALSE
  )
  ps_fn <- file.path(out_dir, "peak_summary.csv")
  utils::write.csv(peak_summary, ps_fn, row.names = FALSE)
  tables$peak_summary <- ps_fn

  # Shared samples with optional companion assay (RNA/16S/etc.)
  companion_experiment <- .chip_form_scalar(companion_experiment)
  clin_ids <- if ("primary" %in% names(clin)) {
    as.character(clin$primary)
  } else {
    rownames(clin)
  }
  clin_ids <- clin_ids[nzchar(trimws(clin_ids))]
  shared <- character(0)
  associations <- list()

  if (!is.null(companion_experiment) && nzchar(companion_experiment)) {
    assay_ids <- .chip_empt_sample_ids(session_id, companion_experiment)
    # Normalize lightly for matching
    shared <- intersect(toupper(trimws(clin_ids)), toupper(trimws(assay_ids)))
    if (length(shared) >= 5L) {
      empt <- tryCatch(load_empt(session_id, companion_experiment), error = function(e) NULL)
      if (!is.null(empt)) {
        mat <- as.matrix(SummarizedExperiment::assays(empt)[[1]])
        # Map clinical rows to assay columns
        clin_key <- toupper(trimws(clin_ids))
        assay_key <- toupper(trimws(colnames(mat)))
        use_clin <- which(clin_key %in% shared)
        use_assay <- match(clin_key[use_clin], assay_key)
        ok <- !is.na(use_assay)
        use_clin <- use_clin[ok]
        use_assay <- use_assay[ok]
        if (length(use_clin) >= 5L) {
          # Gene-set mean expression vs numeric clinical vars
          genes_in <- intersect(chip_genes, rownames(mat))
          if (length(genes_in) >= 2L) {
            gmean <- colMeans(mat[genes_in, use_assay, drop = FALSE], na.rm = TRUE)
            num_vars <- dict$variable[dict$is_numeric & dict$variable != "primary"]
            rows <- list()
            for (vn in utils::head(num_vars, 40)) {
              xv <- suppressWarnings(as.numeric(as.character(clin[[vn]][use_clin])))
              keep <- is.finite(xv) & is.finite(gmean)
              if (sum(keep) < 5L) next
              ct <- suppressWarnings(stats::cor.test(gmean[keep], xv[keep], method = "spearman"))
              rows[[length(rows) + 1L]] <- data.frame(
                variable = vn,
                n = sum(keep),
                rho = unname(ct$estimate),
                p_value = ct$p.value,
                stringsAsFactors = FALSE
              )
            }
            if (length(rows)) {
              assoc_df <- do.call(rbind, rows)
              assoc_df <- assoc_df[order(assoc_df$p_value), , drop = FALSE]
              afn <- file.path(out_dir, "peak_geneset_vs_clinical.csv")
              utils::write.csv(assoc_df, afn, row.names = FALSE)
              tables$associations <- afn
              associations <- utils::head(assoc_df, 30)
            }
          }
        }
      }
    }
  }

  mode <- if (length(shared) >= 5L && length(associations)) {
    "shared_sample_association"
  } else {
    "peak_summary_plus_clinical_dictionary"
  }

  list(
    success = TRUE,
    mode = mode,
    chip_genes_n = length(chip_genes),
    clinical_n_samples = length(clin_ids),
    clinical_n_variables = ncol(clin),
    shared_samples_n = length(shared),
    companion_experiment = companion_experiment %||% "",
    associations = associations,
    tables = tables,
    note = if (identical(mode, "shared_sample_association")) {
      "Peak gene-set mean vs numeric clinical variables (Spearman) on shared samples."
    } else {
      "No ≥5 shared samples with companion assay — exported peak summary + clinical variable dictionary for downstream use."
    }
  )
}
