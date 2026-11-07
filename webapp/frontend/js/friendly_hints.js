/**
 * friendly_hints.js — EMP Web v9.1.0 Round 2: friendly, dismissible
 * contextual reminders.
 *
 * Hints (each shown at most until dismissed; dismissal is stored under
 * localStorage key `emp_hint_dismissed_<id>`):
 *   - "qc-after-import"  (key hint.qc)        — fires on the
 *     "emp:data-imported" / "emp:analysis-complete" window events when a
 *     producer dispatches them.
 *   - "bg-for-long-jobs" (key hint.background) — fired by the job tray
 *     (window.empHintBg) the first time a background job is seen
 *     running; also shown once on the very first visit, as an
 *     onboarding tip, when no import event integration exists yet.
 *   - "save-work"        (key hint.save)      — gentle reminder every
 *     45 minutes while the page stays open.
 *
 * Everything is defensive: if the DOM or localStorage is unavailable the
 * module quietly does nothing.
 */
import { t } from "./locale.js?v=i18n-zh-default-v1";

const HINT_KEYS = {
  "qc-after-import": "hint.qc",
  "bg-for-long-jobs": "hint.background",
  "save-work": "hint.save",
};
const SAVE_INTERVAL_MS = 45 * 60 * 1000;
const VISITED_KEY = "emp_hints_visited_v1";

let _bar = null;

function isDismissed(id) {
  try {
    return localStorage.getItem(`emp_hint_dismissed_${id}`) === "1";
  } catch {
    return false;
  }
}

function markDismissed(id) {
  try {
    localStorage.setItem(`emp_hint_dismissed_${id}`, "1");
  } catch { /* storage unavailable */ }
}

function toast(message, type) {
  window.dispatchEvent(new CustomEvent("emp:toast", { detail: { message, type } }));
}

function ensureStyle() {
  if (document.getElementById("emp-hints-style")) return;
  const st = document.createElement("style");
  st.id = "emp-hints-style";
  st.textContent = `
    .emp-hintbar{position:fixed;bottom:16px;left:50%;transform:translateX(-50%);
      z-index:1190;max-width:min(560px,94vw);display:flex;gap:10px;align-items:flex-start;
      border:1px solid var(--border,#d0d7de);background:var(--surface,#fff);color:inherit;
      border-radius:10px;box-shadow:0 8px 28px rgba(0,0,0,.16);padding:10px 12px;font-size:13px}
    .emp-hintbar-title{font-weight:600;white-space:nowrap}
    .emp-hintbar-msg{flex:1}
    .emp-hintbar button{cursor:pointer;border:1px solid var(--border,#d0d7de);
      background:transparent;color:inherit;border-radius:6px;padding:2px 10px;font-size:12px;white-space:nowrap}
  `;
  document.head.appendChild(st);
}

function hideBar() {
  if (_bar) {
    _bar.remove();
    _bar = null;
  }
}

/** Show one hint (no-op when the id is unknown or already dismissed). */
export function showHint(id) {
  try {
    const key = HINT_KEYS[id];
    if (!key || isDismissed(id)) return;
    if (typeof document === "undefined" || !document.body) return;
    toast(t(key), "info");
    ensureStyle();
    hideBar();
    _bar = document.createElement("div");
    _bar.className = "emp-hintbar";
    const title = document.createElement("span");
    title.className = "emp-hintbar-title";
    title.textContent = t("hint.title");
    const msg = document.createElement("span");
    msg.className = "emp-hintbar-msg";
    msg.textContent = t(key);
    const btn = document.createElement("button");
    btn.type = "button";
    btn.textContent = t("hint.dismiss");
    btn.addEventListener("click", () => {
      markDismissed(id);
      hideBar();
    });
    _bar.append(title, msg, btn);
    document.body.appendChild(_bar);
  } catch (e) {
    console.warn("[emp-hints] show failed", e);
  }
}

export function initFriendlyHints() {
  try {
    // Programmatic access for producers that prefer a direct call.
    window.empHints = { show: showHint };
    window.empHintBg = () => showHint("bg-for-long-jobs");

    // (1) QC reminder after data import / analysis completion events.
    window.addEventListener("emp:data-imported", () => showHint("qc-after-import"));
    window.addEventListener("emp:analysis-complete", () => showHint("qc-after-import"));

    // First visit: surface the background-jobs tip once (onboarding),
    // because no import-event producer exists in the current codebase.
    let firstVisit = false;
    try {
      firstVisit = !localStorage.getItem(VISITED_KEY);
      if (firstVisit) localStorage.setItem(VISITED_KEY, "1");
    } catch { /* ignore */ }
    if (firstVisit) showHint("bg-for-long-jobs");

    // (3) Periodic save reminder while the page stays open.
    setInterval(() => {
      if (!isDismissed("save-work")) showHint("save-work");
    }, SAVE_INTERVAL_MS);
  } catch (e) {
    console.warn("[emp-hints] init failed", e);
  }
}
