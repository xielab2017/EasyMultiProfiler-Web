// Course GitHub sync panel: student login, repo bind, weekly / project sync.
import * as API from "./api.js?v=2026-07-21-gh-sync-v2";
import { t } from "./locale.js?v=2026-07-16-multi-demo-v2";

const LS_STUDENT_TOKEN = "emp_student_token";
const LS_TRACK = "emp_github_track";
const LS_ASSIGNMENT = "emp_github_assignment";
const LS_CUSTOM_TRACK = "emp_github_custom_track";
const LS_CUSTOM_ASG = "emp_github_custom_assignment";

let _tracks = [];
let _student = null;

function toast(msg, type = "info") {
  window.dispatchEvent(new CustomEvent("emp:toast", { detail: { msg, type } }));
}

function setLoading(on) {
  const el = document.getElementById("loading-spinner");
  if (el) el.classList.toggle("hidden", !on);
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

function currentTrack() {
  const id = $("gh-track")?.value;
  return _tracks.find((tr) => tr.id === id) || null;
}

function currentAssignment() {
  const track = currentTrack();
  const id = $("gh-assignment")?.value;
  if (!track) return null;
  return (track.assignments || []).find((a) => a.id === id) || null;
}

function updateCustomFields() {
  const track = currentTrack();
  const asg = currentAssignment();
  const trackWrap = $("gh-custom-track-wrap");
  const asgInput = $("gh-custom-assignment");
  if (trackWrap) trackWrap.classList.toggle("hidden", !(track && track.custom));
  if (asgInput) {
    const must = !!(asg && (asg.custom || asg.type === "custom" || asg.id === "assignment_custom"));
    asgInput.placeholder = must
      ? (t("github.customAsgRequired") || "必填：自定义作业标题")
      : (t("github.customAsgOptional") || "可选：覆盖默认周次/项目标题");
    asgInput.required = must;
  }
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
  sel.innerHTML = _tracks.map((tr) =>
    `<option value="${esc(tr.id)}">${esc(tr.title || tr.id)}</option>`
  ).join("");
  if (prev && [...sel.options].some((o) => o.value === prev)) sel.value = prev;
  const ct = $("gh-custom-track");
  if (ct && localStorage.getItem(LS_CUSTOM_TRACK)) ct.value = localStorage.getItem(LS_CUSTOM_TRACK);
  const ca = $("gh-custom-assignment");
  if (ca && localStorage.getItem(LS_CUSTOM_ASG)) ca.value = localStorage.getItem(LS_CUSTOM_ASG);
  fillAssignmentSelect();
}

function fillAssignmentSelect() {
  const trackSel = $("gh-track");
  const asgSel = $("gh-assignment");
  if (!trackSel || !asgSel) return;
  const track = _tracks.find((tr) => tr.id === trackSel.value);
  const list = (track && track.assignments) || [];
  const prev = localStorage.getItem(LS_ASSIGNMENT) || asgSel.value;
  asgSel.innerHTML = list.map((a) => {
    let label = a.title || a.id;
    if (a.type === "weekly" && a.week != null) label = `W${a.week} · ${a.title}`;
    else if (a.type === "project") label = `★ ${a.title}`;
    else if (a.type === "custom" || a.custom) label = `✎ ${a.title}`;
    return `<option value="${esc(a.id)}">${esc(label)}</option>`;
  }).join("");
  if (prev && [...asgSel.options].some((o) => o.value === prev)) asgSel.value = prev;
  updateCustomFields();
}

async function refreshStatus() {
  const token = localStorage.getItem(LS_STUDENT_TOKEN);
  if (!token) {
    _student = null;
    setPanelMode("auth");
    renderStudentChip();
    return;
  }
  try {
    const res = await API.githubStatus();
    _student = res.student;
    const bound = !!(res.student && res.student.github && res.student.github.bound);
    setPanelMode(bound ? "bound" : "logged_in");
    renderStudentChip();
    if ($("gh-repo-url") && bound) {
      $("gh-repo-url").value = res.student.github.html_url || "";
    }
    await refreshSyncHistory();
  } catch (e) {
    localStorage.removeItem(LS_STUDENT_TOKEN);
    _student = null;
    setPanelMode("auth");
    renderStudentChip();
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
        <span class="hint">run ${esc(s.run_id || "")} · ${esc(String(s.n_files || 0))} files</span>
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
  setLoading(true);
  try {
    const res = await API.githubRegister({ student_id, password, display_name });
    localStorage.setItem(LS_STUDENT_TOKEN, res.student_token);
    _student = res.student;
    toast(t("github.registerOk"), "success");
    setPanelMode("logged_in");
    renderStudentChip();
  } catch (e) {
    toast(e.message || String(e), "error");
  } finally {
    setLoading(false);
  }
}

async function onLogin() {
  const student_id = ($("gh-student-id")?.value || "").trim();
  const password = $("gh-password")?.value || "";
  if (!student_id || !password) {
    toast(t("github.needIdPassword"), "error");
    return;
  }
  setLoading(true);
  try {
    const res = await API.githubLogin({ student_id, password });
    localStorage.setItem(LS_STUDENT_TOKEN, res.student_token);
    _student = res.student;
    toast(t("github.loginOk"), "success");
    const bound = !!(res.student && res.student.github && res.student.github.bound);
    setPanelMode(bound ? "bound" : "logged_in");
    renderStudentChip();
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
  const repo_url = ($("gh-repo-url")?.value || "").trim();
  const github_token = ($("gh-pat")?.value || "").trim();
  const branch = ($("gh-branch")?.value || "").trim() || null;
  if (!repo_url || !github_token) {
    toast(t("github.needRepoToken"), "error");
    return;
  }
  setLoading(true);
  try {
    const res = await API.githubBind({ repo_url, github_token, branch });
    _student = res.student;
    if ($("gh-pat")) $("gh-pat").value = "";
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
  const track_id = $("gh-track")?.value;
  const assignment_id = $("gh-assignment")?.value;
  if (!track_id || !assignment_id) {
    toast(t("github.needAssignment"), "error");
    return;
  }
  const track = currentTrack();
  const asg = currentAssignment();
  const custom_track_name = ($("gh-custom-track")?.value || "").trim();
  const custom_assignment_title = ($("gh-custom-assignment")?.value || "").trim();

  if (track?.custom && !custom_track_name) {
    toast(t("github.needCustomTrack") || "请填写自定义轨道名称。", "error");
    return;
  }
  if ((asg?.custom || asg?.type === "custom" || asg?.id === "assignment_custom") && !custom_assignment_title) {
    toast(t("github.needCustomAsg") || "请填写自定义作业标题。", "error");
    return;
  }

  localStorage.setItem(LS_TRACK, track_id);
  localStorage.setItem(LS_ASSIGNMENT, assignment_id);
  if (custom_track_name) localStorage.setItem(LS_CUSTOM_TRACK, custom_track_name);
  if (custom_assignment_title) localStorage.setItem(LS_CUSTOM_ASG, custom_assignment_title);

  const commit_message = ($("gh-commit-msg")?.value || "").trim() || null;
  const include_rds = !!$("gh-include-rds")?.checked;
  const session_id = localStorage.getItem("emp_session_id") || null;
  const experiment = window._emp?.currentExp || null;

  setLoading(true);
  try {
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
    toast(res.message || t("github.syncOk"), "success");
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
    toast(e.message || String(e), "error");
  } finally {
    setLoading(false);
  }
}

export function applyGithubSyncI18n() {
  const map = [
    ["gh-card-title", "github.title"],
    ["gh-card-hint", "github.hint"],
    ["btn-gh-register", "github.register"],
    ["btn-gh-login", "github.login"],
    ["btn-gh-logout", "github.logout"],
    ["btn-gh-bind", "github.bind"],
    ["btn-gh-unbind", "github.unbind"],
    ["btn-gh-sync", "github.sync"],
  ];
  for (const [id, key] of map) {
    const el = $(id);
    if (el) el.textContent = t(key);
  }
  const hint = $("gh-assignment-hint");
  if (hint) hint.textContent = t("github.assignmentHint") || hint.textContent;
  updateCustomFields();
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
  });
  $("gh-assignment")?.addEventListener("change", () => {
    localStorage.setItem(LS_ASSIGNMENT, $("gh-assignment").value);
    updateCustomFields();
  });

  try {
    const data = await API.githubAssignments();
    _tracks = data.tracks || [];
    fillTrackSelect();
  } catch (e) {
    console.warn("github assignments load failed", e);
  }

  applyGithubSyncI18n();
  await refreshStatus();
  if (typeof lucide !== "undefined") lucide.createIcons();
}
