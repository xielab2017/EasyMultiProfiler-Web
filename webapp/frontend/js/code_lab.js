/**
 * Code lab: reference snippets + optional **real** R execution via POST /api/user_r/run.
 * Drafts + edit history remain in localStorage.
 */
import { CODE_LAB_TEMPLATES } from "./code_lab_templates.js?v=2026-06-20-v5.0.0";
import { codeLabArtifactURL, execUserR, optimizeRCode } from "./api.js?v=2026-06-20-v5.0.0";
import { t } from "./locale.js?v=2026-06-20-v5.0.0";

const LS_KEY = "emp_code_lab_store_v1";
const LLM_CFG_KEY = "emp_code_lab_llm_config_v1";
const CAMPUS_LLM_PRESET = {
  provider: "campus",
  base_url: "http://10.22.18.12:9901/v1",
  // Key intentionally blank: the backend supplies the campus default key for
  // provider "campus", so it never needs to ship in client-side source.
  api_key: "",
  model: "mixed",
  task_type: "code_optimize",
  campus_models: {
    fast: "deepseek-v4-flash",
    accurate: "Qwen3.6-35B-A3B",
    vision: "Qwen3-VL-8B-Instruct",
    embedding: "Qwen-embedding",
  },
};
const PAGES = new Set(["preparation", "analysis", "clinical", "runall", "visualization"]);

const DEFAULT_TAB = {
  preparation: "prep-filter",
  analysis: "ana-alpha",
  clinical: "overview",
  runall: "runall-rnaseq",
  visualization: "viz-barplot",
};

const CLINICAL_SNIPPET_LABELS = {
  overview: "Overview / vars / reorient",
  cor: "Feature × trait correlation",
  fitline: "Scatter + fit line",
  wgcna: "WGCNA (async)",
  three_line: "三线表",
  systematic: "系统临床统计",
  joint: "Multi-omics joint",
  marker_model: "Multi-omics marker model",
  reorient: "行列转换",
};

const CLINICAL_NO_EXPERIMENT_TABS = new Set(["overview", "three_line", "systematic", "reorient", "marker_model"]);

/** Prefetched *.r.txt (run webapp/scripts/build_code_snippets.py after plumber/viz edits). */
const SNIPPET_URLS = (() => {
  const m = {};
  for (const [workflow, tabs] of Object.entries(CODE_LAB_TEMPLATES)) {
    for (const tab of Object.keys(tabs)) {
      m[`${workflow}::${tab}`] = `snippets/${workflow}__${tab}.r.txt`;
    }
  }
  return m;
})();

/** After full viz.R function bodies, optional one-liner to materialize a plot (last expr). */
const EXEC_ONE_LINER = {
  "visualization::viz-barplot": '\n\nmake_barplot(session_id, experiment, NULL, NULL, "top20", 20L)\n',
  "visualization::viz-boxplot": "\n\nmake_boxplot(session_id, experiment, NULL, NULL, 9, 6, NULL, NULL)\n",
  "visualization::viz-heatmap":
    "\n\nmake_heatmap(session_id, experiment, NULL, 50L, 11, 8, NULL, TRUE, TRUE, NULL, 11, NULL, NULL)\n",
  "visualization::viz-volcano": "\n\nmake_volcano(session_id, experiment)\n",
  "visualization::viz-scatter":
    "\n\nmake_scatter(session_id, experiment, NULL, 1L, 2L, 8, 6, NULL, \"auto\", NULL)\n",
  "visualization::viz-structure": "\n\nmake_structure(session_id, experiment, NULL, 10L, 11, 6, NULL, NULL)\n",
  "visualization::viz-alpha":
    "\n\nmake_alpha_plot(session_id, experiment, NULL, \"shannon\", \"current\", 8, 6, NULL, NULL)\n",
};

async function prefetchSnippets() {
  const out = {};
  for (const [key, rel] of Object.entries(SNIPPET_URLS)) {
    try {
      const r = await fetch(new URL(rel, import.meta.url), { cache: "no-cache" });
      if (r.ok) out[key] = await r.text();
    } catch {
      /* offline */
    }
  }
  globalThis.__empPrefetchedSnippets = out;
}

function buildFreshTemplate(workflow, tab) {
  const k = draftKey(workflow, tab);
  const full = globalThis.__empPrefetchedSnippets?.[k];
  const base = templateFor(workflow, tab);
  if (!full) return workflow === "clinical" ? injectClinicalUiDefaults(base, tab) : base;
  const tail = EXEC_ONE_LINER[k] || "";
  const body = workflow === "clinical" ? injectClinicalUiDefaults(full, tab) : full;
  return `# --- 服务器全文 / 同源片段（可改后「在 R 中执行」）---\n${body}${tail}\n\n# --- 路由说明 ---\n${base}`;
}

function rString(v) {
  if (v === null || v === undefined || v === "") return "NULL";
  return JSON.stringify(String(v));
}

function rBool(v) {
  return v ? "TRUE" : "FALSE";
}

function rVector(vals, fallback = "character()") {
  const xs = (vals || []).filter((v) => v !== null && v !== undefined && String(v).trim() !== "");
  if (!xs.length) return fallback;
  return `c(${xs.map((v) => rString(v)).join(", ")})`;
}

function selectedValues(id) {
  const el = document.getElementById(id);
  return Array.from(el?.selectedOptions || []).map((o) => o.value);
}

function clinicalSourceValue() {
  const v = document.getElementById("clin-data-source")?.value || "auto";
  return v === "auto" ? (window._emp?.clinicalResolvedSource || "standalone") : v;
}

function injectClinicalUiDefaults(code, tab) {
  const source = clinicalSourceValue();
  const group = document.getElementById("clin-three-group")?.value || null;
  const maxLevels = Number(document.getElementById("clin-three-max-levels")?.value || 20);
  const engine = document.getElementById("clin-three-engine")?.value || "gtsummary";
  const skipHigh = document.getElementById("clin-three-skip-high-card")?.checked !== false;
  let replacement = null;

  if (tab === "three_line" || tab === "systematic") {
    const cohortFilter = tab === "systematic"
      ? (document.getElementById("clin-systematic-cohort")?.value || null)
      : null;
    const cohortLine = tab === "systematic"
      ? `, cohort_filter = ${rString(cohortFilter)}`
      : "";
    replacement = `b <- list(
  session_id = session_id,
  experiment = if (exists("experiment", inherits = FALSE) && !is.null(experiment)) as.character(experiment)[1] else NULL,
  source = ${rString(source)}, group_var = ${rString(group)}, skip_high_cardinality = ${rBool(skipHigh)},
  max_levels = ${Number.isFinite(maxLevels) ? Math.trunc(maxLevels) : 20}L, table_engine = ${rString(engine)}${cohortLine}
)`;
  } else if (tab === "cor") {
    replacement = `b <- list(
  session_id = session_id, experiment = as.character(experiment)[1],
  traits = ${rVector(selectedValues("clin-cor-traits"), 'c("REPLACE_WITH_NUMERIC_CLINICAL_COL")')},
  method = ${rString(document.getElementById("clin-cor-method")?.value || "spearman")},
  top_n_features = ${Math.trunc(Number(document.getElementById("clin-cor-topn")?.value || 30))}L,
  p_adjust = ${rString(document.getElementById("clin-cor-padj")?.value || "BH")},
  clinical_source = ${rString(source)}
)`;
  } else if (tab === "fitline") {
    replacement = `b <- list(
  session_id = session_id, experiment = as.character(experiment)[1],
  feature = ${rString(document.getElementById("clin-fit-feature")?.value || "REPLACE_FEATURE")},
  trait = ${rString(document.getElementById("clin-fit-trait")?.value || "REPLACE_TRAIT")},
  group = ${rString(document.getElementById("clin-fit-group")?.value || null)},
  method = ${rString(document.getElementById("clin-fit-method")?.value || "lm")},
  log_y = ${rBool(document.getElementById("clin-fit-logy")?.value === "true")},
  clinical_source = ${rString(source)}
)`;
  } else if (tab === "wgcna") {
    replacement = `b <- list(
  session_id = session_id, experiment = as.character(experiment)[1],
  traits = ${rVector(selectedValues("clin-wgcna-traits"), "character()")},
  min_module_size = ${Math.trunc(Number(document.getElementById("clin-wgcna-minmod")?.value || 30))}L,
  clinical_source = ${rString(source)}
)`;
  } else if (tab === "marker_model") {
    replacement = `b <- list(
  session_id = session_id,
  experiments = ${rVector(selectedValues("clin-marker-experiments"), 'c("REPLACE_EXPERIMENT")')},
  outcome_var = ${rString(document.getElementById("clin-marker-outcome")?.value || "REPLACE_BINARY_OUTCOME")},
  positive_class = ${rString(document.getElementById("clin-marker-positive")?.value || null)},
  methods = ${rVector(selectedValues("clin-marker-methods"), 'c("randomForest", "lasso", "xgboost")')},
  clinical_source = ${rString(source)},
  include_clinical_numeric = ${rBool(document.getElementById("clin-marker-include-clinical")?.checked !== false)},
  max_features_per_omics = ${Math.trunc(Number(document.getElementById("clin-marker-max-features")?.value || 200))}L,
  validation_fraction = ${Number(document.getElementById("clin-marker-validation")?.value || 0.3)},
  top_n = 30L, seed = 123L
)`;
  }
  if (!replacement) return code;
  return code.replace(/b <- list\([\s\S]*?\n\)/, replacement);
}

let rootEl;
let consoleEl;
let execOut;
let originalEl;
let taEl;
let clinicalRow;
let clinicalSel;
let histEl;
let llmStatusEl;
let llmConfigEls = {};
let state = {
  workflow: null,
  tab: null,
  debounce: null,
  lastRecorded: "",
};

function loadStore() {
  try {
    const raw = localStorage.getItem(LS_KEY);
    if (!raw) return { drafts: {}, optimized: {}, history: [] };
    const j = JSON.parse(raw);
    if (!j || typeof j !== "object") return { drafts: {}, history: [] };
    if (!j.drafts || typeof j.drafts !== "object") j.drafts = {};
    if (!j.optimized || typeof j.optimized !== "object") j.optimized = {};
    if (!Array.isArray(j.history)) j.history = [];
    return j;
  } catch {
    return { drafts: {}, optimized: {}, history: [] };
  }
}

function saveStore(store) {
  try {
    localStorage.setItem(LS_KEY, JSON.stringify(store));
  } catch {
    /* quota */
  }
}

function draftKey(workflow, tab) {
  return `${workflow}::${tab}`;
}

function loadLlmConfig() {
  try {
    const raw = localStorage.getItem(LLM_CFG_KEY);
    if (!raw) return {};
    const cfg = JSON.parse(raw);
    return cfg && typeof cfg === "object" ? cfg : {};
  } catch {
    return {};
  }
}

function saveLlmConfig(cfg) {
  try {
    localStorage.setItem(LLM_CFG_KEY, JSON.stringify(cfg || {}));
  } catch {
    /* quota */
  }
}

function templateFor(workflow, tab) {
  const w = CODE_LAB_TEMPLATES[workflow];
  if (!w) return `# (no template for workflow "${workflow}")\n`;
  const t = w[tab];
  if (typeof t === "string" && t.trim()) return t;
  return `# Template not defined for ${workflow} / ${tab}\n# See webapp/backend/plumber.R\n`;
}

function detectActiveTabInPage(page) {
  const sec = document.getElementById(`page-${page}`);
  if (!sec) return null;
  const bar = sec.querySelector(".tab-bar");
  const activeBtn = bar?.querySelector(".tab.active");
  if (activeBtn?.dataset?.tab) return activeBtn.dataset.tab;
  const activePanel = sec.querySelector(".tab-panel.active");
  return activePanel?.id || null;
}

function syncDockLayout() {
  if (!rootEl) return;
  const open = rootEl.classList.contains("code-lab--open");
  const visible = !rootEl.classList.contains("code-lab--hidden");
  const docked = visible && open;
  document.body.classList.toggle("code-lab-docked", docked);
  consoleEl?.classList.toggle("hidden", !docked);
  if (docked) repositionConsolePanel();
}

function repositionConsolePanel() {
  if (!consoleEl) return;
  const activePage = document.querySelector("#main > .page.active");
  if (activePage) {
    activePage.insertAdjacentElement("afterend", consoleEl);
  }
}

function ensureConsolePanel() {
  consoleEl = document.getElementById("code-lab-console");
  execOut = document.getElementById("code-lab-exec-out");
  if (!consoleEl || !execOut) return;
  if (consoleEl.dataset.bound) return;
  consoleEl.dataset.bound = "1";
  document.getElementById("code-lab-console-clear")?.addEventListener("click", () => {
    execOut.innerHTML = `<p class="code-lab-exec-placeholder">${t("codelab.placeholder")}</p>`;
  });
}

function hideDock() {
  state.workflow = null;
  state.tab = null;
  rootEl?.classList.add("code-lab--hidden");
  syncDockLayout();
}

function showDock() {
  rootEl?.classList.remove("code-lab--hidden");
  syncDockLayout();
}

function saveCurrentDraft() {
  if (!state.workflow || !state.tab || !taEl) return;
  const s = loadStore();
  if (!s.optimized) s.optimized = {};
  s.optimized[draftKey(state.workflow, state.tab)] = taEl.value;
  // Backward compatibility with older localStorage shape.
  s.drafts[draftKey(state.workflow, state.tab)] = taEl.value;
  saveStore(s);
}

function sourceCodeForCurrent() {
  if (!state.workflow || !state.tab) return "";
  return originalEl?.value || buildFreshTemplate(state.workflow, state.tab);
}

function setOptimizedCode(code, kind = "llm") {
  if (!taEl || !state.workflow || !state.tab) return;
  taEl.value = code;
  saveCurrentDraft();
  const s = loadStore();
  s.history.push({
    t: Date.now(),
    workflow: state.workflow,
    tab: state.tab,
    code,
    kind,
  });
  while (s.history.length > 500) s.history.shift();
  saveStore(s);
  state.lastRecorded = code;
  renderHistory();
}

function setLlmStatus(message, kind = "muted") {
  if (!llmStatusEl) return;
  llmStatusEl.textContent = message || "";
  llmStatusEl.dataset.kind = kind;
}

function applyLlmConfigToForm() {
  const cfg = loadLlmConfig();
  const entries = {
    provider: cfg.provider || "chatgpt",
    mode: cfg.mode || "api",
    api_key: cfg.api_key || "",
    base_url: cfg.base_url || "",
    model: cfg.model || "",
    task_type: cfg.task_type || "code_optimize",
    remote_host: cfg.remote_host || "",
    remote_port: cfg.remote_port || "",
    remote_path: cfg.remote_path || "/api/llm/optimize_r",
    providers: Array.isArray(cfg.providers) ? cfg.providers.join(",") : (cfg.providers || ""),
  };
  for (const [key, val] of Object.entries(entries)) {
    if (llmConfigEls[key]) llmConfigEls[key].value = val;
  }
  updateLlmFormHints(entries.provider);
}

function applyCampusLlmPreset() {
  const cfg = { ...loadLlmConfig(), ...CAMPUS_LLM_PRESET };
  saveLlmConfig(cfg);
  applyLlmConfigToForm();
}

function updateLlmFormHints(provider) {
  const modelEl = llmConfigEls.model;
  const keyEl = llmConfigEls.api_key;
  const baseEl = llmConfigEls.base_url;
  const taskEl = llmConfigEls.task_type;
  if (taskEl) {
    const wrap = taskEl.closest("label");
    if (wrap) wrap.classList.toggle("hidden", provider !== "campus");
  }
  if (!modelEl) return;
  if (provider === "campus") {
    modelEl.placeholder = "mixed = DeepSeek-v4-flash → Qwen3.6-35B-A3B";
    if (keyEl) keyEl.placeholder = "校园内网 API Key（已预填，可改）";
    if (baseEl) baseEl.placeholder = "http://10.22.18.12:9901/v1";
  } else {
    modelEl.placeholder = "DeepSeek 推荐 deepseek-chat；可填 deepseek-v4-flash";
    if (keyEl) keyEl.placeholder = "仅保存在本机浏览器";
    if (baseEl) baseEl.placeholder = "留空使用对应 Provider 默认地址";
  }
}

function collectLlmConfig() {
  const mode = llmConfigEls.mode?.value || "api";
  const provider = llmConfigEls.provider?.value || "chatgpt";
  const cfg = {
    mode,
    provider,
    api_key: llmConfigEls.api_key?.value || "",
    base_url: llmConfigEls.base_url?.value || "",
    model: llmConfigEls.model?.value || "",
    task_type: llmConfigEls.task_type?.value || "code_optimize",
    remote_host: llmConfigEls.remote_host?.value || "",
    remote_port: llmConfigEls.remote_port?.value || "",
    remote_path: llmConfigEls.remote_path?.value || "/api/llm/optimize_r",
    providers: (llmConfigEls.providers?.value || "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean),
  };
  if (provider === "campus") {
    cfg.campus_models = { ...CAMPUS_LLM_PRESET.campus_models };
  }
  saveLlmConfig(cfg);
  return {
    provider: mode === "remote" || provider === "remote" ? "remote" : provider,
    config: cfg,
  };
}

async function runCodeInR(code, label = "优化脚本", sourceCode = null) {
  if (!execOut) ensureConsolePanel();
  const exp = window._emp?.currentExp;
  if (!execOut) return;
  const canRunWithoutExperiment = state.workflow === "clinical" && CLINICAL_NO_EXPERIMENT_TABS.has(state.tab);
  if (!exp && !canRunWithoutExperiment) {
    execOut.innerHTML = `<p class="code-lab-exec-err">${t("codelab.noExperiment")}</p>`;
    consoleEl?.scrollIntoView({ behavior: "smooth", block: "nearest" });
    return { ok: false, error: "no experiment selected" };
  }
  execOut.innerHTML = `<p class="code-lab-exec-wait">${t("codelab.running", null, { label })}</p>`;
  consoleEl?.scrollIntoView({ behavior: "smooth", block: "nearest" });
  try {
    const res = await execUserR({
      experiment: exp || null,
      code,
      width: 9,
      height: 6,
      workflow: state.workflow,
      tab: state.tab,
      label,
      source_code: sourceCode ?? sourceCodeForCurrent(),
    });
    if (!res.success) {
      execOut.innerHTML = `<p class="code-lab-exec-err">${escapeHtml(res.error || "failed")}</p>`;
      return { ok: false, error: res.error || "failed" };
    }
    const bits = [];
    const plotSrc = execPlotImageSrc(res.plot) ?? execPlotImageSrc(res.png);
    if (plotSrc) {
      bits.push(`<h5>${escapeHtml(label)} · ${escapeHtml(t("codelab.plotOut"))}</h5><img class="code-lab-exec-img" alt="plot" src="${plotSrc.replace(/"/g, "&quot;")}" />`);
    }
    if (res.stdout && res.stdout.trim()) {
      bits.push(`<h5>${escapeHtml(t("codelab.stdout"))}</h5><pre class="code-lab-exec-pre">${escapeHtml(res.stdout)}</pre>`);
    }
    if (res.value_text && String(res.value_text).trim()) {
      bits.push(`<h5>${escapeHtml(t("codelab.returnVal"))}</h5><pre class="code-lab-exec-pre">${escapeHtml(res.value_text)}</pre>`);
    }
    const tableBits = renderExecTables(res.tables);
    if (tableBits) bits.push(tableBits);
    if (res.artifact_name) {
      bits.push(`<h5>${escapeHtml(t("codelab.downloadBundle"))}</h5>
        <p><a class="btn btn-outline code-lab-download" href="${escapeAttr(codeLabArtifactURL(res.artifact_name))}" download>
          ${escapeHtml(t("codelab.downloadBundleBtn"))}
        </a></p>`);
    }
    if (!bits.length) bits.push(`<p>${escapeHtml(t("codelab.doneNoOutput", null, { label }))}</p>`);
    bits.push(`<p class="code-lab-exec-meta">${escapeHtml(`${label}; backend_ms=${res.backend_ms ?? "?"}`)}</p>`);
    execOut.innerHTML = bits.join("");
    consoleEl?.scrollIntoView({ behavior: "smooth", block: "nearest" });
    return { ok: true };
  } catch (err) {
    const msg = err.message || String(err);
    execOut.innerHTML = `<p class="code-lab-exec-err">${escapeHtml(msg)}</p>`;
    consoleEl?.scrollIntoView({ behavior: "smooth", block: "nearest" });
    return { ok: false, error: msg };
  }
}

function normalizeExecTableRows(tab) {
  if (!tab) return [];
  if (Array.isArray(tab)) return tab;
  if (typeof tab === "string") {
    try {
      const parsed = JSON.parse(tab);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }
  if (tab.json) {
    try {
      const parsed = JSON.parse(tab.json);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }
  return [];
}

function renderExecTables(tables) {
  if (!Array.isArray(tables) || !tables.length) return "";
  const parts = [];
  for (const tab of tables) {
    const rows = normalizeExecTableRows(tab);
    if (!rows.length) continue;
    const cols = Object.keys(rows[0] || {});
    if (!cols.length) continue;
    const body = rows.slice(0, 200).map((row) =>
      `<tr>${cols.map((c) => `<td>${escapeHtml(row[c] ?? "")}</td>`).join("")}</tr>`
    ).join("");
    parts.push(`<h5>${escapeHtml(tab.name || "表格输出")} (${escapeHtml(`${tab.n_rows ?? rows.length} rows`)})</h5>
      <div class="code-lab-table-wrap"><table class="code-lab-result-table">
        <thead><tr>${cols.map((c) => `<th>${escapeHtml(c)}</th>`).join("")}</tr></thead>
        <tbody>${body}</tbody>
      </table></div>`);
  }
  return parts.join("");
}

function pushHistoryEntry() {
  if (!state.workflow || !state.tab || !taEl) return;
  const code = taEl.value;
  if (code === state.lastRecorded) return;
  state.lastRecorded = code;
  const s = loadStore();
  s.history.push({
    t: Date.now(),
    workflow: state.workflow,
    tab: state.tab,
    code,
    kind: "edit",
  });
  while (s.history.length > 500) s.history.shift();
  saveStore(s);
  renderHistory();
}

function renderHistory() {
  if (!histEl) return;
  const s = loadStore();
  const wf = state.workflow;
  const tab = state.tab;
  const matches = s.history.filter((h) => h.workflow === wf && h.tab === tab);
  const rows = matches.slice(-40).reverse();
  if (!rows.length) {
    histEl.innerHTML =
      '<div class="code-lab-history-item"><span class="code-lab-history-preview">No edits recorded yet for this step.</span></div>';
    return;
  }
  histEl.innerHTML = rows
    .map((h) => {
      const when = new Date(h.t).toLocaleString();
      const preview = (h.code || "").replace(/\s+/g, " ").trim().slice(0, 120);
      return `<div class="code-lab-history-item">
        <span class="code-lab-history-meta">${escapeHtml(when)}</span>
        <span class="code-lab-history-preview" title="${escapeAttr(h.code)}">${escapeHtml(preview)}</span>
        <span class="code-lab-history-actions"><button type="button" class="btn btn-outline code-lab-restore" data-ts="${h.t}">Restore</button></span>
      </div>`;
    })
    .join("");
  histEl.querySelectorAll(".code-lab-restore").forEach((btn) => {
    btn.addEventListener("click", () => {
      const ts = +btn.getAttribute("data-ts");
      const hit = loadStore().history.find((x) => x.t === ts);
      if (hit && taEl) {
        taEl.value = hit.code;
        saveCurrentDraft();
        pushHistoryEntry();
      }
    });
  });
}

function escapeHtml(s) {
  return String(s || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** Normalize user_r/run plot payload → img src, or null when not a renderable PNG. */
function execPlotImageSrc(raw) {
  const toSrc = (s) => (s.startsWith("data:") ? s : `data:image/png;base64,${s}`);
  if (typeof raw === "string" && raw.length > 0) return toSrc(raw);
  if (Array.isArray(raw)) {
    const s = raw.find((v) => typeof v === "string" && v.length > 0);
    return s ? toSrc(s) : null;
  }
  if (raw && typeof raw === "object") {
    for (const v of Object.values(raw)) {
      if (typeof v === "string" && v.length > 0) return toSrc(v);
    }
  }
  return null;
}

function escapeAttr(s) {
  return escapeHtml(s).replace(/\n/g, "&#10;");
}

function clinicalSnippetLabel(key) {
  const i18n = {
    three_line: "clinical.threeLine",
    systematic: "clinical.systematic",
    reorient: "clinical.reorient",
    overview: "clinical.overview",
  };
  return i18n[key] ? t(i18n[key]) : (CLINICAL_SNIPPET_LABELS[key] || key);
}

function setHeadTitle() {
  const h = rootEl?.querySelector(".code-lab-head h4");
  if (!h) return;
  if (!state.workflow) {
    h.textContent = t("codelab.headTitle");
    return;
  }
  const tabLabel =
    state.workflow === "clinical"
      ? clinicalSnippetLabel(state.tab) || state.tab
      : state.tab;
  h.textContent = `${t("codelab.workflowCode")} · ${state.workflow} · ${tabLabel}`;
}

export function applyCodeLabI18n() {
  if (!rootEl) return;
  const q = (sel) => rootEl.querySelector(sel);
  const setText = (sel, key) => { const el = q(sel); if (el) el.textContent = t(key); };
  setText(".code-lab-head h4", "codelab.headTitle");
  const badge = q(".code-lab-badge");
  if (badge) badge.textContent = t("codelab.badge");
  const hint = q(".code-lab-hint");
  if (hint) hint.innerHTML = t("codelab.intro");
  setText("#code-lab-clinical-row label", "codelab.clinicalStep");
  const srcTitle = q(".code-lab-code-block:first-of-type .code-lab-code-title span");
  if (srcTitle) srcTitle.textContent = t("codelab.sourceLabel");
  setText("#code-lab-use-source", "codelab.copyToOpt");
  const optTitle = q(".code-lab-code-block:nth-of-type(2) .code-lab-code-title span");
  if (optTitle) optTitle.textContent = t("codelab.optLabel");
  setText("#code-lab-run-source", "codelab.runSource");
  const llmSum = q("#code-lab-llm-wrap > summary");
  if (llmSum) llmSum.textContent = t("codelab.llmConfig");
  setText("#code-lab-exec", "codelab.runOptShort");
  setText("#code-lab-llm-optimize", "codelab.optimize");
  const hist = q(".code-lab-history summary");
  if (hist) hist.textContent = t("codelab.history");
  const instLab = q(".code-lab-llm-instruction");
  if (instLab) {
    for (const n of instLab.childNodes) {
      if (n.nodeType === Node.TEXT_NODE && n.textContent.trim()) {
        n.textContent = t("codelab.instruction");
        break;
      }
    }
  }
  if (clinicalSel) {
    const cur = clinicalSel.value;
    [...clinicalSel.options].forEach((o) => {
      o.textContent = clinicalSnippetLabel(o.value);
    });
    clinicalSel.value = cur;
  }
  setHeadTitle();
}

function applyContext(workflow, tab) {
  if (!PAGES.has(workflow)) {
    hideDock();
    return;
  }
  saveCurrentDraft();
  state.workflow = workflow;
  state.tab = tab;
  if (workflow === "clinical") {
    clinicalRow?.classList.remove("hidden");
    if (clinicalSel && clinicalSel.value !== tab) clinicalSel.value = tab;
  } else {
    clinicalRow?.classList.add("hidden");
  }
  const s = loadStore();
  const key = draftKey(workflow, tab);
  const source = buildFreshTemplate(workflow, tab);
  const draft = s.optimized?.[key] ?? s.drafts?.[key];
  if (originalEl) originalEl.value = source;
  taEl.value = typeof draft === "string" ? draft : source;
  state.lastRecorded = taEl.value;
  setHeadTitle();
  showDock();
  renderHistory();
}

function runallTabId() {
  const sel = document.getElementById("ra-pipeline");
  const v = sel?.value === "m16s" ? "m16s" : "rnaseq";
  return `runall-${v}`;
}

export function applyCopilotAction({ page, tab, instruction, autoOptimize = false } = {}) {
  if (!rootEl) return;
  const wf = page || state.workflow || "analysis";
  if (PAGES.has(wf)) {
    applyContext(wf, tab || detectActiveTabInPage(wf) || DEFAULT_TAB[wf]);
    showDock();
    rootEl.classList.add("code-lab--open");
    syncDockLayout();
  }
  const inst = document.getElementById("code-lab-llm-instruction");
  if (inst && instruction) inst.value = instruction;
  if (autoOptimize && instruction) {
    rootEl.querySelector("#code-lab-llm-optimize")?.click();
  }
  rootEl.scrollIntoView({ behavior: "smooth", block: "nearest" });
}

export function openCodeLabPanel(page) {
  if (!rootEl || !PAGES.has(page)) return;
  notifyCodeLabNavigate(page);
  showDock();
  rootEl.classList.add("code-lab--open");
  syncDockLayout();
  rootEl.scrollIntoView({ behavior: "smooth", block: "nearest" });
}

export function notifyCodeLabNavigate(page) {
  if (!rootEl) return;
  if (!PAGES.has(page)) {
    saveCurrentDraft();
    hideDock();
    return;
  }
  if (page === "clinical") {
    const t = document.getElementById("clin-analysis-strategy")?.value || clinicalSel?.value || DEFAULT_TAB.clinical;
    applyContext("clinical", t);
    return;
  }
  if (page === "runall") {
    applyContext("runall", runallTabId());
    return;
  }
  const tab = detectActiveTabInPage(page) || DEFAULT_TAB[page];
  applyContext(page, tab);
  repositionConsolePanel();
}

export function notifyCodeLabTab(page, tabId) {
  if (!rootEl || !PAGES.has(page) || page === "clinical" || page === "runall") return;
  applyContext(page, tabId);
}

export function notifyCodeLabClinicalStep(tabId) {
  if (!rootEl || !CLINICAL_SNIPPET_LABELS[tabId]) return;
  applyContext("clinical", tabId);
  repositionConsolePanel();
}

export function refreshCodeLabContext() {
  if (!rootEl || !state.workflow || !state.tab) return;
  applyContext(state.workflow, state.tab);
}

export async function initCodeLab() {
  await prefetchSnippets();
  ensureConsolePanel();

  document.getElementById("code-lab-root")?.remove();

  rootEl = document.createElement("div");
  rootEl.id = "code-lab-root";
  rootEl.dataset.empLayout = "v3";
  rootEl.className = "code-lab--hidden code-lab--open";
  rootEl.innerHTML = `
    <div class="code-lab-head" title="Click to expand / collapse">
      <h4>流程代码</h4>
      <span class="code-lab-badge">原始/优化 R · LLM</span>
    </div>
    <div class="code-lab-body">
      <div class="code-lab-pane-src code-lab-pane-src--full">
        <div class="code-lab-pane-src-head">System Source vs Optimized R</div>
        <p class="code-lab-hint">
          上方是系统生成的纯 R 原始脚本；下方是人工或 LLM 优化脚本。
          <strong>「运行优化脚本」</strong> → <code>POST /api/user_r/run</code>。切勿对公网暴露。
        </p>
        <div class="code-lab-clinical-row hidden" id="code-lab-clinical-row">
          <label for="code-lab-clinical-snippet">Clinical 子步骤</label>
          <select id="code-lab-clinical-snippet"></select>
        </div>
        <div class="code-lab-compare">
          <section class="code-lab-code-block">
            <div class="code-lab-code-title">
              <span>系统原始脚本（只读，可直接运行）</span>
              <button type="button" class="btn btn-outline" id="code-lab-use-source">复制到优化区</button>
            </div>
            <textarea class="code-lab-editor code-lab-editor--source" id="code-lab-original" spellcheck="false" autocomplete="off" readonly></textarea>
          </section>
          <section class="code-lab-code-block">
            <div class="code-lab-code-title">
              <span>优化脚本（LLM/人工修改后运行）</span>
              <button type="button" class="btn btn-outline" id="code-lab-run-source">运行原始脚本</button>
            </div>
            <textarea class="code-lab-editor" id="code-lab-editor" spellcheck="false" autocomplete="off"></textarea>
          </section>
        </div>
        <details class="code-lab-llm-wrap" id="code-lab-llm-wrap">
          <summary>LLM 代码优化配置（默认 API 直连）</summary>
          <div class="code-lab-llm-grid">
            <label>Provider
              <select id="code-lab-llm-provider">
                <option value="campus">校园内网模型（混合）</option>
                <option value="chatgpt">ChatGPT / OpenAI</option>
                <option value="deepseek">DeepSeek</option>
                <option value="qwen">Qwen</option>
                <option value="minimax">MiniMax</option>
                <option value="gemini">Gemini</option>
                <option value="claude">Claude</option>
                <option value="custom">Custom OpenAI-compatible</option>
                <option value="auto">Auto 多模型</option>
                <option value="remote">Remote 远程服务</option>
              </select>
            </label>
            <label>任务类型
              <select id="code-lab-llm-task-type">
                <option value="code_optimize">代码优化（快→准混合）</option>
                <option value="complex">复杂推理（准→快混合）</option>
                <option value="vision">视觉理解</option>
                <option value="embedding">向量嵌入</option>
              </select>
            </label>
            <label>Model
              <input type="text" id="code-lab-llm-model" placeholder="mixed = DeepSeek-v4-flash → Qwen3.6-35B-A3B">
            </label>
            <label>API Key
              <input type="password" id="code-lab-llm-key" placeholder="仅保存在本机浏览器">
            </label>
            <label>Base URL（可选）
              <input type="text" id="code-lab-llm-base-url" placeholder="留空使用对应 Provider 默认地址">
            </label>
          </div>
          <details class="code-lab-llm-advanced">
            <summary>高级设置：Auto 多模型 / Remote IP + 端口</summary>
            <div class="code-lab-llm-grid">
              <label>Auto Providers
                <input type="text" id="code-lab-llm-providers" placeholder="deepseek,qwen,chatgpt">
              </label>
              <label>远程 IP/Host
                <input type="text" id="code-lab-llm-remote-host" placeholder="192.168.1.10 或 http://host">
              </label>
              <label>远程端口
                <input type="text" id="code-lab-llm-remote-port" placeholder="8001">
              </label>
              <label>远程 API Path
                <input type="text" id="code-lab-llm-remote-path" placeholder="/api/llm/optimize_r">
              </label>
            </div>
          </details>
          <label class="code-lab-llm-instruction">优化要求
            <textarea id="code-lab-llm-instruction" placeholder="例如：保留纯 R 兼容，优化配色、图例、字体大小，并让最后一行返回 ggplot"></textarea>
          </label>
          <div class="code-lab-llm-actions">
            <button type="button" class="btn btn-primary" id="code-lab-llm-optimize">用 LLM 优化原始脚本</button>
            <span class="code-lab-llm-status" id="code-lab-llm-status"></span>
          </div>
        </details>
        <div class="code-lab-toolbar">
          <button type="button" class="btn btn-primary" id="code-lab-exec">运行优化脚本</button>
          <button type="button" class="btn btn-outline" id="code-lab-reset">优化区恢复原始</button>
          <button type="button" class="btn btn-outline" id="code-lab-copy">复制</button>
          <button type="button" class="btn btn-outline" id="code-lab-toggle-collapse">收起面板</button>
        </div>
        <details id="code-lab-history-wrap" class="code-lab-history-wrap">
          <summary>编辑历史（本机）</summary>
          <div class="code-lab-history" id="code-lab-history"></div>
        </details>
      </div>
    </div>
  `;
  document.body.appendChild(rootEl);

  taEl = rootEl.querySelector("#code-lab-editor");
  originalEl = rootEl.querySelector("#code-lab-original");
  histEl = rootEl.querySelector("#code-lab-history");
  llmStatusEl = rootEl.querySelector("#code-lab-llm-status");
  llmConfigEls = {
    mode: rootEl.querySelector("#code-lab-llm-mode"),
    provider: rootEl.querySelector("#code-lab-llm-provider"),
    task_type: rootEl.querySelector("#code-lab-llm-task-type"),
    model: rootEl.querySelector("#code-lab-llm-model"),
    api_key: rootEl.querySelector("#code-lab-llm-key"),
    base_url: rootEl.querySelector("#code-lab-llm-base-url"),
    providers: rootEl.querySelector("#code-lab-llm-providers"),
    remote_host: rootEl.querySelector("#code-lab-llm-remote-host"),
    remote_port: rootEl.querySelector("#code-lab-llm-remote-port"),
    remote_path: rootEl.querySelector("#code-lab-llm-remote-path"),
  };
  applyLlmConfigToForm();
  if (!loadLlmConfig().provider) applyCampusLlmPreset();
  llmConfigEls.provider?.addEventListener("change", () => {
    if (llmConfigEls.provider.value === "campus") applyCampusLlmPreset();
    else updateLlmFormHints(llmConfigEls.provider.value);
    collectLlmConfig();
  });
  Object.values(llmConfigEls).forEach((el) => {
    el?.addEventListener("change", () => collectLlmConfig());
    el?.addEventListener("blur", () => collectLlmConfig());
  });
  clinicalRow = rootEl.querySelector("#code-lab-clinical-row");
  clinicalSel = rootEl.querySelector("#code-lab-clinical-snippet");
  for (const [val, lab] of Object.entries(CLINICAL_SNIPPET_LABELS)) {
    const o = document.createElement("option");
    o.value = val;
    o.textContent = clinicalSnippetLabel(val);
    clinicalSel.appendChild(o);
  }
  clinicalSel.addEventListener("change", () => {
    applyContext("clinical", clinicalSel.value);
  });

  rootEl.querySelector(".code-lab-head").addEventListener("click", () => {
    rootEl.classList.toggle("code-lab--open");
    syncDockLayout();
  });

  rootEl.querySelector("#code-lab-toggle-collapse").addEventListener("click", (e) => {
    e.stopPropagation();
    rootEl.classList.remove("code-lab--open");
    syncDockLayout();
  });

  syncDockLayout();

  taEl.addEventListener("input", () => {
    saveCurrentDraft();
    clearTimeout(state.debounce);
    state.debounce = setTimeout(() => pushHistoryEntry(), 800);
  });

  taEl.addEventListener("blur", () => {
    saveCurrentDraft();
    pushHistoryEntry();
  });

  rootEl.querySelector("#code-lab-use-source").addEventListener("click", (e) => {
    e.stopPropagation();
    setOptimizedCode(sourceCodeForCurrent(), "source-copy");
  });

  rootEl.querySelector("#code-lab-run-source").addEventListener("click", async (e) => {
    e.stopPropagation();
    await runCodeInR(sourceCodeForCurrent(), "系统原始脚本", sourceCodeForCurrent());
  });

function collectUiContext() {
  const ctx = {};
  if (window._emp?.currentExp) ctx.experiment = window._emp.currentExp;
  const omics = document.getElementById("omics-pipeline")?.value;
  if (omics) ctx.omics = omics;
  for (const id of ["tx-group", "m16s-group", "mbx-group", "mgx-group"]) {
    const el = document.getElementById(id);
    if (el?.value) { ctx.group_var = el.value; break; }
  }
  for (const [id, key] of [
    ["tx-fc", "fc_cutoff"], ["tx-padj", "padj_cutoff"],
    ["diff-fc", "fc_cutoff"], ["diff-padj", "padj_cutoff"],
  ]) {
    const el = document.getElementById(id);
    if (el?.value) ctx[key] = el.value;
  }
  return Object.keys(ctx).length ? ctx : null;
}

  rootEl.querySelector("#code-lab-llm-optimize").addEventListener("click", async (e) => {
    e.stopPropagation();
    if (!state.workflow || !state.tab) return;
    const { provider, config } = collectLlmConfig();
    const instruction = rootEl.querySelector("#code-lab-llm-instruction")?.value || "";
    setLlmStatus("正在请求 LLM 优化，结果会写入优化脚本区…", "wait");
    try {
      const res = await optimizeRCode({
        provider,
        config,
        workflow: state.workflow,
        tab: state.tab,
        source_code: sourceCodeForCurrent(),
        instruction,
        ui_context: collectUiContext(),
      });
      const code = res.optimized_code || res.code || "";
      if (!code.trim()) throw new Error("LLM 未返回可用 R 代码");
      setOptimizedCode(code, `llm:${res.provider || res.model || provider}`);
      const modelHint = res.model ? `，模型 ${res.model}` : "";
      setLlmStatus(`已生成优化脚本（${res.provider || provider}${modelHint}），请先检查再运行。`, "ok");
      import("./teaching.js?v=2026-06-19-course-v9")
        .then((m) => m.traceEvent?.({
          event_type: "llm_optimize",
          workflow: state.workflow,
          tab: state.tab,
          provider: res.provider || provider,
          model: res.model,
        }))
        .catch(() => {});
    } catch (err) {
      setLlmStatus(err.message || String(err), "error");
    }
  });

  rootEl.querySelector("#code-lab-reset").addEventListener("click", (e) => {
    e.stopPropagation();
    if (!state.workflow || !state.tab) return;
    const s = loadStore();
    delete s.drafts[draftKey(state.workflow, state.tab)];
    if (s.optimized) delete s.optimized[draftKey(state.workflow, state.tab)];
    saveStore(s);
    const source = buildFreshTemplate(state.workflow, state.tab);
    if (originalEl) originalEl.value = source;
    setOptimizedCode(source, "reset");
  });

  rootEl.querySelector("#code-lab-copy").addEventListener("click", async (e) => {
    e.stopPropagation();
    try {
      await navigator.clipboard.writeText(taEl.value);
    } catch {
      /* ignore */
    }
  });

  rootEl.querySelector("#code-lab-exec").addEventListener("click", async (e) => {
    e.stopPropagation();
    const first = await runCodeInR(taEl.value, "优化脚本", sourceCodeForCurrent());
    if (first?.ok || !first?.error) return;
    await autoRepairAndRerun(first.error);
  });

  // AI auto-repair: when the optimized script fails, ask the LLM to fix it
  // (feeding back the exact R error) and re-run once. Best-effort; silently
  // gives up if no LLM is reachable.
  async function autoRepairAndRerun(errorMessage) {
    if (!state.workflow || !state.tab) return;
    const repairErrors = [
      "no experiment selected", "请先选择全局",
      "session", "code is empty",
    ];
    if (repairErrors.some((s) => String(errorMessage || "").includes(s))) return;
    let cfg;
    try { cfg = collectLlmConfig(); } catch { return; }
    if (!cfg?.provider) return;
    setLlmStatus("脚本运行报错，AI 正在尝试自动修复并重跑…", "wait");
    try {
      const res = await optimizeRCode({
        provider: cfg.provider,
        config: cfg.config,
        workflow: state.workflow,
        tab: state.tab,
        source_code: taEl.value,
        instruction:
          `上一版脚本运行报错，请仅修复使其能在当前会话内成功运行，` +
          `保持分析意图与发表级出图风格（emp_pub_theme）。报错信息：\n${errorMessage}`,
        ui_context: collectUiContext(),
      });
      const fixed = res.optimized_code || res.code || "";
      if (!fixed.trim()) throw new Error("AI 未返回修复后的代码");
      setOptimizedCode(fixed, `repair:${res.provider || cfg.provider}`);
      setLlmStatus("AI 已生成修复版脚本，正在重跑…", "wait");
      const second = await runCodeInR(taEl.value, "AI 修复后脚本", sourceCodeForCurrent());
      if (second?.ok) {
        setLlmStatus("AI 自动修复成功，脚本已正常运行。", "ok");
      } else {
        setLlmStatus(`AI 自动修复后仍报错，请手动检查：${second?.error || ""}`, "error");
      }
    } catch (err) {
      setLlmStatus(`AI 自动修复失败：${err.message || String(err)}`, "error");
    }
  }

  const ra = document.getElementById("ra-pipeline");
  ra?.addEventListener("change", () => {
    if (state.workflow === "runall") applyContext("runall", runallTabId());
  });

  applyCodeLabI18n();
  window.addEventListener("emp:locale-change", () => applyCodeLabI18n());
}
