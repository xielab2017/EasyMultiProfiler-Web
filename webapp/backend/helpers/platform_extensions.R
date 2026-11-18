# A v1 manifest is data. All assay access, operations and display output belong to the host.
.ext_abort <- function(msg) stop(errorCondition(msg, class = "emp_validation_error"))
.ext_text <- function(x, max = 128L) is.character(x) && length(x) == 1L && !is.na(x) &&
  nzchar(x) && nchar(x, type = "bytes") <= max && !grepl("[[:cntrl:]]", x)
.ext_fields <- function(x, keys) {
  if (!is.list(x) || is.null(names(x)) || anyDuplicated(names(x)) || !setequal(names(x), keys))
    .ext_abort(paste("Expected fields:", paste(keys, collapse = ", ")))
}
.ext_key <- function(x) .ext_text(x, 48L) && grepl("^[a-z][a-z0-9_-]*$", x)
.ext_stats <- c("observed", "missing", "nonzero", "sum", "mean", "median", "sd", "min", "max")
.ext_check_expr <- function(x, depth = 0L) {
  if (depth > 4L) .ext_abort("Expression exceeds four nested operations")
  if (is.list(x) && !is.null(x$stat)) {
    .ext_fields(x, "stat")
    if (!.ext_text(x$stat) || !x$stat %in% .ext_stats) .ext_abort("Unsupported summary statistic")
  } else if (is.list(x) && !is.null(x$constant)) {
    .ext_fields(x, "constant")
    if (!is.numeric(x$constant) || length(x$constant) != 1L || !is.finite(x$constant)) .ext_abort("Invalid finite constant")
  } else {
    .ext_fields(x, c("op","left","right"))
    if (!.ext_text(x$op) || !x$op %in% c("add","subtract","multiply","divide")) .ext_abort("Unsupported arithmetic operation")
    .ext_check_expr(x$left, depth + 1L)
    .ext_check_expr(x$right, depth + 1L)
  }
}

emp_ext_validate <- function(m) {
  .ext_fields(m, c("abi","id","name","version","permissions","definition"))
  if (!.ext_key(m$id) || !.ext_text(m$name) || !.ext_text(m$version, 32L) ||
      !grepl("^(0|[1-9][0-9]{0,5})\\.(0|[1-9][0-9]{0,5})\\.(0|[1-9][0-9]{0,5})$", m$version)) .ext_abort("Invalid plugin identity or x.y.z version")
  if (!.ext_text(m$abi) || !m$abi %in% c("emp.analysis.v1","emp.view.v1","emp.chat-ui.v1")) .ext_abort("Unsupported plugin ABI")
  analysis <- identical(m$abi, "emp.analysis.v1")
  chat <- identical(m$abi, "emp.chat-ui.v1")
  required <- switch(m$abi, emp.analysis.v1=c("assay.read","job.result.write"),
                     emp.view.v1="job.result.read", "emp.chat-ui.v1"="chat.panel")
  if (!is.list(m$permissions) || !is.null(names(m$permissions)) || !all(vapply(m$permissions,.ext_text,logical(1))) ||
      length(m$permissions) != length(required) || !setequal(unlist(m$permissions), required)) .ext_abort("Plugin permissions do not match its ABI")
  d <- m$definition
  if (analysis) {
    .ext_fields(d, c("axis","metrics"))
    if (!.ext_text(d$axis) || !d$axis %in% c("sample","feature") || !is.list(d$metrics) ||
        !is.null(names(d$metrics)) || !length(d$metrics) || length(d$metrics) > 8L) .ext_abort("Invalid axis or metric count (1-8)")
    keys <- vapply(d$metrics, function(metric) {
      .ext_fields(metric,c("key","expression"))
      if (!.ext_key(metric$key) || identical(metric$key,"item")) .ext_abort("Invalid metric key")
      .ext_check_expr(metric$expression)
      metric$key
    }, character(1))
    if (anyDuplicated(keys)) .ext_abort("Duplicate metric keys")
  } else if (chat) {
    .ext_fields(d,c("renderer","startup"))
    if (!identical(d$renderer,"research-chat") || !.ext_text(d$startup) ||
        !d$startup %in% c("adaptive","collapsed","expanded")) .ext_abort("Unsupported chat panel or startup setting")
  } else {
    .ext_fields(d,c("input","layout","label","value","limit"))
    if (!identical(d$input,"emp.metric-table.v1") || !identical(d$label,"item") ||
        !.ext_text(d$layout) || !d$layout %in% c("table","bars") || !.ext_key(d$value) || identical(d$value,"item") ||
        !is.numeric(d$limit) || length(d$limit)!=1L || !is.finite(d$limit) || d$limit!=floor(d$limit) ||
        d$limit<1 || d$limit>200) .ext_abort("Invalid display definition")
  }
  m
}

emp_ext_parse_body <- function(raw) {
  # Allow the manifest plus its JSON envelope. The stored manifest has its own size limit.
  if (!is.character(raw) || length(raw) != 1L || nchar(raw, type="bytes") > 65536L)
    .ext_abort("Plugin request exceeds 64 KiB")
  tryCatch(jsonlite::fromJSON(raw, simplifyVector=FALSE), error=function(e) .ext_abort("Expected a valid JSON request"))
}

.ext_json <- function(x) as.character(jsonlite::toJSON(x,auto_unbox=TRUE,null="null",na="null",digits=NA))
.ext_digest <- function(x) digest::digest(.ext_json(x),algo="sha256",serialize=FALSE)
.ext_home <- function(principal) file.path(PROJECT_DIR,".plugins",digest::digest(c(emp_endpoint_id(),principal),algo="sha256"))
.ext_root <- function() Sys.getenv("EMP_PLUGIN_ROOT",unset=file.path(Sys.getenv("EMP_ROOT", unset=normalizePath(file.path(Sys.getenv("BACKEND_DIR",unset="webapp/backend"),"../.."),mustWork=FALSE)), "plugins"))
.ext_read <- function(path) {
  size <- file.info(path)$size
  if (!is.finite(size) || size<=0 || size>32768) .ext_abort("Plugin manifest exceeds 32 KiB or is empty")
  m <- emp_ext_validate(jsonlite::read_json(path,simplifyVector=FALSE))
  if (!identical(m$id,basename(dirname(path)))) .ext_abort("Plugin directory must match its id")
  m
}
.ext_scan <- function(root) {
  out <- list(); invalid <- list()
  if (dir.exists(root)) for (dir in sort(list.dirs(root,recursive=FALSE,full.names=TRUE))) {
    path <- file.path(dir, "plugin.json")
    if (!file.exists(path)) next
    res <- tryCatch(.ext_read(path),error=identity)
    if (inherits(res,"error")) invalid[[length(invalid)+1L]] <- list(id=basename(dir),reason=conditionMessage(res))
    else out[[res$id]] <- res
  }
  list(entries=out, invalid=invalid)
}

.ext_inventory <- function(principal) {
  shared <- .ext_scan(file.path(.ext_root(),"extensions"))
  personal <- .ext_scan(file.path(.ext_home(principal),"installed"))
  examples <- .ext_scan(file.path(.ext_root(),"examples"))
  # A user package cannot replace a server administrator's installed definition.
  removed <- list.files(file.path(.ext_home(principal),"removed"))
  visible_shared <- shared$entries[!names(shared$entries) %in% removed]
  list(installed=c(visible_shared,personal$entries[setdiff(names(personal$entries),names(shared$entries))]),
       shared=names(shared$entries), examples=examples$entries, invalid=c(shared$invalid,personal$invalid,examples$invalid))
}
.ext_grant <- function(principal,id) file.path(.ext_home(principal),"grants",paste0(id,".json"))
.ext_enabled <- function(principal,m) {
  path <- .ext_grant(principal,m$id)
  isTRUE(tryCatch(identical(jsonlite::read_json(path)$sha256,.ext_digest(m)),error=function(e) FALSE,warning=function(w) FALSE))
}
emp_ext_catalog <- function(principal) {
  inv <- .ext_inventory(principal)
  summary <- function(m) list(id=m$id,abi=m$abi,name=m$name,version=m$version,
    permissions=m$permissions,definition=m$definition,sha256=.ext_digest(m),enabled=.ext_enabled(principal,m))
  list(success=TRUE, abis=list("emp.analysis.v1","emp.view.v1","emp.chat-ui.v1"),
       installed=unname(lapply(inv$installed, function(m) c(summary(m),list(settings=.ext_settings(principal,m))))),
       examples=unname(lapply(inv$examples, summary)), invalid=inv$invalid)
}
.ext_defaults <- function(m) {
  if (identical(m$abi,"emp.chat-ui.v1")) return(m$definition["startup"])
  if (identical(m$abi,"emp.view.v1")) return(m$definition[c("layout","limit")])
  list(metrics=lapply(m$definition$metrics, function(metric) metric$key))
}
.ext_check_settings <- function(m, settings) {
  defaults <- .ext_defaults(m)
  .ext_fields(settings,names(defaults))
  if (identical(m$abi,"emp.chat-ui.v1")) {
    if (!.ext_text(settings$startup) || !settings$startup %in% c("adaptive","expanded","collapsed"))
      .ext_abort("Choose adaptive, expanded or collapsed")
    return(settings)
  }
  if (identical(m$abi,"emp.view.v1")) {
    if (!.ext_text(settings$layout) || !settings$layout %in% c("table","bars") ||
        !is.numeric(settings$limit) || length(settings$limit)!=1L || !is.finite(settings$limit) ||
        settings$limit!=floor(settings$limit) || settings$limit<1 || settings$limit>200)
      .ext_abort("Choose table or bars and a row limit from 1 to 200")
  } else {
    keys <- settings$metrics
    if (!is.list(keys) || !is.null(names(keys)) || !length(keys) || !all(vapply(keys,.ext_key,logical(1))) ||
        anyDuplicated(unlist(keys)) || !all(unlist(keys) %in% unlist(defaults$metrics)))
      .ext_abort("Select at least one metric declared by the analysis plugin")
    settings$metrics <- Filter(function(key) key %in% unlist(keys), defaults$metrics)
  }
  settings
}
.ext_settings_path <- function(principal,m) file.path(.ext_home(principal),"settings",paste0(m$id,".json"))
.ext_settings <- function(principal,m) {
  path <- .ext_settings_path(principal,m)
  if (file.exists(path)) {
    record <- jsonlite::read_json(path,simplifyVector=FALSE)
    if (identical(record$sha256,.ext_digest(m))) return(.ext_check_settings(m,record$settings))
  }
  .ext_defaults(m)
}
emp_ext_save_settings <- function(principal,b) {
  .ext_fields(b,c("id","sha256","settings"))
  if (!.ext_key(b$id)) .ext_abort("Invalid plugin id")
  m <- .ext_inventory(principal)$installed[[b$id]]
  if (is.null(m) || !identical(.ext_digest(m),b$sha256)) .ext_abort("Plugin changed; refresh before saving settings")
  settings <- if (is.null(b$settings)) .ext_defaults(m) else .ext_check_settings(m,b$settings)
  .emp_write_json_atomic(.ext_settings_path(principal,m),list(sha256=b$sha256,settings=settings))
  list(success=TRUE,settings=settings)
}
emp_ext_install <- function(principal,body) {
  inv <- .ext_inventory(principal)
  if (identical(names(body),"example_id")) {
    if (!.ext_key(body$example_id) || is.null(inv$examples[[body$example_id]])) .ext_abort("Unknown plugin example")
    m <- inv$examples[[body$example_id]]
  } else {
    .ext_fields(body,"manifest")
    m <- emp_ext_validate(body$manifest)
  }
  if (nchar(.ext_json(m), type="bytes") > 32768L) .ext_abort("Plugin manifest exceeds 32 KiB")
  removed <- file.path(.ext_home(principal),"removed",m$id)
  if (m$id %in% inv$shared && file.exists(removed)) {
    shared <- .ext_read(file.path(.ext_root(),"extensions",m$id,"plugin.json"))
    if (!identical(.ext_digest(m),.ext_digest(shared))) .ext_abort("A deployment plugin already owns that id")
    if (unlink(removed)!=0L) stop("Unable to restore plugin")
    return(list(success=TRUE,id=m$id,sha256=.ext_digest(m),status="installed"))
  }
  old <- inv$installed[[m$id]]
  if (!is.null(old)) {
    if (identical(.ext_digest(old),.ext_digest(m))) return(list(success=TRUE,id=m$id,sha256=.ext_digest(m),status="already_installed"))
    if (m$id %in% inv$shared) .ext_abort("A deployment plugin already owns that id")
    if (utils::compareVersion(m$version,old$version)<=0 || !identical(old$abi,m$abi)) .ext_abort("Updates require a higher version and the same ABI")
  }
  if (is.null(old) && length(inv$installed)>=128) .ext_abort("Installed plugin limit reached")
  path <- file.path(.ext_home(principal),"installed",m$id,"plugin.json")
  # Preserve full numeric definitions across reloads before calculating grants.
  dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
  tmp <- tempfile(tmpdir=dirname(path));on.exit(unlink(tmp),add=TRUE)
  writeLines(.ext_json(m),tmp,useBytes=TRUE)
  if (!file.rename(tmp,path)) stop("Unable to install plugin")
  list(success=TRUE,id=m$id,sha256=.ext_digest(m),status="installed")
}

emp_ext_uninstall <- function(principal,b) {
  .ext_fields(b,c("id","sha256"))
  if (!.ext_key(b$id) || !.ext_text(b$sha256)) .ext_abort("Invalid uninstall request")
  inv <- .ext_inventory(principal)
  m <- inv$installed[[b$id]]
  if (!is.null(m)) {
    if (!identical(b$sha256,.ext_digest(m))) .ext_abort("Plugin changed; refresh before removing")
    emp_ext_toggle(principal,list(id=m$id,sha256=b$sha256,enabled=FALSE))
    if (m$id %in% inv$shared) {
      .emp_write_json_atomic(file.path(.ext_home(principal),"removed",m$id),list(sha256=b$sha256))
    } else {
      path <- file.path(.ext_home(principal),"installed",m$id,"plugin.json")
      if (unlink(path)!=0L) stop("Unable to remove plugin")
    }
  }
  list(success=TRUE,id=b$id,status="uninstalled")
}

emp_ext_toggle <- function(principal,b) {
  .ext_fields(b,c("id","sha256","enabled"))
  if (!.ext_key(b$id) || !is.logical(b$enabled) || length(b$enabled)!=1L || is.na(b$enabled)) .ext_abort("Invalid plugin enable request")
  m <- .ext_inventory(principal)$installed[[b$id]]
  if (is.null(m) || !identical(b$sha256,.ext_digest(m))) .ext_abort("Plugin changed; refresh before enabling")
  path <- .ext_grant(principal,m$id)
  if (b$enabled) .emp_write_json_atomic(path,list(sha256=b$sha256)) else if (file.exists(path) && unlink(path)!=0L) stop("Unable to disable plugin")
  list(success=TRUE,id=m$id,enabled=b$enabled)
}

.ext_require <- function(principal,id,abi,sha256) {
  if (!.ext_key(id)) .ext_abort("Invalid plugin id")
  m <- .ext_inventory(principal)$installed[[id]]
  if (is.null(m) || !identical(m$abi,abi) || !identical(.ext_digest(m),sha256) || !.ext_enabled(principal,m))
    .ext_abort("Enable this exact plugin version before use")
  m
}

.ext_eval <- function(expr, values) {
  if (!is.null(expr$stat)) return(values[[expr$stat]])
  if (!is.null(expr$constant)) return(expr$constant)
  left <- .ext_eval(expr$left,values); right <- .ext_eval(expr$right,values)
  result <- switch(expr$op,add=left+right,subtract=left-right,multiply=left*right,divide=left/right)
  ifelse(is.finite(result),result,NA_real_)
}
.ext_leaves <- function(expr) {
  if (!is.null(expr$stat)) return(expr$stat)
  if (!is.null(expr$constant)) return(character())
  c(.ext_leaves(expr$left),.ext_leaves(expr$right))
}
emp_ext_compute <- function(manifest, matrix, experiment, assay, settings=.ext_defaults(manifest)) {
  m <- emp_ext_validate(manifest)
  settings <- .ext_check_settings(m, settings)
  metrics <- Filter(function(metric) metric$key %in% unlist(settings$metrics),m$definition$metrics)
  dim0 <- dim(matrix)
  if (length(dim0)!=2 || any(dim0<1) || prod(as.double(dim0))>1e6) .ext_abort("Plugin input must contain 1 to 1000000 cells")
  x <- as.matrix(matrix)
  if (!is.numeric(x) || any(is.infinite(x))) .ext_abort("Plugin input requires numeric data with finite measurements or NA")
  fp <- digest::digest(x, algo="sha256", serializeVersion=2)
  if (identical(m$definition$axis,"feature")) x <- t(x)
  if (ncol(x)>5000 || is.null(colnames(x)) || anyNA(colnames(x)) || any(!nzchar(colnames(x))) || anyDuplicated(colnames(x)))
    .ext_abort("Plugin result axis needs 1-5000 uniquely labelled items")
  needed <- unique(unlist(lapply(metrics,function(v) .ext_leaves(v$expression))))
  stats <- list()
  for (stat in needed) {
    stat_fn <- switch(stat,observed=function(v) sum(!is.na(v)),missing=function(v) sum(is.na(v)),
      nonzero=function(v) sum(v!=0,na.rm=TRUE),
      sum=sum,mean=mean,median=stats::median,sd=stats::sd,min=min,max=max)
    stats[[stat]] <- if (stat %in% c("observed","missing","nonzero")) apply(x,2L,stat_fn) else
      apply(x,2L,function(v) {v<-v[!is.na(v)]; if(length(v)) stat_fn(v) else NA_real_})
  }
  rows <- data.frame(item=colnames(x),stringsAsFactors=FALSE,check.names=FALSE)
  for (metric in metrics) {
    value <- .ext_eval(metric$expression,stats)
    rows[[metric$key]] <- ifelse(is.finite(value),value,NA_real_)
  }
  list(success=TRUE,contract="emp.metric-table.v1",execution_performed=TRUE,columns=as.list(names(rows)),rows=rows,
       plugin=list(id=m$id,version=m$version,abi=m$abi,sha256=.ext_digest(m),definition=m$definition,settings=settings),
       input=list(experiment=experiment,assay=assay,features=dim0[1],samples=dim0[2],sha256=fp),
       runtime=list(r_version=as.character(getRversion()),web_version=emp_web_version()))
}
.ext_job <- function(manifest,session_id,experiment,assay,on_progress,settings=.ext_defaults(manifest)) {
  on_progress(10,"Reading selected assay")
  obj <- load_empt(session_id,experiment)
  if (!assay %in% SummarizedExperiment::assayNames(obj)) .ext_abort("Selected assay no longer exists")
  mat <- SummarizedExperiment::assay(obj,assay)
  on_progress(35,"Computing registered summary")
  emp_ext_compute(manifest,mat,experiment,assay,settings)
}
emp_ext_run <- function(principal,b) {
  .ext_fields(b,c("id","sha256","session_id","experiment","assay"))
  sid <- validate_session_id(b$session_id)
  emp_assert_session_owner(sid,principal)
  m <- .ext_require(principal,b$id,"emp.analysis.v1",b$sha256)
  if (!.ext_text(b$experiment,256L) || !.ext_text(b$assay,256L) || !file.exists(mae_path(sid)) ||
      !b$experiment %in% list_experiments(sid)) .ext_abort("Select an imported experiment and assay in this session")
  id <- submit_job("analysis:plugin", .ext_job, list(manifest=m,session_id=sid,experiment=b$experiment,assay=b$assay,settings=.ext_settings(principal,m)),
                   session_id=sid,owner_id=principal)
  list(success=TRUE,job_id=id,plugin=m$id,version=m$version)
}

emp_ext_present <- function(principal,b) {
  .ext_fields(b,c("id","sha256","session_id","job_id"))
  sid <- validate_session_id(b$session_id)
  emp_assert_session_owner(sid,principal)
  m <- .ext_require(principal,b$id,"emp.view.v1",b$sha256)
  emp_assert_job_owner(b$job_id,principal)
  st <- get_job_status(b$job_id)
  if (!identical(st$session_id,sid) || !identical(st$kind,"analysis:plugin") || !identical(st$status,"done"))
    .ext_abort("A completed plugin job from the selected session is required")
  result <- get_job_result(b$job_id)
  d <- m$definition
  if (!identical(result$contract,d$input) || !is.data.frame(result$rows) || !d$value %in% names(result$rows))
    .ext_abort("This result does not supply the display plugin's required metric")
  settings <- .ext_settings(principal,m)
  rows <- head(result$rows[c(d$label,d$value)], settings$limit)
  list(success=TRUE,layout=settings$layout,metric=d$value,rows=rows,total=nrow(result$rows),job_id=b$job_id,
       view=list(id=m$id,version=m$version,sha256=.ext_digest(m)))
}
