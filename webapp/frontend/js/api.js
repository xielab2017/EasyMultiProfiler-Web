// API client – talks to the Plumber backend.
// The base URL is resolved lazily on every request so that the value
// picked up at module-load time does not go stale if the surrounding
// page re-configures window.API_BASE (e.g. after a late reverse-proxy
// rewrite, or when a user navigates between pages of a multi-page app).
//
// Priority:
//   1. window.API_BASE  (explicit override – used in embedded deployments)
//   2. Heuristic based on window.location.port:
//      - 8080  → http://<host>:8000/api   (local dev, matches start_local.sh)
//      - 18080 → http://<host>:18000/api  (alt pairing used by some CI scripts)
//   3. Fallback: "/api" (same-origin reverse proxy)
function resolveApiBase() {
  if (typeof window !== "undefined" && window.API_BASE) return window.API_BASE;
  if (typeof window === "undefined" || !window.location) return "/api";
  const host = window.location.hostname || "127.0.0.1";
  const p = window.location.port || "";
  if (p === "8080")  return `http://${host}:8000/api`;
  if (p === "18080") return `http://${host}:18000/api`;
  return "/api";
}

function resolveApiCandidates() {
  const primary = resolveApiBase();
  if (typeof window === "undefined" || !window.location) return [primary];
  const p = window.location.port || "";
  const host = window.location.hostname || "127.0.0.1";
  const out = [primary];
  if (p === "8080") {
    out.push(`http://${host}:8000/api`, "http://127.0.0.1:8000/api", "http://localhost:8000/api");
  } else if (p === "18080") {
    out.push(`http://${host}:18000/api`, "http://127.0.0.1:18000/api", "http://localhost:18000/api");
  }
  // Keep order while deduplicating.
  return [...new Set(out)];
}
export function apiBase() { return resolveApiBase(); }
export { request };
// Backward-compatible export – a handful of call-sites read `API` as a
// string to build URLs (e.g. download links).  Keep it reactive via a
// string-wrapping object that delegates to the resolver on every call.
// Equality/concat keeps working because we define toString/Symbol.toPrimitive.
export const API = Object.freeze({
  toString:            () => resolveApiBase(),
  [Symbol.toPrimitive]: () => resolveApiBase(),
  valueOf:             () => resolveApiBase(),
});

function sessionId() {
  return localStorage.getItem("emp_session_id") || null;
}

function headers(extra = {}) {
  const h = { "Content-Type": "application/json", ...extra };
  const sid = sessionId();
  if (sid) h["X-Session-Id"] = sid;
  const token = (
    (typeof window !== "undefined" && window.EMP_API_TOKEN) ||
    (typeof localStorage !== "undefined" && localStorage.getItem("emp_api_token")) ||
    ""
  ).trim();
  if (token) h["Authorization"] = `Bearer ${token}`;
  const studentToken = (
    typeof localStorage !== "undefined" && localStorage.getItem("emp_student_token")
  ) || "";
  if (studentToken) h["X-Student-Token"] = studentToken;
  return h;
}

function normalizeApiErrorMessage(status, msg) {
  let out = msg || `HTTP ${status}`;
  if (status === 401 || /authentication required/i.test(String(out))) {
    out = "Authentication required. Reload the page so runtime_auth.local.js can attach EMP_API_TOKEN, or set localStorage emp_api_token.";
  } else if (status === 403) {
    out = `Access denied: ${out}`;
  } else if (
    status === 413 ||
    /long vectors not supported|split_by_boundary|single-shot multipart|超过.*上传上限|chunked upload/i.test(String(out))
  ) {
    out = String(out).trim() ||
      "BAM 过大，R/plumber 无法一次接收整文件。请刷新页面后重试（将自动分片），或改用服务器路径注册。";
  } else if (
    status >= 500 &&
    (/^500\b/i.test(String(out)) || /internal server error/i.test(String(out)))
  ) {
    out = `服务器错误（HTTP ${status}）。若 BAM 超过约 2GiB，请刷新页面使用分片上传。原始信息: ${out}`;
  }
  return out;
}

/** Timeout for large multipart uploads: 10 min base + 3 min / 100MB, cap 3 h. */
export function uploadTimeoutMs(fileSizeBytes) {
  const size = Math.max(0, Number(fileSizeBytes) || 0);
  const per100 = Math.ceil(size / (100 * 1024 * 1024));
  return Math.min(3 * 60 * 60 * 1000, Math.max(10 * 60 * 1000, 600_000 + per100 * 180_000));
}

/**
 * Multipart POST via XHR so we can report real upload % (fetch cannot).
 * Progress contract for callers:
 *   - upload bytes → pct 0–90
 *   - waiting for server after upload complete → pct 90–99, message 「服务器处理中…」
 *   - success → pct 100
 * Always settles the promise (resolve/reject); never leaves the caller hanging
 * without an error if XHR fails or JSON parse blows up.
 */
function requestMultipartWithProgress(path, formData, opts = {}) {
  const onProgress = typeof opts.onProgress === "function" ? opts.onProgress : null;
  const timeoutMs = Math.max(30_000, Number(opts.timeoutMs) || uploadTimeoutMs(opts.fileSizeBytes));
  const bases = resolveApiCandidates();
  const authHeaders = headers();
  delete authHeaders["Content-Type"]; // browser sets multipart boundary
  const t0 = (typeof performance !== "undefined" ? performance.now() : Date.now());

  const emit = (pct, message, phase) => {
    if (!onProgress) return;
    try { onProgress({ pct, message: message || "", phase: phase || "" }); }
    catch (_) { /* ignore UI callback errors */ }
  };

  const tryOne = (base) => new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    let settled = false;
    let waitTimer = null;
    let waitPct = 90;

    const cleanup = () => {
      if (waitTimer) { clearInterval(waitTimer); waitTimer = null; }
    };
    const fail = (err) => {
      if (settled) return;
      settled = true;
      cleanup();
      reject(err instanceof Error ? err : new Error(String(err || "Upload failed")));
    };
    const ok = (data) => {
      if (settled) return;
      settled = true;
      cleanup();
      resolve(data);
    };

    xhr.open("POST", `${base}${path}`, true);
    xhr.timeout = timeoutMs;
    for (const [k, v] of Object.entries(authHeaders)) {
      if (v != null && v !== "") xhr.setRequestHeader(k, String(v));
    }

    xhr.upload.onprogress = (ev) => {
      if (!ev.lengthComputable || !ev.total) {
        emit(Math.min(88, waitPct), "Uploading…", "upload");
        return;
      }
      const frac = Math.max(0, Math.min(1, ev.loaded / ev.total));
      emit(Math.round(frac * 90), `Uploading… ${Math.round(frac * 100)}%`, "upload");
    };
    xhr.upload.onload = () => {
      waitPct = 90;
      emit(90, "服务器处理中…", "processing");
      // Soft climb 90→99 while the server copies/registers the BAM.
      waitTimer = setInterval(() => {
        waitPct = Math.min(99, waitPct + 0.35);
        emit(waitPct, "服务器处理中…", "processing");
      }, 400);
    };

    xhr.onerror = () => fail(new Error(`Network error uploading to ${base}`));
    xhr.ontimeout = () => fail(new Error(
      `Upload timed out after ${Math.round(timeoutMs / 60000)} min. Try a smaller file, check disk space, or use server-path register instead of browser upload.`
    ));
    xhr.onabort = () => fail(new Error("Upload aborted"));

    xhr.onload = () => {
      cleanup();
      const totalMs = Math.round(
        ((typeof performance !== "undefined" ? performance.now() : Date.now()) - t0)
      );
      const status = xhr.status;
      const raw = xhr.responseText || "";
      let data = null;
      try {
        data = raw ? JSON.parse(raw) : null;
      } catch (parseErr) {
        const snippet = String(raw).replace(/\s+/g, " ").slice(0, 240);
        if (status >= 200 && status < 300) {
          fail(new Error(
            `Server returned non-JSON response (HTTP ${status}). ${String(parseErr.message || parseErr)} ${snippet}`
          ));
          return;
        }
        fail(new Error(normalizeApiErrorMessage(
          status,
          snippet ? `HTTP ${status}: ${snippet}` : `HTTP ${status}`
        )));
        return;
      }
      if (status < 200 || status >= 300 || (data && data.success === false)) {
        const msg = normalizeApiErrorMessage(
          status,
          (data && (data.error || data.message)) || (raw ? raw.slice(0, 240) : `HTTP ${status}`)
        );
        const err = new Error(msg);
        err.total_ms = totalMs;
        if (data && data.backend_ms != null) err.backend_ms = data.backend_ms;
        fail(err);
        return;
      }
      if (!data || typeof data !== "object") data = { success: true };
      data._total_ms = totalMs;
      emit(100, "Done", "done");
      try {
        window.dispatchEvent(new CustomEvent("emp:timing", {
          detail: { path, method: "POST", total_ms: totalMs,
                    backend_ms: data.backend_ms, ok: true },
        }));
      } catch (_) { /* no-op */ }
      ok(data);
    };

    try {
      xhr.send(formData);
    } catch (e) {
      fail(e);
    }
  });

  return (async () => {
    let lastErr = null;
    for (const base of bases) {
      try {
        return await tryOne(base);
      } catch (e) {
        lastErr = e;
        // Only retry other candidates on network / reachability failures.
        const msg = String(e && e.message || e);
        if (!/Network error|Failed to fetch|Cannot reach|timed out/i.test(msg)) throw e;
      }
    }
    const tried = bases.join(", ");
    throw lastErr || new Error(
      `Cannot reach EMP API (${tried}). Start the backend with: bash webapp/scripts/start_local.sh`
    );
  })();
}

async function request(method, path, body = null, multipart = false, optsExtra = {}) {
  const authHeaders = headers();
  if (multipart) {
    // Let the browser set multipart boundary; keep auth + session headers.
    delete authHeaders["Content-Type"];
  }
  const opts = { method, headers: authHeaders };
  if (body && !multipart) opts.body = JSON.stringify(body);
  if (body && multipart) opts.body = body; // FormData

  const timeoutMs = Number(optsExtra.timeoutMs);
  let abortTimer = null;
  if (Number.isFinite(timeoutMs) && timeoutMs > 0 && typeof AbortController !== "undefined") {
    const ac = new AbortController();
    opts.signal = ac.signal;
    abortTimer = setTimeout(() => ac.abort(), timeoutMs);
  }

  const bases = resolveApiCandidates();
  const t0 = (typeof performance !== "undefined" ? performance.now() : Date.now());
  let res = null;
  let lastErr = null;
  try {
    for (const base of bases) {
      try {
        res = await fetch(`${base}${path}`, opts);
        break;
      } catch (e) {
        lastErr = e;
        if (e && (e.name === "AbortError" || /aborted/i.test(String(e.message || e)))) {
          throw new Error(
            `Request timed out after ${Math.round(timeoutMs / 60000)} min (${path}). ` +
            "Large BAM MACS/annotate jobs can take longer — retry, or check api.log / macs_callpeak.err.log."
          );
        }
      }
    }
  } finally {
    if (abortTimer) clearTimeout(abortTimer);
  }
  if (!res) {
    const tried = bases.join(", ");
    throw new Error(
      `Cannot reach EMP API (${tried}). Start the backend with: bash webapp/scripts/start_local.sh`
    );
  }
  const totalMs = ((typeof performance !== "undefined" ? performance.now() : Date.now()) - t0);
  const ct = res.headers.get("content-type") || "";

  if (ct.includes("application/json")) {
    let data;
    try {
      data = await res.json();
    } catch (parseErr) {
      const err = new Error(`Server returned invalid JSON (HTTP ${res.status}). ${String(parseErr.message || parseErr)}`);
      err.total_ms = Math.round(totalMs);
      throw err;
    }
    if (!res.ok || data.success === false) {
      const msg = normalizeApiErrorMessage(
        res.status,
        data.error || data.message || `HTTP ${res.status}`
      );
      const err = new Error(msg);
      err.total_ms = Math.round(totalMs);
      err.backend_ms = data.backend_ms;
      throw err;
    }
    data._total_ms = Math.round(totalMs);
    // Emit a lightweight timing event so app.js can surface it.
    try {
      window.dispatchEvent(new CustomEvent("emp:timing", {
        detail: { path, method, total_ms: data._total_ms,
                  backend_ms: data.backend_ms, ok: true }
      }));
    } catch (_) { /* no-op */ }
    return data;
  }

  if (!res.ok) {
    const err = new Error(`HTTP ${res.status}`);
    err.total_ms = Math.round(totalMs);
    throw err;
  }
  return res;
}

// ── SESSION ───────────────────────────────────────
export async function getWorkflows() {
  const data = await request("GET", "/workflows");
  return data.workflows || [];
}

export async function getWorkflow(workflowId) {
  const data = await request("GET", `/workflows/${encodeURIComponent(workflowId)}`);
  return data.workflow;
}

export async function createSession() {
  const data = await request("POST", "/session");
  localStorage.setItem("emp_session_id", data.session_id);
  return data.session_id;
}

export async function deleteSession() {
  const sid = sessionId();
  if (!sid) return { success: true };
  const data = await request("DELETE", `/session/${encodeURIComponent(sid)}`);
  localStorage.removeItem("emp_session_id");
  return data;
}

// ── USER R (local learning; runs on Plumber host — trusted use only) ──
// POST /api/user_r/run (legacy: /api/exec/user_r)
export async function execUserR(params = {}) {
  if (!sessionId()) await createSession();
  return request("POST", "/user_r/run", {
    session_id: sessionId(),
    experiment: params.experiment ?? null,
    code:       params.code ?? "",
    width:      params.width,
    height:     params.height,
    workflow:   params.workflow ?? null,
    tab:        params.tab ?? null,
    label:      params.label ?? null,
    source_code: params.source_code ?? null,
  });
}

export function codeLabArtifactURL(artifactName) {
  const sid = sessionId();
  return `${resolveApiBase()}/code_lab/artifacts/${encodeURIComponent(sid)}/${encodeURIComponent(artifactName)}`;
}

// ── LLM CODE OPTIMIZATION (Code Lab) ─────────────────────
export async function optimizeRCode(params = {}) {
  return request("POST", "/llm/optimize_r", {
    provider:    params.provider ?? "chatgpt",
    config:      params.config ?? {},
    workflow:    params.workflow ?? null,
    tab:         params.tab ?? null,
    source_code: params.source_code ?? params.code ?? "",
    external_code: params.external_code ?? params.optimized_code ?? params.candidate_code ?? null,
    instruction: params.instruction ?? "",
    ui_context:  params.ui_context ?? null,
  });
}

export async function getOpenRouterVerified() {
  return request("GET", "/llm/openrouter_verified");
}

export async function probeOpenRouterModels(params = {}) {
  return request("POST", "/llm/probe_openrouter", {
    config: params.config ?? {},
    models: params.models ?? null,
    write_manifest: params.write_manifest ?? true,
  });
}

// AI copilot: interpret an analysis result and suggest next steps. Reuses the
// Code Lab LLM config if the student configured one; otherwise the backend
// falls back to a deterministic offline interpretation.
import { getLocale } from "./locale.js?v=2026-07-16-multi-demo";

export async function aiInterpret(context = {}, opts = {}) {
  let provider = opts.provider ?? null;
  let config = opts.config ?? null;
  if (!provider || !config) {
    try {
      const stored = JSON.parse(localStorage.getItem("emp_code_lab_llm_config_v1") || "null");
      if (stored && typeof stored === "object") {
        config = config ?? stored;
        provider = provider ?? stored.provider ?? null;
      }
    } catch { /* ignore malformed config */ }
  }
  const locale = context.locale ?? context.lang ?? opts.locale ?? getLocale();
  return request("POST", "/ai/interpret", {
    context: { ...context, locale, lang: locale },
    locale,
    user_id: opts.user_id ?? getEvolutionUserId(),
    session_id: sessionId(),
    provider: provider ?? "campus",
    config: config ?? {},
  });
}

function getEvolutionUserId() {
  try {
    let id = localStorage.getItem("emp_evolution_user_id");
    if (!id) {
      id = typeof crypto !== "undefined" && crypto.randomUUID
        ? crypto.randomUUID()
        : `u_${Date.now().toString(36)}`;
      localStorage.setItem("emp_evolution_user_id", id);
    }
    return id;
  } catch {
    return "anonymous";
  }
}

export async function evolutionEvent(body = {}) {
  return request("POST", "/evolution/event", {
    user_id: body.user_id ?? getEvolutionUserId(),
    session_id: body.session_id ?? sessionId(),
    event_type: body.event_type ?? body.type ?? "generic",
    payload: body.payload ?? body,
  });
}

export async function evolutionProfile(userId = null) {
  const uid = userId ?? getEvolutionUserId();
  return request("GET", `/evolution/profile?user_id=${encodeURIComponent(uid)}`);
}

export async function listExperiments() {
  const sid = sessionId();
  if (!sid) return [];
  const data = await request("GET", `/session/${sid}/experiments`);
  return data.experiments || [];
}

// ── IMPORT ────────────────────────────────────────
/** Cache a pre-computed DE / marker CSV as session diff_raw_<experiment>.rds */
export async function importDiffRaw(formData) {
  if (!sessionId()) await createSession();
  const sid = sessionId();
  const body = new FormData();
  let sawSession = false;
  for (const [key, value] of formData.entries()) {
    if (key === "session_id") sawSession = true;
    if (value instanceof File) {
      body.append(
        key,
        new File([value], value.name || "diff.csv", {
          type: "application/octet-stream",
          lastModified: value.lastModified,
        })
      );
    } else {
      body.append(key, value);
    }
  }
  if (!sawSession && sid) body.append("session_id", sid);
  return request("POST", "/import/diff_raw", body, true);
}

export async function importData(formData) {
  if (!sessionId()) await createSession();
  const sid = sessionId();

  // Normalize file parts to application/octet-stream. Some browsers/Windows
  // stacks send text/csv or an empty Content-Type, which older Plumber
  // multipart configs failed to unwrap into uploadable bytes.
  // Must go through request() so Bearer / X-Session-Id / API fallbacks apply
  // (legacy raw fetch caused "Failed to fetch" / 401 on LAN auth builds).
  const body = new FormData();
  let sawSession = false;
  for (const [key, value] of formData.entries()) {
    if (key === "session_id") sawSession = true;
    if (value instanceof File) {
      body.append(
        key,
        new File([value], value.name || "upload.bin", {
          type: "application/octet-stream",
          lastModified: value.lastModified,
        })
      );
    } else {
      body.append(key, value);
    }
  }
  if (!sawSession && sid) body.append("session_id", sid);

  return request("POST", "/import", body, true);
}

export async function listDemoDatasets() {
  const data = await request("GET", "/demo_datasets");
  return data.datasets || [];
}

export async function importDemoDataset(datasetId, experimentName = null) {
  const sid = sessionId();
  if (!sid) await createSession();
  const body = { session_id: sessionId(), dataset_id: datasetId };
  if (experimentName) body.experiment_name = experimentName;
  return request("POST", "/import/demo", body);
}

export async function previewFile(formData) {
  return request("POST", "/preview", formData, true);
}

// ── SUMMARY ───────────────────────────────────────
export async function getSummary(experiment) {
  const sid = sessionId();
  return request("GET", `/summary/${sid}/${encodeURIComponent(experiment)}`);
}

export async function getColdata(experiment) {
  const sid = sessionId();
  return request("GET", `/coldata/${sid}/${encodeURIComponent(experiment)}`);
}

export async function getFeatures(experiment, { limit = 0, offset = 0, q = "" } = {}) {
  const sid = sessionId();
  const qs = new URLSearchParams();
  if (limit > 0) qs.set("limit", String(limit));
  if (offset > 0) qs.set("offset", String(offset));
  if (q) qs.set("q", q);
  const suffix = qs.toString() ? `?${qs}` : "";
  return request("GET", `/features/${sid}/${encodeURIComponent(experiment)}${suffix}`);
}

export async function inspectOverview(experiment) {
  const sid = sessionId();
  return request("GET", `/inspect/${sid}/${encodeURIComponent(experiment)}`);
}

export async function inspectAssay(experiment, offset = 1, limit = 20) {
  const sid = sessionId();
  return request("GET", `/inspect/assay/${sid}/${encodeURIComponent(experiment)}?offset=${offset}&limit=${limit}`);
}

export async function inspectColdata(experiment) {
  const sid = sessionId();
  return request("GET", `/inspect/coldata/${sid}/${encodeURIComponent(experiment)}`);
}

export async function inspectRowdata(experiment, offset = 1, limit = 50) {
  const sid = sessionId();
  return request("GET", `/inspect/rowdata/${sid}/${encodeURIComponent(experiment)}?offset=${offset}&limit=${limit}`);
}

export async function inspectResults(experiment) {
  const sid = sessionId();
  return request("GET", `/inspect/results/${sid}/${encodeURIComponent(experiment)}`);
}

export async function inspectResult(experiment, resultName) {
  const sid = sessionId();
  return request("GET", `/inspect/result/${sid}/${encodeURIComponent(experiment)}/${encodeURIComponent(resultName)}`);
}

// ── PREPARATION ───────────────────────────────────
export async function filterData(experiment, params) {
  const sid = sessionId();
  return request("POST", "/prepare/filter", { session_id: sid, experiment, ...params });
}

export async function normalizeData(experiment, methodOrParams) {
  const sid = sessionId();
  const body = (methodOrParams && typeof methodOrParams === "object")
    ? { session_id: sid, experiment, ...methodOrParams }
    : { session_id: sid, experiment, method: methodOrParams };
  return request("POST", "/prepare/normalize", body);
}

export async function imputeData(experiment, methodOrParams) {
  const sid = sessionId();
  const body = (methodOrParams && typeof methodOrParams === "object")
    ? { session_id: sid, experiment, ...methodOrParams }
    : { session_id: sid, experiment, method: methodOrParams };
  return request("POST", "/prepare/impute", body);
}

export async function rarefyData(experiment, sampleSizeOrParams) {
  const sid = sessionId();
  const body = (sampleSizeOrParams && typeof sampleSizeOrParams === "object")
    ? { session_id: sid, experiment, ...sampleSizeOrParams }
    : { session_id: sid, experiment, sample_size: sampleSizeOrParams };
  return request("POST", "/prepare/rarefy", body);
}

export async function collapseData(experiment, taxaLevelOrParams) {
  const sid = sessionId();
  const body = (taxaLevelOrParams && typeof taxaLevelOrParams === "object")
    ? { session_id: sid, experiment, ...taxaLevelOrParams }
    : { session_id: sid, experiment, taxa_level: taxaLevelOrParams };
  return request("POST", "/prepare/collapse", body);
}

export async function listPrepareSnapshots(experiment) {
  const sid = sessionId();
  return request("GET", `/prepare/snapshots/${encodeURIComponent(sid)}/${encodeURIComponent(experiment)}`);
}

export async function usePrepareSnapshot(experiment, snapshot_id) {
  const sid = sessionId();
  return request("POST", "/prepare/use_snapshot", { session_id: sid, experiment, snapshot_id });
}

// ── ANALYSIS ──────────────────────────────────────
export async function analyzeAlpha(experiment, method, source = "current") {
  const sid = sessionId();
  return request("POST", "/analyze/alpha", { session_id: sid, experiment, method, source });
}

export async function analyzeDiff(experiment, method, group_var, ref_group, test_group, opts = {}) {
  const sid = sessionId();
  return request("POST", "/analyze/differential",
    { session_id: sid, experiment, method, group_var, ref_group, test_group, ...opts });
}

export async function analyzeDiffAsync(experiment, method, group_var, ref_group, test_group, opts = {}) {
  const sid = sessionId();
  return request("POST", "/analyze/differential/async",
    { session_id: sid, experiment, method, group_var, ref_group, test_group, ...opts });
}

export async function getJobStatus(jobId) {
  return request("GET", `/jobs/${encodeURIComponent(jobId)}`);
}

export async function getJobResult(jobId) {
  return request("GET", `/jobs/${encodeURIComponent(jobId)}/result`);
}

// ────────────────────────────────────────────────────────────────
//  One-click pipelines (Run All)
// ────────────────────────────────────────────────────────────────

export async function runAllRnaseq(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/rnaseq/run_all", { session_id: sid, experiment, ...params });
}

export async function runAllM16s(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/microbiome_16s/run_all", { session_id: sid, experiment, ...params });
}

export async function listBundles() {
  const sid = sessionId();
  return request("GET", `/bundles/${encodeURIComponent(sid)}`);
}

export function bundleDownloadUrl(name) {
  const sid = sessionId();
  return `${resolveApiBase()}/bundles/${encodeURIComponent(sid)}/${encodeURIComponent(name)}`;
}

export async function pollJobUntilDone(jobId, onProgress = null, intervalMs = 700, timeoutMs = 600000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const st = await getJobStatus(jobId);
    const job = st.job || {};
    if (onProgress) {
      try { onProgress(job); } catch (_) { /* no-op */ }
    }
    if (job.status === "done")  return { job, result: await getJobResult(jobId) };
    if (job.status === "error") throw new Error(job.error || "Job failed");
    await new Promise(r => setTimeout(r, intervalMs));
  }
  throw new Error("Job timed out");
}

export async function analyzeDimension(experiment, method) {
  const sid = sessionId();
  return request("POST", "/analyze/dimension", { session_id: sid, experiment, method });
}

export async function analyzeCorrelation(experiment, use) {
  const sid = sessionId();
  return request("POST", "/analyze/correlation", { session_id: sid, experiment, use });
}

export async function analyzeCluster(experiment, method, k) {
  const sid = sessionId();
  return request("POST", "/analyze/cluster", { session_id: sid, experiment, method, k });
}

export async function analyzeMarker(experiment, method, group_var, ref_group = null, test_group = null) {
  const sid = sessionId();
  return request("POST", "/analyze/marker", { session_id: sid, experiment, method, group_var, ref_group, test_group });
}

export async function analyzeEnrichment(experiment, database, organism, opts = {}) {
  const sid = sessionId();
  return request("POST", "/analyze/enrichment", {
    session_id: sid,
    experiment,
    database,
    organism,
    fc_cutoff: opts.fcCutoff ?? 1.0,
    p_cutoff:  opts.pCutoff  ?? 0.05,
    use_padj:  opts.usePadj  ?? true,
    direction: opts.direction ?? "both",
    top_n:     opts.topN      ?? 20,
  });
}

// Submit enrichment as a background job so the UI can show a progress bar
// through the same polling mechanism used by "Run All".
export async function analyzeEnrichmentAsync(experiment, database, organism, opts = {}) {
  const sid = sessionId();
  return request("POST", "/analyze/enrichment/async", {
    session_id: sid,
    experiment,
    database,
    organism,
    fc_cutoff: opts.fcCutoff ?? 1.0,
    p_cutoff:  opts.pCutoff  ?? 0.05,
    use_padj:  opts.usePadj  ?? true,
    direction: opts.direction ?? "both",
    top_n:     opts.topN      ?? 20,
  });
}

// Retrieve the list of known enrichment species plus which OrgDb packages
// are already installed on the backend.  Used to build the dropdown.
export async function listEnrichmentSpecies() {
  return request("GET", "/enrichment/species");
}

// Trigger a server-side BiocManager::install() for a missing OrgDb.  Returns
// a job_id that the frontend polls with its usual progress bar.
export async function installOrgDb(orgdb) {
  return request("POST", "/enrichment/install", { orgdb });
}

export async function vizDegHeatmap(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/visualize/deg_heatmap", { session_id: sid, experiment, ...params });
}

export async function getDiffRaw(experiment) {
  const sid = sessionId();
  return request("GET", `/analyze/diff_raw/${sid}/${encodeURIComponent(experiment)}`);
}

export async function analyzeNetwork(experiment, method, cutoff) {
  const sid = sessionId();
  return request("POST", "/analyze/network", { session_id: sid, experiment, method, cutoff });
}

// ── VISUALIZATION ─────────────────────────────────
export async function vizBarplot(experiment, params) {
  const sid = sessionId();
  return request("POST", "/visualize/barplot", { session_id: sid, experiment, ...params });
}

export async function vizBoxplot(experiment, params) {
  const sid = sessionId();
  return request("POST", "/visualize/boxplot", { session_id: sid, experiment, ...params });
}

export async function vizHeatmap(experiment, params) {
  const sid = sessionId();
  return request("POST", "/visualize/heatmap", { session_id: sid, experiment, ...params });
}

export async function vizVolcano(experiment, params) {
  const sid = sessionId();
  return request("POST", "/visualize/volcano", { session_id: sid, experiment, ...params });
}

export async function vizScatter(experiment, params) {
  const sid = sessionId();
  return request("POST", "/visualize/scatter", { session_id: sid, experiment, ...params });
}

export async function vizStructure(experiment, params) {
  const sid = sessionId();
  return request("POST", "/visualize/structure", { session_id: sid, experiment, ...params });
}

export async function vizAlpha(experiment, params) {
  const sid = sessionId();
  return request("POST", "/visualize/alpha", { session_id: sid, experiment, ...params });
}

// ── CLINICAL & PHENOTYPE ──────────────────────────
// List numeric (+ categorical, informational only) colData columns so the
// Clinical & Phenotype page can populate its dropdowns.
export async function clinicalVars(experiment) {
  const sid = sessionId();
  return request("GET",
    `/clinical/vars/${encodeURIComponent(sid)}/${encodeURIComponent(experiment)}`);
}

export async function clinicalVarsStandalone() {
  const sid = sessionId();
  return request("GET", `/clinical/vars_standalone/${encodeURIComponent(sid)}`);
}

export async function clinicalThreeLine(params = {}) {
  const sid = sessionId();
  return request("POST", "/clinical/three_line", { session_id: sid, ...params });
}

export async function clinicalSystematicSummary(params = {}) {
  const sid = sessionId();
  return request("POST", "/clinical/systematic_summary", { session_id: sid, ...params });
}

export async function clinicalReorient(mode = "auto") {
  const sid = sessionId();
  return request("POST", "/clinical/reorient", { session_id: sid, mode });
}

export async function clinicalMultiomicsJoint(params = {}) {
  const sid = sessionId();
  return request("POST", "/clinical/multiomics_joint", { session_id: sid, ...params });
}

export async function clinicalMarkerModel(params = {}) {
  const sid = sessionId();
  return request("POST", "/clinical/marker_model", { session_id: sid, ...params });
}

// Feature × Trait correlation (synchronous – usually < 5 s).
// `params` = { traits: [..], method, top_n_features, p_adjust }
export async function clinicalCor(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/clinical/cor",
    { session_id: sid, experiment, ...params });
}

// Scatter + regression line for ONE feature vs ONE numeric trait.
// `params` = { feature, trait, group, method, log_y }
export async function clinicalFitline(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/clinical/fitline",
    { session_id: sid, experiment, ...params });
}

// WGCNA module–trait correlation (async: 1–5 min on bulk RNAseq).
// Returns `{ success, job_id, kind }`.  Poll with the usual progress helper.
export async function clinicalWgcnaAsync(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/clinical/wgcna/async",
    { session_id: sid, experiment, ...params });
}

// ── WORKFLOW: METABOLOMICS ────────────────────────
export async function mbxProfile(experiment) {
  const sid = sessionId();
  return request("POST", "/workflows/metabolomics/profile", { session_id: sid, experiment });
}

export async function mbxPreprocess(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/metabolomics/preprocess", { session_id: sid, experiment, ...params });
}

export async function mbxAnalyzeDiff(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/metabolomics/analyze/differential", { session_id: sid, experiment, ...params });
}

export async function mbxVizVolcano(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/metabolomics/visualize/volcano", { session_id: sid, experiment, ...params });
}

// ── WORKFLOW: MICROBIOME 16S ──────────────────────
export async function m16sProfile(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/microbiome_16s/profile", { session_id: sid, experiment, ...params });
}
export async function m16sValidate(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/microbiome_16s/validate", { session_id: sid, experiment, ...params });
}

export async function m16sPrepareTaxonomy(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/microbiome_16s/prepare/taxonomy", { session_id: sid, experiment, ...params });
}

export async function m16sVizSankey(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/microbiome_16s/visualize/sankey", { session_id: sid, experiment, ...params });
}

export async function m16sVizNetwork(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/microbiome_16s/visualize/network", { session_id: sid, experiment, ...params });
}

// ── METAGENOMICS WORKFLOW ─────────────────────────
export async function mgxProfile(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/metagenomics/profile", { session_id: sid, experiment, ...params });
}
export async function mgxValidate(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/metagenomics/validate", { session_id: sid, experiment, ...params });
}

export async function mgxPreprocess(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/metagenomics/preprocess", { session_id: sid, experiment, ...params });
}

export async function mgxAnalyzeDifferential(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/metagenomics/analyze/differential", { session_id: sid, experiment, ...params });
}

export async function mgxAnalyzeEnrichment(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/metagenomics/analyze/enrichment", { session_id: sid, experiment, ...params });
}

export async function mgxVizHeatmap(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/metagenomics/visualize/heatmap", { session_id: sid, experiment, ...params });
}

export async function mgxVizVolcano(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/metagenomics/visualize/volcano", { session_id: sid, experiment, ...params });
}

export function mgxExportResultURL(experiment) {
  const sid = sessionId();
  return `${API}/workflows/metagenomics/export/result/${sid}/${encodeURIComponent(experiment)}`;
}

// ── TRANSCRIPTOMICS WORKFLOW ───────────────────────
export async function txProfile(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/transcriptomics/profile", { session_id: sid, experiment, ...params });
}
export async function txValidate(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/transcriptomics/validate", { session_id: sid, experiment, ...params });
}

export async function txAnalyzeDifferential(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/transcriptomics/analyze/differential", { session_id: sid, experiment, ...params });
}

export async function txAnalyzeGsea(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/transcriptomics/analyze/gsea", { session_id: sid, experiment, ...params });
}

export async function txAnalyzeWgcna(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/transcriptomics/analyze/wgcna", { session_id: sid, experiment, ...params });
}

export async function txVizHeatmap(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/transcriptomics/visualize/heatmap", { session_id: sid, experiment, ...params });
}

export async function txVizVolcano(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/transcriptomics/visualize/volcano", { session_id: sid, experiment, ...params });
}

// ── CHIP-SEQ WORKFLOW ───────────────────────────────
export async function chipProfile(experiment = null, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/chipseq/profile", { session_id: sid, experiment, ...params });
}

export async function chipValidate(experiment = null, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/chipseq/validate", { session_id: sid, experiment, ...params });
}

export async function chipCallPeaks(params = {}) {
  const sid = sessionId();
  // Match nginx/gateway 7200s; large treatment+control BAMs can take tens of minutes.
  return request("POST", "/workflows/chipseq/analyze/peaks", { session_id: sid, ...params }, false, {
    timeoutMs: 2 * 60 * 60 * 1000,
  });
}

export async function chipAnnotate(params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/chipseq/analyze/annotation", { session_id: sid, ...params }, false, {
    timeoutMs: 60 * 60 * 1000,
  });
}

export async function chipCrossOmics(params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/chipseq/analyze/cross_omics", { session_id: sid, ...params }, false, {
    timeoutMs: 60 * 60 * 1000,
  });
}

/** Normalize upload File parts so Plumber multipart reliably unwraps bytes. */
function asOctetStreamFile(file, fallbackName = "upload.bin") {
  if (!(file instanceof File) && !(file instanceof Blob)) return file;
  const name = (file instanceof File && file.name) ? file.name : fallbackName;
  return new File([file], name, {
    type: "application/octet-stream",
    lastModified: file instanceof File ? file.lastModified : Date.now(),
  });
}

export async function chipUploadPeaks(file, genome = "hs", preset = "chipseq_tf") {
  if (!sessionId()) await createSession();
  const sid = sessionId();
  const fd = new FormData();
  fd.append("session_id", sid || "");
  fd.append("peak_file", asOctetStreamFile(file, "peaks.bed"));
  fd.append("genome", genome);
  fd.append("preset", preset);
  return request("POST", "/workflows/chipseq/peaks/upload", fd, true);
}

export async function chipListPeaks() {
  const sid = sessionId();
  if (!sid) return { success: true, peak_files: [], active_peak_id: "", last_peaks: null };
  return request("GET", `/workflows/chipseq/peaks/list?session_id=${encodeURIComponent(sid)}`);
}

export async function chipSelectPeak({ peak_id = null, peak_file = null } = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/chipseq/peaks/select", {
    session_id: sid,
    peak_id,
    peak_file,
  });
}

export async function chipListBams() {
  const sid = sessionId();
  if (!sid) return { files: [], n_treatment: 0, n_control: 0 };
  return request("GET", `/workflows/chipseq/bams/list?session_id=${encodeURIComponent(sid || "")}`);
}

export async function chipUploadBam(file, group = "t", onProgress = null) {
  // Same auth/session path as importData — missing session previously caused silent/401 failures.
  if (!sessionId()) await createSession();
  const sid = sessionId();
  const size = (file && typeof file.size === "number") ? file.size : 0;
  // R/plumber multipart cannot parse bodies ≳2GiB ("long vectors not supported").
  // Chunk anytime the file is large enough to risk memory/parser failure.
  const CHUNK = 32 * 1024 * 1024; // 32 MiB
  const SINGLESHOT_MAX = 1500 * 1024 * 1024; // 1.5 GiB soft cap
  if (size > SINGLESHOT_MAX || size > CHUNK * 2) {
    return chipUploadBamChunked(file, group, onProgress, CHUNK);
  }
  const fd = new FormData();
  fd.append("bam_file", asOctetStreamFile(file, "alignment.bam"));
  fd.append("session_id", sid || "");
  fd.append("group", group);
  return requestMultipartWithProgress("/workflows/chipseq/bams/upload", fd, {
    onProgress,
    fileSizeBytes: size,
    timeoutMs: uploadTimeoutMs(size),
  });
}

async function chipUploadBamChunked(file, group = "t", onProgress = null, chunkSize = 32 * 1024 * 1024) {
  const sid = sessionId();
  const size = file.size || 0;
  const name = (file && file.name) ? file.name : "alignment.bam";
  const emit = (pct, message, phase) => {
    if (!onProgress) return;
    try { onProgress({ pct, message: message || "", phase: phase || "" }); }
    catch (_) { /* ignore */ }
  };
  emit(1, "初始化分片上传…", "init");
  const init = await request("POST", "/workflows/chipseq/bams/upload_init", {
    session_id: sid,
    filename: name,
    group,
    total_bytes: size,
  });
  if (init && init.session_id) {
    try { localStorage.setItem("emp_session_id", init.session_id); } catch (_) { /* ignore */ }
  }
  const uploadId = init && init.upload_id;
  if (!uploadId) throw new Error("分片上传初始化失败（无 upload_id）。");

  const totalChunks = Math.max(1, Math.ceil(size / chunkSize));
  let offset = 0;
  for (let i = 0; i < totalChunks; i++) {
    const end = Math.min(size, offset + chunkSize);
    const blob = file.slice(offset, end);
    const fd = new FormData();
    fd.append("chunk", new File([blob], `${name}.part${i}`, { type: "application/octet-stream" }));
    fd.append("session_id", sid || "");
    fd.append("upload_id", uploadId);
    fd.append("chunk_index", String(i));
    // Map chunk bytes to 2–90%; leave 90–99 for finalize.
    const basePct = 2 + Math.round((i / totalChunks) * 88);
    await requestMultipartWithProgress("/workflows/chipseq/bams/upload_chunk", fd, {
      fileSizeBytes: end - offset,
      timeoutMs: uploadTimeoutMs(end - offset),
      onProgress: (p) => {
        const local = Math.max(0, Math.min(1, (p?.pct || 0) / 90));
        const pct = Math.min(90, basePct + Math.round(local * (88 / totalChunks)));
        emit(pct, `分片上传 ${i + 1}/${totalChunks}…`, "upload");
      },
    });
    offset = end;
    emit(Math.min(90, 2 + Math.round(((i + 1) / totalChunks) * 88)), `分片 ${i + 1}/${totalChunks} 完成`, "upload");
  }

  emit(92, "服务器合并分片…", "processing");
  const done = await request("POST", "/workflows/chipseq/bams/upload_complete", {
    session_id: sid,
    upload_id: uploadId,
  });
  emit(100, "Done", "done");
  return done;
}

export async function chipRegisterBams(entries) {
  const sid = sessionId();
  return request("POST", "/workflows/chipseq/bams/register", { session_id: sid, entries });
}

export async function chipScanFolder(folderPath, defaultGroup = "t") {
  const sid = sessionId();
  return request("POST", "/workflows/chipseq/bams/scan_folder", {
    session_id: sid, folder_path: folderPath, default_group: defaultGroup,
  });
}

export async function chipSetBamGroup(fileId, group) {
  const sid = sessionId();
  return request("POST", "/workflows/chipseq/bams/set_group", { session_id: sid, file_id: fileId, group });
}

export async function chipAnnotateFull(params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/chipseq/analyze/annotation_full", { session_id: sid, ...params }, false, {
    timeoutMs: 60 * 60 * 1000,
  });
}

export async function chipRnaseqCoanalysis(params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/chipseq/analyze/rnaseq_coanalysis", { session_id: sid, ...params }, false, {
    timeoutMs: 60 * 60 * 1000,
  });
}

export async function chipMicrobiomeCoanalysis(params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/chipseq/analyze/microbiome_coanalysis", { session_id: sid, ...params }, false, {
    timeoutMs: 60 * 60 * 1000,
  });
}

export async function chipMetabolomicsCoanalysis(params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/chipseq/analyze/metabolomics_coanalysis", { session_id: sid, ...params }, false, {
    timeoutMs: 60 * 60 * 1000,
  });
}

export async function chipClinicalCoanalysis(params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/chipseq/analyze/clinical_coanalysis", { session_id: sid, ...params }, false, {
    timeoutMs: 60 * 60 * 1000,
  });
}

export async function chipRecipePacks() {
  return request("GET", "/workflows/chipseq/recipes/packs");
}

export async function chipMacsPresets() {
  return request("GET", "/workflows/chipseq/macs/presets");
}

export async function chipDownloadTable(filePath) {
  const sid = sessionId();
  return request(
    "GET",
    `/workflows/chipseq/tables/download?session_id=${encodeURIComponent(sid || "")}&file_path=${encodeURIComponent(filePath || "")}`
  );
}

export async function chipDownstreamCatalog() {
  return request("GET", "/workflows/chipseq/downstream/catalog");
}

export async function chipPeakQc(params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/chipseq/peak_qc", { session_id: sid, ...params });
}

export async function chipToolsStatus() {
  return request("GET", "/workflows/chipseq/tools/status");
}

export async function chipHomer(params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/chipseq/analyze/homer", { session_id: sid, ...params });
}

export async function chipDiffBind(params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/chipseq/analyze/diffbind", { session_id: sid, ...params });
}

export async function chipDeepTools(params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/chipseq/analyze/deeptools", { session_id: sid, ...params });
}

/** Peak set ops: blacklist|merge|summit|overlap|idr|promoter|enhancer|super_enhancer|broad|bivalent|chromatin_proxy */
export async function chipPeaksOps(params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/chipseq/analyze/peaks_ops", { session_id: sid, ...params });
}

// ── EXPORT ────────────────────────────────────────
export function exportAssayURL(experiment) {
  const sid = sessionId();
  return `${API}/export/assay/${sid}/${encodeURIComponent(experiment)}`;
}

export function exportEmptURL(experiment) {
  const sid = sessionId();
  return `${API}/export/empt/${sid}/${encodeURIComponent(experiment)}`;
}

export async function prepareEmptExport(experiment) {
  const sid = sessionId();
  return request("POST", "/export/empt/prepare", { session_id: sid, experiment });
}

export function exportColdataURL(experiment) {
  const sid = sessionId();
  return `${API}/export/coldata/${sid}/${encodeURIComponent(experiment)}`;
}

export function exportResultURL(experiment, analysis) {
  const sid = sessionId();
  return `${API}/export/result/${sid}/${encodeURIComponent(experiment)}/${analysis}`;
}

export function exportRdsURL() {
  const sid = sessionId();
  return `${API}/export/rds/${sid}`;
}

export function mbxExportDiffURL(experiment) {
  const sid = sessionId();
  return `${API}/workflows/metabolomics/export/differential/${sid}/${encodeURIComponent(experiment)}`;
}

export async function mbxValidate(experiment, params = {}) {
  const sid = sessionId();
  return request("POST", "/workflows/metabolomics/validate", { session_id: sid, experiment, ...params });
}

// ── TEACHING ──────────────────────────────────────
export async function teachingCases() {
  return request("GET", "/teaching/cases");
}

export async function teachingCase(caseId) {
  return request("GET", `/teaching/cases/${encodeURIComponent(caseId)}`);
}

export async function teachingPrompts() {
  return request("GET", "/teaching/prompts");
}

export async function teachingTrace(eventOrOpts = {}) {
  if (typeof eventOrOpts === "object" && eventOrOpts.user_id) {
    const q = new URLSearchParams();
    q.set("user_id", eventOrOpts.user_id);
    if (eventOrOpts.limit) q.set("limit", String(eventOrOpts.limit));
    return request("GET", `/teaching/trace?${q.toString()}`);
  }
  return request("POST", "/teaching/trace", eventOrOpts);
}

export async function teachingReflection(payload) {
  return request("POST", "/teaching/reflection", payload);
}

export async function teachingSubmitQuiz(payload) {
  return request("POST", "/teaching/quiz", payload);
}

export async function teachingProgress(userId = null) {
  const q = userId ? `?user_id=${encodeURIComponent(userId)}` : "";
  return request("GET", `/teaching/progress${q}`);
}

export async function teachingPreclassTemplate() {
  return request("GET", "/teaching/preclass");
}

export async function teachingSubmitPreclass(fields) {
  return request("POST", "/teaching/preclass", { fields });
}

export async function teachingCritiqueCases() {
  return request("GET", "/teaching/critique");
}

export async function teachingSubmitCritique(payload) {
  return request("POST", "/teaching/critique", payload);
}

export async function teachingSaveJournal(payload) {
  return request("POST", "/teaching/journal", payload);
}

export async function teachingReport() {
  return request("GET", "/teaching/report");
}

// ── GITHUB COURSE SYNC ────────────────────────────
export async function githubAssignments() {
  return request("GET", "/github/assignments");
}

export async function githubRegister(payload) {
  return request("POST", "/github/register", payload);
}

export async function githubLogin(payload) {
  return request("POST", "/github/login", payload);
}

export async function githubLogout() {
  return request("POST", "/github/logout", {});
}

export async function githubStatus() {
  return request("GET", "/github/status");
}

export async function githubEnsureClassRepo() {
  return request("POST", "/github/ensure_class_repo", {});
}

export async function githubBind(payload) {
  return request("POST", "/github/bind", payload);
}

export async function githubUnbind() {
  return request("POST", "/github/unbind", {});
}

export async function githubSync(payload) {
  return request("POST", "/github/sync", payload);
}

export async function githubSyncs() {
  return request("GET", "/github/syncs");
}
