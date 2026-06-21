# LLM-assisted R code optimization for Code Lab.
# The API key is supplied per request from the browser and is not persisted here.

.llm_chr <- function(x, default = "") {
  if (is.null(x) || length(x) < 1L) return(default)
  y <- tryCatch(as.character(x[[1L]]), error = function(e) default)
  if (is.na(y)) default else y
}

.llm_clean_base_url <- function(x) {
  x <- trimws(.llm_chr(x))
  sub("/+$", "", x)
}

.llm_remote_url <- function(cfg) {
  direct <- .llm_clean_base_url(cfg$remote_url %||% cfg$endpoint %||% "")
  if (nzchar(direct)) return(direct)
  host <- trimws(.llm_chr(cfg$remote_host %||% cfg$host))
  port <- trimws(.llm_chr(cfg$remote_port %||% cfg$port))
  path <- trimws(.llm_chr(cfg$remote_path %||% cfg$path, "/api/llm/optimize_r"))
  if (!nzchar(host)) return("")
  if (!grepl("^https?://", host, ignore.case = TRUE)) host <- paste0("http://", host)
  host <- sub("/+$", "", host)
  if (nzchar(port) && !grepl(sprintf(":%s$", port), host)) host <- paste0(host, ":", port)
  if (!startsWith(path, "/")) path <- paste0("/", path)
  paste0(host, path)
}

.llm_campus_builtin_cfg <- function() {
  list(
    base_url = Sys.getenv("EMP_CAMPUS_LLM_URL", "http://10.22.18.12:9901/v1"),
    api_key = Sys.getenv("EMP_CAMPUS_LLM_API_KEY", unset = ""),
    models = list(
      fast = "deepseek-v4-flash",
      accurate = "Qwen3.6-35B-A3B",
      vision = "Qwen3-VL-8B-Instruct",
      embedding = "Qwen-embedding"
    )
  )
}

.llm_campus_merge_cfg <- function(cfg) {
  builtin <- .llm_campus_builtin_cfg()
  cfg <- cfg %||% list()
  if (!nzchar(trimws(.llm_chr(cfg$base_url)))) cfg$base_url <- builtin$base_url
  if (!nzchar(trimws(.llm_chr(cfg$api_key)))) cfg$api_key <- builtin$api_key
  cfg
}

.llm_campus_task_models <- function(task, cfg) {
  builtin <- .llm_campus_builtin_cfg()
  models <- cfg$campus_models %||% list()
  task <- tolower(trimws(.llm_chr(task, "code_optimize")))
  pick <- function(nm, fallback) {
    x <- trimws(.llm_chr(models[[nm]] %||% builtin$models[[nm]] %||% fallback))
    if (nzchar(x)) x else fallback
  }
  switch(task,
    code_optimize = c(pick("fast", "deepseek-v4-flash"), pick("accurate", "Qwen3.6-35B-A3B")),
    vision = c(pick("vision", "Qwen3-VL-8B-Instruct")),
    embedding = c(pick("embedding", "Qwen-embedding")),
    complex = c(pick("accurate", "Qwen3.6-35B-A3B"), pick("fast", "deepseek-v4-flash")),
    c(pick("fast", "deepseek-v4-flash"), pick("accurate", "Qwen3.6-35B-A3B"))
  )
}

.llm_campus_optimize_once <- function(cfg, model, code, workflow, tab, instruction, ui_context = NULL) {
  cfg <- .llm_campus_merge_cfg(cfg)
  cfg$model <- model
  if (is.null(cfg$timeout) || !is.finite(suppressWarnings(as.numeric(cfg$timeout)))) {
    cfg$timeout <- 8
  }
  .llm_optimize_once("campus", cfg, code, workflow, tab, instruction, ui_context)
}

.llm_campus_optimize <- function(cfg, code, workflow = NULL, tab = NULL, instruction = NULL, ui_context = NULL) {
  cfg <- .llm_campus_merge_cfg(cfg)
  task <- tolower(trimws(.llm_chr(cfg$task_type %||% cfg$task, "code_optimize")))
  models <- unique(.llm_campus_task_models(task, cfg))
  explicit <- trimws(.llm_chr(cfg$model))
  if (nzchar(explicit) && !tolower(explicit) %in% c("mixed", "auto", "混合", "mix")) {
    models <- unique(c(explicit, models))
  }
  errors <- character(0)
  conn_fails <- 0L
  for (model in models) {
    if (!nzchar(model)) next
    aliases <- unique(c(.llm_model_aliases(model), model))
    if (length(aliases) > 3L) aliases <- aliases[seq_len(3L)]
    for (model_try in aliases) {
      out <- tryCatch(
        .llm_campus_optimize_once(cfg, model_try, code, workflow, tab, instruction %||% "", ui_context),
        error = function(e) {
          msg <- conditionMessage(e)
          errors <<- c(errors, sprintf("%s: %s", model_try, msg))
          if (grepl("timed out|connection refused|empty reply|url error|couldn't connect",
                    msg, ignore.case = TRUE)) {
            conn_fails <<- conn_fails + 1L
          }
          NULL
        }
      )
      if (is.character(out) && nzchar(trimws(out))) {
        return(list(
          success = TRUE,
          provider = paste0("campus:", model_try),
          model = model_try,
          task_type = task,
          optimized_code = out,
          errors = errors
        ))
      }
      if (conn_fails >= 2L) break
    }
    if (conn_fails >= 2L) break
  }
  stop(paste(c("Campus LLM models failed.", errors), collapse = "\n"))
}

.llm_provider_defaults <- function(provider, cfg) {
  provider <- tolower(trimws(.llm_chr(provider, "chatgpt")))
  model <- trimws(.llm_chr(cfg$model))
  base_url <- .llm_clean_base_url(cfg$base_url)
  campus_builtin <- .llm_campus_builtin_cfg()
  list(
    provider = provider,
    base_url = switch(provider,
      deepseek = if (nzchar(base_url)) base_url else "https://api.deepseek.com",
      qwen = if (nzchar(base_url)) base_url else "https://dashscope.aliyuncs.com/compatible-mode/v1",
      minimax = if (nzchar(base_url)) base_url else "https://api.minimax.chat/v1",
      gemini = if (nzchar(base_url)) base_url else "https://generativelanguage.googleapis.com/v1beta",
      claude = if (nzchar(base_url)) base_url else "https://api.anthropic.com/v1",
      chatgpt = if (nzchar(base_url)) base_url else "https://api.openai.com/v1",
      openai = if (nzchar(base_url)) base_url else "https://api.openai.com/v1",
      campus = if (nzchar(base_url)) base_url else campus_builtin$base_url,
      custom = base_url,
      remote = .llm_remote_url(cfg),
      base_url
    ),
    model = switch(provider,
      deepseek = if (nzchar(model)) model else "deepseek-chat",
      qwen = if (nzchar(model)) model else "qwen-plus",
      minimax = if (nzchar(model)) model else "MiniMax-Text-01",
      gemini = if (nzchar(model)) model else "gemini-1.5-pro",
      claude = if (nzchar(model)) model else "claude-3-5-sonnet-latest",
      chatgpt = if (nzchar(model)) model else "gpt-4o-mini",
      openai = if (nzchar(model)) model else "gpt-4o-mini",
      campus = if (nzchar(model)) model else campus_builtin$models$fast,
      model
    )
  )
}

.llm_extract_text <- function(x) {
  if (is.null(x)) return("")
  if (is.character(x) && length(x) >= 1L) return(paste(x, collapse = "\n"))
  if (is.data.frame(x)) x <- lapply(x, as.list)
  for (nm in c("optimized_code", "code", "text", "content", "output", "result")) {
    if (!is.null(x[[nm]])) {
      y <- .llm_extract_text(x[[nm]])
      if (nzchar(y)) return(y)
    }
  }
  if (!is.null(x$choices) && length(x$choices) >= 1L) {
    choice <- x$choices[[1L]]
    y <- .llm_extract_text(choice$message$content %||% choice$message$reasoning_content %||% choice$text)
    if (nzchar(y)) return(y)
  }
  if (!is.null(x$content) && is.list(x$content)) {
    ys <- vapply(x$content, function(part) .llm_chr(part$text), character(1))
    y <- paste(ys[nzchar(ys)], collapse = "\n")
    if (nzchar(y)) return(y)
  }
  if (!is.null(x$candidates) && length(x$candidates) >= 1L) {
    parts <- x$candidates[[1L]]$content$parts
    if (length(parts)) {
      ys <- vapply(parts, function(part) .llm_chr(part$text), character(1))
      y <- paste(ys[nzchar(ys)], collapse = "\n")
      if (nzchar(y)) return(y)
    }
  }
  ""
}

.llm_extract_r_code <- function(text) {
  text <- paste(as.character(text), collapse = "\n")
  m <- regmatches(text, regexpr("```[rR]?\\s*\\n[\\s\\S]*?```", text, perl = TRUE))
  if (length(m) && nzchar(m[[1L]])) {
    text <- sub("^```[rR]?\\s*\\n", "", m[[1L]], perl = TRUE)
    text <- sub("\\n```$", "", text, perl = TRUE)
  }
  text <- gsub("^```[rR]?\\s*|```$", "", text, perl = TRUE)
  trimws(text)
}

.llm_pure_r_or_stop <- function(text) {
  code <- .llm_extract_r_code(text)
  if (!nzchar(trimws(code))) stop("LLM returned empty code")
  tryCatch(parse(text = code), error = function(e) {
    stop(sprintf("LLM returned non-parseable R code: %s", conditionMessage(e)))
  })
  code
}

.llm_prompt <- function(code, workflow, tab, instruction, ui_context = NULL) {
  ctx_lines <- character(0)
  if (!is.null(ui_context) && length(ui_context)) {
    ctx_lines <- vapply(names(ui_context), function(k) {
      paste0("- ", k, ": ", paste(as.character(ui_context[[k]]), collapse = ", "))
    }, character(1))
  }
  paste(
    "You are an expert bioinformatics engineer optimizing EasyMultiProfiler Code Lab R scripts.",
    "Return ONLY executable R code, with no markdown fences and no explanation.",
    "Preserve the student's analysis intent; make minimal, high-impact edits unless asked to refactor.",
    "The returned code must be pure R and compatible with POST /api/user_r/run.",
    "Do not use JavaScript, browser APIs, Python, shell commands, network calls, or package installation.",
    "Keep session_id and experiment (character name) available; do not replace with phyloseq objects.",
    "For publication-quality plots use emp_pub_theme(), emp_pub_palette(), emp_set_color_panel() from EasyMultiProfiler.",
    "Prefer ggrepel for crowded labels; ensure axis titles, legend, and readable base_size (10-12).",
    "If producing a plot, make the last expression a ggplot object, a base64 PNG string, or list(plot = <base64_png>).",
    "For clinical standalone: use run_clinical_systematic_summary() and cohort_filter; do not manually read CSVs.",
    sprintf("Workflow: %s; Tab: %s.", .llm_chr(workflow, "unknown"), .llm_chr(tab, "unknown")),
    if (length(ctx_lines)) paste("Current UI / analysis context:\n", paste(ctx_lines, collapse = "\n")) else "",
    if (nzchar(trimws(.llm_chr(instruction)))) paste("User instruction:", instruction) else "",
    "Original R code:",
    code,
    sep = "\n\n"
  )
}

.llm_normalize_openai_base <- function(base_url) {
  b <- .llm_clean_base_url(base_url)
  if (!nzchar(b)) return("")
  b
}

.llm_chat_completion_urls <- function(base_url) {
  b <- .llm_normalize_openai_base(base_url)
  if (!nzchar(b)) return(character(0))
  root <- sub("/v1$", "", b, ignore.case = TRUE)
  unique(c(
    paste0(b, "/chat/completions"),
    paste0(root, "/v1/chat/completions"),
    paste0(root, "/api/v1/chat/completions")
  ))
}

.llm_model_aliases <- function(model) {
  m <- tolower(trimws(.llm_chr(model)))
  if (!nzchar(m) || m %in% c("mixed", "auto", "mix", "混合")) return(character(0))
  table <- list(
    "deepseek-v4-flash" = c("deepseek-v4-flash", "deepseek-chat", "DeepSeek-V3", "deepseek-reasoner"),
    "deepseek-chat" = c("deepseek-chat", "deepseek-v4-flash", "DeepSeek-V3"),
    "qwen3.6-35b-a3b" = c("Qwen3.6-35B-A3B", "qwen-plus", "qwen-max", "Qwen2.5-72B-Instruct"),
    "qwen3-vl-8b-instruct" = c("Qwen3-VL-8B-Instruct", "qwen-vl-plus", "qwen-vl-max"),
    "qwen-embedding" = c("Qwen-embedding", "text-embedding-v3", "qwen-embedding")
  )
  hits <- unique(c(model, table[[m]] %||% character(0)))
  hits[nzchar(hits)]
}

.llm_auth_headers <- function(key, provider = NULL) {
  key <- trimws(.llm_chr(key))
  if (!nzchar(key)) return(character(0))
  c(paste0("Authorization: Bearer ", key))
}

.llm_format_http_error <- function(url, py_err = "", curl_err = "", status = NULL) {
  msg <- character(0)
  if (!is.null(status) && is.finite(status)) {
    msg <- c(msg, sprintf("HTTP %s from LLM endpoint", as.integer(status)))
  }
  if (nzchar(py_err)) {
    if (grepl("HTTP Error 404", py_err, fixed = TRUE)) {
      msg <- c(msg, "Endpoint or model not found (404). Check Base URL and Model name in Code Lab LLM settings.")
    } else if (grepl("HTTP Error 401|403", py_err, perl = TRUE)) {
      msg <- c(msg, "Authentication failed. Check API Key.")
    } else {
      msg <- c(msg, sub("\\s+", " ", gsub("Traceback.*", "", py_err, perl = TRUE)))
    }
  }
  if (nzchar(curl_err)) msg <- c(msg, curl_err)
  if (nzchar(url)) msg <- c(msg, sprintf("URL: %s", url))
  paste(msg[nzchar(msg)], collapse = " | ")
}

.llm_local_optimize_r <- function(code, workflow = NULL, tab = NULL, instruction = NULL) {
  out <- paste(as.character(code), collapse = "\n")
  if (!nzchar(trimws(out))) return("")
  inst <- tolower(paste(instruction %||% "", collapse = " "))

  if (grepl("ggplot\\(", out) && !grepl("emp_pub_theme\\(", out)) {
    out <- sub(
      "\\)\\s*$",
      " +\n  emp_pub_theme(base_size = 11))",
      trimws(out),
      perl = TRUE
    )
  }
  if (grepl("scale_fill_gradient|scale_color_", out) && !grepl("emp_pub_palette|emp_scale_fill_pub|emp_diverging_colors", out)) {
    out <- paste0(
      "# Local polish: prefer emp_pub_palette() / emp_diverging_colors() for publication colors.\n",
      out
    )
  }
  if (grepl("散点|边际|marginal|layer|立体|双层", inst)) {
    out <- paste0(
      "# Note: make_scatter() already adds layered points + marginal axis stats when >=2 groups.\n",
      out
    )
  }
  header <- "# Local rule-based polish (LLM unreachable). Review before running.\n"
  if (!grepl("^# Local rule-based polish", out)) out <- paste0(header, out)
  tryCatch({ parse(text = out); out }, error = function(e) code)
}

.llm_call_curl <- function(url, headers, body, timeout = 120) {
  if (!nzchar(url)) stop("LLM endpoint/base_url is required")
  body_file <- tempfile(fileext = ".json")
  out_file <- tempfile(fileext = ".json")
  err_file <- tempfile(fileext = ".log")
  req_file <- tempfile(fileext = ".json")
  py_file <- tempfile(fileext = ".py")
  on.exit(unlink(c(body_file, out_file, err_file, req_file, py_file), force = TRUE), add = TRUE)
  writeLines(jsonlite::toJSON(body, auto_unbox = TRUE, null = "null"), body_file, useBytes = TRUE)
  headers <- unname(as.character(headers))
  headers <- headers[nzchar(headers)]
  writeLines(jsonlite::toJSON(list(url = url, headers = headers, body_file = body_file, timeout = timeout),
                              auto_unbox = TRUE, null = "null"), req_file, useBytes = TRUE)
  env <- c(
    "http_proxy=", "https_proxy=", "HTTP_PROXY=", "HTTPS_PROXY=",
    "all_proxy=", "ALL_PROXY=", "NO_PROXY=*", "no_proxy=*"
  )
  py <- Sys.which("python")
  if (!nzchar(py)) py <- Sys.which("python3")
  if (nzchar(py)) {
    writeLines(c(
      "import json, sys, urllib.request",
      "cfg = json.load(open(sys.argv[1], 'r', encoding='utf-8'))",
      "headers = {'Content-Type': 'application/json'}",
      "extra_headers = cfg.get('headers') or []",
      "if isinstance(extra_headers, str):",
      "    extra_headers = [extra_headers]",
      "for h in extra_headers:",
      "    if ':' in h:",
      "        k, v = h.split(':', 1)",
      "        k = k.strip()",
      "        if k:",
      "            headers[k] = v.strip()",
      "data = open(cfg['body_file'], 'rb').read()",
      "req = urllib.request.Request(cfg['url'], data=data, headers=headers, method='POST')",
      "try:",
      "    with urllib.request.urlopen(req, timeout=float(cfg.get('timeout') or 120)) as resp:",
      "        sys.stdout.write(resp.read().decode('utf-8', 'replace'))",
      "except urllib.error.HTTPError as e:",
      "    body = e.read().decode('utf-8', 'replace') if hasattr(e, 'read') else ''",
      "    sys.stderr.write('HTTP Error %s: %s\\n%s' % (e.code, e.reason, body[:500]))",
      "    sys.exit(int(e.code) if e.code else 1)",
      "except urllib.error.URLError as e:",
      "    sys.stderr.write('URL Error: %s' % e.reason)",
      "    sys.exit(1)"
    ), py_file, useBytes = TRUE)
    status <- system2(py, c(py_file, req_file), stdout = out_file, stderr = err_file, env = env)
    err <- paste(readLines(err_file, warn = FALSE), collapse = "\n")
    txt <- paste(readLines(out_file, warn = FALSE), collapse = "\n")
    if (identical(status, 0L) && nzchar(txt)) {
      parsed <- tryCatch(
        jsonlite::fromJSON(txt, simplifyVector = FALSE, simplifyDataFrame = FALSE, simplifyMatrix = FALSE),
        error = function(e) NULL
      )
      if (is.null(parsed)) return(list(raw_text = txt))
      return(parsed)
    }
    if (nzchar(err)) {
      py_err <- err
      if (grepl("HTTP Error [45]\\d\\d", err, perl = TRUE)) {
        stop(.llm_format_http_error(url, py_err = py_err, curl_err = "", status = NULL))
      }
      stop(.llm_format_http_error(url, py_err = py_err, curl_err = "", status = NULL))
    } else {
      py_err <- sprintf("python exited with status %s", status)
      stop(.llm_format_http_error(url, py_err = py_err, curl_err = "", status = NULL))
    }
  } else {
    py_err <- "python/python3 not found"
  }

  if (!nzchar(Sys.which("curl"))) {
    stop(.llm_format_http_error(url, py_err = py_err, curl_err = "", status = NULL))
  }
  args <- c(
    "-q", "-f", "-sS", "--http1.1", "--noproxy", "*",
    "--max-time", as.character(timeout), "-X", "POST",
    "-H", "Content-Type: application/json"
  )
  if (length(headers)) {
    for (h in headers) args <- c(args, "-H", h)
  }
  args <- c(args, "--data-binary", paste0("@", body_file), url)
  status <- system2("curl", args, stdout = out_file, stderr = err_file, env = env)
  err <- paste(readLines(err_file, warn = FALSE), collapse = "\n")
  txt <- paste(readLines(out_file, warn = FALSE), collapse = "\n")
  if (!identical(status, 0L)) {
    stop(.llm_format_http_error(url, py_err = py_err, curl_err = err, status = status))
  }
  if (!nzchar(txt)) stop("LLM response is empty")
  parsed <- tryCatch(
    jsonlite::fromJSON(txt, simplifyVector = FALSE, simplifyDataFrame = FALSE, simplifyMatrix = FALSE),
    error = function(e) NULL
  )
  if (is.null(parsed)) return(list(raw_text = txt))
  parsed
}

.llm_openai_chat_call <- function(base_url, model, key, prompt, cfg, timeout = 120,
                                   provider = "openai") {
  urls <- .llm_chat_completion_urls(base_url)
  if (!length(urls)) stop("LLM base_url is empty or invalid")
  if (identical(provider, "campus") && length(urls) > 1L) urls <- urls[1L]
  body <- list(
    model = model,
    messages = list(
      list(role = "system", content = "Return only pure executable R code."),
      list(role = "user", content = prompt)
    ),
    max_tokens = as.integer(cfg$max_tokens %||% 4096L),
    temperature = suppressWarnings(as.numeric(cfg$temperature %||% 0.2))
  )
  headers <- .llm_auth_headers(key, provider)
  errors <- character(0)
  for (url in urls) {
    resp <- tryCatch(
      .llm_call_curl(url, headers, body, timeout),
      error = function(e) {
        errors <<- c(errors, conditionMessage(e))
        NULL
      }
    )
    if (!is.null(resp)) {
      txt <- .llm_extract_text(resp)
      if (nzchar(trimws(txt))) return(.llm_pure_r_or_stop(txt))
    }
  }
  stop(paste(c("OpenAI-compatible chat/completions failed.", errors), collapse = "\n"))
}

.llm_optimize_once <- function(provider, cfg, code, workflow, tab, instruction, ui_context = NULL) {
  if (identical(tolower(trimws(.llm_chr(provider))), "campus")) {
    cfg <- .llm_campus_merge_cfg(cfg)
  }
  d <- .llm_provider_defaults(provider, cfg)
  provider <- d$provider
  prompt <- .llm_prompt(code, workflow, tab, instruction, ui_context)
  key <- trimws(.llm_chr(cfg$api_key))
  timeout <- suppressWarnings(as.numeric(cfg$timeout %||% 120))
  if (is.na(timeout) || timeout <= 0) timeout <- 120

  if (identical(provider, "remote")) {
    body <- list(
      provider = cfg$remote_provider %||% "auto",
      model = d$model,
      source_code = code,
      workflow = workflow,
      tab = tab,
      instruction = instruction,
      prompt = prompt
    )
    resp <- .llm_call_curl(d$base_url, character(0), body, timeout)
    return(.llm_pure_r_or_stop(.llm_extract_text(resp$raw_text %||% resp)))
  }

  needs_key <- !provider %in% c("campus", "custom")
  if (needs_key && !nzchar(key)) stop(sprintf("API key required for provider: %s", provider))
  if (provider %in% c("chatgpt", "openai", "deepseek", "qwen", "minimax", "custom", "campus")) {
    return(.llm_openai_chat_call(
      d$base_url, d$model, key, prompt, cfg, timeout, provider = provider
    ))
  }
  if (identical(provider, "claude")) {
    url <- paste0(d$base_url, "/messages")
    body <- list(
      model = d$model,
      max_tokens = as.integer(cfg$max_tokens %||% 4096L),
      temperature = suppressWarnings(as.numeric(cfg$temperature %||% 0.2)),
      messages = list(list(role = "user", content = prompt))
    )
    headers <- c(paste0("x-api-key: ", key), "anthropic-version: 2023-06-01")
    resp <- .llm_call_curl(url, headers, body, timeout)
    return(.llm_pure_r_or_stop(.llm_extract_text(resp)))
  }
  if (identical(provider, "gemini")) {
    url <- paste0(d$base_url, "/models/", utils::URLencode(d$model, reserved = TRUE), ":generateContent?key=", utils::URLencode(key, reserved = TRUE))
    body <- list(contents = list(list(parts = list(list(text = prompt)))))
    resp <- .llm_call_curl(url, character(0), body, timeout)
    return(.llm_pure_r_or_stop(.llm_extract_text(resp)))
  }
  stop(sprintf("Unsupported LLM provider: %s", provider))
}

optimize_r_with_llm <- function(provider, cfg, code, workflow = NULL, tab = NULL, instruction = NULL, ui_context = NULL) {
  code <- paste(as.character(code), collapse = "\n")
  if (!nzchar(trimws(code))) stop("source_code is empty")
  provider <- tolower(trimws(.llm_chr(provider, "chatgpt")))
  cfg <- cfg %||% list()
  errors <- character(0)
  result <- tryCatch({
    if (identical(provider, "campus")) {
      return(.llm_campus_optimize(cfg, code, workflow, tab, instruction, ui_context))
    }
    providers <- cfg$providers %||% provider
    if (identical(provider, "auto")) {
      providers <- unlist(providers, use.names = FALSE)
      providers <- providers[nzchar(providers)]
      if (!length(providers)) {
        providers <- c("campus", "deepseek", "qwen", "chatgpt", "claude", "gemini", "minimax")
      }
    } else {
      providers <- provider
    }
    for (p in providers) {
      out <- tryCatch(
        .llm_optimize_once(p, cfg, code, workflow, tab, instruction %||% "", ui_context),
        error = function(e) {
          errors <<- c(errors, sprintf("%s: %s", p, conditionMessage(e)))
          NULL
        }
      )
      if (is.character(out) && nzchar(trimws(out))) {
        return(list(success = TRUE, provider = p, optimized_code = out, errors = errors))
      }
    }
    stop(paste(c("All LLM providers failed.", errors), collapse = "\n"))
  }, error = function(e) {
    errors <<- c(errors, conditionMessage(e))
    NULL
  })

  if (!is.null(result) && is.list(result) && isTRUE(result$success)) return(result)

  local <- .llm_local_optimize_r(code, workflow, tab, instruction)
  if (nzchar(trimws(local)) && !identical(trimws(local), trimws(code))) {
    return(list(
      success = TRUE,
      provider = "local_rules",
      optimized_code = local,
      errors = errors,
      fallback = TRUE
    ))
  }
  stop(paste(c("All LLM providers failed and local polish could not improve the script.", errors),
             collapse = "\n"))
}

plumber_llm_optimize_r_post <- function(req, res) {
  safe_api({ # nolint: object_usage_linter
    b <- jsonlite::fromJSON(req$postBody, simplifyVector = FALSE)
    cfg <- b$config %||% list()
    optimize_r_with_llm(
      provider = b$provider %||% cfg$provider %||% "chatgpt",
      cfg = cfg,
      code = b$source_code %||% b$code %||% "",
      workflow = b$workflow %||% NULL,
      tab = b$tab %||% NULL,
      instruction = b$instruction %||% NULL,
      ui_context = b$ui_context %||% NULL
    )
  }, res)
}
