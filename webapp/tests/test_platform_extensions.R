# Run from the repository root with its normal R library on R_LIBS.
source("webapp/backend/helpers/utils.R")
source("webapp/backend/helpers/platform_extensions.R")
analysis <- .ext_read("plugins/examples/sample-quality/plugin.json")
view <- .ext_read("plugins/examples/quality-bars/plugin.json")
invalid <- function(expr) {
  caught <- tryCatch({force(expr); FALSE}, emp_validation_error = function(e) TRUE)
  stopifnot(caught)
}
bad <- analysis
bad$permissions <- c(bad$permissions, list("external_network"))
invalid(emp_ext_validate(bad))
bad <- analysis
bad$definition$metrics[[2]]$key <- bad$definition$metrics[[1]]$key
invalid(emp_ext_validate(bad))
bad <- view
bad$definition$limit <- 201
invalid(emp_ext_validate(bad))
bad <- view
bad$definition$script <- "extra field"
invalid(emp_ext_validate(bad))
deep <- list(stat="mean")
for (i in seq_len(5L)) deep <- list(op="add", left=deep, right=list(constant=1))
invalid(.ext_check_expr(deep))
invalid(emp_ext_parse_body('{"broken":'))
stopifnot(identical(emp_ext_parse_body(.ext_json(analysis)), analysis))

# Two samples and three features with a fully missing feature, partial input and a zero denominator.
mat <- matrix(c(NA, 1, -3, NA, NA, 3), nrow=3, dimnames=list(c("all_missing","partial","centered"),c("A","B")))
analysis$definition$axis <- "feature"
rows <- emp_ext_compute(analysis,mat,"fixture","counts")$rows
stopifnot(identical(rows$item, rownames(mat)),
          identical(as.numeric(rows$observed), c(0,1,2)),
          identical(as.numeric(rows$missing), c(2,1,0)),
          is.na(rows$mean[1]), is.na(rows$sd[2]), rows$mean[3]==0, is.na(rows$cv[3]))
invalid(emp_ext_compute(analysis, matrix(0, 1001L, 1000L), "fixture", "counts"))
bad_mat <- mat
bad_mat[1] <- Inf
invalid(emp_ext_compute(analysis,bad_mat,"fixture","counts"))
bad_mat <- mat
rownames(bad_mat)[2] <- rownames(bad_mat)[1]
invalid(emp_ext_compute(analysis,bad_mat,"fixture","counts"))

# An author may define a constant indicator independently of summary statistics.
analysis$definition$metrics <- list(list(key="constant", expression=list(constant=2)))
constant <- emp_ext_compute(analysis,mat,"fixture","counts")
stopifnot(identical(unname(constant$rows$constant), rep(2,3)),
          identical(constant$columns, list("item","constant")),
          identical(constant$plugin$sha256,.ext_digest(analysis)))
cat("PASS manifest schema, capability and expression limits, missing data, bound checks and stable provenance\n")

chat <- .ext_read("plugins/examples/zotero-style-chat/plugin.json")
stopifnot(identical(.ext_defaults(chat), list(startup="adaptive")))
invalid(.ext_check_settings(chat,list(startup="unknown")))
chat$definition$renderer <- "external"
invalid(emp_ext_validate(chat))
