// Main application – routing, state, page wiring.
// The ?v= query string is a cache-buster: browsers treat each unique URL
// as a separate module, so bumping this value forces clients to drop any
// stale copy of api.js held in the HTTP cache or the module map.  Keep
// this value in lock-step with the one used in index.html (app.js ?v=).
import * as API from "./api.js?v=nav-active-fix-v1";
import {
  initCodeLab,
  notifyCodeLabNavigate,
  notifyCodeLabTab,
  notifyCodeLabClinicalStep,
  refreshCodeLabContext,
  openCodeLabPanel,
  applyCopilotAction,
} from "./code_lab.js?v=nav-active-fix-v1";
import {
  initTeaching,
  onTeachingPage,
  setupTeachingTraceHooks,
} from "./teaching.js?v=nav-active-fix-v1";
import { applyOmicsDefaults, omicsDefaultsHint } from "./omics_defaults.js?v=nav-active-fix-v1";
import { initGuide, openGuideInstallTab } from "./guide.js?v=nav-active-fix-v1";
import { initLocale, getLocale, t, pageTitleKey } from "./locale.js?v=nav-active-fix-v1";
import { applyPagesI18n } from "./i18n_pages.js?v=nav-active-fix-v1";
import { initFontScale } from "./font_scale.js?v=nav-active-fix-v1";
import { initEvolution, trackPromptButtonClick } from "./evolution.js?v=2026-07-16-multi-demo-v2";
import { initGithubSync } from "./github_sync.js?v=editable-repo-v1";

// ── Global state ──────────────────────────────────
window._emp = {
  experiments: [],      // [{name, samples, features, assay}]
  currentExp: null,     // string – currently selected experiment
  standaloneClinical: null, // {columns:[], orientation:"..."} for clinical-only uploads
  chipLastPeaks: null,  // session-level ChIP peaks (BED/MACS) — not an MAE experiment
  activeDataKind: "experiment", // "experiment" | "clinical" | "chipseq"
  clinicalResolvedSource: "experiment",
  coldataCols: [],      // [{name, n_unique, values}]
  features: [],         // string[] (dropdown subset; may be truncated)
  featuresN: 0,         // total feature count from server
  expCache: {},         // per-experiment {coldataCols, features, featuresN, fetchedAt}
  uiSnapshots: {},      // per-experiment UI result HTML (analysis/viz/prep/summary)
  uiSnapshotActiveKey: null, // key currently shown in the UI result panes
  _groupRefreshInflight: null,
  analysisBusy: 0,      // >0 while withBusy / withGlobalProgress is active
  syncInflight: false,  // GitHub homework sync mutex (also set by github_sync.js)
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
  wrap:   document.getElementById("global-progress"),
  label:  document.getElementById("gp-label"),
  msg:    document.getElementById("gp-msg"),
  pct:    document.getElementById("gp-pct"),
  bar:    document.getElementById("gp-bar"),
  cancel: document.getElementById("gp-cancel"),
});

/** Active cancel handler for the upload currently shown in the top strip. */
let _gpOnCancel = null;

function setGlobalProgressCancellable(onCancel) {
  _gpOnCancel = typeof onCancel === "function" ? onCancel : null;
  const btn = _gp().cancel;
  if (!btn) return;
  const on = !!_gpOnCancel;
  btn.classList.toggle("hidden", !on);
  btn.disabled = !on;
  if (on) btn.textContent = t("upload.cancel");
}

function initGlobalProgressCancel() {
  const btn = _gp().cancel;
  if (!btn || btn.dataset.bound === "1") return;
  btn.dataset.bound = "1";
  btn.addEventListener("click", () => {
    if (!_gpOnCancel) return;
    btn.disabled = true;
    try { _gpOnCancel(); } catch (_) { /* ignore */ }
  });
}
initGlobalProgressCancel();

export function showGlobalProgress(label = "Working…", opts = {}) {
  const g = _gp();
  if (!g.wrap) return;
  g.label.textContent = label;
  g.msg.textContent   = "";
  g.pct.textContent   = "0%";
  g.bar.style.setProperty("--pct", "0%");
  g.wrap.classList.remove("hidden");
  setGlobalProgressCancellable(opts.onCancel || null);
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
  setGlobalProgressCancellable(null);
}

// Submit an async backend call that returns `{ job_id }`, then poll until
// completion while driving the global progress bar.  The caller receives
// the final result object from `/api/jobs/<id>/result`.
export async function withGlobalProgress(label, jobPromiseOrId, opts = {}) {
  window._emp.analysisBusy = (window._emp.analysisBusy || 0) + 1;
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
  } finally {
    window._emp.analysisBusy = Math.max(0, (window._emp.analysisBusy || 1) - 1);
  }
}

function _busyElapsedLabel(t0) {
  const s = Math.max(0, Math.floor((Date.now() - t0) / 1000));
  const m = Math.floor(s / 60);
  const r = s % 60;
  return m > 0 ? `${m}m ${r}s` : `${r}s`;
}

// Generic "show the top strip while this promise is pending".
// Use for synchronous backend endpoints that do NOT return a job_id so the
// user still sees visual feedback.  The strip moves with indeterminate
// drift (no real % from the server).
//
// opts.mode:
//   - "asymptote" (default): climbs toward 92% until the promise settles
//     (fine for short calls; looks "stuck at 92%" on long jobs).
//   - "hold": 0–5% start, then pulse in holdMin–holdMax (default 50–85)
//     with phase text + elapsed time — use for MACS / long ChIP analyze.
export async function withBusy(label, workPromiseOrFn, opts = {}) {
  window._emp.analysisBusy = (window._emp.analysisBusy || 0) + 1;
  showGlobalProgress(label);
  const mode = opts.mode === "hold" ? "hold" : "asymptote";
  const holdLo = Math.max(5, Math.min(90, Number(opts.holdMin) || 50));
  const holdHi = Math.max(holdLo + 1, Math.min(95, Number(opts.holdMax) || 85));
  const baseMsg = opts.message || "";
  const t0 = Date.now();
  let drift = 0, driftTimer = null;
  const driftLoop = () => {
    const elapsed = _busyElapsedLabel(t0);
    const msg = baseMsg
      ? `${baseMsg}（已用时 ${elapsed}）`
      : (mode === "hold" ? `已用时 ${elapsed}` : "");
    if (mode === "hold") {
      const sec = (Date.now() - t0) / 1000;
      if (sec < 1.2) {
        drift = Math.min(5, (sec / 1.2) * 5);
      } else {
        const mid = (holdLo + holdHi) / 2;
        const amp = (holdHi - holdLo) / 2;
        // Gentle pulse so the bar stays alive without implying near-done.
        drift = mid + amp * Math.sin((sec - 1.2) / 9);
      }
      updateGlobalProgress(drift, msg);
    } else {
      // Climb asymptotically toward 92% – never reach 100 until we actually finish.
      drift = Math.min(drift + (92 - drift) * 0.08, 92);
      updateGlobalProgress(drift, msg || opts.message || "");
    }
  };
  driftTimer = setInterval(driftLoop, mode === "hold" ? 400 : 300);
  driftLoop();
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
  } finally {
    window._emp.analysisBusy = Math.max(0, (window._emp.analysisBusy || 1) - 1);
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
    const downloadName = options.downloadName || `${containerId}.csv`;
    container.innerHTML = `
      <div class="plot-toolbar">
        <button type="button" class="btn btn-outline emp-csv-dl" data-dl-name="${escapeHtml(downloadName)}">
          <i data-lucide="download"></i> Download CSV
        </button>
      </div>
      <table class="${options.tableClass || ""}">${thead}${tbody}</table>
    `;
    const dlBtn = container.querySelector(".emp-csv-dl");
    if (dlBtn) {
      dlBtn.addEventListener("click", () => {
        const csvRows = [cols.join(",")].concat(
          rows.map((r) => cols.map((c) => {
            const v = r[c] ?? "";
            const s = String(v).replaceAll('"', '""');
            return /[",\n]/.test(s) ? `"${s}"` : s;
          }).join(","))
        );
        const blob = new Blob([csvRows.join("\n")], { type: "text/csv;charset=utf-8;" });
        const a = document.createElement("a");
        a.href = URL.createObjectURL(blob);
        a.download = downloadName;
        a.click();
        setTimeout(() => URL.revokeObjectURL(a.href), 5000);
      });
    }
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
    noteUiResultChanged();
  } catch(e) {
    container.innerHTML = `<p style='padding:12px;color:#991b1b'>Could not parse results: ${e.message}</p>`;
    container.classList.remove("hidden");
  }
}

export function plotPdfDownloadUrl(pdfName) {
  if (!pdfName) return null;
  const sid = localStorage.getItem("emp_session_id");
  const exp = window._emp?.currentExp;
  if (!sid || !exp) return null;
  return `${API.apiBase()}/download/plot/${sid}/${encodeURIComponent(exp)}/${encodeURIComponent(pdfName)}`;
}

function plotDownloadOptions(res = {}) {
  if (res.pdf_available && res.pdf_name) {
    return { pdfUrl: plotPdfDownloadUrl(res.pdf_name), pdfName: res.pdf_name };
  }
  return {};
}

export function showPlot(containerId, base64png, options = {}) {
  const container = document.getElementById(containerId);
  if (!container) return;
  const pngSrc = `data:image/png;base64,${base64png}`;
  const pdfUrl = options.pdfUrl || (options.pdfName ? plotPdfDownloadUrl(options.pdfName) : null);
  const downloadStem = options.downloadStem || "plot";
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
      if (mime === "image/tiff" && url.startsWith("data:image/png")) {
        url = c.toDataURL("image/png");
      }
      const a = document.createElement("a");
      a.href = url;
      a.download = name;
      a.click();
    });
  };
  const pdfBtnHtml = pdfUrl
    ? `<a class="btn btn-outline" id="${containerId}-dl-pdf" href="${pdfUrl}" download="${downloadStem}.pdf" title="Editable vector PDF (ggplot)"><i data-lucide="download"></i> PDF</a>`
    : "";
  container.innerHTML = `
    <div class="plot-toolbar">
      <a class="btn btn-outline" id="${containerId}-dl-png" href="${pngSrc}" download="${downloadStem}.png"><i data-lucide="download"></i> PNG</a>
      <a class="btn btn-outline" id="${containerId}-dl-jpg" href="#"><i data-lucide="download"></i> JPEG</a>
      <a class="btn btn-outline" id="${containerId}-dl-tiff" href="#"><i data-lucide="download"></i> TIFF</a>
      ${pdfBtnHtml}
    </div>
    <img src="${pngSrc}" alt="Plot">
  `;
  container.classList.remove("hidden");
  addDownloadHandler(`${containerId}-dl-jpg`, "image/jpeg", `${downloadStem}.jpg`);
  addDownloadHandler(`${containerId}-dl-tiff`, "image/tiff", `${downloadStem}.tiff`);
  if (window.lucide) lucide.createIcons({ nodes: [container] });
  attachAiCopilot(container, { ...inferAiContext(containerId), kind: "plot" });
  noteUiResultChanged();
}

function buildPlotPanelHtml(panelId, base64png, downloadStem, pdfName = null) {
  const pngSrc = `data:image/png;base64,${base64png}`;
  const pdfUrl = pdfName ? plotPdfDownloadUrl(pdfName) : null;
  const pdfBtn = pdfUrl
    ? `<a class="btn btn-outline" href="${pdfUrl}" download="${downloadStem}.pdf" title="Editable vector PDF (ggplot)"><i data-lucide="download"></i> PDF</a>`
    : "";
  return `
    <div class="ord-plot-panel" id="${panelId}-wrap">
      <div class="plot-toolbar">
        <a class="btn btn-outline" id="${panelId}-dl-png" href="${pngSrc}" download="${downloadStem}.png"><i data-lucide="download"></i> PNG</a>
        <a class="btn btn-outline" id="${panelId}-dl-jpg" href="#"><i data-lucide="download"></i> JPEG</a>
        ${pdfBtn}
      </div>
      <img src="${pngSrc}" alt="${downloadStem}">
    </div>`;
}

function wirePlotPanelDownloads(panelId, downloadStem) {
  const wrap = document.getElementById(`${panelId}-wrap`);
  if (!wrap) return;
  const img = wrap.querySelector("img");
  if (!img) return;
  const mkCanvas = () => new Promise((resolve, reject) => {
    const probe = new Image();
    probe.onload = () => {
      const c = document.createElement("canvas");
      c.width = probe.naturalWidth || probe.width;
      c.height = probe.naturalHeight || probe.height;
      c.getContext("2d").drawImage(probe, 0, 0);
      resolve(c);
    };
    probe.onerror = reject;
    probe.src = img.src;
  });
  const jpgBtn = document.getElementById(`${panelId}-dl-jpg`);
  jpgBtn?.addEventListener("click", async (e) => {
    e.preventDefault();
    const c = await mkCanvas();
    const a = document.createElement("a");
    a.href = c.toDataURL("image/jpeg", 0.95);
    a.download = `${downloadStem}.jpg`;
    a.click();
  });
}

function formatOrdinationStats(stats) {
  if (!stats || typeof stats !== "object") return "";
  const lines = [];
  if (stats.title) lines.push(`<strong>${escapeHtml(stats.title)}</strong>`);
  if (stats.subtitle) lines.push(`<div>${escapeHtml(stats.subtitle)}</div>`);
  if (stats.caption) lines.push(`<div>${escapeHtml(stats.caption)}</div>`);
  ["proj_x", "proj_y"].forEach(key => {
    const rec = stats[key];
    if (rec?.axis && rec?.label) {
      lines.push(`<div>${escapeHtml(rec.axis)} projection: ${escapeHtml(rec.label)}</div>`);
    }
  });
  return lines.join("");
}

export function showOrdinationResult(containerId, res) {
  const container = document.getElementById(containerId);
  if (!container) return;
  const panels = [
    { id: `${containerId}-main`, b64: res.plot_main || res.plot, label: "Core ordination", stem: "ordination_core", pdfName: res.pdf_main_name },
    { id: `${containerId}-proj-x`, b64: res.plot_proj_x, label: res.stats?.axis_x || "Axis X projection", stem: "ordination_proj_axis_x", pdfName: res.pdf_proj_x_name },
    { id: `${containerId}-proj-y`, b64: res.plot_proj_y, label: res.stats?.axis_y || "Axis Y projection", stem: "ordination_proj_axis_y", pdfName: res.pdf_proj_y_name },
  ].filter(p => p.b64);

  let html = "";
  const statsHtml = formatOrdinationStats(res.stats);
  if (statsHtml) {
    html += `<div class="ord-stats-card">${statsHtml}</div>`;
  }
  for (const p of panels) {
    html += `<section class="ord-section"><h4 class="ord-section-title">${escapeHtml(p.label)}</h4>${buildPlotPanelHtml(p.id, p.b64, p.stem, p.pdfName)}</section>`;
  }
  container.innerHTML = html || `<p style="padding:12px">No plot returned.</p>`;
  container.classList.remove("hidden");
  for (const p of panels) wirePlotPanelDownloads(p.id, p.stem);
  if (window.lucide) lucide.createIcons({ nodes: [container] });
  attachAiCopilot(container, { ...inferAiContext(containerId), kind: "plot" });
  noteUiResultChanged();
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
  const rawId = String(domId || "");
  let id = rawId.replace(/-(result|out|table|output)$/i, "");
  const omicsPrefix = { tx: "transcriptomics", mgx: "metagenomics", mbx: "metabolomics", m16s: "microbiome_16s", chip: "chipseq" };
  let omics = currentOmicsPreset();
  const pfx = id.match(/^(tx|mgx|mbx|m16s)-/);
  if (pfx) { omics = omicsPrefix[pfx[1]] || omics; id = id.replace(/^(tx|mgx|mbx|m16s)-/, ""); }
  id = id.replace(/^(viz|analysis|ana)-/, "").replace(/-(plot|viz|out)$/, "");
  const isDegHeatmap = /deg[-_]?heat/i.test(id);
  if (isDegHeatmap) id = "heatmap";
  const map = {
    alpha: "alpha", "alpha-plot": "alpha", dim: "dimension", scatter: "scatter",
    cor: "correlation", cluster: "cluster", marker: "marker", enrich: "enrichment",
    diff: "differential", volcano: "volcano", heatmap: "heatmap", boxplot: "boxplot",
    barplot: "barplot", structure: "structure", sankey: "structure", network: "network",
    analysis: "differential",
  };
  const analysis_type = map[id] || id || "analysis";
  const params = {};
  if (isDegHeatmap) {
    params.heatmap_mode = "differential";
    const fc = document.getElementById("deg-fc")?.value;
    const p = document.getElementById("deg-p")?.value;
    if (fc) params.fc_cutoff = fc;
    if (p) params.p_cutoff = p;
  }
  const groupEl = document.getElementById("heat-group") || document.getElementById("scat-group") || document.getElementById("m16s-group");
  const group = groupEl?.value || null;
  const groups = [];
  if (group && window._emp?.coldataCols) {
    const col = window._emp.coldataCols.find((c) => c.name === group);
    if (col?.values?.length) groups.push(...col.values);
  }
  return {
    analysis_type,
    omics,
    experiment: window._emp?.currentExp || null,
    group,
    groups: groups.length ? groups : undefined,
    params: Object.keys(params).length ? params : undefined,
  };
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
  chipseq: "ChIP-seq Analysis",
  chipseq_downstream: "ChIPseq Downstream",
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
  // Unified ChIP page: downstream checklist lives under Step2 / Advanced.
  let chipStep = null;
  if (page === "chipseq_downstream") {
    page = "chipseq";
    chipStep = "2";
  }
  // Dedicated pages: chipseq (never fold into analysis-only).
  // Highlight the matching nav item; when on unified chipseq, also mark the
  // hidden downstream alias so any leftover deep-links stay consistent.
  document.querySelectorAll(".nav-item").forEach(el => {
    const match = el.dataset.page === page ||
      (page === "chipseq" && el.dataset.page === "chipseq_downstream");
    el.classList.toggle("active", match);
  });
  document.querySelectorAll(".page").forEach(el => el.classList.remove("active"));
  const target = document.getElementById(`page-${page}`);
  if (target) target.classList.add("active");
  document.getElementById("page-title").textContent =
    t(pageTitleKey(page), getLocale()) || pageTitles[page] || page;
  updateWorkflowStepper(page);
  try { localStorage.setItem("emp_last_page", page); } catch { /* quota */ }
  window.dispatchEvent(new CustomEvent("emp:page-view", { detail: { page, locale: getLocale() } }));

  // Refresh dynamic content on navigation
  if (page === "summary") loadSummary();
  if (page === "inspector") loadInspector();
  if (page === "analysis" || page === "visualization" || page === "preparation") {
    ensureGroupSelectors({ background: true });
  }
  if (page === "preparation" && window._emp.currentExp) refreshPrepareSnapshots();
  if (page === "clinical") refreshClinicalVars();
  if (page === "course" || page === "prompts") onTeachingPage(page);
  if (page === "guide") initGuide();
  if (page === "chipseq") {
    ensureChipUnifiedLayout();
    refreshChipBamTable();
    refreshChipPeakStatus();
    if (chipStep) setChipWizardStep(chipStep);
    else setChipWizardStep(window._emp.chipWizardStep || "1");
    refreshChipRecipeDeps();
    loadChipRecipePacks().catch(() => {});
    if (window.lucide) lucide.createIcons();
  }
  // Code Lab still keys off analysis for ChIP form snippets.
  notifyCodeLabNavigate(page === "chipseq" ? "analysis" : page);
}

/** Jump to dedicated ChIPseq workspace (sidebar / Import helpers). */
function openChipseqWorkspace({ skipNavigate = false } = {}) {
  window._emp.currentOmics = "chipseq";
  window._emp.activeDataKind = "chipseq";
  try {
    const sel = document.getElementById("omics-pipeline");
    if (sel) sel.value = "chipseq";
  } catch (_) { /* no-op */ }
  try {
    window.dispatchEvent(new CustomEvent("emp:omics-change", { detail: { omics: "chipseq" } }));
  } catch (_) { /* no-op */ }
  if (!skipNavigate) navigateTo("chipseq");
  setTimeout(() => {
    // Keep analysis-tab pointer in sync if user later opens 分析 → ChIP-seq.
    document.querySelector('[data-tab="ana-chipseq"]')?.classList.add("active");
    refreshChipBamTable();
    refreshChipPeakStatus();
    if (window.lucide) lucide.createIcons();
  }, 120);
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

function demoLabel(d) {
  if (!d) return "";
  if (getLocale() === "zh") return d.label_zh || d.label_en || d.label || d.id;
  return d.label_en || d.label || d.id;
}

function demoIcon(omics) {
  switch ((omics || "").toLowerCase()) {
    case "transcriptomics": return "🧬";
    case "microbiome_16s":  return "🧫";
    case "metagenomics":   return "🦠";
    case "metabolomics":   return "⚗️";
    case "clinical":       return "🩺";
    case "chipseq":        return "🧶";
    case "multiomics":     return "🔗";
    case "customize":      return "✏️";
    default:               return "📊";
  }
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
    const singleBtn = available.map(d => `
      <button type="button" class="btn btn-outline demo-dataset-btn"
              data-demo-id="${escapeHtml(d.id)}"
              data-omics="${escapeHtml(d.omics || "")}">
        <span class="demo-icon">${demoIcon(d.omics)}</span>
        <span class="demo-label">${escapeHtml(demoLabel(d))}</span>
      </button>`).join("");
    root.innerHTML = `
      <div class="demo-row-wrap">
        <div class="demo-row demo-row-single">${singleBtn}</div>
        <button type="button" class="btn btn-primary demo-load-all-btn" data-demo-load-all>
          <span class="demo-icon">✨</span>
          <span class="demo-label">${escapeHtml(t("demo.loadAll"))}</span>
        </button>
        <p class="hint demo-load-all-hint">${escapeHtml(t("demo.loadAllHint"))}</p>
      </div>`;
    root.querySelectorAll(".demo-dataset-btn").forEach(btn => {
      btn.addEventListener("click", () => importDemoById(btn.dataset.demoId, btn.dataset.omics));
    });
    root.querySelector("[data-demo-load-all]")?.addEventListener("click", importAllDemos);
  } catch (e) {
    root.innerHTML = `<span class="hint">${t("demo.loadFail")}${escapeHtml(e.message)}</span>`;
  }
}

async function importAllDemos() {
  setLoading(true);
  try {
    if (!localStorage.getItem("emp_session_id")) await API.createSession();
    const datasets = await API.listDemoDatasets();
    const available = datasets.filter(d => d.available);
    const targets = available.filter(d => ["m16s_course", "rnaseq_course", "clinical_course"].includes(d.id));
    if (!targets.length) {
      toast(t("demo.unavailable"), "error");
      return;
    }
    const failures = [];
    for (const d of targets) {
      try {
        if (d.id === "clinical_course") {
          // Clinical is session-level (no MAE experiment); import is independent.
          await withBusy(`Loading ${demoLabel(d)}`, () => API.importDemoDataset(d.id));
        } else {
          await withBusy(`Loading ${demoLabel(d)}`, () => API.importDemoDataset(d.id));
          await refreshExperimentList();
        }
      } catch (e) {
        failures.push({ id: d.id, message: e.message });
      }
    }
    await refreshExperimentList();
    if (failures.length) {
      toast(`Loaded with ${failures.length} issue(s). See console.`, "error");
      console.warn("[demo] failures:", failures);
    } else {
      toast(t("demo.loadAllDone"), "success");
    }
    showAlert("import-result",
      `✓ Loaded ${targets.length - failures.length}/${targets.length} demo datasets.`,
      failures.length ? "info" : "success");
    navigateTo("summary");
  } catch (e) {
    showAlert("import-result", `Error: ${e.message}`, "error");
    toast(e.message, "error");
  } finally {
    setLoading(false);
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
        listEl.querySelectorAll(".workflow-tag").forEach((b) => b.classList.toggle("is-active", b === btn));
        try {
          window.dispatchEvent(new CustomEvent("emp:omics-change", { detail: { omics: wid } }));
        } catch (_) { /* no-op */ }

        // Sync top experiment selector to a loaded dataset of this type.
        if (wid === "clinical") {
          const sc = await probeStandaloneClinical();
          if (sc && globalExp && [...globalExp.options].some((o) => o.value === CLINICAL_STANDALONE_TOKEN)) {
            globalExp.value = CLINICAL_STANDALONE_TOKEN;
            await onGlobalExperimentChange(CLINICAL_STANDALONE_TOKEN);
          } else {
            navigateTo("clinical");
          }
        } else if (wid === "chipseq") {
          const chip = await probeStandaloneChipPeaks();
          if (chip && globalExp && [...globalExp.options].some((o) => o.value === CHIP_STANDALONE_TOKEN)) {
            globalExp.value = CHIP_STANDALONE_TOKEN;
            await onGlobalExperimentChange(CHIP_STANDALONE_TOKEN);
          } else {
            openChipseqWorkspace();
          }
        } else {
          const match = (window._emp.experiments || []).find((e) => e.omics === wid)
            || (window._emp.experiments || []).find((e) => inferOmicsForExperiment(e.name) === wid);
          if (match && globalExp) {
            globalExp.value = match.name;
            await onGlobalExperimentChange(match.name);
          }
        }

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
let _groupRefreshDebounce = null;
const CLINICAL_STANDALONE_TOKEN = "__clinical_standalone__";
const CHIP_STANDALONE_TOKEN = "__chipseq_peaks__";

function isClinicalStandaloneToken(value) {
  return String(value || "") === CLINICAL_STANDALONE_TOKEN;
}

function isChipStandaloneToken(value) {
  return String(value || "") === CHIP_STANDALONE_TOKEN;
}

function clinicalStandaloneOptionHtml() {
  return `<option value="${CLINICAL_STANDALONE_TOKEN}">Clinical / Phenotype (session)</option>`;
}

function chipStandaloneOptionHtml() {
  return `<option value="${CHIP_STANDALONE_TOKEN}">ChIP-seq (peaks)</option>`;
}

function chipPeakDisplayName(peaks) {
  if (!peaks) return "";
  if (peaks.display_name) return String(peaks.display_name);
  const path = peaks.peak_file || "";
  return path.split(/[/\\]/).pop() || path || "";
}

function fillGlobalExperimentSelect(exps, sc, preferred = null, chip = null) {
  if (!globalExp) return;
  const list = Array.isArray(exps) ? exps : [];
  let html = list.map((e) => `<option value="${escapeHtml(e.name)}">${escapeHtml(e.name)}</option>`).join("");
  if (sc) html += clinicalStandaloneOptionHtml();
  if (chip) html += chipStandaloneOptionHtml();
  globalExp.innerHTML = html;
  const wrap = document.getElementById("exp-selector-wrap");
  if (!list.length && !sc && !chip) {
    wrap?.classList.add("hidden");
    return;
  }
  wrap?.classList.remove("hidden");

  const prefer = preferred || window._emp.currentExp;
  if (isClinicalStandaloneToken(prefer) && sc) {
    globalExp.value = CLINICAL_STANDALONE_TOKEN;
    window._emp.currentExp = null;
    window._emp.activeDataKind = "clinical";
  } else if (isChipStandaloneToken(prefer) && chip) {
    globalExp.value = CHIP_STANDALONE_TOKEN;
    window._emp.currentExp = null;
    window._emp.activeDataKind = "chipseq";
  } else if (prefer && list.some((e) => e.name === prefer)) {
    globalExp.value = prefer;
    window._emp.currentExp = prefer;
    window._emp.activeDataKind = "experiment";
  } else if (list.length) {
    globalExp.value = list[0].name;
    window._emp.currentExp = list[0].name;
    window._emp.activeDataKind = "experiment";
  } else if (sc) {
    globalExp.value = CLINICAL_STANDALONE_TOKEN;
    window._emp.currentExp = null;
    window._emp.activeDataKind = "clinical";
  } else if (chip) {
    globalExp.value = CHIP_STANDALONE_TOKEN;
    window._emp.currentExp = null;
    window._emp.activeDataKind = "chipseq";
  }
  if (!window._emp.uiSnapshotActiveKey) {
    const gv = globalExp?.value;
    window._emp.uiSnapshotActiveKey = isClinicalStandaloneToken(gv)
      ? CLINICAL_STANDALONE_TOKEN
      : isChipStandaloneToken(gv)
        ? CHIP_STANDALONE_TOKEN
        : (window._emp.currentExp || null);
  }
  updateUiSnapshotBadges();
}

function activePageKey() {
  return document.querySelector(".page.active")?.id?.replace(/^page-/, "") || "";
}

function inferOmicsForExperiment(expName) {
  if (isClinicalStandaloneToken(expName) || window._emp.activeDataKind === "clinical") {
    return "clinical";
  }
  if (isChipStandaloneToken(expName) || window._emp.activeDataKind === "chipseq") {
    return "chipseq";
  }
  const hit = (window._emp.experiments || []).find((e) => e.name === expName);
  if (hit?.omics) return hit.omics;
  const n = String(expName || "").toLowerCase();
  if (/16s|m16s|tax|microbiome/.test(n)) return "microbiome_16s";
  if (/chip|atac|peak/.test(n)) return "chipseq";
  if (/meta.?bol|mbx/.test(n)) return "metabolomics";
  if (/metagen|mgx|ko_|pathway/.test(n)) return "metagenomics";
  if (/prot|protein/.test(n)) return "proteomics";
  if (/rna|tx|transcript|gene/.test(n)) return "transcriptomics";
  return "";
}

async function reloadActivePageForExperiment() {
  const page = activePageKey();
  const clinicalMode = window._emp.activeDataKind === "clinical";
  const chipMode = window._emp.activeDataKind === "chipseq";
  if (page === "summary") await loadSummary();
  if (page === "inspector") await loadInspector();
  if (page === "preparation" && !clinicalMode && !chipMode) {
    await ensureGroupSelectors({ force: true });
    if (window._emp.currentExp) await refreshPrepareSnapshots();
  }
  if ((page === "analysis" || page === "visualization" || page === "runall") && !clinicalMode && !chipMode) {
    await ensureGroupSelectors({ force: true });
  }
  if (page === "clinical" || clinicalMode) await refreshClinicalVars();
  if ((page === "analysis" || page === "chipseq") && chipMode) {
    refreshChipPeakStatus();
  }
  if (page === "export" && !clinicalMode && !chipMode) {
    await ensureGroupSelectors({ force: true, background: true });
  }
  notifyCodeLabNavigate(page || "import");
}

// ── Per-experiment UI result snapshots ─────────────────────────────
// When switching omics experiments, keep analysis/viz/prep plots & tables so
// multi-omics homework is not wiped. Prepare-data snapshots (RDS) are separate.
const UI_SNAP_RESULT_ROOTS = [
  "#page-analysis",
  "#page-chipseq",
  "#page-chipseq_downstream",
  "#page-visualization",
  "#page-preparation",
  "#page-clinical",
  "#page-runall",
  "#page-export",
];
const UI_SNAP_FIXED_IDS = [
  "summary-stats", "summary-coldata", "summary-features",
  "inspector-stats", "inspector-assay-table", "inspector-coldata-table",
  "inspector-rowdata-table", "inspector-result-table",
  "import-result",
];

function uiSnapshotStorageKey() {
  const sid = localStorage.getItem("emp_session_id") || "nosession";
  return `emp_ui_result_snaps_v1_${sid}`;
}

function uiSnapshotLabel(key) {
  if (isClinicalStandaloneToken(key)) return "Clinical / Phenotype";
  if (isChipStandaloneToken(key)) return "ChIP-seq (peaks)";
  return key || "(unknown)";
}

function persistUiSnapshotsToStorage() {
  try {
    const payload = {
      version: 1,
      savedAt: new Date().toISOString(),
      byKey: window._emp.uiSnapshots || {},
    };
    sessionStorage.setItem(uiSnapshotStorageKey(), JSON.stringify(payload));
  } catch (_) {
    // quota / private mode — keep in-memory only
  }
}

function loadUiSnapshotsFromStorage() {
  try {
    const raw = sessionStorage.getItem(uiSnapshotStorageKey());
    if (!raw) return;
    const payload = JSON.parse(raw);
    if (payload?.byKey && typeof payload.byKey === "object") {
      window._emp.uiSnapshots = { ...(window._emp.uiSnapshots || {}), ...payload.byKey };
    }
  } catch (_) { /* ignore */ }
}

function collectResultAreaSnapshot(rootSel) {
  const root = document.querySelector(rootSel);
  if (!root) return { areas: {}, activeTab: null };
  const areas = {};
  root.querySelectorAll(".result-area[id]").forEach((el) => {
    const html = el.innerHTML || "";
    if (!html.trim()) return;
    areas[el.id] = {
      html,
      hidden: el.classList.contains("hidden"),
    };
  });
  const activeTab = root.querySelector(".tab-bar .tab.active")?.dataset?.tab || null;
  return { areas, activeTab };
}

function snapshotHasContent(snap) {
  if (!snap?.pages) return false;
  return Object.values(snap.pages).some((p) => p?.areas && Object.keys(p.areas).length > 0);
}

function currentUiSnapshotKey() {
  if (window._emp.uiSnapshotActiveKey) return window._emp.uiSnapshotActiveKey;
  if (window._emp.activeDataKind === "clinical" || isClinicalStandaloneToken(window._emp.currentExp)) {
    return CLINICAL_STANDALONE_TOKEN;
  }
  if (window._emp.activeDataKind === "chipseq" || isChipStandaloneToken(window._emp.currentExp)) {
    return CHIP_STANDALONE_TOKEN;
  }
  const ge = document.getElementById("global-experiment")?.value;
  if (isClinicalStandaloneToken(ge)) return CLINICAL_STANDALONE_TOKEN;
  if (isChipStandaloneToken(ge)) return CHIP_STANDALONE_TOKEN;
  return window._emp.currentExp || ge || null;
}

let _uiSnapNoteTimer = null;
/** Debounced capture after plots/tables land in the DOM. */
function noteUiResultChanged() {
  const key = currentUiSnapshotKey();
  if (!key) return;
  if (!window._emp.uiSnapshotActiveKey) window._emp.uiSnapshotActiveKey = key;
  clearTimeout(_uiSnapNoteTimer);
  _uiSnapNoteTimer = setTimeout(() => {
    _uiSnapNoteTimer = null;
    captureUiSnapshot(key);
  }, 220);
}

function captureUiSnapshot(key) {
  if (!key) return false;
  const pages = {};
  UI_SNAP_RESULT_ROOTS.forEach((sel) => {
    const pageKey = sel.replace("#page-", "");
    pages[pageKey] = collectResultAreaSnapshot(sel);
  });
  // Fixed containers outside generic result-area scans
  const fixed = {};
  UI_SNAP_FIXED_IDS.forEach((id) => {
    const el = document.getElementById(id);
    if (!el) return;
    const html = el.innerHTML || "";
    if (!html.trim()) return;
    fixed[id] = { html, hidden: el.classList.contains("hidden") };
  });
  pages._fixed = { areas: fixed };

  const snap = {
    key,
    omics: inferOmicsForExperiment(key) || window._emp.activeDataKind || "",
    updatedAt: new Date().toISOString(),
    pages,
  };
  if (!snapshotHasContent(snap)) return false;
  window._emp.uiSnapshots[key] = snap;
  persistUiSnapshotsToStorage();
  updateUiSnapshotBadges();
  return true;
}

function clearUiResultPanes() {
  UI_SNAP_RESULT_ROOTS.forEach((sel) => {
    document.querySelectorAll(`${sel} .result-area`).forEach((el) => {
      el.innerHTML = "";
      el.classList.add("hidden");
    });
  });
  UI_SNAP_FIXED_IDS.forEach((id) => {
    if (id === "import-result") return; // keep last import status message
    const el = document.getElementById(id);
    if (el) el.innerHTML = "";
  });
}

function restoreUiSnapshot(key) {
  if (!key) return false;
  loadUiSnapshotsFromStorage();
  const snap = window._emp.uiSnapshots?.[key];
  if (!snapshotHasContent(snap)) return false;

  Object.entries(snap.pages || {}).forEach(([pageKey, pageSnap]) => {
    if (pageKey === "_fixed") {
      Object.entries(pageSnap.areas || {}).forEach(([id, meta]) => {
        const el = document.getElementById(id);
        if (!el || id === "import-result") return;
        el.innerHTML = meta.html || "";
        el.classList.toggle("hidden", !!meta.hidden && !(meta.html || "").trim());
      });
      return;
    }
    const root = document.getElementById(`page-${pageKey}`);
    if (!root) return;
    Object.entries(pageSnap.areas || {}).forEach(([id, meta]) => {
      const el = document.getElementById(id);
      if (!el) return;
      el.innerHTML = meta.html || "";
      if ((meta.html || "").trim()) el.classList.remove("hidden");
      else el.classList.toggle("hidden", !!meta.hidden);
    });
    if (pageSnap.activeTab) {
      const tabBtn = root.querySelector(`.tab-bar .tab[data-tab="${pageSnap.activeTab}"]`);
      if (tabBtn) tabBtn.click();
    }
  });
  updateUiSnapshotBadges();
  return true;
}

function updateUiSnapshotBadges() {
  const keys = Object.keys(window._emp.uiSnapshots || {}).filter((k) =>
    snapshotHasContent(window._emp.uiSnapshots[k])
  );
  let host = document.getElementById("ui-snap-status");
  if (!host) {
    const wrap = document.getElementById("exp-selector-wrap");
    if (!wrap) return;
    host = document.createElement("span");
    host.id = "ui-snap-status";
    host.className = "hint ui-snap-status";
    wrap.appendChild(host);
  }
  if (!keys.length) {
    host.textContent = "";
    host.classList.add("hidden");
    return;
  }
  host.classList.remove("hidden");
  host.title = keys.map(uiSnapshotLabel).join(", ");
  host.textContent = `Snapshots: ${keys.length} experiment(s)`;
}

async function onGlobalExperimentChange(expName) {
  const next = String(expName || "").trim();
  const clinicalMode = isClinicalStandaloneToken(next);
  const chipMode = isChipStandaloneToken(next);
  const nextKey = clinicalMode
    ? CLINICAL_STANDALONE_TOKEN
    : chipMode
      ? CHIP_STANDALONE_TOKEN
      : next;
  const prevKey = window._emp.uiSnapshotActiveKey
    || (window._emp.activeDataKind === "clinical" ? CLINICAL_STANDALONE_TOKEN : null)
    || (window._emp.activeDataKind === "chipseq" ? CHIP_STANDALONE_TOKEN : null)
    || window._emp.currentExp
    || null;

  // Flush pending debounced capture so a just-rendered plot is not lost.
  if (_uiSnapNoteTimer) {
    clearTimeout(_uiSnapNoteTimer);
    _uiSnapNoteTimer = null;
  }

  // Save previous experiment's plots/tables before wiping the panes.
  if (prevKey && prevKey !== nextKey) {
    if (captureUiSnapshot(prevKey)) {
      toast(`Saved result snapshot · ${uiSnapshotLabel(prevKey)}`, "info");
    }
  }
  clearUiResultPanes();

  if (clinicalMode) {
    window._emp.activeDataKind = "clinical";
    if (window._emp.currentExp && isClinicalStandaloneToken(window._emp.currentExp)) {
      window._emp.currentExp = null;
    }
    const sourceSel = document.getElementById("clin-data-source");
    if (sourceSel) sourceSel.value = "standalone";
    try {
      window.dispatchEvent(new CustomEvent("emp:omics-change", { detail: { omics: "clinical" } }));
    } catch (_) { /* no-op */ }

    setLoading(true);
    try {
      await probeStandaloneClinical();
      window._emp.uiSnapshotActiveKey = CLINICAL_STANDALONE_TOKEN;
      const restored = restoreUiSnapshot(CLINICAL_STANDALONE_TOKEN);
      const page = activePageKey();
      if (restored) {
        toast(`Restored result snapshot · ${uiSnapshotLabel(CLINICAL_STANDALONE_TOKEN)}`, "success");
        if (["analysis", "preparation", "visualization", "inspector", "runall"].includes(page)) {
          navigateTo("clinical");
        } else if (page === "clinical") {
          await refreshClinicalVars();
        } else if (page === "summary") {
          // keep restored summary if present; otherwise load
          if (!document.getElementById("summary-stats")?.innerHTML?.trim()) await loadSummary();
        }
      } else if (["analysis", "preparation", "visualization", "inspector", "runall"].includes(page)) {
        navigateTo("clinical");
      } else {
        await reloadActivePageForExperiment();
      }
      try {
        window.dispatchEvent(new CustomEvent("emp:experiment-change", {
          detail: { experiment: CLINICAL_STANDALONE_TOKEN, omics: "clinical", page: activePageKey() },
        }));
      } catch (_) { /* no-op */ }
    } finally {
      setLoading(false);
    }
    return;
  }

  if (chipMode) {
    window._emp.activeDataKind = "chipseq";
    if (window._emp.currentExp && isChipStandaloneToken(window._emp.currentExp)) {
      window._emp.currentExp = null;
    }
    try {
      window.dispatchEvent(new CustomEvent("emp:omics-change", { detail: { omics: "chipseq" } }));
    } catch (_) { /* no-op */ }

    setLoading(true);
    try {
      await probeStandaloneChipPeaks();
      window._emp.uiSnapshotActiveKey = CHIP_STANDALONE_TOKEN;
      const restored = restoreUiSnapshot(CHIP_STANDALONE_TOKEN);
      if (restored) {
        toast(`Restored result snapshot · ${uiSnapshotLabel(CHIP_STANDALONE_TOKEN)}`, "success");
      }
      openChipseqWorkspace();
      try {
        window.dispatchEvent(new CustomEvent("emp:experiment-change", {
          detail: { experiment: CHIP_STANDALONE_TOKEN, omics: "chipseq", page: activePageKey() },
        }));
      } catch (_) { /* no-op */ }
    } finally {
      setLoading(false);
    }
    return;
  }

  window._emp.activeDataKind = "experiment";
  window._emp.currentExp = next || null;
  if (next) invalidateExperimentCache(next);

  const omics = inferOmicsForExperiment(next);
  if (omics) {
    try {
      window.dispatchEvent(new CustomEvent("emp:omics-change", { detail: { omics } }));
    } catch (_) { /* no-op */ }
  }

  setLoading(true);
  try {
    await refreshGroupSelectors({ force: true });
    window._emp.uiSnapshotActiveKey = nextKey;
    const restored = restoreUiSnapshot(nextKey);
    if (restored) {
      toast(`Restored result snapshot · ${uiSnapshotLabel(nextKey)}`, "success");
      await refreshPrepareSnapshots();
      // If summary/inspector empty after restore, refill from API.
      const page = activePageKey();
      if (page === "summary" && !document.getElementById("summary-stats")?.innerHTML?.trim()) {
        await loadSummary();
      }
      if (page === "inspector" && !document.getElementById("inspector-stats")?.innerHTML?.trim()) {
        await loadInspector();
      }
      if (page === "clinical") await refreshClinicalVars();
    } else {
      await reloadActivePageForExperiment();
    }
    try {
      window.dispatchEvent(new CustomEvent("emp:experiment-change", {
        detail: { experiment: next, omics: omics || null, page: activePageKey(), restored },
      }));
    } catch (_) { /* no-op */ }
  } finally {
    setLoading(false);
  }
}

globalExp.addEventListener("change", () => {
  clearTimeout(_groupRefreshDebounce);
  _groupRefreshDebounce = setTimeout(() => {
    onGlobalExperimentChange(globalExp.value);
  }, 80);
});

const EXP_CACHE_TTL_MS = 5 * 60 * 1000;
const FEATURE_DROPDOWN_LIMIT = 500;

function invalidateExperimentCache(exp = null) {
  if (!exp) {
    window._emp.expCache = {};
    return;
  }
  delete window._emp.expCache[exp];
}

function experimentCacheFresh(exp) {
  const c = window._emp.expCache?.[exp];
  return !!(c && (Date.now() - (c.fetchedAt || 0) < EXP_CACHE_TTL_MS));
}

function applyGroupSelectorDom() {
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

  const featureSelectors = ["bar-feature","box-feature"];
  const feats = (window._emp.features || []).slice(0, FEATURE_DROPDOWN_LIMIT);
  featureSelectors.forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    el.innerHTML = feats.map(f => `<option value="${f}">${f}</option>`).join("");
    if (window._emp.featuresN > feats.length) {
      el.title = `Showing ${feats.length} of ${window._emp.featuresN} features`;
    }
  });

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
  bindGroupChange("scat-group", updateScatGroupFilter);
  bindGroupChange("diff-method", updateDiffComparisonUI);
  bindGroupChange("diff-comparison-mode", updateDiffComparisonUI);
  updateDiffGroups();
  updateMarkerGroups();
  updateMgxGroups();
  updateMbxGroups();
  updateTxGroups();
  updateRaGroups();
  updateScatGroupFilter();
}

function ensureGroupSelectors({ force = false, background = false } = {}) {
  const exp = window._emp.currentExp;
  if (!exp) return Promise.resolve();
  if (!force && experimentCacheFresh(exp)) {
    const c = window._emp.expCache[exp];
    window._emp.coldataCols = c.coldataCols || [];
    window._emp.features = c.features || [];
    window._emp.featuresN = c.featuresN || window._emp.features.length;
    applyGroupSelectorDom();
    return Promise.resolve();
  }
  return refreshGroupSelectors({ force, background });
}

async function refreshGroupSelectors({ force = false, background = false } = {}) {
  const exp = window._emp.currentExp;
  if (!exp) return;

  if (!force && experimentCacheFresh(exp)) {
    const c = window._emp.expCache[exp];
    window._emp.coldataCols = c.coldataCols || [];
    window._emp.features = c.features || [];
    window._emp.featuresN = c.featuresN || window._emp.features.length;
    applyGroupSelectorDom();
    return;
  }

  const inflight = window._emp._groupRefreshInflight;
  if (inflight?.exp === exp && !force) {
    await inflight.promise;
    return;
  }

  const run = (async () => {
    const cd = await API.getColdata(exp);
    const ft = await API.getFeatures(exp, { limit: FEATURE_DROPDOWN_LIMIT });
    window._emp.coldataCols = cd.columns || [];
    window._emp.features = ft.features || [];
    window._emp.featuresN = ft.n_total ?? window._emp.features.length;
    window._emp.expCache[exp] = {
      coldataCols: window._emp.coldataCols,
      features: window._emp.features,
      featuresN: window._emp.featuresN,
      fetchedAt: Date.now(),
    };
    applyGroupSelectorDom();
  })();

  window._emp._groupRefreshInflight = { exp, promise: run };
  try {
    await run;
  } catch (e) {
    if (!background) console.warn("refreshGroupSelectors:", e.message);
  } finally {
    if (window._emp._groupRefreshInflight?.promise === run) {
      window._emp._groupRefreshInflight = null;
    }
  }
}

async function probeStandaloneClinical() {
  let sc = window._emp.standaloneClinical;
  if (sc?.columns?.length) return sc;
  try {
    const sv = await API.clinicalVarsStandalone();
    const rows = Array.isArray(sv?.data) ? sv.data : [];
    if (rows.length) {
      sc = {
        columns: rows.map((r) => r.name),
        orientation: "samples in rows",
        n_variables: rows.length,
      };
      window._emp.standaloneClinical = sc;
      return sc;
    }
  } catch (_) {
    // no standalone clinical table in this session
  }
  return null;
}

function renderStandaloneClinicalCard(sc) {
  const n = (sc.columns || []).length;
  return `
    <div class="exp-card exp-card-clinical" data-clinical-standalone="1">
      <h4>🩺 Clinical / Phenotype (session)</h4>
      <div class="meta">${n} variables · session-level table</div>
      <div class="meta">Orientation: ${sc.orientation || "samples in rows"}</div>
      <div class="meta hint">Not an omics assay — open Clinical &amp; Phenotype to analyze.</div>
      <button type="button" class="btn btn-outline btn-sm" data-goto-clinical>Open Clinical page</button>
    </div>
  `;
}

function bindClinicalCardActions(root) {
  root?.querySelectorAll("[data-goto-clinical]").forEach((btn) => {
    btn.addEventListener("click", () => {
      if (globalExp && [...globalExp.options].some((o) => o.value === CLINICAL_STANDALONE_TOKEN)) {
        globalExp.value = CLINICAL_STANDALONE_TOKEN;
      }
      onGlobalExperimentChange(CLINICAL_STANDALONE_TOKEN);
    });
  });
}

/** Session-level ChIP peaks (BED upload / MACS) — mirror clinical standalone. */
async function probeStandaloneChipPeaks() {
  let peaks = window._emp.chipLastPeaks;
  if (peaks?.peak_file) return peaks;
  try {
    const res = await API.chipListBams();
    if (res?.last_peaks?.peak_file) {
      adoptChipLastPeaks({
        ...(res.last_peaks || {}),
        peak_file: res.last_peaks.peak_file,
      });
      return window._emp.chipLastPeaks;
    }
  } catch (_) {
    // no chip session / peaks yet
  }
  return null;
}

function renderStandaloneChipCard(peaks) {
  const name = chipPeakDisplayName(peaks) || "peaks";
  const src = peaks?.source === "preimported"
    ? "pre-called BED"
    : (peaks?.source || "peaks");
  const genome = peaks?.genome ? ` · genome ${peaks.genome}` : "";
  return `
    <div class="exp-card exp-card-chipseq" data-chipseq-standalone="1">
      <h4>🧶 ChIP-seq (peaks)</h4>
      <div class="meta">${escapeHtml(name)} · session-level peaks</div>
      <div class="meta">${escapeHtml(src)}${escapeHtml(genome)}</div>
      <div class="meta hint">Not an MAE assay — open Analysis → ChIP-seq to annotate.</div>
      <button type="button" class="btn btn-outline btn-sm" data-goto-chipseq>Open ChIP-seq</button>
    </div>
  `;
}

function bindChipCardActions(root) {
  root?.querySelectorAll("[data-goto-chipseq]").forEach((btn) => {
    btn.addEventListener("click", () => {
      if (globalExp && [...globalExp.options].some((o) => o.value === CHIP_STANDALONE_TOKEN)) {
        globalExp.value = CHIP_STANDALONE_TOKEN;
      }
      onGlobalExperimentChange(CHIP_STANDALONE_TOKEN);
    });
  });
}

async function refreshExperimentList() {
  try {
    const prevKey = (window._emp.experiments || []).map((e) => e.name).join("|");
    const exps = await API.listExperiments();
    const nextKey = (exps || []).map((e) => e.name).join("|");
    if (prevKey !== nextKey) invalidateExperimentCache();
    window._emp.experiments = exps;
    const cards = document.getElementById("exp-cards");
    const sc = await probeStandaloneClinical();
    const chip = await probeStandaloneChipPeaks();

    const keepClinical =
      window._emp.activeDataKind === "clinical" ||
      isClinicalStandaloneToken(globalExp?.value);
    const keepChip =
      window._emp.activeDataKind === "chipseq" ||
      isChipStandaloneToken(globalExp?.value);
    const preferred = keepClinical
      ? CLINICAL_STANDALONE_TOKEN
      : keepChip
        ? CHIP_STANDALONE_TOKEN
        : window._emp.currentExp;

    if (!exps.length) {
      if (sc || chip) {
        fillGlobalExperimentSelect([], sc, preferred, chip);
        if (cards) {
          cards.innerHTML =
            (chip ? renderStandaloneChipCard(chip) : "") +
            (sc ? renderStandaloneClinicalCard(sc) : "");
          bindClinicalCardActions(cards);
          bindChipCardActions(cards);
        }
        document.getElementById("import-experiments").classList.remove("hidden");
        document.getElementById("session-badge")?.classList.remove("hidden");
      } else {
        window._emp.currentExp = null;
        window._emp.activeDataKind = "experiment";
        if (globalExp) globalExp.innerHTML = "";
        document.getElementById("exp-selector-wrap")?.classList.add("hidden");
        document.getElementById("import-experiments").classList.add("hidden");
      }
      return;
    }

    // Global selector: omics experiments + clinical / ChIP session entries when present
    fillGlobalExperimentSelect(exps, sc, preferred, chip);
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
    const chipRnaseq = document.getElementById("chip-rnaseq-exp");
    const chipCrossRna = document.getElementById("chip-cross-rnaseq");
    const chipCrossPro = document.getElementById("chip-cross-proteomics");
    const expOpts = exps.map(e => `<option value="${e.name}">${e.name}${e.omics ? ` (${e.omics})` : ""}</option>`).join("");
    if (chipRnaseq) {
      chipRnaseq.innerHTML = expOpts;
      if (window._emp.currentExp) chipRnaseq.value = window._emp.currentExp;
    }
    if (chipCrossRna) {
      chipCrossRna.innerHTML = `<option value="">— none —</option>${expOpts}`;
      if (window._emp.currentExp) chipCrossRna.value = window._emp.currentExp;
    }
    if (chipCrossPro) {
      chipCrossPro.innerHTML = `<option value="">— none —</option>${expOpts}`;
    }
    fillChipRecipeDepSelects(exps);

    // Import page cards: omics experiments + optional standalone clinical / ChIP
    const omicsCards = exps.map(e => `
      <div class="exp-card">
        <h4>${e.name}</h4>
        <div class="meta">${e.samples} samples · ${e.features} features</div>
        <div class="meta">Assay: ${e.assay}${e.omics ? ` · ${e.omics}` : ""}</div>
      </div>
    `).join("");
    cards.innerHTML =
      omicsCards +
      (chip ? renderStandaloneChipCard(chip) : "") +
      (sc ? renderStandaloneClinicalCard(sc) : "");
    bindClinicalCardActions(cards);
    bindChipCardActions(cards);
    document.getElementById("import-experiments").classList.remove("hidden");

    // Session badge
    document.getElementById("session-badge").classList.remove("hidden");

    if (window._emp.activeDataKind !== "clinical" && window._emp.activeDataKind !== "chipseq") {
      await refreshGroupSelectors();
      await refreshPrepareSnapshots();
    }
  } catch (e) {
    // Common case: clinical/chip-only session has no MAE experiments.
    // Try standalone fallbacks before showing failure state.
    const cards = document.getElementById("exp-cards");
    try {
      const sc = await probeStandaloneClinical();
      const chip = await probeStandaloneChipPeaks();
      if (sc || chip) {
        const keepClinical =
          window._emp.activeDataKind === "clinical" ||
          isClinicalStandaloneToken(globalExp?.value);
        const keepChip =
          window._emp.activeDataKind === "chipseq" ||
          isChipStandaloneToken(globalExp?.value);
        const preferred = keepClinical
          ? CLINICAL_STANDALONE_TOKEN
          : keepChip
            ? CHIP_STANDALONE_TOKEN
            : null;
        fillGlobalExperimentSelect([], sc, preferred, chip);
        if (cards) {
          cards.innerHTML =
            (chip ? renderStandaloneChipCard(chip) : "") +
            (sc ? renderStandaloneClinicalCard(sc) : "");
          bindClinicalCardActions(cards);
          bindChipCardActions(cards);
        }
        document.getElementById("import-experiments").classList.remove("hidden");
        document.getElementById("session-badge")?.classList.remove("hidden");
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

// ── Multi-omics parallel upload cards ──────────────────────────────
// Each `data-upload-type` card has its own data file, metadata file,
// experiment name.  Hitting `Upload …` POSTs to /api/import with the
// matching data_type, appending a new MAE experiment to the same session.
const UPLOAD_TYPE_MAP = {
  transcriptomics: "normal",
  microbiome_16s:  "tax",
  metabolomics:    "normal",
  metagenomics:    "normal",
  proteomics:      "normal",
  chipseq:         "chipseq",
  clinical:        "clinical",
};

function syncUploadCardMode(card) {
  if (!card) return;
  const mode = card.querySelector(".upload-import-mode")?.value || "matrix";
  const isDiff = mode === "diff_raw";
  card.classList.toggle("upload-card--diff", isDiff);
  card.querySelectorAll(".upload-matrix-only").forEach((el) => el.classList.toggle("hidden", isDiff));
  card.querySelectorAll(".upload-diff-only").forEach((el) => el.classList.toggle("hidden", !isDiff));
  const type = card.dataset.uploadType;
  const short = ({
    transcriptomics: "tx", proteomics: "pro", microbiome_16s: "m16s",
    metagenomics: "mgx", metabolomics: "mbx",
  })[type];
  const label = card.querySelector(".upload-data-label");
  if (label && short) {
    label.textContent = isDiff ? t("upload.dataLabel.diff") : t(`upload.dataLabel.${short}`);
  }
  const btn = card.querySelector(".upload-btn");
  if (btn && short) {
    const icon = btn.querySelector("i")?.outerHTML || "";
    const key = isDiff ? `upload.btnDiff.${short}` : `upload.btn.${short}`;
    btn.innerHTML = `${icon} ${t(key)}`.trim();
  }
}

function bindUploadCard(omicsType) {
  const card = document.querySelector(`.upload-card[data-upload-type="${omicsType}"]`);
  if (!card) return;
  const dataInput = card.querySelector(".upload-data-file");
  const metaInput = card.querySelector(".upload-meta-file");
  const dataName  = card.querySelector(".data-filename");
  const metaName  = card.querySelector(".meta-filename");
  const expName   = card.querySelector(".upload-exp-name");
  const modeSel   = card.querySelector(".upload-import-mode");
  const btn       = card.querySelector(".upload-btn");
  if (!dataInput || !btn) return;

  if (!btn.dataset.labelMatrixKey) {
    const short = ({
      transcriptomics: "tx", proteomics: "pro", microbiome_16s: "m16s",
      metagenomics: "mgx", metabolomics: "mbx", clinical: "clinical",
    })[omicsType];
    if (short) {
      btn.dataset.labelMatrixKey = `upload.btn.${short}`;
      if (short !== "clinical") btn.dataset.labelDiffKey = `upload.btnDiff.${short}`;
    }
  }
  modeSel?.addEventListener("change", () => syncUploadCardMode(card));
  syncUploadCardMode(card);

  dataInput.addEventListener("change", () => {
    const f = dataInput.files[0];
    if (dataName) dataName.textContent = f?.name || "";
    if (f && expName && !expName.dataset.touched) {
      const base = f.name.replace(/\.[^.]+$/, "").replace(/[^A-Za-z0-9_]/g, "_");
      expName.value = base || expName.value;
    }
    if (expName) expName.dataset.touched = "1";
  });
  expName?.addEventListener("input", () => {
    if (expName) expName.dataset.touched = "1";
  });
  metaInput?.addEventListener("change", () => {
    if (metaName) metaName.textContent = metaInput.files[0]?.name || "";
  });

  bindUploadDropZoneForCard(card);

  btn.addEventListener("click", async () => {
    const dataFile = dataInput.files[0];
    if (!dataFile) {
      toast(t("import.noDataFile"), "error");
      return;
    }
    const importMode = modeSel?.value || "matrix";
    const fd = new FormData();
    fd.append("data_file", dataFile);
    fd.append("experiment_name", expName?.value || omicsType);

    setLoading(true);
    try {
      if (!localStorage.getItem("emp_session_id")) await API.createSession();
      let res;
      if (importMode === "diff_raw") {
        res = await withBusy(`Importing DE (${omicsType})`, () => API.importDiffRaw(fd));
        showAlert("import-result",
          `✓ DE results cached for "${res.experiment_name}": ${res.features} features. ${res.message || "Ready for ChIP joint packs."}`,
          "success");
        toast(`${res.experiment_name}: diff_raw cached`, "success");
        window._emp.standaloneClinical = null;
      } else {
        const dataType = UPLOAD_TYPE_MAP[omicsType] || "normal";
        fd.append("data_type", omicsType === "clinical"
          ? (card.querySelector(".upload-clinical-kind")?.value || "clinical_raw")
          : dataType);
        fd.append("assay_name", card.querySelector(".upload-assay-name")?.value || "counts");
        fd.append("start_level", card.querySelector(".upload-start-level")?.value || "Species");
        fd.append("tax_sep", card.querySelector(".upload-tax-sep")?.value || ";");
        if (metaInput?.files[0]) fd.append("metadata_file", metaInput.files[0]);
        res = await withBusy(`Importing ${omicsType}`, () => API.importData(fd));
        if (res.import_mode === "clinical_merge" || res.import_mode === "clinical_standalone") {
          const modeMsg = res.import_mode === "clinical_standalone"
            ? "No direct sample-ID overlap found; saved as session-level clinical table. Select it in ChIP Step2 joint packs."
            : `Merged into ${res.updated_experiments} experiment(s). Usable in ChIP Peak × Clinical packs.`;
          showAlert("import-result",
            `✓ Clinical/phenotype upload done. ${modeMsg} Columns: ${(res.columns || []).join(", ")}.`,
            "success");
          toast("Clinical metadata uploaded successfully.", "success");
          if (res.import_mode === "clinical_standalone") {
            window._emp.standaloneClinical = {
              columns: res.columns || [],
              orientation: res.orientation || "samples in rows",
            };
            try {
              window.dispatchEvent(new CustomEvent("emp:omics-change", { detail: { omics: "clinical" } }));
            } catch (_) { /* no-op */ }
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
      }
      await refreshExperimentList();
    } catch (e) {
      showAlert("import-result", `Error: ${e.message}`, "error");
      toast(e.message, "error");
    } finally {
      setLoading(false);
    }
  });
}

function bindUploadDropZoneForCard(card) {
  const zones = card.querySelectorAll(".upload-zone");
  zones.forEach((zone) => {
    const input = zone.querySelector('input[type="file"]');
    if (!input) return;
    zone.addEventListener("dragover", (e) => {
      e.preventDefault();
      zone.classList.add("upload-zone-hot");
    });
    zone.addEventListener("dragleave", () => zone.classList.remove("upload-zone-hot"));
    zone.addEventListener("drop", (e) => {
      e.preventDefault();
      zone.classList.remove("upload-zone-hot");
      const file = e.dataTransfer?.files?.[0];
      if (!file) return;
      const dt = new DataTransfer();
      dt.items.add(file);
      input.files = dt.files;
      input.dispatchEvent(new Event("change", { bubbles: true }));
    });
  });
}

["transcriptomics", "proteomics", "microbiome_16s", "metagenomics", "metabolomics", "clinical"]
  .forEach(bindUploadCard);

function bindChipseqUploadCard() {
  const card = document.querySelector(`.upload-card[data-upload-type="chipseq"]`);
  if (!card) return;
  const dataInput = card.querySelector(".upload-data-file");
  const dataName  = card.querySelector(".data-filename");
  const expName   = card.querySelector(".upload-exp-name");
  const genomeSel = card.querySelector(".upload-genome");
  const presetSel = card.querySelector(".upload-preset");
  const btn       = card.querySelector(".upload-btn");
  if (!btn) return;

  dataInput?.addEventListener("change", () => {
    const f = dataInput.files?.[0];
    if (dataName) dataName.textContent = f?.name || "";
    if (f && expName && !expName.dataset.touched) {
      const base = f.name.replace(/\.[^.]+$/, "").replace(/[^A-Za-z0-9_]/g, "_");
      expName.value = base || expName.value || "chipseq_peaks";
    }
    if (expName) expName.dataset.touched = "1";
  });
  bindUploadDropZoneForCard(card);

  btn.addEventListener("click", async () => {
    const file = dataInput?.files?.[0];
    if (!file) { toast("Choose a peak file first (.bed / .narrowPeak / .broadPeak / .gff).", "error"); return; }
    setLoading(true);
    try {
      if (!localStorage.getItem("emp_session_id")) await API.createSession();
      const genome = genomeSel?.value || "mm";
      const preset = presetSel?.value || "cutrun_tf_p05";
      const res = await withBusy("Uploading pre-called peaks",
        () => API.chipUploadPeaks(file, genome, preset));
      const annoEl = document.getElementById("chip-anno-genome");
      if (annoEl) delete annoEl.dataset.userSet;
      syncChipAnnoFromPeakGenome(res.genome || genome, { force: true });
      window._emp.chipLastPeaks = {
        peak_file: res.peak_file,
        run_dir: res.run_dir,
        genome: res.genome || genome,
        preset: res.preset || preset,
        source: "preimported",
        format_hint: res.format_hint,
        display_name: file.name,
      };
      window._emp.activeDataKind = "chipseq";
      showAlert("import-result",
        `✓ Peak file uploaded (${file.name}). This is a MACS-style peak product — ChIPseeker can annotate it directly (no BAM / re-calling needed).`,
        "success");
      toast("Peaks ready — annotate with ChIPseeker.", "success");
      await refreshExperimentList();
      if (globalExp && [...globalExp.options].some((o) => o.value === CHIP_STANDALONE_TOKEN)) {
        globalExp.value = CHIP_STANDALONE_TOKEN;
      }
      openChipseqWorkspace();
      refreshChipPeakStatus(file.name);
    } catch (e) {
      showAlert("import-result", `Error: ${e.message}`, "error");
      toast(e.message, "error");
    } finally {
      setLoading(false);
    }
  });
}
bindChipseqUploadCard();

document.getElementById("btn-go-chipseq")?.addEventListener("click", () => {
  openChipseqWorkspace();
});
document.getElementById("btn-ana-open-chipseq")?.addEventListener("click", () => {
  openChipseqWorkspace();
});
document.getElementById("btn-ana-open-chipseq-downstream")?.addEventListener("click", () => {
  navigateTo("chipseq_downstream");
});
document.getElementById("btn-chipseq-goto-downstream")?.addEventListener("click", () => {
  navigateTo("chipseq_downstream");
});
document.getElementById("chip-btn-goto-step2-b")?.addEventListener("click", () => {
  setChipWizardStep("2");
});

// Direct upload of pre-called peaks (skip MACS) – handled by the chip card below
async function uploadChipseqPeaks(sid, file, genome = "mm", preset = "cutrun_tf_p05") {
  return API.chipUploadPeaks(file, genome, preset);
}

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
        try {
          window.dispatchEvent(new CustomEvent("emp:omics-change", { detail: { omics: "clinical" } }));
        } catch (_) { /* no-op */ }
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
      invalidateExperimentCache(exp);
      refreshPrepareSnapshots();
      refreshGroupSelectors({ force: true, background: true });
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
      noteUiResultChanged();
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
    noteUiResultChanged();
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
    noteUiResultChanged();
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

// ── ChIP-seq WORKFLOW ─────────────────────────────
const CHIP_MACS_PRESET_HINTS = {
  cutrun_tf_p05: "Lab TF Cut&Run (Nr4a1/HA vs IgG): pool all BAM -t vs -c, -f BAMPE -p 0.05 -g 1.87e9 -B.",
  cutrun_tf_p01: "Stricter TF Cut&Run: BAMPE -p 0.01 -g 1.87e9 -B.",
  cutrun_histone_p05: "Lab histone Cut&Run (same recipe as TF): BAMPE -p 0.05 -B — not --broad.",
  cutrun_histone_p01: "Stricter histone Cut&Run: BAMPE -p 0.01 -g 1.87e9 -B.",
  atac_bampe_p05: "ATAC PE lab-style: -f BAMPE -p 0.05 -g 1.87e9 -B; optional IgG/input as -c.",
  atac_bampe_q05: "ATAC PE with FDR: -f BAMPE -q 0.05 -g 1.87e9 -B.",
  cutrun_pe_p05: "Alias of TF Cut&Run p=0.05.",
  cutrun_pe_p01: "Alias of TF Cut&Run p=0.01.",
  histone_broad: "Optional broad domains (--broad). Lab histone Cut&Run default is cutrun_histone_p05.",
  chipseq_tf: "Classic SE ChIP-seq TF: -f BAM -q 0.01. Not for Cut&Run.",
  chipseq_histone_broad: "Legacy SE broad histone. Prefer cutrun_histone_p05 or histone_broad.",
  atac_paired: "Alias of ATAC BAMPE q=0.05.",
  atac_cutting_site: "Cutting-site mode: --nomodel --shift -75 --extsize 150 --keep-dup all.",
  cuttag_tn5: "MACS3 CUT&Tag example: --nomodel --shift -50 --extsize 100.",
  dnase_smoothed: "DNase smoothing window: --nomodel --shift -100 --extsize 200.",
  no_control: "Treatment only (no -c). Optional --nolambda; use with caution.",
  custom: "Manually set all MACS parameters below.",
};

const CHIP_MACS_PRESET_VALUES = {
  cutrun_tf_p05: { format: "BAMPE", cutoff_type: "p", pvalue: 0.05, keep_dup: "auto", broad: false, nomodel: false, call_summits: false, nolambda: false, save_bdg: true, gsize: "1.87e9" },
  cutrun_tf_p01: { format: "BAMPE", cutoff_type: "p", pvalue: 0.01, keep_dup: "auto", broad: false, nomodel: false, call_summits: false, nolambda: false, save_bdg: true, gsize: "1.87e9" },
  cutrun_histone_p05: { format: "BAMPE", cutoff_type: "p", pvalue: 0.05, keep_dup: "auto", broad: false, nomodel: false, call_summits: false, nolambda: false, save_bdg: true, gsize: "1.87e9" },
  cutrun_histone_p01: { format: "BAMPE", cutoff_type: "p", pvalue: 0.01, keep_dup: "auto", broad: false, nomodel: false, call_summits: false, nolambda: false, save_bdg: true, gsize: "1.87e9" },
  atac_bampe_p05: { format: "BAMPE", cutoff_type: "p", pvalue: 0.05, keep_dup: "auto", broad: false, nomodel: false, call_summits: false, nolambda: false, save_bdg: true, gsize: "1.87e9" },
  atac_bampe_q05: { format: "BAMPE", cutoff_type: "q", qvalue: 0.05, keep_dup: "auto", broad: false, nomodel: false, call_summits: false, nolambda: false, save_bdg: true, gsize: "1.87e9" },
  cutrun_pe_p05: { format: "BAMPE", cutoff_type: "p", pvalue: 0.05, keep_dup: "auto", broad: false, nomodel: false, call_summits: false, nolambda: false, save_bdg: true, gsize: "1.87e9" },
  cutrun_pe_p01: { format: "BAMPE", cutoff_type: "p", pvalue: 0.01, keep_dup: "auto", broad: false, nomodel: false, call_summits: false, nolambda: false, save_bdg: true, gsize: "1.87e9" },
  histone_broad: { format: "BAMPE", cutoff_type: "p", pvalue: 0.05, broad: true, broad_cutoff: 0.1, keep_dup: "auto", nomodel: false, save_bdg: true, gsize: "1.87e9" },
  chipseq_tf: { format: "BAM", cutoff_type: "q", qvalue: 0.01, keep_dup: "auto", broad: false, nomodel: false, call_summits: false, nolambda: false, save_bdg: false },
  chipseq_histone_broad: { format: "BAM", cutoff_type: "q", qvalue: 0.01, broad: true, broad_cutoff: 0.1, keep_dup: "auto", nomodel: false },
  atac_paired: { format: "BAMPE", cutoff_type: "q", qvalue: 0.05, keep_dup: "auto", broad: false, nomodel: false, save_bdg: true, gsize: "1.87e9" },
  atac_cutting_site: { format: "BAM", cutoff_type: "q", qvalue: 0.05, keep_dup: "all", nomodel: true, shift: -75, extsize: 150, broad: false },
  cuttag_tn5: { format: "BAM", cutoff_type: "q", qvalue: 0.01, nomodel: true, shift: -50, extsize: 100, keep_dup: "auto" },
  dnase_smoothed: { format: "BAM", cutoff_type: "q", qvalue: 0.05, nomodel: true, shift: -100, extsize: 200, keep_dup: "auto" },
  no_control: { format: "BAMPE", cutoff_type: "p", pvalue: 0.05, nolambda: true, keep_dup: "auto", save_bdg: true, gsize: "1.87e9" },
};

function chipSetField(id, value) {
  const el = document.getElementById(id);
  if (!el || value == null) return;
  if (el.type === "checkbox") el.checked = !!value;
  else el.value = String(value);
}

function applyChipMacsPreset(presetId) {
  const hint = document.getElementById("chip-macs-preset-hint");
  if (hint) hint.textContent = CHIP_MACS_PRESET_HINTS[presetId] || CHIP_MACS_PRESET_HINTS.custom;
  if (presetId === "custom") return;
  const p = CHIP_MACS_PRESET_VALUES[presetId];
  if (!p) return;
  chipSetField("chip-format", p.format);
  chipSetField("chip-cutoff-type", p.cutoff_type || "q");
  chipSetField("chip-qvalue", p.qvalue);
  chipSetField("chip-pvalue", p.pvalue);
  chipSetField("chip-keep-dup", p.keep_dup);
  chipSetField("chip-broad", p.broad);
  chipSetField("chip-broad-cutoff", p.broad_cutoff);
  chipSetField("chip-call-summits", p.call_summits);
  chipSetField("chip-nomodel", p.nomodel);
  chipSetField("chip-shift", p.shift ?? "");
  chipSetField("chip-extsize", p.extsize ?? "");
  chipSetField("chip-nolambda", p.nolambda);
  chipSetField("chip-save-bdg", p.save_bdg);
  chipSetField("chip-gsize", p.gsize ?? "");
  document.getElementById("chip-cutoff-type")?.dispatchEvent(new Event("change"));
}

function chipBool(id) {
  return document.getElementById(id)?.checked === true;
}

function chipMacsParams() {
  const cutoffType = document.getElementById("chip-cutoff-type")?.value || "q";
  const shiftVal = document.getElementById("chip-shift")?.value;
  const extVal = document.getElementById("chip-extsize")?.value;
  const tsizeVal = document.getElementById("chip-tsize")?.value;
  const minLen = document.getElementById("chip-min-length")?.value;
  const maxGap = document.getElementById("chip-max-gap")?.value;
  const slocal = document.getElementById("chip-slocal")?.value;
  const llocal = document.getElementById("chip-llocal")?.value;
  const scaleTo = document.getElementById("chip-scale-to")?.value;
  const preset = document.getElementById("chip-macs-preset")?.value || "custom";
  const broad = chipBool("chip-broad");
  // Summits are for narrow peaks; ignore when --broad is on (backend also drops it).
  const callSummits = broad ? false : chipBool("chip-call-summits");
  const params = {
    genome: document.getElementById("chip-genome")?.value || "hs",
    prefer_macs: document.getElementById("chip-prefer-macs")?.value || "auto",
    format: document.getElementById("chip-format")?.value || "BAM",
    preset: preset === "custom" ? null : preset,
    keep_dup: document.getElementById("chip-keep-dup")?.value || "auto",
    broad,
    broad_cutoff: +document.getElementById("chip-broad-cutoff")?.value || 0.1,
    call_summits: callSummits,
    save_bdg: chipBool("chip-save-bdg"),
    nomodel: chipBool("chip-nomodel"),
    fix_bimodal: chipBool("chip-fix-bimodal"),
    nolambda: chipBool("chip-nolambda"),
    cutoff_analysis: chipBool("chip-cutoff-analysis"),
    fe_cutoff: +document.getElementById("chip-fe-cutoff")?.value || 1,
    extra_args: document.getElementById("chip-extra-args")?.value?.trim() || null,
  };
  if (cutoffType === "p") {
    params.pvalue = +document.getElementById("chip-pvalue")?.value || 0.05;
  } else {
    params.qvalue = +document.getElementById("chip-qvalue")?.value || 0.01;
  }
  const gsizeVal = document.getElementById("chip-gsize")?.value?.trim();
  if (gsizeVal) params.gsize = gsizeVal;
  if (shiftVal !== "" && shiftVal != null) params.shift = +shiftVal;
  if (extVal !== "" && extVal != null) params.extsize = +extVal;
  if (tsizeVal !== "" && tsizeVal != null) params.tsize = +tsizeVal;
  if (minLen !== "" && minLen != null) params.min_length = +minLen;
  if (maxGap !== "" && maxGap != null) params.max_gap = +maxGap;
  if (slocal !== "" && slocal != null) params.slocal = +slocal;
  if (llocal !== "" && llocal != null) params.llocal = +llocal;
  if (scaleTo) params.scale_to = scaleTo;
  return params;
}

const CHIP_GENOME_TXDB = {
  hs: { txdb: "TxDb.Hsapiens.UCSC.hg19.knownGene", anno_db: "org.Hs.eg.db" },
  hg19: { txdb: "TxDb.Hsapiens.UCSC.hg19.knownGene", anno_db: "org.Hs.eg.db" },
  mm: { txdb: "TxDb.Mmusculus.UCSC.mm10.knownGene", anno_db: "org.Mm.eg.db" },
};

function syncChipAnnoGenomeDefaults(genome) {
  const map = CHIP_GENOME_TXDB[genome] || CHIP_GENOME_TXDB.hs;
  const tx = document.getElementById("chip-txdb");
  const ad = document.getElementById("chip-annodb");
  if (tx && [...tx.options].some((o) => o.value === map.txdb)) tx.value = map.txdb;
  if (ad && [...ad.options].some((o) => o.value === map.anno_db)) ad.value = map.anno_db;
}

function chipAnnotateParams() {
  const annoGenome = document.getElementById("chip-anno-genome")?.value
    || document.getElementById("chip-genome")?.value
    || "mm";
  const tssUp = document.getElementById("chip-tss-up")?.value;
  const tssDn = document.getElementById("chip-tss-dn")?.value;
  const txdb = document.getElementById("chip-txdb")?.value || "";
  const annoDb = document.getElementById("chip-annodb")?.value || "";
  const params = {
    genome: annoGenome,
    tss_upstream: tssUp !== "" && tssUp != null ? +tssUp : -3000,
    tss_downstream: tssDn !== "" && tssDn != null ? +tssDn : 3000,
    level: document.getElementById("chip-anno-level")?.value || "transcript",
    overlap: document.getElementById("chip-overlap")?.value || "TSS",
    flank_distance: +document.getElementById("chip-flank-distance")?.value || 5000,
    add_flank_gene_info: document.getElementById("chip-add-flank")?.checked || false,
    same_strand: document.getElementById("chip-same-strand")?.checked || false,
    ignore_overlap: document.getElementById("chip-ignore-overlap")?.checked || false,
    score_cutoff: +document.getElementById("chip-score-cutoff")?.value || 5,
  };
  if (txdb) params.txdb = txdb;
  if (annoDb) params.anno_db = annoDb;
  return params;
}

function chipParams() {
  const m = chipMacsParams();
  const a = chipAnnotateParams();
  return { genome: a.genome || m.genome, prefer_macs: m.prefer_macs, qvalue: m.qvalue, score_cutoff: a.score_cutoff };
}

async function uploadChipBams(inputId, group, label) {
  const input = document.getElementById(inputId);
  const files = input?.files ? [...input.files] : [];
  if (!files.length) { toast(`Select ${label} BAM/SAM files.`, "error"); return; }
  setLoading(true);
  window._emp.analysisBusy = (window._emp.analysisBusy || 0) + 1;
  let hideTimer = null;
  const clearHideTimer = () => { if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; } };
  try {
    if (!localStorage.getItem("emp_session_id")) await API.createSession();
    for (const f of files) {
      clearHideTimer();
      const ac = new AbortController();
      showGlobalProgress(`Upload ${f.name}`, { onCancel: () => ac.abort() });
      try {
        await API.chipUploadBam(f, group, (p) => {
          updateGlobalProgress(p?.pct ?? 0, p?.message || "");
        }, { signal: ac.signal });
        updateGlobalProgress(100, "Done");
      } catch (e) {
        if (API.isUploadCancelled(e)) {
          toast(t("upload.cancelled"), "info");
          throw e;
        }
        updateGlobalProgress(100, `Failed: ${e.message}`);
        toast(e.message, "error");
        throw e;
      }
    }
    hideTimer = setTimeout(hideGlobalProgress, 500);
    await refreshChipBamTable();
    showAlert("chip-profile-result", `✓ Uploaded ${files.length} ${label} file(s).`, "success");
    toast(`${label} upload complete.`, "success");
    input.value = "";
  } catch (e) {
    clearHideTimer();
    hideGlobalProgress();
    if (API.isUploadCancelled(e)) {
      showAlert("chip-profile-result", t("upload.cancelled"), "info");
    } else {
      showAlert("chip-profile-result", `Error: ${e.message}`, "error");
    }
  } finally {
    window._emp.analysisBusy = Math.max(0, (window._emp.analysisBusy || 1) - 1);
    setLoading(false);
  }
}

/** Normalize UI / peak genome codes to chip-anno-genome values: mm | hs | hg19. */
function chipNormalizeAnnoGenome(g) {
  const s = String(g || "").toLowerCase().trim();
  if (!s) return "mm";
  if (s === "mm" || s.startsWith("mm") || s.includes("mouse")) return "mm";
  if (s === "hg19" || s === "grch37") return "hg19";
  if (s === "hs" || s.startsWith("hg") || s.includes("human")) return "hs";
  return "mm";
}

function chipAssemblyForAnnoGenome(g) {
  const key = chipNormalizeAnnoGenome(g);
  if (key === "mm") return "mm10";
  if (key === "hg19") return "hg19";
  return "hg38";
}

function chipAnnoGenomeIsUserSet() {
  return document.getElementById("chip-anno-genome")?.dataset?.userSet === "1";
}

function chipAnnoGenomeValue() {
  return document.getElementById("chip-anno-genome")?.value || "mm";
}

/** Authoritative genome for status / session: manual Genome mapping wins when userSet. */
function chipEffectivePeakGenome(peaks = null) {
  if (chipAnnoGenomeIsUserSet()) return chipNormalizeAnnoGenome(chipAnnoGenomeValue());
  const p = peaks || window._emp?.chipLastPeaks;
  return chipNormalizeAnnoGenome(p?.genome || p?.assembly || chipAnnoGenomeValue());
}

/** Write genome onto active peak + matching chipPeakFiles entry (client session). */
function applyChipSessionGenome(genomeCode) {
  const key = chipNormalizeAnnoGenome(genomeCode);
  const assembly = chipAssemblyForAnnoGenome(key);
  window._emp = window._emp || {};
  const peaks = window._emp.chipLastPeaks;
  if (peaks) {
    peaks.genome = key;
    peaks.assembly = assembly;
  }
  const id = window._emp.chipActivePeakId || peaks?.id;
  const path = peaks?.peak_file || peaks?.path;
  const files = window._emp.chipPeakFiles;
  if (Array.isArray(files)) {
    for (const e of files) {
      if ((id && e.id === id) || (path && (e.peak_file === path || e.path === path))) {
        e.genome = key;
        e.assembly = assembly;
      }
    }
  }
  return { genome: key, assembly };
}

/**
 * Merge server last_peaks into client.
 * Manual Genome mapping always wins for the active session after the user sets it.
 */
function adoptChipLastPeaks(serverLp, opts = {}) {
  window._emp = window._emp || {};
  const preferUser = opts.preferUserGenome !== false && chipAnnoGenomeIsUserSet();
  const prev = window._emp.chipLastPeaks || {};
  const merged = { ...prev, ...(serverLp || {}) };
  if (preferUser) {
    const g = chipNormalizeAnnoGenome(chipAnnoGenomeValue() || prev.genome);
    merged.genome = g;
    merged.assembly = chipAssemblyForAnnoGenome(g);
  }
  window._emp.chipLastPeaks = merged;
  if (preferUser) applyChipSessionGenome(merged.genome);
  return merged;
}

/** Persist Genome mapping to session peak registry (no re-upload). */
async function persistChipPeakGenome(genomeCode = null) {
  const g = chipNormalizeAnnoGenome(genomeCode || chipAnnoGenomeValue());
  applyChipSessionGenome(g);
  if (!localStorage.getItem("emp_session_id")) return null;
  if (!window._emp?.chipLastPeaks?.peak_file) return null;
  try {
    const res = await API.chipSetPeakGenome({
      genome: g,
      peak_id: window._emp.chipActivePeakId || window._emp.chipLastPeaks?.id || null,
    });
    if (res?.last_peaks) adoptChipLastPeaks(res.last_peaks, { preferUserGenome: true });
    if (Array.isArray(res?.peak_files)) {
      window._emp.chipPeakFiles = res.peak_files;
      applyChipSessionGenome(g);
    }
    if (res?.active_peak_id) window._emp.chipActivePeakId = res.active_peak_id;
    return res;
  } catch (_) {
    // Client state already updated; list refresh must still respect userSet.
    return null;
  }
}

function refreshChipPeakStatus(displayName = null) {
  const peaks = window._emp.chipLastPeaks;
  const path = peaks?.peak_file || "";
  const els = [
    document.getElementById("chip-peak-status"),
    document.getElementById("chip-peak-status-anno"),
  ].filter(Boolean);
  if (!els.length) return;
  if (!path && !displayName) {
    els.forEach((el) => {
      el.classList.add("hidden");
      el.textContent = "";
    });
    return;
  }
  const name = displayName || peaks?.display_name || path.split(/[/\\]/).pop() || path;
  const srcRaw = peaks?.source || "peaks";
  const src = (srcRaw === "preimported" || srcRaw === "upload")
    ? "uploaded peak file"
    : (srcRaw === "macs" || /narrowPeak|broadPeak|summits/i.test(name) ? "MACS output" : srcRaw);
  const genomeCode = chipEffectivePeakGenome(peaks);
  if (peaks && genomeCode) {
    peaks.genome = genomeCode;
    peaks.assembly = chipAssemblyForAnnoGenome(genomeCode);
  }
  const genome = genomeCode ? ` · genome ${genomeCode}` : "";
  const nPeaks = peaks?.n_peaks;
  const nTxt = (nPeaks != null && nPeaks !== "")
    ? ` · <strong>${escapeHtml(String(nPeaks))}</strong> peaks`
    : "";
  const lowWarn = (Number(nPeaks) >= 0 && Number(nPeaks) < 50)
    ? `<br><span class="hint" style="color:#b45309">⚠ Only ${escapeHtml(String(nPeaks))} peak(s) — ChIPseeker will mirror this count. Re-run MACS (§3) with --nomodel/--extsize, looser -q, or Histone/broad if needed.</span>`
    : "";
  const html = `✓ Peak file ready for ChIPseeker: <strong>${escapeHtml(name)}</strong> (${escapeHtml(src)}${escapeHtml(genome)}${nTxt}).<br><span class="meta">${escapeHtml(path)}</span>${lowWarn}`;
  els.forEach((el) => {
    el.innerHTML = html;
    el.classList.remove("hidden");
  });
  // Align ChIPseeker genome only if user has not manually overridden the dropdown.
  syncChipAnnoFromPeakGenome(peaks?.genome, { force: false });
}

function syncChipAnnoFromPeakGenome(genome, opts = {}) {
  if (!genome) return;
  const force = opts.force === true;
  const annoG = document.getElementById("chip-anno-genome");
  // ponytail: respect manual species choice; peak metadata often stale (defaulted to hs).
  // User's Genome mapping always wins until they change the dropdown again.
  if (!force && annoG?.dataset?.userSet === "1") {
    const key = chipNormalizeAnnoGenome(annoG.value || "mm");
    applyChipSessionGenome(key);
    syncChipAnnoGenomeDefaults(key);
    return;
  }
  const key = chipNormalizeAnnoGenome(genome);
  const macsG = document.getElementById("chip-genome");
  if (annoG && annoG.value !== key && [...annoG.options].some((o) => o.value === key)) {
    annoG.value = key;
    syncChipAnnoGenomeDefaults(key);
  } else if (annoG) {
    syncChipAnnoGenomeDefaults(annoG.value || key);
  }
  if (macsG && (key === "hs" || key === "mm") && macsG.value !== key
      && macsG.dataset?.userSet !== "1") {
    macsG.value = key;
  }
}

function renderChipPlots(plots) {
  const el = document.getElementById("chip-plots");
  if (!el) return;
  const entries = plots && typeof plots === "object" ? Object.entries(plots) : [];
  if (!entries.length) {
    el.classList.add("hidden");
    el.innerHTML = "";
    return;
  }
  el.innerHTML = entries.map(([title, b64]) => `
    <div class="chip-plot-panel card">
      <h4>${escapeHtml(String(title).replace(/_/g, " "))}</h4>
      <img src="data:image/png;base64,${b64}" alt="${escapeHtml(title)}">
    </div>
  `).join("");
  el.classList.remove("hidden");
  if (window.lucide) lucide.createIcons({ nodes: [el] });
  try { noteUiResultChanged(); } catch (_) { /* ignore */ }
}

function renderChipTables(tables) {
  const el = document.getElementById("chip-tables");
  if (!el) return;
  const entries = tables && typeof tables === "object"
    ? Object.entries(tables).filter(([, p]) => typeof p === "string" && p)
    : [];
  window._emp.chipLastTables = Object.fromEntries(entries);
  if (!entries.length) {
    el.classList.add("hidden");
    el.innerHTML = "";
    return;
  }
  const labels = {
    annotation_all: "All peak annotations",
    high_confidence: "High-confidence peaks (score filter)",
    promoter: "Promoter peaks",
    promoter_1kb: "Promoter ≤1kb",
    GO_BP: "GO Biological Process",
    GO_CC: "GO Cellular Component",
    GO_MF: "GO Molecular Function",
    KEGG: "KEGG",
    promoter_GO_BP: "Promoter GO-BP",
    promoter_GO_CC: "Promoter GO-CC",
    promoter_GO_MF: "Promoter GO-MF",
    promoter_KEGG: "Promoter KEGG",
    expression: "ChIP-gene expression matrix",
    diff: "ChIP-gene differential table",
    diff_sig: "ChIP-gene significant DE",
  };
  el.innerHTML = `
    <h4 style="margin:12px 0 8px">${escapeHtml(t("chip.tablesTitle") || "Result tables")}</h4>
    <div class="btn-row" style="flex-wrap:wrap;gap:8px">
      ${entries.map(([key, path]) => `
        <button type="button" class="btn btn-outline btn-sm chip-table-dl"
          data-path="${escapeHtml(path)}" data-key="${escapeHtml(key)}">
          <i data-lucide="download"></i> ${escapeHtml(labels[key] || key)}
        </button>`).join("")}
    </div>`;
  el.classList.remove("hidden");
  el.querySelectorAll(".chip-table-dl").forEach((btn) => {
    btn.addEventListener("click", async () => {
      try {
        const res = await withBusy("Download table", () => API.chipDownloadTable(btn.dataset.path));
        const blob = new Blob([res.content || ""], { type: "text/csv;charset=utf-8" });
        const a = document.createElement("a");
        a.href = URL.createObjectURL(blob);
        a.download = res.filename || `${btn.dataset.key || "chip_table"}.csv`;
        a.click();
        URL.revokeObjectURL(a.href);
        toast("Table downloaded.", "success");
      } catch (e) {
        toast(e.message, "error");
      }
    });
  });
  if (window.lucide) lucide.createIcons({ nodes: [el] });
}

function renderChipCrossResult(res) {
  const el = document.getElementById("chip-analysis-result");
  if (!el) return;
  const rec = Array.isArray(res.recommendation) ? res.recommendation : [];
  const list = (arr, n = 40) => (arr || []).slice(0, n).map((g) => escapeHtml(g)).join(", ")
    + ((arr || []).length > n ? "…" : "");
  el.innerHTML = `
    <div style="padding:12px">
      <p style="color:#166534;margin:0 0 8px">✓ Cross-omics overlap</p>
      <ul class="hint" style="margin:0 0 8px 1.2em">
        <li>ChIP genes: <strong>${res.chip_genes_n ?? 0}</strong></li>
        <li>RNA significant: <strong>${res.rnaseq_sig_n ?? 0}</strong> · overlap: <strong>${res.overlap_chip_rnaseq_n ?? 0}</strong></li>
        <li>Proteomics significant: <strong>${res.proteomics_sig_n ?? 0}</strong> · overlap: <strong>${res.overlap_chip_proteomics_n ?? 0}</strong></li>
        <li>Triplet overlap: <strong>${res.overlap_triplet_n ?? 0}</strong></li>
      </ul>
      ${res.overlap_chip_rnaseq_n ? `<p class="meta"><strong>ChIP ∩ RNA:</strong> ${list(res.overlap_chip_rnaseq)}</p>` : ""}
      ${res.overlap_chip_proteomics_n ? `<p class="meta"><strong>ChIP ∩ Proteomics:</strong> ${list(res.overlap_chip_proteomics)}</p>` : ""}
      ${res.overlap_triplet_n ? `<p class="meta"><strong>Triplet:</strong> ${list(res.overlap_triplet)}</p>` : ""}
      ${rec.length ? `<p class="hint">${rec.map((r) => escapeHtml(r)).join("<br>")}</p>` : ""}
    </div>`;
  el.classList.remove("hidden");
}

/** Restore last peaks from session manifest when UI state was lost (reload / tab switch). */
async function ensureChipPeaksFromSession() {
  if (window._emp.chipLastPeaks?.peak_file) {
    refreshChipPeakStatus();
    return window._emp.chipLastPeaks;
  }
  try {
    const res = await API.chipListBams();
    if (res.last_peaks?.peak_file) {
      adoptChipLastPeaks({
        ...res.last_peaks,
        source: res.last_peaks.source || "session",
      });
      window._emp.activeDataKind = "chipseq";
      refreshChipPeakStatus();
      return window._emp.chipLastPeaks;
    }
  } catch (_) { /* API down — caller surfaces error */ }
  return null;
}

function isChipApiUnreachableError(msg = "") {
  return /cannot reach emp api|failed to fetch|networkerror|econnrefused/i.test(String(msg || ""));
}

async function runChipAnnotate({ silentEmptyToast = false } = {}) {
  const el = document.getElementById("chip-analysis-result");
  const peaks = await ensureChipPeaksFromSession();
  const peakFile = peaks?.peak_file || null;
  if (!peakFile) {
    const tip = t("chip.hint.annotateFail")
      || "Upload a MACS peak file (.bed / .narrowPeak) in section 1, or run Call peaks (MACS) in section 3 — then annotate.";
    if (el) {
      el.innerHTML = `<p style="padding:12px;color:#991b1b">Error: no peak file in this session.</p><p class="hint" style="padding:0 12px 12px">${escapeHtml(tip)}</p>`;
      el.classList.remove("hidden");
    }
    toast(tip, "error");
    const err = new Error(tip);
    err.code = "NO_PEAK_FILE";
    throw err;
  }
  if (!silentEmptyToast) {
    toast(t("chip.toast.usingSessionPeaks") || "Annotating current peak file with ChIPseeker…", "info");
  }
  const ap = chipAnnotateParams();
  const res = await withBusy("ChIPseeker annotation", () => API.chipAnnotateFull({
    peak_file: peakFile,
    ...ap,
  }), {
    mode: "hold",
    message: "ChIPseeker 注释中，首次加载注释库可能较慢…",
  });
  window._emp.chipLastAnnotation = res.annotation_csv;
  if (peaks && res.n_peaks != null) {
    window._emp.chipLastPeaks = { ...peaks, n_peaks: res.n_peaks };
    refreshChipPeakStatus();
  }
  renderChipPlots(res.plots);
  renderChipTables(res.tables);
  const nPlots = res.plots ? Object.keys(res.plots).length : 0;
  const nTables = res.tables ? Object.keys(res.tables).length : 0;
  const peakName = (peakFile || "").split(/[/\\]/).pop() || peakFile || "";
  const lowAnno = Number(res.n_peaks) > 0 && Number(res.n_peaks) < 50
    ? `<p class="hint" style="padding:0 12px 8px;color:#b45309">Annotated file = current session peak (<code>${escapeHtml(peakName)}</code>). Low count usually means MACS found few peaks — not a ChIPseeker pie-chart bug. Re-check §3 MACS output / Peak QC.</p>`
    : "";
  if (el) {
    el.innerHTML = `<p style="padding:12px;color:#166534">✓ Annotated <strong>${res.n_peaks}</strong> peaks from <code>${escapeHtml(peakName)}</code> (${escapeHtml(res.txdb || ap.txdb || "")}, level=${escapeHtml(res.level || ap.level)}).<br>
      Downstream: ${nPlots} plot(s) · ${nTables} table(s) — use download buttons below for CSV.<br>
      <span class="meta">CSV: ${escapeHtml(res.annotation_csv || "")}</span></p>${lowAnno}`;
    el.classList.remove("hidden");
  }
  if (Number(res.n_peaks) > 0 && Number(res.n_peaks) < 50) {
    toast(`Annotated ${res.n_peaks} peak(s) — if unexpected, re-run MACS with looser params.`, "warning");
  } else {
    toast(t("chip.toast.annotateOk") || "ChIPseeker annotation + downstream enrichment complete.", "success");
  }
  return res;
}

async function uploadChipPeaksFromAnalysis() {
  const input = document.getElementById("chip-peak-file");
  const file = input?.files?.[0];
  if (!file) {
    toast("Choose a peak file (.bed / .narrowPeak / .broadPeak / .gff).", "error");
    return false;
  }
  setLoading(true);
  try {
    if (!localStorage.getItem("emp_session_id")) await API.createSession();
    // Genome at upload is optional metadata; user picks species before Annotate (Advanced §4).
    const genome = document.getElementById("chip-anno-genome")?.value
      || document.getElementById("chip-genome")?.value
      || "mm";
    const preset = document.getElementById("chip-macs-preset")?.value || "cutrun_tf_p05";
    const res = await withBusy("Uploading peak file", () => API.chipUploadPeaks(file, genome, preset));
    // Do not force-sync genome from upload response — peak metadata may default to hs and
    // would overwrite a manual Mouse/Human choice (or the post-upload species pick).
    window._emp.chipLastPeaks = {
      peak_file: res.peak_file,
      run_dir: res.run_dir,
      genome: document.getElementById("chip-anno-genome")?.value || res.genome || genome,
      assembly: res.assembly,
      preset: res.preset || preset,
      source: "upload",
      format_hint: res.format_hint,
      display_name: file.name,
      name: file.name,
      n_peaks: res.n_peaks,
      id: res.peak_id || res.last_peaks?.id,
    };
    window._emp.activeDataKind = "chipseq";
    applyChipSessionGenome(document.getElementById("chip-anno-genome")?.value || genome);
    refreshChipPeakStatus(file.name);
    await refreshChipdsLastPeaks({ forceList: true, preserveGenomeSelects: true });
    await refreshExperimentList();
    if (globalExp && [...globalExp.options].some((o) => o.value === CHIP_STANDALONE_TOKEN)) {
      globalExp.value = CHIP_STANDALONE_TOKEN;
    }
    input.value = "";
    showAlert("chip-profile-result",
      `✓ Peak file uploaded (${file.name}). Next: Advanced → ChIPseeker — choose genome/species, then Annotate.`,
      "success");
    toast(t("chip.toast.uploadOk") || "Peaks uploaded. Choose genome, then Annotate.", "success");
    return true;
  } catch (e) {
    showAlert("chip-profile-result", `Error: ${e.message}`, "error");
    toast(e.message, "error");
    return false;
  } finally { setLoading(false); }
}

/** Local folder picker → upload BAM/SAM files (browser cannot expose absolute OS paths). */
async function browseAndUploadChipFolder() {
  const picker = document.getElementById("chip-folder-picker");
  if (!picker) {
    toast("Folder picker not available in this browser.", "error");
    return;
  }
  picker.value = "";
  picker.click();
}

async function onChipFolderPicked(ev) {
  const files = [...(ev.target?.files || [])];
  const bamLike = files.filter((f) => /\.(bam|sam)$/i.test(f.name));
  if (!bamLike.length) {
    toast("No BAM/SAM files found in the selected folder.", "error");
    return;
  }
  // Show folder label in the path field (relative name only — browsers hide absolute paths).
  const rel = bamLike[0].webkitRelativePath || bamLike[0].name;
  const folderLabel = rel.includes("/") ? rel.split("/")[0] : `(local folder · ${bamLike.length} BAM/SAM)`;
  const pathInput = document.getElementById("chip-folder-path");
  if (pathInput) pathInput.value = `local:${folderLabel}`;

  setLoading(true);
  window._emp.analysisBusy = (window._emp.analysisBusy || 0) + 1;
  let hideTimer = null;
  const clearHideTimer = () => { if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; } };
  try {
    if (!localStorage.getItem("emp_session_id")) await API.createSession();
    for (const f of bamLike) {
      clearHideTimer();
      const ac = new AbortController();
      showGlobalProgress(`Upload ${f.name}`, { onCancel: () => ac.abort() });
      try {
        await API.chipUploadBam(f, "t", (p) => {
          updateGlobalProgress(p?.pct ?? 0, p?.message || "");
        }, { signal: ac.signal });
        updateGlobalProgress(100, "Done");
      } catch (e) {
        if (API.isUploadCancelled(e)) {
          toast(t("upload.cancelled"), "info");
          throw e;
        }
        updateGlobalProgress(100, `Failed: ${e.message}`);
        toast(e.message, "error");
        throw e;
      }
    }
    hideTimer = setTimeout(hideGlobalProgress, 500);
    await refreshChipBamTable();
    showAlert(
      "chip-profile-result",
      `✓ Uploaded ${bamLike.length} BAM/SAM from local folder 「${folderLabel}」 as Treatment. Reassign Control in the table if needed.`,
      "success"
    );
    toast(`Uploaded ${bamLike.length} alignment file(s).`, "success");
  } catch (e) {
    clearHideTimer();
    hideGlobalProgress();
    if (API.isUploadCancelled(e)) {
      showAlert("chip-profile-result", t("upload.cancelled"), "info");
    } else {
      showAlert("chip-profile-result", `Error: ${e.message}`, "error");
    }
  } finally {
    window._emp.analysisBusy = Math.max(0, (window._emp.analysisBusy || 1) - 1);
    setLoading(false);
    ev.target.value = "";
  }
}

async function refreshChipBamTable() {
  const wrap = document.getElementById("chip-bam-table-wrap");
  const summary = document.getElementById("chip-bam-summary");
  const tbody = document.querySelector("#chip-bam-table tbody");
  if (!wrap || !tbody) return;
  try {
    const res = await API.chipListBams();
    const files = res.files || [];
    const nT = res.n_treatment ?? files.filter((f) => f.group === "t").length;
    const nC = res.n_control ?? files.filter((f) => f.group === "c").length;
    const cntT = document.getElementById("chip-count-treatment");
    const cntC = document.getElementById("chip-count-control");
    if (cntT) cntT.textContent = `Treatment: ${nT}`;
    if (cntC) cntC.textContent = `Control: ${nC}`;
    if (summary) summary.classList.toggle("hidden", !files.length);
    if (!files.length) {
      wrap.classList.add("hidden");
      tbody.innerHTML = "";
    } else {
      const sorted = [...files].sort((a, b) => (a.group === "c") - (b.group === "c"));
      tbody.innerHTML = sorted.map((f) => `
      <tr class="chip-row--${f.group === "c" ? "c" : "t"}" data-chip-id="${escapeHtml(f.id || f.name)}">
        <td>${escapeHtml(f.name || "")}</td>
        <td>
          <select class="chip-bam-group" data-id="${escapeHtml(f.id || f.name)}">
            <option value="t" ${f.group === "t" ? "selected" : ""}>Treatment (T)</option>
            <option value="c" ${f.group === "c" ? "selected" : ""}>Control (C)</option>
          </select>
        </td>
        <td class="meta">${escapeHtml(f.path || "")}</td>
      </tr>
    `).join("");
      wrap.classList.remove("hidden");
      tbody.querySelectorAll(".chip-bam-group").forEach((sel) => {
        sel.addEventListener("change", async () => {
          try {
            await API.chipSetBamGroup(sel.dataset.id, sel.value);
            await refreshChipBamTable();
            toast("Sample group updated.", "success");
          } catch (e) {
            toast(e.message, "error");
          }
        });
      });
    }
    if (res.last_peaks?.peak_file) {
      adoptChipLastPeaks(res.last_peaks);
      refreshChipPeakStatus();
      const alreadyListed = globalExp
        && [...globalExp.options].some((o) => o.value === CHIP_STANDALONE_TOKEN);
      if (!alreadyListed) refreshExperimentList().catch(() => {});
    }
    if (res.last_annotation_csv) window._emp.chipLastAnnotation = res.last_annotation_csv;
  } catch (_) {
    wrap.classList.add("hidden");
    if (summary) summary.classList.add("hidden");
  }
}

document.getElementById("chip-macs-preset")?.addEventListener("change", (e) => {
  applyChipMacsPreset(e.target.value);
});

document.getElementById("chip-cutoff-type")?.addEventListener("change", (e) => {
  const isP = e.target.value === "p";
  document.getElementById("chip-qvalue-wrap")?.classList.toggle("hidden", isP);
  document.getElementById("chip-pvalue-wrap")?.classList.toggle("hidden", !isP);
});

document.getElementById("chip-btn-upload-treatment")?.addEventListener("click", () => {
  uploadChipBams("chip-bam-files-treatment", "t", "Treatment");
});
document.getElementById("chip-btn-upload-control")?.addEventListener("click", () => {
  uploadChipBams("chip-bam-files-control", "c", "Control");
});
document.getElementById("chip-btn-upload-peaks")?.addEventListener("click", () => {
  uploadChipPeaksFromAnalysis();
});
document.getElementById("chip-btn-goto-annotate")?.addEventListener("click", () => {
  setChipWizardStep("advanced");
  openChipseqSection("chip-section-annotate");
  toast(t("chip.toast.gotoAnnotate") || "Choose genome/species, then Annotate (ChIPseeker).", "info");
});
document.getElementById("chip-btn-browse-folder")?.addEventListener("click", () => {
  browseAndUploadChipFolder();
});
document.getElementById("chip-folder-picker")?.addEventListener("change", (e) => {
  onChipFolderPicked(e);
});

document.getElementById("chip-btn-scan-folder")?.addEventListener("click", async () => {
  const folder = document.getElementById("chip-folder-path")?.value?.trim();
  if (!folder || folder.startsWith("local:")) {
    toast("Enter a server folder path for Scan, or use 「打开文件夹」 to pick local BAMs.", "error");
    return;
  }
  setLoading(true);
  try {
    if (!localStorage.getItem("emp_session_id")) await API.createSession();
    const res = await withBusy("Scan BAM folder", () => API.chipScanFolder(folder, "t"));
    await refreshChipBamTable();
    showAlert("chip-profile-result", `✓ Registered ${res.n_files || 0} file(s) as Treatment. Reassign Control samples in the table.`, "success");
  } catch (e) {
    showAlert("chip-profile-result", `Error: ${e.message}`, "error");
    toast(e.message, "error");
  } finally { setLoading(false); }
});

document.getElementById("chip-btn-profile")?.addEventListener("click", async () => {
  setLoading(true);
  clearAlert("chip-profile-result");
  try {
    const res = await withBusy("ChIP-seq profile", () => API.chipProfile());
    const p = res.profile || {};
    const macs = [p.has_macs3 && "macs3", p.has_macs2 && "macs2"].filter(Boolean).join(", ") || "none";
    showAlert(
      "chip-profile-result",
      `✓ MACS: ${macs}; ChIPseeker: ${p.has_chipseeker ? "yes" : "no"}; OrgDb hs/mm: ${p.has_orgdb_hs}/${p.has_orgdb_mm}.`,
      p.has_chipseeker && (p.has_macs3 || p.has_macs2) ? "success" : "warning"
    );
    await refreshChipBamTable();
  } catch (e) {
    showAlert("chip-profile-result", `Error: ${e.message}`, "error");
  } finally { setLoading(false); }
});

document.getElementById("chip-btn-peaks")?.addEventListener("click", async () => {
  setLoading(true);
  const el = document.getElementById("chip-analysis-result");
  try {
    const mp = chipMacsParams();
    const peaksG = String(window._emp.chipLastPeaks?.genome || "").toLowerCase();
    const macsG = String(mp.genome || "").toLowerCase();
    if (peaksG && macsG && peaksG !== macsG &&
        !((peaksG === "hs" || peaksG === "hg19" || peaksG === "hg38") &&
          (macsG === "hs" || macsG === "hg19" || macsG === "hg38"))) {
      toast(
        `Genome caution: existing peaks are “${peaksG}” but MACS is set to “${macsG}”. Continuing with MACS genome ${macsG}.`,
        "warning"
      );
    }
    const res = await withBusy("MACS peak calling", () => API.chipCallPeaks({
      use_manifest: true,
      ...mp,
    }), {
      mode: "hold",
      holdMin: 50,
      holdMax: 85,
      message: "MACS 运行中，大 BAM 可能需数十分钟…",
    });
    const nPeaks = Number(res.n_peaks);
    window._emp.chipLastPeaks = {
      ...(res.last_peaks || {}),
      ...res,
      source: "macs",
      n_peaks: Number.isFinite(nPeaks) ? nPeaks : res.n_peaks,
      display_name: (res.peak_file || "").split(/[/\\]/).pop() || "MACS peaks",
      id: res.peak_id || res.last_peaks?.id,
    };
    window._emp.activeDataKind = "chipseq";
    const warnLines = Array.isArray(res.macs_warnings)
      ? res.macs_warnings.slice(0, 3).map((w) => `<li>${escapeHtml(String(w))}</li>`).join("")
      : "";
    const lowHint = res.low_peak_hint
      ? `<p class="hint" style="padding:0 12px 8px;color:#b45309">${escapeHtml(res.low_peak_hint)}</p>`
      : (Number.isFinite(nPeaks) && nPeaks < 50
        ? `<p class="hint" style="padding:0 12px 8px;color:#b45309">Only ${nPeaks} peak(s) called — unusual. Try §3 Advanced: --nomodel + extsize 200, -q 0.05, or Histone/broad preset; then open narrowPeak / treat_pileup.bdg in IGV.</p>`
        : "");
    const peakCountHtml = Number.isFinite(nPeaks)
      ? `<strong>${nPeaks}</strong> peak(s)`
      : "peaks";
    el.innerHTML = `<p style="padding:12px;color:#166534">✓ Peaks called with ${escapeHtml(res.caller || "MACS")}: ${peakCountHtml}. <strong>Treatment: ${res.n_treatment ?? (res.treatment_bams || []).length}</strong>, <strong>Control: ${res.n_control ?? (res.control_bams || []).length}</strong>.<br>
      Peak: <code>${escapeHtml(res.peak_file || "")}</code><br>
      ${res.summit_file ? `Summits: <code>${escapeHtml(res.summit_file)}</code><br>` : ""}
      ${res.run_dir ? `Run dir: <code>${escapeHtml(res.run_dir)}</code><br>` : ""}
      <span class="hint">Previous uploads / MACS runs remain in <strong>当前峰文件</strong> dropdown · View narrowPeak in IGV · Peak QC (downstream) · Annotate (ChIPseeker) in §4.</span></p>
      ${lowHint}
      ${warnLines ? `<ul class="hint" style="padding:0 12px 12px;margin:0;color:#92400e">${warnLines}</ul>` : ""}`;
    el.classList.remove("hidden");
    refreshChipPeakStatus();
    await refreshChipdsLastPeaks({ forceList: true, forceGenomeSync: true });
    await refreshExperimentList();
    if (globalExp && [...globalExp.options].some((o) => o.value === CHIP_STANDALONE_TOKEN)) {
      globalExp.value = CHIP_STANDALONE_TOKEN;
    }
    if (Number.isFinite(nPeaks) && nPeaks < 50) {
      toast(`MACS done but only ${nPeaks} peak(s) — check params / IGV before annotating.`, "warning");
    } else {
      toast("MACS complete — peak file ready for ChIPseeker.", "success");
    }
  } catch (e) {
    el.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${escapeHtml(e.message)}</p>`;
    el.classList.remove("hidden");
    toast(e.message, "error");
  } finally { setLoading(false); }
});

document.getElementById("chip-btn-annotate")?.addEventListener("click", async () => {
  setLoading(true);
  const el = document.getElementById("chip-analysis-result");
  try {
    await runChipAnnotate();
  } catch (e) {
    const msg = e?.message || String(e);
    let tip = "";
    if (isChipApiUnreachableError(msg)) {
      tip = t("chip.hint.apiDown")
        || "Backend API is unreachable. Start it with: bash webapp/scripts/start_local.sh — then retry Annotate.";
    } else if (e?.code !== "NO_PEAK_FILE" && !/no peak file/i.test(msg)) {
      tip = t("chip.hint.annotateFail")
        || "Upload a MACS peak file (.bed / .narrowPeak) in section 1, or run Call peaks (MACS) in section 3 — then annotate.";
    }
    if (el && e?.code !== "NO_PEAK_FILE") {
      el.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${escapeHtml(msg)}</p>${
        tip ? `<p class="hint" style="padding:0 12px 12px">${escapeHtml(tip)}</p>` : ""
      }`;
      el.classList.remove("hidden");
    }
    toast(msg, "error");
  } finally { setLoading(false); }
});

document.getElementById("chip-anno-genome")?.addEventListener("change", async (e) => {
  e.target.dataset.userSet = "1";
  const g = chipNormalizeAnnoGenome(e.target.value);
  e.target.value = g;
  syncChipAnnoGenomeDefaults(g);
  applyChipSessionGenome(g);
  const macsG = document.getElementById("chip-genome");
  if (macsG && (g === "mm" || g === "hs") && macsG.dataset?.userSet !== "1") {
    macsG.value = g;
  }
  // Seed HOMER/ops selects only when those controls are not manually locked.
  try { syncChipdsGenomeSelects(g, { force: false }); } catch (_) { /* ignore */ }
  try { refreshChipPeakStatus(); } catch (_) { /* ignore */ }
  try { renderChipdsLastPeaksBadge(window._emp.chipLastPeaks); } catch (_) { /* ignore */ }
  await persistChipPeakGenome(g);
  try { refreshChipPeakStatus(); } catch (_) { /* ignore */ }
  try { renderChipdsLastPeaksBadge(window._emp.chipLastPeaks); } catch (_) { /* ignore */ }
});
document.getElementById("chip-genome")?.addEventListener("change", async (e) => {
  e.target.dataset.userSet = "1";
  const g = e.target.value === "mm" ? "mm" : "hs";
  const annoG = document.getElementById("chip-anno-genome");
  if (annoG) {
    annoG.value = g;
    annoG.dataset.userSet = "1";
    syncChipAnnoGenomeDefaults(g);
  }
  applyChipSessionGenome(g);
  try { syncChipdsGenomeSelects(g, { force: false }); } catch (_) { /* ignore */ }
  try { refreshChipPeakStatus(); } catch (_) { /* ignore */ }
  try { renderChipdsLastPeaksBadge(window._emp.chipLastPeaks); } catch (_) { /* ignore */ }
  await persistChipPeakGenome(g);
});

document.getElementById("chip-btn-coanalysis")?.addEventListener("click", async () => {
  const rnaseq = document.getElementById("chip-rnaseq-exp")?.value;
  if (!rnaseq) { toast("Select an RNA-seq experiment.", "error"); return; }
  setLoading(true);
  const el = document.getElementById("chip-analysis-result");
  try {
    const cp = chipParams();
    const res = await withBusy("ChIP + RNA-seq co-analysis", () => API.chipRnaseqCoanalysis({
      rnaseq_experiment: rnaseq,
      peak_annotation_csv: window._emp.chipLastAnnotation || null,
      genome: cp.genome,
      score_cutoff: +document.getElementById("chip-co-score-cutoff")?.value || 10,
      min_total_counts: +document.getElementById("chip-min-counts")?.value || 100,
      rnaseq_p_cutoff: +document.getElementById("chip-rna-p-cutoff")?.value || 0.05,
      promoter_filter: document.getElementById("chip-promoter-filter")?.checked !== false,
    }), {
      mode: "hold",
      message: "跨组学联合分析运行中…",
    });
    renderChipPlots(res.plots);
    renderChipTables(res.tables);
    el.innerHTML = `<p style="padding:12px;color:#166534">✓ Co-analysis: <strong>${res.chip_genes_n}</strong> peak-linked genes with RNA-seq ${escapeHtml(rnaseq)}.<br>
      Plots: ${res.plots ? Object.keys(res.plots).length : 0} · Tables: ${res.tables ? Object.keys(res.tables).length : 0}</p>`;
    el.classList.remove("hidden");
    toast("RNA-seq co-analysis complete.", "success");
  } catch (e) {
    el.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${escapeHtml(e.message)}</p>`;
    el.classList.remove("hidden");
    toast(e.message, "error");
  } finally { setLoading(false); }
});

document.getElementById("chip-btn-cross")?.addEventListener("click", async () => {
  const rna = document.getElementById("chip-cross-rnaseq")?.value || null;
  const pro = document.getElementById("chip-cross-proteomics")?.value || null;
  if (!rna && !pro) {
    toast("Select at least one RNA-seq or proteomics experiment.", "error");
    return;
  }
  if (!window._emp.chipLastAnnotation) {
    toast("Run ChIPseeker annotation (section 4) first.", "error");
    return;
  }
  setLoading(true);
  try {
    const res = await withBusy("ChIP cross-omics overlap", () => API.chipCrossOmics({
      peak_annotation_csv: window._emp.chipLastAnnotation,
      rnaseq_experiment: rna || null,
      proteomics_experiment: pro || null,
      rnaseq_p_cutoff: +document.getElementById("chip-cross-rna-p")?.value || 0.05,
      rnaseq_fc_cutoff: +document.getElementById("chip-cross-rna-fc")?.value || 1,
      proteomics_p_cutoff: +document.getElementById("chip-cross-pro-p")?.value || 0.05,
      proteomics_fc_cutoff: +document.getElementById("chip-cross-pro-fc")?.value || 0.5,
    }), {
      mode: "hold",
      message: "交叉组学重叠分析运行中…",
    });
    renderChipCrossResult(res);
    toast("Cross-omics overlap complete.", "success");
  } catch (e) {
    const el = document.getElementById("chip-analysis-result");
    if (el) {
      el.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${escapeHtml(e.message)}</p>`;
      el.classList.remove("hidden");
    }
    toast(e.message, "error");
  } finally { setLoading(false); }
});

refreshChipBamTable();
applyChipMacsPreset(document.getElementById("chip-macs-preset")?.value || "cutrun_tf_p05");

// ── ChIPseq downstream checklist page ─────────────────
let _chipdsCatalog = null;
let _chipdsFiltersBound = false;

function chipdsEsc(s) {
  return escapeHtml(String(s ?? ""));
}

function chipdsPriorityClass(p) {
  if (p === "must") return "chipds-pri--must";
  if (p === "recommend") return "chipds-pri--recommend";
  if (p === "advanced") return "chipds-pri--advanced";
  return "chipds-pri--optional";
}

function chipdsStatusLabel(status) {
  return status === "available" ? "可运行" : "规划中";
}

function chipdsNeedBam(v) {
  const s = String(v ?? "").toLowerCase();
  if (s === "yes" || s === "y" || s === "true" || s === "1") return "yes";
  if (s === "no" || s === "n" || s === "false" || s === "0") return "no";
  return s || "no";
}

async function fetchChipDownstreamCatalog() {
  try {
    const res = await API.chipDownstreamCatalog();
    const cat = res?.catalog || res;
    if (cat?.items?.length) return cat;
  } catch (_) { /* fall through to static */ }
  const r = await fetch(`data/chipseq_downstream_catalog.json?v=chipseq-peaks-fix-v1`);
  if (!r.ok) throw new Error("无法加载下游分析目录");
  return r.json();
}

function filterChipDownstreamItems(items) {
  const stage = document.getElementById("chipds-filter-stage")?.value || "";
  const priority = document.getElementById("chipds-filter-priority")?.value || "";
  const bam = document.getElementById("chipds-filter-bam")?.value || "";
  const status = document.getElementById("chipds-filter-status")?.value || "";
  const q = (document.getElementById("chipds-search")?.value || "").trim().toLowerCase();
  return (items || []).filter((it) => {
    if (stage && it.stage !== stage) return false;
    if (priority && it.priority !== priority) return false;
    if (bam && chipdsNeedBam(it.need_bam) !== bam) return false;
    if (status && (it.status || "planned") !== status) return false;
    if (q) {
      const blob = [it.name, it.purpose, it.software, it.alt_software, it.stage, it.method]
        .map((x) => String(x || "").toLowerCase())
        .join(" ");
      if (!blob.includes(q)) return false;
    }
    return true;
  });
}

function renderChipDownstreamMarks(strategies) {
  const root = document.getElementById("chipds-mark-strategies");
  if (!root) return;
  if (!strategies?.length) {
    root.innerHTML = `<p class="hint">无 Mark 策略数据</p>`;
    return;
  }
  root.innerHTML = strategies.map((m) => `
    <div class="chipds-mark-card">
      <div class="chipds-mark-title">${chipdsEsc(m.target)}</div>
      <div class="chipds-mark-meta"><span>峰型</span>${chipdsEsc(m.peak_type)}</div>
      <div class="chipds-mark-meta"><span>定位</span>${chipdsEsc(m.localization)}</div>
      <div class="chipds-mark-meta"><span>必做</span>${chipdsEsc(m.must_do)}</div>
      <div class="chipds-mark-meta"><span>软件</span>${chipdsEsc(m.software)}</div>
      <div class="chipds-mark-note">${chipdsEsc(m.notes || "")}</div>
    </div>
  `).join("");
}

function renderChipDownstreamCatalog(catalog) {
  const root = document.getElementById("chipds-catalog");
  if (!root || !catalog) return;
  const items = filterChipDownstreamItems(catalog.items || []);
  const stages = catalog.stages?.length
    ? catalog.stages
    : [...new Set(items.map((i) => i.stage).filter(Boolean))];

  if (!items.length) {
    root.innerHTML = `<p class="hint">无匹配模块，请调整筛选条件。</p>`;
    return;
  }

  // Dedupe by action: one card listing covered module ids (#a,#b,…)
  const ACTION_PACK = {
    chip_peak_qc: "core",
    chip_peaks_blacklist: "core",
    chip_peaks_merge: "core",
    chip_peaks_summit: "core",
    chip_peaks_overlap: "core",
    chip_idr_approx: "core",
    chip_diffbind: "core",
    chip_annotate: "core",
    chip_homer: "motif",
    chip_promoter_call: "histone_enhancer",
    chip_enhancer_call: "histone_enhancer",
    chip_super_enhancer: "histone_enhancer",
    chip_bivalent: "histone_enhancer",
    chip_broad_domains: "histone_enhancer",
    chip_chromatin_proxy: "histone_enhancer",
    chip_deeptools_heatmap: "visualization",
    chip_deeptools_coverage: "visualization",
    chip_deeptools_corr: "visualization",
    chip_rna_co: "rna_protein",
    chip_cross: "rna_protein",
    chip_microbiome_coanalysis: "microbiome_16s_mgx",
    chip_metabolomics_coanalysis: "metabolomics",
    chip_clinical_coanalysis: "clinical",
  };

  const byStage = new Map();
  for (const st of stages) byStage.set(st, []);
  for (const it of items) {
    const st = it.stage || "其他";
    if (!byStage.has(st)) byStage.set(st, []);
    byStage.get(st).push(it);
  }

  const parts = [];
  for (const [st, list] of byStage) {
    if (!list.length) continue;
    const groups = new Map();
    const planned = [];
    for (const it of list) {
      const act = it.action || null;
      if (!act) {
        planned.push(it);
        continue;
      }
      if (!groups.has(act)) groups.set(act, []);
      groups.get(act).push(it);
    }
    const cards = [];
    for (const [act, group] of groups) {
      const primary = group[0];
      const ids = group.map((g) => g.id).filter((x) => x != null);
      const available = primary.status === "available" && act;
      const bam = group.some((g) => chipdsNeedBam(g.need_bam) === "yes") ? "yes" : "no";
      const packId = primary.pack_id || ACTION_PACK[act] || "";
      const idLabel = ids.length > 1
        ? `#${ids.map((id) => chipdsEsc(id)).join(",#")}`
        : `#${chipdsEsc(ids[0] ?? primary.id)}`;
      cards.push(`<article class="chipds-card ${available ? "chipds-card--run" : "chipds-card--planned"}" data-id="${chipdsEsc(primary.id)}" data-action="${chipdsEsc(act)}">
            <div class="chipds-card-head">
              <span class="chipds-card-id">${idLabel}</span>
              <span class="chipds-pri ${chipdsPriorityClass(primary.priority)}">${chipdsEsc(primary.priority_label || primary.priority)}</span>
              <span class="chipds-status ${available ? "chipds-status--ok" : "chipds-status--plan"}">${chipdsStatusLabel(primary.status)}</span>
              ${bam === "yes" ? `<span class="chipds-bam">需BAM</span>` : ""}
              ${packId ? `<span class="chipds-pack">pack:${chipdsEsc(packId)}</span>` : ""}
            </div>
            <h5 class="chipds-card-name">${chipdsEsc(primary.name)}${ids.length > 1 ? ` <span class="hint">(+${ids.length - 1})</span>` : ""}</h5>
            <p class="chipds-card-purpose">${chipdsEsc(primary.purpose)}</p>
            <p class="chipds-card-sw"><strong>软件</strong> ${chipdsEsc(primary.software || "—")}</p>
            <div class="chipds-card-actions">
              ${available
                ? `<button type="button" class="btn btn-primary btn-sm" data-chipds-action="${chipdsEsc(act)}">运行</button>`
                : `<button type="button" class="btn btn-outline btn-sm" disabled title="规划中">规划中</button>`}
            </div>
          </article>`);
    }
    for (const it of planned) {
      cards.push(`<article class="chipds-card chipds-card--planned" data-id="${chipdsEsc(it.id)}">
            <div class="chipds-card-head">
              <span class="chipds-card-id">#${chipdsEsc(it.id)}</span>
              <span class="chipds-pri ${chipdsPriorityClass(it.priority)}">${chipdsEsc(it.priority_label || it.priority)}</span>
              <span class="chipds-status chipds-status--plan">${chipdsStatusLabel(it.status)}</span>
            </div>
            <h5 class="chipds-card-name">${chipdsEsc(it.name)}</h5>
            <p class="chipds-card-purpose">${chipdsEsc(it.purpose)}</p>
            <p class="chipds-card-sw"><strong>软件</strong> ${chipdsEsc(it.software || "—")}</p>
            <div class="chipds-card-actions">
              <button type="button" class="btn btn-outline btn-sm" disabled title="规划中">规划中</button>
            </div>
          </article>`);
    }
    parts.push(`<div class="chipds-stage">
      <h4 class="chipds-stage-title">${chipdsEsc(st)} <span class="chipds-stage-count">${cards.length}</span></h4>
      <div class="chipds-cards">${cards.join("")}</div>
    </div>`);
  }
  root.innerHTML = parts.join("");
  root.querySelectorAll("[data-chipds-action]").forEach((btn) => {
    btn.addEventListener("click", () => runChipDownstreamAction(btn.dataset.chipdsAction));
  });
}

function updateChipDownstreamSummary(catalog, filteredCount) {
  const s = catalog?.summary || {};
  const elM = document.getElementById("chipds-badge-modules");
  const elMust = document.getElementById("chipds-badge-must");
  const elAv = document.getElementById("chipds-badge-available");
  if (elM) elM.textContent = t("chipds.badge.modules", null, { cur: filteredCount ?? s.modules ?? "—", total: s.modules ?? "—" });
  if (elMust) elMust.textContent = t("chipds.badge.must", null, { n: s.must ?? "—" });
  if (elAv) elAv.textContent = t("chipds.badge.available", null, { n: s.available ?? "—" });
}

function fillChipDownstreamStageSelect(catalog) {
  const sel = document.getElementById("chipds-filter-stage");
  if (!sel) return;
  const prev = sel.value;
  const stages = catalog.stages?.length
    ? catalog.stages
    : [...new Set((catalog.items || []).map((i) => i.stage).filter(Boolean))];
  // Rebuild so empty option text tracks locale; keep stage ids as-is (catalog language).
  sel.innerHTML = `<option value="">${t("chipds.opt.allStages")}</option>` +
    stages.map((st) => `<option value="${chipdsEsc(st)}">${chipdsEsc(st)}</option>`).join("");
  sel.dataset.filled = "1";
  if (prev && [...sel.options].some((o) => o.value === prev)) sel.value = prev;
}

function bindChipDownstreamFilters() {
  if (_chipdsFiltersBound) return;
  _chipdsFiltersBound = true;
  const rerender = () => {
    if (!_chipdsCatalog) return;
    const filtered = filterChipDownstreamItems(_chipdsCatalog.items || []);
    updateChipDownstreamSummary(_chipdsCatalog, filtered.length);
    renderChipDownstreamCatalog(_chipdsCatalog);
  };
  ["chipds-filter-stage", "chipds-filter-priority", "chipds-filter-bam", "chipds-filter-status"]
    .forEach((id) => document.getElementById(id)?.addEventListener("change", rerender));
  document.getElementById("chipds-search")?.addEventListener("input", rerender);
}

function openChipseqSection(sectionId) {
  openChipseqWorkspace({ skipNavigate: false });
  // Annotate / RNA / cross live under the Advanced wizard panel (hidden on Step 1/2).
  if (sectionId === "chip-section-annotate"
      || sectionId === "chip-section-rna"
      || sectionId === "chip-section-cross") {
    setChipWizardStep("advanced");
  }
  setTimeout(() => {
    const el = document.getElementById(sectionId);
    if (el) {
      el.scrollIntoView({ behavior: "smooth", block: "start" });
      el.classList.add("chip-section-flash");
      setTimeout(() => el.classList.remove("chip-section-flash"), 1600);
    }
  }, 280);
}

async function runChipDownstreamAction(action) {
  if (!action) return;
  if (action === "chip_annotate") {
    openChipseqSection("chip-section-annotate");
    toast("已跳转到 ChIP-seq · §4 ChIPseeker", "info");
    return;
  }
  if (action === "chip_rna_co") {
    openChipseqSection("chip-section-rna");
    toast("已跳转到 ChIP-seq · §5 RNA 联合分析", "info");
    return;
  }
  if (action === "chip_cross") {
    openChipseqSection("chip-section-cross");
    toast("已跳转到 ChIP-seq · §6 跨组学重叠", "info");
    return;
  }
  if (action === "chip_peak_qc") {
    await runChipPeakQcOnPage();
    return;
  }
  if (action === "chip_homer") {
    focusChipdsToolPanel("homer");
    await runChipHomerOnPage();
    return;
  }
  if (action === "chip_diffbind") {
    focusChipdsToolPanel("diffbind");
    await runChipDiffBindOnPage();
    return;
  }
  if (action === "chip_deeptools_heatmap") {
    focusChipdsToolPanel("deeptools");
    const modeEl = document.getElementById("chipds-dt-mode");
    if (modeEl) modeEl.value = "heatmap";
    await runChipDeepToolsOnPage();
    return;
  }
  if (action === "chip_deeptools_corr") {
    focusChipdsToolPanel("deeptools");
    const modeEl = document.getElementById("chipds-dt-mode");
    if (modeEl) modeEl.value = "corr";
    await runChipDeepToolsOnPage();
    return;
  }
  if (action === "chip_deeptools_coverage") {
    focusChipdsToolPanel("deeptools");
    const modeEl = document.getElementById("chipds-dt-mode");
    if (modeEl) modeEl.value = "coverage";
    await runChipDeepToolsOnPage();
    return;
  }
  const peaksOpsMap = {
    chip_peaks_blacklist: "blacklist",
    chip_peaks_merge: "merge",
    chip_peaks_summit: "summit",
    chip_peaks_overlap: "overlap",
    chip_idr_approx: "idr",
    chip_promoter_call: "promoter",
    chip_enhancer_call: "enhancer",
    chip_super_enhancer: "super_enhancer",
    chip_broad_domains: "broad",
    chip_bivalent: "bivalent",
    chip_chromatin_proxy: "chromatin_proxy",
  };
  if (peaksOpsMap[action]) {
    focusChipdsToolPanel("peaksops");
    await runChipPeaksOpsOnPage(peaksOpsMap[action]);
    return;
  }
  if (action === "chip_microbiome_coanalysis") {
    await runChipMicrobiomeCoanalysisOnPage();
    return;
  }
  if (action === "chip_metabolomics_coanalysis") {
    await runChipMetabolomicsCoanalysisOnPage();
    return;
  }
  if (action === "chip_clinical_coanalysis") {
    await runChipClinicalCoanalysisOnPage();
    return;
  }
  toast(`未知动作: ${action}`, "warning");
}

function focusChipdsToolPanel(which) {
  const map = {
    homer: "chipds-panel-homer",
    diffbind: "chipds-panel-diffbind",
    deeptools: "chipds-panel-deeptools",
    peaksops: "chipds-panel-peaksops",
  };
  const id = map[which];
  const el = id ? document.getElementById(id) : null;
  if (el) {
    el.open = true;
    el.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }
}

function renderChipdsToolPlots(plots) {
  const el = document.getElementById("chipds-tool-plots");
  if (!el) return;
  const entries = plots && typeof plots === "object" ? Object.entries(plots).filter(([, v]) => v) : [];
  if (!entries.length) {
    el.classList.add("hidden");
    el.innerHTML = "";
    return;
  }
  el.innerHTML = entries.map(([title, b64]) => {
    const src = String(b64).startsWith("data:") ? b64 : `data:image/png;base64,${b64}`;
    return `<div>
      <div class="chipds-plot-title">${chipdsEsc(String(title).replace(/_/g, " "))}</div>
      <img src="${src}" alt="${chipdsEsc(title)}">
    </div>`;
  }).join("");
  el.classList.remove("hidden");
}

function renderChipdsTableFromRows(rows, statusMsg) {
  const status = document.getElementById("chipds-qc-status");
  const summary = document.getElementById("chipds-qc-summary");
  const wrap = document.getElementById("chipds-qc-table-wrap");
  const table = document.getElementById("chipds-qc-table");
  if (status && statusMsg) {
    status.textContent = statusMsg;
    status.className = "alert alert-success";
    status.classList.remove("hidden");
  }
  if (summary) summary.classList.add("hidden");
  if (!table || !wrap) return;
  if (!rows?.length) {
    wrap.classList.add("hidden");
    return;
  }
  const cols = Object.keys(rows[0]);
  table.querySelector("thead").innerHTML =
    `<tr>${cols.map((c) => `<th>${chipdsEsc(c)}</th>`).join("")}</tr>`;
  table.querySelector("tbody").innerHTML = rows.map((row) =>
    `<tr>${cols.map((c) => `<td>${chipdsEsc(row[c])}</td>`).join("")}</tr>`
  ).join("");
  wrap.classList.remove("hidden");
}

function renderChipdsJsonSlim(res, dropKeys = []) {
  const jsonEl = document.getElementById("chipds-qc-json");
  if (!jsonEl) return;
  const slim = { ...res };
  for (const k of dropKeys) delete slim[k];
  if (slim.plots) slim.plots = Object.keys(slim.plots);
  jsonEl.textContent = JSON.stringify(slim, null, 2);
  jsonEl.classList.remove("hidden");
}

function setChipdsError(msg) {
  const status = document.getElementById("chipds-qc-status");
  if (status) {
    status.textContent = msg || "失败";
    status.className = "alert alert-error";
    status.classList.remove("hidden");
  }
  document.getElementById("chipds-qc-summary")?.classList.add("hidden");
  document.getElementById("chipds-qc-table-wrap")?.classList.add("hidden");
  document.getElementById("chipds-tool-plots")?.classList.add("hidden");
}

async function refreshChipdsToolStatus() {
  const hints = document.getElementById("chipds-tool-hints");
  const setBadge = (id, ok, label) => {
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = `${label}: ${ok ? "已安装" : "未安装"}`;
    el.className = `chipds-tool-badge ${ok ? "chipds-tool-badge--ok" : "chipds-tool-badge--miss"}`;
  };
  try {
    const res = await API.chipToolsStatus();
    const tools = res?.tools || {};
    setBadge("chipds-tool-homer", !!tools.homer?.available, "HOMER");
    setBadge("chipds-tool-diffbind", !!tools.diffbind?.available, "DiffBind");
    setBadge("chipds-tool-deeptools", !!tools.deeptools?.available, "deepTools");
    setBadge("chipds-tool-genomicranges", !!tools.genomicranges?.available, "GenomicRanges");
    const hintParts = [];
    const usable = tools.homer?.genomes_usable || tools.homer?.genomes_installed || [];
    const onDisk = tools.homer?.genomes_on_disk || [];
    if (tools.homer?.available) {
      hintParts.push(
        usable.length
          ? `HOMER 可用基因组: ${usable.join(", ")}`
          : "HOMER CLI 已找到，但尚无已注册基因组（需 configureHomer.pl -install）"
      );
      if (onDisk.length && (!usable.length || onDisk.some((g) => !usable.includes(g)))) {
        hintParts.push(`磁盘目录（未全部注册）: ${onDisk.join(", ")}`);
      }
    }
    if (tools.homer?.install_hint) hintParts.push(tools.homer.install_hint);
    if (tools.diffbind?.install_hint) hintParts.push(tools.diffbind.install_hint);
    if (tools.deeptools?.install_hint) hintParts.push(tools.deeptools.install_hint);
    if (tools.bedtools && !tools.bedtools.available && tools.bedtools.note) {
      hintParts.push(tools.bedtools.note);
    }
    if (hints) hints.textContent = hintParts.length
      ? hintParts.join(" · ")
      : "工具均已检测到，可直接在下方面板运行。";
  } catch (e) {
    setBadge("chipds-tool-homer", false, "HOMER");
    setBadge("chipds-tool-diffbind", false, "DiffBind");
    setBadge("chipds-tool-deeptools", false, "deepTools");
    setBadge("chipds-tool-genomicranges", false, "GenomicRanges");
    if (hints) hints.textContent = e.message || "无法检测工具状态（请确认 API 已启动）";
  }
}

async function runChipHomerOnPage() {
  setLoading(true);
  try {
    if (!localStorage.getItem("emp_session_id")) await API.createSession();
    // Refresh badge / peaks metadata only — do not clobber a manual genome choice.
    const peaks = await refreshChipdsLastPeaks({ forceList: true, preserveGenomeSelects: true });
    const peaksUi = chipGenomeToUi(chipEffectivePeakGenome(peaks));
    const genomeChosen = document.getElementById("chipds-homer-genome")?.value || peaksUi || "hg38";
    // Only warn when peak metadata and HOMER select disagree *and* user has not locked Genome mapping.
    if (peaksUi && genomeChosen && peaksUi !== genomeChosen && !chipAnnoGenomeIsUserSet()) {
      toast(`峰文件基因组为 ${peaksUi}，当前选择 ${genomeChosen}，结果可能无意义`, "warning");
    }
    const res = await API.chipHomer({
      genome: genomeChosen,
      size: +document.getElementById("chipds-homer-size")?.value || 200,
      motif_length: document.getElementById("chipds-homer-len")?.value || "8,10,12",
      annotate: document.getElementById("chipds-homer-annotate")?.value === "1",
    });
    if (!res?.success) throw new Error(res?.error || "HOMER failed");
    // Keep the user's select value; do not force-echo peak assembly.
    renderChipdsToolPlots(null);
    const rows = res.top_motifs || res.annotate?.preview || [];
    renderChipdsTableFromRows(
      rows,
      `HOMER 成功 · ${res.n_known_motifs ?? rows.length} motifs · genome ${res.genome || genomeChosen} · ${res.output_dir || ""}`
    );
    const summary = document.getElementById("chipds-qc-summary");
    if (summary) {
      summary.innerHTML = `
        <div><strong>峰数</strong> ${chipdsEsc(res.n_peaks)}</div>
        <div><strong>命令</strong> <code>${chipdsEsc(res.command || "")}</code></div>
        <div><strong>knownResults</strong> ${chipdsEsc(res.known_results || "—")}</div>
      `;
      summary.classList.remove("hidden");
    }
    renderChipdsJsonSlim(res, ["top_motifs"]);
    document.getElementById("chipds-qc-status")?.scrollIntoView({ behavior: "smooth", block: "nearest" });
    toast("HOMER motif 完成", "success");
  } catch (e) {
    setChipdsError(e.message);
    renderChipdsJsonSlim({ success: false, error: e.message });
    toast(e.message, "error");
  } finally {
    setLoading(false);
  }
}

async function runChipDiffBindOnPage() {
  setLoading(true);
  try {
    if (!localStorage.getItem("emp_session_id")) await API.createSession();
    const res = await API.chipDiffBind({
      method: document.getElementById("chipds-db-method")?.value || "DESeq2",
      fdr: +document.getElementById("chipds-db-fdr")?.value || 0.05,
      top_n: +document.getElementById("chipds-db-topn")?.value || 50,
    });
    renderChipdsToolPlots(res.plots || null);
    const rows = res.top_sites || [];
    const sum = res.summary || {};
    renderChipdsTableFromRows(
      rows,
      `DiffBind 成功 · DB ${sum.n_db ?? "—"} / ${sum.n_total ?? rows.length} · T=${res.n_treatment} C=${res.n_control}`
    );
    const summary = document.getElementById("chipds-qc-summary");
    if (summary) {
      summary.innerHTML = `
        <div><strong>差异位点 (FDR&lt;${chipdsEsc(res.fdr_threshold)})</strong> ${chipdsEsc(sum.n_db)} · 非差异 ${chipdsEsc(sum.n_not_db)}</div>
        <div><strong>报告</strong> ${chipdsEsc(res.report_csv || "—")}</div>
        <div><strong>样本表</strong> ${chipdsEsc(res.samplesheet || "—")}</div>
      `;
      summary.classList.remove("hidden");
    }
    renderChipdsJsonSlim(res, ["top_sites", "plots"]);
    document.getElementById("chipds-qc-status")?.scrollIntoView({ behavior: "smooth", block: "nearest" });
    toast("DiffBind 完成", "success");
  } catch (e) {
    setChipdsError(e.message);
    renderChipdsJsonSlim({ success: false, error: e.message });
    toast(e.message, "error");
  } finally {
    setLoading(false);
  }
}

async function runChipDeepToolsOnPage() {
  setLoading(true);
  try {
    if (!localStorage.getItem("emp_session_id")) await API.createSession();
    const mode = document.getElementById("chipds-dt-mode")?.value || "heatmap";
    const res = await API.chipDeepTools({
      mode,
      bin_size: +document.getElementById("chipds-dt-binsize")?.value || 50,
      before_region: +document.getElementById("chipds-dt-before")?.value || 1000,
      after_region: +document.getElementById("chipds-dt-after")?.value || 1000,
      normalize_using: document.getElementById("chipds-dt-norm")?.value || "RPKM",
    });
    renderChipdsToolPlots(res.plots || null);
    const status = document.getElementById("chipds-qc-status");
    if (status) {
      status.textContent = `deepTools ${res.mode || mode} 成功 · ${res.output_dir || ""}`;
      status.className = "alert alert-success";
      status.classList.remove("hidden");
    }
    const summary = document.getElementById("chipds-qc-summary");
    if (summary) {
      const cov = (res.coverage_files || []).map((p) => basenameSafe(p)).join(", ");
      summary.innerHTML = `
        <div><strong>模式</strong> ${chipdsEsc(res.mode || mode)}</div>
        ${res.n_peaks != null ? `<div><strong>峰数</strong> ${chipdsEsc(res.n_peaks)}</div>` : ""}
        ${res.n_bams != null ? `<div><strong>BAM 数</strong> ${chipdsEsc(res.n_bams)}</div>` : ""}
        ${cov ? `<div><strong>coverage</strong> ${chipdsEsc(cov)}</div>` : ""}
        ${res.plot_path ? `<div><strong>图</strong> ${chipdsEsc(res.plot_path)}</div>` : ""}
      `;
      summary.classList.remove("hidden");
    }
    document.getElementById("chipds-qc-table-wrap")?.classList.add("hidden");
    renderChipdsJsonSlim(res, ["plots"]);
    document.getElementById("chipds-qc-status")?.scrollIntoView({ behavior: "smooth", block: "nearest" });
    toast(`deepTools ${mode} 完成`, "success");
  } catch (e) {
    setChipdsError(e.message);
    renderChipdsJsonSlim({ success: false, error: e.message });
    toast(e.message, "error");
  } finally {
    setLoading(false);
  }
}

function basenameSafe(p) {
  const s = String(p || "");
  const i = Math.max(s.lastIndexOf("/"), s.lastIndexOf("\\"));
  return i >= 0 ? s.slice(i + 1) : s;
}

/** Treat UI placeholders like /path/to/... as unset. */
function isChipPlaceholderPath(p) {
  const s = String(p || "").trim();
  if (!s) return true;
  if (/^(\/path\/to\/|C:\\path\\to\\|\/path\\to\\)/i.test(s)) return true;
  if (/path/i.test(s) && /(rep2_or_markB|markC)\.bed$/i.test(s)) return true;
  return false;
}

/** Map session/MACS genome codes to HOMER / peaks_ops UI select values.
 *  Dropdown values: hg38 | hg19 | mm10 | mm39. Never returns hg18.
 */
function chipGenomeToUi(g) {
  const s = String(g || "").toLowerCase().trim();
  if (["mm", "mm10", "mouse", "mu", "m"].includes(s)) return "mm10";
  if (s === "mm39") return "mm39";
  if (["hg19", "grch37"].includes(s)) return "hg19";
  // hs / human / hg38 / legacy hg18 → hg38 (do not surface hg18 in the UI)
  if (["hg38", "grch38", "hs", "human", "h", "hg18", "ncbi36"].includes(s)) return "hg38";
  if (["hg38", "hg19", "mm10", "mm39"].includes(s)) return s;
  return "hg38";
}

/** Peak-file identity used to detect when last_peaks has been replaced. */
function chipdsLastPeaksIdentity(peaks) {
  return String(peaks?.peak_file || "").trim();
}

function chipdsGenomeSelectIsUserSet(el) {
  return el?.dataset?.userSet === "1";
}

function markChipdsGenomeSelectUserSet(el) {
  if (el) el.dataset.userSet = "1";
}

function clearChipdsGenomeSelectUserSet(el) {
  if (el) delete el.dataset.userSet;
}

/**
 * Sync HOMER / peaks_ops genome dropdowns from last_peaks (or an explicit genome).
 * @param {string} genome
 * @param {{ force?: boolean }} [opts] force=true clears userSet and always writes
 */
function syncChipdsGenomeSelects(genome, opts = {}) {
  const { force = false } = opts;
  const ui = chipGenomeToUi(genome);
  const homer = document.getElementById("chipds-homer-genome");
  const ops = document.getElementById("chipds-ops-genome");
  // Only assign when the option exists — never inject orphan values like hg18.
  if (homer && [...homer.options].some((o) => o.value === ui)) {
    if (force || !chipdsGenomeSelectIsUserSet(homer)) {
      homer.value = ui;
      if (force) clearChipdsGenomeSelectUserSet(homer);
    }
  }
  if (ops && [...ops.options].some((o) => o.value === ui)) {
    if (force || !chipdsGenomeSelectIsUserSet(ops)) {
      ops.value = ui;
      if (force) clearChipdsGenomeSelectUserSet(ops);
    }
  }
}

function chipPeakEntryLabel(entry) {
  if (!entry) return "";
  if (entry.label) return entry.label;
  const srcRaw = String(entry.source || "upload").toLowerCase();
  const src = (srcRaw === "upload" || srcRaw === "preimported")
    ? "上传"
    : (srcRaw === "macs" ? "MACS" : `衍生/${srcRaw.replace(/^ops_/, "")}`);
  const name = entry.name || entry.display_name || basenameSafe(entry.peak_file || entry.path || "") || "peaks";
  const n = entry.n_peaks;
  const nTxt = (n == null || n === "")
    ? "?"
    : (Number(n) === 1 ? "1 peak" : `${n} peaks`);
  return `${src}: ${name} (${nTxt})`;
}

function fillChipPeakSelectEl(sel, peakFiles, activeId) {
  if (!sel) return;
  const prev = sel.value;
  const files = Array.isArray(peakFiles) ? peakFiles : [];
  sel.innerHTML = "";
  if (!files.length) {
    const opt = document.createElement("option");
    opt.value = "";
    opt.textContent = t("chip.opt.noPeaks");
    sel.appendChild(opt);
    return;
  }
  for (const e of files) {
    const opt = document.createElement("option");
    opt.value = e.id || e.peak_file || "";
    opt.textContent = chipPeakEntryLabel(e);
    opt.title = e.peak_file || e.path || "";
    if (Number(e.n_peaks) === 0) opt.dataset.empty = "1";
    sel.appendChild(opt);
  }
  const want = activeId || prev || "";
  if (want && [...sel.options].some((o) => o.value === want)) {
    sel.value = want;
  } else {
    sel.selectedIndex = 0;
  }
}

function renderChipPeakSelectors(peakFiles, activeId, lastPeaks) {
  fillChipPeakSelectEl(document.getElementById("chip-peak-select"), peakFiles, activeId);
  fillChipPeakSelectEl(document.getElementById("chipds-peak-select"), peakFiles, activeId);
  fillChipPeakSelectEl(document.getElementById("chip-deps-peak"), peakFiles, activeId);
  if (lastPeaks?.peak_file) {
    adoptChipLastPeaks(lastPeaks);
    window._emp.chipPeakFiles = peakFiles || [];
    window._emp.chipActivePeakId = activeId || lastPeaks.id || "";
  }
}

function renderChipdsLastPeaksBadge(peaks) {
  const badge = document.getElementById("chipds-last-peaks-badge");
  if (!badge) return;
  const path = peaks?.peak_file || "";
  if (!path) {
    badge.textContent = t("chipds.peaks.empty");
    badge.className = "chipds-last-peaks-badge chipds-last-peaks-badge--empty";
    badge.title = "";
    return;
  }
  const name = basenameSafe(path);
  const gLabel = chipAnnoGenomeIsUserSet()
    ? chipAssemblyForAnnoGenome(chipAnnoGenomeValue())
    : (peaks?.assembly || chipGenomeToUi(peaks?.genome) || peaks?.genome || "");
  const genome = gLabel ? ` · ${gLabel}` : "";
  const srcRaw = String(peaks?.source || "").toLowerCase();
  const src = srcRaw
    ? ` · ${(srcRaw === "preimported" || srcRaw === "upload") ? t("chipds.peaks.srcUpload") : (srcRaw === "macs" ? "MACS" : srcRaw)}`
    : "";
  const n = peaks?.n_peaks;
  const nTxt = (n == null || n === "") ? "" : ` · ${n} peaks`;
  badge.textContent = `${name}${genome}${src}${nTxt}`;
  badge.title = path;
  if (Number(n) === 0) {
    badge.className = "chipds-last-peaks-badge chipds-last-peaks-badge--warn";
    badge.textContent += t("chipds.peaks.emptyFile");
  } else {
    badge.className = "chipds-last-peaks-badge chipds-last-peaks-badge--ok";
  }
}

/**
 * Refresh last_peaks badge / registry. Genome selects are synced only when:
 * - forceGenomeSync (e.g. 「使用已上传峰文件」), or
 * - last_peaks identity (peak_file path) changed AND user has not overridden Genome mapping, or
 * - first load / selects not yet userSet (and preserveGenomeSelects is false).
 * Manual Genome mapping always wins for the active session after the user sets it.
 */
async function refreshChipdsLastPeaks(opts = {}) {
  const {
    toastOnMissing = false,
    forceList = false,
    preserveGenomeSelects = false,
    forceGenomeSync = false,
    preferUpload = false,
  } = opts;
  window._emp = window._emp || {};
  const prevIdentity = window._emp.chipLastPeaksIdentity || chipdsLastPeaksIdentity(window._emp.chipLastPeaks);
  let peaks = (!forceList && window._emp?.chipLastPeaks?.peak_file)
    ? window._emp.chipLastPeaks
    : null;
  let peakFiles = window._emp.chipPeakFiles || [];
  let activeId = window._emp.chipActivePeakId || "";
  try {
    if (!localStorage.getItem("emp_session_id")) await API.createSession();
    const res = await API.chipListPeaks();
    peakFiles = Array.isArray(res?.peak_files) ? res.peak_files : [];
    activeId = res?.active_peak_id || "";
    if (res?.last_peaks?.peak_file) {
      peaks = adoptChipLastPeaks(res.last_peaks);
    }
    // 「使用已上传峰文件」: bind newest upload entry if present.
    if (preferUpload) {
      const uploads = peakFiles.filter((e) => {
        const s = String(e.source || "").toLowerCase();
        return (s === "upload" || s === "preimported") && Number(e.n_peaks) > 0;
      });
      const pick = uploads[0] || peakFiles.find((e) => Number(e.n_peaks) > 0) || null;
      if (pick?.id) {
        const sel = await API.chipSelectPeak({ peak_id: pick.id });
        if (sel?.last_peaks?.peak_file) {
          peaks = adoptChipLastPeaks(sel.last_peaks);
          activeId = sel.active_peak_id || pick.id;
          peakFiles = Array.isArray(sel.peak_files) ? sel.peak_files : peakFiles;
        }
      }
    }
  } catch (_) {
    // session / API may not be ready
  }
  window._emp.chipPeakFiles = peakFiles;
  window._emp.chipActivePeakId = activeId;
  if (chipAnnoGenomeIsUserSet()) applyChipSessionGenome(chipAnnoGenomeValue());
  renderChipPeakSelectors(peakFiles, activeId, peaks);
  const nextIdentity = chipdsLastPeaksIdentity(peaks);
  const identityChanged = Boolean(nextIdentity && nextIdentity !== prevIdentity);
  if (nextIdentity) window._emp.chipLastPeaksIdentity = nextIdentity;

  renderChipdsLastPeaksBadge(peaks);
  if (forceGenomeSync) {
    const annoG = document.getElementById("chip-anno-genome");
    if (annoG) delete annoG.dataset.userSet;
    syncChipAnnoFromPeakGenome(peaks?.genome || peaks?.assembly, { force: true });
  } else if (chipAnnoGenomeIsUserSet()) {
    applyChipSessionGenome(chipAnnoGenomeValue());
    syncChipAnnoFromPeakGenome(chipAnnoGenomeValue(), { force: false });
  } else if (identityChanged && !preserveGenomeSelects) {
    syncChipAnnoFromPeakGenome(peaks?.genome || peaks?.assembly, { force: true });
  } else if (preserveGenomeSelects) {
    // Upload / soft refresh: keep Genome mapping dropdown; write it onto session peaks.
    applyChipSessionGenome(chipAnnoGenomeValue());
  }
  refreshChipPeakStatus();

  const peakGenome = chipEffectivePeakGenome(peaks);
  if (peakGenome) {
    if (forceGenomeSync) {
      syncChipdsGenomeSelects(peakGenome, { force: true });
    } else if (identityChanged && !preserveGenomeSelects && !chipAnnoGenomeIsUserSet()) {
      syncChipdsGenomeSelects(peakGenome, { force: true });
    } else if (!preserveGenomeSelects) {
      syncChipdsGenomeSelects(peakGenome, { force: false });
    }
  }
  if (!peaks?.peak_file && toastOnMissing) {
    toast("请先在 ChIPseq 页上传峰文件或运行 MACS", "warning");
  } else if (peaks?.peak_file && Number(peaks.n_peaks) === 0 && toastOnMissing) {
    toast("当前峰文件为 0 peaks — 请在下拉中切换到其他上传/MACS 结果", "warning");
  }
  return peaks;
}

async function onChipPeakSelectChange(ev) {
  const peakId = (ev?.currentTarget?.value || "").trim();
  if (!peakId) return;
  setLoading(true);
  try {
    if (!localStorage.getItem("emp_session_id")) await API.createSession();
    const res = await API.chipSelectPeak({ peak_id: peakId });
    if (!res?.success && res?.error) throw new Error(res.error);
    window._emp.chipLastPeaks = adoptChipLastPeaks(res.last_peaks || {});
    window._emp.chipActivePeakId = res.active_peak_id || peakId;
    window._emp.chipPeakFiles = Array.isArray(res.peak_files) ? res.peak_files : (window._emp.chipPeakFiles || []);
    window._emp.chipLastPeaksIdentity = chipdsLastPeaksIdentity(window._emp.chipLastPeaks);
    renderChipPeakSelectors(window._emp.chipPeakFiles, window._emp.chipActivePeakId, window._emp.chipLastPeaks);
    // Prefer keeping manual Genome mapping across peak switches.
    if (chipAnnoGenomeIsUserSet()) {
      const g = chipAnnoGenomeValue();
      applyChipSessionGenome(g);
      await persistChipPeakGenome(g);
    } else {
      syncChipAnnoFromPeakGenome(
        window._emp.chipLastPeaks?.genome || window._emp.chipLastPeaks?.assembly,
        { force: true }
      );
    }
    renderChipdsLastPeaksBadge(window._emp.chipLastPeaks);
    refreshChipPeakStatus();
    const g = chipEffectivePeakGenome(window._emp.chipLastPeaks);
    if (g) syncChipdsGenomeSelects(g, { force: !chipAnnoGenomeIsUserSet() });
    const label = chipPeakEntryLabel(window._emp.chipLastPeaks);
    if (res.warning) toast(res.warning, "warning");
    else toast(`已切换当前峰文件: ${label || basenameSafe(window._emp.chipLastPeaks?.peak_file || "")}`, "success");
  } catch (e) {
    toast(e.message, "error");
    await refreshChipdsLastPeaks({ forceList: true, preserveGenomeSelects: true });
  } finally {
    setLoading(false);
  }
}

function collectChipPeaksOpsParams(op) {
  const peakBRaw = (document.getElementById("chipds-ops-peak-b")?.value || "").trim();
  const peakCRaw = (document.getElementById("chipds-ops-peak-c")?.value || "").trim();
  const peakB = isChipPlaceholderPath(peakBRaw) ? "" : peakBRaw;
  const peakC = isChipPlaceholderPath(peakCRaw) ? "" : peakCRaw;
  const params = {
    op,
    genome: document.getElementById("chipds-ops-genome")?.value || "hg38",
    merge_gap: +document.getElementById("chipds-ops-merge-gap")?.value || 0,
    summit_size: +document.getElementById("chipds-ops-summit")?.value || 250,
    promoter_window: +document.getElementById("chipds-ops-promoter")?.value || 2000,
    stitch_gap: +document.getElementById("chipds-ops-stitch")?.value || 12500,
  };
  if (peakB) params.peak_b = peakB;
  if (peakC) params.peak_c = peakC;
  return params;
}

async function runChipPeaksOpsOnPage(op) {
  setLoading(true);
  try {
    if (!localStorage.getItem("emp_session_id")) await API.createSession();
    await refreshChipdsLastPeaks({ forceList: true, preserveGenomeSelects: true });
    const params = collectChipPeaksOpsParams(op);
    const needsB = ["overlap", "idr", "bivalent", "chromatin_proxy"].includes(op);
    if (needsB && !params.peak_b) {
      throw new Error("该操作需要 peak_b（第二峰集路径）。请在上方「Peak 集合操作」面板填写真实路径（勿用 /path/to/ 占位符）。");
    }
    const res = await API.chipPeaksOps(params);
    if (!res?.success) throw new Error(res?.error || "peaks_ops failed");
    if (res.last_peaks?.peak_file) {
      window._emp = window._emp || {};
      const prevId = window._emp.chipLastPeaksIdentity || chipdsLastPeaksIdentity(window._emp.chipLastPeaks);
      adoptChipLastPeaks(res.last_peaks);
      const nextId = chipdsLastPeaksIdentity(window._emp.chipLastPeaks);
      window._emp.chipLastPeaksIdentity = nextId;
      renderChipdsLastPeaksBadge(window._emp.chipLastPeaks);
      // New peak file from ops → seed genome selects unless user already locked Genome mapping.
      if ((res.last_peaks.assembly || res.last_peaks.genome) && nextId && nextId !== prevId) {
        if (chipAnnoGenomeIsUserSet()) {
          applyChipSessionGenome(chipAnnoGenomeValue());
          await persistChipPeakGenome(chipAnnoGenomeValue());
        } else {
          syncChipdsGenomeSelects(res.last_peaks.assembly || res.last_peaks.genome, { force: true });
        }
      }
    }
    renderChipdsToolPlots(res.plots || null);
    const rows = res.preview || (res.transition?.top_transitions) || [];
    const statusBits = [
      `peaks_ops · ${res.op || op}`,
      res.n_after != null ? `after ${res.n_after}` : null,
      res.n_promoter != null ? `promoter ${res.n_promoter}` : null,
      res.n_enhancer != null ? `enhancer ${res.n_enhancer}` : null,
      res.n_super != null ? `SE ${res.n_super}` : null,
      res.n_domains != null ? `domains ${res.n_domains}` : null,
      res.n_bivalent != null ? `bivalent ${res.n_bivalent}` : null,
      res.jaccard != null ? `jaccard ${Number(res.jaccard).toFixed(3)}` : null,
      res.output_bed || res.files?.shared || "",
    ].filter(Boolean);
    renderChipdsTableFromRows(rows, statusBits.join(" · "));
    const summary = document.getElementById("chipds-qc-summary");
    if (summary) {
      const extras = [];
      if (res.note) extras.push(`<div><strong>说明</strong> ${chipdsEsc(res.note)}</div>`);
      if (res.state_counts) {
        extras.push(`<div><strong>状态计数</strong> ${chipdsEsc(JSON.stringify(res.state_counts))}</div>`);
      }
      if (res.distance_bins) {
        extras.push(`<div><strong>距离分箱</strong> ${chipdsEsc(JSON.stringify(res.distance_bins))}</div>`);
      }
      if (res.counts) {
        extras.push(`<div><strong>集合计数</strong> ${chipdsEsc(JSON.stringify(res.counts))}</div>`);
      }
      summary.innerHTML = extras.join("") || `<div><strong>op</strong> ${chipdsEsc(op)}</div>`;
      summary.classList.remove("hidden");
    }
    renderChipdsJsonSlim(res, ["preview", "plots"]);
    document.getElementById("chipds-qc-status")?.scrollIntoView({ behavior: "smooth", block: "nearest" });
    toast(`Peak ops「${op}」完成`, "success");
  } catch (e) {
    setChipdsError(e.message);
    renderChipdsJsonSlim({ success: false, error: e.message });
    toast(e.message, "error");
  } finally {
    setLoading(false);
  }
}

function bindChipdsToolPanels() {
  if (bindChipdsToolPanels._bound) return;
  bindChipdsToolPanels._bound = true;
  document.getElementById("chipds-btn-refresh-tools")?.addEventListener("click", () => refreshChipdsToolStatus());
  document.getElementById("chipds-btn-homer")?.addEventListener("click", () => runChipHomerOnPage());
  document.getElementById("chipds-btn-diffbind")?.addEventListener("click", () => runChipDiffBindOnPage());
  document.getElementById("chipds-btn-deeptools")?.addEventListener("click", () => runChipDeepToolsOnPage());
  document.getElementById("chipds-btn-use-uploaded-peaks")?.addEventListener("click", async () => {
    const peaks = await refreshChipdsLastPeaks({
      toastOnMissing: true,
      forceList: true,
      forceGenomeSync: true,
      preferUpload: true,
    });
    if (peaks?.peak_file) toast(`已同步峰文件: ${basenameSafe(peaks.peak_file)}`, "success");
  });
  document.getElementById("chipds-btn-refresh-peaks")?.addEventListener("click", async () => {
    await refreshChipdsLastPeaks({ forceList: true, preserveGenomeSelects: true, toastOnMissing: true });
    toast("峰文件列表已刷新", "success");
  });
  document.getElementById("chipds-peak-select")?.addEventListener("change", onChipPeakSelectChange);
  document.getElementById("chip-peak-select")?.addEventListener("change", onChipPeakSelectChange);
  // Track manual genome choices so refresh / run does not overwrite them.
  for (const id of ["chipds-homer-genome", "chipds-ops-genome"]) {
    document.getElementById(id)?.addEventListener("change", (ev) => {
      markChipdsGenomeSelectUserSet(ev.currentTarget);
    });
  }
}

function renderChipPeakQcResult(res) {
  const status = document.getElementById("chipds-qc-status");
  const summary = document.getElementById("chipds-qc-summary");
  const wrap = document.getElementById("chipds-qc-table-wrap");
  const table = document.getElementById("chipds-qc-table");
  const jsonEl = document.getElementById("chipds-qc-json");
  document.getElementById("chipds-tool-plots")?.classList.add("hidden");

  if (!res?.success) {
    if (status) {
      status.textContent = res?.error || "Peak QC 失败";
      status.className = "alert alert-error";
      status.classList.remove("hidden");
    }
    summary?.classList.add("hidden");
    wrap?.classList.add("hidden");
    if (jsonEl) {
      jsonEl.textContent = JSON.stringify(res || {}, null, 2);
      jsonEl.classList.remove("hidden");
    }
    return;
  }

  if (status) {
    status.textContent = `Peak QC 成功 · ${res.n_peaks} peaks · ${res.path || ""}`;
    status.className = "alert alert-success";
    status.classList.remove("hidden");
  }

  const ws = res.width_summary || {};
  const ss = res.score_summary;
  const chromLines = (res.chrom_counts || [])
    .slice(0, 12)
    .map((c) => `${c.chrom}: ${c.n}`)
    .join(" · ");
  if (summary) {
    summary.innerHTML = `
      <div><strong>峰数</strong> ${chipdsEsc(res.n_peaks)}</div>
      <div><strong>宽度</strong> min ${chipdsEsc(ws.min)} · median ${chipdsEsc(ws.median)} · mean ${chipdsEsc(ws.mean != null ? Number(ws.mean).toFixed(1) : "—")} · max ${chipdsEsc(ws.max)}</div>
      ${ss ? `<div><strong>Score (${chipdsEsc(res.score_column || "score")})</strong> min ${chipdsEsc(ss.min)} · median ${chipdsEsc(ss.median)} · mean ${chipdsEsc(ss.mean != null ? Number(ss.mean).toFixed(2) : "—")} · max ${chipdsEsc(ss.max)}</div>` : `<div><strong>Score</strong> —</div>`}
      <div><strong>染色体 (top)</strong> ${chipdsEsc(chromLines || "—")}</div>
    `;
    summary.classList.remove("hidden");
  }

  const preview = res.preview || [];
  if (table && wrap) {
    if (!preview.length) {
      wrap.classList.add("hidden");
    } else {
      const cols = Object.keys(preview[0]);
      table.querySelector("thead").innerHTML =
        `<tr>${cols.map((c) => `<th>${chipdsEsc(c)}</th>`).join("")}</tr>`;
      table.querySelector("tbody").innerHTML = preview.map((row) =>
        `<tr>${cols.map((c) => `<td>${chipdsEsc(row[c])}</td>`).join("")}</tr>`
      ).join("");
      wrap.classList.remove("hidden");
    }
  }

  if (jsonEl) {
    const slim = { ...res };
    delete slim.preview;
    jsonEl.textContent = JSON.stringify(slim, null, 2);
    jsonEl.classList.remove("hidden");
  }
}

async function runChipPeakQcOnPage() {
  setLoading(true);
  try {
    if (!localStorage.getItem("emp_session_id")) await API.createSession();
    const res = await API.chipPeakQc();
    renderChipPeakQcResult(res);
    document.getElementById("chipds-qc-status")?.scrollIntoView({ behavior: "smooth", block: "nearest" });
    if (res?.success) toast(`Peak QC: ${res.n_peaks} peaks`, "success");
    else toast(res?.error || "Peak QC 失败", "error");
  } catch (e) {
    renderChipPeakQcResult({ success: false, error: e.message });
    toast(e.message, "error");
  } finally {
    setLoading(false);
  }
}

async function loadChipDownstreamPage() {
  bindChipDownstreamFilters();
  bindChipdsToolPanels();
  refreshChipdsToolStatus();
  refreshChipdsLastPeaks({ forceList: true });
  try {
    if (!_chipdsCatalog) {
      _chipdsCatalog = await fetchChipDownstreamCatalog();
    }
    fillChipDownstreamStageSelect(_chipdsCatalog);
    renderChipDownstreamMarks(_chipdsCatalog.mark_strategies || []);
    const filtered = filterChipDownstreamItems(_chipdsCatalog.items || []);
    updateChipDownstreamSummary(_chipdsCatalog, filtered.length);
    renderChipDownstreamCatalog(_chipdsCatalog);
    if (window.lucide) lucide.createIcons();
  } catch (e) {
    const root = document.getElementById("chipds-catalog");
    if (root) root.innerHTML = `<p class="hint" style="color:#991b1b">${chipdsEsc(e.message)}</p>`;
    toast(e.message, "error");
  }
}

// ── ChIP unified wizard + recipe packs ──────────────────────────────
let _chipRecipePacks = null;
let _chipWizardBound = false;

function ensureChipUnifiedLayout() {
  const host = document.getElementById("chip-advanced-downstream-host");
  const down = document.getElementById("page-chipseq_downstream");
  if (!host || !down || host.dataset.moved === "1") return;
  const kids = [...down.children];
  for (const el of kids) host.appendChild(el);
  host.dataset.moved = "1";
  down.classList.add("hidden");
  loadChipDownstreamPage().catch(() => {});
}

function setChipWizardStep(step) {
  const s = String(step || "1");
  window._emp.chipWizardStep = s;
  document.querySelectorAll(".chip-wizard-tab").forEach((btn) => {
    const on = String(btn.dataset.chipStep) === s;
    btn.classList.toggle("active", on);
    btn.setAttribute("aria-selected", on ? "true" : "false");
  });
  document.querySelectorAll("[data-chip-step-panel]").forEach((panel) => {
    const on = String(panel.dataset.chipStepPanel) === s;
    panel.classList.toggle("hidden", !on);
  });
  if (s === "2") {
    refreshChipRecipeDeps();
    loadChipRecipePacks().catch(() => {});
  }
  if (s === "advanced") {
    ensureChipUnifiedLayout();
    loadChipDownstreamPage().catch(() => {});
  }
  if (!_chipWizardBound) {
    _chipWizardBound = true;
    document.getElementById("chip-wizard-tabs")?.addEventListener("click", (ev) => {
      const btn = ev.target.closest(".chip-wizard-tab");
      if (!btn) return;
      setChipWizardStep(btn.dataset.chipStep);
    });
    document.getElementById("chip-deps-refresh")?.addEventListener("click", () => refreshChipRecipeDeps());
    document.getElementById("chip-recipe-combo-run")?.addEventListener("click", () => {
      const ids = [...document.querySelectorAll("#chip-recipe-combo-checks input[type=checkbox]:checked")]
        .map((el) => el.value)
        .filter(Boolean);
      runChipRecipeCombo(ids);
    });
    document.getElementById("chip-deps-peak")?.addEventListener("change", async (ev) => {
      const v = ev.target.value;
      if (!v) return;
      try {
        await API.chipSelectPeak({ peak_id: v });
        await refreshChipPeakStatus();
      } catch (e) { toast(e.message, "error"); }
    });
  }
}

function _chipExpOmics(exp) {
  return exp?.omics || inferOmicsForExperiment(exp?.name) || "";
}

function fillChipRecipeDepSelects(exps) {
  const list = exps || window._emp.experiments || [];
  const none = `<option value="">${t("chip.opt.none")}</option>`;
  const opt = (e) => `<option value="${chipdsEsc(e.name)}">${chipdsEsc(e.name)}${e.omics ? ` (${chipdsEsc(e.omics)})` : ""}</option>`;
  const fill = (id, pred) => {
    const el = document.getElementById(id);
    if (!el) return;
    const prev = el.value;
    const matched = list.filter(pred);
    el.innerHTML = none + matched.map(opt).join("") +
      (matched.length < list.length
        ? `<optgroup label="${t("chip.opt.allExps")}">${list.map(opt).join("")}</optgroup>`
        : "");
    if (prev && [...el.options].some((o) => o.value === prev)) el.value = prev;
  };
  fill("chip-deps-rna", (e) => /transcriptomics|rna/i.test(_chipExpOmics(e)) || /rna|gene|tx/i.test(e.name));
  fill("chip-deps-proteomics", (e) => /proteomics|protein/i.test(_chipExpOmics(e)) || /prot/i.test(e.name));
  fill("chip-deps-m16s", (e) => /microbiome_16s|16s|tax/i.test(_chipExpOmics(e)) || /16s|m16s|tax/i.test(e.name));
  fill("chip-deps-mgx", (e) => /metagenomics|mgx/i.test(_chipExpOmics(e)) || /mgx|metagen|ko/i.test(e.name));
  fill("chip-deps-mbx", (e) => /metabolomics|mbx/i.test(_chipExpOmics(e)) || /mbx|metabol/i.test(e.name));
  const clin = document.getElementById("chip-deps-clinical");
  if (clin) {
    const prev = clin.value;
    clin.innerHTML = `${none}<option value="standalone">${t("chip.opt.standaloneClin")}</option>`;
    if (prev) clin.value = prev;
  }
}

async function refreshChipRecipeDeps() {
  fillChipRecipeDepSelects(window._emp.experiments || []);
  try {
    const bams = await API.chipListBams();
    const el = document.getElementById("chip-deps-bam");
    if (el) {
      el.textContent = `T: ${bams.n_treatment ?? 0} · C: ${bams.n_control ?? 0}`;
    }
  } catch (_) { /* ignore */ }
  try {
    await refreshChipdsLastPeaks({ forceList: true });
  } catch (_) { /* ignore */ }
}

async function loadChipRecipePacks() {
  const root = document.getElementById("chip-recipe-packs");
  if (!root) return;
  if (!_chipRecipePacks) {
    try {
      const r = await fetch(`data/chipseq_recipe_packs.json?v=recipes-v1`);
      if (!r.ok) throw new Error(`recipe packs HTTP ${r.status}`);
      _chipRecipePacks = await r.json();
    } catch (e) {
      try {
        const api = await API.chipRecipePacks();
        _chipRecipePacks = api.packs || api;
      } catch (e2) {
        root.innerHTML = `<p class="hint" style="color:#991b1b">${chipdsEsc(e2.message || e.message)}</p>`;
        return;
      }
    }
  }
  const packs = _chipRecipePacks.packs || [];
  const zh = getLocale() === "zh";
  const internal = packs.filter((p) => p.group === "chip_internal");
  const joint = packs.filter((p) => p.group === "joint");
  const card = (p) => {
    const title = zh ? (p.title_zh || p.title_en) : (p.title_en || p.title_zh);
    const desc = zh ? (p.description_zh || p.description_en) : (p.description_en || p.description_zh);
    const badge = p.group === "joint" ? t("chip.recipe.badge.joint") : t("chip.recipe.badge.chip");
    return `<article class="chip-recipe-card" data-pack-id="${chipdsEsc(p.id)}">
      <div class="chip-recipe-card-head">
        <span class="chip-badge ${p.group === "joint" ? "chip-badge--t" : "chip-badge--peak"}">${chipdsEsc(badge)}</span>
        <h5>${chipdsEsc(title)}</h5>
      </div>
      <p class="hint">${chipdsEsc(desc || "")}</p>
      <p class="chip-recipe-req"><strong>${t("chip.recipe.requires")}</strong> ${(p.requires || []).map(chipdsEsc).join(", ")}</p>
      <button type="button" class="btn btn-primary btn-sm" data-run-pack="${chipdsEsc(p.id)}">${t("chip.recipe.run")}</button>
    </article>`;
  };
  root.innerHTML = `
    <h4 class="chip-section-title">${t("chip.recipe.internal")}</h4>
    <div class="chip-recipe-grid">${internal.map(card).join("")}</div>
    <h4 class="chip-section-title">${t("chip.recipe.joint")}</h4>
    <div class="chip-recipe-grid">${joint.map(card).join("")}</div>`;
  root.querySelectorAll("[data-run-pack]").forEach((btn) => {
    btn.addEventListener("click", () => runChipRecipePack(btn.dataset.runPack));
  });

  const combo = _chipRecipePacks.combo || {};
  const note = document.getElementById("chip-recipe-combo-note");
  if (note) note.textContent = zh ? (combo.title_zh || _chipRecipePacks.combo_note_zh || "") : (combo.title_en || _chipRecipePacks.combo_note_en || "");
  const checks = document.getElementById("chip-recipe-combo-checks");
  if (checks) {
    const ids = combo.selectable_pack_ids || joint.map((p) => p.id);
    checks.innerHTML = ids.map((id) => {
      const p = packs.find((x) => x.id === id);
      const label = p ? (zh ? p.title_zh : p.title_en) : id;
      return `<label class="checkbox-label chip-recipe-combo-item">
        <input type="checkbox" value="${chipdsEsc(id)}">
        <span>${chipdsEsc(label || id)}</span>
      </label>`;
    }).join("");
  }
}

function chipRecipeLog(msg, kind = "info") {
  const el = document.getElementById("chip-recipe-results");
  if (!el) return;
  const line = document.createElement("div");
  line.className = `chip-recipe-log chip-recipe-log--${kind}`;
  line.textContent = msg;
  el.appendChild(line);
  el.scrollTop = el.scrollHeight;
}

function chipRecipeGate(pack) {
  const requires = pack.requires || [];
  const peakSel = document.getElementById("chip-deps-peak")?.value ||
    document.getElementById("chip-peak-select")?.value ||
    window._emp.chipLastPeaks?.peak_file;
  const rna = document.getElementById("chip-deps-rna")?.value || "";
  const pro = document.getElementById("chip-deps-proteomics")?.value || "";
  const m16s = document.getElementById("chip-deps-m16s")?.value || "";
  const mgx = document.getElementById("chip-deps-mgx")?.value || "";
  const mbx = document.getElementById("chip-deps-mbx")?.value || "";
  const clin = document.getElementById("chip-deps-clinical")?.value || "";
  const missing = [];
  for (const r of requires) {
    if (r === "peaks" && !peakSel) missing.push("peaks");
    if (r === "genome") { /* MACS/HOMER genome always available via UI */ }
    if (r === "bam_or_peaks" && !peakSel) {
      // BAM optional if peaks present; check later in deeptools
    }
    if (r === "rna_or_proteomics" && !rna && !pro) missing.push("RNA or proteomics");
    if (r === "m16s_or_mgx" && !m16s && !mgx) missing.push("16S or MGX");
    if (r === "mbx" && !mbx) missing.push("metabolomics");
    if (r === "clinical" && !clin) missing.push("clinical");
  }
  return { ok: !missing.length, missing, peakSel, rna, pro, m16s, mgx, mbx, clin };
}

async function runChipRecipePack(packId) {
  if (!_chipRecipePacks) await loadChipRecipePacks();
  const pack = (_chipRecipePacks?.packs || []).find((p) => p.id === packId);
  if (!pack) {
    toast(`Unknown pack: ${packId}`, "error");
    return;
  }
  const gate = chipRecipeGate(pack);
  if (!gate.ok) {
    toast(t("chip.recipe.missingDeps", null, { deps: gate.missing.join(", ") }), "error");
    chipRecipeLog(`[${packId}] blocked: ${gate.missing.join(", ")}`, "error");
    return;
  }
  const results = document.getElementById("chip-recipe-results");
  if (results) results.innerHTML = `<p class="hint">Running pack <strong>${chipdsEsc(packId)}</strong>…</p>`;
  chipRecipeLog(`[${packId}] start`, "info");
  setLoading(true);
  try {
    for (const step of pack.steps || []) {
      const action = step.action;
      const extra = step.requires_extra || [];
      if (extra.includes("bam_2t2c")) {
        try {
          const bams = await API.chipListBams();
          if ((bams.n_treatment || 0) < 2 || (bams.n_control || 0) < 2) {
            chipRecipeLog(`[${packId}] skip ${action} (need ≥2T+≥2C BAM)`, "warn");
            continue;
          }
        } catch (_) {
          chipRecipeLog(`[${packId}] skip ${action} (BAM check failed)`, "warn");
          continue;
        }
      }
      if (extra.includes("peak_b") && !document.getElementById("chipds-ops-peak-b")?.value) {
        chipRecipeLog(`[${packId}] skip ${action} (peak_b not set)`, "warn");
        continue;
      }
      if (extra.includes("rna") && !gate.rna) {
        chipRecipeLog(`[${packId}] skip ${action} (no RNA)`, "warn");
        continue;
      }
      if (extra.includes("rna_or_proteomics") && !gate.rna && !gate.pro) {
        chipRecipeLog(`[${packId}] skip ${action} (no RNA/proteomics)`, "warn");
        continue;
      }
      chipRecipeLog(`[${packId}] → ${action}`, "info");
      try {
        if (action === "chip_annotate") {
          await runChipAnnotate({ silentEmptyToast: true });
        } else if (action === "chip_rna_co") {
          if (!gate.rna) {
            chipRecipeLog(`[${packId}] skip ${action} (no RNA)`, "warn");
            continue;
          }
          const sel = document.getElementById("chip-rnaseq-exp");
          if (sel) sel.value = gate.rna;
          await API.chipRnaseqCoanalysis({
            rnaseq_experiment: gate.rna,
            genome: document.getElementById("chip-anno-genome")?.value || "mm",
            score_cutoff: +(document.getElementById("chip-co-score-cutoff")?.value || 10),
            min_total_counts: +(document.getElementById("chip-min-counts")?.value || 100),
            rnaseq_p_cutoff: +(document.getElementById("chip-rna-p-cutoff")?.value || 0.05),
            promoter_filter: !!document.getElementById("chip-promoter-filter")?.checked,
          });
        } else if (action === "chip_cross") {
          await API.chipCrossOmics({
            rnaseq_experiment: gate.rna || null,
            proteomics_experiment: gate.pro || null,
            rnaseq_p_cutoff: +(document.getElementById("chip-cross-rna-p")?.value || 0.05),
            rnaseq_fc_cutoff: +(document.getElementById("chip-cross-rna-fc")?.value || 1),
            proteomics_p_cutoff: +(document.getElementById("chip-cross-pro-p")?.value || 0.05),
            proteomics_fc_cutoff: +(document.getElementById("chip-cross-pro-fc")?.value || 0.5),
          });
        } else if (action === "chip_microbiome_coanalysis") {
          await API.chipMicrobiomeCoanalysis({
            m16s_experiment: gate.m16s || null,
            mgx_experiment: gate.mgx || null,
            genome: document.getElementById("chip-anno-genome")?.value || "mm",
          });
        } else if (action === "chip_metabolomics_coanalysis") {
          await API.chipMetabolomicsCoanalysis({
            mbx_experiment: gate.mbx,
            genome: document.getElementById("chip-anno-genome")?.value || "mm",
          });
        } else if (action === "chip_clinical_coanalysis") {
          await API.chipClinicalCoanalysis({
            companion_experiment: gate.rna || gate.m16s || null,
          });
        } else {
          await runChipDownstreamAction(action);
        }
        chipRecipeLog(`[${packId}] ✓ ${action}`, "ok");
      } catch (e) {
        chipRecipeLog(`[${packId}] ✗ ${action}: ${e.message}`, "error");
      }
    }
    for (const pl of pack.planned_steps || []) {
      chipRecipeLog(`[${packId}] planned: ${pl.title || pl.id}`, "warn");
    }
    chipRecipeLog(`[${packId}] done`, "ok");
    toast(`Pack ${packId} finished`, "success");
  } finally {
    setLoading(false);
  }
}

async function runChipRecipeCombo(selectedIds) {
  if (!_chipRecipePacks) await loadChipRecipePacks();
  const order = _chipRecipePacks?.combo?.default_order || selectedIds;
  const ids = order.filter((id) => selectedIds.includes(id));
  if (!ids.length) {
    toast("请至少勾选一个配方包", "error");
    return;
  }
  const results = document.getElementById("chip-recipe-results");
  if (results) results.innerHTML = `<p class="hint">Combo: ${ids.map(chipdsEsc).join(" → ")}</p>`;
  for (const id of ids) {
    await runChipRecipePack(id);
  }
}

async function runChipMicrobiomeCoanalysisOnPage() {
  const m16s = document.getElementById("chip-deps-m16s")?.value || "";
  const mgx = document.getElementById("chip-deps-mgx")?.value || "";
  if (!m16s && !mgx) {
    toast("Select 16S and/or MGX in the dependency panel", "error");
    setChipWizardStep("2");
    return;
  }
  setLoading(true);
  try {
    const res = await API.chipMicrobiomeCoanalysis({
      m16s_experiment: m16s || null,
      mgx_experiment: mgx || null,
    });
    chipRecipeLog(`microbiome coanalysis: genes=${res.chip_genes_n} 16S=${res.m16s_sig_n} MGX=${res.mgx_sig_n}`, "ok");
    toast("Microbiome co-analysis done", "success");
  } catch (e) {
    toast(e.message, "error");
  } finally {
    setLoading(false);
  }
}

async function runChipMetabolomicsCoanalysisOnPage() {
  const mbx = document.getElementById("chip-deps-mbx")?.value || "";
  if (!mbx) {
    toast("Select metabolomics experiment in the dependency panel", "error");
    setChipWizardStep("2");
    return;
  }
  setLoading(true);
  try {
    const res = await API.chipMetabolomicsCoanalysis({ mbx_experiment: mbx });
    chipRecipeLog(`metabolomics coanalysis: genes=${res.chip_genes_n} MBX=${res.mbx_sig_n}`, "ok");
    toast("Metabolomics co-analysis done", "success");
  } catch (e) {
    toast(e.message, "error");
  } finally {
    setLoading(false);
  }
}

async function runChipClinicalCoanalysisOnPage() {
  const clin = document.getElementById("chip-deps-clinical")?.value || "";
  if (!clin) {
    toast("Select clinical source in the dependency panel", "error");
    setChipWizardStep("2");
    return;
  }
  setLoading(true);
  try {
    const res = await API.chipClinicalCoanalysis({
      companion_experiment: document.getElementById("chip-deps-rna")?.value || null,
    });
    chipRecipeLog(`clinical coanalysis mode=${res.mode} genes=${res.chip_genes_n} shared=${res.shared_samples_n}`, "ok");
    toast("Clinical co-analysis done", "success");
  } catch (e) {
    toast(e.message, "error");
  } finally {
    setLoading(false);
  }
}

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
      showPlot(outId, res.plot, { downloadStem: outId.replace(/-out$/, ""), ...plotDownloadOptions(res) });
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
  const sc = +document.getElementById("viz-figure-scale")?.value;
  const atx = +document.getElementById("viz-axis-text-x")?.value;
  const aty = +document.getElementById("viz-axis-text-y")?.value;
  const alx = +document.getElementById("viz-axis-title-x")?.value;
  const aly = +document.getElementById("viz-axis-title-y")?.value;
  return {
    color_panel: document.getElementById("viz-color-panel")?.value || "npg",
    custom_colors: useCustom ? (picks.join(",") || null) : null,
    figure_scale: Number.isFinite(sc) && sc > 0 ? sc : 1,
    axis_text_x: Number.isFinite(atx) && atx > 0 ? atx : 11,
    axis_text_y: Number.isFinite(aty) && aty > 0 ? aty : 11,
    axis_title_x: Number.isFinite(alx) && alx > 0 ? alx : 12,
    axis_title_y: Number.isFinite(aly) && aly > 0 ? aly : 12,
  };
}

function wireVizAspectLock(widthId, heightId, ratio) {
  const wEl = document.getElementById(widthId);
  const hEl = document.getElementById(heightId);
  const lockEl = document.getElementById("viz-lock-aspect");
  if (!wEl || !hEl || !ratio) return;
  let syncing = false;
  const fromWidth = () => {
    if (!lockEl?.checked) return;
    const w = +wEl.value;
    if (!Number.isFinite(w) || w <= 0) return;
    hEl.value = String(Math.round((w / ratio) * 2) / 2);
  };
  const fromHeight = () => {
    if (!lockEl?.checked) return;
    const h = +hEl.value;
    if (!Number.isFinite(h) || h <= 0) return;
    wEl.value = String(Math.round((h * ratio) * 2) / 2);
  };
  wEl.addEventListener("input", () => {
    if (syncing) return;
    syncing = true;
    fromWidth();
    syncing = false;
  });
  hEl.addEventListener("input", () => {
    if (syncing) return;
    syncing = true;
    fromHeight();
    syncing = false;
  });
}

wireVizAspectLock("scat-width", "scat-height", 9 / 7);
wireVizAspectLock("scat-proj-width", "scat-proj-height", 7 / 4.5);
wireVizAspectLock("heat-width", "heat-height", 11 / 8);

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

function updateScatGroupFilter() {
  const gEl = document.getElementById("scat-group");
  const wrap = document.getElementById("scat-groups-wrap");
  const box = document.getElementById("scat-groups-filter");
  if (!gEl || !box || !wrap) return;
  const col = window._emp.coldataCols.find(c => c.name === gEl.value);
  if (!col?.values?.length) {
    wrap.classList.add("hidden");
    box.innerHTML = '<span class="muted">Select a group variable first.</span>';
    return;
  }
  wrap.classList.remove("hidden");
  box.innerHTML = col.values.map(v => {
    const safe = String(v).replace(/"/g, "&quot;");
    return `<label class="chk-inline"><input type="checkbox" class="scat-grp-cb" value="${safe}" checked> ${safe}</label>`;
  }).join("");
}

function selectedScatGroups() {
  return [...document.querySelectorAll("#scat-groups-filter .scat-grp-cb:checked")]
    .map(el => el.value)
    .filter(Boolean);
}

function currentScatterSize() {
  const w = +document.getElementById("scat-width")?.value;
  const h = +document.getElementById("scat-height")?.value;
  const pw = +document.getElementById("scat-proj-width")?.value;
  const ph = +document.getElementById("scat-proj-height")?.value;
  return {
    width:  Number.isFinite(w) && w > 0 ? w : 9,
    height: Number.isFinite(h) && h > 0 ? h : 7,
    proj_width: Number.isFinite(pw) && pw > 0 ? pw : 7,
    proj_height: Number.isFinite(ph) && ph > 0 ? ph : 4.5,
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
    showPlot("volcano-out", res.plot, { downloadStem: "volcano", ...plotDownloadOptions(res) });
    document.getElementById("vol-pdf-link")?.classList.add("hidden");
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
    showPlot("deg-heatmap-out", res.plot, { downloadStem: "deg_heatmap", ...plotDownloadOptions(res) });
    if (meta) {
      const omics = currentOmicsPreset();
      const unit = omics === "microbiome_16s" ? "taxa" : "genes";
      meta.textContent = res.n_genes ? `${res.n_genes} differential ${unit} plotted` : "";
    }
    document.getElementById("deg-pdf-link")?.classList.add("hidden");
    toast("DEG heatmap ready.", "success");
  } catch(e) {
    out.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${e.message}</p>`;
    toast(e.message, "error");
  } finally { setLoading(false); }
});

document.getElementById("btn-scatter")?.addEventListener("click", async () => {
  const exp = window._emp.currentExp;
  if (!exp) { toast("Import data first.", "error"); return; }
  const out = document.getElementById("scatter-out");
  setLoading(true);
  out.innerHTML = '<p style="padding:12px">Generating ordination panels…</p>';
  out.classList.remove("hidden");
  try {
    await ensurePageSnapshot("visualization");
    const res = await withBusy("Ordination plot", () => API.vizScatter(exp, {
      group: document.getElementById("scat-group").value || null,
      dim1:  +document.getElementById("scat-dim1").value,
      dim2:  +document.getElementById("scat-dim2").value,
      groups_include: selectedScatGroups(),
      ordination: document.getElementById("scat-ordination")?.value || "auto",
      ...currentScatterSize(),
      ...currentColorOptions(),
    }));
    showOrdinationResult("scatter-out", res);
    toast("Ordination panels ready.", "success");
  } catch (e) {
    out.innerHTML = `<p style="padding:12px;color:#991b1b">Error: ${e.message}</p>`;
    toast(e.message, "error");
  } finally {
    setLoading(false);
  }
});

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
    ...currentColorOptions(),
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
function ensureChipseqNavVisible() {
  // ChIPseq + downstream must stay in the sidebar (not analysis-only embedding).
  document.querySelectorAll(
    '.nav-item[data-page="chipseq"], .nav-item[data-page="chipseq_downstream"]'
  ).forEach((el) => {
    el.classList.remove("hidden");
    el.style.removeProperty("display");
  });
}

function applyOmicsPreset(omics) {
  const body = document.body;
  [...body.classList].forEach((c) => {
    if (c.startsWith("omics-")) body.classList.remove(c);
  });
  // multiomics / customize behave like "all": show every tab (no body filter class)
  const showAll = !omics || omics === "all" || omics === "multiomics" || omics === "customize";
  if (!showAll) body.classList.add(`omics-${omics}`);
  localStorage.setItem("emp_omics", omics || "all");
  ensureChipseqNavVisible();

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
  const listEl = document.getElementById("workflow-list");
  listEl?.querySelectorAll(".workflow-tag").forEach((b) => {
    b.classList.toggle("is-active", b.dataset.workflowId === omics);
  });
});

// ── GLOBAL CLEAR ALL ──────────────────────────────
async function clearAllData() {
  setLoading(true);
  try { await API.deleteSession(); } catch (_) { /* no session yet */ }
  localStorage.removeItem("emp_session_id");
  window._emp.experiments = [];
  window._emp.currentExp = null;
  window._emp.standaloneClinical = null;
  window._emp.chipLastPeaks = null;
  window._emp.activeDataKind = "experiment";
  window._emp.uiSnapshots = {};
  window._emp.uiSnapshotActiveKey = null;
  window._emp.coldataCols = [];
  window._emp.features = [];
  window._emp.featuresN = 0;
  invalidateExperimentCache();
  try { sessionStorage.removeItem(uiSnapshotStorageKey()); } catch (_) { /* ignore */ }
  updateUiSnapshotBadges();
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

// ── Auto-select clinical traits (client-side heuristics) ───────────
// Prefer continuous numeric vars with enough non-NA; boost common
// phenotype names; skip ID-like / near-unique columns; cap for heatmaps.
const CLIN_TRAIT_SKIP_RE = [
  /^(sample|subject|patient|barcode|index|row|col|id)$/i,
  /(^|[_-])(sample|subject|patient)?id($|[_-])/i,
  /uuid|barcode/i,
];
const CLIN_TRAIT_PREFERRED_RE = [
  /^age$/i, /^bmi$/i, /^weight$/i, /^height$/i,
  /mayo/i, /ibs[_-]?sss/i, /disease[_-]?duration/i,
  /crp|esr|calprotectin|fecal[_-]?cal/i,
  /albumin|hemoglobin|hba1c|glucose/i,
  /score|severity|activity/i,
];

function scoreClinicalTraitName(name, meta = {}, { minN = 5 } = {}) {
  const key = String(name || "").toLowerCase();
  if (!key) return -Infinity;
  if (CLIN_TRAIT_SKIP_RE.some((re) => re.test(key))) return -Infinity;

  const n = Number(meta.n_samples);
  const nUnique = Number(meta.n_unique);
  if (Number.isFinite(n) && n < minN) return -Infinity;
  // Nearly unique per sample → likely an encoded ID.
  if (Number.isFinite(n) && Number.isFinite(nUnique) && n >= 10
      && nUnique >= Math.max(20, n * 0.9)) {
    return -Infinity;
  }

  let s = 0;
  if (Number.isFinite(n)) s += Math.min(n, 100) / 10;
  if (Number.isFinite(nUnique) && Number.isFinite(n) && n > 0) {
    if (nUnique <= 2) s -= 1;
    else if (nUnique >= 8 || nUnique / n >= 0.3) s += 5;
    else if (nUnique >= 4) s += 2;
  }
  for (let i = 0; i < CLIN_TRAIT_PREFERRED_RE.length; i++) {
    if (CLIN_TRAIT_PREFERRED_RE[i].test(key)) {
      s += 24 - i;
      break;
    }
  }
  if (/age|bmi|weight|height|mayo|ibs|duration|crp|calprotectin|albumin|score|severity|activity/
      .test(key)) {
    s += 6;
  }
  return s;
}

/** Select sensible traits in a <select> already filled with numeric options. */
function autoConfigureClinicalTraits(selectEl, { maxTraits = 10, minN = 5 } = {}) {
  if (!selectEl) return [];
  const options = Array.from(selectEl.options || []).filter((o) => o.value);
  if (!options.length) return [];

  const byName = new Map((_clinVarCache || []).map((r) => [r.name, r]));
  const ranked = options
    .map((o) => {
      const meta = byName.get(o.value) || {};
      return { name: o.value, score: scoreClinicalTraitName(o.value, meta, { minN }) };
    })
    .filter((x) => Number.isFinite(x.score) && x.score > -Infinity)
    .sort((a, b) => b.score - a.score || a.name.localeCompare(b.name));

  const pool = ranked.length
    ? ranked
    : options.map((o) => ({ name: o.value, score: 0 }));
  const cap = Math.max(1, Math.min(maxTraits, pool.length));
  const pick = pool.slice(0, cap).map((x) => x.name);
  const pickSet = new Set(pick);

  if (selectEl.multiple) {
    Array.from(selectEl.options).forEach((o) => {
      o.selected = pickSet.has(o.value);
    });
  } else if (pick[0]) {
    selectEl.value = pick[0];
  }
  return pick;
}

function ensureNumericField(el, fallback, { min = null } = {}) {
  if (!el) return;
  const v = +el.value;
  if (!Number.isFinite(v) || String(el.value).trim() === ""
      || (min != null && v < min)) {
    el.value = String(fallback);
  }
}

async function runClinicalAutoConfig(kind) {
  if (!Array.isArray(_clinVarCache) || !_clinVarCache.length) {
    try { await refreshClinicalVars(); } catch (_) { /* toast below */ }
  }
  const selectId = kind === "wgcna" ? "clin-wgcna-traits"
    : kind === "fitline" ? "clin-fit-trait"
      : "clin-cor-traits";
  const selectEl = document.getElementById(selectId);
  if (!selectEl?.options?.length) {
    toast(t("clinical.autoConfigNeedVars"), "error");
    return;
  }

  setClinicalCodeStrategy(kind === "fitline" ? "fitline" : kind);
  const maxTraits = kind === "fitline" ? 1 : 10;
  const picked = autoConfigureClinicalTraits(selectEl, { maxTraits });
  if (!picked.length) {
    toast(t("clinical.autoConfigNone"), "error");
    return;
  }

  if (kind === "cor") {
    const method = document.getElementById("clin-cor-method");
    if (method) method.value = "spearman";
    ensureNumericField(document.getElementById("clin-cor-topn"), 30, { min: 5 });
    const padj = document.getElementById("clin-cor-padj");
    if (padj) padj.value = "BH";
  } else if (kind === "wgcna") {
    ensureNumericField(document.getElementById("clin-wgcna-minmod"), 30, { min: 10 });
  }

  toast(t("clinical.autoConfigToast", null, { n: picked.length }), "success");
  refreshClinicalCodeScript();
}

document.getElementById("clin-btn-cor-auto-config")?.addEventListener("click", () => {
  runClinicalAutoConfig("cor");
});
document.getElementById("clin-btn-wgcna-auto-config")?.addEventListener("click", () => {
  runClinicalAutoConfig("wgcna");
});
document.getElementById("clin-btn-fit-auto-config")?.addEventListener("click", () => {
  runClinicalAutoConfig("fitline");
});

// ponytail: client-side name/N heuristics only; upgrade = backend trait recommender.
if (typeof window !== "undefined" && /[?&]emp_selftest=1\b/.test(String(location.search || ""))) {
  const bmi = scoreClinicalTraitName("BMI", { n_samples: 40, n_unique: 28 });
  const age = scoreClinicalTraitName("age", { n_samples: 40, n_unique: 25 });
  const sid = scoreClinicalTraitName("sample_id", { n_samples: 40, n_unique: 40 });
  console.assert(bmi > sid && age > sid, "clinical auto-trait scoring");
}

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
    if (res.plot) showPlot("clin-cor-plot", res.plot, { downloadStem: "clinical_cor", ...plotDownloadOptions(res) });
    else plot.innerHTML = `<p style="padding:12px">Correlation done, but the
      matrix is too small to render a heatmap (need ≥ 2 features).</p>`;
    document.getElementById("clin-cor-pdf")?.classList.add("hidden");

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
    showPlot("clin-fit-plot", res.plot, { downloadStem: "clinical_fitline", ...plotDownloadOptions(res) });
    status.className = "alert alert-info";
    status.textContent = `Spearman r = ${(+res.r).toFixed(3)}, p = ${(+res.p).toExponential(2)}, n = ${res.n}`
      + (res.group_used ? "  (grouped fit)" : "");
    status.classList.remove("hidden");
    document.getElementById("clin-fit-pdf")?.classList.add("hidden");
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
    const wgcnaPdfName = res.pdf_name || (res.pdf ? String(res.pdf).split("/").pop() : null);
    showPlot("clin-wgcna-plot", res.png, {
      downloadStem: "wgcna_modtrait",
      pdfName: wgcnaPdfName,
      pdfUrl: wgcnaPdfName ? plotPdfDownloadUrl(wgcnaPdfName) : null,
    });
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
      pdfLink.classList.add("hidden");
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
    import("./github_sync.js?v=editable-repo-v1").then((m) => m.applyGithubSyncI18n?.());
    // Re-apply page bindings after other locale listeners (Code Lab, etc.).
    try {
      applyPagesI18n();
    } catch (e) {
      console.warn("[emp-i18n] locale-change applyPagesI18n failed", e);
    }
    if (document.getElementById("page-clinical")?.classList.contains("active")) {
      updateClinicalPrecheck();
    }
    // Dynamic ChIP / chipds panels
    if (_chipdsCatalog) {
      fillChipDownstreamStageSelect(_chipdsCatalog);
      const filtered = filterChipDownstreamItems(_chipdsCatalog.items || []);
      updateChipDownstreamSummary(_chipdsCatalog, filtered.length);
      renderChipDownstreamCatalog(_chipdsCatalog);
    }
    renderChipPeakSelectors(
      window._emp?.chipPeakFiles || [],
      window._emp?.chipActivePeakId || "",
      window._emp?.chipLastPeaks || null,
    );
    refreshChipRecipeDeps();
    loadChipRecipePacks().catch(() => {});
  });
  await initCodeLab();
  initEvolution();
  await initTeaching();
  setupTeachingTraceHooks();
  await initGithubSync();
  await loadWorkflowBlueprint();
  await loadDemoDatasetButtons();
  loadUiSnapshotsFromStorage();
  await refreshExperimentList();
  updateUiSnapshotBadges();
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
