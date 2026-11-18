suppressPackageStartupMessages(library(SummarizedExperiment))
source("webapp/backend/helpers/analysis.R")
counts <- matrix(as.numeric(1:24), 4, dimnames = list(paste0("g", 1:4), paste0("s", 1:6)))
raw <- SummarizedExperiment(assays = list(counts = counts))
selected <- raw[c("g3", "g1"), c("s5", "s2", "s4")]
colData(selected)$group <- c("B", "A", "B")
assay(selected) <- log2(assay(selected)) - 4
original <- selected
recovered <- .diff_count_input(selected, raw)
stopifnot(recovered$recovered, recovered$source == "original_import_counts",
          identical(assay(recovered$empt), counts[c("g3", "g1"), c("s5", "s2", "s4")]),
          identical(colData(recovered$empt), colData(original)),
          identical(assay(selected), assay(original)),
          identical(assay(raw), counts))
valid <- .diff_count_input(raw)
stopifnot(valid$source == "current_counts", identical(valid$empt, raw))
reject <- function(candidate) stopifnot(inherits(try(.diff_count_input(selected, candidate), silent = TRUE), "try-error"))
reject(NULL)
reject(raw[-3, ])
reject(raw[, -5])
fractional <- raw; assay(fractional) <- assay(fractional) / 10
reject(fractional)
negative <- raw; assay(negative)[3, 5] <- -1
reject(negative)
missing <- raw; assay(missing)[3, 5] <- NA_real_
reject(missing)
duplicated <- raw; rownames(duplicated)[2] <- rownames(duplicated)[1]
reject(duplicated)
cat("Count recovery passed: exact ID alignment, preserved annotations and exclusions, invalid snapshots blocked.\n")

# This legacy exact-test path is used for all-pairwise comparisons; the
# count workbench has a separate edgeR quasi-likelihood executor.
set.seed(43)
labels <- factor(rep(c("Control", "Treatment B"), each = 3))
expr <- matrix(rnbinom(240 * 6, size = 4, mu = 80), nrow = 240,
               dimnames = list(paste0("g", 1:240), paste0("s", 1:6)))
expr[1:15, 4:6] <- expr[1:15, 4:6] * 8L
dataset <- SummarizedExperiment(assays = list(counts = expr), colData = S4Vectors::DataFrame(group = labels))
native <- edgeR::DGEList(counts = expr, group = labels)
native <- edgeR::estimateDisp(edgeR::calcNormFactors(native))
for (pair in list(levels(labels), rev(levels(labels)))) {
  expected <- edgeR::topTags(edgeR::exactTest(native, pair = pair), n = Inf, sort.by = "none")$table
  actual <- .diff_native_edger_pairwise(dataset, "group", pair[1], pair[2], filter_low = FALSE)
  stopifnot(identical(actual$feature, rownames(expected)),
            isTRUE(all.equal(actual$log2FC, expected$logFC, tolerance = 1e-12)),
            isTRUE(all.equal(actual$fdr, expected$FDR, tolerance = 1e-12)),
            isTRUE(all.equal(actual$pvalue, expected$PValue, tolerance = 1e-12)))
}
# Package-provided missing adjusted P values (e.g. DESeq2 independent
# filtering) must survive formatting, including when a raw P value exists.
compact <- .diff_format_native_result(c("g1", "g2"), "group", "DESeq2", "T vs C",
                                      c(.03, .01), c(1, -1), padj = c(NA_real_, .04))
stopifnot(identical(compact$fdr, c(NA_real_, .04)))
cat("Native differential tables preserve edgeR contrast direction and missing package-adjusted P values.\n")
