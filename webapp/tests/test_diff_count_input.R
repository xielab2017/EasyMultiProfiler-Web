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
