const $ = (id) => document.getElementById(id);
let current = null, plan = null, generation = 0, working = false;
let selectedContextManifestId = null, lastWorkflowPlanId = null, contextPreview = null;
function resetAgentContext() { contextPreview = null; $('agent-context-consent').checked = false; $('agent-context-preview').textContent = '上下文已改变，请重新预览并确认。'; }
async function request(operation, body) {
  const response = await fetch(`/api/public-data/${operation}`, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)});
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || `HTTP ${response.status}`);
  return data;
}
function clearPlan() { selectedContextManifestId = null; resetAgentContext(); plan = null; $('save').disabled = true; $('plan-result').textContent = '选择已改变，请重新检查计划。'; }
function busy(value) { for (const id of ['search', 'resolve', 'plan']) $(id).disabled = value || (id === 'plan' && !current); }
async function run(work) {
  if (working) return;
  working = true;
  busy(true); $('status').textContent = '正在读取公开元数据…';
  try { await work(); $('status').textContent = '元数据操作完成。未下载任何测序文件。'; }
  catch (error) { $('status').textContent = `无法完成：${error.message}。请检查元数据服务和网络。`; }
  finally { working = false; busy(false); }
}
$('search').onclick = () => run(async () => {
  const data = await request('search', {term: $('term').value});
  $('studies').replaceChildren();
  for (const record of data.records) {
    const row = document.createElement('p'); row.textContent = `${record.accession}: ${record.title}`;
    if (/^GSE\d+$/.test(record.accession)) {
      const button = document.createElement('button'); button.textContent = '填入 accession';
      button.onclick = () => { $('accession').value = record.accession; }; row.append(button);
    }
    $('studies').append(row);
  }
  if (!data.records.length) $('studies').textContent = '没有检索结果，不能据此判断原始数据不存在。';
});
$('resolve').onclick = () => run(async () => {
  generation++; current = null; clearPlan(); $('runs').textContent = '正在读取…';
  const data = await request('resolve', {accession: $('accession').value}); current = data;
  const table = document.createElement('table');
  const head = document.createElement('tr');
  for (const label of ['选择', 'Run / Sample', '物种', '策略 / Layout', 'FASTQ 字节']) { const th = document.createElement('th'); th.textContent = label; head.append(th); }
  table.append(head);
  for (const r of data.manifest.runs) {
    const row = document.createElement('tr'), cell = document.createElement('td'), check = document.createElement('input');
    check.type = 'checkbox'; check.value = r.run_accession; check.setAttribute('aria-label', `选择 ${r.run_accession}`);
    check.onchange = () => { generation++; clearPlan(); }; cell.append(check); row.append(cell);
    for (const value of [`${r.run_accession} / ${r.sample_accession}`, r.scientific_name, `${r.library_strategy} / ${r.library_layout}`, r.files.length ? r.files.reduce((n, f) => n + f.bytes, 0).toLocaleString() : '无公开链接']) {
      const td = document.createElement('td'); td.textContent = value; row.append(td);
    }
    table.append(row);
  }
  $('runs').replaceChildren(table);
  if (!data.manifest.runs.length) $('runs').textContent = '未解析到 runs；请核对来源关联与 accession。';
});
$('plan').onclick = () => run(async () => {
  clearPlan(); const version = generation;
  const selected = [...$('runs').querySelectorAll('input:checked')].map((x) => x.value);
  const result = await request('plan', {manifest_id: current.manifest_id, selected_runs: selected});
  if (version !== generation) throw new Error('选择已改变，请重新生成计划');
  plan = result; selectedContextManifestId = result.context_manifest_id; resetAgentContext(); $('plan-result').textContent = JSON.stringify(plan, null, 2); $('save').disabled = false;
});
$('save').onclick = () => {
  if (!plan) return;
  const url = URL.createObjectURL(new Blob([JSON.stringify(plan, null, 2)], {type: 'application/json'}));
  const a = document.createElement('a'); a.href = url; a.download = 'emp-download-review-plan.json'; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
};

function showPaper(data) {
  $('paper-result').replaceChildren();
  const pre = document.createElement('pre'); pre.textContent = JSON.stringify(data, null, 2); $('paper-result').append(pre);
  for (const article of data.articles || []) {
    const button = document.createElement('button'); button.textContent = `读取摘要候选 · PMID ${article.pmid}`;
    button.onclick = () => run(async () => showPaper(await request('papers/abstract', {pmid: article.pmid})));
    $('paper-result').append(button);
  }
  for (const item of data.accessions || []) {
    const button = document.createElement('button'); button.textContent = `选择候选 ${item.accession}`;
    button.onclick = () => { $('accession').value = item.accession; if (/^GSE\d+$/.test(item.accession)) $('processed-accession').value = item.accession; };
    $('paper-result').append(button);
  }
}
async function readPdf(file) {
  if (!file || file.size > 15 * 1024 * 1024) throw new Error('请选择 ≤15 MiB 的 PDF');
  const response = await fetch('/api/public-data/papers/pdf', {method: 'POST', headers: {'Content-Type': 'application/pdf'}, body: file});
  const data = await response.json(); if (!response.ok) throw new Error(data.error || 'PDF解析失败'); showPaper(data);
}
$('pdf').onchange = () => run(() => readPdf($('pdf').files[0]));
$('pdf-drop').ondragover = (event) => { event.preventDefault(); };
$('pdf-drop').ondrop = (event) => { event.preventDefault(); run(() => readPdf(event.dataTransfer.files[0])); };
$('paper-search').onclick = () => run(async () => showPaper(await request('papers/search', {term: $('paper-term').value})));
let processed = null, lastMatrix = null;
$('processed-resolve').onclick = () => run(async () => {
  processed = null; lastMatrix = null; resetAgentContext(); $('matrix-download').replaceChildren(); $('processed-files').replaceChildren(); $('processed-result').textContent = '';
  const data = await request('processed/resolve', {accession: $('processed-accession').value}); processed = data; resetAgentContext();
  for (const file of data.manifest.files) {
    const row = document.createElement('p'); row.textContent = `${file.name} | ${file.format_hint} | ${file.bytes ?? '大小未知'} bytes | 类型未确认`;
    const button = document.createElement('button'); button.textContent = '确认下载此文件并检查';
    button.disabled = file.format_hint !== 'tabular_candidate' || !file.bytes || file.bytes > data.manifest.maximum_download_bytes;
    button.onclick = () => {
      if (working) return;
      if (!confirm(`从 NCBI GEO 下载 ${file.name}（${file.bytes} bytes）到云端本地工作目录并检查？不会执行分析。`)) return;
      button.disabled = true;
      run(async () => { try { const result = await request('processed/download', {manifest_id: data.manifest_id, file_id: file.id, confirmed: true}); $('processed-result').textContent = JSON.stringify(result, null, 2); lastMatrix = result; resetAgentContext(); const link = document.createElement('a'); link.href = `/api/public-data/files/${encodeURIComponent(result.download_id)}`; link.textContent = '保存已下载矩阵到本机'; $('matrix-download').replaceChildren(link); $('workflow-datasets').value = JSON.stringify([{id:'matrix1',omics:'bulk_rnaseq',data_type:'unknown',provenance:{source:result.source_url,sha256:result.sha256},sample_ids:result.inspection.column_labels || []}], null, 2); invalidateWorkflow(); } finally { button.disabled = false; } });
    };
    row.append(button); $('processed-files').append(row);
  }
  if (!data.manifest.files.length) $('processed-files').textContent = '未发现Series补充文件；不表示没有处理矩阵。';
});
$('annotations').onclick = () => run(async () => {
  const result = await request('processed/annotations', {accession: $('processed-accession').value, columns: lastMatrix?.inspection.column_labels || []});
  $('annotation-result').textContent = JSON.stringify(result, null, 2); if (result.matches.length && result.matches.every((m) => m.status === 'exact')) $('workflow-samples').value = JSON.stringify(result.matches.map((m) => ({id:m.column,group:''})), null, 2); invalidateWorkflow();
});
let workflowCatalog = null, workflowSteps = [], workflowGeneration = 0;
function invalidateWorkflow() { lastWorkflowPlanId = null; resetAgentContext(); workflowGeneration++; $('workflow-result').textContent = '计划已改变，请重新校验。'; }
for (const id of ['workflow-datasets','workflow-samples','contrast-test','contrast-reference','use-batch']) $(id).addEventListener('input', invalidateWorkflow);
function renderSteps() {
  $('workflow-steps').replaceChildren();
  workflowSteps.forEach((step, i) => {
    const row = document.createElement('p'); row.textContent = `${i + 1}. ${step.operation} `;
    const dataset = document.createElement('input'); dataset.value = step.dataset_id || 'matrix1'; dataset.setAttribute('aria-label', '数据集ID'); dataset.onchange = () => { step.dataset_id = dataset.value; invalidateWorkflow(); }; row.append(dataset);
    const params = document.createElement('input'); params.value = JSON.stringify(step.parameters); params.setAttribute('aria-label', `${step.operation} 参数JSON`);
    params.onchange = () => { try { step.parameters = JSON.parse(params.value); invalidateWorkflow(); $('workflow-result').textContent = '步骤已改变，请重新校验。'; } catch { params.value = JSON.stringify(step.parameters); } }; row.append(params);
    for (const [label, action] of [['上移', () => { if (i) [workflowSteps[i-1], workflowSteps[i]] = [workflowSteps[i], workflowSteps[i-1]]; }], ['删除', () => workflowSteps.splice(i, 1)]]) {
      const button = document.createElement('button'); button.textContent = label; button.onclick = () => { action(); invalidateWorkflow(); $('workflow-result').textContent = '步骤已改变，请重新校验。'; renderSteps(); }; row.append(button);
    }
    $('workflow-steps').append(row);
  });
}
function addOperation(operation) { invalidateWorkflow(); workflowSteps.push({operation, dataset_id:'matrix1', parameters: {...workflowCatalog.operations[operation].parameters}}); renderSteps(); }
$('use-template').onclick = () => {
  if (!workflowCatalog) return;
  const template = workflowCatalog.templates.find((x) => x.id === $('workflow-template').value);
  if (!template.supported) { $('workflow-result').textContent = template.reason; return; }
  workflowSteps = []; template.steps.forEach(addOperation); $('workflow-result').textContent = '模板只生成计划，请填写数据来源和样本注释后校验。';
};
$('add-step').onclick = () => { if (workflowCatalog) addOperation($('workflow-operation').value); };
$('validate-workflow').onclick = () => run(async () => {
  const validationGeneration = workflowGeneration;
  const datasets = JSON.parse($('workflow-datasets').value), samples = JSON.parse($('workflow-samples').value);
  const plan = {version: 1, datasets, samples, design: {group:'group', contrast:[$('contrast-test').value, $('contrast-reference').value]}, steps: workflowSteps.map((s, i) => ({...s, id:`step${i+1}`, dataset_id: s.dataset_id || datasets[0]?.id || ''}))};
  if ($('use-batch').checked) plan.design.batch = 'batch';
  const result = await request('workflows/validate', {plan}); if (validationGeneration !== workflowGeneration) throw new Error('计划已改变，请重新校验'); lastWorkflowPlanId = result.plan_id || null; resetAgentContext(); $('workflow-result').textContent = JSON.stringify(result, null, 2);
});
fetch('/api/public-data/workflows/templates').then(async (r) => { if (!r.ok) throw new Error('模板服务不可用'); return r.json(); }).then((catalog) => {
  workflowCatalog = catalog;
  for (const template of catalog.templates) { const option = document.createElement('option'); option.value = template.id; option.textContent = `${template.label}${template.supported ? '' : '（未支持）'}`; $('workflow-template').append(option); }
}).catch((error) => { $('workflow-result').textContent = `需启动元数据旁路服务：${error.message}`; });
let agentProvider = null, agentConfigRevision = null;
fetch('/api/public-data/agent/status').then(async (r) => { if (!r.ok) throw new Error('服务不可用'); return r.json(); }).then((data) => { $('agent-status').textContent = JSON.stringify(data, null, 2); agentProvider = data.provider; agentConfigRevision = data.config_revision; $('agent-consent').checked = false; $('agent-consent-label').textContent = `我同意将此问题及工具元数据发送至 ${data.provider}，并将必要的公开检索词/accession发送至NCBI/ENA。PDF附件不会发送，不要粘贴私人内容。`; }).catch((error) => { $('agent-status').textContent = error.message; });
$('agent-send').onclick = () => run(async () => {
  if (!$('agent-consent').checked) throw new Error('请先确认此公开问题的数据发送范围');
  const ids = chosenContextIds();
  if (Object.keys(ids).length && (!contextPreview || !$('agent-context-consent').checked)) throw new Error('请先预览并明确同意发送选中摘要');
  const result = await request('agent/respond', {question: $('agent-question').value, consent: true, expected_provider: agentProvider, expected_config_revision: agentConfigRevision,
    context_ids: ids, context_consent: $('agent-context-consent').checked, context_sha256: contextPreview?.snapshot_sha256});
  $('agent-result').textContent = JSON.stringify(result, null, 2);
});

function chosenContextIds() {
  const ids = {};
  if ($('agent-data-source').value === 'runs') {
    const id = selectedContextManifestId || current?.manifest_id;
    if (!id) throw new Error('请先读取runs清单'); ids.manifest_id = id;
  } else if ($('agent-data-source').value === 'processed') {
    if (!processed) throw new Error('请先读取处理矩阵候选'); ids.manifest_id = processed.manifest_id;
  }
  if ($('agent-inspection').checked) { if (!lastMatrix) throw new Error('请先完成矩阵下载与检查'); ids.download_id = lastMatrix.download_id; }
  if ($('agent-plan').checked) { if (!lastWorkflowPlanId) throw new Error('请先重新预检当前流程'); ids.plan_id = lastWorkflowPlanId; }
  return ids;
}
for (const id of ['agent-data-source','agent-inspection','agent-plan']) $(id).addEventListener('change', resetAgentContext);
$('agent-question').addEventListener('input', () => { $('agent-consent').checked = false; });
$('agent-preview').onclick = () => run(async () => {
  const ids = chosenContextIds();
  const result = await request('agent/context-preview', {context_ids: ids});
  if (JSON.stringify(ids) !== JSON.stringify(chosenContextIds())) throw new Error('选择已改变，请重新预览');
  contextPreview = result; $('agent-context-preview').textContent = JSON.stringify(result, null, 2); $('agent-context-consent').checked = false;
});
