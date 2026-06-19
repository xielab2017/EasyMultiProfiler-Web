# AI analysis copilot: interpret results and suggest next steps for students.
#
# Two layers:
#   1. LLM layer  - reuses the multi-provider machinery in llm.R to produce a
#                   rich, teaching-oriented interpretation when an API key is
#                   configured (or the campus gateway is reachable).
#   2. Offline    - a deterministic, domain-aware generator that always returns
#                   a useful interpretation, so the feature works even with no
#                   network / no key. The LLM layer falls back to this on error.
#
# The frontend posts a compact "context" describing the current analysis so we
# never need to re-run anything heavy here.

# Relies on the global `%||%` (NULL/length-0 coalesce) defined in utils.R,
# which is sourced before this file.

.ai_chr <- function(x, default = "") {
  if (is.null(x) || length(x) < 1L) return(default)
  y <- tryCatch(as.character(x[[1L]]), error = function(e) default)
  if (length(y) < 1L || is.na(y)) default else y
}

.ai_num <- function(x, default = NA_real_) {
  y <- suppressWarnings(as.numeric(x))
  if (length(y) < 1L || is.na(y[1L])) default else y[1L]
}

# Friendly Chinese labels for analysis / omics types.
.ai_analysis_label <- function(t) {
  t <- tolower(trimws(.ai_chr(t)))
  map <- c(
    differential = "差异分析", diff = "差异分析", volcano = "火山图（差异分析）",
    alpha = "Alpha 多样性", dimension = "降维 / 排序 (PCA/PCoA)", scatter = "排序散点 (PCA/PCoA)",
    correlation = "相关性分析", cluster = "聚类分析", marker = "生物标志物 (机器学习)",
    enrichment = "功能富集 (KEGG/GO)", network = "共现网络", heatmap = "热图",
    boxplot = "箱线图", barplot = "组成柱状图", structure = "群落组成",
    clinical_cor = "临床-特征相关", fitline = "拟合回归", three_line = "基线三线表",
    marker_model = "多组学诊断模型", wgcna = "WGCNA 模块-性状"
  )
  unname(map[t]) %||% (.ai_chr(t, "分析"))
}

.ai_omics_label <- function(o) {
  o <- tolower(trimws(.ai_chr(o)))
  map <- c(
    rnaseq = "转录组 (RNA-seq)", transcriptomics = "转录组 (RNA-seq)",
    microbiome_16s = "16S 微生物组", m16s = "16S 微生物组", "16s" = "16S 微生物组",
    metagenomics = "宏基因组", mgx = "宏基因组",
    metabolomics = "代谢组", mbx = "代谢组",
    clinical = "临床表型", normal = "通用组学"
  )
  unname(map[o]) %||% (.ai_chr(o, "组学数据"))
}

# Build a compact textual summary of the result context (used both for the LLM
# prompt and as the backbone of the offline interpretation).
.ai_summarise_context <- function(ctx) {
  lines <- character(0)
  add <- function(...) lines[[length(lines) + 1L]] <<- paste0(...)

  atype <- .ai_chr(ctx$analysis_type, "analysis")
  add("分析类型: ", .ai_analysis_label(atype))
  if (!is.null(ctx$omics)) add("组学: ", .ai_omics_label(ctx$omics))
  if (!is.null(ctx$experiment)) add("实验对象: ", .ai_chr(ctx$experiment))

  ds <- ctx$dataset %||% list()
  if (!is.null(ds$n_samples)) add("样本数: ", .ai_chr(ds$n_samples))
  if (!is.null(ds$n_features)) add("特征数: ", .ai_chr(ds$n_features))
  if (!is.null(ctx$group)) add("分组变量: ", .ai_chr(ctx$group))
  if (!is.null(ctx$groups)) add("组别: ", paste(as.character(unlist(ctx$groups)), collapse = " vs "))

  params <- ctx$params %||% list()
  if (length(params)) {
    pv <- vapply(names(params), function(k) paste0(k, "=", .ai_chr(params[[k]])), character(1))
    add("参数: ", paste(pv, collapse = ", "))
  }

  st <- ctx$stats %||% list()
  if (length(st)) {
    sv <- vapply(names(st), function(k) paste0(k, "=", .ai_chr(st[[k]])), character(1))
    add("关键统计量: ", paste(sv, collapse = ", "))
  }

  tbl <- ctx$table %||% list()
  if (!is.null(tbl$columns)) add("结果表列: ", paste(as.character(unlist(tbl$columns)), collapse = ", "))
  if (!is.null(tbl$n_rows)) add("结果行数: ", .ai_chr(tbl$n_rows))
  rows <- tbl$rows %||% NULL
  if (!is.null(rows) && length(rows)) {
    add("前若干行预览:")
    nshow <- min(length(rows), 8L)
    for (i in seq_len(nshow)) {
      r <- rows[[i]]
      if (is.list(r)) {
        kv <- vapply(names(r), function(k) paste0(k, "=", .ai_chr(r[[k]])), character(1))
        add("  - ", paste(kv, collapse = ", "))
      } else {
        add("  - ", paste(as.character(unlist(r)), collapse = ", "))
      }
    }
  }
  paste(lines, collapse = "\n")
}

# ---------------------------------------------------------------------------
# Offline, deterministic interpretation (always available).
# ---------------------------------------------------------------------------
.ai_offline_next_steps <- function(atype, omics) {
  atype <- tolower(trimws(.ai_chr(atype)))
  omics <- tolower(trimws(.ai_chr(omics)))
  base <- switch(atype,
    differential = c(
      "用火山图 (Visualize ▸ Volcano) 直观展示上调/下调特征。",
      "对显著差异特征做功能富集 (Analysis ▸ Enrichment, KEGG/GO) 解释生物学意义。",
      "用 DEG 热图查看显著特征在样本间的表达模式与聚类。",
      "若分组不平衡或存在批次，考虑在差异分析中加入协变量或先做归一化。"
    ),
    volcano = c(
      "对火山图右侧/左侧的显著特征导出列表，进行功能富集分析。",
      "结合效应量 (log2FC) 与显著性 (p_adj) 设定更严格阈值，减少假阳性。"
    ),
    alpha = c(
      "用 Boxplot + 组间检验确认 Alpha 多样性差异是否显著 (Wilcoxon/Kruskal)。",
      "进一步做 Beta 多样性 (降维/排序 PCoA) 看群落整体结构是否分离。",
      "如样本测序深度差异大，先做抽平 (Rarefy) 再比较多样性。"
    ),
    dimension = ,
    scatter = c(
      "用 PERMANOVA / 组间检验评估排序上的分离是否统计显著。",
      "若分组在前两轴未分开，尝试不同距离 (Bray-Curtis/Aitchison) 或先归一化。",
      "结合差异分析找出驱动分离的关键特征。"
    ),
    correlation = c(
      "对强相关特征对绘制散点/拟合线确认关系形态 (线性/非线性)。",
      "相关不等于因果，结合分组与临床变量进一步验证。",
      "可构建共现网络 (Analysis ▸ Network) 看模块结构。"
    ),
    cluster = c(
      "将聚类标签与已知分组对照，评估聚类是否反映生物学分组。",
      "用热图按聚类排序展示特征模式。",
      "尝试不同聚类数 k 或方法 (kmeans/ward) 检验稳健性。"
    ),
    marker = ,
    marker_model = c(
      "用交叉验证 / 留出验证评估模型泛化能力，避免过拟合。",
      "对 Top 重要特征做生物学注释与文献核对。",
      "报告 AUC/准确率并与随机基线比较。"
    ),
    enrichment = c(
      "聚焦显著富集通路 (p_adj < 0.05)，结合上下调方向解读。",
      "用通路-基因网络或气泡图展示富集结果。",
      "跨组学比较富集通路，寻找一致的功能信号。"
    ),
    network = c(
      "识别高连接度的枢纽 (hub) 节点，它们常是关键调控者。",
      "做模块划分，并将模块与分组/性状关联 (WGCNA)。"
    ),
    c(
      "用可视化模块把当前结果做成可发表图表。",
      "结合其他分析交叉验证当前发现。",
      "在 Course ▸ 反思区记录你的解读与下一步假设。"
    )
  )
  # Omics-specific add-ons
  extra <- character(0)
  if (omics %in% c("microbiome_16s", "m16s", "16s")) {
    extra <- c("可用 Sankey/组成图展示门-属层级的分类组成。")
  } else if (omics %in% c("rnaseq", "transcriptomics")) {
    extra <- c("RNA-seq 差异建议用 DESeq2/edgeR (基于原始计数)，而非已归一化矩阵。")
  } else if (omics %in% c("metabolomics", "mbx")) {
    extra <- c("代谢组先处理缺失值 (impute) 与归一化 (log/Pareto) 再做差异。")
  }
  c(base, extra)
}

.ai_offline_interpretation <- function(ctx) {
  atype <- .ai_chr(ctx$analysis_type, "analysis")
  omics <- .ai_chr(ctx$omics)
  st <- ctx$stats %||% list()
  tbl <- ctx$table %||% list()

  parts <- character(0)
  push <- function(...) parts[[length(parts) + 1L]] <<- paste0(...)

  push("## ", .ai_analysis_label(atype), " 解读\n")

  # Result overview, driven by available stats.
  overview <- character(0)
  n_sig <- .ai_num(st$n_significant %||% st$n_sig)
  n_total <- .ai_num(st$n_total %||% tbl$n_rows)
  if (!is.na(n_sig)) {
    msg <- paste0("本次分析共检出 **", n_sig, "** 个显著特征")
    if (!is.na(n_total)) msg <- paste0(msg, "（候选 ", n_total, " 个）")
    msg <- paste0(msg, "。")
    if (!is.na(n_sig) && n_sig == 0) {
      msg <- paste0(msg, " 没有达到显著阈值，可能是效应较弱、样本量不足或阈值过严。")
    }
    overview <- c(overview, msg)
  }
  n_up <- .ai_num(st$n_up); n_down <- .ai_num(st$n_down)
  if (!is.na(n_up) || !is.na(n_down)) {
    up_s <- if (is.na(n_up)) 0 else n_up
    down_s <- if (is.na(n_down)) 0 else n_down
    overview <- c(overview, paste0("其中上调 ", up_s, " 个、下调 ", down_s, " 个。"))
  }
  for (k in c("R2", "r2", "AUC", "auc", "p_value", "pvalue", "shannon", "explained_var")) {
    if (!is.null(st[[k]])) overview <- c(overview, paste0(k, " = ", .ai_chr(st[[k]]), "。"))
  }
  if (!length(overview)) {
    overview <- paste0("已生成 ", .ai_analysis_label(atype), " 结果。")
  }
  push("**结果概览**\n\n", paste(overview, collapse = " "), "\n")

  # Top features, if provided.
  rows <- tbl$rows %||% NULL
  if (!is.null(rows) && length(rows)) {
    feat_key <- intersect(c("feature", "Feature", "name", "id", "gene", "taxa"), names(rows[[1L]]))
    if (length(feat_key)) {
      fk <- feat_key[1L]
      tops <- vapply(rows[seq_len(min(length(rows), 6L))], function(r) .ai_chr(r[[fk]]), character(1))
      tops <- tops[nzchar(tops)]
      if (length(tops)) push("**值得关注的特征**\n\n", paste0("`", tops, "`", collapse = "、"), "\n")
    }
  }

  # Biological framing per analysis type.
  framing <- switch(tolower(trimws(atype)),
    differential = "差异分析比较两组之间每个特征的丰度/表达。log2FC 反映变化幅度与方向，p_adj (校正后 p 值) 控制多重比较假阳性——优先看 p_adj 而非原始 p 值。",
    volcano = "火山图横轴是 log2FC（变化方向与幅度），纵轴是 -log10(p)。右上/左上角的点既显著又变化大，最值得关注。",
    alpha = "Alpha 多样性衡量单个样本内部的物种丰富度与均匀度 (如 Shannon/Simpson)。组间比较应配合非参数检验。",
    dimension = "降维/排序把高维特征压缩到少数几个轴上。样本在前两轴上的聚集/分离反映整体结构差异，括号中的百分比是该轴解释的方差。",
    scatter = "排序散点展示样本在主轴上的分布。组别若明显分开，提示整体谱差异；重叠则提示差异有限。",
    correlation = "相关分析度量特征间的协同变化 (Spearman 适合非线性单调关系)。注意相关并不意味因果。",
    cluster = "聚类按相似度把样本分组。理想情况下聚类应与已知生物学分组一致，否则提示存在其他主导变异来源 (如批次)。",
    marker = "机器学习标志物分析按对分类的贡献给特征排序。重要性高的特征是潜在生物标志物，但需独立验证。",
    enrichment = "富集分析判断显著特征是否过度集中在某些通路 (KEGG/GO)，把零散的基因/代谢物提升到通路与功能层面解读。",
    network = "共现网络用边连接强相关的特征，枢纽节点和模块往往对应关键的调控关系或功能单元。",
    "该结果是多组学分析流程中的一步，建议结合上下游分析综合解读。"
  )
  push("**生物学解读**\n\n", framing, "\n")

  # Caveats (statistical traps for students).
  caveats <- c(
    "样本量小时结论不稳健，注意每组重复数。",
    "多重检验务必看校正后的 p 值 (p_adj/FDR)。",
    "显著 ≠ 生物学重要，结合效应量与先验知识判断。"
  )
  push("**注意事项**\n\n", paste0("- ", caveats, collapse = "\n"), "\n")

  steps <- .ai_offline_next_steps(atype, omics)
  push("**下一步建议**\n\n", paste0(seq_along(steps), ". ", steps, collapse = "\n"), "\n")

  list(text = paste(parts, collapse = "\n"), next_steps = steps)
}

# ---------------------------------------------------------------------------
# LLM layer
# ---------------------------------------------------------------------------
.ai_system_prompt <- function() {
  paste(
    "你是 EasyMultiProfiler (EMP) 多组学数据分析平台的 AI 教学助手，面向生物信息学初学者。",
    "你的任务：用通俗、准确、鼓励性的中文，帮助学生解读他们刚刚得到的分析结果，并给出可执行的下一步建议。",
    "严格基于用户提供的结果上下文进行解读，不要编造不存在的数值或特征。",
    "输出使用 Markdown，结构为：## 标题、结果概览、生物学解读、注意事项(常见统计陷阱)、下一步建议(编号列表)。",
    "解读要具体到这次的数据 (引用提供的统计量与特征名)，避免空泛套话。控制在 400 字以内。",
    sep = "\n"
  )
}

.ai_llm_chat <- function(provider, cfg, system_prompt, user_prompt) {
  provider <- tolower(trimws(.ai_chr(provider, "campus")))
  if (identical(provider, "campus")) cfg <- .llm_campus_merge_cfg(cfg)
  d <- .llm_provider_defaults(provider, cfg)
  provider <- d$provider
  key <- trimws(.ai_chr(cfg$api_key))
  timeout <- .ai_num(cfg$timeout, 90); if (is.na(timeout) || timeout <= 0) timeout <- 90
  temperature <- .ai_num(cfg$temperature, 0.4)
  max_tokens <- as.integer(.ai_num(cfg$max_tokens, 900))

  if (provider %in% c("chatgpt", "openai", "deepseek", "qwen", "minimax", "custom", "campus")) {
    if (!nzchar(key)) stop(sprintf("API key required for provider: %s", provider))
    url <- paste0(d$base_url, "/chat/completions")
    body <- list(model = d$model, messages = list(
      list(role = "system", content = system_prompt),
      list(role = "user", content = user_prompt)
    ), max_tokens = max_tokens, temperature = temperature)
    resp <- .llm_call_curl(url, c(paste0("Authorization: Bearer ", key)), body, timeout)
    return(.llm_extract_text(resp))
  }
  if (identical(provider, "claude")) {
    if (!nzchar(key)) stop("API key required for provider: claude")
    url <- paste0(d$base_url, "/messages")
    body <- list(model = d$model, max_tokens = max_tokens, temperature = temperature,
                 system = system_prompt, messages = list(list(role = "user", content = user_prompt)))
    resp <- .llm_call_curl(url, c(paste0("x-api-key: ", key), "anthropic-version: 2023-06-01"), body, timeout)
    return(.llm_extract_text(resp))
  }
  if (identical(provider, "gemini")) {
    if (!nzchar(key)) stop("API key required for provider: gemini")
    url <- paste0(d$base_url, "/models/", utils::URLencode(d$model, reserved = TRUE),
                  ":generateContent?key=", utils::URLencode(key, reserved = TRUE))
    body <- list(
      systemInstruction = list(parts = list(list(text = system_prompt))),
      contents = list(list(parts = list(list(text = user_prompt))))
    )
    resp <- .llm_call_curl(url, character(0), body, timeout)
    return(.llm_extract_text(resp))
  }
  stop(sprintf("Unsupported LLM provider for copilot: %s", provider))
}

# Main entry: returns a list with interpretation text, source, and next steps.
ai_interpret <- function(ctx, provider = NULL, cfg = NULL) {
  ctx <- ctx %||% list()
  summary_txt <- .ai_summarise_context(ctx)
  offline <- .ai_offline_interpretation(ctx)

  provider <- tolower(trimws(.ai_chr(provider, .ai_chr(cfg$provider, ""))))
  has_key <- nzchar(trimws(.ai_chr((cfg %||% list())$api_key)))
  want_llm <- nzchar(provider) && !identical(provider, "offline") &&
    (identical(provider, "campus") || has_key)

  if (want_llm) {
    user_prompt <- paste0(
      "学生刚刚在 EMP 平台完成了一步分析。以下是结果上下文：\n\n",
      summary_txt,
      "\n\n请据此给出面向初学者的解读与下一步建议。"
    )
    llm_err <- NULL
    out <- tryCatch(.ai_llm_chat(provider, cfg, .ai_system_prompt(), user_prompt),
                    error = function(e) {
                      llm_err <<- conditionMessage(e)
                      NULL
                    })
    if (!is.null(out) && nzchar(trimws(out))) {
      return(list(success = TRUE, source = "llm", provider = provider,
                  interpretation = out, next_steps = offline$next_steps,
                  context_summary = summary_txt))
    }
    return(list(success = TRUE, source = "offline", provider = provider,
                interpretation = offline$text, next_steps = offline$next_steps,
                context_summary = summary_txt,
                llm_error = llm_err %||% "LLM 不可用，已使用本地解读。"))
  }

  list(success = TRUE, source = "offline", provider = "offline",
       interpretation = offline$text, next_steps = offline$next_steps,
       context_summary = summary_txt)
}

plumber_ai_interpret_post <- function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody, simplifyVector = FALSE)
    ctx <- b$context %||% b
    provider <- b$provider %||% (b$config %||% list())$provider %||% NULL
    cfg <- b$config %||% list()
    res_out <- ai_interpret(ctx, provider = provider, cfg = cfg)
    res_out
  }, res)
}
