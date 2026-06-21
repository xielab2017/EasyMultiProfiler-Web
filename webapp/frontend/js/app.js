// Main application – routing, state, page wiring.
// The ?v= query string is a cache-buster: browsers treat each unique URL
// as a separate module, so bumping this value forces clients to drop any
// stale copy of api.js held in the HTTP cache or the module map.  Keep
// this value in lock-step with the one used in index.html (app.js ?v=).
import * as API from "./api.js?v=2026-06-21-v5.0.1";
import {
  initCodeLab,
  notifyCodeLabNavigate,
  notifyCodeLabTab,
  notifyCodeLabClinicalStep,
  refreshCodeLabContext,
  openCodeLabPanel,
  applyCopilotAction,
} from "./code_lab.js?v=2026-06-21-v5.0.1";
import {
  initTeaching,
  onTeachingPage,
  setupTeachingTraceHooks,
} from "./teaching.js?v=2026-06-21-v5.0.1";
import { applyOmicsDefaults, omicsDefaultsHint } from "./omics_defaults.js?v=2026-06-21-v5.0.1";
import { initGuide, openGuideInstallTab } from "./guide.js?v=2026-06-21-v5.0.1";
import { initLocale, getLocale, t, pageTitleKey } from "./locale.js?v=2026-06-21-v5.0.1";
import { initFontScale } from "./font_scale.js?v=2026-06-21-v5.0.1";
import { initEvolution, trackPromptButtonClick } from "./evolution.js?v=2026-06-21-v5.0.1";

// ── Global state ──────────────────────────────────
window._emp = {
  experiments: [],      // [{name, samples, features, assay}]
  currentExp: null,     // string – currently selected experiment
  standaloneClinical: null, // {columns:[], orientation:"..."} for clinical-only uploads
  clinicalResolvedSource: "experiment",
  coldataCols: [],      // [{name, n_unique, values}]
  features: [],         // string[]
  workflows: [],        // [{id,label,description,n_stages}]
  inspector: {
    assayOffset: 1,
    assayLimit: 20,
    assayTotal: 0,
    rowOffset: 1,
    rowLimit: 50,
    rowTotal: 0,
  },
};

// ── Helpers ───────────────────────────────────────
export function toast(msg, type = "info") {
  const el = document.createElement("div");
  el.className = `toast toast-${type}`;
  el.textContent = msg;
  document.getElementById("toast-container").appendChild(el);
  setTimeout(() => el.remove(), 4000);
}

export function setLoading(on) {
  document.getElementById("loading-spinner").classList.toggle("hidden", !on);
}

// ── Global progress bar ───────────────────────────
// A single top-of-page strip that every long-running analysis can drive:
//     const job = await API.someAsyncRoute(...);
//     const result = await withGlobalProgress("KEGG enrichment", job.job_id);
// The helper polls the job, updates the bar, and returns the final result.
const _gp = () => ({
  wrap:  document.getElementById("global-progress"),
  label: document.getElementById("gp-label"),
  msg:   document.getElementById("gp-msg"),
  pct:   document.getElementById("gp-pct"),
  bar:   document.getElementById("gp-bar"),
});

export function showGlobalProgress(label = "Working…") {
  const g = _gp();
  if (!g.wrap) return;
  g.label.textContent = label;
  g.msg.textContent   = "";
  g.pct.textContent   = "0%";
  g.bar.style.setProperty("--pct", "0%");
  g.wrap.classList.remove("hidden");
}

export function updateGlobalProgress(pct, message = "") {
  const g = _gp();
  if (!g.wrap || g.wrap.classList.contains("hidden")) return;
  const p = Math.max(0, Math.min(100, Math.round(Number(pct) || 0)));
  g.pct.textContent = p + "%";
  g.bar.style.setProperty("--pct", p + "%");
  g.msg.textContent = message ? ` — ${message}` : "";
}

export function hideGlobalProgress() {
  const g = _gp();
  if (!g.wrap) return;
  g.wrap.classList.add("hidden");
  g.bar.style.setProperty("--pct", "0%");
}

// Submit an async backend call that returns `{ job_id }`, then poll until
// completion while driving the global progress bar.  The caller receives
// the final result object from `/api/jobs/<id>/result`.
export async function withGlobalProgress(label, jobPromiseOrId, opts = {}) {
  showGlobalProgress(label);
  // Drive an "indeterminate drift" between server-side bumps so the bar
  // *always* feels alive even during the long KEGG REST call.  The drift
  // is reset every time we receive a real progress update from the server.
  let seen = 0, drift = 0, driftTimer = null;
  const driftLoop = () => {
    const gap = Math.max(0, 95 - seen);
    if (gap <= 2) return;
    drift = Math.min(drift + 0.6, gap * 0.95);
    updateGlobalProgress(seen + drift, "");
  };
  driftTimer = setInterval(driftLoop, 400);

  try {
    const resp = typeof jobPromiseOrId === "string" ? { job_id: jobPromiseOrId } : await jobPromiseOrId;
    const jobId = resp?.job_id;
    if (!jobId) throw new Error("Backend did not return job_id");
    const { result } = await API.pollJobUntilDone(jobId, (job) => {
      const p = Number(job.progress ?? 0);
      if (p > seen) { seen = p; drift = 0; }
      updateGlobalProgress(Math.max(seen, p), job.message || "");
    }, opts.intervalMs ?? 600, opts.timeoutMs ?? 1800000);
    clearInterval(driftTimer);
    updateGlobalProgress(100, "Done");
    setTimeout(hideGlobalProgress, 600);
    return result;
  } catch (e) {
    clearInterval(driftTimer);
    updateGlobalProgress(100, `Failed: ${e.message}`);
    setTimeout(hideGlobalProgress, 2500);
    throw e;
  }
}

// Generic "show the top strip while this promise is pending".
// Use for synchronous backend endpoints that do NOT return a job_id so the
// user still sees visual feedback.  The strip moves with indeterminate
// drift (no real % from the server).
export async function withBusy(label, workPromiseOrFn, opts = {}) {
  showGlobalProgress(label);
  let drift = 0, driftTimer = null;
  const driftLoop = () => {
    // Climb asymptotically toward 92% – never reach 100 until we actually finish.
    drift = Math.min(drift + (92 - drift) * 0.08, 92);
    updateGlobalProgress(drift, opts.message || "");
  };
  driftTimer = setInterval(driftLoop, 300);
  const work = typeof workPromiseOrFn === "function" ? workPromiseOrFn() : workPromiseOrFn;
  try {
    const result = await work;
    clearInterval(driftTimer);
    updateGlobalProgress(100, "Done");
    setTimeout(hideGlobalProgress, 500);
    return result;
  } catch (e) {
    clearInterval(driftTimer);
    updateGlobalProgress(100, `Failed: ${e.message}`);
    setTimeout(hideGlobalProgress, 2500);
    throw e;
  }
}

export function showAlert(id, msg, type = "info") {
  const el = document.getElementById(id);
  if (!el) return;
  el.className = `alert alert-${type}`;
  el.textContent = msg;
  el.classList.remove("hidden");
}

export function clearAlert(id) {
  const el = document.getElementById(id);
  if (el) el.classList.add("hidden");
}

/** Normalise API payloads to an array of plain row objects for HTML tables. */
function coerceTableRows(payload) {
  let x = payload;
  for (let depth = 0; depth < 4 && typeof x === "string"; depth++) {
    const t = x.trim();
    if (!t) return [];
    try {
      x = JSON.parse(t);
    } catch {
      return [];
    }
  }
  if (x == null) return [];
  if (Array.isArray(x)) {
    if (x.length === 0) return [];
    if (typeof x[0] === "object" && x[0] !== null && !Array.isArray(x[0])) return x;
    return [];
  }
  if (typeof x === "object") {
    const keys = Object.keys(x);
    if (!keys.length) return [];
    const first = x[keys[0]];
    if (first != null && Array.isArray(first) &&
        keys.every((k) => Array.isArray(x[k])) &&
        keys.every((k) => x[k].length === first.length)) {
      const n = first.length;
      const out = [];
      for (let i = 0; i < n; i++) {
        const row = {};
        for (const k of keys) row[k] = x[k][i];
        out.push(row);
      }
      return out;
    }
    return [x];
  }
  return [];
}

export function showResultTable(containerId, jsonStr, maxRows = 500, options = {}) {
  const container = document.getElementById(containerId);
  if (!container) return;
  try {
    const rows = coerceTableRows(jsonStr);
    if (!Array.isArray(rows) || rows.length === 0) {
      const emptyMsg = options.emptyMessage || "No results returned.";
      container.innerHTML = `<p style='padding:12px;color:#64748b'>${emptyMsg}</p>`;
      container.classList.remove("hidden");
      return;
    }
    const cols = Object.keys(rows[0]);
    const pValueKey = options.pValueKey && cols.includes(options.pValueKey) ? options.pValueKey : null;
    const variableKey = options.variableKey && cols.includes(options.variableKey) ? options.variableKey : null;
    const prettyCol = (k) => options.prettyHeader ? String(k).replaceAll("_", " ").replaceAll(".", " ") : k;
    const fmtP = (v) => {
      const x = Number(v);
      if (!Number.isFinite(x)) return String(v ?? "");
      if (x < 1e-4) return x.toExponential(2);
      return x.toFixed(4);
    };
    const pStars = (v) => {
      const x = Number(v);
      if (!Number.isFinite(x)) return "";
      if (x < 0.001) return "***";
      if (x < 0.01) return "**";
      if (x < 0.05) return "*";
      return "";
    };
    const formatVariable = (v, isSection) => {
      const s = String(v ?? "").trim();
      if (!s) return "";
      const hasColon = s.endsWith(":");
      const core = hasColon ? s.slice(0, -1) : s;
      const normalized = core.replaceAll("_", " ").replace(/\s+/g, " ").trim();
      return isSection || hasColon ? `${normalized}:` : normalized;
    };
    const slice = rows.slice(0, maxRows);
    const thead = `<thead><tr>${cols.map(c=>`<th>${prettyCol(c)}</th>`).join("")}</tr></thead>`;
    const normalizeCell = (v) => {
      const s = String(v ?? "").trim();
      if (!s || s === "." || s === ". [.;.]" || s === ".%") return "-";
      if (/^\.\s*\[\.;\.\]$/.test(s)) return "-";
      if (/^\d+\s*\(\.%\)$/.test(s)) return s.replace("(.%)", "(0.0%)");
      return s;
    };
    const isSectionRow = (row) => {
      if (!variableKey) return false;
      const name = String(row[variableKey] ?? "").trim();
      if (!name.endsWith(":")) return false;
      return cols.filter((c) => c !== variableKey && c !== pValueKey).every((c) => !normalizeCell(row[c]) || normalizeCell(row[c]) === "-");
    };
    const bodyRows = slice.map((r) => {
      const section = isSectionRow(r);
      const trClass = section ? "section-row" : "data-row";
      return `<tr class="${trClass}">${cols.map((c, idx) => {
        const raw = r[c];
        const val0 = c === pValueKey ? fmtP(raw) : normalizeCell(raw);
        const stars = c === pValueKey ? pStars(raw) : "";
        const sig = c === pValueKey && Number(raw) < 0.05;
        let style = sig ? "font-weight:600;color:#b45309;" : "";
        if (section) style += "font-weight:700;";
        if (variableKey && c === variableKey && !section && String(raw ?? "").trim()) {
          style += "padding-left:16px;";
        }
        if (idx > 0) style += "text-align:center;";
        let val = c === pValueKey && val0 === "-" ? "-" : val0;
        if (c === pValueKey && Number.isFinite(Number(raw))) {
          const pv = Number(raw);
          val = pv < 0.001 ? "<0.001" : fmtP(pv);
        }
        if (variableKey && c === variableKey) {
          val = formatVariable(raw, section);
        }
        return `<td title="${raw ?? ''}" style="${style}">${val}${stars ? ` ${stars}` : ""}</td>`;
      }).join("")}</tr>`;
    }).join("");
    const tbody = `<tbody>${bodyRows}</tbody>`;
    const csvRows = [cols.join(",")].concat(
      rows.map((r) => cols.map((c) => {
        const v = r[c] ?? "";
        const s = String(v).replaceAll('"', '""');
        return /[",\n]/.test(s) ? `"${s}"` : s;
      }).join(","))
    );
    const csvBlob = new Blob([csvRows.join("\n")], { type: "text/csv;charset=utf-8;" });
    const csvUrl = URL.createObjectURL(csvBlob);
    container.innerHTML = `
      <div class="plot-toolbar">
        <a class="btn btn-outline" download="${options.downloadName || `${containerId}.csv`}" href="${csvUrl}">
          <i data-lucide="download"></i> Download CSV
        </a>
      </div>
      <table class="${options.tableClass || ""}">${thead}${tbody}</table>
    `;
    if (rows.length > maxRows) {
      container.insertAdjacentHTML("beforeend",
        `<p style="padding:8px 12px;font-size:12px;color:#64748b">Showing first ${maxRows} of ${rows.length} rows</p>`);
    }
    if (options.publicationNote) {
      container.insertAdjacentHTML("beforeend",
        `<p style="padding:6px 12px 10px;color:#64748b;font-size:12px">${options.publicationNote}</p>`);
    }
    container.classList.remove("hidden");
    if (options.aiCopilot !== false) {
      attachAiCopilot(container, { ...inferAiContext(containerId), kind: "table", ...(options.aiContext || {}) });
    }
  } catch(e) {
    container.innerHTML = `<p style='padding:12px;color:#991b1b'>Could not parse results: ${e.message}</p>`;
    container.classList.remove("hidden");
  }
}

export function showPlot(containerId, base64png) {
  const container = document.getElementById(containerId);
  if (!container) return;
  const pngSrc = `data:image/png;base64,${base64png}`;
  const mkCanvas = () => new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      const c = document.createElement("canvas");
      c.width = img.naturalWidth || img.width;
      c.height = img.naturalHeight || img.height;
      c.getContext("2d").drawImage(img, 0, 0);
      resolve(c);
    };
    img.onerror = reject;
    img.src = pngSrc;
  });
  const addDownloadHandler = (id, mime, name) => {
    const el = document.getElementById(id);
    if (!el) return;
    el.addEventListener("click", async (e) => {
      e.preventDefault();
      const c = await mkCanvas();
      let url = c.toDataURL(mime);
      // Some browsers don't support TIFF export; keep button and fallback to PNG bytes.
      if (mime === "image/tiff" && url.startsWith("data:image/png")) {
        url = c.toDataURL("image/png");
      }
      const a = document.createElement("a");
      a.href = url;
      a.download = name;
      a.click();
    });
  };
  container.innerHTML = `
    <div class="plot-toolbar">
      <a class="btn btn-outline" id="${containerId}-dl-png" href="${pngSrc}" download="plot.png"><i data-lucide="download"></i> PNG</a>
      <a class="btn btn-outline" id="${containerId}-dl-jpg" href="#"><i data-lucide="download"></i> JPEG</a>
      <a class="btn btn-outline" id="${containerId}-dl-tiff" href="#"><i data-lucide="download"></i> TIFF</a>
      <a class="btn btn-outline" id="${containerId}-dl-pdf" href="#"><i data-lucide="download"></i> PDF</a>
    </div>
    <img src="${pngSrc}" alt="Plot">
  `;
  container.classList.remove("hidden");
  addDownloadHandler(`${containerId}-dl-jpg`, "image/jpeg", "plot.jpg");
  addDownloadHandler(`${containerId}-dl-tiff`, "image/tiff", "plot.tiff");
  const pdfBtn = document.getElementById(`${containerId}-dl-pdf`);
  if (pdfBtn) {
    pdfBtn.addEventListener("click", async (e) => {
      e.preventDefault();
      const c = await mkCanvas();
      const jpgData = c.toDataURL("image/jpeg", 0.95);
      if (window.jspdf?.jsPDF) {
        const { jsPDF } = window.jspdf;
        const pdf = new jsPDF({
          orientation: c.width >= c.height ? "landscape" : "portrait",
          unit: "pt",
          format: [c.width, c.height],
        });
        pdf.addImage(jpgData, "JPEG", 0, 0, c.width, c.height);
        pdf.save("plot.pdf");
      } else {
        // Fallback: open print dialog if jsPDF is unavailable.
        const w = window.open("", "_blank");
        if (w) {
          w.document.write(`<img src="${jpgData}" style="max-width:100%;">`);
          w.document.close();
          w.print();
        }
      }
    });
  }
  // Re-initialise icons inside the new element
  if (window.lucide) lucide.createIcons({ nodes: [container] });
  attachAiCopilot(container, { ...inferAiContext(containerId), kind: "plot" });
}

// ── AI 分析助手 (Copilot) ───────────────────────────
// Adds a lightweight "AI 解读" button under any result table / plot. It posts a
// compact context to /api/ai/interpret and renders a student-friendly
// interpretation (LLM when configured, deterministic offline otherwise).

// Minimal, safe Markdown → HTML (headings, bold, ordered/unordered lists).
// (Reuses the shared escapeHtml defined later in this module.)
function renderMiniMarkdown(md) {
  const lines = String(md ?? "").split(/\r?\n/);
  let html = "";
  let listType = null;
  const closeList = () => { if (listType) { html += `</${listType}>`; listType = null; } };
  for (let raw of lines) {
    const line = raw.trimEnd();
    if (!line.trim()) { closeList(); continue; }
    let m;
    if ((m = line.match(/^#{1,6}\s+(.*)$/))) {
      closeList();
      html += `<h4 class="ai-md-h">${inline(m[1])}</h4>`;
    } else if ((m = line.match(/^\s*[-*]\s+(.*)$/))) {
      if (listType !== "ul") { closeList(); html += "<ul>"; listType = "ul"; }
      html += `<li>${inline(m[1])}</li>`;
    } else if ((m = line.match(/^\s*\d+\.\s+(.*)$/))) {
      if (listType !== "ol") { closeList(); html += "<ol>"; listType = "ol"; }
      html += `<li>${inline(m[1])}</li>`;
    } else {
      closeList();
      html += `<p>${inline(line)}</p>`;
    }
  }
  closeList();
  return html;
  function inline(t) {
    return escapeHtml(t)
      .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
      .replace(/`(.+?)`/g, "<code>$1</code>");
  }
}

function currentOmicsPreset() {
  try { return localStorage.getItem("emp_omics") || ""; } catch { return ""; }
}

// Infer {analysis_type, omics} from a result/plot container id like
// "alpha-result", "tx-viz-volcano-out", "mgx-diff-result".
function inferAiContext(domId) {
  let id = String(domId || "").replace(/-(result|out|table|output)$/i, "");
  const omicsPrefix = { tx: "transcriptomics", mgx: "metagenomics", mbx: "metabolomics", m16s: "microbiome_16s", chip: "chipseq" };
  let omics = currentOmicsPreset();
  const pfx = id.match(/^(tx|mgx|mbx|m16s)-/);
  if (pfx) { omics = omicsPrefix[pfx[1]] || omics; id = id.replace(/^(tx|mgx|mbx|m16s)-/, ""); }
  id = id.replace(/^(viz|analysis|ana)-/, "").replace(/-(plot|viz|out)$/, "");
  const map = {
    alpha: "alpha", "alpha-plot": "alpha", dim: "dimension", scatter: "scatter",
    cor: "correlation", cluster: "cluster", marker: "marker", enrich: "enrichment",
    diff: "differential", volcano: "volcano", heatmap: "heatmap", boxplot: "boxplot",
    barplot: "barplot", structure: "structure", sankey: "structure", network: "network",
    analysis: "differential",
  };
  const analysis_type = map[id] || id || "analysis";
  return { analysis_type, omics, experiment: window._emp?.currentExp || null };
}

// Derive quick stats from a differential-style table to enrich interpretation.
function deriveTableStats(rows, cols) {
  const stats = {};
  if (!Array.isArray(rows) || !rows.length) return stats;
  stats.n_total = rows.length;
  const lc = cols.map((c) => String(c).toLowerCase());
  const findCol = (cands) => { for (const cand of cands) { const i = lc.indexOf(cand); if (i >= 0) return cols[i]; } return null; };
  const padjCol = findCol(["padj", "p_adj", "fdr", "qvalue", "q_value", "adj.p.val", "adj_pval"]);
  const pCol = findCol(["pvalue", "p_value", "pval", "p"]);
  const fcCol = findCol(["log2fc", "log2foldchange", "logfc", "log2_fc", "fc"]);
  const sigCol = padjCol || pCol;
  if (sigCol) {
    let nsig = 0, up = 0, down = 0;
    for (const r of rows) {
      const p = Number(r[sigCol]);
      if (Number.isFinite(p) && p < 0.05) {
        nsig++;
        if (fcCol) { const fc = Number(r[fcCol]); if (Number.isFinite(fc)) { if (fc > 0) up++; else if (fc < 0) down++; } }
      }
    }
    stats.n_significant = nsig;
    if (fcCol) { stats.n_up = up; stats.n_down = down; }
  }
  return stats;
}

const INTERPRET_CARD_KEYS = [
  { key: "interpretation", titleKey: "copilot.card.interpretation" },
  { key: "limitations", titleKey: "copilot.card.limitations" },
  { key: "figure_optimization", titleKey: "copilot.card.figure" },
  { key: "downstream_guidance", titleKey: "copilot.card.downstream" },
  { key: "manuscript_panel", titleKey: "copilot.card.manuscript" },
];

function renderInterpretCards(sections, promptButtons, baseContext) {
  const sec = sections || {};
  const cards = INTERPRET_CARD_KEYS.filter(({ key }) => sec[key] && String(sec[key]).trim())
    .map(({ key, titleKey }) => {
      const isFigure = key === "figure_optimization";
      const btnHtml = isFigure && Array.isArray(promptButtons) && promptButtons.length
        ? `<div class="ai-copilot-prompt-btns">${
            promptButtons.map((b, i) => `
              <button type="button" class="btn btn-outline btn-sm ai-prompt-btn"
                data-prompt-idx="${i}">${escapeHtml(b.label || t("copilot.action.default"))}</button>`).join("")
          }</div>`
        : "";
      return `<article class="ai-interpret-card ai-interpret-card--${key}">
        <h4 class="ai-interpret-card-title">${escapeHtml(t(titleKey))}</h4>
        <div class="ai-interpret-card-body">${renderMiniMarkdown(sec[key])}</div>
        ${btnHtml}
      </article>`;
    }).join("");
  if (cards) return `<div class="ai-interpret-cards">${cards}</div>`;
  return `<div class="ai-copilot-body">${renderMiniMarkdown(sec.interpretation || "")}</div>`;
}

function attachAiCopilot(container, baseContext) {
  if (!container || container.querySelector(".ai-copilot")) return;
  const wrap = document.createElement("div");
  wrap.className = "ai-copilot";
  wrap.innerHTML = `
    <button type="button" class="btn btn-outline ai-copilot-btn">
      <i data-lucide="sparkles"></i> <span class="ai-copilot-btn-label">${t("copilot.btn")}</span>
    </button>
    <div class="ai-copilot-panel hidden"></div>
  `;
  container.appendChild(wrap);
  if (window.lucide) lucide.createIcons({ nodes: [wrap] });
  const btn = wrap.querySelector(".ai-copilot-btn");
  const panel = wrap.querySelector(".ai-copilot-panel");

  btn.addEventListener("click", async () => {
    panel.classList.remove("hidden");
    panel.innerHTML = `<p class="ai-copilot-loading">${t("copilot.loading")}</p>`;
    btn.disabled = true;
    try {
      const ctx = { ...baseContext };
      // Enrich with table data if present.
      const table = container.querySelector("table");
      if (table) {
        const cols = [...table.querySelectorAll("thead th")].map((th) => th.textContent.trim());
        const bodyRows = [...table.querySelectorAll("tbody tr")].slice(0, 8).map((tr) => {
          const cells = [...tr.querySelectorAll("td")];
          const obj = {};
          cells.forEach((td, i) => { obj[cols[i] || `c${i}`] = (td.getAttribute("title") || td.textContent).trim(); });
          return obj;
        });
        const allRows = [...table.querySelectorAll("tbody tr")].map((tr) => {
          const cells = [...tr.querySelectorAll("td")];
          const obj = {};
          cells.forEach((td, i) => { obj[cols[i] || `c${i}`] = (td.getAttribute("title") || td.textContent).trim(); });
          return obj;
        });
        ctx.table = { columns: cols, n_rows: allRows.length, rows: bodyRows };
        ctx.stats = { ...deriveTableStats(allRows, cols), ...(ctx.stats || {}) };
      }
      const dsExp = (window._emp?.experiments || []).find((e) => e.name === window._emp?.currentExp);
      if (dsExp) ctx.dataset = { n_samples: dsExp.samples, n_features: dsExp.features };
      const gSel = document.getElementById("global-experiment")?.closest("#main") &&
        (document.querySelector("#tx-group, #m16s-group, #mbx-group, [id$='-group']")?.value);
      if (gSel) ctx.group = gSel;
      const plotImg = container.querySelector("img[src^='data:image']");
      if (plotImg) {
        ctx.plot_present = true;
        // Send the actual PNG so vision-capable models can critique the figure.
        const src = plotImg.getAttribute("src") || "";
        if (src.length <= 6_000_000) ctx.plot_image = src;
      }
      ctx.locale = getLocale();
      ctx.lang = ctx.locale;
      const res = await API.aiInterpret(ctx);
      const sourceBadge = res.source === "llm"
        ? `<span class="ai-copilot-src ai-src-llm">${t("copilot.src.llm")}</span>${
            res.vision ? `<span class="ai-copilot-src ai-src-vision">${t("copilot.src.vision")}</span>` : ""}`
        : `<span class="ai-copilot-src ai-src-offline">${t("copilot.src.offline")}</span>`;
      const sections = res.sections || {};
      const promptButtons = res.prompt_buttons || [];
      const actions = res.actions || [];
      const checklist = res.visual_checklist || [];
      const bodyHtml = (sections.interpretation || sections.limitations)
        ? renderInterpretCards(sections, promptButtons, baseContext)
        : `<div class="ai-copilot-body">${renderMiniMarkdown(res.interpretation)}</div>`;
      const checklistHtml = (baseContext.kind === "plot" && checklist.length)
        ? `<details class="ai-copilot-checklist"><summary class="hint">${t("copilot.checklist.summary")} (${checklist.length})</summary><ol class="ai-checklist-ol">${
            checklist.map((item) => `<li>${escapeHtml(item)}</li>`).join("")
          }</ol></details>`
        : "";
      const actionsHtml = actions.length
        ? `<div class="ai-copilot-actions"><p class="hint">${t("copilot.actions.hint")}</p>${
            actions.map((a) => `
              <button type="button" class="btn btn-outline btn-sm ai-copilot-action"
                data-workflow="${escapeHtml(a.workflow || "")}"
                data-tab="${escapeHtml(a.tab || "")}"
                data-instruction="${escapeHtml(a.instruction || "")}"
                data-auto="${a.auto_optimize ? "1" : "0"}">${escapeHtml(a.label || t("copilot.action.default"))}</button>`).join("")
          }</div>`
        : "";
      panel.innerHTML = `
        <div class="ai-copilot-head">${sourceBadge}
          <span class="ai-copilot-hint">${t("copilot.disclaimer")}</span>
        </div>
        ${bodyHtml}
        ${checklistHtml}
        ${actionsHtml}`;
      const wfPage = baseContext.kind === "plot" ? "visualization" : "analysis";
      const wfTab = baseContext.analysis_type === "heatmap" ? "viz-heatmap" : null;
      panel.querySelectorAll(".ai-prompt-btn").forEach((pb) => {
        pb.addEventListener("click", () => {
          const idx = Number(pb.dataset.promptIdx);
          const item = promptButtons[idx];
          if (!item?.prompt) return;
          trackPromptButtonClick(item.label || "", { analysis_type: ctx.analysis_type });
          window.dispatchEvent(new CustomEvent("emp:apply-copilot-action", {
            detail: {
              page: wfPage,
              tab: wfTab,
              instruction: item.prompt,
              autoOptimize: false,
            },
          }));
          toast(t("copilot.toast.applied"), "success");
        });
      });
      panel.querySelectorAll(".ai-copilot-action").forEach((btn) => {
        btn.addEventListener("click", () => {
          const page = btn.dataset.workflow || "analysis";
          window.dispatchEvent(new CustomEvent("emp:apply-copilot-action", {
            detail: {
              page,
              tab: btn.dataset.tab || null,
              instruction: btn.dataset.instruction || "",
              autoOptimize: btn.dataset.auto === "1",
            },
          }));
          toast(t("copilot.toast.applied"), "success");
        });
      });
      if (window.lucide) lucide.createIcons({ nodes: [panel] });
      window.dispatchEvent(new CustomEvent("emp:ai-interpret", {
        detail: { analysis_type: ctx.analysis_type, source: res.source, locale: ctx.locale },
      }));
    } catch (e) {
      panel.innerHTML = `<p class="ai-copilot-error">${escapeHtml(t("copilot.error"))}${escapeHtml(e.message)}</p>`;
    } finally {
      btn.disabled = false;
    }
  });
}

function toStringArray(value) {
  if (Array.isArray(value)) return value.map((v) => String(v));
  if (typeof value === "string") return value ? [value] : [];
  if (value && typeof value === "object") return Object.values(value).map((v) => String(v));
  return [];
}

function escapeHtml(text) {
  return String(text ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

async function ensureWorkflowReady(workflowId, exp, opts = {}) {
  const alertId = opts.alertId || null;
  const checkerMap = {
    transcriptomics: API.txValidate,
    microbiome_16s: API.m16sValidate,
    metagenomics: API.mgxValidate,
    metabolomics: API.mbxValidate,
    chipseq: API.chipValidate,
  };
  const checker = checkerMap[workflowId];
  if (!checker) return true;
  const resp = await checker(exp, opts.params || {});
  const validation = resp.validation || {};
  const checks = validation.checks || {};
  const failed = Object.entries(checks).filter(([, v]) => v === false).map(([k]) => k);
  const checkLabelMap = {
    has_assay: "数据矩阵为空或未加载",
    has_metadata: "缺少样本元数据",
    has_group_candidates: "没有可用于分组分析的分类列",
    has_features: "特征数量不足",
    has_samples: "样本数量不足",
    taxonomy_depth_ok: "分类层级信息不足（至少需要两级）",
    missingness_high: "缺失率较高（建议先预处理）",
  };
  if (failed.length) {
    const readable = failed.map((k) => checkLabelMap[k] || k);
    const msg = `预检查未通过：${readable.join("；")}。请先完善数据或参数设置。`;
    if (alertId) showAlert(alertId, msg, "error");
    throw new Error(msg);
  }
  if (alertId) {
    showAlert(alertId, "预检查通过，开始执行流程...", "info");
  }
  return true;
}

// ── Navigation ────────────────────────────────────
const pageTitles = {
  course: "Course Cases",
  guide: "User Guide · 使用指南",
  prompts: "AI Prompt Library",
  import: "Import Data",
  summary: "Data Summary",
  inspector: "EMPT Inspector",
  preparation: "Data Preparation",
  analysis: "Analysis",
  clinical: "Clinical & Phenotype",
  runall: "One-click Run All",
  visualization: "Visualization",
  export: "Export Results",
};

const WORKFLOW_ORDER = [
  "guide", "course", "prompts", "import", "summary", "inspector",
  "preparation", "analysis", "clinical", "runall", "visualization", "export",
];

function updateWorkflowStepper(page) {
  const stepper = document.getElementById("workflow-stepper");
  if (!stepper) return;
  const activeIdx = WORKFLOW_ORDER.indexOf(page);
  stepper.querySelectorAll(".wf-step").forEach(el => {
    const stepIdx = WORKFLOW_ORDER.indexOf(el.dataset.wf);
    const isActive = el.dataset.wf === page;
    el.classList.toggle("is-active", isActive);
    el.classList.toggle("is-done", activeIdx >= 0 && stepIdx >= 0 && stepIdx < activeIdx);
  });
}

function navigateTo(page) {
  document.querySelectorAll(".nav-item").forEach(el => {
    el.classList.toggle("active", el.dataset.page === page);
  });
  document.querySelectorAll(".page").forEach(el => el.classList.remove("active"));
  const target = document.getElementById(`page-${page}`);
  if (target) target.classList.add("active");
  document.getElementById("page-title").textContent = t(pageTitleKey(page), getLocale()) || page;
  updateWorkflowStepper(page);
  try { localStorage.setItem("emp_last_page", page); } catch { /* quota */ }
  window.dispatchEvent(new CustomEvent("emp:page-view", { detail: { page, locale: getLocale() } }));

  // Refresh dynamic content on navigation
  if (page === "summary") loadSummary();
  if (page === "inspector") loadInspector();
  if (page === "analysis" || page === "visualization" || page === "preparation") refreshGroupSelectors();
  if (page === "preparation" && window._emp.currentExp) refreshPrepareSnapshots();
  if (page === "clinical") refreshClinicalVars();
  if (page === "course" || page === "prompts") onTeachingPage(page);
  if (page === "guide") initGuide();
  notifyCodeLabNavigate(page);
}

window.__empNavigate = navigateTo;

window.addEventListener("emp:toast", (e) => {
  const { msg, type } = e.detail || {};
  if (msg) toast(msg, type || "info");
});

window.addEventListener("emp:apply-copilot-action", (e) => {
  const { page, tab, instruction, autoOptimize } = e.detail || {};
  if (page) navigateTo(page);
  applyCopilotAction({ page, tab, instruction, autoOptimize });
});

window.addEventListener("emp:open-code-lab", (e) => {
  const page = e.detail?.page || "analysis";
  navigateTo(page);
  openCodeLabPanel(page);
});

document.getElementById("workflow-stepper")?.addEventListener("click", (e) => {
  const step = e.target.closest(".wf-step");
  if (!step?.dataset.wf) return;
  navigateTo(step.dataset.wf);
});

window.addEventListener("emp:import-demo", (e) => {
  const { datasetId, omics } = e.detail || {};
  if (datasetId) importDemoById(datasetId, omics);
});

document.getElementById("btn-help-guide")?.addEventListener("click", () => navigateTo("guide"));
document.getElementById("btn-welcome-guide")?.addEventListener("click", () => {
  document.getElementById("welcome-card")?.classList.add("hidden");
  navigateTo("guide");
});
document.getElementById("btn-course-to-guide")?.addEventListener("click", () => navigateTo("guide"));
document.getElementById("btn-help-course")?.addEventListener("click", () => navigateTo("course"));
document.getElementById("btn-welcome-course")?.addEventListener("click", () => {
  document.getElementById("welcome-card")?.classList.add("hidden");
  navigateTo("course");
});
document.getElementById("btn-welcome-dismiss")?.addEventListener("click", () => {
  document.getElementById("welcome-card")?.classList.add("hidden");
  try { localStorage.setItem("emp_welcome_dismissed", "1"); } catch { /* quota */ }
});

function bindUploadDropZone(zoneId, inputId, filenameId, onFile) {
  const zone = document.getElementById(zoneId);
  const input = document.getElementById(inputId);
  if (!zone || !input) return;
  zone.addEventListener("dragover", (e) => {
    e.preventDefault();
    zone.classList.add("is-dragover");
  });
  zone.addEventListener("dragleave", () => zone.classList.remove("is-dragover"));
  zone.addEventListener("drop", (e) => {
    e.preventDefault();
    zone.classList.remove("is-dragover");
    const file = e.dataTransfer?.files?.[0];
    if (!file) return;
    const dt = new DataTransfer();
    dt.items.add(file);
    input.files = dt.files;
    input.dispatchEvent(new Event("change", { bubbles: true }));
    if (onFile) onFile(file);
  });
}

async function loadDemoDatasetButtons() {
  const root = document.getElementById("demo-dataset-buttons");
  if (!root) return;
  try {
    const datasets = await API.listDemoDatasets();
    const available = datasets.filter(d => d.available);
    if (!available.length) {
      root.innerHTML = `<span class="hint">${t("demo.unavailable")}</span>`;
      return;
    }
    root.innerHTML = available.map(d => `
      <button type="button" class="btn btn-outline demo-dataset-btn" data-demo-id="${escapeHtml(d.id)}" data-omics="${escapeHtml(d.omics || "")}">
        ${escapeHtml(d.label)}
      </button>`).join("");
    root.querySelectorAll(".demo-dataset-btn").forEach(btn => {
      btn.addEventListener("click", () => importDemoById(btn.dataset.demoId, btn.dataset.omics));
    });
  } catch (e) {
    root.innerHTML = `<span class="hint">${t("demo.loadFail")}${escapeHtml(e.message)}</span>`;
  }
}

async function importDemoById(datasetId, omics) {
  setLoading(true);
  try {
    if (!localStorage.getItem("emp_session_id")) await API.createSession();
    const res = await withBusy("Loading demo data", () => API.importDemoDataset(datasetId));
    if (omics && omics !== "clinical") {
      const sel = document.getElementById("omics-pipeline");
      if (sel) sel.value = omics;
      window.dispatchEvent(new CustomEvent("emp:omics-change", { detail: { omics } }));
    }
    if (res.import_mode === "clinical_standalone" || res.import_mode === "clinical_merge") {
      showAlert("import-result",
        `✓ 临床示例已加载。${res.columns?.length ? ` ${res.columns.length} 个变量。` : ""}`,
        "success");
      if (res.import_mode === "clinical_standalone") {
        window._emp.standaloneClinical = {
          columns: res.columns || [],
          orientation: res.orientation || "samples in rows",
        };
      }
      toast(t("demo.clinicalReady"), "success");
      navigateTo("clinical");
    } else {
      showAlert("import-result",
        `✓ 已加载「${res.experiment_name}」：${res.samples} 样本 · ${res.features} 特征`,
        "success");
      toast(t("demo.imported", null, { name: res.experiment_name }), "success");
      await refreshExperimentList();
      applyOmicsDefaults(omics || document.getElementById("omics-pipeline")?.value, { silent: false });
      navigateTo("summary");
    }
    document.getElementById("btn-topbar-clear")?.classList.remove("hidden");
  } catch (e) {
    showAlert("import-result", `Error: ${e.message}`, "error");
    toast(e.message, "error");
  } finally {
    setLoading(false);
  }
}

document.querySelectorAll(".nav-item").forEach(el => {
  el.addEventListener("click", () => navigateTo(el.dataset.page));
});

async function loadWorkflowBlueprint() {
  const listEl = document.getElementById("workflow-list");
  const detailEl = document.getElementById("workflow-detail");
  if (!listEl || !detailEl) return;

  try {
    const workflows = await API.getWorkflows();
    window._emp.workflows = workflows;
    if (!workflows.length) return;

    listEl.innerHTML = workflows.map(w =>
      `<button class="tag workflow-tag" data-workflow-id="${escapeHtml(w.id)}">${escapeHtml(w.label)}</button>`
    ).join("");

    listEl.querySelectorAll(".workflow-tag").forEach(btn => {
      btn.addEventListener("click", async () => {
        const wid = btn.dataset.workflowId;
        try {
          const wf = await API.getWorkflow(wid);
          const stageHtml = (wf.stages || []).map(s => `
            <div style="margin-bottom:10px">
              <strong>${escapeHtml(s.name)}</strong>
              <ul style="margin:6px 0 0 16px;">
                ${(s.steps || []).map(step => `<li>${escapeHtml(step)}</li>`).join("")}
              </ul>
            </div>
          `).join("");

          detailEl.innerHTML = `
            <h4 style="margin-bottom:6px">${escapeHtml(wf.label)}</h4>
            <p style="margin-bottom:10px;color:#475569">${escapeHtml(wf.description)}</p>
            ${stageHtml}
          `;
          detailEl.classList.remove("hidden");
        } catch (e) {
          detailEl.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${escapeHtml(e.message)}</p>`;
          detailEl.classList.remove("hidden");
        }
      });
    });
  } catch (e) {
    // keep this silent; workflow endpoint may be unavailable during partial deployments
  }
}

// ── Tab switching ─────────────────────────────────
document.querySelectorAll(".tab-bar").forEach(bar => {
  bar.addEventListener("click", e => {
    const tab = e.target.closest(".tab");
    if (!tab) return;
    const targetId = tab.dataset.tab;
    const panel = document.getElementById(targetId);
    if (!panel) return;
    bar.querySelectorAll(".tab").forEach(t => t.classList.remove("active"));
    tab.classList.add("active");
    const allPanels = bar.nextElementSibling
      ? [...bar.parentElement.querySelectorAll(".tab-panel")] : [];
    // Find panels in same section
    const section = tab.closest("section");
    section.querySelectorAll(".tab-panel").forEach(p => p.classList.add("hidden"));
    panel.classList.remove("hidden");
    panel.classList.add("active");
    // Side-effects on tab activation.
    // Enrichment tab: refresh the OrgDb status so users see "Install now"
    // immediately when the backend reports a missing species package.
    if (targetId === "ana-enrich" && typeof refreshEnrichmentSpecies === "function") {
      refreshEnrichmentSpecies();
    }
    const sec = tab.closest("section");
    if (sec?.id?.startsWith("page-")) {
      const pageKey = sec.id.slice(5);
      notifyCodeLabTab(pageKey, targetId);
    }
  });
});

// ── Global experiment selector ─────────────────────
const globalExp = document.getElementById("global-experiment");
globalExp.addEventListener("change", () => {
  window._emp.currentExp = globalExp.value;
  refreshGroupSelectors();
});

async function refreshExperimentList() {
  try {
    const exps = await API.listExperiments();
    window._emp.experiments = exps;
    const cards = document.getElementById("exp-cards");
    if (!exps.length) {
      window._emp.currentExp = null;
      globalExp.innerHTML = "";
      document.getElementById("exp-selector-wrap").classList.add("hidden");
      // Recover standalone clinical state even after page refresh.
      let sc = window._emp.standaloneClinical;
      if (!sc) {
        try {
          const sv = await API.clinicalVarsStandalone();
          const rows = Array.isArray(sv?.data) ? sv.data : [];
          if (rows.length) {
            sc = { columns: rows.map(r => r.name), orientation: "samples in rows" };
            window._emp.standaloneClinical = sc;
          }
        } catch (_) {
          // no standalone clinical table in this session
        }
      }
      if (sc && cards) {
        cards.innerHTML = `
          <div class="exp-card">
            <h4>Standalone Clinical Table</h4>
            <div class="meta">${(sc.columns || []).length} variables</div>
            <div class="meta">Orientation: ${sc.orientation || "samples in rows"}</div>
          </div>
        `;
        document.getElementById("import-experiments").classList.remove("hidden");
      } else {
        document.getElementById("import-experiments").classList.add("hidden");
      }
      return;
    }

    // Global selector
    const wrap = document.getElementById("exp-selector-wrap");
    wrap.classList.remove("hidden");
    globalExp.innerHTML = exps.map(e => `<option value="${e.name}">${e.name}</option>`).join("");
    if (!window._emp.currentExp || !exps.some(e => e.name === window._emp.currentExp)) {
      window._emp.currentExp = exps[0].name;
    }
    globalExp.value = window._emp.currentExp;
    const crossA = document.getElementById("cross-exp-a");
    const crossB = document.getElementById("cross-exp-b");
    const crossC = document.getElementById("cross-exp-c");
    if (crossA && crossB) {
      const html = exps.map(e => `<option value="${e.name}">${e.name}</option>`).join("");
      crossA.innerHTML = html;
      crossB.innerHTML = html;
      if (exps.length > 1) crossB.value = exps[1].name;
      if (crossC) crossC.innerHTML = `<option value="">none</option>${html}`;
    }
    const markerExp = document.getElementById("clin-marker-experiments");
    if (markerExp) {
      markerExp.innerHTML = exps.map(e => `<option value="${e.name}" selected>${e.name}</option>`).join("");
    }

    // Import page cards
    cards.innerHTML = exps.map(e => `
      <div class="exp-card">
        <h4>${e.name}</h4>
        <div class="meta">${e.samples} samples · ${e.features} features</div>
        <div class="meta">Assay: ${e.assay}</div>
      </div>
    `).join("");
    document.getElementById("import-experiments").classList.remove("hidden");

    // Session badge
    document.getElementById("session-badge").classList.remove("hidden");

    await refreshGroupSelectors();
    await refreshPrepareSnapshots();
  } catch (e) {
    // Common case: clinical-only session has no MAE experiments.
    // Try standalone clinical fallback before showing failure state.
    const cards = document.getElementById("exp-cards");
    try {
      const sv = await API.clinicalVarsStandalone();
      const rows = Array.isArray(sv?.data) ? sv.data : [];
      if (rows.length) {
        window._emp.currentExp = null;
        window._emp.standaloneClinical = { columns: rows.map(r => r.name), orientation: "samples in rows" };
        globalExp.innerHTML = "";
        document.getElementById("exp-selector-wrap").classList.add("hidden");
        if (cards) {
          cards.innerHTML = `
            <div class="exp-card">
              <h4>Standalone Clinical Table</h4>
              <div class="meta">${rows.length} variables</div>
              <div class="meta">Source: session clinical upload</div>
            </div>
          `;
        }
        document.getElementById("import-experiments").classList.remove("hidden");
        document.getElementById("session-badge").classList.remove("hidden");
        return;
      }
    } catch (_) {
      // fallback probe failed, show normal error path below
    }
    document.getElementById("exp-selector-wrap").classList.add("hidden");
    document.getElementById("import-experiments").classList.add("hidden");
    toast(`Load data failed: ${e.message}`, "error");
  }
}

async function refreshGroupSelectors() {
  const exp = window._emp.currentExp;
  if (!exp) return;
  try {
    const cd = await API.getColdata(exp);
    window._emp.coldataCols = cd.columns || [];
    const ft = await API.getFeatures(exp);
    window._emp.features = ft.features || [];
  } catch(e) { return; }

  const GROUP_NAME_HINTS = new Set([
    "group", "subgroup", "cohort", "condition", "disease", "diagnosis", "treatment",
  ]);
  const groupColumnOptions = (cols) => {
    const isInternal = (name) => /(_safe|__emp)$/i.test(String(name || ""));
    const usable = (cols || []).filter((c) => {
      if (isInternal(c.name)) return false;
      const n = Number(c.n_unique) || 0;
      if (n < 2) return false;
      const key = String(c.name || "").toLowerCase();
      if (GROUP_NAME_HINTS.has(key)) return true;
      return n <= 50;
    });
    const preferred = usable.filter((c) => GROUP_NAME_HINTS.has(String(c.name || "").toLowerCase()));
    const rest = usable.filter((c) => !preferred.includes(c));
  preferred.sort((a, b) => String(a.name).localeCompare(String(b.name)));
  rest.sort((a, b) => String(a.name).localeCompare(String(b.name)));
    return [...preferred, ...rest];
  };

  const groupSelectors = [
    "bar-group","box-group","heat-group","scat-group","struct-group","aplot-group",
    "diff-group","marker-group","mgx-group","mgx-viz-group","mbx-group",
    "tx-group","tx-viz-group","ra-group"
  ];
  const cats = groupColumnOptions(window._emp.coldataCols);
  groupSelectors.forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    const hasNone = el.id.startsWith("bar-") || el.id.startsWith("box-") ||
                    el.id.startsWith("heat-") || el.id.startsWith("scat-") ||
                    el.id.startsWith("struct-") || el.id.startsWith("aplot-");
    el.innerHTML = (hasNone ? '<option value="">None</option>' : '') +
      cats.map(c => {
        const preview = (c.values || []).slice(0, 4).join(", ");
        const suffix = preview ? ` — ${preview}${(c.values || []).length > 4 ? "…" : ""}` : ` (${c.n_unique})`;
        return `<option value="${c.name}">${c.name}${suffix}</option>`;
      }).join("");
  });

  const autoGroup =
    cats.find((c) => String(c.name).toLowerCase() === "group") ||
    cats.find((c) => GROUP_NAME_HINTS.has(String(c.name).toLowerCase()));
  if (autoGroup) {
    groupSelectors.forEach((id) => {
      const el = document.getElementById(id);
      if (el && !el.value) el.value = autoGroup.name;
    });
  }

  // Feature selectors
  const featureSelectors = ["bar-feature","box-feature"];
  const feats = window._emp.features.slice(0, 500);
  featureSelectors.forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    el.innerHTML = feats.map(f => `<option value="${f}">${f}</option>`).join("");
  });

  // Group-dependent: ref / test group.
  // refreshGroupSelectors() runs on every experiment refresh / navigation, so
  // guard against attaching duplicate change listeners (which would fire the
  // ref/test updaters multiple times per change).
  const bindGroupChange = (id, handler) => {
    const el = document.getElementById(id);
    if (!el || el.dataset.groupChangeBound === "1") return;
    el.addEventListener("change", handler);
    el.dataset.groupChangeBound = "1";
  };
  bindGroupChange("diff-group", updateDiffGroups);
  bindGroupChange("marker-group", updateMarkerGroups);
  bindGroupChange("mgx-group", updateMgxGroups);
  bindGroupChange("mbx-group", updateMbxGroups);
  bindGroupChange("tx-group", updateTxGroups);
  bindGroupChange("ra-group", updateRaGroups);
  bindGroupChange("diff-method", updateDiffComparisonUI);
  bindGroupChange("diff-comparison-mode", updateDiffComparisonUI);
  updateDiffGroups();
  updateMarkerGroups();
  updateMgxGroups();
  updateMbxGroups();
  updateTxGroups();
  updateRaGroups();
}

function updateMarkerGroups() {
  const gEl = document.getElementById("marker-group");
  if (!gEl) return;
  const col = window._emp.coldataCols.find(c => c.name === gEl.value);
  const vals = col ? col.values : [];
  ["marker-ref", "marker-test"].forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    el.innerHTML = '<option value="">(auto)</option>' +
      vals.map(v => `<option value="${v}">${v}</option>`).join("");
  });
  if (vals.length >= 2) document.getElementById("marker-test").value = vals[1];
}

function updateRaGroups() {
  const gEl = document.getElementById("ra-group");
  if (!gEl) return;
  const col = window._emp.coldataCols.find(c => c.name === gEl.value);
  const vals = col ? col.values : [];
  ["ra-ref", "ra-test"].forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    el.innerHTML = '<option value="">(auto)</option>' +
      vals.map(v => `<option value="${v}">${v}</option>`).join("");
  });
  // Pre-fill a sensible 2-group contrast so Run All works on the first click.
  // Prefer a control-looking level (DMSO/Control/...) as reference.
  if (vals.length >= 2) {
    const ctrlRe = /^(dmso|control|ctrl|ctl|wt|wildtype|healthy|normal|baseline|veh(icle)?|untreated|pbs|mock|sham|hc)$/i;
    const ref = vals.find(v => ctrlRe.test(String(v))) || vals[0];
    const test = vals.find(v => v !== ref) || vals[1];
    const refEl = document.getElementById("ra-ref");
    const testEl = document.getElementById("ra-test");
    if (refEl) refEl.value = ref;
    if (testEl) testEl.value = test;
  }
}

function updateDiffGroups() {
  const gEl = document.getElementById("diff-group");
  if (!gEl) return;
  const col = window._emp.coldataCols.find(c => c.name === gEl.value);
  const vals = col ? col.values : [];
  ["diff-ref","diff-test"].forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    el.innerHTML = vals.map(v => `<option value="${v}">${v}</option>`).join("");
  });
  if (vals.length >= 2) {
    document.getElementById("diff-test").value = vals[1];
  }
  updateDiffComparisonUI();
}

function updateDiffComparisonUI() {
  const modeEl = document.getElementById("diff-comparison-mode");
  const methodEl = document.getElementById("diff-method");
  if (!modeEl) return;
  const method = methodEl?.value || "DESeq2";
  const multiCapable = method === "DESeq2" || method === "edgeR";
  [...modeEl.options].forEach(opt => {
    if (opt.value !== "pairwise") opt.disabled = !multiCapable;
  });
  if (!multiCapable && modeEl.value !== "pairwise") modeEl.value = "pairwise";
  const showPair = modeEl.value === "pairwise";
  document.querySelectorAll(".diff-pairwise-only").forEach(el => {
    el.classList.toggle("hidden", !showPair);
  });
  const subsetEl = document.getElementById("diff-subset");
  if (subsetEl) {
    const multi = modeEl.value !== "pairwise";
    if (multi) subsetEl.value = "false";
    subsetEl.disabled = multi;
  }
}

function updateMgxGroups() {
  const gEl = document.getElementById("mgx-group");
  if (!gEl) return;
  const col = window._emp.coldataCols.find(c => c.name === gEl.value);
  const vals = col ? col.values : [];
  ["mgx-ref", "mgx-test"].forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    el.innerHTML = vals.map(v => `<option value="${v}">${v}</option>`).join("");
  });
  if (vals.length >= 2) document.getElementById("mgx-test").value = vals[1];
}

function updateMbxGroups() {
  const gEl = document.getElementById("mbx-group");
  if (!gEl) return;
  const col = window._emp.coldataCols.find(c => c.name === gEl.value);
  const vals = col ? col.values : [];
  ["mbx-ref", "mbx-test"].forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    el.innerHTML = vals.map(v => `<option value="${v}">${v}</option>`).join("");
  });
  if (vals.length >= 2) document.getElementById("mbx-test").value = vals[1];
}

function updateTxGroups() {
  const gEl = document.getElementById("tx-group");
  if (!gEl) return;
  const col = window._emp.coldataCols.find(c => c.name === gEl.value);
  const vals = col ? col.values : [];
  ["tx-ref", "tx-test"].forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    el.innerHTML = vals.map(v => `<option value="${v}">${v}</option>`).join("");
  });
  if (vals.length >= 2) document.getElementById("tx-test").value = vals[1];
}

// ── IMPORT PAGE ───────────────────────────────────
document.getElementById("import-data-type").addEventListener("change", function() {
  const typ = this.value;
  document.getElementById("tax-options").classList.toggle("hidden", typ !== "tax");
  document.getElementById("import-clinical-kind-wrap")?.classList.toggle("hidden", typ !== "clinical");
  const dataLabel = document.getElementById("import-data-label");
  const metaLabel = document.getElementById("import-meta-label");
  if (dataLabel && metaLabel) {
    if (typ === "clinical") {
      dataLabel.textContent = "Clinical Raw Data";
      metaLabel.textContent = "Clinical Meta Data";
    } else {
      dataLabel.textContent = "Count Matrix";
      metaLabel.textContent = "Metadata";
    }
  }
});

document.getElementById("import-data-file").addEventListener("change", function() {
  const name = this.files[0]?.name || "";
  document.getElementById("data-filename").textContent = name;
  // Auto-fill experiment name from filename
  if (name) {
    const base = name.replace(/\.[^.]+$/, "").replace(/[^A-Za-z0-9_]/g, "_");
    document.getElementById("import-exp-name").value = base || "experiment";
  }
});

document.getElementById("import-meta-file").addEventListener("change", function() {
  document.getElementById("meta-filename").textContent = this.files[0]?.name || "";
});

bindUploadDropZone("drop-data", "import-data-file", "data-filename");
bindUploadDropZone("drop-meta", "import-meta-file", "meta-filename");

document.getElementById("btn-inspector-refresh")?.addEventListener("click", loadInspector);
document.getElementById("btn-inspector-assay-prev")?.addEventListener("click", async () => {
  const st = window._emp.inspector;
  st.assayOffset = Math.max(1, st.assayOffset - st.assayLimit);
  await loadInspectorAssay();
});
document.getElementById("btn-inspector-assay-next")?.addEventListener("click", async () => {
  const st = window._emp.inspector;
  if (st.assayOffset + st.assayLimit <= st.assayTotal) st.assayOffset += st.assayLimit;
  await loadInspectorAssay();
});
document.getElementById("btn-inspector-rowdata-prev")?.addEventListener("click", async () => {
  const st = window._emp.inspector;
  st.rowOffset = Math.max(1, st.rowOffset - st.rowLimit);
  await loadInspectorRowdata();
});
document.getElementById("btn-inspector-rowdata-next")?.addEventListener("click", async () => {
  const st = window._emp.inspector;
  if (st.rowOffset + st.rowLimit <= st.rowTotal) st.rowOffset += st.rowLimit;
  await loadInspectorRowdata();
});
document.getElementById("btn-inspector-load-result")?.addEventListener("click", async () => {
  const exp = window._emp.currentExp;
  if (!exp) return;
  const resultName = document.getElementById("inspector-result-select")?.value || "";
  if (!resultName) { toast("No result table available.", "info"); return; }
  setLoading(true);
  try {
    const res = await withBusy(`Load ${resultName}`,
      () => API.inspectResult(exp, resultName));
    showResultTable("inspector-result-table", res.rows);
  } catch (e) {
    toast(`Load result failed: ${e.message}`, "error");
  } finally {
    setLoading(false);
  }
});

document.getElementById("btn-clear-session")?.addEventListener("click", async () => {
  setLoading(true);
  try {
    await API.deleteSession();
    window._emp.experiments = [];
    window._emp.currentExp = null;
    window._emp.standaloneClinical = null;
    window._emp.coldataCols = [];
    window._emp.features = [];
    document.getElementById("exp-cards").innerHTML = "";
    document.getElementById("global-experiment").innerHTML = "";
    document.getElementById("summary-stats").innerHTML = "";
    document.getElementById("summary-coldata").innerHTML = "";
    document.getElementById("summary-features").innerHTML = "";
    document.getElementById("exp-selector-wrap").classList.add("hidden");
    document.getElementById("import-experiments").classList.add("hidden");
    document.getElementById("session-badge").classList.add("hidden");
    clearAlert("import-result");
    toast("Loaded data cleared. You can import new files now.", "success");
  } catch (e) {
    toast(`Clear session failed: ${e.message}`, "error");
  } finally {
    setLoading(false);
  }
});

document.getElementById("btn-import").addEventListener("click", async () => {
  const dataFile = document.getElementById("import-data-file").files[0];
  if (!dataFile) { toast("Please select a data file.", "error"); return; }

  const fd = new FormData();
  const dtUI = document.getElementById("import-data-type").value;
  const dt = dtUI === "clinical"
    ? (document.getElementById("import-clinical-kind")?.value || "clinical_raw")
    : dtUI;
  fd.append("data_file",       dataFile);
  fd.append("experiment_name", document.getElementById("import-exp-name").value);
  fd.append("data_type",       dt);
  fd.append("assay_name",      document.getElementById("import-assay-name").value);
  fd.append("start_level",     document.getElementById("import-start-level").value);
  fd.append("tax_sep",         document.getElementById("import-tax-sep").value);

  const metaFile = document.getElementById("import-meta-file").files[0];
  if (metaFile) fd.append("metadata_file", metaFile);

  setLoading(true);
  try {
    if (!localStorage.getItem("emp_session_id")) await API.createSession();
    const res = await withBusy("Importing data", () => API.importData(fd));
    if (res.import_mode === "clinical_merge" || res.import_mode === "clinical_standalone") {
      const modeMsg = res.import_mode === "clinical_standalone"
        ? "No direct sample-ID overlap found; saved as session-level clinical table."
        : `Merged into ${res.updated_experiments} experiment(s).`;
      const orientMsg = res.orientation
        ? ` Detected orientation: ${res.orientation}.`
        : "";
      showAlert("import-result",
        `✓ Clinical/phenotype upload done. ${modeMsg}${orientMsg} Columns: ${(res.columns || []).join(", ")}.`,
        "success");
      toast("Clinical metadata uploaded successfully.", "success");
      if (res.import_mode === "clinical_standalone") {
        window._emp.standaloneClinical = {
          columns: res.columns || [],
          orientation: res.orientation || "samples in rows",
        };
      } else {
        window._emp.standaloneClinical = null;
      }
    } else {
      showAlert("import-result",
        `✓ Imported "${res.experiment_name}": ${res.samples} samples, ${res.features} features.`,
        "success");
      toast(`${res.experiment_name} imported successfully!`, "success");
      window._emp.standaloneClinical = null;
    }
    await refreshExperimentList();
  } catch(e) {
    showAlert("import-result", `Error: ${e.message}`, "error");
    toast(e.message, "error");
  } finally {
    setLoading(false);
  }
});

// ── SUMMARY PAGE ──────────────────────────────────
async function loadSummary() {
  const exp = window._emp.currentExp;
  const statsEl = document.getElementById("summary-stats");
  const colEl = document.getElementById("summary-coldata");
  const featEl = document.getElementById("summary-features");
  if (!exp) {
    // Fallback for clinical-only sessions (no omics experiment in MAE list)
    let sc = window._emp.standaloneClinical;
    if (!sc) {
      try {
        const sv = await API.clinicalVarsStandalone();
        const rows = Array.isArray(sv?.data) ? sv.data : [];
        if (rows.length) {
          sc = { columns: rows.map(r => r.name), orientation: "samples in rows" };
          window._emp.standaloneClinical = sc;
        }
      } catch (_) {}
    }
    if (sc) {
      setLoading(true);
      try {
        const res = await API.clinicalVarsStandalone();
        const rows = Array.isArray(res.data) ? res.data : [];
        const num = rows.filter(r => r.type === "numeric").length;
        const cat = rows.filter(r => r.type === "categorical").length;
        if (statsEl) {
          statsEl.innerHTML = `
            <div class="stat-box"><div class="stat-val">${rows.length}</div><div class="stat-lbl">Clinical Variables</div></div>
            <div class="stat-box"><div class="stat-val">${num}</div><div class="stat-lbl">Numeric</div></div>
            <div class="stat-box"><div class="stat-val">${cat}</div><div class="stat-lbl">Categorical</div></div>
            <div class="stat-box"><div class="stat-val">${window._emp.standaloneClinical.orientation || "samples in rows"}</div><div class="stat-lbl">Orientation</div></div>
          `;
        }
        if (colEl) {
          colEl.innerHTML = `
            <thead><tr><th>name</th><th>type</th><th>n_samples</th><th>n_unique</th></tr></thead>
            <tbody>${rows.map(r => `<tr><td>${r.name ?? ""}</td><td>${r.type ?? ""}</td><td>${r.n_samples ?? ""}</td><td>${r.n_unique ?? ""}</td></tr>`).join("")}</tbody>
          `;
        }
        if (featEl) featEl.innerHTML = "<span class='hint'>Clinical-only session: no assay feature list.</span>";
      } catch (e) {
        if (statsEl) statsEl.innerHTML = "<div class='hint'>Clinical-only session loaded, but variable summary failed.</div>";
      } finally {
        setLoading(false);
      }
      return;
    }
    if (statsEl) statsEl.innerHTML = "<div class='hint'>No loaded experiment. Import data first.</div>";
    if (colEl) colEl.innerHTML = "";
    if (featEl) featEl.innerHTML = "<span class='hint'>No feature names available.</span>";
    return;
  }
  setLoading(true);
  try {
    const s = await API.getSummary(exp);
    document.getElementById("summary-stats").innerHTML = `
      <div class="stat-box"><div class="stat-val">${s.n_samples}</div><div class="stat-lbl">Samples</div></div>
      <div class="stat-box"><div class="stat-val">${s.n_features}</div><div class="stat-lbl">Features</div></div>
      <div class="stat-box"><div class="stat-val">${s.coldata_cols.length}</div><div class="stat-lbl">Metadata Cols</div></div>
      <div class="stat-box"><div class="stat-val">${s.assay_name}</div><div class="stat-lbl">Assay</div></div>
    `;

    // Coldata table
    if (s.coldata && s.coldata.length) {
      const cols = ["sample", ...s.coldata_cols];
      const tbl  = document.getElementById("summary-coldata");
      tbl.innerHTML = `
        <thead><tr>${cols.map(c=>`<th>${c}</th>`).join("")}</tr></thead>
        <tbody>${s.coldata.map(row =>
          `<tr>${cols.map(c => `<td>${row[c] ?? ""}</td>`).join("")}</tr>`
        ).join("")}</tbody>
      `;
    }

    // Feature tags
    const featureNames = toStringArray(s.feature_names);
    document.getElementById("summary-features").innerHTML = featureNames.length
      ? featureNames.map((f) => `<span class="tag">${escapeHtml(f)}</span>`).join("")
      : "<span class='hint'>No feature names available.</span>";
  } catch(e) {
    toast(`Summary error: ${e.message}`, "error");
  } finally {
    setLoading(false);
  }
}

async function loadInspector() {
  const exp = window._emp.currentExp;
  const statsEl = document.getElementById("inspector-stats");
  if (!exp) {
    let sc = window._emp.standaloneClinical;
    if (!sc) {
      try {
        const sv = await API.clinicalVarsStandalone();
        const rows = Array.isArray(sv?.data) ? sv.data : [];
        if (rows.length) {
          sc = { columns: rows.map(r => r.name), orientation: "samples in rows" };
          window._emp.standaloneClinical = sc;
        }
      } catch (_) {}
    }
    if (sc) {
      try {
        const res = await API.clinicalVarsStandalone();
        const rows = Array.isArray(res.data) ? res.data : [];
        const num = rows.filter(r => r.type === "numeric").length;
        if (statsEl) {
          statsEl.innerHTML = `
            <div class="stat-box"><div class="stat-val">clinical-only</div><div class="stat-lbl">Session Type</div></div>
            <div class="stat-box"><div class="stat-val">${rows.length}</div><div class="stat-lbl">Variables</div></div>
            <div class="stat-box"><div class="stat-val">${num}</div><div class="stat-lbl">Numeric Vars</div></div>
            <div class="stat-box"><div class="stat-val">N/A</div><div class="stat-lbl">Assay</div></div>
          `;
        }
        showResultTable("inspector-assay-table", [{ note: "No assay matrix in clinical-only session." }]);
        showResultTable("inspector-coldata-table", rows);
        showResultTable("inspector-rowdata-table", [{ note: "No rowData in clinical-only session." }]);
        const ap = document.getElementById("inspector-assay-page");
        const rp = document.getElementById("inspector-rowdata-page");
        if (ap) ap.textContent = "Rows 0-0 / 0";
        if (rp) rp.textContent = "Rows 0-0 / 0";
      } catch (_) {
        if (statsEl) statsEl.innerHTML = "<div class='hint'>Clinical-only session loaded.</div>";
        showResultTable("inspector-assay-table", [{ note: "No assay matrix available." }]);
        showResultTable("inspector-coldata-table", [{ note: "No colData available." }]);
        showResultTable("inspector-rowdata-table", [{ note: "No rowData available." }]);
      }
      return;
    }
    if (statsEl) statsEl.innerHTML = "<div class='hint'>No loaded experiment. Import data first.</div>";
    showResultTable("inspector-assay-table", [{ note: "No experiment selected." }]);
    showResultTable("inspector-coldata-table", [{ note: "No experiment selected." }]);
    showResultTable("inspector-rowdata-table", [{ note: "No experiment selected." }]);
    return;
  }
  setLoading(true);
  try {
    const overview = await API.inspectOverview(exp);
    const s = overview.summary || {};
    document.getElementById("inspector-stats").innerHTML = `
      <div class="stat-box"><div class="stat-val">${s.n_samples ?? 0}</div><div class="stat-lbl">Samples</div></div>
      <div class="stat-box"><div class="stat-val">${s.n_features ?? 0}</div><div class="stat-lbl">Features</div></div>
      <div class="stat-box"><div class="stat-val">${s.n_coldata_cols ?? 0}</div><div class="stat-lbl">colData Cols</div></div>
      <div class="stat-box"><div class="stat-val">${s.n_rowdata_cols ?? 0}</div><div class="stat-lbl">rowData Cols</div></div>
    `;
    await loadInspectorAssay();
    await loadInspectorColdata();
    await loadInspectorRowdata();
    await loadInspectorResultList();
  } catch (e) {
    toast(`Inspector error: ${e.message}`, "error");
  } finally {
    setLoading(false);
  }
}

async function loadInspectorAssay() {
  const exp = window._emp.currentExp;
  if (!exp) return;
  try {
    const st = window._emp.inspector;
    const res = await API.inspectAssay(exp, st.assayOffset, st.assayLimit);
    st.assayTotal = res.total || 0;
    showResultTable("inspector-assay-table", res.rows);
    const from = st.assayTotal ? st.assayOffset : 0;
    const to = Math.min(st.assayOffset + st.assayLimit - 1, st.assayTotal);
    document.getElementById("inspector-assay-page").textContent = `Rows ${from}-${to} / ${st.assayTotal}`;
  } catch (e) {
    showResultTable("inspector-assay-table", [{ error: e.message }]);
    const ap = document.getElementById("inspector-assay-page");
    if (ap) ap.textContent = "Rows 0-0 / 0";
  }
}

async function loadInspectorColdata() {
  const exp = window._emp.currentExp;
  if (!exp) return;
  const res = await API.inspectColdata(exp);
  showResultTable("inspector-coldata-table", res.rows);
}

async function loadInspectorRowdata() {
  const exp = window._emp.currentExp;
  if (!exp) return;
  try {
    const st = window._emp.inspector;
    const res = await API.inspectRowdata(exp, st.rowOffset, st.rowLimit);
    st.rowTotal = res.total || 0;
    showResultTable("inspector-rowdata-table", res.rows);
    const from = st.rowTotal ? st.rowOffset : 0;
    const to = Math.min(st.rowOffset + st.rowLimit - 1, st.rowTotal);
    document.getElementById("inspector-rowdata-page").textContent = `Rows ${from}-${to} / ${st.rowTotal}`;
  } catch (e) {
    showResultTable("inspector-rowdata-table", [{ error: e.message }]);
    const rp = document.getElementById("inspector-rowdata-page");
    if (rp) rp.textContent = "Rows 0-0 / 0";
  }
}

async function loadInspectorResultList() {
  const exp = window._emp.currentExp;
  if (!exp) return;
  const res = await API.inspectResults(exp);
  const sel = document.getElementById("inspector-result-select");
  const items = res.results || [];
  sel.innerHTML = items.length
    ? items.map((r) => `<option value="${escapeHtml(r)}">${escapeHtml(r)}</option>`).join("")
    : `<option value="">(no EMP result found)</option>`;
}

// ── PREPARATION PAGE ──────────────────────────────
async function prepAction(btnId, alertId, fn) {
  const btnEl = document.getElementById(btnId);
  if (!btnEl) return;
  btnEl.addEventListener("click", async () => {
    const exp = window._emp.currentExp;
    if (!exp) { toast("Import data first.", "error"); return; }
    const label = btnEl.textContent.trim().replace(/\s+/g, " ") || "Preparation";
    setLoading(true);
    clearAlert(alertId);
    try {
      const res = await withBusy(label, () => fn(exp));
      const summary = { ...res };
      delete summary.preview_data;
      showAlert(alertId, `✓ Done. ${JSON.stringify(summary)}`, "success");
      showResultTable("prep-preview", res?.preview_data ?? null, 30);
      document.getElementById("prep-preview")?.scrollIntoView({ behavior: "smooth", block: "nearest" });
      refreshPrepareSnapshots();
      toast("Preparation step completed.", "success");
    } catch(e) {
      showAlert(alertId, `Error: ${e.message}`, "error");
    } finally { setLoading(false); }
  });
}

function currentPrepareMode() {
  return document.getElementById("prep-mode")?.value || "stack";
}

document.getElementById("btn-prep-recommended")?.addEventListener("click", () => {
  const omics = document.getElementById("omics-pipeline")?.value;
  if (!window._emp.currentExp && omics !== "clinical") {
    toast(t("toast.importFirst"), "error");
    return;
  }
  applyOmicsDefaults(omics);
});

window.addEventListener("emp:apply-omics-defaults", (e) => {
  applyOmicsDefaults(e.detail?.omics, { silent: !!e.detail?.silent });
});

prepAction("btn-filter", "filter-result", exp => API.filterData(exp, {
  min_count:   +document.getElementById("filter-min-count").value,
  min_detect_rate: +document.getElementById("filter-min-detect-rate").value,
  max_detect_rate: +document.getElementById("filter-max-detect-rate").value,
  min_prevalence: +document.getElementById("filter-min-prevalence").value,
  max_na:      +document.getElementById("filter-max-na").value,
  prepare_mode: currentPrepareMode(),
}));

prepAction("btn-normalize", "normalize-result", exp =>
  API.normalizeData(exp, {
    method: document.getElementById("norm-method").value,
    prepare_mode: currentPrepareMode(),
  }));
document.getElementById("btn-normalize-export-assay")?.addEventListener("click", () => {
  const exp = window._emp.currentExp;
  if (!exp) { toast("Import data first.", "error"); return; }
  const a = document.createElement("a");
  a.href = API.exportAssayURL(exp);
  a.download = `${exp}_normalized_assay.csv`;
  a.click();
});

prepAction("btn-impute", "impute-result", exp =>
  API.imputeData(exp, {
    method: document.getElementById("impute-method").value,
    prepare_mode: currentPrepareMode(),
  }));

(() => {
  const normDesc = document.getElementById("norm-method-desc");
  const normSel = document.getElementById("norm-method");
  const imputeDesc = document.getElementById("impute-method-desc");
  const imputeSel = document.getElementById("impute-method");
  const normMap = {
    rclr: "rclr: robust log-ratio for sparse microbiome matrices (recommended default).",
    clr: "clr: centered log-ratio for compositional data; sensitive to zeros.",
    hellinger: "Hellinger: square-root transformed relative abundances; good for ecological distance analyses.",
    total: "Relative Abundance: converts each sample to proportions (simple and interpretable).",
    log: "Log Transform: compresses dynamic range for count/intensity-like data.",
    CSS: "CSS: cumulative sum scaling for uneven sequencing depth."
  };
  const imputeMap = {
    knn: "KNN: borrows information from similar samples; preferred when missingness is moderate.",
    zero: "Replace with Zero: conservative for presence/absence style interpretations.",
    min: "Minimum Value: left-censor style fill for low-abundance signals.",
    mean: "Mean: quick baseline fill; less robust for skewed omics data."
  };
  const render = () => {
    if (normDesc && normSel) normDesc.textContent = normMap[normSel.value] || "";
    if (imputeDesc && imputeSel) imputeDesc.textContent = imputeMap[imputeSel.value] || "";
  };
  normSel?.addEventListener("change", render);
  imputeSel?.addEventListener("change", render);
  render();
})();

prepAction("btn-rarefy", "rarefy-result", exp =>
  API.rarefyData(exp, {
    sample_size: +document.getElementById("rarefy-size").value,
    prepare_mode: currentPrepareMode(),
  }));

prepAction("btn-collapse", "collapse-result", exp =>
  API.collapseData(exp, {
    taxa_level: document.getElementById("collapse-level").value,
    prepare_mode: currentPrepareMode(),
  }));

document.getElementById("m16s-btn-profile").addEventListener("click", async () => {
  const exp = window._emp.currentExp;
  if (!exp) { toast("Import data first.", "error"); return; }
  setLoading(true);
  clearAlert("m16s-profile-result");
  try {
    const res = await withBusy("16S taxonomy profile",
      () => API.m16sProfile(exp, {
        tax_sep: document.getElementById("m16s-tax-sep").value || ";"
      }));
    const p = res.profile || {};
    showAlert(
      "m16s-profile-result",
      `Taxonomy profiled: ${p.n_features ?? 0} taxa, ${p.n_samples ?? 0} samples, max depth ${p.max_taxonomy_depth ?? "NA"}.`,
      "success"
    );
  } catch (e) {
    showAlert("m16s-profile-result", `Error: ${e.message}`, "error");
  } finally {
    setLoading(false);
  }
});

prepAction("m16s-btn-prepare-taxonomy", "m16s-prepare-result", exp =>
  ensureWorkflowReady("microbiome_16s", exp, { alertId: "m16s-prepare-result", params: { tax_sep: document.getElementById("m16s-tax-sep").value || ";" } })
    .then(() => API.m16sPrepareTaxonomy(exp, {
      collapse_level: document.getElementById("m16s-collapse-level").value,
      tax_sep: document.getElementById("m16s-tax-sep").value || ";",
      min_total_abundance: +document.getElementById("m16s-min-total-abundance").value,
      keep_top_n: +document.getElementById("m16s-keep-topn").value,
      drop_unassigned: document.getElementById("m16s-drop-unassigned").value === "true",
      normalize_method: document.getElementById("m16s-normalize-method").value || "none",
      prepare_mode: currentPrepareMode(),
    })));

async function refreshPrepareSnapshots() {
  const exp = window._emp.currentExp;
  const sel = document.getElementById("prep-snapshot-select");
  const anaSel = document.getElementById("ana-snapshot-select");
  const vizSel = document.getElementById("viz-snapshot-select");
  if (!exp || !sel) return;
  try {
    const res = await API.listPrepareSnapshots(exp);
    const snaps = Array.isArray(res.snapshots) ? res.snapshots : [];
    const html = snaps.length
      ? snaps.map((s) => `<option value="${s.snapshot_id}">${s.snapshot_id} (${s.mtime})</option>`).join("")
      : `<option value="">(no snapshots)</option>`;
    sel.innerHTML = html;
    if (anaSel) anaSel.innerHTML = `<option value="">(current active)</option>${html}`;
    if (vizSel) vizSel.innerHTML = `<option value="">(current active)</option>${html}`;
  } catch (_) {
    sel.innerHTML = `<option value="">(snapshot unavailable)</option>`;
    if (anaSel) anaSel.innerHTML = `<option value="">(snapshot unavailable)</option>`;
    if (vizSel) vizSel.innerHTML = `<option value="">(snapshot unavailable)</option>`;
  }
}
document.getElementById("btn-prep-refresh-snapshots")?.addEventListener("click", refreshPrepareSnapshots);
document.getElementById("btn-prep-use-snapshot")?.addEventListener("click", async () => {
  const exp = window._emp.currentExp;
  const sid = document.getElementById("prep-snapshot-select")?.value;
  if (!exp || !sid) return;
  try {
    await API.usePrepareSnapshot(exp, sid);
    toast(`Activated snapshot: ${sid}`, "success");
  } catch (e) {
    toast(`Use snapshot failed: ${e.message}`, "error");
  }
});

document.getElementById("btn-cross-omics-cor")?.addEventListener("click", async () => {
  const expA = document.getElementById("cross-exp-a")?.value;
  const expB = document.getElementById("cross-exp-b")?.value;
  const out = document.getElementById("cross-omics-result");
  if (!expA || !expB) return;
  setLoading(true);
  out.classList.remove("hidden");
  out.innerHTML = '<p style="padding:12px">Running cross-omics correlation...</p>';
  try {
    await ensurePageSnapshot("analysis");
    const rA = await API.analyzeCorrelation(expA, "spearman");
    const rB = await API.analyzeCorrelation(expB, "spearman");
    out.innerHTML = `
      <div class="alert alert-info">Cross-omics precompute done for <strong>${expA}</strong> and <strong>${expB}</strong>.</div>
      <div class="hint">Use Correlation/Clinical modules to continue joint interpretation. Preview below is from Omics A.</div>
    `;
    const box = document.createElement("div");
    box.id = "cross-omics-table-a";
    box.className = "result-area";
    out.appendChild(box);
    showResultTable("cross-omics-table-a", rA.data, 100);
    void rB;
  } catch (e) {
    out.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${e.message}</p>`;
  } finally {
    setLoading(false);
  }
});

document.getElementById("btn-cross-omics-clin")?.addEventListener("click", async () => {
  const expA = document.getElementById("cross-exp-a")?.value;
  const expB = document.getElementById("cross-exp-b")?.value;
  const expC = document.getElementById("cross-exp-c")?.value || "";
  const out = document.getElementById("cross-omics-result");
  if (!expA || !expB) return;
  setLoading(true);
  out.classList.remove("hidden");
  out.innerHTML = '<p style="padding:12px">Preparing omics-clinical association...</p>';
  try {
    await ensurePageSnapshot("analysis");
    await refreshClinicalVars();
    const source = (document.getElementById("clin-data-source")?.value || (expC ? "standalone" : "experiment"));
    const numTraits = (_clinVarCache || []).filter(r => r.type === "numeric").map(r => r.name).slice(0, 3);
    const r = await API.clinicalMultiomicsJoint({
      exp_a: expA,
      exp_b: expB,
      traits: numTraits,
      method: "spearman",
      top_n: 20,
      clinical_source: source,
    });
    const clinMsg = expC ? `clinical table: <strong>${expC}</strong>` : `clinical source: <strong>${source}</strong>`;
    out.innerHTML = `
      <div class="alert alert-info">
        Multi-omics clinical joint analysis done: <strong>${expA}</strong> + <strong>${expB}</strong>, ${clinMsg}.<br>
        Top features: A=${r.n_top_a || 0}, B=${r.n_top_b || 0}, edges=${r.n_edges || 0}.
      </div>`;
    const aBox = document.createElement("div");
    aBox.id = "cross-omics-clin-a";
    aBox.className = "result-area";
    out.appendChild(aBox);
    showResultTable("cross-omics-clin-a", r.top_a, 200);
    const bBox = document.createElement("div");
    bBox.id = "cross-omics-clin-b";
    bBox.className = "result-area";
    out.appendChild(bBox);
    showResultTable("cross-omics-clin-b", r.top_b, 200);
    const eBox = document.createElement("div");
    eBox.id = "cross-omics-clin-edges";
    eBox.className = "result-area";
    out.appendChild(eBox);
    showResultTable("cross-omics-clin-edges", r.edges, 300);
  } catch (e) {
    out.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${e.message}</p>`;
  } finally {
    setLoading(false);
  }
});

async function ensurePageSnapshot(which) {
  const exp = window._emp.currentExp;
  if (!exp) return;
  const id = which === "analysis"
    ? (document.getElementById("ana-snapshot-select")?.value || "")
    : (document.getElementById("viz-snapshot-select")?.value || "");
  if (!id) return;
  await API.usePrepareSnapshot(exp, id);
}

// ── ANALYSIS PAGE ─────────────────────────────────
async function runAnalysis(btnId, resultId, apiFn) {
  const btnEl = document.getElementById(btnId);
  if (!btnEl) return;
  btnEl.addEventListener("click", async () => {
    const exp = window._emp.currentExp;
    if (!exp) { toast("Import data first.", "error"); return; }
    const label = btnEl.textContent.trim().replace(/\s+/g, " ") || "Analysis";
    setLoading(true);
    const resultEl = document.getElementById(resultId);
    resultEl.innerHTML = '<p style="padding:12px">Running analysis…</p>';
    resultEl.classList.remove("hidden");
    try {
      await ensurePageSnapshot("analysis");
      const res = await withBusy(label, () => apiFn(exp));
      showResultTable(resultId, res.data);
      toast("Analysis complete.", "success");
    } catch(e) {
      resultEl.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${e.message}</p>`;
      toast(e.message, "error");
    } finally { setLoading(false); }
  });
}

runAnalysis("btn-alpha", "alpha-result", exp =>
  API.analyzeAlpha(
    exp,
    document.getElementById("alpha-method").value,
    document.getElementById("alpha-source")?.value || "current"
  ));

function updateDiffProgress(pct, msg) {
  const wrap = document.getElementById("diff-progress");
  const bar  = document.getElementById("diff-progress-bar");
  const m    = document.getElementById("diff-progress-msg");
  if (!wrap || !bar || !m) return;
  wrap.classList.remove("hidden");
  const p = Math.max(0, Math.min(100, Math.round(pct ?? 0)));
  bar.style.setProperty("--pct", `${p}%`);
  m.textContent = `${p}% ${msg || ""}`;
}

function hideDiffProgress() {
  document.getElementById("diff-progress")?.classList.add("hidden");
}

document.getElementById("btn-diff").addEventListener("click", async () => {
  const exp = window._emp.currentExp;
  if (!exp) { toast("Import data first.", "error"); return; }
  const runMode = document.getElementById("diff-mode")?.value || "async";
  const opts = {
    filter_low:        document.getElementById("diff-filter-low")?.value === "true",
    subset_two_groups: document.getElementById("diff-subset")?.value === "true",
    comparison_mode:   document.getElementById("diff-comparison-mode")?.value || "pairwise",
    cores:             document.getElementById("diff-cores")?.value || "auto",
  };
  const method = document.getElementById("diff-method").value;
  const grp    = document.getElementById("diff-group").value;
  const refG   = document.getElementById("diff-ref").value;
  const testG  = document.getElementById("diff-test").value;
  const cmpMode = opts.comparison_mode;

  const resultEl = document.getElementById("diff-result");
  resultEl.innerHTML = '<p style="padding:12px">Running…</p>';
  resultEl.classList.remove("hidden");
  updateDiffProgress(1, "Submitting");

  setLoading(true);
  const t0 = performance.now();
  try {
    if (runMode === "sync") {
      updateDiffProgress(5, `Mode: ${cmpMode}`);
      const res = await API.analyzeDiff(exp, method, grp, refG, testG, opts);
      updateDiffProgress(100, "Done");
      showResultTable("diff-result", res.data);
      reportLastRun("Differential (sync)", performance.now() - t0, res.backend_ms);
      toast(`Differential done in ${((performance.now()-t0)/1000).toFixed(1)}s`, "success");
    } else {
      updateDiffProgress(3, `Mode: ${cmpMode}`);
      const { job_id } = await API.analyzeDiffAsync(exp, method, grp, refG, testG, opts);
      const { result } = await API.pollJobUntilDone(job_id, (job) => {
        updateDiffProgress(job.progress, job.message);
      });
      updateDiffProgress(100, "Done");
      showResultTable("diff-result", result.data);
      reportLastRun("Differential (async)", performance.now() - t0, result.backend_ms);
      toast(`Differential done in ${((performance.now()-t0)/1000).toFixed(1)}s`, "success");
    }
  } catch(e) {
    resultEl.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${e.message}</p>`;
    updateDiffProgress(100, `Failed: ${e.message}`);
    toast(e.message, "error");
  } finally {
    setLoading(false);
    setTimeout(hideDiffProgress, 1500);
  }
});

runAnalysis("btn-dim", "dim-result", exp =>
  API.analyzeDimension(exp, document.getElementById("dim-method").value));

runAnalysis("btn-cor", "cor-result", exp =>
  API.analyzeCorrelation(exp, document.getElementById("cor-method").value));

runAnalysis("btn-cluster", "cluster-result", exp =>
  API.analyzeCluster(exp,
    document.getElementById("cluster-method").value,
    +document.getElementById("cluster-k").value));

runAnalysis("btn-marker", "marker-result", exp =>
  API.analyzeMarker(exp,
    document.getElementById("marker-method").value,
    document.getElementById("marker-group").value,
    document.getElementById("marker-ref")?.value || "",
    document.getElementById("marker-test")?.value || ""));

// Populate organism dropdown with installed OrgDb states (strike through &
// flag organisms whose Bioconductor package is missing so the user knows
// exactly what to install), and render an inline status badge next to the
// selector telling them whether the current choice is ready to run.
let _ENRICH_SPECIES = [];
function _renderEnrichSpeciesBadge() {
  const sel = document.getElementById("enrich-organism");
  if (!sel) return;
  let badge = document.getElementById("enrich-organism-badge");
  if (!badge) {
    badge = document.createElement("div");
    badge.id = "enrich-organism-badge";
    badge.style.cssText =
      "margin-top:6px;font-size:12px;padding:6px 10px;border-radius:6px;line-height:1.4;";
    sel.parentNode.appendChild(badge);
  }
  const row = _ENRICH_SPECIES.find(r => r.kegg_code === sel.value);
  if (!row) { badge.style.display = "none"; return; }
  if (row.installed) {
    badge.style.display = "block";
    badge.style.background = "#ecfdf5";
    badge.style.color = "#065f46";
    badge.style.border = "1px solid #a7f3d0";
    badge.innerHTML = `OrgDb <code>${row.orgdb}</code> is installed — ready to run.`;
  } else {
    badge.style.display = "block";
    badge.style.background = "#fef3c7";
    badge.style.color = "#92400e";
    badge.style.border = "1px solid #fde68a";
    badge.innerHTML =
      `OrgDb <code>${row.orgdb}</code> for <strong>${row.label}</strong> is NOT installed. ` +
      `<button class="btn" id="btn-install-orgdb" style="margin-left:8px;padding:4px 10px;font-size:12px">` +
      `Install now</button>` +
      `<div style="margin-top:4px;opacity:.75">(runs <code>${row.install_cmd}</code> on the server; can take a few minutes)</div>`;
    const btn = document.getElementById("btn-install-orgdb");
    if (btn) btn.addEventListener("click", () => _installOrgDbInteractive(row));
  }
}

async function _installOrgDbInteractive(row) {
  try {
    const submit = API.installOrgDb(row.orgdb);
    const res = await withGlobalProgress(`Installing ${row.orgdb}`, submit,
                                           { timeoutMs: 1800000 });
    if (res?.installed || res?.success) {
      toast(`${row.orgdb} installed. You can run enrichment now.`, "success");
      await refreshEnrichmentSpecies();
    } else {
      toast(`${row.orgdb} install did not complete. Check server log.`, "error");
    }
  } catch (e) {
    toast(`Install failed: ${e.message}`, "error");
  }
}

async function refreshEnrichmentSpecies() {
  const sel = document.getElementById("enrich-organism");
  if (!sel) return;
  try {
    const { data } = await API.listEnrichmentSpecies();
    if (!Array.isArray(data) || !data.length) return;
    _ENRICH_SPECIES = data;
    const prev = sel.value;
    sel.innerHTML = "";
    for (const row of data) {
      const opt = document.createElement("option");
      opt.value = row.kegg_code;
      const state = row.installed
        ? ""
        : " — needs install";
      opt.textContent = `${row.label} (${row.kegg_code}, ${row.orgdb})${state}`;
      opt.dataset.installed = String(row.installed);
      // Don't fully disable – let users pick & see the exact install command.
      if (!row.installed) opt.style.color = "#9ca3af";
      sel.appendChild(opt);
    }
    const firstInstalled = data.find(r => r.installed)?.kegg_code;
    const keep = data.find(r => r.kegg_code === prev && r.installed);
    sel.value = keep ? prev : (firstInstalled || prev);
    _renderEnrichSpeciesBadge();
    sel.addEventListener("change", _renderEnrichSpeciesBadge);
  } catch (e) {
    console.warn("[enrich] species list unavailable:", e.message);
  }
}
// Modules run after DOMContentLoaded has already fired in many browsers, so
// call the loader immediately (and also on DOMContentLoaded as a safety net).
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", refreshEnrichmentSpecies);
} else {
  refreshEnrichmentSpecies();
}

document.getElementById("btn-enrich").addEventListener("click", async () => {
  const exp = window._emp.currentExp;
  if (!exp) { toast("Import data first.", "error"); return; }
  const tbl  = document.getElementById("enrich-result");
  const info = document.getElementById("enrich-summary");
  const plot = document.getElementById("enrich-plot");
  const db  = document.getElementById("enrich-database").value;
  const org = document.getElementById("enrich-organism").value;
  const t0 = performance.now();
  try {
    const submit = API.analyzeEnrichmentAsync(exp, db, org, {
      fcCutoff:  +document.getElementById("enrich-fc-cutoff").value || 1.0,
      pCutoff:   +document.getElementById("enrich-p-cutoff").value  || 0.05,
      usePadj:   document.getElementById("enrich-use-padj").value === "true",
      direction: document.getElementById("enrich-direction").value,
      topN:      +document.getElementById("enrich-top-n").value || 20,
    });
    const r = await withGlobalProgress(`${db} enrichment (${org})`, submit);
    if (info) {
      info.classList.remove("hidden");
      info.innerHTML = `
        <strong>${r.database}</strong> on <strong>${r.organism}</strong>,
        direction: <code>${r.direction}</code>,
        DEGs: <code>${r.deg_count ?? 0}</code>,
        mapped: <code>${r.mapped_count ?? 0}</code>,
        enriched terms: <code>${r.n_rows ?? 0}</code>.`;
    }
    showResultTable("enrich-result", r.data, 100);
    if (r.plot) {
      plot.classList.remove("hidden");
      plot.innerHTML = `<img src="${r.plot}" alt="${r.database} enrichment"/>`;
    } else {
      plot.classList.add("hidden"); plot.innerHTML = "";
    }
    reportLastRun(`Enrichment ${db}`, performance.now() - t0, r.backend_ms);
  } catch(e) {
    tbl.classList.remove("hidden");
    const isMissingDb = /BiocManager::install|is not installed|not installed|OrgDb package/i.test(e.message || "");
    const cmd = (e.message.match(/BiocManager::install\("[^"]+"\)/) || [""])[0];
    const hint = isMissingDb
      ? `<div style="padding:12px;color:#991b1b">
           <strong>OrgDb package missing for this species.</strong>
           <div style="margin-top:6px">Click <em>Install now</em> on the Organism dropdown above, or run in R on the server:<br>
             <code>${cmd || 'BiocManager::install("...")'}</code>
           </div>
         </div>`
      : `<p style="padding:12px;color:#991b1b">Error: ${e.message}</p>`;
    tbl.innerHTML = hint;
    // Re-read species list in case the user just triggered Install now from
    // a previous attempt – avoids showing a stale "not installed" badge.
    refreshEnrichmentSpecies();
    toast(e.message, "error");
  }
});

document.getElementById("btn-network").addEventListener("click", async () => {
  const exp = window._emp.currentExp;
  if (!exp) { toast("Import data first.", "error"); return; }
  setLoading(true);
  const el = document.getElementById("network-result");
  try {
    await withBusy("Network analysis", () => API.analyzeNetwork(exp,
      document.getElementById("network-method").value,
      +document.getElementById("network-cutoff").value));
    el.innerHTML = '<p style="padding:12px;color:#166534">✓ Network analysis completed. Visualize in the Visualization page.</p>';
    el.classList.remove("hidden");
    toast("Network analysis complete.", "success");
  } catch(e) {
    el.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${e.message}</p>`;
    el.classList.remove("hidden");
    toast(e.message, "error");
  } finally { setLoading(false); }
});

document.getElementById("mgx-btn-profile").addEventListener("click", async () => {
  const exp = window._emp.currentExp;
  if (!exp) { toast("Import data first.", "error"); return; }
  setLoading(true);
  clearAlert("mgx-profile-result");
  try {
    const res = await withBusy("Metagenomics profile",
      () => API.mgxProfile(exp, { id_type: document.getElementById("mgx-id-type").value }));
    const p = res.profile || {};
    showAlert(
      "mgx-profile-result",
      `✓ ID type: ${p.id_type_effective || "unknown"} (inferred: ${p.id_type_inferred || "unknown"}), ${p.n_features || 0} features, ${p.n_samples || 0} samples.`,
      "success"
    );
  } catch (e) {
    showAlert("mgx-profile-result", `Error: ${e.message}`, "error");
    toast(e.message, "error");
  } finally { setLoading(false); }
});

document.getElementById("tx-btn-profile")?.addEventListener("click", async () => {
  const exp = window._emp.currentExp;
  if (!exp) { toast("Import data first.", "error"); return; }
  setLoading(true);
  clearAlert("tx-profile-result");
  try {
    const res = await withBusy("Transcriptomics profile",
      () => API.txProfile(exp, { assay_hint: "counts" }));
    const p = res.profile || {};
    showAlert(
      "tx-profile-result",
      `✓ Transcriptomics profile: ${p.n_features || 0} features, ${p.n_samples || 0} samples.`,
      "success"
    );
  } catch (e) {
    showAlert("tx-profile-result", `Error: ${e.message}`, "error");
    toast(e.message, "error");
  } finally { setLoading(false); }
});

runAnalysis("tx-btn-diff", "tx-analysis-result", exp =>
  ensureWorkflowReady("transcriptomics", exp, { alertId: "tx-profile-result" })
    .then(() => API.txAnalyzeDifferential(exp, {
      method: document.getElementById("tx-diff-method").value,
      group_var: document.getElementById("tx-group").value || null,
      ref_group: document.getElementById("tx-ref").value || null,
      test_group: document.getElementById("tx-test").value || null
    })));

runAnalysis("tx-btn-gsea", "tx-analysis-result", exp =>
  ensureWorkflowReady("transcriptomics", exp, { alertId: "tx-profile-result" })
    .then(() => API.txAnalyzeGsea(exp, {
      database: document.getElementById("tx-gsea-db").value,
      organism: document.getElementById("tx-gsea-org").value || "hsa"
    })));

runAnalysis("tx-btn-wgcna", "tx-analysis-result", exp =>
  ensureWorkflowReady("transcriptomics", exp, { alertId: "tx-profile-result" })
    .then(() => API.txAnalyzeWgcna(exp, {
      method: document.getElementById("tx-wgcna-method").value,
      cutoff: +document.getElementById("tx-wgcna-cutoff").value
    })));

prepAction("mgx-btn-preprocess", "mgx-profile-result", exp =>
  ensureWorkflowReady("metagenomics", exp, {
    alertId: "mgx-profile-result",
    params: { id_type: document.getElementById("mgx-id-type").value }
  }).then(() => API.mgxPreprocess(exp, {
    max_na: +document.getElementById("mgx-max-na").value,
    normalize_method: document.getElementById("mgx-normalize-method").value || "rclr"
  })));

runAnalysis("mgx-btn-diff", "mgx-diff-result", exp =>
  ensureWorkflowReady("metagenomics", exp, {
    alertId: "mgx-profile-result",
    params: { id_type: document.getElementById("mgx-id-type").value }
  }).then(() => API.mgxAnalyzeDifferential(exp, {
    id_type: document.getElementById("mgx-id-type").value,
    method: document.getElementById("mgx-diff-method").value,
    group_var: document.getElementById("mgx-group").value || null,
    ref_group: document.getElementById("mgx-ref").value || null,
    test_group: document.getElementById("mgx-test").value || null
  })));

runAnalysis("mgx-btn-enrich", "mgx-enrich-result", exp =>
  ensureWorkflowReady("metagenomics", exp, {
    alertId: "mgx-profile-result",
    params: { id_type: document.getElementById("mgx-id-type").value }
  }).then(() => API.mgxAnalyzeEnrichment(exp, {
    id_type: document.getElementById("mgx-id-type").value,
    database: document.getElementById("mgx-database").value || null
  })));

// ── VISUALIZATION PAGE ────────────────────────────
// Barplot mode toggle
document.getElementById("bar-mode").addEventListener("change", function() {
  document.getElementById("bar-topn-wrap").classList.toggle("hidden", this.value === "single");
  document.getElementById("bar-feature-wrap").classList.toggle("hidden", this.value !== "single");
});

async function genPlot(btnId, outId, apiFn, { metaId } = {}) {
  const btnEl = document.getElementById(btnId);
  if (!btnEl) return;
  btnEl.addEventListener("click", async () => {
    const exp = window._emp.currentExp;
    if (!exp) { toast("Import data first.", "error"); return; }
    const label = btnEl.textContent.trim().replace(/\s+/g, " ") || "Plot";
    setLoading(true);
    const out = document.getElementById(outId);
    out.innerHTML = '<p style="padding:12px">Generating plot…</p>';
    out.classList.remove("hidden");
    const metaEl = metaId ? document.getElementById(metaId) : null;
    try {
      await ensurePageSnapshot("visualization");
      const res = await withBusy(label, () => apiFn(exp));
      showPlot(outId, res.plot);
      // Custom-heatmap diagnostics: backend returns matched/missing arrays
      // alongside the base64 PNG so we can report which genes actually
      // landed on the heatmap.
      if (metaEl) {
        const nUsed    = Number(res.n_used    ?? (res.matched?.length || 0));
        const nMissing = Number(res.n_missing ?? (res.missing?.length || 0));
        if (nUsed || nMissing) {
          let txt = `Matched ${nUsed} feature${nUsed === 1 ? "" : "s"}`;
          if (nMissing) {
            const preview = (res.missing || []).slice(0, 8).join(", ");
            txt += ` · ${nMissing} not found${preview ? `: ${preview}${nMissing > 8 ? "…" : ""}` : ""}`;
          }
          metaEl.textContent = txt;
        }
      }
      toast("Plot ready.", "success");
    } catch(e) {
      out.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${e.message}</p>`;
      if (metaEl) metaEl.textContent = "";
      toast(e.message, "error");
    } finally { setLoading(false); }
  });
}

// ---------------------------------------------------------------
// Custom-feature-list helpers for heatmap widgets.  A single
// helper wires the textarea + file-upload + clear button so the
// three heatmap panels (general / transcriptomics / metagenomics)
// share one implementation.
// ---------------------------------------------------------------
function _readFeatureFile(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload  = () => resolve(String(reader.result || ""));
    reader.onerror = () => reject(reader.error || new Error("File read failed"));
    reader.readAsText(file);
  });
}

function _parseFeatures(text) {
  if (!text) return [];
  // Split on newline / comma / semicolon / tab / whitespace runs.  When
  // a CSV has a header row we strip lines that look like column headers
  // ("gene", "id", "symbol", "feature") so a normal Excel export "Just
  // Works" without the user editing the file.
  return String(text).split(/[\s,;]+/)
    .map(s => s.trim())
    .filter(Boolean)
    .filter(s => !/^(gene|genes|id|ids|symbol|feature|name)$/i.test(s));
}

function wireCustomFeatureBox({ textareaId, fileId, clearId, metaId }) {
  const ta   = document.getElementById(textareaId);
  const fi   = document.getElementById(fileId);
  const cl   = document.getElementById(clearId);
  const meta = document.getElementById(metaId);
  if (!ta) return () => "";

  function reportCount() {
    const n = _parseFeatures(ta.value).length;
    if (meta) meta.textContent = n ? `Ready: ${n} feature${n === 1 ? "" : "s"}` : "";
  }
  ta?.addEventListener("input", reportCount);
  fi?.addEventListener("change", async () => {
    const f = fi.files?.[0];
    if (!f) return;
    try {
      const text = await _readFeatureFile(f);
      ta.value = text.trim();
      reportCount();
    } catch (e) {
      toast(`Could not read file: ${e.message}`, "error");
    } finally {
      fi.value = "";
    }
  });
  cl?.addEventListener("click", () => {
    ta.value = ""; reportCount();
    if (fi) fi.value = "";
  });
  return () => ta.value.trim(); // getter returns raw text for POSTing
}

function currentColorOptions() {
  const useCustom = document.getElementById("viz-use-custom-colors")?.checked;
  const picks = [1,2,3,4,5,6]
    .map((i) => document.getElementById(`viz-color-${i}`)?.value || "")
    .filter(Boolean);
  return {
    color_panel: document.getElementById("viz-color-panel")?.value || "npg",
    custom_colors: useCustom ? (picks.join(",") || null) : null,
  };
}

genPlot("btn-barplot", "barplot-out", exp => API.vizBarplot(exp, {
  mode:    document.getElementById("bar-mode").value,
  group:   document.getElementById("bar-group").value || null,
  feature: document.getElementById("bar-feature").value || null,
  top_n:   +document.getElementById("bar-topn").value,
  ...currentColorOptions(),
}));

genPlot("btn-boxplot", "boxplot-out", exp => API.vizBoxplot(exp, {
  group:   document.getElementById("box-group").value || null,
  feature: document.getElementById("box-feature").value || null,
  ...currentColorOptions(),
}));

function currentHeatmapSize() {
  const w = +document.getElementById("heat-width")?.value;
  const h = +document.getElementById("heat-height")?.value;
  return {
    width:  Number.isFinite(w) && w > 0 ? w : 11,
    height: Number.isFinite(h) && h > 0 ? h : 8,
  };
}

// "Top-variance" heatmap (classic): always ignores the custom list.
genPlot("btn-heatmap", "heatmap-out", exp => API.vizHeatmap(exp, {
  group: document.getElementById("heat-group").value || null,
  top_n: +document.getElementById("heat-topn").value,
  cluster_rows: document.getElementById("heat-cluster-rows").value === "true",
  cluster_cols: document.getElementById("heat-cluster-cols").value === "true",
  show_gene_names: document.getElementById("heat-show-rn").value === "true",
  font_size: +document.getElementById("heat-font-size").value || 11,
  ...currentHeatmapSize(),
  ...currentColorOptions(),
}), { metaId: "heat-custom-meta" });

// ── Custom-feature-list heatmap (shared viz) ────────────────────
const _getHeatCustom = wireCustomFeatureBox({
  textareaId: "heat-custom",
  fileId:     "heat-custom-file",
  clearId:    "heat-custom-clear",
  metaId:     "heat-custom-meta",
});
genPlot("btn-heatmap-custom", "heatmap-out", exp => {
  const raw = _getHeatCustom();
  if (!_parseFeatures(raw).length) {
    throw new Error("Paste or upload a feature list first.");
  }
  return API.vizHeatmap(exp, {
    group:    document.getElementById("heat-group").value || null,
    top_n:    +document.getElementById("heat-topn").value,
    features: raw, // backend splits + deduplicates
    cluster_rows: document.getElementById("heat-cluster-rows").value === "true",
    cluster_cols: document.getElementById("heat-cluster-cols").value === "true",
    show_gene_names: document.getElementById("heat-show-rn").value === "true",
    font_size: +document.getElementById("heat-font-size").value || 11,
    ...currentHeatmapSize(),
    ...currentColorOptions(),
  });
}, { metaId: "heat-custom-meta" });

// ── Transcriptomics heatmap: textbox optional ───────────────────
const _getTxHeatCustom = wireCustomFeatureBox({
  textareaId: "tx-heat-custom",
  fileId:     "tx-heat-custom-file",
  clearId:    "tx-heat-custom-clear",
  metaId:     "tx-heat-custom-meta",
});

// ── Metagenomics heatmap: textbox optional ──────────────────────
const _getMgxHeatCustom = wireCustomFeatureBox({
  textareaId: "mgx-heat-custom",
  fileId:     "mgx-heat-custom-file",
  clearId:    "mgx-heat-custom-clear",
  metaId:     "mgx-heat-custom-meta",
});

document.getElementById("btn-volcano")?.addEventListener("click", async () => {
  const exp = window._emp.currentExp;
  if (!exp) { toast("Import data first.", "error"); return; }
  const out = document.getElementById("volcano-out");
  const pdfLink = document.getElementById("vol-pdf-link");
  pdfLink?.classList.add("hidden");
  out.innerHTML = '<p style="padding:12px">Generating volcano plot…</p>';
  out.classList.remove("hidden");
  setLoading(true);
  try {
    await ensurePageSnapshot("visualization");
    const res = await withBusy("Volcano plot", () => API.vizVolcano(exp, {
      fc_cutoff: +document.getElementById("vol-fc").value,
      p_cutoff:  +document.getElementById("vol-p").value,
      use_padj:  document.getElementById("vol-use-padj")?.value === "true",
      label_top: +document.getElementById("vol-label-top")?.value || 15,
      ...currentColorOptions(),
    }));
    showPlot("volcano-out", res.plot);
    if (res.pdf_available && pdfLink) {
      const sid = localStorage.getItem("emp_session_id");
      pdfLink.href = `${API.apiBase()}/download/plot/${sid}/${encodeURIComponent(exp)}/volcano.pdf`;
      pdfLink.classList.remove("hidden");
    }
    toast("Volcano plot ready.", "success");
  } catch(e) {
    out.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${e.message}</p>`;
    toast(e.message, "error");
  } finally { setLoading(false); }
});

document.getElementById("btn-deg-heatmap")?.addEventListener("click", async () => {
  const exp = window._emp.currentExp;
  if (!exp) { toast("Import data first.", "error"); return; }
  const out = document.getElementById("deg-heatmap-out");
  const meta = document.getElementById("deg-meta");
  const pdfLink = document.getElementById("deg-pdf-link");
  pdfLink?.classList.add("hidden");
  out.innerHTML = '<p style="padding:12px">Generating DEG heatmap…</p>';
  out.classList.remove("hidden");
  setLoading(true);
  try {
    await ensurePageSnapshot("visualization");
    const res = await withBusy("DEG heatmap", () => API.vizDegHeatmap(exp, {
      group:         document.getElementById("heat-group").value || null,
      fc_cutoff:    +document.getElementById("deg-fc").value,
      p_cutoff:     +document.getElementById("deg-p").value,
      use_padj:      document.getElementById("deg-use-padj").value === "true",
      min_row_sum:  +document.getElementById("deg-min-rowsum").value,
      max_genes:    +document.getElementById("deg-max-genes").value,
      cluster_rows:  document.getElementById("deg-cluster-rows").value === "true",
      cluster_cols:  document.getElementById("deg-cluster-cols").value === "true",
      show_rownames: document.getElementById("deg-show-rn").value === "true",
      font_size:    +document.getElementById("deg-font-size").value || 10,
      ...currentHeatmapSize(),
      ...currentColorOptions(),
    }));
    showPlot("deg-heatmap-out", res.plot);
    if (meta) meta.textContent = res.n_genes ? `${res.n_genes} DEGs plotted` : "";
    if (res.pdf_available && pdfLink) {
      const sid  = localStorage.getItem("emp_session_id");
      pdfLink.href = `${API.apiBase()}/download/plot/${sid}/${encodeURIComponent(exp)}/deg_heatmap.pdf`;
      pdfLink.classList.remove("hidden");
    }
    toast("DEG heatmap ready.", "success");
  } catch(e) {
    out.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${e.message}</p>`;
    toast(e.message, "error");
  } finally { setLoading(false); }
});

genPlot("btn-scatter", "scatter-out", exp => API.vizScatter(exp, {
  group: document.getElementById("scat-group").value || null,
  dim1:  +document.getElementById("scat-dim1").value,
  dim2:  +document.getElementById("scat-dim2").value,
  ordination: document.getElementById("scat-ordination")?.value || "auto",
  ...currentColorOptions(),
}));

genPlot("btn-structure", "structure-out", exp => API.vizStructure(exp, {
  group: document.getElementById("struct-group").value || null,
  top_n: +document.getElementById("struct-topn").value,
  ...currentColorOptions(),
}));

genPlot("btn-alpha-plot", "alpha-plot-out", exp => API.vizAlpha(exp, {
  group:  document.getElementById("aplot-group").value || null,
  metric: document.getElementById("aplot-metric").value,
  source: document.getElementById("aplot-source")?.value || "current",
  ...currentColorOptions(),
}));

genPlot("m16s-btn-sankey", "m16s-sankey-out", exp =>
  ensureWorkflowReady("microbiome_16s", exp, {
    params: { tax_sep: document.getElementById("m16s-sankey-tax-sep").value || ";" }
  }).then(() => API.m16sVizSankey(exp, {
    from_level: document.getElementById("m16s-sankey-from").value,
    to_level: document.getElementById("m16s-sankey-to").value,
    top_n: +document.getElementById("m16s-sankey-topn").value,
    tax_sep: document.getElementById("m16s-sankey-tax-sep").value || ";",
    ...currentColorOptions(),
  }))
);

genPlot("m16s-btn-network", "m16s-network-out", exp =>
  ensureWorkflowReady("microbiome_16s", exp).then(() => API.m16sVizNetwork(exp, {
    method: document.getElementById("m16s-network-method").value,
    cutoff: +document.getElementById("m16s-network-cutoff").value,
    top_n: +document.getElementById("m16s-network-topn").value,
  }))
);

genPlot("mgx-btn-heatmap", "mgx-viz-heatmap-out", exp => {
  const raw = _getMgxHeatCustom();
  return API.mgxVizHeatmap(exp, {
    group:    document.getElementById("mgx-viz-group").value || null,
    top_n:    +document.getElementById("mgx-viz-topn").value,
    features: raw || undefined,  // omit when the textbox is empty
    ...currentColorOptions(),
  });
}, { metaId: "mgx-heat-custom-meta" });

genPlot("mgx-btn-volcano", "mgx-viz-volcano-out", exp => API.mgxVizVolcano(exp, {
  fc_cutoff: +document.getElementById("mgx-viz-fc").value,
  p_cutoff: +document.getElementById("mgx-viz-p").value,
  ...currentColorOptions(),
}));

genPlot("tx-btn-heatmap", "tx-viz-heatmap-out", exp => {
  const raw = _getTxHeatCustom();
  return API.txVizHeatmap(exp, {
    group:    document.getElementById("tx-viz-group").value || null,
    top_n:    +document.getElementById("tx-viz-topn").value,
    features: raw || undefined,  // omit when the textbox is empty
    ...currentColorOptions(),
  });
}, { metaId: "tx-heat-custom-meta" });

genPlot("tx-btn-volcano", "tx-viz-volcano-out", exp => API.txVizVolcano(exp, {
  fc_cutoff: +document.getElementById("tx-viz-fc").value,
  p_cutoff: +document.getElementById("tx-viz-p").value,
  ...currentColorOptions(),
}));

document.getElementById("mbx-btn-profile")?.addEventListener("click", async () => {
  const exp = window._emp.currentExp;
  if (!exp) { toast("Import data first.", "error"); return; }
  setLoading(true);
  clearAlert("mbx-status");
  try {
    const res = await withBusy("Metabolomics profile", () => API.mbxProfile(exp));
    const p = res.profile || {};
    const d = p.defaults || {};
    showAlert(
      "mbx-status",
      `Defaults: max_na=${d.max_na ?? "n/a"}, impute=${d.impute_method ?? "n/a"}, normalize=${d.normalize_method ?? "n/a"}, diff=${d.differential_method ?? "n/a"}. Missingness=${p.raw_missingness ?? "n/a"}.`,
      "success"
    );
  } catch (e) {
    showAlert("mbx-status", `Error: ${e.message}`, "error");
    toast(e.message, "error");
  } finally {
    setLoading(false);
  }
});

document.getElementById("mbx-btn-preprocess")?.addEventListener("click", async () => {
  const exp = window._emp.currentExp;
  if (!exp) { toast("Import data first.", "error"); return; }
  setLoading(true);
  clearAlert("mbx-status");
  try {
    await ensureWorkflowReady("metabolomics", exp, { alertId: "mbx-status" });
    const maxNaRaw = document.getElementById("mbx-max-na").value;
    const res = await withBusy("Metabolomics preprocess",
      () => API.mbxPreprocess(exp, {
        max_na: maxNaRaw === "" ? null : +maxNaRaw,
        impute_method: document.getElementById("mbx-impute-method").value || null,
        normalize_method: document.getElementById("mbx-normalize-method").value || null
      }));
    const r = res.result || {};
    showAlert(
      "mbx-status",
      `Preprocess done: kept=${r.kept_features ?? "n/a"}, max_na=${r.max_na ?? "auto"}, impute=${r.impute_method ?? "auto"}, normalize=${r.normalize_method ?? "auto"}.`,
      "success"
    );
  } catch (e) {
    showAlert("mbx-status", `Error: ${e.message}`, "error");
    toast(e.message, "error");
  } finally {
    setLoading(false);
  }
});

document.getElementById("mbx-btn-diff")?.addEventListener("click", async () => {
  const exp = window._emp.currentExp;
  if (!exp) { toast("Import data first.", "error"); return; }
  setLoading(true);
  const out = document.getElementById("mbx-diff-result");
  out.innerHTML = '<p style="padding:12px">Running metabolomics differential...</p>';
  out.classList.remove("hidden");
  try {
    await ensureWorkflowReady("metabolomics", exp, { alertId: "mbx-status" });
    const res = await withBusy("Metabolomics differential",
      () => API.mbxAnalyzeDiff(exp, {
        method: document.getElementById("mbx-diff-method").value || null,
        group_var: document.getElementById("mbx-group").value || null,
        ref_group: document.getElementById("mbx-ref").value || null,
        test_group: document.getElementById("mbx-test").value || null
      }));
    showResultTable("mbx-diff-result", res.data);
    toast("Metabolomics differential complete.", "success");
  } catch (e) {
    out.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${e.message}</p>`;
    toast(e.message, "error");
  } finally {
    setLoading(false);
  }
});

genPlot("mbx-btn-volcano", "mbx-volcano-out", exp => API.mbxVizVolcano(exp, {
  fc_cutoff: +document.getElementById("mbx-fc-cutoff").value,
  p_cutoff: +document.getElementById("mbx-p-cutoff").value,
  ...currentColorOptions(),
}));

// ── EXPORT PAGE ───────────────────────────────────
function downloadURL(url, filename) {
  const a = document.createElement("a");
  a.href = url; a.download = filename; a.click();
}

document.getElementById("btn-export-assay").addEventListener("click", () => {
  const exp = window._emp.currentExp;
  if (!exp) { toast("Import data first.", "error"); return; }
  downloadURL(API.exportAssayURL(exp), `${exp}_assay.csv`);
});

document.getElementById("btn-export-coldata").addEventListener("click", () => {
  const exp = window._emp.currentExp;
  if (!exp) { toast("Import data first.", "error"); return; }
  downloadURL(API.exportColdataURL(exp), `${exp}_metadata.csv`);
});

document.getElementById("btn-export-diff").addEventListener("click", () => {
  const exp = window._emp.currentExp;
  if (!exp) { toast("Import data first.", "error"); return; }
  downloadURL(API.exportResultURL(exp, "diff_analysis"), `${exp}_differential.csv`);
});

document.getElementById("btn-export-alpha").addEventListener("click", () => {
  const exp = window._emp.currentExp;
  if (!exp) { toast("Import data first.", "error"); return; }
  downloadURL(API.exportResultURL(exp, "alpha"), `${exp}_alpha.csv`);
});

document.getElementById("btn-export-rds").addEventListener("click", () => {
  downloadURL(API.exportRdsURL(), "EMP_session.rds");
});

document.getElementById("btn-summary-export-empt")?.addEventListener("click", async () => {
  const exp = window._emp.currentExp;
  if (!exp) { toast("Import data first.", "error"); return; }
  setLoading(true);
  try {
    await withBusy("Preparing EMPT export", () => API.prepareEmptExport(exp));
    downloadURL(API.exportEmptURL(exp), `${exp}_EMP_EMPT.rds`);
    toast("EMP format generated in R and download started.", "success");
  } catch (e) {
    toast(`EMP export failed: ${e.message}. If you just updated code, restart backend.`, "error");
  } finally {
    setLoading(false);
  }
});

document.getElementById("mbx-btn-export-diff")?.addEventListener("click", () => {
  const exp = window._emp.currentExp;
  if (!exp) { toast("Import data first.", "error"); return; }
  downloadURL(API.mbxExportDiffURL(exp), `${exp}_metabolomics_differential.csv`);
});

document.getElementById("mgx-btn-export-diff")?.addEventListener("click", () => {
  const exp = window._emp.currentExp;
  if (!exp) { toast("Import data first.", "error"); return; }
  downloadURL(API.mgxExportResultURL(exp), `${exp}_metagenomics_differential.csv`);
});

// ── OMICS PRESET ──────────────────────────────────
function applyOmicsPreset(omics) {
  const body = document.body;
  [...body.classList].forEach((c) => {
    if (c.startsWith("omics-")) body.classList.remove(c);
  });
  if (omics && omics !== "all") body.classList.add(`omics-${omics}`);
  localStorage.setItem("emp_omics", omics || "all");

  document.querySelectorAll(".tab-bar").forEach((bar) => {
    const section = bar.closest("section");
    if (!section) return;
    const visibleTabs = [...bar.querySelectorAll(".tab")].filter(
      (t) => t.offsetParent !== null
    );
    if (!visibleTabs.length) return;
    const activeTab = visibleTabs.find((t) => t.classList.contains("active")) || visibleTabs[0];
    bar.querySelectorAll(".tab").forEach((t) => t.classList.remove("active"));
    activeTab.classList.add("active");
    section.querySelectorAll(".tab-panel").forEach((p) => {
      p.classList.add("hidden"); p.classList.remove("active");
    });
    const panel = document.getElementById(activeTab.dataset.tab);
    if (panel) { panel.classList.remove("hidden"); panel.classList.add("active"); }
  });
}

(() => {
  const sel = document.getElementById("omics-pipeline");
  if (!sel) return;
  const saved = localStorage.getItem("emp_omics");
  if (saved) sel.value = saved;
  applyOmicsPreset(sel.value);
  sel.addEventListener("change", () => applyOmicsPreset(sel.value));
})();

window.addEventListener("emp:omics-change", (e) => {
  const omics = e.detail?.omics || "all";
  const sel = document.getElementById("omics-pipeline");
  if (sel) sel.value = omics;
  applyOmicsPreset(omics);
});

// ── GLOBAL CLEAR ALL ──────────────────────────────
async function clearAllData() {
  setLoading(true);
  try { await API.deleteSession(); } catch (_) { /* no session yet */ }
  localStorage.removeItem("emp_session_id");
  window._emp.experiments = [];
  window._emp.currentExp = null;
  window._emp.coldataCols = [];
  window._emp.features = [];
  document.querySelectorAll(".result-area, .alert").forEach((el) => {
    el.innerHTML = ""; el.classList.add("hidden");
  });
  ["exp-cards", "global-experiment", "summary-stats", "summary-coldata",
   "summary-features", "inspector-stats", "inspector-assay-table",
   "inspector-coldata-table", "inspector-rowdata-table",
   "inspector-result-table", "perf-last"].forEach((id) => {
    const el = document.getElementById(id); if (el) el.innerHTML = "";
  });
  document.getElementById("exp-selector-wrap")?.classList.add("hidden");
  document.getElementById("import-experiments")?.classList.add("hidden");
  document.getElementById("session-badge")?.classList.add("hidden");
  document.getElementById("btn-topbar-clear")?.classList.add("hidden");
  document.getElementById("step-timing")?.classList.add("hidden");
  setLoading(false);
  toast("All loaded data & analysis results cleared from memory.", "success");
}

document.getElementById("btn-topbar-clear")?.addEventListener("click", clearAllData);

// ── PERF / TIMING SURFACE ─────────────────────────
function prettyPath(p) {
  return String(p || "")
    .replace(/^\//, "")
    .replace(/\/[0-9a-f-]{8,}/g, "/:id")
    .replace(/\?.*$/, "");
}

function reportLastRun(label, totalMs, backendMs) {
  const chip = document.getElementById("step-timing");
  const lab  = document.getElementById("step-timing-label");
  const panel = document.getElementById("perf-last");
  const total = Math.round(totalMs || 0);
  const be    = backendMs ? `  ·  be ${Math.round(backendMs)}ms` : "";
  if (chip && lab) {
    chip.classList.remove("hidden");
    chip.classList.toggle("slow", total > 5000);
    chip.classList.toggle("ok", total <= 1000);
    lab.textContent = `${label}: ${total}ms${be}`;
  }
  if (panel) panel.textContent = `${label}\n${total}ms${be}`;
}

window.addEventListener("emp:timing", (ev) => {
  const d = ev.detail || {};
  reportLastRun(prettyPath(d.path), d.total_ms, d.backend_ms);
  document.getElementById("btn-topbar-clear")?.classList.remove("hidden");
});

// ══════════════════════════════════════════════════════════
//   Run All (one-click pipeline + unified progress bar)
// ══════════════════════════════════════════════════════════

(function initRunAll() {
  const bar  = () => document.getElementById("ra-progress-bar");
  const wrap = () => document.getElementById("ra-progress-wrap");
  const pct  = () => document.getElementById("ra-progress-pct");
  const msg  = () => document.getElementById("ra-progress-msg");
  const logEl = () => document.getElementById("ra-log");
  const dlLink = () => document.getElementById("ra-download");

  function setProgress(p, m) {
    wrap()?.classList.remove("hidden");
    if (bar()) bar().style.width = `${Math.max(0, Math.min(100, p))}%`;
    if (pct()) pct().textContent = `${Math.round(p)}%`;
    if (msg()) msg().textContent = m || "";
  }
  function appendLog(line) {
    if (!logEl()) return;
    logEl().style.display = "block";
    logEl().textContent += line + "\n";
    logEl().scrollTop = logEl().scrollHeight;
  }
  function togglePipelineUI() {
    const pipeline = document.getElementById("ra-pipeline")?.value || "rnaseq";
    const isRna = pipeline === "rnaseq";
    document.querySelectorAll(".ra-m16s-only").forEach(el => el.classList.toggle("hidden", isRna));
    ["ra-ref-wrap","ra-test-wrap","ra-organism-wrap","ra-rowsum-wrap","ra-enrich-wrap"]
      .forEach(id => document.getElementById(id)?.classList.toggle("hidden", !isRna));
  }
  document.getElementById("ra-pipeline")?.addEventListener("change", togglePipelineUI);
  togglePipelineUI();

  async function refreshBundlesList() {
    const el = document.getElementById("ra-bundles");
    if (!el) return;
    try {
      const r = await API.listBundles();
      const list = r.bundles || [];
      if (!list.length) { el.innerHTML = "—"; return; }
      el.innerHTML = list.map(b =>
        `<div style="display:flex;justify-content:space-between;padding:6px 0;border-bottom:1px solid var(--border)">
           <span><i data-lucide="archive"></i> <strong>${b.name}</strong>
             <span class="muted" style="margin-left:8px">${b.mtime}</span>
             <span class="muted" style="margin-left:8px">${b.size_kb} KB</span>
           </span>
           <a class="btn btn-outline btn-sm" target="_blank" rel="noopener"
              href="${API.bundleDownloadUrl(b.name)}">
             <i data-lucide="download"></i> Download
           </a>
         </div>`).join("");
      if (window.lucide) window.lucide.createIcons();
    } catch(_) { el.innerHTML = "—"; }
  }

  // Guess the model organism from feature (gene) naming convention:
  //   human gene symbols are ALL-CAPS (TP53), mouse are Title-case (Trp53),
  //   rat similar to mouse. Falls back to mouse when ambiguous.
  function guessOrganism() {
    const feats = (window._emp?.features || []).filter(f => /^[A-Za-z][A-Za-z0-9.\-]+$/.test(f)).slice(0, 400);
    if (feats.length < 10) return null;
    let allCaps = 0, titleCase = 0;
    for (const f of feats) {
      if (/^[A-Z0-9.\-]+$/.test(f) && /[A-Z]/.test(f)) allCaps++;
      else if (/^[A-Z][a-z]/.test(f)) titleCase++;
    }
    if (allCaps > titleCase * 1.5) return "hsa";
    if (titleCase > allCaps * 1.5) return "mmu";
    return null;
  }

  document.getElementById("btn-run-all-smart")?.addEventListener("click", () => {
    const exp = window._emp.currentExp;
    if (!exp) { toast("先导入数据再使用智能默认值。", "error"); return; }
    const pipeline = document.getElementById("ra-pipeline")?.value || "rnaseq";
    // Group + ref/test come from refreshGroupSelectors()/updateRaGroups() heuristics.
    refreshGroupSelectors().then(() => {
      updateRaGroups();
      if (pipeline === "rnaseq") {
        const org = guessOrganism();
        if (org) {
          const orgEl = document.getElementById("ra-organism");
          if (orgEl) orgEl.value = org;
        }
        // Recommended thresholds for the bundled RNA-seq demo.
        const set = (id, v) => { const el = document.getElementById(id); if (el) el.value = v; };
        set("ra-fc", "1");
        set("ra-p", "0.05");
        set("ra-use-padj", "true");
        set("ra-min-rowsum", "10");
        const orgName = document.getElementById("ra-organism")?.value || "mmu";
        toast(`已套用推荐参数：物种=${orgName}，|log2FC|≥1，padj≤0.05，min rowSum=10。`, "success");
      } else {
        const set = (id, v) => { const el = document.getElementById(id); if (el) el.value = v; };
        set("ra-tax-level", "Genus");
        set("ra-alpha", "shannon");
        set("ra-ord", "PCoA");
        toast("已套用 16S 推荐参数：Genus 层级，Shannon 多样性，PCoA 排序。", "success");
      }
    });
  });

  document.getElementById("btn-run-all")?.addEventListener("click", async () => {
    const exp = window._emp.currentExp;
    if (!exp) { toast("Import data first.", "error"); return; }

    const pipeline = document.getElementById("ra-pipeline").value;
    const group = document.getElementById("ra-group").value || null;

    // Reset UI
    if (logEl()) logEl().textContent = "";
    setProgress(1, "Starting…");
    dlLink()?.classList.add("hidden");
    setLoading(true);
    document.getElementById("btn-run-all").disabled = true;
    showGlobalProgress(pipeline === "rnaseq" ? "RNAseq — Run All" : "16S — Run All");

    try {
      let submit;
      if (pipeline === "rnaseq") {
        submit = await API.runAllRnaseq(exp, {
          group_var:   group,
          ref_group:   document.getElementById("ra-ref").value || null,
          test_group:  document.getElementById("ra-test").value || null,
          organism:    document.getElementById("ra-organism").value,
          fc_cutoff:  +document.getElementById("ra-fc").value,
          p_cutoff:   +document.getElementById("ra-p").value,
          use_padj:    document.getElementById("ra-use-padj").value === "true",
          min_row_sum:+document.getElementById("ra-min-rowsum").value,
          do_enrichment: document.getElementById("ra-enrich").value === "true",
        });
      } else {
        submit = await API.runAllM16s(exp, {
          group_var:      group,
          taxonomy_level: document.getElementById("ra-tax-level").value,
          alpha_index:    document.getElementById("ra-alpha").value,
          ord_method:     document.getElementById("ra-ord").value,
        });
      }
      appendLog(`submitted  ${submit.job_id}`);

      const { job, result } = await API.pollJobUntilDone(
        submit.job_id,
        (j) => {
          setProgress(j.progress || 0, j.message || j.status || "");
          updateGlobalProgress(j.progress || 0, j.message || "");
          if (j.message) appendLog(`[${j.progress || 0}%] ${j.message}`);
        },
        /*intervalMs*/ 800,
        /*timeoutMs */ 1800000, // 30 min
      );
      setProgress(100, "Done");
      updateGlobalProgress(100, "Done");
      setTimeout(hideGlobalProgress, 600);
      appendLog(`elapsed ${result.elapsed_s}s   bundle ${result.zip_name}`);

      if (result?.zip_name) {
        const a = dlLink();
        a.href = API.bundleDownloadUrl(result.zip_name);
        a.download = result.zip_name;
        a.classList.remove("hidden");
        if (window.lucide) window.lucide.createIcons();
      }
      toast("Bundle ready – click Download to save the zip.", "success");
      refreshBundlesList();
    } catch(e) {
      appendLog("ERROR: " + e.message);
      toast(e.message, "error");
      updateGlobalProgress(100, `Failed: ${e.message}`);
      setTimeout(hideGlobalProgress, 1500);
    } finally {
      setLoading(false);
      document.getElementById("btn-run-all").disabled = false;
    }
  });

  // Refresh bundles list when the tab becomes active.
  document.querySelectorAll('.nav-item[data-page="runall"]').forEach(el => {
    el.addEventListener("click", () => setTimeout(refreshBundlesList, 250));
  });
})();

// =====================================================================
// CLINICAL & PHENOTYPE
// ---------------------------------------------------------------------
// Three pieces:
//   (a) refreshClinicalVars()   — calls /clinical/vars and fills
//                                 every dropdown on the page
//   (b) feature × trait correlation handler
//   (c) scatter / fitline handler
//   (d) WGCNA async handler
// =====================================================================
let _clinVarCache = null;
let _clinResolvedSource = "experiment";

function setClinicalCodeStrategy(step, opts = {}) {
  const valid = new Set(["overview", "cor", "fitline", "wgcna", "three_line", "systematic", "joint", "reorient", "marker_model"]);
  if (!valid.has(step)) return;
  const sel = document.getElementById("clin-analysis-strategy");
  if (sel && sel.value !== step) sel.value = step;
  document.querySelectorAll("#page-clinical [data-clinical-script]").forEach((el) => {
    el.classList.toggle("clinical-script-active", el.dataset.clinicalScript === step);
  });
  notifyCodeLabClinicalStep(step);
  if (opts.scroll) {
    const target = document.querySelector(`#page-clinical [data-clinical-script="${step}"].card`) ||
      document.querySelector(`#page-clinical [data-clinical-script="${step}"]`);
    target?.scrollIntoView({ behavior: "smooth", block: "start" });
  }
}

function refreshClinicalCodeScript() {
  if (document.querySelector("#page-clinical.page.active")) refreshCodeLabContext();
}

async function resolveClinicalSource(preferred = "auto") {
  const exp = window._emp.currentExp;
  const pref = (preferred || "auto").toLowerCase();
  if (pref === "standalone") {
    const r = await API.clinicalVarsStandalone();
    return { source: "standalone", rows: Array.isArray(r?.data) ? r.data : [] };
  }
  if (pref === "experiment") {
    if (!exp) return { source: "experiment", rows: [] };
    const r = await API.clinicalVars(exp);
    return { source: "experiment", rows: Array.isArray(r?.data) ? r.data : [] };
  }
  // auto: prefer standalone if exists, otherwise experiment
  try {
    const s = await API.clinicalVarsStandalone();
    const sRows = Array.isArray(s?.data) ? s.data : [];
    const sNum = sRows.filter((r) => r.type === "numeric").length;
    if (sRows.length && sNum > 0) return { source: "standalone", rows: sRows };
    if (sRows.length && !exp) return { source: "standalone", rows: sRows };
  } catch (_) {}
  if (!exp) return { source: "experiment", rows: [] };
  const e = await API.clinicalVars(exp);
  const eRows = Array.isArray(e?.data) ? e.data : [];
  const eNum = eRows.filter((r) => r.type === "numeric").length;
  if (eNum > 0) return { source: "experiment", rows: eRows };
  // fallback: if experiment is count-only, try standalone once more
  try {
    const s = await API.clinicalVarsStandalone();
    const sRows = Array.isArray(s?.data) ? s.data : [];
    const sNum = sRows.filter((r) => r.type === "numeric").length;
    if (sRows.length && sNum > 0) return { source: "standalone", rows: sRows };
  } catch (_) {}
  return { source: "experiment", rows: eRows };
}

function updateClinicalPrecheck() {
  const el = document.getElementById("clin-precheck");
  if (!el) return;
  const btnThree = document.getElementById("clin-btn-three-line");
  const btnSys = document.getElementById("clin-btn-systematic");
  const sourceSel = document.getElementById("clin-data-source")?.value || "experiment";
  const source = sourceSel === "auto" ? _clinResolvedSource : sourceSel;
  const engine = document.getElementById("clin-three-engine")?.value || "gtsummary";
  const rows = Array.isArray(_clinVarCache) ? _clinVarCache : [];
  const num = rows.filter((r) => r.type === "numeric").length;
  const status = num > 0 ? "ok" : (rows.length > 0 ? "risk" : "missing");
  const tag = status === "ok" ? t("clinical.precheckOk")
    : (status === "risk" ? t("clinical.precheckRisk") : t("clinical.precheckMissing"));
  el.classList.remove("hidden");
  el.classList.remove("alert-error", "alert-info", "alert-success");
  el.classList.remove("precheck-ok", "precheck-risk", "precheck-missing");
  el.innerHTML = `<strong>${t("clinical.precheck")}</strong>: source=${source} | numeric=${num} | engine=${engine} | status=${tag}`;

  if (status === "ok") {
    el.classList.add("alert-success", "precheck-ok");
    if (btnThree) btnThree.disabled = false;
    if (btnSys) btnSys.disabled = false;
  } else if (status === "risk") {
    el.classList.add("alert-error", "precheck-risk");
    if (btnThree) btnThree.disabled = true;
    if (btnSys) btnSys.disabled = true;
  } else {
    el.classList.add("alert-info", "precheck-missing");
    if (btnThree) btnThree.disabled = true;
    if (btnSys) btnSys.disabled = true;
  }
}

async function refreshClinicalVars() {
  const exp = window._emp.currentExp;
  const sourceSel = document.getElementById("clin-data-source");
  const sourceReq = sourceSel?.value || "auto";
  const summary = document.getElementById("clin-vars-summary");
  if (!exp && sourceReq === "experiment") {
    if (summary) summary.textContent = "Load an experiment first.";
    _clinVarCache = [];
    updateClinicalPrecheck();
    return;
  }
  if (summary) summary.textContent = "Detecting…";
  try {
    let resolved = await resolveClinicalSource(sourceReq);
    let rows = resolved.rows || [];
    // User selected experiment explicitly but there are no numeric vars:
    // auto-fallback to standalone if it has numeric traits.
    if (sourceReq === "experiment") {
      const expNum = rows.filter((r) => r.type === "numeric").length;
      if (expNum <= 0) {
        try {
          const s = await API.clinicalVarsStandalone();
          const sRows = Array.isArray(s?.data) ? s.data : [];
          const sNum = sRows.filter((r) => r.type === "numeric").length;
          if (sNum > 0) {
            resolved = { source: "standalone", rows: sRows };
            rows = sRows;
            if (summary) summary.textContent = "Experiment has 0 numeric traits; switched to standalone clinical source.";
            if (sourceSel) sourceSel.value = "standalone";
          }
        } catch (_) {}
      }
    }
    _clinResolvedSource = resolved.source || "experiment";
    window._emp.clinicalResolvedSource = _clinResolvedSource;
    _clinVarCache = rows;
    const num = rows.filter(r => r.type === "numeric");
    const cat = rows.filter(r => r.type === "categorical");
    if (summary) {
      summary.textContent = rows.length
        ? `${num.length} numeric · ${cat.length} categorical (total ${rows.length})`
        : "No colData columns – add metadata on the Data page.";
    }
    updateClinicalPrecheck();

    // Render the detected-variables table
    const wrap = document.getElementById("clin-vars-table-wrap");
    const tbody = document.querySelector("#clin-vars-table tbody");
    if (tbody) {
      tbody.innerHTML = rows.map(r => `
        <tr>
          <td>${r.name}</td>
          <td><span class="tag ${r.type === "numeric" ? "ok" : ""}">${r.type}</span></td>
          <td>${r.n_samples ?? ""}</td>
          <td>${r.n_unique ?? ""}</td>
          <td>${r.type === "numeric" && Number.isFinite(r.min) ? (+r.min).toPrecision(4) : ""}</td>
          <td>${r.type === "numeric" && Number.isFinite(r.max) ? (+r.max).toPrecision(4) : ""}</td>
          <td>${r.type === "numeric" && Number.isFinite(r.mean) ? (+r.mean).toPrecision(4) : ""}</td>
        </tr>`).join("");
      wrap?.classList.toggle("hidden", rows.length === 0);
    }

    // Fill both multi-select trait boxes with numeric-only options.
    const numOpts = num.map(r => `<option value="${r.name}">${r.name}</option>`).join("");
    document.getElementById("clin-cor-traits").innerHTML    = numOpts;
    document.getElementById("clin-wgcna-traits").innerHTML  = numOpts;
    document.getElementById("clin-fit-trait").innerHTML     =
      numOpts || '<option value="">— no numeric trait —</option>';

    // Group dropdown on the scatter card uses CATEGORICAL columns.
    const catOpts = cat.map(r => `<option value="${r.name}">${r.name}</option>`).join("");
    document.getElementById("clin-fit-group").innerHTML =
      `<option value="">— no grouping —</option>${catOpts}`;
    const markerOutcome = document.getElementById("clin-marker-outcome");
    if (markerOutcome) {
      markerOutcome.innerHTML = catOpts || '<option value="">— no binary outcome —</option>';
    }
    const threeSel = document.getElementById("clin-three-group");
    if (threeSel) {
      const groupCats = cat.filter((r) => {
        const key = String(r.name || "").toLowerCase();
        return key === "group" || key === "subgroup" || key === "cohort" || (r.n_unique >= 2 && r.n_unique <= 50);
      });
      const preferred = groupCats.filter((r) => ["group", "subgroup", "cohort"].includes(String(r.name || "").toLowerCase()));
      const ordered = [...preferred, ...groupCats.filter((r) => !preferred.includes(r))];
      threeSel.innerHTML = `<option value="">(auto)</option>` +
        ordered.map((r) => {
          const preview = Array.isArray(r.levels) ? r.levels.slice(0, 4).join(", ") : "";
          const suffix = preview ? ` — ${preview}` : (r.n_unique ? ` (${r.n_unique})` : "");
          return `<option value="${r.name}">${r.name}${suffix}</option>`;
        }).join("");
      const auto = ordered.find((r) => String(r.name).toLowerCase() === "group") || ordered[0];
      if (auto && !threeSel.value) threeSel.value = auto.name;
    }
  } catch (e) {
    if (summary) summary.textContent = "Error: " + e.message;
    updateClinicalPrecheck();
    toast(e.message, "error");
  }
}
document.getElementById("clin-btn-refresh-vars")?.addEventListener("click",
  () => {
    setClinicalCodeStrategy("overview");
    refreshClinicalVars();
  });
document.getElementById("clin-data-source")?.addEventListener("change",
  () => {
    refreshClinicalVars();
    refreshClinicalCodeScript();
  });
document.getElementById("clin-three-engine")?.addEventListener("change",
  () => {
    updateClinicalPrecheck();
    refreshClinicalCodeScript();
  });

document.getElementById("clin-analysis-strategy")?.addEventListener("change", (e) => {
  setClinicalCodeStrategy(e.target.value, { scroll: true });
});

document.querySelectorAll("#page-clinical [data-clinical-script]").forEach((el) => {
  el.addEventListener("click", (ev) => {
    const step = ev.target?.closest?.("[data-clinical-script]")?.dataset?.clinicalScript ||
      el.dataset.clinicalScript;
    if (step) setClinicalCodeStrategy(step);
  }, { capture: true });
  el.addEventListener("focusin", () => {
    if (el.dataset.clinicalScript) setClinicalCodeStrategy(el.dataset.clinicalScript);
  });
});

[
  "clin-three-group", "clin-three-skip-high-card", "clin-three-max-levels",
  "clin-cor-traits", "clin-cor-method", "clin-cor-topn", "clin-cor-padj",
  "clin-fit-feature", "clin-fit-trait", "clin-fit-group", "clin-fit-method", "clin-fit-logy",
  "clin-wgcna-traits", "clin-wgcna-minmod", "clin-reorient-mode",
  "clin-marker-experiments", "clin-marker-outcome", "clin-marker-positive", "clin-marker-methods",
  "clin-marker-max-features", "clin-marker-validation", "clin-marker-include-clinical",
].forEach((id) => {
  const el = document.getElementById(id);
  el?.addEventListener("change", refreshClinicalCodeScript);
  el?.addEventListener("input", refreshClinicalCodeScript);
});

document.getElementById("clin-btn-reorient")?.addEventListener("click", async () => {
  setClinicalCodeStrategy("reorient");
  const mode = document.getElementById("clin-reorient-mode")?.value || "auto";
  setLoading(true);
  try {
    const r = await withBusy("Clinical orientation fix", () => API.clinicalReorient(mode));
    if (r?.warning) {
      toast(`${r.warning} (orientation=${r.orientation})`, "info");
    } else {
      toast(`Clinical table updated. Detected orientation: ${r.orientation}.`, "success");
    }
    await refreshClinicalVars();
  } catch (e) {
    toast(e.message, "error");
  } finally {
    setLoading(false);
  }
});

async function resolveClinicalAnalysisExperiment() {
  let exp = window._emp.currentExp || null;
  if (exp) return exp;
  if (Array.isArray(window._emp.experiments) && window._emp.experiments.length) {
    exp = window._emp.experiments[0]?.name || null;
    if (exp) {
      window._emp.currentExp = exp;
      const globalExp = document.getElementById("global-experiment");
      if (globalExp) globalExp.value = exp;
      return exp;
    }
  }
  try {
    await refreshExperimentList();
  } catch (_) {
    // ignore and keep fallback below
  }
  return window._emp.currentExp ||
    (Array.isArray(window._emp.experiments) && window._emp.experiments[0]?.name) ||
    null;
}

document.getElementById("clin-btn-three-line")?.addEventListener("click", async () => {
  setClinicalCodeStrategy("three_line");
  const out = document.getElementById("clin-three-table");
  let source = document.getElementById("clin-data-source")?.value || "auto";
  const exp = window._emp.currentExp;
  out.classList.remove("hidden");
  out.innerHTML = '<p style="padding:12px">Building three-line table…</p>';
  setLoading(true);
  try {
    if (source === "auto") {
      const resolved = await resolveClinicalSource("auto");
      source = resolved.source;
      _clinResolvedSource = source;
      window._emp.clinicalResolvedSource = source;
      _clinVarCache = resolved.rows;
      updateClinicalPrecheck();
      refreshClinicalCodeScript();
    }
    const r = await withBusy("Clinical three-line table", () => API.clinicalThreeLine({
      source,
      experiment: source === "experiment" ? exp : null,
      group_var: document.getElementById("clin-three-group")?.value || null,
      skip_high_cardinality: document.getElementById("clin-three-skip-high-card")?.checked !== false,
      max_levels: +document.getElementById("clin-three-max-levels")?.value || 20,
      table_engine: document.getElementById("clin-three-engine")?.value || "gtsummary",
    }));
    showResultTable("clin-three-table", r.data, 500, {
      prettyHeader: true,
      pValueKey: "P_value",
      variableKey: "Variable",
      downloadName: "clinical_three_line_table.csv",
      tableClass: "clinical-pub-table",
      publicationNote: "Continuous variables are shown as median [Q1;Q3]; categorical variables as n (%). p.overall: * <0.05, ** <0.01, *** <0.001.",
    });
    if (r?.warning) toast(r.warning, "info");
    if (r?.engine_used) {
      toast(`Three-line table ready (${r.engine_used}, numeric vars=${r.n_numeric_vars ?? "NA"}).`, "success");
    } else {
      toast("Three-line table ready.", "success");
    }
  } catch (e) {
    out.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${e.message}</p>`;
    toast(e.message, "error");
  } finally {
    setLoading(false);
  }
});

document.getElementById("clin-btn-systematic")?.addEventListener("click", async () => {
  setClinicalCodeStrategy("systematic");
  let source = document.getElementById("clin-data-source")?.value || "auto";
  const exp = window._emp.currentExp;
  const baseDiv = document.getElementById("clin-three-table");
  const withinDiv = document.getElementById("clin-systematic-within");
  const betweenDiv = document.getElementById("clin-systematic-between");
  [baseDiv, withinDiv, betweenDiv].forEach((el) => {
    if (!el) return;
    el.classList.remove("hidden");
    el.innerHTML = '<p style="padding:12px">Running systematic clinical analysis…</p>';
  });
  setLoading(true);
  try {
    if (source === "auto") {
      const resolved = await resolveClinicalSource("auto");
      source = resolved.source;
      _clinResolvedSource = source;
      window._emp.clinicalResolvedSource = source;
      _clinVarCache = resolved.rows;
      updateClinicalPrecheck();
      refreshClinicalCodeScript();
    }
    const cohortFilter = document.getElementById("clin-systematic-cohort")?.value || null;
    const r = await withBusy("Clinical systematic summary", () => API.clinicalSystematicSummary({
      source,
      experiment: source === "experiment" ? exp : null,
      group_var: document.getElementById("clin-three-group")?.value || null,
      skip_high_cardinality: document.getElementById("clin-three-skip-high-card")?.checked !== false,
      max_levels: +document.getElementById("clin-three-max-levels")?.value || 20,
      table_engine: document.getElementById("clin-three-engine")?.value || "gtsummary",
      cohort_filter: cohortFilter || null,
    }));

    const designType = r.design_type || "unknown";
    const analysisNote = r.analysis_note || "";
    const groupUsed = r.group_var || "(auto)";
    showResultTable("clin-three-table", r.baseline || [], 500, {
      prettyHeader: true,
      pValueKey: "P_value",
      variableKey: "Variable",
      downloadName: "clinical_baseline_table1.csv",
      tableClass: "clinical-pub-table",
      publicationNote: `Table 1 (baseline). design=${designType}; group=${groupUsed}; n=${r.n_baseline || 0}; paired samples=${r.n_pairs || 0}. ${analysisNote}`,
    });
    showResultTable("clin-systematic-within", r.within || [], 500, {
      prettyHeader: true,
      pValueKey: "P_value",
      variableKey: "Variable",
      downloadName: "clinical_within_group_paired_change.csv",
      tableClass: "clinical-pub-table",
      publicationNote: designType === "cross_sectional"
        ? "Within-group paired change is not applicable for cross-sectional data (no before/after pairs)."
        : "Within-group paired change table: Before vs After (Wilcoxon signed-rank).",
      emptyMessage: designType === "cross_sectional"
        ? "No within-group paired table for cross-sectional data."
        : "No valid before/after pairs found for within-group analysis.",
    });
    showResultTable("clin-systematic-between", r.between || [], 500, {
      prettyHeader: true,
      pValueKey: "P_value",
      variableKey: "Variable",
      downloadName: designType === "cross_sectional"
        ? "clinical_between_group_comparison.csv"
        : "clinical_between_group_delta.csv",
      tableClass: "clinical-pub-table",
      publicationNote: designType === "cross_sectional"
        ? "Between-group comparison table for cross-sectional data (Wilcoxon/Kruskal-Wallis)."
        : "Between-group delta comparison table: UC Δ vs IBS Δ (Wilcoxon rank-sum).",
      emptyMessage: designType === "cross_sectional"
        ? "No between-group comparison could be computed."
        : "No between-cohort delta comparison available.",
    });
    toast(`Systematic clinical summary ready (${designType}).`, "success");
  } catch (e) {
    [baseDiv, withinDiv, betweenDiv].forEach((el) => {
      if (!el) return;
      el.classList.remove("hidden");
      el.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${e.message}</p>`;
    });
    toast(e.message, "error");
  } finally {
    setLoading(false);
  }
});

// ── (b) Feature × Trait correlation ───────────────────────────────
document.getElementById("clin-btn-cor")?.addEventListener("click", async () => {
  setClinicalCodeStrategy("cor");
  const exp = await resolveClinicalAnalysisExperiment();
  if (!exp) {
    toast("No omics experiment loaded. Import expression/abundance matrix first.", "error");
    return;
  }
  const srcSel = document.getElementById("clin-data-source")?.value || "auto";
  const src = srcSel === "auto" ? (await resolveClinicalSource("auto")).source : srcSel;
  const traitSel = document.getElementById("clin-cor-traits");
  const traits = Array.from(traitSel?.selectedOptions || []).map(o => o.value);
  if (!traits.length) {
    toast("Select at least one numeric clinical trait.", "error");
    return;
  }
  const status = document.getElementById("clin-cor-status");
  const plot = document.getElementById("clin-cor-plot");
  const tableWrap = document.getElementById("clin-cor-table-wrap");
  const pdfLink = document.getElementById("clin-cor-pdf");
  pdfLink?.classList.add("hidden");
  plot.innerHTML = '<p style="padding:12px">Computing correlations…</p>';
  plot.classList.remove("hidden");
  tableWrap?.classList.add("hidden");
  status.classList.add("hidden");
  setLoading(true);
  try {
    const res = await withBusy("Clinical correlation", () => API.clinicalCor(exp, {
      traits,
      method:         document.getElementById("clin-cor-method").value,
      top_n_features: +document.getElementById("clin-cor-topn").value,
      p_adjust:       document.getElementById("clin-cor-padj").value,
      clinical_source: src,
    }));
    if (res.plot) showPlot("clin-cor-plot", res.plot);
    else plot.innerHTML = `<p style="padding:12px">Correlation done, but the
      matrix is too small to render a heatmap (need ≥ 2 features).</p>`;

    status.className = "alert alert-info";
    status.textContent =
      `${res.n_feat} features × ${traits.length} trait(s), n = ${res.n_samp} samples ` +
      `(method=${res.method}, adj=${res.p_adjust}).` +
      (res.table_n > 500 ? `  Top 500 of ${res.table_n} rows shown below.` : "");
    status.classList.remove("hidden");

    const tbody = document.querySelector("#clin-cor-table tbody");
    if (tbody) {
      tbody.innerHTML = (res.table || []).slice(0, 200).map(r => `
        <tr>
          <td>${r.feature}</td>
          <td>${r.trait}</td>
          <td>${Number.isFinite(r.r)    ? (+r.r).toFixed(3)    : ""}</td>
          <td>${Number.isFinite(r.p)    ? (+r.p).toExponential(2) : ""}</td>
          <td>${Number.isFinite(r.p_adj)? (+r.p_adj).toExponential(2) : ""}</td>
        </tr>`).join("");
      tableWrap?.classList.remove("hidden");
    }

    if (res.pdf_available && pdfLink) {
      const sid = localStorage.getItem("emp_session_id");
      pdfLink.href = `${API.apiBase()}/download/plot/${sid}/${encodeURIComponent(exp)}/${res.pdf_name}`;
      pdfLink.classList.remove("hidden");
    }
    toast("Clinical correlation ready.", "success");
  } catch (e) {
    plot.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${e.message}</p>`;
    toast(e.message, "error");
  } finally { setLoading(false); }
});

// ── (c) Scatter + regression line ─────────────────────────────────
document.getElementById("clin-btn-fit")?.addEventListener("click", async () => {
  setClinicalCodeStrategy("fitline");
  const exp = await resolveClinicalAnalysisExperiment();
  if (!exp) {
    toast("No omics experiment loaded. Import expression/abundance matrix first.", "error");
    return;
  }
  const srcSel = document.getElementById("clin-data-source")?.value || "auto";
  const src = srcSel === "auto" ? (await resolveClinicalSource("auto")).source : srcSel;
  const feature = document.getElementById("clin-fit-feature").value.trim();
  const trait   = document.getElementById("clin-fit-trait").value;
  if (!feature || !trait) {
    toast("Enter a feature ID and select a trait.", "error");
    return;
  }
  const plot = document.getElementById("clin-fit-plot");
  const status = document.getElementById("clin-fit-status");
  const pdfLink = document.getElementById("clin-fit-pdf");
  pdfLink?.classList.add("hidden");
  plot.innerHTML = '<p style="padding:12px">Fitting…</p>';
  plot.classList.remove("hidden");
  status.classList.add("hidden");
  setLoading(true);
  try {
    const res = await withBusy(`${feature} vs ${trait}`, () => API.clinicalFitline(exp, {
      feature, trait,
      group:  document.getElementById("clin-fit-group").value || null,
      method: document.getElementById("clin-fit-method").value,
      log_y:  document.getElementById("clin-fit-logy").value === "true",
      clinical_source: src,
    }));
    showPlot("clin-fit-plot", res.plot);
    status.className = "alert alert-info";
    status.textContent = `Spearman r = ${(+res.r).toFixed(3)}, p = ${(+res.p).toExponential(2)}, n = ${res.n}`
      + (res.group_used ? "  (grouped fit)" : "");
    status.classList.remove("hidden");
    if (res.pdf_available && pdfLink) {
      const sid = localStorage.getItem("emp_session_id");
      pdfLink.href = `${API.apiBase()}/download/plot/${sid}/${encodeURIComponent(exp)}/${res.pdf_name}`;
      pdfLink.classList.remove("hidden");
    }
    toast("Scatter ready.", "success");
  } catch (e) {
    plot.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${e.message}</p>`;
    toast(e.message, "error");
  } finally { setLoading(false); }
});

// ── (d) WGCNA module–trait (async, real progress bar) ──────────────
document.getElementById("clin-btn-wgcna")?.addEventListener("click", async () => {
  setClinicalCodeStrategy("wgcna");
  const exp = await resolveClinicalAnalysisExperiment();
  if (!exp) {
    toast("No omics experiment loaded. Import expression/abundance matrix first.", "error");
    return;
  }
  const srcSel = document.getElementById("clin-data-source")?.value || "auto";
  const src = srcSel === "auto" ? (await resolveClinicalSource("auto")).source : srcSel;
  const traitSel = document.getElementById("clin-wgcna-traits");
  const traits = Array.from(traitSel?.selectedOptions || []).map(o => o.value);
  const plot = document.getElementById("clin-wgcna-plot");
  const status = document.getElementById("clin-wgcna-status");
  const tableWrap = document.getElementById("clin-wgcna-table-wrap");
  const pdfLink = document.getElementById("clin-wgcna-pdf");
  pdfLink?.classList.add("hidden");
  tableWrap?.classList.add("hidden");
  plot.innerHTML = '<p style="padding:12px">Submitting WGCNA job…</p>';
  plot.classList.remove("hidden");
  status.classList.add("hidden");
  setLoading(true);
  try {
    const submit = API.clinicalWgcnaAsync(exp, {
      traits,
      min_module_size: +document.getElementById("clin-wgcna-minmod").value,
      clinical_source: src,
    });
    const res = await withGlobalProgress("WGCNA module–trait", submit,
                                          { timeoutMs: 20 * 60 * 1000 });
    showPlot("clin-wgcna-plot", res.png);
    status.className = "alert alert-info";
    status.textContent = `${res.n_modules} modules × ${res.n_traits} trait(s), ` +
      `top ${res.n_feat_used} variance features used for clustering.`;
    status.classList.remove("hidden");

    // The plumber /api/jobs/<id>/result wrapper json-encodes a `data`
    // data.frame; `table` may be pre-parsed or may also be a string.  Pick
    // whichever shape we actually got.
    let rows = [];
    if (Array.isArray(res.table)) rows = res.table;
    else if (typeof res.table === "string") {
      try { rows = JSON.parse(res.table); } catch (_) { /* ignore */ }
    }
    if (!rows.length && typeof res.data === "string") {
      try { rows = JSON.parse(res.data); } catch (_) { /* ignore */ }
    } else if (!rows.length && Array.isArray(res.data)) rows = res.data;
    const tbody = document.querySelector("#clin-wgcna-table tbody");
    if (tbody) {
      tbody.innerHTML = rows.slice(0, 100).map(r => `
        <tr>
          <td>${r.trait ?? ""}</td>
          <td>${r.module ?? ""}</td>
          <td>${Number.isFinite(+r.r)     ? (+r.r).toFixed(3)          : ""}</td>
          <td>${Number.isFinite(+r.p)     ? (+r.p).toExponential(2)    : ""}</td>
          <td>${Number.isFinite(+r.p_adj) ? (+r.p_adj).toExponential(2): ""}</td>
        </tr>`).join("");
      if (rows.length) tableWrap?.classList.remove("hidden");
    }

    if (res.pdf && pdfLink) {
      const sid = localStorage.getItem("emp_session_id");
      const name = (res.pdf + "").split("/").pop() || `wgcna_modtrait.pdf`;
      pdfLink.href = `${API.apiBase()}/download/plot/${sid}/${encodeURIComponent(exp)}/${name}`;
      pdfLink.classList.remove("hidden");
    }
    toast("WGCNA done.", "success");
  } catch (e) {
    plot.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${e.message}</p>`;
    toast(e.message, "error");
  } finally { setLoading(false); }
});

// ── (e) Multi-omics marker diagnostic / warning model ───────────────
document.getElementById("clin-btn-marker-model")?.addEventListener("click", async () => {
  setClinicalCodeStrategy("marker_model");
  let exps = Array.from(document.getElementById("clin-marker-experiments")?.selectedOptions || [])
    .map(o => o.value)
    .filter(Boolean);
  if (!exps.length) {
    await refreshExperimentList();
    exps = Array.from(document.getElementById("clin-marker-experiments")?.selectedOptions || [])
      .map(o => o.value)
      .filter(Boolean);
  }
  if (!exps.length) {
    toast("Select at least one omics experiment for marker modeling.", "error");
    return;
  }
  const outcome = document.getElementById("clin-marker-outcome")?.value || "";
  if (!outcome) {
    toast("Select a binary clinical outcome variable.", "error");
    return;
  }
  const methods = Array.from(document.getElementById("clin-marker-methods")?.selectedOptions || [])
    .map(o => o.value);
  const srcSel = document.getElementById("clin-data-source")?.value || "auto";
  const src = srcSel === "auto" ? (await resolveClinicalSource("auto")).source : srcSel;
  const status = document.getElementById("clin-marker-status");
  ["clin-marker-performance", "clin-marker-markers", "clin-marker-scores"].forEach((id) => {
    const el = document.getElementById(id);
    el?.classList.remove("hidden");
    if (el) el.innerHTML = '<p style="padding:12px">Running marker model…</p>';
  });
  if (status) {
    status.className = "alert alert-info";
    status.textContent = "Training models and computing ROC/AUC metrics…";
    status.classList.remove("hidden");
  }
  setLoading(true);
  try {
    const r = await withBusy("Clinical marker model", () => API.clinicalMarkerModel({
      experiments: exps,
      outcome_var: outcome,
      positive_class: document.getElementById("clin-marker-positive")?.value || null,
      methods,
      clinical_source: src,
      include_clinical_numeric: document.getElementById("clin-marker-include-clinical")?.checked !== false,
      max_features_per_omics: +document.getElementById("clin-marker-max-features")?.value || 200,
      validation_fraction: +document.getElementById("clin-marker-validation")?.value || 0.3,
      top_n: 30,
      seed: 123,
    }));
    showResultTable("clin-marker-performance", r.performance || [], 200, {
      prettyHeader: true,
      downloadName: "clinical_marker_model_performance.csv",
      tableClass: "clinical-pub-table",
      publicationNote: "Diagnostic/warning model performance: AUC, cut-off, sensitivity, specificity, sample size, and validation type.",
    });
    showResultTable("clin-marker-markers", r.markers || [], 500, {
      prettyHeader: true,
      downloadName: "clinical_marker_candidates.csv",
      tableClass: "clinical-pub-table",
      publicationNote: "Single-marker ROC results and multi-marker feature importance.",
    });
    showResultTable("clin-marker-scores", r.sample_scores || [], 500, {
      prettyHeader: true,
      downloadName: "clinical_marker_sample_scores.csv",
      tableClass: "clinical-pub-table",
      publicationNote: "Per-sample risk scores from multi-marker models.",
    });
    if (status) {
      const meta = r.meta || {};
      status.className = "alert alert-success";
      status.textContent = `Done: ${meta.n_samples || 0} samples, ${meta.n_features || 0} features, validation=${meta.validation || "NA"}.`;
    }
    toast("Marker model ready.", "success");
  } catch (e) {
    ["clin-marker-performance", "clin-marker-markers", "clin-marker-scores"].forEach((id) => {
      const el = document.getElementById(id);
      if (el) el.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${e.message}</p>`;
    });
    if (status) {
      status.className = "alert alert-error";
      status.textContent = e.message;
    }
    toast(e.message, "error");
  } finally {
    setLoading(false);
  }
});

// ── INITIALISE ────────────────────────────────────
(async () => {
  await initLocale();
  initFontScale();
  if (window.lucide) window.lucide.createIcons({ nodes: [document.getElementById("locale-switch")].filter(Boolean) });
  window.addEventListener("emp:locale-change", () => {
    document.querySelectorAll(".ai-copilot-btn-label").forEach((el) => {
      el.textContent = t("copilot.btn");
    });
    if (document.getElementById("page-clinical")?.classList.contains("active")) {
      updateClinicalPrecheck();
    }
  });
  await initCodeLab();
  initEvolution();
  await initTeaching();
  setupTeachingTraceHooks();
  await loadWorkflowBlueprint();
  await loadDemoDatasetButtons();
  await refreshExperimentList();
  if (localStorage.getItem("emp_session_id")) {
    document.getElementById("btn-topbar-clear")?.classList.remove("hidden");
  }
  if (localStorage.getItem("emp_welcome_dismissed")) {
    document.getElementById("welcome-card")?.classList.add("hidden");
  }
  const savedPage = localStorage.getItem("emp_last_page");
  if (savedPage && document.getElementById(`page-${savedPage}`)) {
    navigateTo(savedPage);
  } else {
    navigateTo("course");
  }
  updateWorkflowStepper(document.querySelector(".page.active")?.id?.replace("page-", "") || "course");
})();
