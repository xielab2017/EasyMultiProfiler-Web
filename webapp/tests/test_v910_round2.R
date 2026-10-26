# test_v910_round2.R — standalone tests for the v9.1.0 Round 2 backend
# helpers (memory_utils.R + i18n_locale.R).
#
# Run on a machine with R (and the Matrix package, a declared package
# dependency):
#   Rscript webapp/tests/test_v910_round2.R
#
# Exits non-zero (via stopifnot) on the first failed assertion and
# prints "test_v910_round2.R: all assertions passed" on success.

args <- commandArgs(trailingOnly = FALSE)
file_arg <- sub("^--file=", "", grep("^--file=", args, value = TRUE))
script_dir <- if (length(file_arg)) dirname(normalizePath(file_arg[1])) else getwd()
helpers_dir <- file.path(script_dir, "..", "backend", "helpers")

source(file.path(helpers_dir, "i18n_locale.R"))
source(file.path(helpers_dir, "memory_utils.R"))

## --- i18n_locale sanity (shared with Round 1 expectations) --------------
stopifnot(identical(emp_country_to_locale("JP"), "ja"))
stopifnot(identical(emp_negotiate_locale("SA", "en-US"), "ar"))
stopifnot(identical(emp_negotiate_locale(NULL, "ko-KR"), "ko"))
stopifnot(identical(emp_locale_dir("ar"), "rtl"))
stopifnot(identical(emp_locale_dir("en"), "ltr"))

## --- Density of a sparse synthetic matrix --------------------------------
set.seed(42)
mat <- matrix(0, nrow = 50, ncol = 20)
mat[sample(length(mat), 40)] <- runif(40, 1, 10)  # 4% non-zero
density <- emp_matrix_density(mat)
stopifnot(is.finite(density), density > 0, density < 0.30)

## --- Sparse conversion preserves values ----------------------------------
sp <- emp_maybe_sparse(mat, threshold = 0.30, quiet = TRUE)
stopifnot(inherits(sp, "sparseMatrix"))
stopifnot(isTRUE(attr(sp, "sparse_converted")))
stopifnot(isTRUE(all.equal(as.matrix(sp), mat, check.attributes = FALSE)))

## --- Dense matrix is returned unchanged -----------------------------------
dense <- matrix(runif(100), nrow = 10, ncol = 10)
stopifnot(identical(emp_maybe_sparse(dense, quiet = TRUE), dense))

## --- Non-matrix input passes through untouched ----------------------------
stopifnot(identical(emp_maybe_sparse("not a matrix", quiet = TRUE), "not a matrix"))
stopifnot(is.na(emp_matrix_density(NULL)))

## --- Chunk plan sums to n --------------------------------------------------
for (n in c(0, 1, 7, 1000, 123456)) {
  plan <- emp_chunk_plan(n, target_mb = 1, row_bytes_estimate = 4096)
  stopifnot(is.integer(plan), sum(plan) == n)
  if (n > 0) stopifnot(all(plan > 0))
}
stopifnot(identical(emp_chunk_plan(0), integer(0)))

## --- Memory info shape ------------------------------------------------------
info_env <- new.env(parent = emptyenv())
info_env$big <- matrix(0, nrow = 100, ncol = 100)
info_env$small <- 1:10
info <- emp_memory_info(env = info_env)
stopifnot(is.list(info))
stopifnot(is.data.frame(info$top_objects))
stopifnot(all(c("name", "size_mb") %in% names(info$top_objects)))
stopifnot(identical(info$top_objects$name[1], "big"))
stopifnot(is.finite(info$gc_used_mb), info$gc_used_mb > 0)
stopifnot(identical(info$r_version, as.character(getRversion())))

## --- Release removes only the named objects --------------------------------
rel_env <- new.env(parent = emptyenv())
rel_env$drop_me <- matrix(0, nrow = 50, ncol = 50)
rel_env$keep_me <- 42
res <- emp_release("drop_me", env = rel_env)
stopifnot(identical(res$removed, "drop_me"))
stopifnot(!exists("drop_me", envir = rel_env, inherits = FALSE))
stopifnot(exists("keep_me", envir = rel_env, inherits = FALSE))

cat("test_v910_round2.R: all assertions passed\n")
