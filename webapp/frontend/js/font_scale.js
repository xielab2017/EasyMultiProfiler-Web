/**
 * Global UI font scale — proportional typography via html root rem.
 * Persists to localStorage (emp_font_scale).
 */
import { t } from "./locale.js?v=2026-07-16-multi-demo";

export const FONT_SCALE_LS = "emp_font_scale";
export const FONT_SCALE_STEPS = [0.85, 0.9, 0.95, 1, 1.05, 1.1, 1.15, 1.2, 1.25];
export const FONT_SCALE_DEFAULT = 1;

export function getFontScale() {
  const raw = parseFloat(localStorage.getItem(FONT_SCALE_LS));
  if (Number.isFinite(raw) && FONT_SCALE_STEPS.some(s => Math.abs(s - raw) < 0.001)) {
    return raw;
  }
  return FONT_SCALE_DEFAULT;
}

export function applyFontScale(scale, { persist = true } = {}) {
  const next = FONT_SCALE_STEPS.find(s => Math.abs(s - scale) < 0.001) ?? FONT_SCALE_DEFAULT;
  document.documentElement.style.setProperty("--font-scale", String(next));
  document.documentElement.dataset.fontScale = String(Math.round(next * 100));
  if (persist) localStorage.setItem(FONT_SCALE_LS, String(next));
  updateFontScaleUI(next);
  return next;
}

function nearestStepIndex(scale) {
  let idx = FONT_SCALE_STEPS.findIndex(s => Math.abs(s - scale) < 0.001);
  if (idx < 0) {
    idx = FONT_SCALE_STEPS.reduce((best, s, i) =>
      Math.abs(s - scale) < Math.abs(FONT_SCALE_STEPS[best] - scale) ? i : best, 0);
  }
  return idx;
}

export function stepFontScale(delta) {
  const current = getFontScale();
  const idx = nearestStepIndex(current);
  const next = FONT_SCALE_STEPS[Math.min(FONT_SCALE_STEPS.length - 1, Math.max(0, idx + delta))];
  applyFontScale(next);
  window.dispatchEvent(new CustomEvent("emp:font-scale-change", { detail: { scale: next } }));
  return next;
}

export function resetFontScale() {
  applyFontScale(FONT_SCALE_DEFAULT);
  window.dispatchEvent(new CustomEvent("emp:font-scale-change", { detail: { scale: FONT_SCALE_DEFAULT } }));
}

function updateFontScaleUI(scale) {
  const val = document.getElementById("font-scale-value");
  if (val) val.textContent = `${Math.round(scale * 100)}%`;
  const idx = nearestStepIndex(scale);
  const dec = document.getElementById("btn-font-smaller");
  const inc = document.getElementById("btn-font-larger");
  if (dec) dec.disabled = idx <= 0;
  if (inc) inc.disabled = idx >= FONT_SCALE_STEPS.length - 1;
}

export function initFontScale() {
  applyFontScale(getFontScale(), { persist: false });
  document.getElementById("btn-font-smaller")?.addEventListener("click", () => stepFontScale(-1));
  document.getElementById("btn-font-larger")?.addEventListener("click", () => stepFontScale(1));
  document.getElementById("btn-font-reset")?.addEventListener("click", resetFontScale);
  window.addEventListener("emp:locale-change", () => updateFontScaleLabels());
  updateFontScaleLabels();
}

function updateFontScaleLabels() {
  const label = document.querySelector(".font-scale-switch .locale-switch-label");
  if (label) label.textContent = t("fontScale.label");
  const dec = document.getElementById("btn-font-smaller");
  const inc = document.getElementById("btn-font-larger");
  const reset = document.getElementById("btn-font-reset");
  if (dec) dec.title = t("fontScale.smaller");
  if (inc) inc.title = t("fontScale.larger");
  if (reset) reset.title = t("fontScale.reset");
}

/** Inline bootstrap — call from <head> before paint to avoid flash. */
export function bootstrapFontScaleFromStorage() {
  const raw = parseFloat(localStorage.getItem(FONT_SCALE_LS));
  if (Number.isFinite(raw) && raw >= 0.85 && raw <= 1.25) {
    document.documentElement.style.setProperty("--font-scale", String(raw));
    document.documentElement.dataset.fontScale = String(Math.round(raw * 100));
  }
}
