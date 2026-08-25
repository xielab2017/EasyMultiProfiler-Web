// Course GitHub sync panel: student login, repo bind, weekly / project sync.
import * as API from "./api.js?v=2026-07-22-import-auth-v5";
import { t } from "./locale.js?v=nav-active-fix-v1";

const LS_STUDENT_TOKEN = "emp_student_token";
const LS_TRACK = "emp_github_track";
const LS_ASSIGNMENT = "emp_github_assignment";
const LS_CUSTOM_TRACK = "emp_github_custom_track";
const LS_CUSTOM_ASG = "emp_github_custom_assignment";

const DEFAULT_CLASS_REPO =
  "https://github.com/xielab2017/Bioinformatics_homework_XieLiwei";

const TRACK_TITLE_KEYS = {
  microbiome_16s: "omics.microbiome_16s",
  transcriptomics: "omics.transcriptomics",
  metabolomics: "omics.metabolomics",
  metagenomics: "omics.metagenomics",
  clinical: "omics.clinical",
  multiomics: "omics.multiomics",
  customize: "github.track.customize",
};

/** Fixed assignment menu — always available even if API is down. */
function builtinAssignments() {
  return [
    ...Array.from({ length: 16 }, (_, i) => {
      const n = i + 1;
      const id = `week_${String(n).padStart(2, "0")}`;
      return { id, week: n, type: "weekly", title: t("github.weekN", null, { n }) };
    }),
    { id: "project_major", type: "project", title: t("github.projectMajor") },
  ];
}

let _tracks = [];
let _student = null;
/** Serialize Sync clicks — prevent overlapping homework sync requests. */
let emp_sync_inflight = false;

function toast(msg, type = "info") {
  window.dispatchEvent(new CustomEvent("emp:toast", { detail: { msg, type } }));
}

function setLoading(on) {
  const el = document.getElementById("loading-spinner");
  if (el) el.classList.toggle("hidden", !on);
}

function setSyncButtonDisabled(disabled) {
  const btn = $("btn-gh-sync");
  if (!btn) return;
  btn.disabled = !!disabled;
  btn.setAttribute("aria-busy", disabled ? "true" : "false");
}

/** True when analysis / busy UI is active (spinner, progress bar, or busy depth). */
function isAnalysisOrBusyActive() {
  if ((window._emp?.analysisBusy || 0) > 0) return true;
  const gp = document.getElementById("global-progress");
  if (gp && !gp.classList.contains("hidden")) return true;
  const spinner = document.getElementById("loading-spinner");
  // Spinner may be used by sync itself; only treat as busy when sync is NOT the owner.
  if (spinner && !spinner.classList.contains("hidden") && !emp_sync_inflight) return true;
  return false;
}

/** Guard sync: block while analysis/jobs run or another sync is in flight. */
function assertCanSync() {
  if (emp_sync_inflight || window._emp?.syncInflight) {
    toast(t("github.syncInProgress"), "error");
    return false;
  }
  if (isAnalysisOrBusyActive()) {
    toast(t("github.analysisRunning"), "error");
    return false;
  }
  return true;
}

function $(id) {
  return document.getElementById(id);
}

function esc(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function trackTitle(tr) {
  if (!tr) return "";
  const key = TRACK_TITLE_KEYS[tr.id];
  return key ? t(key) : (tr.title || tr.id);
}

function currentTrack() {
  const id = $("gh-track")?.value;
  return _tracks.find((tr) => tr.id === id) || null;
}

function currentAssignment() {
  const id = $("gh-assignment")?.value;
  return builtinAssignments().find((a) => a.id === id) || null;
}

function updateCustomFields() {
  const track = currentTrack();
  const trackWrap = $("gh-custom-track-wrap");
  if (trackWrap) trackWrap.classList.toggle("hidden", !(track && track.custom));
  updatePathPreview();
}

/** Slug for customize track — mirrors backend .github_slugify loosely. */
function slugifyTrack(text, fallback = "customize") {
  const raw = String(text || "").trim();
  if (!raw) return fallback;
  let slug = raw
    .normalize("NFKD")
    .replace(/[^\x00-\x7F]/g, "")
    .replace(/[^A-Za-z0-9._-]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 48);
  if (!slug || !/^[A-Za-z0-9]/.test(slug)) slug = fallback;
  return slug;
}

/** Live preview of week-first GitHub path (UI Week N ↔ folder Week_0N). */
function previewGitPath() {
  const trackSel = $("gh-track")?.value || "track";
  const asg = currentAssignment();
  let weekDir;
  let typeDir;
  if (asg?.type === "project") {
    weekDir = asg.id === "project_major" ? "Project_Major" : "Project_Other";
    typeDir = "project";
  } else {
    const n = asg?.week || 1;
    weekDir = `Week_${String(n).padStart(2, "0")}`;
    typeDir = "weekly";
  }
  let trackFolder = trackSel;
  const track = currentTrack();
  if (track?.custom || trackSel === "customize") {
    const custom = ($("gh-custom-track")?.value || "").trim();
    trackFolder = custom ? slugifyTrack(custom) : "customize";
  }
  return `EMP2026/${weekDir}/${trackFolder}/${typeDir}/runs/<timestamp>/`;
}

function updatePathPreview() {
  const el = $("gh-path-preview");
  if (!el) return;
  const path = previewGitPath();
  const prefix = t("github.pathPreview", null, { path: "" }).replace("{path}", "").trim();
  el.innerHTML = `${esc(prefix)} <code>${esc(path)}</code>`;
}

function prefillClassRepo(url) {
  const input = $("gh-repo-url");
  if (!input) return;
  const repoUrl = (url || DEFAULT_CLASS_REPO).trim() || DEFAULT_CLASS_REPO;
  input.value = repoUrl;
  input.readOnly = true;
  input.setAttribute("aria-readonly", "true");
  const hint = $("gh-repo-lock-hint");
  if (hint) hint.textContent = t("github.classRepoLocked");
}

function applyAuthClassRepo(res) {
  const classRepo = res?.class_homework_repo || DEFAULT_CLASS_REPO;
  prefillClassRepo(classRepo);
  if (res?.student) _student = res.student;
  const bound = !!(res?.github_bound || (_student?.github && _student.github.bound));
  setPanelMode(bound ? "bound" : "logged_in");
  renderStudentChip();
  if (res?.need_pat && !bound) {
    toast(t("github.needPatForClass"), "info");
  } else if (res?.auto_bound) {
    toast(t("github.autoBoundOk"), "success");
  }
}

function fillAssignmentSelect() {
  const asgSel = $("gh-assignment");
  if (!asgSel) return;
  const prev = localStorage.getItem(LS_ASSIGNMENT) || asgSel.value || "week_01";
  const list = builtinAssignments();
  asgSel.innerHTML = list.map((a) =>
    `<option value="${esc(a.id)}">${esc(a.title)}</option>`
  ).join("");
  asgSel.disabled = false;
  asgSel.removeAttribute("aria-disabled");
  if (prev && [...asgSel.options].some((o) => o.value === prev)) {
    asgSel.value = prev;
  } else {
    asgSel.value = "week_01";
  }
  updateCustomFields();
}

function setPanelMode(mode) {
  const auth = $("gh-auth-panel");
  const bind = $("gh-bind-panel");
  const sync = $("gh-sync-panel");
  if (!auth || !bind || !sync) return;
  const loggedIn = mode === "logged_in" || mode === "bound";
  auth.classList.toggle("hidden", loggedIn);
  bind.classList.toggle("hidden", !loggedIn);
  sync.classList.toggle("hidden", mode !== "bound");
}

function renderStudentChip() {
  const el = $("gh-student-chip");
  if (!el) return;
  if (!_student) {
    el.innerHTML = `<span class="hint">${esc(t("github.notLoggedIn"))}</span>`;
    return;
  }
  const gh = _student.github || {};
  const repo = gh.bound ? `${gh.owner}/${gh.repo}` : t("github.repoNotBound");
  el.innerHTML = `
    <strong>${esc(_student.display_name || _student.student_id)}</strong>
    <span class="hint"> · ${esc(_student.student_id)}</span>
    <span class="tag">${esc(repo)}</span>`;
}

function fillTrackSelect() {
  const sel = $("gh-track");
  if (!sel) return;
  const prev = localStorage.getItem(LS_TRACK) || sel.value;
  const fallbackTracks = [
    { id: "microbiome_16s" },
    { id: "transcriptomics" },
    { id: "metabolomics" },
    { id: "metagenomics" },
    { id: "clinical" },
    { id: "multiomics" },
    { id: "customize", custom: true },
  ];
  const tracks = (_tracks && _tracks.length) ? _tracks : fallbackTracks;
  if (!_tracks.length) _tracks = fallbackTracks.map((tr) => ({ ...tr, title: trackTitle(tr) }));
  // Ensure customize flag
  tracks.forEach((tr) => {
    if (tr.id === "customize") tr.custom = true;
  });
  sel.innerHTML = tracks.map((tr) =>
    `<option value="${esc(tr.id)}">${esc(trackTitle(tr))}</option>`
  ).join("");
  sel.disabled = false;
  if (prev && [...sel.options].some((o) => o.value === prev)) sel.value = prev;
  const ct = $("gh-custom-track");
  if (ct && localStorage.getItem(LS_CUSTOM_TRACK)) ct.value = localStorage.getItem(LS_CUSTOM_TRACK);
  const ca = $("gh-custom-assignment");
  if (ca && localStorage.getItem(LS_CUSTOM_ASG)) ca.value = localStorage.getItem(LS_CUSTOM_ASG);
  fillAssignmentSelect();
  updatePathPreview();
}

async function refreshStatus() {
  const token = localStorage.getItem(LS_STUDENT_TOKEN);
  if (!token) {
    _student = null;
    setPanelMode("auth");
    renderStudentChip();
    prefillClassRepo(DEFAULT_CLASS_REPO);
    return;
  }
  try {
    const res = await API.githubStatus();
    _student = res.student;
    prefillClassRepo(res.class_homework_repo || DEFAULT_CLASS_REPO);
    const bound = !!(res.student && res.student.github && res.student.github.bound);
    setPanelMode(bound ? "bound" : "logged_in");
    renderStudentChip();
    await refreshSyncHistory();
  } catch (e) {
    localStorage.removeItem(LS_STUDENT_TOKEN);
    _student = null;
    setPanelMode("auth");
    renderStudentChip();
    prefillClassRepo(DEFAULT_CLASS_REPO);
  }
}

async function refreshSyncHistory() {
  const box = $("gh-sync-history");
  if (!box) return;
  if (!localStorage.getItem(LS_STUDENT_TOKEN)) {
    box.innerHTML = "";
    return;
  }
  try {
    const res = await API.githubSyncs();
    const syncs = res.syncs || [];
    if (!syncs.length) {
      box.innerHTML = `<p class="hint">${esc(t("github.noSyncHistory"))}</p>`;
      return;
    }
    box.innerHTML = `<ul class="gh-sync-list">${syncs.map((s) => {
      const title = s.assignment_title || s.assignment_id || "";
      const track = s.track_title || s.track_id || "";
      const when = s.synced_at || "";
      const link = s.html_url
        ? `<a href="${esc(s.html_url)}" target="_blank" rel="noopener noreferrer">${esc(t("github.viewCommit"))}</a>`
        : "";
      return `<li><span class="gh-sync-meta">${esc(when)}</span>
        <strong>${esc(track)} / ${esc(title)}</strong>
        <span class="hint">${esc(s.git_path || s.week_dir || "")} · v${esc(s.emp_version || "")} · run ${esc(s.run_id || "")} · ${esc(String(s.n_files || 0))} files</span>
        ${link}</li>`;
    }).join("")}</ul>`;
  } catch {
    box.innerHTML = "";
  }
}

async function onRegister() {
  const student_id = ($("gh-student-id")?.value || "").trim();
  const password = $("gh-password")?.value || "";
  const display_name = ($("gh-display-name")?.value || "").trim();
  if (!student_id || !password) {
    toast(t("github.needIdPassword"), "error");
    return;
  }
  if (!display_name) {
    toast(t("github.needDisplayName"), "error");
    return;
  }
  setLoading(true);
  try {
    const res = await API.githubRegister({ student_id, password, display_name });
    localStorage.setItem(LS_STUDENT_TOKEN, res.student_token);
    toast(t("github.registerOk"), "success");
    applyAuthClassRepo(res);
    await refreshSyncHistory();
  } catch (e) {
    toast(e.message || String(e), "error");
  } finally {
    setLoading(false);
  }
}

async function onLogin() {
  const student_id = ($("gh-student-id")?.value || "").trim();
  const password = $("gh-password")?.value || "";
  const display_name = ($("gh-display-name")?.value || "").trim();
  if (!student_id || !password) {
    toast(t("github.needIdPassword"), "error");
    return;
  }
  setLoading(true);
  try {
    const payload = { student_id, password };
    if (display_name) payload.display_name = display_name;
    const res = await API.githubLogin(payload);
    localStorage.setItem(LS_STUDENT_TOKEN, res.student_token);
    toast(t("github.loginOk"), "success");
    applyAuthClassRepo(res);
    await refreshSyncHistory();
  } catch (e) {
    toast(e.message || String(e), "error");
  } finally {
    setLoading(false);
  }
}

async function onLogout() {
  try {
    await API.githubLogout();
  } catch { /* ignore */ }
  localStorage.removeItem(LS_STUDENT_TOKEN);
  _student = null;
  setPanelMode("auth");
  renderStudentChip();
  toast(t("github.logoutOk"), "info");
}

async function onBind() {
  const repo_url = ($("gh-repo-url")?.value || "").trim() || DEFAULT_CLASS_REPO;
  const github_token = ($("gh-pat")?.value || "").trim();
  const branch = ($("gh-branch")?.value || "").trim() || null;
  if (!github_token) {
    toast(t("github.needRepoToken"), "error");
    return;
  }
  setLoading(true);
  try {
    const res = await API.githubBind({ repo_url, github_token, branch });
    _student = res.student;
    if ($("gh-pat")) $("gh-pat").value = "";
    prefillClassRepo(repo_url);
    toast(t("github.bindOk"), "success");
    setPanelMode("bound");
    renderStudentChip();
  } catch (e) {
    toast(e.message || String(e), "error");
  } finally {
    setLoading(false);
  }
}

async function onUnbind() {
  if (!confirm(t("github.unbindConfirm"))) return;
  setLoading(true);
  try {
    const res = await API.githubUnbind();
    _student = res.student;
    toast(t("github.unbindOk"), "info");
    setPanelMode("logged_in");
    renderStudentChip();
  } catch (e) {
    toast(e.message || String(e), "error");
  } finally {
    setLoading(false);
  }
}

async function onSync() {
  if (!assertCanSync()) return;

  const track_id = $("gh-track")?.value;
  const assignment_id = $("gh-assignment")?.value;
  if (!track_id || !assignment_id) {
    toast(t("github.needAssignment"), "error");
    return;
  }
  const track = currentTrack();
  const custom_track_name = ($("gh-custom-track")?.value || "").trim();
  const custom_assignment_title = ($("gh-custom-assignment")?.value || "").trim();

  if (track?.custom && !custom_track_name) {
    toast(t("github.needCustomTrack"), "error");
    return;
  }

  localStorage.setItem(LS_TRACK, track_id);
  localStorage.setItem(LS_ASSIGNMENT, assignment_id);
  if (custom_track_name) localStorage.setItem(LS_CUSTOM_TRACK, custom_track_name);
  if (custom_assignment_title) localStorage.setItem(LS_CUSTOM_ASG, custom_assignment_title);

  const commit_message = ($("gh-commit-msg")?.value || "").trim() || null;
  const include_rds = !!$("gh-include-rds")?.checked;
  let session_id = localStorage.getItem("emp_session_id") || null;
  // A copied/moved backend can leave an old session id in browser storage.
  // Validate it before submission and transparently create a fresh owned
  // session when the previous backend no longer knows it.
  const experiment = window._emp?.currentExp || null;

  emp_sync_inflight = true;
  if (window._emp) window._emp.syncInflight = true;
  setSyncButtonDisabled(true);
  setLoading(true);
  try {
    if (session_id) session_id = await API.ensureSession();
    const res = await API.githubSync({
      track_id,
      assignment_id,
      custom_track_name: custom_track_name || null,
      custom_assignment_title: custom_assignment_title || null,
      session_id,
      experiment,
      include_rds,
      commit_message,
    });
    const okMsg = res.message || t("github.syncOk");
    toast(okMsg, res.partial ? "info" : "success");
    if (res.sync?.html_url) {
      const link = $("gh-last-commit");
      if (link) {
        link.href = res.sync.html_url;
        link.textContent = t("github.viewCommit");
        link.classList.remove("hidden");
      }
    }
    await refreshSyncHistory();
  } catch (e) {
    const msg = e.message || String(e);
    toast(msg, "error");
  } finally {
    emp_sync_inflight = false;
    if (window._emp) window._emp.syncInflight = false;
    setSyncButtonDisabled(false);
    setLoading(false);
  }
}

function setLabelTextBeforeInput(labelEl, text) {
  if (!labelEl) return;
  for (const n of labelEl.childNodes) {
    if (n.nodeType === Node.TEXT_NODE && n.textContent.trim()) {
      n.textContent = text;
      return;
    }
    if (n.nodeType === Node.ELEMENT_NODE && n.tagName === "SPAN" && n.dataset.i18nLabel === "1") {
      n.textContent = text;
      return;
    }
  }
  const span = document.createElement("span");
  span.dataset.i18nLabel = "1";
  span.textContent = text;
  labelEl.insertBefore(span, labelEl.firstChild);
}

export function applyGithubSyncI18n() {
  const textMap = [
    ["gh-card-title", "github.title"],
    ["gh-card-hint", "github.hint"],
    ["btn-gh-register", "github.register"],
    ["btn-gh-login", "github.login"],
    ["btn-gh-logout", "github.logout"],
    ["btn-gh-bind", "github.bind"],
    ["btn-gh-unbind", "github.unbind"],
    ["gh-assignment-hint", "github.assignmentHint"],
    ["gh-repo-lock-hint", "github.classRepoLocked"],
    ["gh-token-hint", "github.tokenHint"],
  ];
  for (const [id, key] of textMap) {
    const el = $(id);
    if (el) el.textContent = t(key);
  }

  const syncBtn = $("btn-gh-sync");
  if (syncBtn) {
    const icon = syncBtn.querySelector("i")?.outerHTML || "";
    syncBtn.innerHTML = `${icon} ${t("github.sync")}`.trim();
  }
  const last = $("gh-last-commit");
  if (last && !last.classList.contains("hidden")) last.textContent = t("github.viewCommit");

  const labelKeys = [
    ["gh-student-id", "github.label.studentId"],
    ["gh-display-name", "github.label.displayName"],
    ["gh-password", "github.label.password"],
    ["gh-repo-url", "github.label.repoUrl"],
    ["gh-pat", "github.label.pat"],
    ["gh-branch", "github.label.branch"],
    ["gh-track", "github.label.track"],
    ["gh-custom-track", "github.label.customTrack"],
    ["gh-assignment", "github.label.assignment"],
    ["gh-custom-assignment", "github.label.customAsg"],
    ["gh-commit-msg", "github.label.commitMsg"],
  ];
  for (const [inputId, key] of labelKeys) {
    const input = $(inputId);
    const lab = input?.closest("label");
    if (lab) setLabelTextBeforeInput(lab, t(key));
  }
  const rdsLab = $("gh-include-rds")?.closest("label");
  if (rdsLab) {
    for (const n of rdsLab.childNodes) {
      if (n.nodeType === Node.TEXT_NODE && n.textContent.trim()) {
        n.textContent = ` ${t("github.label.includeRds")}`;
        break;
      }
    }
  }

  const ph = [
    ["gh-display-name", "github.ph.displayName"],
    ["gh-password", "github.ph.password"],
    ["gh-pat", "github.ph.pat"],
    ["gh-custom-track", "github.ph.customTrack"],
    ["gh-custom-assignment", "github.ph.customAsg"],
    ["gh-commit-msg", "github.ph.commitMsg"],
  ];
  for (const [id, key] of ph) {
    const el = $(id);
    if (el) el.placeholder = t(key);
  }

  fillTrackSelect();
  fillAssignmentSelect();
  updatePathPreview();
  renderStudentChip();
}

export async function initGithubSync() {
  const card = $("github-sync-card");
  if (!card) return;

  $("btn-gh-register")?.addEventListener("click", onRegister);
  $("btn-gh-login")?.addEventListener("click", onLogin);
  $("btn-gh-logout")?.addEventListener("click", onLogout);
  $("btn-gh-bind")?.addEventListener("click", onBind);
  $("btn-gh-unbind")?.addEventListener("click", onUnbind);
  $("btn-gh-sync")?.addEventListener("click", onSync);
  $("gh-track")?.addEventListener("change", () => {
    localStorage.setItem(LS_TRACK, $("gh-track").value);
    fillAssignmentSelect();
    updatePathPreview();
  });
  $("gh-assignment")?.addEventListener("change", () => {
    localStorage.setItem(LS_ASSIGNMENT, $("gh-assignment").value);
    updateCustomFields();
  });
  $("gh-custom-track")?.addEventListener("input", updatePathPreview);

  try {
    const data = await API.githubAssignments();
    _tracks = data.tracks || [];
  } catch (e) {
    console.warn("github assignments load failed; using builtin menus", e);
    _tracks = [];
  }
  fillTrackSelect();
  fillAssignmentSelect();

  applyGithubSyncI18n();
  prefillClassRepo(DEFAULT_CLASS_REPO);
  await refreshStatus();
  window.addEventListener("emp:locale-change", () => applyGithubSyncI18n());
  if (typeof lucide !== "undefined") lucide.createIcons();
}
