/**
 * Teaching mode: video-gated cases, prompts, learning trace.
 */
import * as API from "./api.js?v=2026-06-20-genz-v1";

const LS_CASE = "emp_teaching_active_case";

const EMP_PAGE_LABELS = {
  import: "导入数据 Data",
  summary: "数据概览 Summary",
  inspector: "数据检查 Inspector",
  preparation: "预处理 Prepare",
  analysis: "分析 Analyze",
  clinical: "临床 Clinical",
  runall: "一键运行 Run All",
  visualization: "可视化 Visualize",
  export: "导出 Export",
  prompts: "AI Prompt 库",
};

function teachToast(msg, type = "info") {
  window.dispatchEvent(new CustomEvent("emp:toast", { detail: { msg, type } }));
}

const OMICS_PATHS = {
  transcriptomics: "Import → Summary → Prepare → Analyze (DESeq2) → Visualize (Volcano) → Export",
  microbiome_16s: "Import (Taxonomy) → Prepare → Analyze (Alpha) → Visualize → Clinical",
  metabolomics: "Import → Prepare → Analyze → Clinical (联合)",
  metagenomics: "Import → Prepare → Analyze → Visualize",
};

const PHASE_LABELS = {
  import: "数据导入",
  prepare: "质控与预处理",
  analysis: "核心分析",
  visualization: "可视化",
  interpretation: "结果解读与假设",
  question: "科学问题",
  method: "方法 / 数据",
  hypothesis: "假设 / 表达",
};

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
      <summary>分镜脚本 / 画面提示</summary>
      <ul class="teaching-sb-list">${rows}</ul>
    </details>`;
}

function renderTakeaways(items) {
  const lis = (items || []).map((s) => `<li>${esc(s)}</li>`).join("");
  if (!lis) return "";
  return `
    <div class="teaching-takeaways">
      <h5>关键要点</h5>
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
  const note = v.source_note ? esc(v.source_note) : "外部参考视频";
  return `
    <p class="teaching-refsource hint">延伸参考：<a href="${url}" target="_blank" rel="noopener noreferrer">${note} ↗</a></p>`;
}

function renderVideoBlock(v) {
  return `
    <div class="teaching-video-block teaching-lesson" data-video-id="${esc(v.id)}">
      <div class="teaching-video-head">
        <span class="tag teaching-video-aspect">${esc(v.step_label || v.aspect_label || v.aspect)}</span>
        <strong>${esc(v.title)}</strong>
        <span class="hint">${esc(v.duration || "")}</span>
        <span class="tag teaching-orig-tag">科普动画 · 中文配音</span>
      </div>
      ${v.objective ? `<p class="teaching-lesson-objective"><span class="teaching-lesson-tag">学习目标</span>${esc(v.objective)}</p>` : ""}
      ${renderLocalVideo(v)}
      ${v.description ? `<p class="hint teaching-video-desc">${esc(v.description)}</p>` : ""}
      <details class="teaching-script-fold">
        <summary>讲解文稿（视频字幕全文）</summary>
        <div class="teaching-lesson-script">${renderScript(v.script)}</div>
      </details>
      ${renderTakeaways(v.takeaways)}
      ${renderStoryboard(v.storyboard)}
      ${renderReferenceLink(v)}
    </div>`;
}

function renderQuizBlock(t, caseId) {
  if (!t.quiz?.questions?.length) return "";
  if (t.quiz_passed) {
    return '<p class="teaching-quiz-passed">✓ 测验已通过，可进行实操与反思。</p>';
  }
  const qs = t.quiz.questions.map((q, qi) => `
    <fieldset class="teaching-quiz-q" data-qid="${esc(q.id)}">
      <legend>${qi + 1}. ${esc(q.question)}</legend>
      ${(q.options || []).map((opt, oi) => `
        <label class="teaching-quiz-opt">
          <input type="radio" name="quiz-${esc(t.id)}-${esc(q.id)}" value="${oi}">
          ${esc(opt)}
        </label>`).join("")}
    </fieldset>`).join("");
  return `
    <div class="teaching-quiz" data-case="${esc(caseId)}" data-task="${esc(t.id)}">
      <h4>步骤测验（需全部答对才能解锁下一步）</h4>
      <p class="hint">请先学习上方背景微课，再完成 ${t.quiz.questions.length} 道选择题。</p>
      ${qs}
      <div class="teaching-quiz-actions">
        <button type="button" class="btn btn-primary btn-submit-quiz">提交测验</button>
        <span class="teaching-quiz-feedback hint"></span>
      </div>
    </div>`;
}

function renderTaskCard(t, i, caseId) {
  const locked = !t.unlocked;
  const videos = (t.videos || []).map(renderVideoBlock).join("");
  const quiz = locked ? "" : renderQuizBlock(t, caseId);
  const canPractice = t.quiz_passed;
  const done = t.reflection_done;

  const empLabel = t.emp_page ? (EMP_PAGE_LABELS[t.emp_page] || t.emp_page) : "";
  return `
    <article class="teaching-task-card ${done ? "is-done" : ""} ${locked ? "is-locked" : ""} ${t.quiz_passed ? "quiz-done" : ""}" data-task-id="${esc(t.id)}">
      ${locked ? '<div class="teaching-lock-banner">🔒 请先完成上一步视频测验以解锁</div>' : ""}
      <header>
        <span class="teaching-task-num">${i + 1}</span>
        <span class="tag">${esc(PHASE_LABELS[t.phase] || t.phase)}</span>
        ${t.quiz_passed ? '<span class="tag tag-ok">测验通过</span>' : ""}
        ${done ? '<span class="tag tag-ok">反思已提交</span>' : ""}
        <h3>${esc(t.title)}</h3>
      </header>
      <p>${esc(t.instructions)}</p>
      ${videos ? `<div class="teaching-videos">${videos}</div>` : ""}
      ${quiz}
      <div class="teaching-practice ${canPractice ? "" : "is-disabled"}">
        ${t.emp_page ? `<button type="button" class="btn btn-outline btn-goto-emp" data-page="${esc(t.emp_page)}" ${canPractice ? "" : "disabled"}>前往实操：${esc(empLabel)}</button>` : ""}
        <label class="teaching-reflection-label">${esc(t.reflection_prompt || "学习反思")}
          <textarea class="teaching-reflection" rows="3" data-case="${esc(caseId)}" data-task="${esc(t.id)}" ${canPractice ? "" : "disabled"}></textarea>
        </label>
        <label class="teaching-reflection-label">AI 使用声明（可选）
          <input type="text" class="teaching-ai-decl" data-case="${esc(caseId)}" data-task="${esc(t.id)}" placeholder="例：仅用 AI 解释参数，结果解读为本人修改" ${canPractice ? "" : "disabled"}>
        </label>
        <button type="button" class="btn btn-primary btn-save-reflection" data-case="${esc(caseId)}" data-task="${esc(t.id)}" ${canPractice ? "" : "disabled"}>提交反思</button>
        ${!canPractice && !locked ? '<p class="hint">通过本步测验后可进行 EMP 实操与反思提交。</p>' : ""}
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
        <span class="tag">${tasks.length} 个步骤</span>
      </button>`;
    }).join("");
    list.querySelectorAll(".teaching-case-card").forEach((btn) => {
      btn.addEventListener("click", () => loadCaseDetail(btn.dataset.caseId));
    });
    const saved = activeCaseId();
    if (saved) loadCaseDetail(saved);
    else if (detail) detail.innerHTML = '<p class="hint">选择左侧组学，按步骤学习 3-5 分钟背景微课并通过测验解锁下一步。</p>';
  } catch (e) {
    list.innerHTML = `<p class="hint">无法加载案例：${esc(e.message)}</p>`;
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
          box.querySelector(".teaching-quiz-feedback").textContent = "请回答所有题目。";
          return;
        }
        answers.push({ id: qid, choice: Number(picked.value) });
      }
      btn.disabled = true;
      const feedback = box.querySelector(".teaching-quiz-feedback");
      feedback.textContent = "提交中…";
      try {
        await ensureSession();
        const res = await API.teachingSubmitQuiz({ case_id: caseId, task_id: taskId, answers });
        if (res.passed) {
          feedback.textContent = "全部正确！下一步已解锁。";
          await traceEvent({ event_type: "quiz_pass", case_id: caseId, task_id: taskId });
          await loadCaseDetail(caseId);
          await renderCaseList();
        } else {
          const wrongHint = (res.wrong_ids || []).length
            ? `（第 ${(res.wrong_ids || []).join("、")} 题需复习）`
            : "";
          feedback.textContent = `答对 ${res.correct}/${res.total} 题，请复习视频后重试。${wrongHint}`;
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
        teachToast("反思已保存并记录到 Learning Trace。", "success");
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
  detail.innerHTML = '<p class="hint">加载中…</p>';
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
        <p><strong>科学问题：</strong>${esc(c.scientific_question)}</p>
        <p>${esc(c.background)}</p>
        <p class="hint"><strong>数据提示：</strong>${esc(c.data_hint)}</p>
        <p class="hint"><strong>推荐路径：</strong>${esc(OMICS_PATHS[c.omics] || "Import → Prepare → Analyze → Visualize")}</p>
        <p class="hint"><strong>学习流程：</strong>观看教学视频 → 完成测验（全部正确）→ 解锁下一步 → EMP 实操与反思</p>
        <div class="btn-row teaching-case-actions">
          <button type="button" class="btn btn-primary btn-load-case-demo" data-omics="${esc(c.omics || "")}">一键加载本课示例数据</button>
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
      teachToast("正在加载课程示例数据…", "info");
    });
    await traceEvent({ event_type: "case_open", case_id: caseId });
  } catch (e) {
    detail.innerHTML = `<p class="hint">加载失败：${esc(e.message)}</p>`;
  }
}

async function renderPromptLibrary() {
  const root = document.getElementById("teaching-prompt-root");
  if (!root) return;
  root.innerHTML = '<p class="hint">加载 Prompt 库…</p>';
  try {
    const data = await API.teachingPrompts();
    const cats = data.categories || [];
    root.innerHTML = cats.map((cat) => `
      <div class="card teaching-prompt-cat">
        <h3>${esc(cat.title)}</h3>
        <p class="hint">${esc(cat.description)}</p>
        ${(cat.templates || []).map((t) => `
          <details class="teaching-prompt-item">
            <summary>${esc(t.title)}</summary>
            <p class="hint"><strong>用途：</strong>${esc(t.usage)}</p>
            <p class="hint"><strong>常见错误：</strong>${(t.pitfalls || []).map(esc).join("；")}</p>
            <pre class="teaching-prompt-text">${esc(t.prompt)}</pre>
            <button type="button" class="btn btn-outline btn-copy-prompt">复制 Prompt</button>
            <button type="button" class="btn btn-primary btn-use-prompt">填入 LLM 优化说明</button>
          </details>
        `).join("")}
      </div>`).join("");

    root.querySelectorAll(".teaching-prompt-item").forEach((item) => {
      const pre = item.querySelector(".teaching-prompt-text");
      item.querySelector(".btn-copy-prompt")?.addEventListener("click", async () => {
        await navigator.clipboard.writeText(pre.textContent);
        traceEvent({ event_type: "prompt_copy", template: item.querySelector("summary")?.textContent });
        teachToast("Prompt 已复制到剪贴板", "success");
      });
      item.querySelector(".btn-use-prompt")?.addEventListener("click", () => {
        const inst = document.getElementById("code-lab-llm-instruction");
        if (inst) inst.value = pre.textContent;
        traceEvent({ event_type: "prompt_use", template: item.querySelector("summary")?.textContent });
        window.dispatchEvent(new CustomEvent("emp:open-code-lab", { detail: { page: "analysis" } }));
        teachToast("已填入 Code Lab 并打开面板", "success");
      });
    });
  } catch (e) {
    root.innerHTML = `<p class="hint">无法加载 Prompt 库：${esc(e.message)}</p>`;
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
        <p class="hint">提示：${(c.hints || []).map(esc).join("；")}</p>
        <fieldset>
          <legend>错误类型（多选）</legend>
          ${(c.error_types || []).map((t) => `
            <label class="teaching-check"><input type="checkbox" value="${esc(t)}"> ${esc(t)}</label>`).join("")}
        </fieldset>
        <label>正确解读
          <textarea class="teaching-critique-correction" rows="4" placeholder="${esc(c.correction_guide || "")}"></textarea>
        </label>
        <label>如何改进 Prompt
          <input type="text" class="teaching-critique-prompt" placeholder="例：要求仅基于给定统计量解读，禁止推断因果">
        </label>
        <button type="button" class="btn btn-primary btn-submit-critique">提交纠错</button>
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
          teachToast("纠错练习已记录。", "success");
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
      teachToast("科学解读与假设已保存。", "success");
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
