/**
 * UI locale: Auto (browser + region hint) or manual 中文 / English.
 * Dispatches emp:locale-change when the active locale changes.
 */
import { I18N_CATALOG } from "./i18n_catalog.js?v=chipseq-downstream-v1";
import { applyDomI18n } from "./ui_dom_i18n.js?v=chipseq-downstream-v1";

const LS_MODE = "emp_ui_locale_mode"; // auto | zh | en
const LS_RESOLVED = "emp_ui_locale_resolved";

const I18N_CORE = {
  zh: {
    "nav.guide": "指南",
    "nav.course": "课程",
    "nav.prompts": "AI 提示",
    "nav.data": "数据",
    "nav.summary": "概览",
    "nav.inspector": "检查",
    "nav.prepare": "预处理",
    "nav.analyze": "分析",
    "nav.chipseq": "ChIPseq",
    "nav.chipseq_downstream": "ChIPseq-下游分析",
    "nav.clinical": "临床",
    "nav.runall": "一键运行",
    "nav.visualize": "可视化",
    "nav.export": "导出",
    "page.guide": "使用指南",
    "page.course": "Course 课程",
    "page.prompts": "AI Prompt 库",
    "page.import": "导入数据",
    "page.summary": "数据概览",
    "page.inspector": "EMPT 检查器",
    "page.preparation": "数据预处理",
    "page.analysis": "分析",
    "page.chipseq": "ChIP-seq 分析",
    "page.chipseq_downstream": "ChIPseq-下游分析",
    "chip.wizard.step1": "上传与调峰",
    "chip.wizard.step2": "一键配方",
    "chip.wizard.advanced": "高级单步",
    "chip.hint.unified": "同页两步：① 上传峰 / BAM / MACS；② 一键配方（ChIP 内 + 跨组学联合）。其他组学请先在 Import / 分析页准备好矩阵或 DE 结果。",
    "chip.recipe.intro": "选择 ChIP 内包或跨组学联合包。依赖面板需指向已导入的 RNA / 蛋白 / 16S / MGX / MBX / 临床实验（或 DE 缓存）。",
    "chip.deps.title": "依赖面板",
    "chip.recipe.combo": "自定义组合一键",
    "page.clinical": "临床表型",
    "chip.browseFolder": "打开文件夹",
    "chipds.intro": "Peak 下游分析清单（来自 Excel）：在 ChIPseeker 注释之后或并行推进的 QC、注释、motif、差异结合、多组学整合等模块。可运行项会跳转到现有 ChIP-seq 工作区（§4–§6），或在本页执行 Peak QC / HOMER / DiffBind / deepTools。",
    "chipds.filters": "筛选",
    "chipds.filter.stage": "阶段",
    "chipds.filter.priority": "优先级",
    "chipds.filter.bam": "BAM 需求",
    "chipds.filter.status": "状态",
    "chipds.filter.search": "搜索",
    "chipds.tools": "下游工具面板",
    "chipds.marks": "Mark 策略速查",
    "chipds.catalog": "下游模块目录",
    "chipds.results": "运行结果",
    "page.runall": "一键 Run All",
    "page.visualization": "可视化",
    "page.export": "导出结果",
    "wf.guide": "指南",
    "wf.course": "课程",
    "wf.prompts": "AI",
    "wf.import": "数据",
    "wf.summary": "概览",
    "wf.inspector": "检查",
    "wf.preparation": "预处理",
    "wf.analysis": "分析",
    "wf.clinical": "临床",
    "wf.runall": "一键",
    "wf.visualization": "可视化",
    "wf.export": "导出",
    "locale.label": "界面语言",
    "locale.auto": "自动",
    "fontScale.label": "字号",
    "fontScale.smaller": "缩小字号",
    "fontScale.larger": "放大字号",
    "fontScale.reset": "恢复默认字号",
    "locale.hint.auto": "自动识别",
    "locale.hint.browser": "浏览器语言",
    "locale.hint.manual": "已手动选择",
    "footer.guide": "安装与使用指南",
    "footer.course": "Course 入门",
    "footer.docs": "文档",
    "copilot.btn": "AI 解读结果",
    "copilot.loading": "AI 正在解读结果…",
    "copilot.src.llm": "AI 模型",
    "copilot.src.offline": "本地解读",
    "copilot.src.vision": "已读图",
    "copilot.disclaimer": "AI 生成内容仅供学习参考，请结合统计与生物学知识判断。",
    "copilot.actions.hint": "可执行建议（一键填入 Code Lab）：",
    "copilot.checklist.summary": "发表级视觉 checklist",
    "copilot.toast.applied": "已填入 Code Lab 优化说明",
    "copilot.error": "AI 解读失败：",
    "copilot.action.default": "应用",
    "copilot.card.interpretation": "结果解读",
    "copilot.card.limitations": "图形与统计局限",
    "copilot.card.figure": "出图优化建议",
    "copilot.card.downstream": "下游分析与机制验证",
    "copilot.card.manuscript": "文章组图建议",
    "copilot.prompt.hint": "一键填入 Code Lab 优化：",
    "guide.copy": "复制命令",
    "guide.copied": "已复制 ✓",
  },
  en: {
    "nav.guide": "Guide",
    "nav.course": "Course",
    "nav.prompts": "AI Prompts",
    "nav.data": "Data",
    "nav.summary": "Summary",
    "nav.inspector": "Inspector",
    "nav.prepare": "Prepare",
    "nav.analyze": "Analyze",
    "nav.chipseq": "ChIPseq",
    "nav.chipseq_downstream": "ChIPseq Downstream",
    "nav.clinical": "Clinical",
    "nav.runall": "Run All",
    "nav.visualize": "Visualize",
    "nav.export": "Export",
    "page.guide": "User Guide",
    "page.course": "Course Cases",
    "page.prompts": "AI Prompt Library",
    "page.import": "Import Data",
    "page.summary": "Data Summary",
    "page.inspector": "EMPT Inspector",
    "page.preparation": "Data Preparation",
    "page.analysis": "Analysis",
    "page.chipseq": "ChIP-seq Analysis",
    "page.chipseq_downstream": "ChIPseq Downstream",
    "chip.wizard.step1": "Upload & peaks",
    "chip.wizard.step2": "One-click packs",
    "chip.wizard.advanced": "Advanced",
    "chip.hint.unified": "Two steps on one page: (1) upload peaks / BAM / MACS; (2) one-click packs (ChIP-internal + cross-omics). Prepare other omics on Import / Analyze first (matrix or DE).",
    "chip.recipe.intro": "Pick ChIP-internal or joint packs. Dependency panel must point at imported RNA / protein / 16S / MGX / MBX / clinical (or DE caches).",
    "chip.deps.title": "Dependencies",
    "chip.recipe.combo": "Custom combo one-click",
    "page.clinical": "Clinical & Phenotype",
    "page.runall": "One-click Run All",
    "page.visualization": "Visualization",
    "page.export": "Export Results",
    "chip.browseFolder": "Browse folder",
    "chipds.intro": "Peak downstream checklist (from Excel): QC, annotation, motif, differential binding, and multi-omics modules after or parallel to ChIPseeker. Runnable items deep-link into the ChIP-seq workspace (§4–§6), or run Peak QC / HOMER / DiffBind / deepTools on this page.",
    "chipds.filters": "Filters",
    "chipds.filter.stage": "Stage",
    "chipds.filter.priority": "Priority",
    "chipds.filter.bam": "BAM need",
    "chipds.filter.status": "Status",
    "chipds.filter.search": "Search",
    "chipds.tools": "Downstream tool panel",
    "chipds.marks": "Mark strategies",
    "chipds.catalog": "Downstream catalog",
    "chipds.results": "Run results",
    "wf.guide": "Guide",
    "wf.course": "Course",
    "wf.prompts": "AI",
    "wf.import": "Data",
    "wf.summary": "Summary",
    "wf.inspector": "Inspect",
    "wf.preparation": "Prep",
    "wf.analysis": "Analyze",
    "wf.clinical": "Clinical",
    "wf.runall": "Run",
    "wf.visualization": "Visualize",
    "wf.export": "Export",
    "locale.label": "Language",
    "locale.auto": "Auto",
    "fontScale.label": "Text size",
    "fontScale.smaller": "Decrease text size",
    "fontScale.larger": "Increase text size",
    "fontScale.reset": "Reset text size",
    "locale.hint.auto": "Auto-detected",
    "locale.hint.browser": "browser language",
    "locale.hint.manual": "Manual",
    "footer.guide": "Install & user guide",
    "footer.course": "Course intro",
    "footer.docs": "Docs",
    "copilot.btn": "AI interpret",
    "copilot.loading": "AI is interpreting…",
    "copilot.src.llm": "AI model",
    "copilot.src.offline": "Local rules",
    "copilot.src.vision": "Vision",
    "copilot.disclaimer": "AI output is for learning only—validate with statistics and biology.",
    "copilot.actions.hint": "Actionable suggestions (one-click to Code Lab):",
    "copilot.checklist.summary": "Publication visual checklist",
    "copilot.toast.applied": "Instruction sent to Code Lab",
    "copilot.error": "AI interpret failed: ",
    "copilot.action.default": "Apply",
    "copilot.card.interpretation": "Result interpretation",
    "copilot.card.limitations": "Statistical & visual limits",
    "copilot.card.figure": "Figure optimization",
    "copilot.card.downstream": "Downstream & validation",
    "copilot.card.manuscript": "Manuscript panel plan",
    "copilot.prompt.hint": "One-click Code Lab prompts:",
    "guide.copy": "Copy command",
    "guide.copied": "Copied ✓",
  },
};

const I18N = {
  zh: { ...I18N_CORE.zh, ...I18N_CATALOG.zh },
  en: { ...I18N_CORE.en, ...I18N_CATALOG.en },
};

let _resolved = "zh";
let _mode = "auto";
let _autoMeta = { country: "", source: "browser" };

export function getLocale() {
  return _resolved === "en" ? "en" : "zh";
}

export function getLocaleMode() {
  return _mode;
}

/** Translate key; supports {name} style placeholders in values. */
export function t(key, locale = null, vars = null) {
  const loc = locale || getLocale();
  let s = I18N[loc]?.[key] ?? I18N.zh[key] ?? key;
  if (vars && typeof vars === "object") {
    Object.entries(vars).forEach(([k, v]) => {
      s = s.replaceAll(`{${k}}`, String(v ?? ""));
    });
  }
  return s;
}

export function pageTitleKey(page) {
  return `page.${page}`;
}

async function fetchIpCountry() {
  try {
    const ctl = new AbortController();
    const tm = setTimeout(() => ctl.abort(), 1500);
    const r = await fetch("https://ipapi.co/json/", { signal: ctl.signal });
    clearTimeout(tm);
    if (r.ok) {
      const j = await r.json();
      const c = String(j?.country_code || "").toUpperCase();
      if (c) return { country: c, source: "ip" };
    }
  } catch { /* fallback */ }
  try {
    const ctl = new AbortController();
    const tm = setTimeout(() => ctl.abort(), 1500);
    const r = await fetch("http://ip-api.com/json/?fields=countryCode", { signal: ctl.signal });
    clearTimeout(tm);
    if (r.ok) {
      const j = await r.json();
      const c = String(j?.countryCode || "").toUpperCase();
      if (c) return { country: c, source: "ip" };
    }
  } catch { /* ignore */ }
  return { country: "", source: "browser" };
}

async function detectLocaleAuto() {
  const navLang = (navigator.language || "").toLowerCase();
  let locale = navLang.startsWith("zh") ? "zh" : "en";
  _autoMeta = { country: "", source: "browser" };
  const ip = await fetchIpCountry();
  _autoMeta = ip;
  if (ip.country) {
    locale = ["CN", "HK", "MO", "TW"].includes(ip.country) ? "zh" : "en";
  }
  return locale;
}

function applyDataI18nAttributes() {
  document.querySelectorAll("[data-i18n]").forEach((el) => {
    const key = el.getAttribute("data-i18n");
    if (key) el.textContent = t(key);
  });

  document.querySelectorAll("[data-i18n-html]").forEach((el) => {
    const key = el.getAttribute("data-i18n-html");
    if (key) el.innerHTML = t(key);
  });

  document.querySelectorAll("[data-i18n-title]").forEach((el) => {
    const key = el.getAttribute("data-i18n-title");
    if (key) el.title = t(key);
  });

  document.querySelectorAll("[data-i18n-placeholder]").forEach((el) => {
    const key = el.getAttribute("data-i18n-placeholder");
    if (key) el.placeholder = t(key);
  });

  document.querySelectorAll("[data-i18n-aria]").forEach((el) => {
    const key = el.getAttribute("data-i18n-aria");
    if (key) el.setAttribute("aria-label", t(key));
  });
}

function applyCourseBanner() {
  const root = document.querySelector(".guide-course-banner .hint");
  if (!root) return;
  const loc = getLocale();
  if (loc === "en") {
    root.innerHTML = `<strong>v9.0</strong> · New users: see <button type="button" class="btn-link" id="btn-course-to-guide">Guide</button> in the sidebar (Mac vs Windows differ) · One-click demo + recommended defaults per lesson`;
  } else {
    root.innerHTML = `<strong>v9.0</strong> · 零基础请先看左侧 <button type="button" class="btn-link" id="btn-course-to-guide">Guide 安装指南</button>（Mac 与 Windows 安装方式不同）· 每课可「一键加载示例数据」+「套用推荐参数」`;
  }
  document.getElementById("btn-course-to-guide")?.addEventListener("click", () => {
    window.dispatchEvent(new CustomEvent("emp:navigate", { detail: { page: "guide" } }));
  });
}

function applyDocumentLocale() {
  const loc = getLocale();
  document.documentElement.lang = loc === "en" ? "en" : "zh-CN";
  document.documentElement.dataset.empLocale = loc;

  applyDataI18nAttributes();
  applyDomI18n();
  applyCourseBanner();

  document.querySelectorAll(".locale-btn").forEach((btn) => {
    const m = btn.dataset.localeMode;
    btn.classList.toggle("active", m === _mode);
  });

  const hint = document.getElementById("locale-mode-hint");
  if (hint) {
    if (_mode === "auto") {
      const locLabel = loc === "en" ? "English" : "中文";
      const via = _autoMeta.source === "ip" && _autoMeta.country
        ? `IP ${_autoMeta.country}`
        : t("locale.hint.browser");
      hint.textContent = `${t("locale.hint.auto")} (${via}) → ${locLabel}`;
    } else {
      hint.textContent = t("locale.hint.manual");
    }
  }

  const activePage = document.querySelector(".nav-item.active")?.dataset.page;
  if (activePage) {
    const titleEl = document.getElementById("page-title");
    if (titleEl) titleEl.textContent = t(pageTitleKey(activePage));
  }

  window.dispatchEvent(new CustomEvent("emp:locale-change", { detail: { locale: loc, mode: _mode } }));
}

export async function setLocaleMode(mode) {
  _mode = mode === "zh" || mode === "en" ? mode : "auto";
  try { localStorage.setItem(LS_MODE, _mode); } catch { /* quota */ }

  if (_mode === "auto") {
    _resolved = await detectLocaleAuto();
  } else {
    _resolved = _mode;
  }
  try { localStorage.setItem(LS_RESOLVED, _resolved); } catch { /* quota */ }
  applyDocumentLocale();
}

export async function initLocale() {
  try {
    _mode = localStorage.getItem(LS_MODE) || "auto";
    if (_mode !== "zh" && _mode !== "en") _mode = "auto";
  } catch {
    _mode = "auto";
  }

  if (_mode === "auto") {
    _resolved = await detectLocaleAuto();
  } else {
    _resolved = _mode;
  }
  try { localStorage.setItem(LS_RESOLVED, _resolved); } catch { /* quota */ }

  const root = document.getElementById("locale-switch");
  if (root && root.dataset.bound !== "1") {
    root.dataset.bound = "1";
    root.querySelectorAll(".locale-btn").forEach((btn) => {
      btn.addEventListener("click", () => setLocaleMode(btn.dataset.localeMode));
    });
  }
  applyDocumentLocale();
}

window._empLocale = { getLocale, t, setLocaleMode };
