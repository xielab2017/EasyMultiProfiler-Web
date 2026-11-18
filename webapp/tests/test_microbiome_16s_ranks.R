# Real EMP taxonomy import with a legacy Kindom column, shuffled sample metadata,
# manual richness and Bray–Curtis checks, and repeated rank aggregation.
suppressPackageStartupMessages(library(EasyMultiProfiler))
root <- tempfile("emp-16s-ranks-")
dir.create(root)
Sys.setenv(EMP_DATA_DIR = root, EMP_SESSION_DIR = file.path(root, "sessions"))
for (helper in c("storage", "utils", "session", "import", "analysis",
                 "workflow_microbiome_16s", "workflow_microbiome_16s_api")) {
  source(file.path("webapp/backend/helpers", paste0(helper, ".R")))
}

set.seed(917)
samples <- paste0("sample", 1:8)
genera <- rep(1:6, each = 2)
phyla <- rep(1:2, each = 6)
lineage <- sprintf("k__Bacteria;p__P%d;c__C%d;o__O1;f__F1;g__G%d;s__T%d",
                   phyla, phyla, genera, seq_along(genera))
counts <- matrix(sample(0:20, 12 * 8, replace = TRUE), ncol = 8,
                 dimnames = list(lineage, samples))
counts[1:2, 1] <- 0L
write.csv(counts, file.path(root, "taxa.csv"), quote = FALSE)
write.csv(data.frame(SampleID = rev(samples), Group = rep(c("B", "A"), each = 4)),
          file.path(root, "mapping.csv"), row.names = FALSE, quote = FALSE)
mae <- build_mae(file.path(root, "taxa.csv"), file.path(root, "mapping.csv"),
                 "fixture", data_type = "tax", assay_name = "counts")
session <- create_session()
save_mae(session, mae)
alpha <- run_alpha(session, "fixture")
aligned <- counts[, alpha$primary, drop = FALSE]
entropy <- apply(aligned, 2, function(x) { p <- x[x > 0] / sum(x); -sum(p * log(p)) })
stopifnot(all(alpha$observed == colSums(aligned > 0)), all(alpha$observerd_index == alpha$observed),
          max(abs(alpha$shannon - entropy)) < 1e-10)

axes <- run_dimension(session, "fixture", "PCoA")
matrix_for_axes <- counts[, axes$primary, drop = FALSE]
bray <- outer(seq_len(ncol(matrix_for_axes)), seq_len(ncol(matrix_for_axes)),
              Vectorize(function(i, j) sum(abs(matrix_for_axes[, i] - matrix_for_axes[, j])) /
                          sum(matrix_for_axes[, i] + matrix_for_axes[, j])))
expected <- stats::cmdscale(as.dist(bray), k = 3)
stopifnot(max(abs(as.vector(dist(axes[, c("PCoA1", "PCoA2", "PCoA3")])) -
                      as.vector(dist(expected)))) < 1e-9)

original <- load_empt(session, "fixture")
profile <- m16s_profile(session, "fixture")
stopifnot(profile$max_taxonomy_depth == 7L, profile$observed_levels[["Domain"]] == 0L,
          profile$observed_levels[["Species"]] == nrow(counts))
genus <- m16s_prepare_taxonomy(original, collapse_level = "Genus")
phylum <- m16s_prepare_taxonomy(genus, collapse_level = "Phylum")
check_totals <- function(aggregated, labels) {
  expected <- rowsum(counts, labels)
  actual <- SummarizedExperiment::assay(aggregated)
  stopifnot(setequal(rownames(actual), rownames(expected)),
            all(actual == expected[rownames(actual), colnames(actual), drop = FALSE]))
}
check_totals(genus, paste0("G", genera))
check_totals(phylum, paste0("P", phyla))
direct <- m16s_parse_taxonomy("d__Bacteria;p__P1;g__G1;s__T1")
stopifnot(is.na(direct[2]), direct[3] == "P1", direct[7] == "G1", direct[8] == "T1")

# Explicit gaps stay unassigned even when imported rank columns have imputed labels.
sparse <- SummarizedExperiment::SummarizedExperiment(
  assays = list(counts = matrix(c(1000L, 3L, 1L, 1000L, 1L, 2L), 3,
                                dimnames = list(c("x", "y", "z"), c("a", "b")))),
  rowData = data.frame(Kindom = "Bacteria", Phylum = "P",
     Genus = c("P_unclassified", "G", "H"), original_taxonomy = c(
       "k__Bacteria;p__P;g__;s__", "k__Bacteria;p__P;g__G;s__T", "k__Bacteria;p__P;g__H;s__U"),
     row.names = c("x", "y", "z")))
one_genus <- m16s_prepare_taxonomy(sparse, drop_unassigned = TRUE, keep_top_n = 1)
stopifnot(identical(rownames(one_genus), "G"),
          identical(unname(as.integer(SummarizedExperiment::assay(one_genus))), c(3L, 1L)))

invalid <- function(x, pattern) {
  message <- tryCatch({m16s_prepare_taxonomy(x); ""}, error = conditionMessage)
  stopifnot(grepl(pattern, message, fixed = TRUE))
}
bad <- genus
SummarizedExperiment::assay(bad)[1, 1] <- 1.5
invalid(bad, "integer counts")
large <- SummarizedExperiment::SummarizedExperiment(
  assays = list(counts = matrix(c(2000000000L, 2000000000L, 1L, 2L), 2,
                                 dimnames = list(c("x", "y"), c("a", "b")))),
  rowData = data.frame(Phylum = c("P", "P"), Genus = c("G", "G"), row.names = c("x", "y")))
invalid(large, "integer range")
cat("16S import, richness, PCoA, Genus/Phylum aggregation and invalid-count cases passed.\n")
