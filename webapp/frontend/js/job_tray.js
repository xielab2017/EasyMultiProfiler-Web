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
import { t, getLocale } from "./locale.js?v=nav-language-20261108";
import { request } from "./api.js?v=nav-language-20261108";
import {bindFloatingDrag} from './floating_drag.mjs';

const POLL_MS = 3000;
const ACTIVE = new Set(["queued", "running", "cancel_requested"]);
const FINISHED = new Set(["done", "error", "cancelled"]);
const DISMISS_KEY = "emp_jobtray_dismissed_v1";

let _root = null;
let _listEl = null;
let _badgeEl = null;
let _titleEl = null;
let _clearEl = null;
let _restoreEl = null;
let _open = false;
let _timer = null;
const _jobs = new Map();      // id -> latest job summary
const _prevStatus = new Map(); // id -> previous status (transition toasts)
const _dismissed = new Set();  // ids removed from the local view
let _bgHintFired = false;

function saveDismissed() {
  try { localStorage.setItem(DISMISS_KEY, JSON.stringify([..._dismissed].slice(-5000))); } catch { /* local storage may be unavailable */ }
}

function clearFinished() {
  for (const [id, job] of _jobs) {
    if (!FINISHED.has(job.status)) continue;
    _dismissed.add(id); _jobs.delete(id); _prevStatus.delete(id);
  }
  saveDismissed(); render(); schedule();
}

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
    .emp-jobtray-toolbar{display:flex;gap:6px;position:sticky;top:0;background:var(--surface,#fff);padding:4px 0 8px;z-index:1}
    .emp-jobtray-toolbar button{border:1px solid var(--border,#d0d7de);background:transparent;color:inherit;border-radius:6px;padding:4px 8px;cursor:pointer}
    .emp-jobtray-toolbar button:disabled{opacity:.5;cursor:default}
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
  const zh = ['zh','zh-TW'].includes(getLocale());
  _clearEl.textContent = zh ? '一键清理已结束任务' : 'Clear finished tasks';
  _clearEl.title = zh ? '仅隐藏已完成、失败和已取消任务；保留结果文件和运行中的任务。' : 'Hide finished tasks; preserve results and active tasks.';
  _clearEl.disabled = !jobs.some(job => FINISHED.has(job.status));
  _restoreEl.textContent = zh ? '恢复列表记录' : 'Restore hidden tasks';
  _restoreEl.disabled = !_dismissed.size;
  _root.querySelector(".emp-jobtray-panel").style.display = _open ? "block" : "none";

  if (!jobs.length) {
    _listEl.innerHTML = `<div class="emp-jobtray-empty">${esc(t("jobtray.empty"))}</div>`;
    return;
  }
  _listEl.innerHTML = jobs.map((job) => {
    const pct = Math.max(0, Math.min(100, Number(job.progress) || 0));
    const zh = ['zh','zh-TW'].includes(getLocale());
    const labels = zh ? {queued:'排队中',running:'运行中',done:'已完成',error:'失败',cancelled:'已取消',cancel_requested:'正在取消'} : {};
    const statusLabel = esc(labels[job.status] || job.status || '');
    const elapsed = Math.max(0,Number(job.elapsed_seconds)||0);
    const action = ACTIVE.has(job.status)
      ? (job.cancellable ? `<button type="button" data-act="cancel" data-id="${esc(job.id)}">${esc(t("jobtray.cancel"))}</button>` : '')
      : `${job.status === 'done' ? `<button type="button" data-act="result" data-id="${esc(job.id)}">${job._matrix?(zh?'下载矩阵':'Download matrix'):(zh ? '下载结果 JSON' : 'Download result JSON')}</button>` : ''}<button type="button" data-act="dismiss" data-id="${esc(job.id)}">×</button>`;
    const names = zh ? {alpha:'多样性分析',differential:'差异分析',dimension:'降维分析',correlation:'相关性分析',cluster:'聚类分析',marker:'标志物分析',filter:'特征过滤',normalize:'归一化',impute:'缺失值处理',rarefy:'抽平',collapse:'分类聚合',taxonomy:'16S 分类处理',three_line:'临床基线表',enrichment:'GO/KEGG 富集分析',gsea:'GSEA 分析',count_workbench:'计数分析工作台',matrix_download:'矩阵下载'} : {};
    const suffix=String(job.kind||'').split('/').at(-1);
    const label=names[suffix]||job.kind||job.id;
    return `<div class="emp-jobtray-job">
      <div class="emp-jobtray-job-head">
        <span class="emp-jobtray-kind">${esc(label)}${typeof job.experiment==='string'&&job.experiment?' · '+esc(job.experiment):''}</span>
        <span class="emp-jobtray-status">${statusLabel}</span>
      </div>
      <div class="emp-jobtray-bar"><i style="width:${pct}%"></i></div>
      ${job.message ? `<div class="emp-jobtray-msg">${esc(job.message)}</div>` : ""}
      <div class="emp-jobtray-msg">${esc(job.id)} · ${Math.floor(elapsed/60)}m ${elapsed%60}s${job.pid ? ' · PID '+esc(job.pid) : ''}</div>
      <div class="emp-jobtray-actions">${action}</div>
    </div>`;
  }).join("");
}

async function poll() {
  try {
    const j = await request('GET', '/jobs?limit=100', null, false, {skipSessionHeader:true,timeoutMs:10000});
    {
      const list = Array.isArray(j?.jobs) ? j.jobs : [];
      window.dispatchEvent(new CustomEvent('emp:jobs-updated',{detail:{jobs:list.map(job=>({id:job.id,status:job.status,progress:job.progress,message:job.message}))}}));
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
    const matrix=_jobs.get(id);if(matrix?._matrix){if(matrix.local_queue)window.empAgentPipeline?.cancelQueued(id);else await fetch('/api/public-data/matrix/cancel',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({job_id:id}),credentials:'omit'});return;}
    await request('POST', `/jobs/${encodeURIComponent(id)}/cancel`, null, false, {skipSessionHeader:true,timeoutMs:10000});
  } catch (error) { toast(error.message, 'error'); }
  poll();
}

async function downloadResult(id) {
  try {
    if(_jobs.get(id)?._matrix){const link=document.createElement('a');link.href='/api/public-data/matrix/files/'+encodeURIComponent(id);link.download=_jobs.get(id).experiment||'matrix';link.click();return;}
    const value = await request('GET', `/jobs/${encodeURIComponent(id)}/result`, null, false, {skipSessionHeader:true});
    const url = URL.createObjectURL(new Blob([JSON.stringify(value,null,2)], {type:'application/json'}));
    const link=document.createElement('a');link.href=url;link.download=`emp-task-${id}.json`;link.click();
    setTimeout(()=>URL.revokeObjectURL(url),1000);
  } catch(error) { toast(error.message, 'error'); }
}

export function initJobTray() {
  try {
    if (_root || typeof document === "undefined" || !document.body) return;
    ensureStyle();
    try { const saved=JSON.parse(localStorage.getItem(DISMISS_KEY)||'[]'); if(Array.isArray(saved))for(const id of saved)if(typeof id==='string')_dismissed.add(id); } catch { /* invalid stored view state is ignored */ }
    _root = document.createElement("div");
    _root.className = "emp-jobtray";
    _root.innerHTML = `
      <button type="button" class="emp-jobtray-toggle">
        <span class="emp-jobtray-title"></span>
        <span class="emp-jobtray-badge idle">0</span>
      </button>
      <div class="emp-jobtray-panel" style="display:none"><div class="emp-jobtray-toolbar"><button type="button" data-jobtray-clear></button><button type="button" data-jobtray-restore></button></div><div class="emp-jobtray-list"></div></div>`;
    document.body.appendChild(_root);
    _listEl = _root.querySelector(".emp-jobtray-list");
    _badgeEl = _root.querySelector(".emp-jobtray-badge");
    _titleEl = _root.querySelector(".emp-jobtray-title");
    _clearEl = _root.querySelector('[data-jobtray-clear]');
    _restoreEl = _root.querySelector('[data-jobtray-restore]');
    _clearEl.addEventListener('click',clearFinished);
    _restoreEl.addEventListener('click',()=>{_dismissed.clear();saveDismissed();render();poll();});
    _root.querySelector(".emp-jobtray-toggle").addEventListener("click", () => {
      _open = !_open;
      render();
      if (_open) poll(); else schedule();
    });
    bindFloatingDrag(_root,_root.querySelector('.emp-jobtray-toggle'));
    window.addEventListener('emp:agent-flow',event=>{const j=event.detail;if(!j.job_id)return;if(j.stage==='replaced'){_jobs.delete(j.job_id);render();return;}_jobs.set(j.job_id,{id:j.job_id,kind:'matrix_download',experiment:j.source_name||j.accession,status:j.stage==='error'?'error':j.status==='completed'?'done':j.status||'running',progress:j.total_bytes?100*(j.bytes_downloaded||0)/j.total_bytes:0,message:j.message||j.stage,cancellable:!['completed','cancelled','error'].includes(j.status),_matrix:true,local_queue:j.local_queue});render();});
    _listEl.addEventListener("click", (e) => {
      const btn = e.target.closest("button[data-act]");
      if (!btn) return;
      const id = btn.dataset.id;
      if (btn.dataset.act === "cancel") cancelJob(id);
      if (btn.dataset.act === 'result') downloadResult(id);
      if (btn.dataset.act === "dismiss") {
        _dismissed.add(id);
        saveDismissed();
        _jobs.delete(id);
        render();
        schedule();
      }
    });
    window.addEventListener("emp:locale-change", () => render());
    window.addEventListener('emp:job-submitted', () => { _open=true; poll(); });
    window.addEventListener('emp:tasks-refresh', () => { _open=true; poll(); });
    render();
    poll();
  } catch (e) {
    console.warn("[emp-jobtray] init failed", e);
  }
}
