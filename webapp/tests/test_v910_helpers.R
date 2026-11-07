# test_v910_helpers.R - standalone checks for the v9.1.0 backend helpers.
#
# Run from anywhere with:
#   Rscript webapp/tests/test_v910_helpers.R
# Exits non-zero (via stopifnot) on the first failed expectation.

backend_dir <- local({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    script <- sub("^--file=", "", file_arg[[1]])
    return(normalizePath(file.path(dirname(script), "..", "backend")))
  }
  file.path(getwd(), "webapp", "backend")
})

source(file.path(backend_dir, "helpers", "i18n_locale.R"))
source(file.path(backend_dir, "helpers", "platform_info.R"))
source(file.path(backend_dir, "helpers", "qc_rigor.R"))
source(file.path(backend_dir, "helpers", "run_pipeline_cache.R"))
source(file.path(backend_dir, "helpers", "multiomics_joint.R"))
source(file.path(backend_dir, "helpers", "repro_report.R"))

## 1. Country mapping + negotiation priority ---------------------------
stopifnot(identical(emp_country_to_locale("JP"), "ja"))
stopifnot(identical(emp_country_to_locale("sa"), "ar"))
stopifnot(identical(emp_country_to_locale("TW"), "zh-TW"))
stopifnot(identical(emp_country_to_locale("CN"), "zh"))
stopifnot(is.na(emp_country_to_locale("XX")))
stopifnot(is.na(emp_country_to_locale(NULL)))

# Country header beats Accept-Language.
stopifnot(identical(emp_negotiate_locale("KR", "en-US"), "ko"))
# Accept-Language used when no country is given.
stopifnot(identical(emp_negotiate_locale(NULL, "ja-JP, en;q=0.8"), "ja"))
stopifnot(identical(emp_negotiate_locale(NULL, "zh-Hant-HK"), "zh-TW"))
# Product default is zh.
stopifnot(identical(emp_negotiate_locale(NULL, NULL), "zh"))
stopifnot(identical(emp_locale_dir("ar"), "rtl"))
stopifnot(identical(emp_locale_dir("ja"), "ltr"))
stopifnot(identical(emp_plot_font_family("ko"), "Noto Sans CJK KR"))
stopifnot(identical(emp_msg("ja", "report.title"),
                    .EMP_MSG[["report.title"]][["ja"]]))
stopifnot(identical(emp_msg("es", "report.title"),
                    .EMP_MSG[["report.title"]][["en"]])) # es falls back to en
stopifnot(identical(emp_msg("en", "no.such.key"), "no.such.key"))

## 2. Platform info -----------------------------------------------------
info <- emp_platform_info()
stopifnot(info$os %in% c("windows", "macos", "linux"))
stopifnot(nzchar(info$r_version))

## 3. QC rigor on a synthetic matrix with planted missingness ---------
set.seed(42)
mat <- matrix(rnorm(20 * 12), nrow = 20,
              dimnames = list(paste0("gene", 1:20), paste0("s", 1:12)))
mat[sample(length(mat), 80)] <- NA # ~33% missing -> HIGH_MISSINGNESS
mat[1, ] <- 1 # zero-variance feature (also clears any NA planted in row 1)
n_na_planted <- sum(is.na(mat))
stopifnot(n_na_planted > 0)
meta <- data.frame(
  group = rep(c("case", "ctrl"), each = 6),
  batch = rep(c("b1", "b2"), each = 6), # batch fully aligned with group
  row.names = colnames(mat)
)
qc <- emp_qc_rigor(mat, meta, group_col = "group", batch_col = "batch")
stopifnot("HIGH_MISSINGNESS" %in% qc$warnings)
stopifnot(qc$summary$missing_overall > 0.2)
stopifnot(qc$checks$variance$zero_variance_features >= 1)
stopifnot("BATCH_GROUP_CONFOUNDING" %in% qc$warnings)
# QC is report-only: the input matrix is untouched.
stopifnot(sum(is.na(mat)) == n_na_planted)

# Clean matrix produces no missingness warning.
clean <- matrix(rnorm(10 * 8), nrow = 10,
                dimnames = list(paste0("g", 1:10), paste0("s", 1:8)))
qc_clean <- emp_qc_rigor(clean)
stopifnot(!("HIGH_MISSINGNESS" %in% qc_clean$warnings))
stopifnot(qc_clean$summary$missing_overall == 0)

## 4. Cross-omics network on synthetic correlated data ------------------
set.seed(7)
n <- 30
base <- rnorm(n)
a <- matrix(c(base + rnorm(n, sd = 0.1), rnorm(n), rnorm(n)), nrow = 3,
            byrow = TRUE,
            dimnames = list(c("a1", "a2", "a3"), paste0("s", 1:n)))
b <- matrix(c(base + rnorm(n, sd = 0.1), rnorm(n)), nrow = 2, byrow = TRUE,
            dimnames = list(c("b1", "b2"), paste0("s", 1:n)))
edges <- emp_cross_omics_network(a, b, fdr = 0.05, cor_min = 0.5)
stopifnot(nrow(edges) >= 1)
stopifnot(any(edges$from == "a1" & edges$to == "b1"))
stopifnot(all(abs(edges$cor) >= 0.5), all(edges$p_adj <= 0.05))

# Joint factor runs and returns matched-sample scores.
jf <- emp_joint_factor(list(x = a, y = b), n_factors = 2)
stopifnot(nrow(jf$scores) == n, ncol(jf$scores) == 2)
stopifnot(length(jf$variance_explained) == 2)

# ChIP-RNA links without a TSS column report NA distances honestly.
peaks <- data.frame(chr = "chr1", start = c(100, 5000), end = c(200, 5200),
                    gene = c("g1", "g2"), stringsAsFactors = FALSE)
links <- emp_chip_rna_links(peaks)
stopifnot(all(is.na(links$distance_to_tss)))
stopifnot(grepl("gene_tss", links$note[[1]]))

## 5. Cache step runs fn once, then serves the cache --------------------
calls <- new.env()
calls$n <- 0
fn <- function() {
  calls$n <- calls$n + 1
  42
}
cache_dir <- tempfile("emp_cache_test_")
dir.create(cache_dir)
first <- emp_run_cached_step("step1", list(x = 1), fn, cache_dir)
second <- emp_run_cached_step("step1", list(x = 1), fn, cache_dir)
stopifnot(identical(first$value, 42), identical(second$value, 42))
stopifnot(!first$cached, second$cached)
stopifnot(calls$n == 1)
# A different key must miss the cache.
third <- emp_run_cached_step("step1", list(x = 2), fn, cache_dir)
stopifnot(!third$cached, calls$n == 2)
unlink(cache_dir, recursive = TRUE)

## 6. Resume plan ---------------------------------------------------------
plan <- emp_resume_plan(c("a", "b", "c"),
                        list(a = TRUE, b = "done", c = FALSE))
stopifnot(identical(plan, "c"))
stopifnot(identical(emp_resume_plan(character(0), list()), character(0)))

## 7. Reproducibility manifest -------------------------------------------
manifest <- emp_repro_manifest(list(run_id = "test"), locale = "ja")
stopifnot(identical(manifest$emp_version, "9.1.0"))
stopifnot(identical(manifest$run_id, "test"))
stopifnot(identical(manifest$locale, "ja"))
out_dir <- tempfile("emp_repro_test_")
paths <- emp_write_repro_report(out_dir, manifest, locale = "ja")
stopifnot(file.exists(paths$report))
if (!is.null(paths$json)) stopifnot(file.exists(paths$json))
report_txt <- paste(readLines(paths$report, warn = FALSE), collapse = "\n")
stopifnot(grepl("9.1.0", report_txt, fixed = TRUE))
unlink(out_dir, recursive = TRUE)

cat("test_v910_helpers.R: all checks passed\n")
