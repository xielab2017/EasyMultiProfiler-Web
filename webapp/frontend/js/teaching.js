/**
 * Teaching mode: video-gated cases, prompts, learning trace.
 */
import * as API from "./api.js?v=2026-07-16-multi-demo";
import { omicsDefaultsHint } from "./omics_defaults.js?v=i18n-zh-default-v1";
import { getLocale, t } from "./locale.js?v=i18n-zh-default-v1";

const LS_CASE = "emp_teaching_active_case";

const EMP_PAGE_LABELS = () => ({
  course: t("page.course"),
  guide: t("page.guide"),
  import: t("page.import"),
  summary: t("page.summary"),
  inspector: t("page.inspector"),
  preparation: t("page.preparation"),
  analysis: t("page.analysis"),
  clinical: t("page.clinical"),
  runall: t("page.runall"),
  visualization: t("page.visualization"),
  export: t("page.export"),
  prompts: t("page.prompts"),
});

function teachToast(msg, type = "info") {
  window.dispatchEvent(new CustomEvent("emp:toast", { detail: { msg, type } }));
}

const OMICS_PATHS = {
  transcriptomics: "Import → Summary → Prepare → Analyze (DESeq2) → Visualize (Volcano) → Export",
  microbiome_16s: "Import (Taxonomy) → Prepare → Analyze (Alpha) → Visualize → Clinical",
  metabolomics: "Import → Prepare → Analyze → Clinical (联合)",
  metagenomics: "Import → Prepare → Analyze → Visualize",
};

const PHASE_LABELS = () => ({
  import: t("teach.phase.import"),
  prepare: t("teach.phase.prepare"),
  analysis: t("teach.phase.analysis"),
  visualization: t("teach.phase.visualization"),
  interpretation: t("teach.phase.interpretation"),
  question: t("teach.phase.question"),
  method: t("teach.phase.method"),
  hypothesis: t("teach.phase.hypothesis"),
});

export function activeCaseId() {
  return localStorage.getItem(LS_CASE);
}

export function setActiveCaseId(id) {
  if (id) localStorage.setItem(LS_CASE, id);
  else localStorage.removeItem(LS_CASE);
}

async function ensureSession() {
  if (!localStorage.getItem("emp_session_id")) {
    await API.createSession();
  }
}

export async function traceEvent(event) {
  try {
    await ensureSession();
    await API.teachingTrace(event);
  } catch {
    /* non-blocking */
  }
}

function esc(s) {
  return String(s ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function renderScript(text) {
  return String(text || "")
    .split(/\n\n+/)
    .map((p) => p.trim())
    .filter(Boolean)
    .map((p) => `<p>${esc(p).replace(/\n/g, "<br>")}</p>`)
    .join("");
}

function renderStoryboard(items) {
  const rows = (items || [])
    .map((it) => {
      const t = typeof it === "object" ? it.t : "";
      const scene = typeof it === "object" ? it.scene : it;
      return `<li><span class="teaching-sb-time">${esc(t || "")}</span><span class="teaching-sb-scene">${esc(scene || "")}</span></li>`;
    })
    .join("");
  if (!rows) return "";
  return `
    <details class="teaching-storyboard">
      <summary>${t("teach.storyboard")}</summary>
      <ul class="teaching-sb-list">${rows}</ul>
    </details>`;
}

function renderTakeaways(items) {
  const lis = (items || []).map((s) => `<li>${esc(s)}</li>`).join("");
  if (!lis) return "";
  return `
    <div class="teaching-takeaways">
      <h5>${t("teach.takeaways")}</h5>
      <ul>${lis}</ul>
    </div>`;
}

function renderLocalVideo(v) {
  if (!v.local_video) return "";
  const src = `${v.local_video}?v=2026-06-19-course-v10`;
  return `
    <div class="teaching-video-embed teaching-local-video">
      <video controls preload="metadata" playsinline src="${esc(src)}"></video>
    </div>`;
}

function renderReferenceLink(v) {
  if (!v.youtube_id) return "";
  const start = v.clip_start != null && v.clip_start !== "" ? `&t=${Number(v.clip_start)}` : "";
  const url = `https://www.youtube.com/watch?v=${encodeURIComponent(v.youtube_id)}${start}`;
  const note = v.source_note ? esc(v.source_note) : t("teach.extRef");
  return `
    <p class="teaching-refsource hint">${t("teach.refVideo")}<a href="${url}" target="_blank" rel="noopener noreferrer">${note} ↗</a></p>`;
}

function renderVideoBlock(v) {
  return `
    <div class="teaching-video-block teaching-lesson" data-video-id="${esc(v.id)}">
      <div class="teaching-video-head">
        <span class="tag teaching-video-aspect">${esc(v.step_label || v.aspect_label || v.aspect)}</span>
        <strong>${esc(v.title)}</strong>
        <span class="hint">${esc(v.duration || "")}</span>
        <span class="tag teaching-orig-tag">${t("teach.lessonTag")}</span>
      </div>
      ${v.objective ? `<p class="teaching-lesson-objective"><span class="teaching-lesson-tag">${t("teach.objective")}</span>${esc(v.objective)}</p>` : ""}
      ${renderLocalVideo(v)}
      ${v.description ? `<p class="hint teaching-video-desc">${esc(v.description)}</p>` : ""}
      <details class="teaching-script-fold">
        <summary>${t("teach.script")}</summary>
        <div class="teaching-lesson-script">${renderScript(v.script)}</div>
      </details>
      ${renderTakeaways(v.takeaways)}
      ${renderStoryboard(v.storyboard)}
      ${renderReferenceLink(v)}
    </div>`;
}

function renderQuizBlock(task, caseId) {
  if (!task.quiz?.questions?.length) return "";
  if (task.quiz_passed) {
    return `<p class="teaching-quiz-passed">${t("teach.quizPassed")}</p>`;
  }
  const qs = task.quiz.questions.map((q, qi) => `
    <fieldset class="teaching-quiz-q" data-qid="${esc(q.id)}">
      <legend>${qi + 1}. ${esc(q.question)}</legend>
      ${(q.options || []).map((opt, oi) => `
        <label class="teaching-quiz-opt">
          <input type="radio" name="quiz-${esc(task.id)}-${esc(q.id)}" value="${oi}">
          ${esc(opt)}
        </label>`).join("")}
    </fieldset>`).join("");
  return `
    <div class="teaching-quiz" data-case="${esc(caseId)}" data-task="${esc(task.id)}">
      <h4>${t("teach.quizTitle")}</h4>
      <p class="hint">${t("teach.quizHint", null, { n: task.quiz.questions.length })}</p>
      ${qs}
      <div class="teaching-quiz-actions">
        <button type="button" class="btn btn-primary btn-submit-quiz">${t("teach.submitQuiz")}</button>
        <span class="teaching-quiz-feedback hint"></span>
      </div>
    </div>`;
}

function renderTaskCard(task, i, caseId) {
  const locked = !task.unlocked;
  const videos = (task.videos || []).map(renderVideoBlock).join("");
  const quiz = locked ? "" : renderQuizBlock(task, caseId);
  const canPractice = task.quiz_passed;
  const done = task.reflection_done;

  const empLabel = task.emp_page ? (EMP_PAGE_LABELS()[task.emp_page] || task.emp_page) : "";
  return `
    <article class="teaching-task-card ${done ? "is-done" : ""} ${locked ? "is-locked" : ""} ${task.quiz_passed ? "quiz-done" : ""}" data-task-id="${esc(task.id)}">
      ${locked ? `<div class="teaching-lock-banner">${t("teach.lockBanner")}</div>` : ""}
      <header>
        <span class="teaching-task-num">${i + 1}</span>
        <span class="tag">${esc(PHASE_LABELS()[task.phase] || task.phase)}</span>
        ${task.quiz_passed ? `<span class="tag tag-ok">${t("teach.quizOk")}</span>` : ""}
        ${done ? `<span class="tag tag-ok">${t("teach.reflectionDone")}</span>` : ""}
        <h3>${esc(task.title)}</h3>
      </header>
      <p>${esc(task.instructions)}</p>
      ${videos ? `<div class="teaching-videos">${videos}</div>` : ""}
      ${quiz}
      <div class="teaching-practice ${canPractice ? "" : "is-disabled"}">
        ${task.emp_page ? `<button type="button" class="btn btn-outline btn-goto-emp" data-page="${esc(task.emp_page)}" ${canPractice ? "" : "disabled"}>${t("teach.gotoEmp")}${esc(empLabel)}</button>` : ""}
        <label class="teaching-reflection-label">${esc(task.reflection_prompt || t("teach.reflection"))}
          <textarea class="teaching-reflection" rows="3" data-case="${esc(caseId)}" data-task="${esc(task.id)}" ${canPractice ? "" : "disabled"}></textarea>
        </label>
        <label class="teaching-reflection-label">${t("teach.aiDecl")}
          <input type="text" class="teaching-ai-decl" data-case="${esc(caseId)}" data-task="${esc(task.id)}" placeholder="${esc(t("teach.aiDeclPh"))}" ${canPractice ? "" : "disabled"}>
        </label>
        <button type="button" class="btn btn-primary btn-save-reflection" data-case="${esc(caseId)}" data-task="${esc(task.id)}" ${canPractice ? "" : "disabled"}>${t("teach.saveReflection")}</button>
        ${!canPractice && !locked ? `<p class="hint">${t("teach.practiceHint")}</p>` : ""}
      </div>
    </article>`;
}

async function renderCaseList() {
  const list = document.getElementById("teaching-case-list");
  const detail = document.getElementById("teaching-case-detail");
  if (!list) return;
  try {
    await ensureSession();
    const [data, prog] = await Promise.all([
      API.teachingCases(),
      API.teachingProgress().catch(() => ({ completed_tasks: {}, passed_quizzes: {} })),
    ]);
    const cases = data.cases || [];
    const passed = prog.passed_quizzes || {};
    const done = prog.completed_tasks || {};
    list.innerHTML = cases.map((c) => {
      const tasks = c.tasks || [];
      const total = tasks.length || 1;
      let completed = 0;
      tasks.forEach((t) => {
        const key = `${c.id}::${t.id}`;
        if (done[key]) completed += 1;
        else if (passed[key]) completed += 0.5;
      });
      const pct = Math.min(100, Math.round((completed / total) * 100));
      return `
      <button type="button" class="teaching-case-card" data-case-id="${esc(c.id)}">
        <div class="teaching-case-progress" style="--pct:${pct}%"><span>${pct}%</span></div>
        <h3>${esc(c.title)}</h3>
        <p class="hint">${esc(c.subtitle || "")}</p>
        <span class="tag">${esc(c.omics || "")}</span>
        <span class="tag">${tasks.length}${t("course.steps")}</span>
      </button>`;
    }).join("");
    list.querySelectorAll(".teaching-case-card").forEach((btn) => {
      btn.addEventListener("click", () => loadCaseDetail(btn.dataset.caseId));
    });
    const saved = activeCaseId();
    if (saved) loadCaseDetail(saved);
    else if (detail) detail.innerHTML = `<p class="hint">${t("course.selectHint")}</p>`;
  } catch (e) {
    list.innerHTML = `<p class="hint">${t("course.loadFail")}${esc(e.message)}</p>`;
  }
}

function bindCaseDetailEvents(detail, caseId) {
  detail.querySelectorAll(".btn-goto-emp").forEach((b) => {
    b.addEventListener("click", () => {
      traceEvent({ event_type: "task_navigate", case_id: caseId, task_page: b.dataset.page });
      window.dispatchEvent(new CustomEvent("emp:navigate", { detail: { page: b.dataset.page } }));
    });
  });

  detail.querySelectorAll(".btn-submit-quiz").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const box = btn.closest(".teaching-quiz");
      const taskId = box.dataset.task;
      const fields = box.querySelectorAll(".teaching-quiz-q");
      const answers = [];
      for (const f of fields) {
        const qid = f.dataset.qid;
        const picked = f.querySelector(`input[name="quiz-${taskId}-${qid}"]:checked`);
        if (!picked) {
          box.querySelector(".teaching-quiz-feedback").textContent = t("teach.answerAll");
          return;
        }
        answers.push({ id: qid, choice: Number(picked.value) });
      }
      btn.disabled = true;
      const feedback = box.querySelector(".teaching-quiz-feedback");
      feedback.textContent = t("teach.submitting");
      try {
        await ensureSession();
        const res = await API.teachingSubmitQuiz({ case_id: caseId, task_id: taskId, answers });
        if (res.passed) {
          feedback.textContent = t("teach.quizAllCorrect");
          await traceEvent({ event_type: "quiz_pass", case_id: caseId, task_id: taskId });
          await loadCaseDetail(caseId);
          await renderCaseList();
        } else {
          const wrongHint = (res.wrong_ids || []).length
            ? t("teach.quizWrongHint", null, { ids: (res.wrong_ids || []).join("、") })
            : "";
          feedback.textContent = t("teach.quizPartial", null, {
            correct: res.correct,
            total: res.total,
            wrong: wrongHint,
          });
          box.querySelectorAll(".teaching-quiz-q").forEach((f) => {
            if ((res.wrong_ids || []).includes(f.dataset.qid)) f.classList.add("is-wrong");
          });
          btn.disabled = false;
        }
      } catch (err) {
        feedback.textContent = err.message || String(err);
        btn.disabled = false;
      }
    });
  });

  detail.querySelectorAll(".btn-save-reflection").forEach((b) => {
    b.addEventListener("click", async () => {
      const ta = detail.querySelector(`textarea[data-task="${b.dataset.task}"]`);
      const ai = detail.querySelector(`input.teaching-ai-decl[data-task="${b.dataset.task}"]`);
      try {
        await ensureSession();
        await API.teachingReflection({
          case_id: b.dataset.case,
          task_id: b.dataset.task,
          reflection: ta?.value || "",
          ai_declaration: ai?.value || "",
        });
        await loadCaseDetail(caseId);
        teachToast(t("teach.reflectionSaved"), "success");
      } catch (err) {
        teachToast(err.message || String(err), "error");
      }
    });
  });

  detail.querySelectorAll(".teaching-video-embed iframe").forEach((iframe) => {
    iframe.addEventListener("load", () => {
      const block = iframe.closest(".teaching-video-block");
      traceEvent({
        event_type: "video_load",
        case_id: caseId,
        video_id: block?.dataset.videoId,
      });
    });
  });
}

async function loadCaseDetail(caseId) {
  const detail = document.getElementById("teaching-case-detail");
  if (!detail) return;
  setActiveCaseId(caseId);
  detail.innerHTML = `<p class="hint">${t("teach.loading")}</p>`;
  try {
    await ensureSession();
    const { case: c } = await API.teachingCase(caseId);
    const omicsSel = document.getElementById("omics-pipeline");
    if (omicsSel && c.omics) omicsSel.value = c.omics;
    window.dispatchEvent(new CustomEvent("emp:omics-change", { detail: { omics: c.omics } }));

    detail.innerHTML = `
      <div class="card">
        <h2>${esc(c.title)}</h2>
        <p class="hint">${esc(c.subtitle || "")}</p>
        <p><strong>${t("teach.sciQ")}</strong>${esc(c.scientific_question)}</p>
        <p>${esc(c.background)}</p>
        <p class="hint"><strong>${t("teach.dataHint")}</strong>${esc(c.data_hint)}</p>
        <p class="hint"><strong>${t("teach.recPath")}</strong>${esc(OMICS_PATHS[c.omics] || "Import → Prepare → Analyze → Visualize")}</p>
        <p class="hint"><strong>${t("teach.recParams")}</strong>${esc(omicsDefaultsHint(c.omics))}</p>
        <p class="hint"><strong>${t("teach.learnFlow")}</strong>${t("teach.learnFlowBody")}</p>
        <div class="btn-row teaching-case-actions">
          <button type="button" class="btn btn-primary btn-load-case-demo" data-omics="${esc(c.omics || "")}">${t("teach.loadDemo")}</button>
          <button type="button" class="btn btn-outline btn-apply-case-defaults" data-omics="${esc(c.omics || "")}">${t("teach.applyDefaults")}</button>
        </div>
      </div>
      <div class="teaching-task-list">
        ${(c.tasks || []).map((t, i) => renderTaskCard(t, i, caseId)).join("")}
      </div>`;

    bindCaseDetailEvents(detail, caseId);
    detail.querySelector(".btn-load-case-demo")?.addEventListener("click", async () => {
      const omics = c.omics || "";
      const demoMap = {
        microbiome_16s: "m16s_course",
        transcriptomics: "rnaseq_course",
        metabolomics: "m16s_course",
        metagenomics: "m16s_course",
      };
      const demoId = demoMap[omics] || "m16s_course";
      window.dispatchEvent(new CustomEvent("emp:navigate", { detail: { page: "import" } }));
      window.dispatchEvent(new CustomEvent("emp:import-demo", { detail: { datasetId: demoId, omics } }));
      teachToast(t("teach.loadingDemo"), "info");
    });
    detail.querySelector(".btn-apply-case-defaults")?.addEventListener("click", () => {
      window.dispatchEvent(new CustomEvent("emp:apply-omics-defaults", {
        detail: { omics: c.omics || "" },
      }));
    });
    await traceEvent({ event_type: "case_open", case_id: caseId });
  } catch (e) {
    detail.innerHTML = `<p class="hint">${t("teach.loadFail")}${esc(e.message)}</p>`;
  }
}

async function renderPromptLibrary() {
  const root = document.getElementById("teaching-prompt-root");
  if (!root) return;
  root.innerHTML = `<p class="hint">${t("teach.loadingPrompts")}</p>`;
  try {
    const data = await API.teachingPrompts();
    const cats = data.categories || [];
    root.innerHTML = cats.map((cat) => `
      <div class="card teaching-prompt-cat">
        <h3>${esc(cat.title)}</h3>
        <p class="hint">${esc(cat.description)}</p>
        ${(cat.templates || []).map((tpl) => `
          <details class="teaching-prompt-item">
            <summary>${esc(tpl.title)}</summary>
            <p class="hint"><strong>${t("prompts.usage")}</strong>${esc(tpl.usage)}</p>
            <p class="hint"><strong>${t("prompts.pitfalls")}</strong>${(tpl.pitfalls || []).map(esc).join(getLocale() === "en" ? "; " : "；")}</p>
            <pre class="teaching-prompt-text">${esc(tpl.prompt)}</pre>
            <button type="button" class="btn btn-outline btn-copy-prompt">${t("prompts.copy")}</button>
            <button type="button" class="btn btn-primary btn-use-prompt">${t("prompts.use")}</button>
          </details>
        `).join("")}
      </div>`).join("");

    root.querySelectorAll(".teaching-prompt-item").forEach((item) => {
      const pre = item.querySelector(".teaching-prompt-text");
      item.querySelector(".btn-copy-prompt")?.addEventListener("click", async () => {
        await navigator.clipboard.writeText(pre.textContent);
        traceEvent({ event_type: "prompt_copy", template: item.querySelector("summary")?.textContent });
        teachToast(t("prompts.copied"), "success");
      });
      item.querySelector(".btn-use-prompt")?.addEventListener("click", () => {
        const inst = document.getElementById("code-lab-llm-instruction");
        if (inst) inst.value = pre.textContent;
        traceEvent({ event_type: "prompt_use", template: item.querySelector("summary")?.textContent });
        window.dispatchEvent(new CustomEvent("emp:open-code-lab", { detail: { page: "analysis" } }));
        teachToast(t("prompts.applied"), "success");
      });
    });
  } catch (e) {
    root.innerHTML = `<p class="hint">${t("prompts.loadFail")}${esc(e.message)}</p>`;
  }
}

async function renderCritiqueLab() {
  const root = document.getElementById("teaching-panel-critique");
  if (!root) return;
  try {
    const data = await API.teachingCritiqueCases();
    const cases = data.cases || [];
    root.innerHTML = cases.map((c) => `
      <div class="card teaching-critique-card" data-case-id="${esc(c.id)}">
        <h3>${esc(c.title)}</h3>
        <p class="teaching-ai-error">${esc(c.ai_text)}</p>
        <p class="hint">${t("teach.critiqueHint")}${(c.hints || []).map(esc).join(getLocale() === "en" ? "; " : "；")}</p>
        <fieldset>
          <legend>${t("teach.errorTypes")}</legend>
          ${(c.error_types || []).map((t) => `
            <label class="teaching-check"><input type="checkbox" value="${esc(t)}"> ${esc(t)}</label>`).join("")}
        </fieldset>
        <label>${t("teach.correctInterp")}
          <textarea class="teaching-critique-correction" rows="4" placeholder="${esc(c.correction_guide || "")}"></textarea>
        </label>
        <label>${t("teach.improvePrompt")}
          <input type="text" class="teaching-critique-prompt" placeholder="${esc(t("teach.improvePromptPh"))}">
        </label>
        <button type="button" class="btn btn-primary btn-submit-critique">${t("teach.submitCritique")}</button>
      </div>`).join("");

    root.querySelectorAll(".teaching-critique-card").forEach((card) => {
      card.querySelector(".btn-submit-critique").addEventListener("click", async () => {
        const types = [...card.querySelectorAll('input[type="checkbox"]:checked')].map((x) => x.value);
        const correction = card.querySelector(".teaching-critique-correction")?.value || "";
        const prompt_reflection = card.querySelector(".teaching-critique-prompt")?.value || "";
        try {
          await ensureSession();
          await API.teachingSubmitCritique({
            case_id: card.dataset.caseId,
            error_types: types,
            correction,
            prompt_reflection,
          });
          teachToast(t("teach.critiqueSaved"), "success");
        } catch (err) {
          teachToast(err.message || String(err), "error");
        }
      });
    });
  } catch (e) {
    root.innerHTML = `<p class="hint">${esc(e.message)}</p>`;
  }
}

function setupTeachingTabs() {
  const tabs = document.querySelectorAll(".teaching-tab");
  const panels = {
    cases: document.getElementById("teaching-panel-cases"),
    critique: document.getElementById("teaching-panel-critique"),
  };
  tabs.forEach((tab) => {
    tab.addEventListener("click", async () => {
      tabs.forEach((t) => t.classList.remove("active"));
      tab.classList.add("active");
      const id = tab.dataset.teachingTab;
      Object.entries(panels).forEach(([k, el]) => el?.classList.toggle("hidden", k !== id));
      if (id === "critique") await renderCritiqueLab();
    });
  });
}

function setupJournalAndReport() {
  document.getElementById("btn-teaching-journal-save")?.addEventListener("click", async () => {
    try {
      await ensureSession();
      await API.teachingSaveJournal({
        interpretation: document.getElementById("teaching-journal-interpretation")?.value || "",
        hypothesis: document.getElementById("teaching-journal-hypothesis")?.value || "",
        limitations: document.getElementById("teaching-journal-limitations")?.value || "",
        ai_declaration: document.getElementById("teaching-journal-ai")?.value || "",
      });
      teachToast(t("teach.journalSaved"), "success");
    } catch (e) {
      teachToast(e.message || String(e), "error");
    }
  });
  document.getElementById("btn-teaching-report")?.addEventListener("click", async () => {
    try {
      await ensureSession();
      const res = await API.teachingReport();
      const sid = localStorage.getItem("emp_session_id") || "local";
      const blob = new Blob([res.markdown || ""], { type: "text/markdown;charset=utf-8" });
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = `EMP_project_report_${sid.slice(0, 8)}.md`;
      a.click();
      URL.revokeObjectURL(a.href);
    } catch (e) {
      teachToast(e.message || String(e), "error");
    }
  });
}

export async function initTeaching() {
  setupTeachingTabs();
  setupJournalAndReport();
  window.addEventListener("emp:navigate", (e) => {
    const page = e.detail?.page;
    if (page && typeof window.__empNavigate === "function") window.__empNavigate(page);
  });
  window.addEventListener("emp:locale-change", async () => {
    if (document.getElementById("page-course")?.classList.contains("active")) {
      await renderCaseList();
      const cid = activeCaseId();
      if (cid) await loadCaseDetail(cid);
    }
    if (document.getElementById("page-prompts")?.classList.contains("active")) await renderPromptLibrary();
    const critique = document.getElementById("teaching-panel-critique");
    if (critique && !critique.classList.contains("hidden")) await renderCritiqueLab();
  });
}

export async function onTeachingPage(page) {
  if (page === "course") await renderCaseList();
  if (page === "prompts") await renderPromptLibrary();
}

export function setupTeachingTraceHooks() {
  window.addEventListener("emp:timing", (e) => {
    const d = e.detail || {};
    if (!d.ok || !d.path) return;
    const interesting = /^\/(import|analyze|visualize|prepare|clinical|llm|user_r|runall)/.test(d.path);
    if (!interesting) return;
    traceEvent({
      event_type: "api_call",
      path: d.path,
      method: d.method,
      total_ms: d.total_ms,
      backend_ms: d.backend_ms,
      case_id: activeCaseId(),
      experiment: window._emp?.currentExp,
    });
  });
}
