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

.ai_resolve_locale <- function(x) {
  loc <- tolower(trimws(.ai_chr(x, "zh")))
  if (grepl("^en", loc)) "en" else "zh"
}

.ai_L <- function(locale, zh, en) {
  if (.ai_resolve_locale(locale) == "en") en else zh
}

# Friendly labels for analysis / omics types (zh or en).
.ai_analysis_label <- function(t, locale = "zh") {
  t <- tolower(trimws(.ai_chr(t)))
  if (.ai_resolve_locale(locale) == "en") {
    map <- c(
      differential = "Differential analysis", diff = "Differential analysis",
      volcano = "Volcano plot", alpha = "Alpha diversity",
      dimension = "Ordination (PCA/PCoA)", scatter = "Ordination scatter",
      correlation = "Correlation", cluster = "Clustering", marker = "Biomarker (ML)",
      enrichment = "Enrichment (KEGG/GO)", network = "Co-occurrence network",
      chipseq = "ChIP-seq peak workflow",
      heatmap = "Heatmap", boxplot = "Boxplot", barplot = "Bar plot",
      structure = "Community composition", clinical_cor = "Clinical-feature correlation",
      fitline = "Fit line", three_line = "Baseline table",
      marker_model = "Multi-omics model", wgcna = "WGCNA"
    )
    return(unname(map[t]) %||% (.ai_chr(t, "Analysis")))
  }
  map <- c(
    differential = "差异分析", diff = "差异分析", volcano = "火山图（差异分析）",
    alpha = "Alpha 多样性", dimension = "降维 / 排序 (PCA/PCoA)", scatter = "排序散点 (PCA/PCoA)",
    correlation = "相关性分析", cluster = "聚类分析", marker = "生物标志物 (机器学习)",
    enrichment = "功能富集 (KEGG/GO)", network = "共现网络", chipseq = "ChIP-seq 峰分析",
    heatmap = "热图",
    boxplot = "箱线图", barplot = "组成柱状图", structure = "群落组成",
    clinical_cor = "临床-特征相关", fitline = "拟合回归", three_line = "基线三线表",
    marker_model = "多组学诊断模型", wgcna = "WGCNA 模块-性状"
  )
  unname(map[t]) %||% (.ai_chr(t, "分析"))
}

.ai_omics_label <- function(o, locale = "zh") {
  o <- tolower(trimws(.ai_chr(o)))
  if (.ai_resolve_locale(locale) == "en") {
    map <- c(
      rnaseq = "Transcriptomics (RNA-seq)", transcriptomics = "Transcriptomics (RNA-seq)",
      microbiome_16s = "16S microbiome", m16s = "16S microbiome", "16s" = "16S microbiome",
      metagenomics = "Metagenomics", mgx = "Metagenomics",
      metabolomics = "Metabolomics", mbx = "Metabolomics",
      chipseq = "ChIP-seq",
      clinical = "Clinical phenotypes", normal = "General omics"
    )
    return(unname(map[o]) %||% (.ai_chr(o, "Omics data")))
  }
  map <- c(
    rnaseq = "转录组 (RNA-seq)", transcriptomics = "转录组 (RNA-seq)",
    microbiome_16s = "16S 微生物组", m16s = "16S 微生物组", "16s" = "16S 微生物组",
    metagenomics = "宏基因组", mgx = "宏基因组",
    metabolomics = "代谢组", mbx = "代谢组",
    chipseq = "ChIP-seq",
    clinical = "临床表型", normal = "通用组学"
  )
  unname(map[o]) %||% (.ai_chr(o, "组学数据"))
}

.ai_is_microbiome_omics <- function(omics) {
  omics <- tolower(trimws(.ai_chr(omics)))
  omics %in% c("microbiome_16s", "m16s", "16s")
}

.ai_feat_taxon_like <- function(x) {
  s <- tolower(trimws(.ai_chr(x)))
  if (!nzchar(s)) return(FALSE)
  grepl(
    "aceae|obacter|ota$|__|phylum|classis|order|genus|species|firmicutes|bacteroid|bifidobacter|fusobacter|prevotella|lactobacillus|streptococcus|clostridium|escherichia|blautia|roseburia|faecalibacterium|ruminococcus|desulfovibrio|agrobacterium|longicatena|ovatus|uniformis|gnavus|reuteri",
    s
  )
}

.ai_infer_feature_kind <- function(ctx, feats = NULL) {
  omics <- tolower(trimws(.ai_chr(ctx$omics)))
  if (.ai_is_microbiome_omics(omics)) return("microbiome_taxa")
  if (omics %in% c("metagenomics", "mgx")) return("mgx_function")
  if (omics %in% c("metabolomics", "mbx")) return("metabolite")
  if (omics %in% c("transcriptomics", "rnaseq")) return("gene")
  if (is.null(feats)) feats <- .ai_extract_visible_features(ctx)
  if (length(feats) &&
      sum(vapply(feats, .ai_feat_taxon_like, logical(1L))) >= max(1L, ceiling(length(feats) * 0.25))) {
    return("microbiome_taxa")
  }
  "gene"
}

.ai_heatmap_mode <- function(ctx) {
  params <- ctx$params %||% list()
  m <- tolower(trimws(.ai_chr(params$heatmap_mode %||% ctx$heatmap_mode)))
  if (nzchar(m)) return(m)
  st <- ctx$stats %||% list()
  if (!is.null(st$n_significant) || !is.null(st$n_sig) ||
      !is.null(params$fc_cutoff) || !is.null(params$p_cutoff)) {
    return("differential")
  }
  "exploratory"
}

.ai_heatmap_profile <- function(ctx) {
  fk <- .ai_infer_feature_kind(ctx)
  mode <- .ai_heatmap_mode(ctx)
  key <- paste0(fk, "_", mode)
  map <- c(
    microbiome_taxa_differential = "m16s_diff",
    microbiome_taxa_exploratory = "m16s_exploratory",
    gene_differential = "rnaseq_deg",
    gene_exploratory = "rnaseq_exploratory",
    mgx_function_differential = "mgx_diff",
    mgx_function_exploratory = "mgx_exploratory",
    metabolite_differential = "mbx_diff",
    metabolite_exploratory = "mbx_exploratory"
  )
  unname(map[key]) %||% key
}

.ai_feature_label <- function(ctx, locale = "zh", plural = TRUE) {
  en <- .ai_resolve_locale(locale) == "en"
  fk <- .ai_infer_feature_kind(ctx)
  if (identical(fk, "microbiome_taxa")) {
    if (en) if (plural) "differential taxa" else "taxon" else if (plural) "差异菌/分类单元" else "菌/分类单元"
  } else if (identical(fk, "mgx_function")) {
    if (en) if (plural) "functional features" else "functional feature" else if (plural) "功能特征" else "功能特征"
  } else if (identical(fk, "metabolite")) {
    if (en) if (plural) "metabolites" else "metabolite" else if (plural) "代谢物" else "代谢物"
  } else {
    if (en) if (plural) "genes" else "gene" else if (plural) "基因" else "基因"
  }
}

.ai_heatmap_plot_rules <- function(ctx, locale = "zh") {
  en <- .ai_resolve_locale(locale) == "en"
  profile <- .ai_heatmap_profile(ctx)
  if (profile %in% c("m16s_diff", "m16s_exploratory")) {
    if (en) {
      return(paste(
        "For 16S / amplicon microbiome heatmaps, NEVER call taxa 'genes'.",
        "CNS Results style (4 sentences in interpretation):",
        "(1) compositional pattern & sample/taxa clustering by group;",
        "(2) quantitative anchors — n taxa, thresholds (log2FC, p/padj), directional enrichment per group;",
        "(3) cautious biology — dysbiosis/homeostasis, known commensals/pathobionts, IBD/IBS literature only as 'associated with';",
        "(4) boundaries — compositional relative abundance, taxonomic resolution, no causality, need qPCR/shotgun/metabolomics validation.",
        "limitations: compositional constraint, multiple-testing/FDR, sequencing depth, method choice (ALDEx2/ANCOM/DESeq2 pseudo-counts).",
        "figure_optimization: 10–30 taxa main figure; genus italics; group annotation bar; Z-score on CLR/log-ratio; row dendrogram.",
        "downstream: beta diversity PERMANOVA, indicator species/LEfSe, PICRUSt2, multi-omics integration."
      ))
    }
    return(paste(
      "16S/扩增子微生物组热图：严禁将菌/ASV/OTU 称为“基因”。",
      "interpretation 按 CNS Results 四句式：",
      "1）群落组成模式与样本/分类单元聚类（组内一致、组间分离）；",
      "2）定量锚点——差异菌数量、|log2FC|/p 或 padj 阈值、各组富集/耗竭方向；",
      "3）生物学指向——用“关联/富集/耗竭”描述，引用 dysbiosis、共生菌/条件致病菌时需克制，避免“致病/导致”；",
      "4）结论边界——组成型相对丰度、分类分辨率限制、不能推断因果，需 qPCR/宏基因组/代谢组验证。",
      "limitations 须提：组成性约束、多重检验/FDR、测序深度、差异方法适用性。",
      "figure_optimization：主图 10–30 个 taxa、属名斜体、顶部分组 annotation、CLR/log-ratio 后 Z-score。",
      "downstream：Beta 多样性+PERMANOVA、指示种/LEfSe、PICRUSt2、多组学整合。"
    ))
  }
  if (profile %in% c("rnaseq_deg", "rnaseq_exploratory")) {
    if (en) {
      return(paste(
        "RNA-seq heatmap: group clustering, co-expression modules, ECM/inflammation/metabolism genes if relevant;",
        "state exploratory if no formal DEG stats; main figure 30–50 genes."
      ))
    }
    return(paste(
      "RNA-seq 热图：组内聚类、共表达模块、ECM/炎症/代谢相关基因；",
      "无正式 DEG 统计时标明探索性；主图建议 30–50 个基因。"
    ))
  }
  if (en) {
    "Heatmap: match feature type to omics (taxa / genes / functions / metabolites); anchor claims to provided stats; no causality from color alone."
  } else {
    "热图：特征类型与组学一致（菌/基因/功能/代谢物）；结论锚定所给统计量；不能仅凭颜色推断因果。"
  }
}

.ai_heatmap_supplement <- function(ctx, locale = "zh") {
  atype <- tolower(trimws(.ai_chr(ctx$analysis_type)))
  if (!identical(atype, "heatmap")) return("")
  en <- .ai_resolve_locale(locale) == "en"
  profile <- .ai_heatmap_profile(ctx)
  params <- ctx$params %||% list()
  feats <- .ai_extract_visible_features(ctx)
  feat_txt <- if (length(feats)) paste(head(feats, 10L), collapse = if (en) ", " else "、") else ""
  thr <- character(0)
  if (!is.null(params$fc_cutoff)) thr <- c(thr, paste0("|log2FC|>=", .ai_chr(params$fc_cutoff)))
  if (!is.null(params$p_cutoff)) thr <- c(thr, paste0("p<=", .ai_chr(params$p_cutoff)))
  if (!is.null(ctx$groups)) thr <- c(thr, paste(as.character(unlist(ctx$groups)), collapse = if (en) " vs " else " vs "))
  thr_txt <- if (length(thr)) paste(thr, collapse = if (en) "; " else "；") else NULL
  hdr <- if (en) "[Heatmap supplement — profile: " else "【热图补充 — 类型: "
  body <- .ai_heatmap_plot_rules(ctx, locale)
  extra <- character(0)
  if (nzchar(feat_txt)) {
    extra <- c(extra, if (en) paste0("Visible features/taxa: ", feat_txt, ".") else
      paste0("图中可见特征/菌名：", feat_txt, "。"))
  }
  if (!is.null(thr_txt)) {
    extra <- c(extra, if (en) paste0("Stated thresholds/groups: ", thr_txt, ".") else
      paste0("所给阈值/分组：", thr_txt, "。"))
  }
  paste0("\n\n", hdr, profile, if (en) "] " else "】", body,
         if (length(extra)) paste0("\n", paste(extra, collapse = " ")) else "")
}

.ai_m16s_diff_interpretation <- function(ctx, locale = "zh") {
  en <- .ai_resolve_locale(locale) == "en"
  feats <- .ai_extract_visible_features(ctx)
  st <- ctx$stats %||% list()
  params <- ctx$params %||% list()
  n_taxa <- .ai_num(st$n_significant %||% st$n_sig %||% st$n_total %||% ctx$table$n_rows)
  n_show <- if (!is.na(n_taxa) && n_taxa > 0) as.integer(n_taxa) else length(feats)
  if (is.na(n_show) || n_show <= 0) n_show <- length(feats)
  feat_note <- if (length(feats)) {
    paste0(if (en) "including " else "包括 ",
           paste(head(feats, 6L), collapse = if (en) ", " else "、"))
  } else ""
  groups <- ctx$groups %||% NULL
  grp_txt <- if (!is.null(groups) && length(groups)) {
    paste(as.character(unlist(groups)), collapse = if (en) " and " else "与")
  } else if (!is.null(ctx$group)) .ai_chr(ctx$group) else NULL
  fc <- .ai_chr(params$fc_cutoff, "")
  pcut <- .ai_chr(params$p_cutoff, "")
  thr <- if (nzchar(fc) || nzchar(pcut)) {
    if (en) paste0("|log2FC|>=", fc %||% "1", ", p<=", pcut %||% "0.05") else
      paste0("|log2FC|>=", fc %||% "1", "、p<=", pcut %||% "0.05")
  } else NULL

  if (en) {
    paste0(
      "Z-score-scaled relative-abundance heatmap of differentially abundant taxa revealed compositional structuring across samples",
      if (!is.null(grp_txt)) paste0(", with samples largely segregating by ", grp_txt, " status") else "",
      ", and co-abundant taxa forming distinct row clusters. ",
      if (!is.na(n_show) && n_show > 0) {
        paste0("Under the applied differential filters",
               if (!is.null(thr)) paste0(" (", thr, ")") else "",
               ", ", n_show, " taxa were retained ", feat_note, "; color blocks indicate directional enrichment or depletion between groups rather than absolute abundance. ")
      } else "",
      "Shifts involving common gut commensals (e.g., Bifidobacterium, Bacteroides) may reflect dysbiosis–homeostasis transitions reported in intestinal disorders, but taxonomic resolution precludes strain-level mechanistic claims. ",
      "These patterns are association-level evidence from compositional amplicon data; causality, functional activity, and clinical relevance require independent validation (qPCR, shotgun metagenomics, metabolomics, or intervention cohorts)."
    )
  } else {
    paste0(
      "基于相对丰度 Z-score 的差异菌群热图显示，样本间存在可辨的群落组成结构",
      if (!is.null(grp_txt)) paste0("，且样本主要按", grp_txt, "分组聚集") else "",
      "，共丰度的分类单元在行列聚类中形成模块。 ",
      if (!is.na(n_show) && n_show > 0) {
        paste0("在当前差异筛选条件下",
               if (!is.null(thr)) paste0("（", thr, "）") else "",
               "保留 ", n_show, " 个分类单元", if (nzchar(feat_note)) paste0("（", feat_note, "）") else "",
               "；红/蓝区块反映组间富集或耗竭方向，而非绝对菌量。 ")
      } else "",
      "以 Bifidobacterium、Bacteroides 等常见肠道菌为代表的丰度偏移，可与肠道稳态/失调相关文献相呼应，但分类层级分辨率不足以支持菌株级机制推断。 ",
      "该结果属于组成型扩增子数据的关联性证据，不能据此推断因果或体内功能活性，需 qPCR、鸟枪法宏基因组、代谢组或干预队列进一步验证。"
    )
  }
}

# Build a compact textual summary of the result context (used both for the LLM
# prompt and as the backbone of the offline interpretation).
.ai_summarise_context <- function(ctx) {
  locale <- .ai_resolve_locale(ctx$locale %||% ctx$lang)
  lines <- character(0)
  add <- function(...) lines[[length(lines) + 1L]] <<- paste0(...)

  atype <- .ai_chr(ctx$analysis_type, "analysis")
  add(.ai_L(locale, "分析类型: ", "Analysis: "), .ai_analysis_label(atype, locale))
  if (!is.null(ctx$omics)) add(.ai_L(locale, "组学: ", "Omics: "), .ai_omics_label(ctx$omics, locale))
  if (tolower(atype) == "heatmap") {
    add(.ai_L(locale, "热图谱系: ", "Heatmap profile: "), .ai_heatmap_profile(ctx))
    add(.ai_L(locale, "特征实体: ", "Feature entity: "), .ai_feature_label(ctx, locale, plural = TRUE))
  }
  if (!is.null(ctx$experiment)) add(.ai_L(locale, "实验对象: ", "Experiment: "), .ai_chr(ctx$experiment))

  ds <- ctx$dataset %||% list()
  if (!is.null(ds$n_samples)) add(.ai_L(locale, "样本数: ", "Samples: "), .ai_chr(ds$n_samples))
  if (!is.null(ds$n_features)) add(.ai_L(locale, "特征数: ", "Features: "), .ai_chr(ds$n_features))
  if (!is.null(ctx$group)) add(.ai_L(locale, "分组变量: ", "Group: "), .ai_chr(ctx$group))
  if (!is.null(ctx$groups)) add(.ai_L(locale, "组别: ", "Groups: "), paste(as.character(unlist(ctx$groups)), collapse = " vs "))

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

.ai_output_language <- function(locale) {
  if (.ai_resolve_locale(locale) == "en") "en-US" else "zh-CN"
}

.ai_extract_visible_features <- function(ctx, max_n = 12L) {
  tbl <- ctx$table %||% list()
  rows <- tbl$rows %||% NULL
  if (is.null(rows) || !length(rows)) return(character(0))
  feat_key <- intersect(c("feature", "Feature", "name", "id", "gene", "taxa"), names(rows[[1L]]))
  if (!length(feat_key)) return(character(0))
  fk <- feat_key[1L]
  tops <- vapply(rows[seq_len(min(length(rows), max_n))], function(r) .ai_chr(r[[fk]]), character(1))
  tops[nzchar(tops)]
}

.ai_key_stats_brief <- function(ctx, locale = "zh", max_n = 4L) {
  st <- ctx$stats %||% list()
  if (!length(st)) return("")
  en <- .ai_resolve_locale(locale) == "en"
  keys <- c(
    "n_significant", "n_sig", "n_up", "n_down", "permanova_p", "p_value",
    "p_adj", "padj", "adj_p", "r2", "auc", "accuracy"
  )
  hits <- intersect(keys, names(st))
  if (!length(hits)) return("")
  hits <- hits[seq_len(min(length(hits), max_n))]
  kv <- vapply(hits, function(k) paste0(k, "=", .ai_chr(st[[k]])), character(1))
  if (en) paste0("Key evidence: ", paste(kv, collapse = ", "), ".") else
    paste0("关键证据：", paste(kv, collapse = "，"), "。")
}

.ai_build_prompt_buttons <- function(ctx, locale = "zh") {
  atype <- tolower(trimws(.ai_chr(ctx$analysis_type)))
  kind <- tolower(trimws(.ai_chr(ctx$kind, "table")))
  en <- .ai_resolve_locale(locale) == "en"
  btns <- list()
  add <- function(label, prompt) {
    btns[[length(btns) + 1L]] <<- list(label = label, prompt = prompt)
  }
  if (kind == "plot" && atype %in% c("heatmap", "cluster")) {
    profile <- .ai_heatmap_profile(ctx)
    if (profile %in% c("m16s_diff", "m16s_exploratory")) {
      if (en) {
        add("Optimize 16S differential-taxa heatmap",
            "Optimize the 16S differential-abundance heatmap: genus-level italics, top 10-30 taxa, group annotation bar, Z-score on CLR/log-ratio, color-blind palette, ComplexHeatmap row dendrogram. Return runnable R code.")
        add("Add phylum row annotation",
            "Add a left-side phylum/family annotation bar to the taxa heatmap using ComplexHeatmap; keep group column annotation and publication export.")
        add("Export taxa table for LEfSe / indicator species",
            "From the current differential taxa result, export a LEfSe-ready table (taxon, group, LDA/log2FC, padj) and sketch indicator-species analysis in R.")
        add("Write CNS-style figure legend",
            "Write a Nature/Cell-style figure legend for this 16S differential-taxa heatmap: normalization, Z-score, clustering, groups, key taxa, no causal language.")
        add("Link beta diversity + PICRUSt2",
            "Design downstream Bray-Curtis PCoA with PERMANOVA plus PICRUSt2 functional prediction for taxa enriched in each group.")
      } else {
        add("优化 16S 差异菌群热图",
            "请优化当前 16S 差异丰度热图：属级斜体命名、主图 10–30 个 taxa、顶部分组 annotation、CLR/log-ratio 后 Z-score、色盲友好配色、ComplexHeatmap 行聚类。输出可运行 R 代码。")
        add("增加门/科水平行注释",
            "用 ComplexHeatmap 为差异菌热图增加左侧门/科注释条，保留顶部分组注释与发表级导出。")
        add("导出 LEfSe/指示种分析表",
            "基于当前差异菌结果导出 LEfSe 格式表（taxon、group、LDA/log2FC、padj），并给出指示种分析 R 代码框架。")
        add("撰写 CNS 风格图注",
            "为这张 16S 差异菌群热图撰写 Nature/Cell 风格 figure legend：标准化、Z-score、聚类、分组、关键菌名，避免因果措辞。")
        add("衔接 Beta 多样性 + PICRUSt2",
            "设计下游 Bray-Curtis PCoA + PERMANOVA，并对各组富集菌做 PICRUSt2 功能预测分析流程。")
      }
    } else if (en) {
      add("Optimize heatmap colors & annotations",
          "Optimize the current R heatmap code: use publication red-white-blue or color-blind palette, fix Z-score scale to -2..2, add sample group annotation bar, improve label readability. Return complete runnable R code.")
      add("Filter core genes & redraw",
          "Modify the heatmap to show top 30-50 representative genes (padj, |log2FC|, variance). Keep group annotations and publication-quality export.")
      add("Convert to ComplexHeatmap",
          "Rewrite the heatmap using ComplexHeatmap with column annotations, row/column clustering, Z-score scaling, clear legend, and high-res PDF/PNG export.")
      add("Generate figure legend",
          "Write an SCI-style figure legend for this heatmap: data type, normalization, clustering, color meaning, groups, main observations. Concise, no overclaim.")
      add("Link GO/KEGG/GSEA",
          "Design downstream GO, KEGG, and GSEA workflow in R for genes shown in the heatmap, including ID mapping, enrichment plots, and GSEA ridge plot.")
    } else {
      add("优化热图配色与注释",
          "请基于当前 R 代码优化热图：使用更适合论文发表的红-白-蓝或色盲友好配色，固定 Z-score 色阶范围为 -2 到 2，增加样本分组 annotation bar，并提高基因名与样本名的可读性。请输出完整可运行的 R 代码。")
      add("筛选核心基因重画热图",
          "请修改当前热图代码，仅展示 top 30–50 个最具代表性的基因。优先按照 adjusted P value、absolute log2FC 和表达方差筛选基因；如果没有差异分析结果，则使用样本间方差最高的基因。请保留分组注释并输出发表级热图。")
      add("改成 ComplexHeatmap",
          "请将当前热图代码改写为 ComplexHeatmap 版本，加入顶部样本分组注释、行列聚类、Z-score 标准化、清晰图例和 PDF/PNG 高分辨率导出。请保证代码可以直接在 R 中运行。")
      add("生成论文图注",
          "请根据当前热图结果生成一段 SCI 论文风格 figure legend，说明数据类型、标准化方法、聚类方法、颜色含义、样本分组和主要观察结果。语言要求专业、简洁，不夸大结论。")
      add("衔接 GO/KEGG/GSEA",
          "请基于当前热图中显示的核心基因，设计下游 GO、KEGG 和 GSEA 分析流程。请给出 R 代码，包括基因 ID 转换、富集分析、气泡图、柱状图和 GSEA ridge plot，并说明每一步的输入文件格式。")
    }
  } else if (kind == "plot") {
    pub <- if (en) "Apply emp_pub_theme and emp_pub_palette; improve axes, legend, labels; export PDF >=300 dpi." else
      "使用 emp_pub_theme 与 emp_pub_palette，优化坐标轴、图例、标签，导出 ≥300 dpi PDF。"
    add(if (en) "Beautify for publication" else "发表级美化", pub)
  } else if (atype %in% c("differential", "diff", "volcano")) {
    add(if (en) "Tune volcano & export DEG list" else "优化火山图并导出 DEG",
        if (en) "Optimize volcano plot thresholds and labels; export significant gene list for enrichment." else
          "优化火山图阈值与标签，并导出显著基因列表用于富集分析。")
  }
  if (!length(btns)) {
    steps <- .ai_offline_next_steps(atype, .ai_chr(ctx$omics), locale)
    if (length(steps)) {
      add(if (en) "Apply next step in Code Lab" else "应用下一步到 Code Lab", steps[1])
    }
  }
  btns
}

.ai_offline_structured <- function(ctx) {
  locale <- .ai_resolve_locale(ctx$locale %||% ctx$lang)
  atype <- tolower(trimws(.ai_chr(ctx$analysis_type, "analysis")))
  omics <- tolower(trimws(.ai_chr(ctx$omics)))
  kind <- tolower(trimws(.ai_chr(ctx$kind, "table")))
  st <- ctx$stats %||% list()
  en <- locale == "en"
  feats <- .ai_extract_visible_features(ctx)
  ecm_genes <- c("Col1a1", "Col1a2", "Col5a1", "Col6a1", "Fn1", "Thbs1", "Acta2", "Bgn", "Sparc", "Lox", "Lgals1")
  ecm_hit <- intersect(feats, ecm_genes)
  n_sig <- .ai_num(st$n_significant %||% st$n_sig)
  has_deg_stats <- !is.na(n_sig) || !is.null(st$log2FC) || !is.null(st$p_adj)

  interpretation <- character(0)
  hm_profile <- if (kind == "plot" && atype == "heatmap") .ai_heatmap_profile(ctx) else NULL
  if (kind == "plot" && atype == "heatmap" && hm_profile %in% c("m16s_diff", "m16s_exploratory")) {
    interpretation <- .ai_m16s_diff_interpretation(ctx, locale)
  } else if (kind == "plot" && atype == "heatmap") {
    gene_note <- if (length(feats)) paste0("`", paste(head(feats, 8L), collapse = if (en) "`, `" else "`、`"), "`") else NULL
    flab <- .ai_feature_label(ctx, locale, plural = TRUE)
    interpretation <- if (en) {
      paste0(
        "Heatmap visualization reveals ", flab, " heterogeneity across samples. ",
        if (length(ecm_hit) && identical(.ai_infer_feature_kind(ctx, feats), "gene")) {
          paste0("Several ECM remodeling genes (", paste(ecm_hit, collapse = ", "),
                 ") show coordinated trends, suggesting stromal remodeling or tissue repair programs. ")
        } else "",
        if (!is.null(gene_note)) paste0("Visible features include ", gene_note, ". ") else "",
        "These patterns may capture biologically meaningful group differences and motivate formal differential and enrichment analyses."
      )
    } else {
      paste0(
        "热图结果显示，不同样本之间的", flab, "模式存在可辨异质性。",
        if (length(ecm_hit) && identical(.ai_infer_feature_kind(ctx, feats), "gene")) {
          paste0("多个细胞外基质重塑相关基因（", paste(ecm_hit, collapse = "、"),
                 "）呈现协同变化趋势，提示 ECM remodeling、纤维化样反应或组织损伤修复可能是重要生物学方向。")
        } else "",
        if (!is.null(gene_note)) paste0("当前可见特征包括 ", gene_note, "。") else "",
        "该模式可为后续差异与功能分析提供线索。"
      )
    }
  } else if (atype %in% c("differential", "diff", "volcano")) {
    interpretation <- if (en) {
      paste0(
        "Differential analysis compares feature abundance/expression between groups. ",
        if (!is.na(n_sig)) paste0(n_sig, " significant feature(s) were detected under current thresholds. ") else "",
        "Interpret effect sizes (log2FC) together with adjusted p-values rather than raw significance alone."
      )
    } else {
      paste0(
        "差异分析比较组间特征丰度/表达变化。",
        if (!is.na(n_sig)) paste0("在当前阈值下检出 ", n_sig, " 个显著特征。") else "",
        "应同时结合 log2FC 与校正 p 值解读，而非只看原始 p 值。"
      )
    }
  } else {
    interpretation <- if (en) {
      paste0(
        .ai_analysis_label(atype, locale),
        " indicates measurable between-group structure in the current cohort. ",
        "In the Results section, first report the primary pattern (separation/convergence/gradient), ",
        "then anchor it to quantitative evidence rather than visual impression alone. ",
        .ai_key_stats_brief(ctx, locale),
        " Frame the finding as association-level evidence and align it with the predefined biological hypothesis."
      )
    } else {
      paste0(
        "本次",
        .ai_analysis_label(atype, locale),
        "结果提示组间存在可量化的整体结构差异。建议在 Results 段按“主模式 → 统计证据 → 生物学指向”三步写作：",
        "先描述分组分离/重叠或连续梯度，再用统计量支撑结论，避免仅凭图形直观判断。",
        .ai_key_stats_brief(ctx, locale),
        "表述层级应控制在“关联性证据”，避免过度机制推断。"
      )
    }
  }

  limitations <- if (kind == "plot" && atype == "heatmap" && hm_profile %in% c("m16s_diff", "m16s_exploratory")) {
    if (en) {
      paste(
        "Amplicon data are compositional (relative abundance sums to 1); shifts in one taxon constrain others—avoid interpreting absolute abundance.",
        "Report FDR/q-values alongside p-values for hundreds of taxa tested.",
        "Taxonomic assignment and genus-level resolution limit strain-specific claims.",
        "Sequencing depth and rarefaction/balancing can bias low-abundance taxa.",
        "Heatmap color alone cannot establish statistical significance or causality without the underlying differential table."
      )
    } else {
      paste(
        "扩增子数据具有组成性（相对丰度总和为 1），某一 taxon 升高会约束其他 taxon，不宜解读为绝对菌量变化。",
        "成百上千 taxa 同时检验时必须报告 FDR/q 值，不能只看原始 p 值。",
        "分类注释与属级分辨率不足以支持菌株特异性机制结论。",
        "测序深度与抽平/平衡策略会影响低丰度菌的稳定性。",
        "仅凭热图颜色不能替代差异分析表格中的统计显著性，更不能推断因果。"
      )
    }
  } else if (kind == "plot" && atype == "heatmap" && !has_deg_stats) {
    if (en) {
      "This heatmap is exploratory and cannot alone prove differential expression. Without formal DESeq2/edgeR/limma statistics (log2FC, adjusted p-values), avoid claiming significant up/down regulation from color alone. Dense gene/sample labels and missing group annotation bars may limit manuscript readability."
    } else {
      "当前热图主要用于探索性表达模式展示，不能单独证明差异表达具有统计显著性。若尚未结合 DESeq2、edgeR 或 limma-voom 的正式结果，不宜仅根据颜色判断显著上调或下调。基因/样本标签过密、分组 annotation 不足时，读者难以快速判断组内一致性与组间差异。"
    }
  } else if (en) {
    "Validate findings with appropriate sample size, multiple-testing correction, and independent replication. Do not infer causality from association plots alone."
  } else {
    "请注意样本量、多重检验校正与独立验证；相关或聚类图 alone 不能推断因果。"
  }

  figure_optimization <- if (kind == "plot") {
    chk <- paste(seq_along(.ai_plot_visual_checklist(locale)), .ai_plot_visual_checklist(locale), sep = ". ", collapse = "\n")
    if (atype == "heatmap") {
      if (hm_profile %in% c("m16s_diff", "m16s_exploratory")) {
        if (en) paste0("Main figure: 10–30 differential taxa at genus level (italics); top group annotation bar; Z-score on CLR/log-ratio; fix scale ~ -2..2; PDF vector export.\n", chk)
        else paste0("主图建议 10–30 个差异菌（属名斜体）；顶部分组 annotation；CLR/log-ratio 后 Z-score；色阶约 -2~2；PDF 矢量导出。\n", chk)
      } else if (en) paste0("Limit main-figure genes to 30-50; fix Z-score to -2..2; add Group/Batch/Time annotation bars; prefer ComplexHeatmap + PDF vector export.\n", chk)
      else paste0("主图建议 30–50 个核心基因；固定 Z-score（如 -2 到 2）；增加 Group/Batch/Time 注释条；ComplexHeatmap + PDF 矢量导出。\n", chk)
    } else chk
  } else {
    if (en) "Turn tabular results into publication-ready figures with emp_pub_theme and consistent palettes." else
      "将表格结果转为发表级图表，统一 emp_pub_theme 与配色。"
  }

  downstream <- paste(.ai_offline_next_steps(atype, omics, locale), collapse = if (en) " " else " ")
  if (hm_profile %in% c("m16s_diff", "m16s_exploratory") && kind == "plot") {
    extra <- if (en) {
      " Run beta-diversity PCoA with PERMANOVA; indicator species / LEfSe; PICRUSt2 functional prediction; validate top taxa by qPCR or shotgun metagenomics; integrate metabolomics/host phenotypes if available."
    } else {
      " 建议补充 Beta 多样性 PCoA + PERMANOVA、指示种/LEfSe、PICRUSt2 功能预测；用 qPCR 或鸟枪法宏基因组验证关键菌；如有条件整合代谢组/宿主表型。"
    }
    downstream <- paste0(downstream, extra)
  } else if (length(ecm_hit) && kind == "plot") {
    extra <- if (en) {
      " Prioritize GO/KEGG/GSEA on ECM organization, collagen fibril organization, TGF-beta signaling, focal adhesion; validate top genes by qPCR/Western blot/IHC."
    } else {
      " 建议优先围绕 ECM organization、collagen fibril organization、TGF-β signaling、focal adhesion 做 GO/KEGG/GSEA，并用 qPCR/Western blot/免疫染色验证核心基因。"
    }
    downstream <- paste0(downstream, extra)
  }

  manuscript <- if (kind == "plot" && atype == "heatmap" && hm_profile %in% c("m16s_diff", "m16s_exploratory")) {
    if (en) {
      "Suitable as a microbiome Results panel (e.g., Figure 2B–C): pair with alpha/beta diversity, differential bar/dot plot, and LEfSe/PICRUSt2; avoid standalone causal claims."
    } else {
      "适合作为微生物组 Results 中的一个 panel（如 Figure 2B–C）：与 alpha/beta 多样性、差异菌柱状/气泡图、LEfSe/PICRUSt2 组合；不宜单独承担因果叙事。"
    }
  } else if (kind == "plot" && atype == "heatmap") {
    if (en) {
      "Suitable as a DEG/expression panel (e.g. Figure 2B). Combine with experimental design, PCA/sample correlation, volcano plot, enrichment bubble plot, GSEA curves, and validation boxplots/qPCR."
    } else {
      "该热图适合作为差异表达结果中的一个 panel（如 Figure 2B）。建议与实验设计、PCA/样本相关性、火山图、GO/KEGG 富集、GSEA 曲线及 qPCR/箱线图验证组合，形成完整证据链。"
    }
  } else if (en) {
    "Place this output in the Results section alongside the analysis that generated it; pair with a validation or enrichment panel where possible."
  } else {
    "将该结果置于论文 Results 对应分析小节，并尽量与验证或富集 panel 组合。"
  }

  list(
    interpretation = interpretation,
    limitations = limitations,
    figure_optimization = figure_optimization,
    downstream_guidance = downstream,
    manuscript_panel = manuscript
  )
}

.ai_sections_to_markdown <- function(sections, locale = "zh") {
  en <- .ai_resolve_locale(locale) == "en"
  titles <- if (en) {
    c("Publication-style interpretation", "Statistical & visualization limitations",
      "Figure optimization", "Downstream & experimental guidance", "Manuscript panel suggestion")
  } else {
    c("结果解读", "图形与统计局限", "出图优化建议", "下游分析与机制验证", "文章组图建议")
  }
  keys <- c("interpretation", "limitations", "figure_optimization", "downstream_guidance", "manuscript_panel")
  parts <- character(0)
  for (i in seq_along(keys)) {
    txt <- sections[[keys[i]]] %||% ""
    if (!nzchar(trimws(txt))) next
    parts[[length(parts) + 1L]] <- paste0("## ", titles[i], "\n\n", txt)
  }
  paste(parts, collapse = "\n\n")
}

.ai_parse_llm_sections <- function(text) {
  txt <- trimws(.ai_chr(text))
  if (!nzchar(txt)) return(NULL)
  # Try JSON block first.
  json_txt <- txt
  if (grepl("```", txt)) {
    m <- regmatches(txt, regexpr("```(?:json)?\\s*([\\s\\S]*?)```", txt, perl = TRUE))
    if (length(m)) json_txt <- sub("^```(?:json)?\\s*|```$", "", m[1], perl = TRUE)
  }
  parsed <- tryCatch(jsonlite::fromJSON(json_txt, simplifyVector = FALSE), error = function(e) NULL)
  if (is.list(parsed) && !is.null(parsed$interpretation)) {
    return(list(
      interpretation = .ai_chr(parsed$interpretation),
      limitations = .ai_chr(parsed$limitations),
      figure_optimization = .ai_chr(parsed$figure_optimization),
      downstream_guidance = .ai_chr(parsed$downstream_guidance %||% parsed$downstream),
      manuscript_panel = .ai_chr(parsed$manuscript_panel_suggestion %||% parsed$manuscript_panel),
      prompt_buttons = parsed$prompt_buttons %||% NULL
    ))
  }
  NULL
}

# ---------------------------------------------------------------------------
# Offline, deterministic interpretation (always available).
# ---------------------------------------------------------------------------
.ai_offline_next_steps <- function(atype, omics, locale = "zh") {
  atype <- tolower(trimws(.ai_chr(atype)))
  omics <- tolower(trimws(.ai_chr(omics)))
  en <- .ai_resolve_locale(locale) == "en"
  base <- if (en) {
    switch(atype,
      differential = c(
        "Use Visualize ▸ Volcano to show up/down regulated features.",
        "Run Enrichment (Analysis ▸ Enrichment, KEGG/GO) on significant hits.",
        "Plot a DEG heatmap to inspect expression patterns across samples.",
        "If groups are imbalanced or batch effects exist, add covariates or normalize first."
      ),
      volcano = c(
        "Export significant features from the volcano arms and run enrichment.",
        "Tighten cutoffs using both log2FC and p_adj to reduce false positives."
      ),
      alpha = c(
        "Confirm alpha diversity differences with boxplots + Wilcoxon/Kruskal tests.",
        "Follow with beta diversity (PCoA/ordination) to see community separation.",
        "Rarefy first if sequencing depth varies widely between samples."
      ),
      dimension = c(
        "Test ordination separation with PERMANOVA or group-wise tests.",
        "If groups overlap on PC1/PC2, try other distances (Bray-Curtis/Aitchison) or normalization.",
        "Combine with differential analysis to find drivers of separation."
      ),
      scatter = c(
        "Test ordination separation with PERMANOVA or group-wise tests.",
        "If groups overlap on PC1/PC2, try other distances (Bray-Curtis/Aitchison) or normalization.",
        "Combine with differential analysis to find drivers of separation."
      ),
      correlation = c(
        "Scatter/fit plots for strong pairs to check linear vs non-linear trends.",
        "Correlation is not causation—validate with groups and clinical covariates.",
        "Build a co-occurrence network (Analysis ▸ Network) to inspect modules."
      ),
      cluster = c(
        "Compare cluster labels to known biological groups.",
        "Sort a heatmap by cluster to visualize feature patterns.",
        "Try different k or methods (kmeans/ward) to test robustness."
      ),
      marker = c(
        "Annotate top biomarkers and check the literature.",
        "Use cross-validation to assess model stability and avoid overfitting."
      ),
      marker_model = c(
        "Use cross-validation / hold-out tests for generalization.",
        "Annotate top important features biologically.",
        "Report AUC/accuracy vs a random baseline."
      ),
      enrichment = c(
        "Focus on pathways with p_adj < 0.05 and interpret direction (up/down).",
        "Show results with pathway networks or dot plots.",
        "Compare enriched pathways across omics layers for consistent signals."
      ),
      network = c(
        "Identify high-degree hub nodes—they often regulate modules.",
        "Partition modules and link them to groups or traits (e.g. WGCNA)."
      ),
      c(
        "Turn results into publication-ready figures in Visualize.",
        "Cross-check findings with other analyses in your workflow.",
        "Record your interpretation and next hypothesis in Course reflections."
      )
    )
  } else {
    switch(atype,
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
      dimension = c(
        "用 PERMANOVA / 组间检验评估排序上的分离是否统计显著。",
        "若分组在前两轴未分开，尝试不同距离 (Bray-Curtis/Aitchison) 或先归一化。",
        "结合差异分析找出驱动分离的关键特征。"
      ),
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
      marker = c(
        "对 Top 标志物做生物学注释与文献核对。",
        "用交叉验证评估模型稳定性，避免过拟合。"
      ),
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
  }
  extra <- character(0)
  if (omics %in% c("microbiome_16s", "m16s", "16s")) {
    extra <- if (en) c("Use Sankey/composition plots for phylum-genus taxonomy.") else
      c("可用 Sankey/组成图展示门-属层级的分类组成。")
  } else if (omics %in% c("rnaseq", "transcriptomics")) {
    extra <- if (en) c("For RNA-seq, prefer DESeq2/edgeR on raw counts, not normalized matrices.") else
      c("RNA-seq 差异建议用 DESeq2/edgeR (基于原始计数)，而非已归一化矩阵。")
  } else if (omics %in% c("metabolomics", "mbx")) {
    extra <- if (en) c("Impute missing values and normalize (log/Pareto) before differential tests.") else
      c("代谢组先处理缺失值 (impute) 与归一化 (log/Pareto) 再做差异。")
  } else if (omics %in% c("chipseq")) {
    extra <- if (en) c(
      "For ChIP-seq, start from BAM-level peak calling (MACS2/3), annotate peaks (ChIPseeker), then integrate peak-linked genes with RNA/proteomics differential signatures."
    ) else c(
      "ChIP-seq 建议从 BAM 调峰（MACS2/3）开始，随后用 ChIPseeker 注释，再与 RNA/proteomics 差异结果交叉。"
    )
  }
  c(base, extra)
}

# Publication-quality plot checklist (offline + LLM reference).
.ai_plot_visual_checklist <- function(locale = "zh") {
  if (.ai_resolve_locale(locale) == "en") {
    return(c(
      "Palette: emp_pub_palette() / emp_set_color_panel(); color-blind friendly groups",
      "Theme: emp_pub_theme(base_size = 12); consistent margins and grid",
      "Axes: complete titles/units; readable tick labels (rotate if needed)",
      "Legend: sensible position (bottom/right); must not cover data",
      "Labels: ggrepel or top-N when overcrowded",
      "Contrast: white background; print-ready PDF/PNG (>= 300 dpi)"
    ))
  }
  c(
    "配色：emp_pub_palette() / emp_set_color_panel()，组间可区分、色盲友好",
    "主题：emp_pub_theme(base_size = 12) 统一字号、边距与网格",
    "坐标轴：轴标题与单位完整，刻度标签可读、必要时旋转",
    "图例：位置合理（bottom/right），不遮挡数据点",
    "标签：点/基因名过多时用 ggrepel 或限制 top-N",
    "对比度：背景白底、线宽/点大小适合印刷（PDF ≥ 300 dpi）"
  )
}

# Map analysis context → Code Lab actions (one-click apply in UI).
.ai_build_actions <- function(ctx, locale = "zh") {
  atype <- tolower(trimws(.ai_chr(ctx$analysis_type)))
  omics <- tolower(trimws(.ai_chr(ctx$omics)))
  kind <- tolower(trimws(.ai_chr(ctx$kind, "table")))
  en <- .ai_resolve_locale(locale) == "en"
  actions <- list()

  add <- function(label, workflow, tab, instruction, auto_optimize = TRUE) {
    actions[[length(actions) + 1L]] <<- list(
      label = label, workflow = workflow, tab = tab,
      instruction = instruction, auto_optimize = isTRUE(auto_optimize)
    )
  }

  pub_theme_inst <- if (en) {
    paste(
      "Improve publication-quality plotting while keeping analysis logic:",
      "1) emp_pub_theme(base_size = 12, legend.position = 'right');",
      "2) emp_pub_palette() or emp_set_color_panel();",
      "3) readable axis labels; ggrepel if needed;",
      "4) last line returns ggplot or plot_to_base64 PNG."
    )
  } else {
    paste(
      "在保留现有分析逻辑的前提下优化发表级出图：",
      "1) 使用 emp_pub_theme(base_size = 12, legend.position = 'right')；",
      "2) 使用 emp_pub_palette() 或 emp_set_color_panel() 保证色盲友好；",
      "3) 轴标签与标题完整可读，必要时 ggrepel 防重叠；",
      "4) 最后一行返回 ggplot 对象或 plot_to_base64() 的 base64 PNG。"
    )
  }

  if (kind == "plot") {
    add(if (en) "Beautify plot (Code Lab)" else "🎨 一键美化当前图表（Code Lab）", "visualization",
        switch(atype, volcano = "viz-volcano", heatmap = "viz-heatmap",
               scatter = "viz-scatter", alpha = "viz-alpha", barplot = "viz-barplot",
               boxplot = "viz-boxplot", structure = "viz-structure", "viz-barplot"),
        pub_theme_inst)
  }

  if (atype %in% c("differential", "diff", "volcano")) {
    add(if (en) "Tune volcano thresholds & labels" else "优化火山图阈值与标签", "visualization", "viz-volcano",
        paste(pub_theme_inst, if (en) "Highlight |log2FC|>1 & padj<0.05; color up vs down." else
                "突出 |log2FC|>1 且 padj<0.05 的点，用颜色区分上下调。"))
    add(if (en) "Run KEGG enrichment (Analyze)" else "运行 KEGG 富集（Analyze）", "analysis", "ana-enrich",
        if (en) "Write clusterProfiler enrichKEGG from the current DE table; keep session_id/experiment." else
          "基于当前差异结果表，编写 clusterProfiler enrichKEGG 流程，保留 session_id/experiment。")
  }
  if (atype %in% c("alpha", "dimension", "scatter")) {
    add(if (en) "Improve alpha/ordination group colors" else "优化 Alpha/排序图分组配色", "visualization",
        if (atype == "alpha") "viz-alpha" else "viz-scatter", pub_theme_inst)
  }
  if (atype %in% c("heatmap")) {
    add(if (en) "Improve heatmap clustering & annotations" else "优化热图行聚类与注释条", "visualization", "viz-heatmap",
        paste(pub_theme_inst, if (en) "Use pheatmap or ggplot heatmap; scale rows; annotate columns by group." else
                "使用 pheatmap 或 ggplot heatmap，行 scale，列注释为分组。"))
  }
  if (omics %in% c("microbiome_16s", "m16s", "16s")) {
    add(if (en) "16S Sankey composition" else "16S Sankey 组成图", "visualization", "viz-m16s-sankey",
        if (en) "Phylum-genus Sankey with emp_pub_theme; return ggplot or base64 PNG." else
          "生成门-属层级 Sankey，emp_pub_theme，最后一行返回 ggplot/base64。")
  }
  if (omics %in% c("transcriptomics", "rnaseq")) {
    add(if (en) "Optimize RNA-seq Run All script" else "RNA-seq Run All 脚本优化", "runall", "runall-rnaseq",
        if (en) "Optimize DESeq2+volcano+heatmap+GSEA script; keep user group vars and cutoffs." else
          "优化一键 DESeq2+火山+热图+GSEA 脚本，保留用户分组变量与阈值。")
  }

  if (!length(actions)) {
    steps <- .ai_offline_next_steps(atype, omics, locale)
    if (length(steps)) {
      add(if (en) "Apply next step to Code Lab" else "应用下一步建议到 Code Lab", "analysis", "ana-diff",
          if (en) paste("Based on results:", steps[1]) else paste("根据当前结果：", steps[1]), FALSE)
    }
  }
  actions
}

.ai_offline_interpretation <- function(ctx) {
  locale <- .ai_resolve_locale(ctx$locale %||% ctx$lang)
  atype <- .ai_chr(ctx$analysis_type, "analysis")
  omics <- .ai_chr(ctx$omics)
  st <- ctx$stats %||% list()
  tbl <- ctx$table %||% list()
  en <- .ai_resolve_locale(locale) == "en"

  parts <- character(0)
  push <- function(...) parts[[length(parts) + 1L]] <<- paste0(...)

  push("## ", .ai_analysis_label(atype, locale),
       if (en) " — interpretation\n\n" else " 解读\n\n")

  overview <- character(0)
  n_sig <- .ai_num(st$n_significant %||% st$n_sig)
  n_total <- .ai_num(st$n_total %||% tbl$n_rows)
  if (!is.na(n_sig)) {
    msg <- if (en) {
      paste0("**", n_sig, "** significant feature(s) detected")
    } else {
      paste0("本次分析共检出 **", n_sig, "** 个显著特征")
    }
    if (!is.na(n_total)) {
      msg <- paste0(msg, if (en) paste0(" (of ", n_total, " tested).") else paste0("（候选 ", n_total, " 个）。"))
    } else msg <- paste0(msg, if (en) "." else "。")
    if (!is.na(n_sig) && n_sig == 0) {
      msg <- paste0(msg, if (en) " None passed thresholds—check effect size, sample size, or cutoffs." else
                      " 没有达到显著阈值，可能是效应较弱、样本量不足或阈值过严。")
    }
    overview <- c(overview, msg)
  }
  n_up <- .ai_num(st$n_up); n_down <- .ai_num(st$n_down)
  if (!is.na(n_up) || !is.na(n_down)) {
    up_s <- if (is.na(n_up)) 0 else n_up
    down_s <- if (is.na(n_down)) 0 else n_down
    overview <- c(overview, if (en) paste0("Up: ", up_s, "; Down: ", down_s, ".") else
                    paste0("其中上调 ", up_s, " 个、下调 ", down_s, " 个。"))
  }
  if (!length(overview)) {
    overview <- if (en) paste0(.ai_analysis_label(atype, locale), " results are ready.") else
      paste0("已生成 ", .ai_analysis_label(atype, locale), " 结果。")
  }
  push("**", if (en) "Overview" else "结果概览", "**\n\n", paste(overview, collapse = " "), "\n")

  # Top features, if provided.
  rows <- tbl$rows %||% NULL
  if (!is.null(rows) && length(rows)) {
    feat_key <- intersect(c("feature", "Feature", "name", "id", "gene", "taxa"), names(rows[[1L]]))
    if (length(feat_key)) {
      fk <- feat_key[1L]
      tops <- vapply(rows[seq_len(min(length(rows), 6L))], function(r) .ai_chr(r[[fk]]), character(1))
      tops <- tops[nzchar(tops)]
      if (length(tops)) push("**", if (en) "Notable features" else "值得关注的特征", "**\n\n",
                              paste0("`", tops, "`", collapse = if (en) ", " else "、"), "\n")
    }
  }

  framing <- if (en) {
    switch(tolower(trimws(atype)),
      differential = "Differential analysis compares feature abundance/expression between groups. Prefer padj over raw p-values.",
      volcano = "Volcano: x = log2FC, y = -log10(p). Top-right/left points are most interesting.",
      alpha = "Alpha diversity reflects richness/evenness within samples. Use non-parametric tests between groups.",
      "Interpret this step together with upstream/downstream analyses in your workflow."
    )
  } else {
    switch(tolower(trimws(atype)),
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
  }
  push("**", if (en) "Biological interpretation" else "生物学解读", "**\n\n", framing, "\n")

  caveats <- if (en) {
    c(
      "Small sample sizes weaken conclusions—check replicates per group.",
      "Use adjusted p-values (padj/FDR) for multiple testing.",
      "Statistical significance is not the same as biological importance."
    )
  } else {
    c(
      "样本量小时结论不稳健，注意每组重复数。",
      "多重检验务必看校正后的 p 值 (p_adj/FDR)。",
      "显著 ≠ 生物学重要，结合效应量与先验知识判断。"
    )
  }
  push("**", if (en) "Caveats" else "注意事项", "**\n\n", paste0("- ", caveats, collapse = "\n"), "\n")

  steps <- .ai_offline_next_steps(atype, omics, locale)
  push("**", if (en) "Next steps" else "下一步建议", "**\n\n",
       paste0(seq_along(steps), ". ", steps, collapse = "\n"), "\n")

  kind <- tolower(trimws(.ai_chr(ctx$kind, "table")))
  if (identical(kind, "plot")) {
    chk <- .ai_plot_visual_checklist(locale)
    push("**", if (en) "Publication visual checklist" else "发表级视觉 checklist", "**\n\n",
         paste0(seq_along(chk), ". ", chk, collapse = "\n"), "\n\n")
  }

  list(text = paste(parts, collapse = "\n"), next_steps = steps,
       actions = .ai_build_actions(ctx, locale),
       visual_checklist = if (identical(kind, "plot")) .ai_plot_visual_checklist(locale) else character(0))
}

# ---------------------------------------------------------------------------
# LLM layer
# ---------------------------------------------------------------------------
.ai_system_prompt <- function(kind = "table", locale = "zh", output_language = NULL, ctx = NULL) {
  ol <- output_language %||% .ai_output_language(locale)
  lang_rule <- paste0(
    "Output language: ", ol, "\n",
    "- Answer ONLY in ", ol, ".\n",
    "- Do NOT infer language from gene names, code, file names, or dataset names.\n",
    if (ol == "zh-CN") "- Use professional Chinese academic writing.\n" else
      "- Use concise American academic English.\n"
  )
  json_rule <- paste(
    "Return a single JSON object (no markdown outside JSON) with keys:",
    "interpretation, limitations, figure_optimization, downstream_guidance, manuscript_panel, prompt_buttons.",
    "prompt_buttons is an array of {label, prompt} with 3-5 items for Code Lab optimization.",
    sep = "\n"
  )
  heatmap_rule <- if (identical(tolower(kind), "plot") && !is.null(ctx) &&
                      tolower(.ai_chr(ctx$analysis_type)) == "heatmap") {
    .ai_heatmap_plot_rules(ctx, locale)
  } else if (identical(tolower(kind), "plot")) {
    if (.ai_resolve_locale(locale) == "en") {
      "Section 2: critique as a reviewer (missing stats, batch effects, feature count, annotations). Section 3: concrete figure optimization."
    } else {
      "模块2模拟审稿人视角；模块3给出可操作的出图优化。"
    }
  } else ""
  if (.ai_resolve_locale(locale) == "en") {
    return(paste(
      "You are an expert bioinformatics assistant embedded in EasyMultiProfiler (EMP).",
      lang_rule,
      "Interpret results in a publication-oriented, biologically meaningful, method-aware manner.",
      "Write `interpretation` at near-journal (CNS-style) quality: concise, evidence-anchored, and hypothesis-linked.",
      "For `interpretation`, follow exactly: (1) Main pattern in one sentence; (2) Quantitative evidence sentence; (3) Biological implication sentence; (4) Conservative claim boundary sentence.",
      "Do not use vague filler such as 'results are ready' or generic teaching placeholders.",
      "Do not invent statistics not provided. Do not claim causality from heatmaps alone.",
      heatmap_rule,
      json_rule,
      sep = "\n"
    ))
  }
  paste(
    "你是 EasyMultiProfiler (EMP) 多组学平台的专家级生物信息解读助手。",
    lang_rule,
    "任务不是解释基本概念，而是论文式结果解读、图形审稿式局限诊断、下游分析导航与代码优化入口。",
    "interpretation 字段必须达到高水平论文 Results 段风格：简洁、证据锚定、与科学问题强关联。",
    "interpretation 必须严格按 4 句结构输出：1) 主模式句；2) 定量证据句；3) 生物学指向句；4) 保守结论边界句。",
    "禁止使用“结果已生成”“可见差异”等空泛模板句。",
    "不要编造未提供的统计显著性；热图 alone 不能推断因果。",
    heatmap_rule,
    json_rule,
    sep = "\n"
  )
}

# Normalise a base64 / data-URL plot string into a data URL the vision APIs accept.
.ai_image_data_url <- function(img) {
  s <- trimws(.ai_chr(img))
  if (!nzchar(s)) return(NULL)
  if (grepl("^data:image/", s)) return(s)
  s <- gsub("\\s", "", s)
  if (!grepl("^[A-Za-z0-9+/=]+$", s)) return(NULL)
  if (nchar(s) < 200L) return(NULL)
  paste0("data:image/png;base64,", s)
}

# Pick the campus vision model when a plot image is supplied.
.ai_campus_vision_model <- function(cfg) {
  builtin <- .llm_campus_builtin_cfg()
  models <- cfg$campus_models %||% list()
  v <- trimws(.ai_chr(models$vision %||% builtin$models$vision))
  if (nzchar(v)) v else "Qwen3-VL-8B-Instruct"
}

.ai_llm_chat <- function(provider, cfg, system_prompt, user_prompt, plot_image = NULL) {
  provider <- tolower(trimws(.ai_chr(provider, "campus")))
  if (identical(provider, "campus")) cfg <- .llm_campus_merge_cfg(cfg)
  d <- .llm_provider_defaults(provider, cfg)
  provider <- d$provider
  key <- trimws(.ai_chr(cfg$api_key))
  timeout <- .ai_num(cfg$timeout, 120); if (is.na(timeout) || timeout <= 0) timeout <- 120
  temperature <- .ai_num(cfg$temperature, 0.4)
  max_tokens <- as.integer(.ai_num(cfg$max_tokens, 1100))
  img_url <- .ai_image_data_url(plot_image)

  if (provider %in% c("chatgpt", "openai", "deepseek", "qwen", "minimax", "nvidia", "custom", "campus")) {
    if (!nzchar(key)) stop(sprintf("API key required for provider: %s", provider))
    url <- paste0(d$base_url, "/chat/completions")
    model <- d$model
    user_content <- user_prompt
    if (!is.null(img_url)) {
      # OpenAI-compatible multimodal message; campus switches to its vision model.
      if (identical(provider, "campus")) model <- .ai_campus_vision_model(cfg)
      user_content <- list(
        list(type = "text", text = user_prompt),
        list(type = "image_url", image_url = list(url = img_url))
      )
    }
    body <- list(model = model, messages = list(
      list(role = "system", content = system_prompt),
      list(role = "user", content = user_content)
    ), max_tokens = max_tokens, temperature = temperature)
    resp <- .llm_call_curl(url, c(paste0("Authorization: Bearer ", key)), body, timeout)
    return(.llm_extract_text(resp))
  }
  if (identical(provider, "claude")) {
    if (!nzchar(key)) stop("API key required for provider: claude")
    url <- paste0(d$base_url, "/messages")
    user_content <- user_prompt
    if (!is.null(img_url)) {
      b64 <- sub("^data:image/png;base64,", "", img_url)
      user_content <- list(
        list(type = "image", source = list(type = "base64", media_type = "image/png", data = b64)),
        list(type = "text", text = user_prompt)
      )
    }
    body <- list(model = d$model, max_tokens = max_tokens, temperature = temperature,
                 system = system_prompt, messages = list(list(role = "user", content = user_content)))
    resp <- .llm_call_curl(url, c(paste0("x-api-key: ", key), "anthropic-version: 2023-06-01"), body, timeout)
    return(.llm_extract_text(resp))
  }
  if (identical(provider, "gemini")) {
    if (!nzchar(key)) stop("API key required for provider: gemini")
    url <- paste0(d$base_url, "/models/", utils::URLencode(d$model, reserved = TRUE),
                  ":generateContent?key=", utils::URLencode(key, reserved = TRUE))
    parts <- list(list(text = user_prompt))
    if (!is.null(img_url)) {
      b64 <- sub("^data:image/png;base64,", "", img_url)
      parts <- list(list(text = user_prompt),
                    list(inline_data = list(mime_type = "image/png", data = b64)))
    }
    body <- list(
      systemInstruction = list(parts = list(list(text = system_prompt))),
      contents = list(list(parts = parts))
    )
    resp <- .llm_call_curl(url, character(0), body, timeout)
    return(.llm_extract_text(resp))
  }
  stop(sprintf("Unsupported LLM provider for copilot: %s", provider))
}

# Main entry: returns interpretation text, structured sections, source, and next steps.
ai_interpret <- function(ctx, provider = NULL, cfg = NULL, personalization = NULL) {
  ctx <- ctx %||% list()
  locale <- .ai_resolve_locale(ctx$locale %||% ctx$lang)
  ctx$locale <- locale
  output_language <- .ai_output_language(locale)
  summary_txt <- .ai_summarise_context(ctx)
  offline <- .ai_offline_interpretation(ctx)
  sections <- .ai_offline_structured(ctx)
  prompt_buttons <- .ai_build_prompt_buttons(ctx, locale)
  structured_text <- .ai_sections_to_markdown(sections, locale)

  provider <- tolower(trimws(.ai_chr(provider, .ai_chr(cfg$provider, ""))))
  has_key <- nzchar(trimws(.ai_chr((cfg %||% list())$api_key)))
  want_llm <- nzchar(provider) && !identical(provider, "offline") &&
    (identical(provider, "campus") || has_key)
  en <- locale == "en"

  pack_response <- function(source, interpretation, sections_out, buttons, extra = list()) {
    c(list(
      success = TRUE,
      source = source,
      provider = provider %||% "offline",
      locale = locale,
      output_language = output_language,
      interpretation = interpretation,
      sections = sections_out,
      prompt_buttons = buttons,
      next_steps = offline$next_steps,
      actions = offline$actions,
      visual_checklist = offline$visual_checklist %||% character(0),
      context_summary = summary_txt
    ), extra)
  }

  if (want_llm) {
    kind <- tolower(trimws(.ai_chr(ctx$kind, "table")))
    plot_image <- .ai_image_data_url(ctx$plot_image %||% ctx$image %||% NULL)
    has_image <- !is.null(plot_image)
    pers <- personalization %||% list()
    pers_txt <- if (length(pers) && nzchar(.ai_chr(pers$summary))) {
      if (en) paste0("\n\nUser profile hint: ", .ai_chr(pers$summary)) else
        paste0("\n\n用户画像提示：", .ai_chr(pers$summary))
    } else ""
    heatmap_supp <- if (identical(kind, "plot") && tolower(.ai_chr(ctx$analysis_type)) == "heatmap") {
      .ai_heatmap_supplement(ctx, locale)
    } else ""
    user_prompt <- paste0(
      if (en) "A student just finished an EMP analysis step. Context:\n\n" else
        "学生刚刚在 EMP 平台完成了一步分析。以下是结果上下文：\n\n",
      summary_txt,
      if (identical(kind, "plot") && has_image) {
        if (en) "\n\n[Plot image attached] Critique publication readiness." else
          "\n\n【附带图表图像】请从发表角度点评该图。"
      } else if (identical(kind, "plot")) {
        if (en) "\n\n[Plot result] Apply visualization critique." else
          "\n\n【图表结果】请进行图形审稿式评价。"
      } else "",
      heatmap_supp,
      pers_txt,
      if (en) paste0("\n\nRespond ONLY in ", output_language, " as JSON per system instructions.") else
        paste0("\n\n请仅使用 ", output_language, "，并按系统说明返回 JSON。")
    )
    llm_err <- NULL
    out <- tryCatch(.ai_llm_chat(provider, cfg, .ai_system_prompt(kind, locale, output_language, ctx), user_prompt, plot_image),
                    error = function(e) {
                      llm_err <<- conditionMessage(e)
                      NULL
                    })
    parsed <- if (!is.null(out)) .ai_parse_llm_sections(out) else NULL
    if (!is.null(parsed)) {
      sec <- list(
        interpretation = parsed$interpretation %||% sections$interpretation,
        limitations = parsed$limitations %||% sections$limitations,
        figure_optimization = parsed$figure_optimization %||% sections$figure_optimization,
        downstream_guidance = parsed$downstream_guidance %||% sections$downstream_guidance,
        manuscript_panel = parsed$manuscript_panel %||% sections$manuscript_panel
      )
      btns <- parsed$prompt_buttons %||% prompt_buttons
      if (is.data.frame(btns)) btns <- as.list(as.data.frame(t(btns), stringsAsFactors = FALSE))
      return(pack_response("llm", .ai_sections_to_markdown(sec, locale), sec, btns,
                             list(vision = has_image)))
    }
    if (!is.null(out) && nzchar(trimws(out))) {
      return(pack_response("llm", out, sections, prompt_buttons,
                           list(vision = has_image, llm_format = "markdown_fallback")))
    }
    return(pack_response("offline", structured_text, sections, prompt_buttons,
                         list(llm_error = llm_err %||% if (en) "LLM unavailable; using local rules." else "LLM 不可用，已使用本地解读。")))
  }

  pack_response("offline", structured_text, sections, prompt_buttons)
}

plumber_ai_interpret_post <- function(req, res) {
  safe_api({
    b <- jsonlite::fromJSON(req$postBody, simplifyVector = FALSE)
    ctx <- b$context %||% b
    loc <- b$locale %||% ctx$locale %||% ctx$lang %||% NULL
    if (!is.null(loc)) {
      ctx$locale <- loc
      ctx$lang <- loc
    }
    provider <- b$provider %||% (b$config %||% list())$provider %||% NULL
    cfg <- b$config %||% list()
    user_id <- b$user_id %||% req$HTTP_X_EMP_USER_ID %||% NULL
    personalization <- NULL
    if (!is.null(user_id) && nzchar(trimws(as.character(user_id)))) {
      personalization <- tryCatch(
        (evolution_get_profile(user_id)$personalization %||% NULL),
        error = function(e) NULL
      )
    }
    res_out <- ai_interpret(ctx, provider = provider, cfg = cfg, personalization = personalization)
    if (!is.null(user_id) && nzchar(trimws(as.character(user_id)))) {
      tryCatch(evolution_record_event(
        user_id = user_id,
        session_id = b$session_id %||% req$HTTP_X_SESSION_ID,
        event_type = "ai_interpret",
        payload = list(
          locale = ctx$locale,
          omics = ctx$omics,
          analysis_type = ctx$analysis_type,
          source = res_out$source
        )
      ), error = function(e) NULL)
    }
    res_out
  }, res)
}
