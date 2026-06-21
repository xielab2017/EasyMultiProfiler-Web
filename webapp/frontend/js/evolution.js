// Self-evolution telemetry: anonymous user profile + event stream to backend.
import * as API from "./api.js?v=2026-06-21-v5.0.1";

const USER_KEY = "emp_evolution_user_id";

function randomId() {
  if (typeof crypto !== "undefined" && crypto.randomUUID) return crypto.randomUUID();
  return `u_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`;
}

export function getEvolutionUserId() {
  try {
    let id = localStorage.getItem(USER_KEY);
    if (!id) {
      id = randomId();
      localStorage.setItem(USER_KEY, id);
    }
    return id;
  } catch {
    return "anonymous";
  }
}

export async function trackEvolutionEvent(eventType, payload = {}) {
  try {
    await API.evolutionEvent({
      user_id: getEvolutionUserId(),
      event_type: eventType,
      payload,
    });
  } catch {
    /* non-blocking */
  }
}

export function initEvolution() {
  trackEvolutionEvent("session_start", {
    locale: document.documentElement.lang || navigator.language || "zh",
    path: typeof location !== "undefined" ? location.pathname : "",
  });

  window.addEventListener("emp:ai-interpret", (e) => {
    const d = e.detail || {};
    trackEvolutionEvent("ai_interpret", {
      analysis_type: d.analysis_type,
      source: d.source,
      locale: d.locale,
    });
  });

  window.addEventListener("emp:page-view", (e) => {
    const d = e.detail || {};
    if (d.page) trackEvolutionEvent("page_view", { page: d.page, locale: d.locale });
  });

  window.addEventListener("emp:analysis-run", (e) => {
    const d = e.detail || {};
    trackEvolutionEvent("analysis_run", {
      analysis_type: d.analysis_type,
      omics: d.omics,
      experiment: d.experiment,
    });
  });
}

export function trackPromptButtonClick(label, extra = {}) {
  trackEvolutionEvent("prompt_button_click", { label, ...extra });
}
