/**
 * job_tray.js — EMP Web v9.1.0 Round 2: background job tray.
 *
 * A fixed bottom-right tray that polls GET /api/jobs and shows recent
 * background jobs (kind, status, progress bar, message), with Cancel for
 * running jobs and dismiss for finished ones. When a job the tray has
 * seen running finishes, a friendly toast is dispatched through the
 * existing "emp:toast" channel (handled in app.js).
 *
 * Polling contract: one poll on init; keep polling every 3 s only while
 * a queued/running job is known or the tray is open; stop otherwise.
 */
import { t } from "./locale.js?v=i18n-zh-default-v1";
import { apiBase } from "./api.js?v=i18n-zh-default-v1";

const POLL_MS = 3000;
const ACTIVE = new Set(["queued", "running"]);

let _root = null;
let _listEl = null;
let _badgeEl = null;
let _titleEl = null;
let _open = false;
let _timer = null;
const _jobs = new Map();      // id -> latest job summary
const _prevStatus = new Map(); // id -> previous status (transition toasts)
const _dismissed = new Set();  // ids removed from the local view
let _bgHintFired = false;

function esc(s) {
  return String(s ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function ensureStyle() {
  if (document.getElementById("emp-jobtray-style")) return;
  const st = document.createElement("style");
  st.id = "emp-jobtray-style";
  st.textContent = `
    .emp-jobtray{position:fixed;bottom:16px;inset-inline-end:16px;z-index:1200;
      font-size:13px;max-width:min(360px,92vw)}
    .emp-jobtray-toggle{display:flex;align-items:center;gap:8px;cursor:pointer;
      border:1px solid var(--border,#d0d7de);background:var(--surface,#fff);
      color:inherit;border-radius:999px;padding:6px 12px;box-shadow:0 4px 18px rgba(0,0,0,.14)}
    .emp-jobtray-badge{min-width:18px;height:18px;border-radius:999px;padding:0 5px;
      background:#1f6feb;color:#fff;font-size:11px;line-height:18px;text-align:center}
    .emp-jobtray-badge.idle{background:#8b949e}
    .emp-jobtray-panel{margin-top:8px;border:1px solid var(--border,#d0d7de);
      background:var(--surface,#fff);border-radius:10px;box-shadow:0 8px 28px rgba(0,0,0,.18);
      padding:8px;max-height:46vh;overflow:auto}
    .emp-jobtray-empty{padding:8px;color:#666}
    .emp-jobtray-job{padding:8px;border-top:1px solid #eee}
    .emp-jobtray-job:first-child{border-top:none}
    .emp-jobtray-job-head{display:flex;justify-content:space-between;gap:8px;align-items:baseline}
    .emp-jobtray-kind{font-weight:600;word-break:break-all}
    .emp-jobtray-status{color:#666;white-space:nowrap}
    .emp-jobtray-bar{height:6px;border-radius:3px;background:#e5e7eb;margin:6px 0;overflow:hidden}
    .emp-jobtray-bar > i{display:block;height:100%;background:#1f6feb;transition:width .3s}
    .emp-jobtray-msg{color:#555;word-break:break-word}
    .emp-jobtray-actions{margin-top:6px;display:flex;gap:6px}
    .emp-jobtray-actions button{cursor:pointer;border:1px solid var(--border,#d0d7de);
      background:transparent;color:inherit;border-radius:6px;padding:2px 10px;font-size:12px}
  `;
  document.head.appendChild(st);
}

function toast(message, type) {
  window.dispatchEvent(new CustomEvent("emp:toast", { detail: { message, type } }));
}

function anyActive() {
  for (const job of _jobs.values()) {
    if (ACTIVE.has(job.status)) return true;
  }
  return false;
}

function schedule() {
  if (_timer) {
    clearTimeout(_timer);
    _timer = null;
  }
  if (_open || anyActive()) {
    _timer = setTimeout(poll, POLL_MS);
  }
}

function render() {
  if (!_root) return;
  const jobs = [..._jobs.values()].filter((j) => !_dismissed.has(j.id));
  const running = jobs.filter((j) => ACTIVE.has(j.status)).length;
  _badgeEl.textContent = String(running);
  _badgeEl.classList.toggle("idle", running === 0);
  _titleEl.textContent = t("jobtray.title");
  _root.querySelector(".emp-jobtray-panel").style.display = _open ? "block" : "none";

  if (!jobs.length) {
    _listEl.innerHTML = `<div class="emp-jobtray-empty">${esc(t("jobtray.empty"))}</div>`;
    return;
  }
  _listEl.innerHTML = jobs.map((job) => {
    const pct = Math.max(0, Math.min(100, Number(job.progress) || 0));
    const statusLabel = job.status === "running" || job.status === "queued"
      ? `${t("jobtray.running")} · ${pct}%`
      : esc(job.status || "");
    const action = ACTIVE.has(job.status)
      ? `<button type="button" data-act="cancel" data-id="${esc(job.id)}">${esc(t("jobtray.cancel"))}</button>`
      : `<button type="button" data-act="dismiss" data-id="${esc(job.id)}">×</button>`;
    return `<div class="emp-jobtray-job">
      <div class="emp-jobtray-job-head">
        <span class="emp-jobtray-kind">${esc(job.kind || job.id)}</span>
        <span class="emp-jobtray-status">${statusLabel}</span>
      </div>
      <div class="emp-jobtray-bar"><i style="width:${pct}%"></i></div>
      ${job.message ? `<div class="emp-jobtray-msg">${esc(job.message)}</div>` : ""}
      <div class="emp-jobtray-actions">${action}</div>
    </div>`;
  }).join("");
}

async function poll() {
  try {
    const r = await fetch(`${apiBase()}/jobs?limit=20`);
    if (r.ok) {
      const j = await r.json();
      const list = Array.isArray(j?.jobs) ? j.jobs : [];
      for (const job of list) {
        if (!job || !job.id || _dismissed.has(job.id)) continue;
        const prev = _prevStatus.get(job.id);
        _prevStatus.set(job.id, job.status);
        _jobs.set(job.id, job);
        if (prev && ACTIVE.has(prev) && job.status === "done") {
          toast(t("jobtray.done", null, { kind: job.kind || job.id }), "success");
        } else if (prev && ACTIVE.has(prev) && job.status === "error") {
          toast(t("jobtray.failed", null, { kind: job.kind || job.id }), "error");
        }
        if (ACTIVE.has(job.status) && !_bgHintFired) {
          _bgHintFired = true;
          try { window.empHintBg?.(); } catch { /* hints are optional */ }
        }
      }
      render();
    }
  } catch {
    /* backend not up yet; the next scheduled poll retries */
  }
  schedule();
}

async function cancelJob(id) {
  try {
    await fetch(`${apiBase()}/jobs/${encodeURIComponent(id)}/cancel`, { method: "POST" });
  } catch { /* status refresh below shows the outcome */ }
  poll();
}

export function initJobTray() {
  try {
    if (_root || typeof document === "undefined" || !document.body) return;
    ensureStyle();
    _root = document.createElement("div");
    _root.className = "emp-jobtray";
    _root.innerHTML = `
      <button type="button" class="emp-jobtray-toggle">
        <span class="emp-jobtray-title"></span>
        <span class="emp-jobtray-badge idle">0</span>
      </button>
      <div class="emp-jobtray-panel" style="display:none"><div class="emp-jobtray-list"></div></div>`;
    document.body.appendChild(_root);
    _listEl = _root.querySelector(".emp-jobtray-list");
    _badgeEl = _root.querySelector(".emp-jobtray-badge");
    _titleEl = _root.querySelector(".emp-jobtray-title");
    _root.querySelector(".emp-jobtray-toggle").addEventListener("click", () => {
      _open = !_open;
      render();
      if (_open) poll(); else schedule();
    });
    _listEl.addEventListener("click", (e) => {
      const btn = e.target.closest("button[data-act]");
      if (!btn) return;
      const id = btn.dataset.id;
      if (btn.dataset.act === "cancel") cancelJob(id);
      if (btn.dataset.act === "dismiss") {
        _dismissed.add(id);
        _jobs.delete(id);
        render();
        schedule();
      }
    });
    window.addEventListener("emp:locale-change", () => render());
    render();
    poll();
  } catch (e) {
    console.warn("[emp-jobtray] init failed", e);
  }
}
