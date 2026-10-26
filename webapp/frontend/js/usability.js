/**
 * usability.js — EMP Web v9.1.0 Round 2: keyboard usability.
 *
 * Shortcuts:
 *   Alt+1 .. Alt+9  — switch to the 1st..9th page in the sidebar
 *                     (.nav-item[data-page] in DOM order), dispatched
 *                     through the existing "emp:navigate" event.
 *   ?               — toggle the shortcuts help overlay (outside inputs).
 *   Esc             — close the overlay.
 */
import { t } from "./locale.js?v=i18n-zh-default-v1";

let _overlay = null;

function isTypingTarget(el) {
  if (!el) return false;
  const tag = String(el.tagName || "").toLowerCase();
  return tag === "input" || tag === "textarea" || tag === "select" ||
    el.isContentEditable === true;
}

function navItems() {
  try {
    return [...document.querySelectorAll(".nav-item[data-page]")];
  } catch {
    return [];
  }
}

function ensureStyle() {
  if (document.getElementById("emp-usability-style")) return;
  const st = document.createElement("style");
  st.id = "emp-usability-style";
  st.textContent = `
    .emp-shortcuts-overlay{position:fixed;inset:0;z-index:1300;
      background:rgba(0,0,0,.45);display:flex;align-items:center;justify-content:center}
    .emp-shortcuts-card{background:var(--surface,#fff);color:inherit;border-radius:12px;
      padding:18px 20px;max-width:min(440px,92vw);max-height:84vh;overflow:auto;
      box-shadow:0 12px 40px rgba(0,0,0,.3);font-size:13px}
    .emp-shortcuts-card h3{margin:0 0 10px;font-size:15px}
    .emp-shortcuts-card table{border-collapse:collapse;width:100%}
    .emp-shortcuts-card td{padding:3px 8px 3px 0;vertical-align:top}
    .emp-shortcuts-card td:first-child{font-weight:600;white-space:nowrap}
    .emp-shortcuts-card button{cursor:pointer;margin-top:12px;border:1px solid var(--border,#d0d7de);
      background:transparent;color:inherit;border-radius:6px;padding:4px 14px}
  `;
  document.head.appendChild(st);
}

function closeOverlay() {
  if (_overlay) {
    _overlay.remove();
    _overlay = null;
  }
}

function toggleOverlay() {
  try {
    if (_overlay) {
      closeOverlay();
      return;
    }
    if (typeof document === "undefined" || !document.body) return;
    ensureStyle();
    _overlay = document.createElement("div");
    _overlay.className = "emp-shortcuts-overlay";
    const card = document.createElement("div");
    card.className = "emp-shortcuts-card";
    const title = document.createElement("h3");
    title.textContent = t("usability.shortcutsTitle");
    const table = document.createElement("table");
    const rows = navItems().slice(0, 9).map((item, i) => {
      const tr = document.createElement("tr");
      const k = document.createElement("td");
      k.textContent = `Alt+${i + 1}`;
      const v = document.createElement("td");
      v.textContent = (item.textContent || item.dataset.page || "").trim();
      tr.append(k, v);
      return tr;
    });
    const extra = document.createElement("tr");
    const ek = document.createElement("td");
    ek.textContent = "? / Esc";
    const ev = document.createElement("td");
    ev.textContent = t("usability.shortcutsTitle");
    extra.append(ek, ev);
    table.append(...rows, extra);
    const btn = document.createElement("button");
    btn.type = "button";
    btn.textContent = t("usability.close");
    btn.addEventListener("click", closeOverlay);
    card.append(title, table, btn);
    _overlay.appendChild(card);
    _overlay.addEventListener("click", (e) => {
      if (e.target === _overlay) closeOverlay();
    });
    document.body.appendChild(_overlay);
  } catch (e) {
    console.warn("[emp-usability] overlay failed", e);
  }
}

export function initUsability() {
  try {
    document.addEventListener("keydown", (e) => {
      try {
        if (e.key === "Escape" && _overlay) {
          closeOverlay();
          return;
        }
        if (e.altKey && /^[1-9]$/.test(e.key)) {
          const items = navItems();
          const item = items[Number(e.key) - 1];
          if (item && item.dataset.page) {
            e.preventDefault();
            window.dispatchEvent(new CustomEvent("emp:navigate", {
              detail: { page: item.dataset.page },
            }));
          }
          return;
        }
        if (e.key === "?" && !e.altKey && !e.ctrlKey && !e.metaKey &&
            !isTypingTarget(e.target)) {
          e.preventDefault();
          toggleOverlay();
        }
      } catch (err) {
        console.warn("[emp-usability] keydown failed", err);
      }
    });
  } catch (e) {
    console.warn("[emp-usability] init failed", e);
  }
}
