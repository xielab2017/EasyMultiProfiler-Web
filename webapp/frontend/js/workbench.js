import {mountWorkflowDesigner} from './workflow_designer.js?v=1';
import {textPair,proposeForScope} from './workflow_library.mjs';
import {featureText, applyFeatureLocale} from './feature_i18n.mjs?v=2';
import {getLocale} from './locale.js?v=i18n-zh-default-v1';
import {request as rRequest} from './api.js?v=i18n-zh-default-v1';
import {CONTRACT, WorkflowState, resultTSV} from './workbench_core.mjs';
import {studyContexts} from './study_model.mjs';
import {mountSampleReview} from './sample_review.js';
import {mountSimpleWorkbench} from './workbench_simple.js';

const ft = (source, vars) => featureText(source, getLocale(), vars);
const $ = id => document.getElementById(`wb-${id}`);
const state = new WorkflowState(ft);
let catalog, input, busy = false, provider = null, proposal = null, result = null, pollTimer = null;
let agentInfo = null, runtimeInfo = null, designer = null, sampleReview = null, quickUI = null, selectedDifferential = 0, readinessVisible = false;
const labels = {qc:ft('计数质量检查'), normalize:ft('Size-factor 归一化'), pca:'PCA', deseq2:ft('DESeq2 差异分析'), heatmap:ft('高变基因热图')};
const paramLabels = {alpha:ft('FDR 阈值'), min_count:ft('最低计数'), min_samples:ft('至少满足的样本数'), components:ft('主成分数'), top_n:ft('展示基因数')};
function message(id, source, vars = {}) { const el=$(id); el.dataset.featureMessage=source; el.dataset.featureVars=JSON.stringify(vars); el.textContent=ft(source,vars); }
const say = (source, vars) => message('status', source, vars);
const navigate = () => document.querySelector('.nav-item[data-page="workbench"]')?.click();

async function api(op, body, extra = {}) {
  const response = await fetch(`/api/public-data/${op}`, {
    method: body === undefined ? 'GET' : 'POST', redirect: 'error', credentials: 'omit',
    ...(body === undefined ? {} : {headers: {'Content-Type':'application/json'}, body:JSON.stringify(body)}), ...extra,
  });
  let data; try { data = await response.json(); } catch { throw Error(ft('元数据服务未就绪，请使用项目启动器启动服务')); }
  if (!response.ok) throw Error(data.error || `HTTP ${response.status}`);
  return data;
}
async function perform(action) {
  if (busy) return;
  busy = true; document.getElementById('page-workbench')?.setAttribute('aria-busy', 'true');
  try { await action(); } catch (error) { say(error.message || ft('操作失败')); }
  finally { busy = false; document.getElementById('page-workbench')?.removeAttribute('aria-busy'); }
}
function edited() {
  state.change(); $('confirm').checked = false; $('run').disabled = true; $('export-plan').disabled = true;
  $('confirm').disabled=true;message('run','请先完成输入与准备检查');$('review-summary').replaceChildren();if(readinessVisible)renderReadiness();
  $('cloud-consent').checked = false; $('context-result').textContent = '';
  message('review', '数据或流程已改变，请重新检查。'); quickUI?.invalidate();guide();
}
function guide() {
  quickUI?.update();
  if(designer&&(designer.composer.scope!=='bulk_rnaseq'||designer.composer.inputType!=='raw_counts')){message('guide','已切换组学流程：从步骤库组合并审核依赖，再到对应页面导入和分析。');return;}
  message('guide', !input ? ft('引导已启动：在矩阵页下载后送入工作台，或上传本地矩阵。')
    : !state.dataset ? ft('请选择真正的样本计数列；Length 等注释列可手动取消勾选。')
      : !state.prepared ? ft('请填写样本分组、原始计数来源和比较方向，编辑流程后点击“检查并准备流程”。')
        : ft('流程已准备。请审核分组、排除列和参数，再确认运行。'));
}
function save(value, name, type = 'application/json') {
  const text = typeof value === 'string' ? value : JSON.stringify(value, null, 2);
  const url = URL.createObjectURL(new Blob([text], {type}));
  const a = document.createElement('a'); a.href = url; a.download = name; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
function renderSteps() { designer?.render(); }

async function acceptInput(value) {
  input = value; state.dataset = null; edited(); $('samples').replaceChildren();
  $('input-info').textContent = `${value.source_name} · ${value.feature_count} features · SHA-256 ${value.source_sha256}`;
  $('columns').replaceChildren();
  for (const column of value.columns) {
    const label = document.createElement('label'), check = document.createElement('input');
    check.type = 'checkbox'; check.value = column; check.checked = !value.suggested_annotation_columns.includes(column);
    check.onchange = () => { state.dataset = null; $('samples').replaceChildren(); edited(); };
    label.append(check, document.createTextNode(column));
    if (value.suggested_annotation_columns.includes(column)) {
      const hint=document.createElement('span');hint.dataset.featureText='（可能是注释，请核对）';hint.textContent=ft(hint.dataset.featureText);label.append(hint);
    }
    $('columns').append(label);
  }
  $('select').disabled = false;
  if(!$('evidence').value.trim())$('evidence').value=[sampleReview.context?.accession,sampleReview.context?.paper?.doi,value.source_name,'SHA-256 '+value.source_sha256].filter(Boolean).join(' · ');
  await selectColumns();guide();
}
async function ingest() {
  const id = $('job').value.trim(), revision = state.revision;
  const value = await api('workbench/ingest', {job_id:id});
  if (id !== $('job').value.trim() || revision !== state.revision) throw Error(ft('输入已改变，旧矩阵响应已丢弃'));
  sampleReview.setContext(studyContexts.get(id));
  await acceptInput(value);
}
function samples() { return [...$('samples').querySelectorAll('input[data-sample]')].map(el => ({id:el.dataset.sample, group:el.value.trim()})); }
function renderSampleTable(ids){
  $('samples').replaceChildren();const table=document.createElement('table'),header=document.createElement('tr');
  for(const source of ['矩阵列 / GSM','分组','样本对应','标题']){const cell=document.createElement('th');cell.dataset.featureText=source;cell.textContent=ft(source);header.append(cell);}table.append(header);
  const metadata=sampleReview.rows(ids);
  for(const id of ids){const row=document.createElement('tr'),name=document.createElement('td'),groupCell=document.createElement('td'),mappingCell=document.createElement('td'),info=document.createElement('td'),group=document.createElement('input');name.textContent=id;group.dataset.sample=id;group.dataset.featurePlaceholder='填写真实组别';group.placeholder=ft('填写真实组别');group.maxLength=256;group.setAttribute('aria-label',ft('{sample} 的组别',{sample:id}));group.oninput=()=>{sampleReview.invalidate();edited();};groupCell.append(group);const matching=metadata.find(item=>item.id===id);info.textContent=[matching?.gsm,matching?.title].filter(Boolean).join(' · ')||ft('未与矩阵匹配');const records=sampleReview.context?.annotations?.records||[];
    if(records.length){const select=document.createElement('select'),empty=document.createElement('option');empty.value='';empty.textContent=ft('未匹配，请核对');select.append(empty);select.dataset.sampleMapping=id;select.setAttribute('aria-label',ft('{sample} 的 GSM 对应',{sample:id}));for(const record of records){const option=document.createElement('option');option.value=record.accession;option.textContent=`${record.accession} · ${record.title}`;select.append(option);}select.value=matching?.gsm||'';let previous=select.value;select.onchange=()=>{try{sampleReview.mapSample(id,select.value);previous=select.value;group.value='';const updated=sampleReview.rows([id])[0];info.textContent=[updated.gsm,updated.title].filter(Boolean).join(' · ');sampleReview.invalidate();edited();}catch(error){select.value=previous;say(error.message);}};mappingCell.append(select);}else mappingCell.textContent=ft('人工注释');
    row.append(name,groupCell,mappingCell,info);table.append(row);}
  $('samples').append(table);sampleReview.update();
}
function plan() {
  if (!state.dataset) throw Error(ft('请先确认计数列'));
  const steps=designer.composer.connectedCountSteps();
  return {version:1, dataset_id:state.dataset.dataset_id, omics:'bulk_rnaseq', data_type:'raw_counts',
    samples:samples(), grouping_review:sampleReview.record(),design:steps.some(step=>['deseq2','edger'].includes(step.operation))?sampleReview.design():{test:$('test').value.trim(), reference:$('reference').value.trim(), independent_samples:$('independent').checked},
    steps,deferred_steps:designer.composer.status().deferred,seed:Number($('seed').value), raw_counts_evidence:$('evidence').value.trim()};
}
function renderReadiness(){
  const scope=designer?.composer.status(),values=samples(),diff=designer?.composer.steps.some(step=>['deseq2','edger'].includes(step.operation));let comparisons=false;
  try{comparisons=!!sampleReview?.design().contrasts.length;}catch{}
  const checks=[
    [!!scope?.nativeExecutable,'选择可执行的原始计数组学流程','wb-scope'],
    [!!input,'读取下载矩阵或上传本地矩阵','wb-ingest'],
    [!!state.dataset,'核对列选择并确认样本计数列','wb-select'],
    [!!values.length&&values.every(row=>row.group),'填写全部样本的真实分组','wb-group-field'],
    [!!$('group-reviewed')?.checked,'核对样本、元数据与论文分组证据','wb-group-reviewed'],
    [!diff||comparisons,'选择有效的参考组与比较方向','wb-comparison-mode'],
    [!diff||(values.length>0&&[...new Set(values.map(row=>row.group))].every(group=>values.filter(row=>row.group===group).length>=2)),'各组至少两个独立重复','wb-samples'],
    [!diff||$('independent').checked,'确认独立样本及当前设计适用','wb-independent'],
    [!!$('evidence').value.trim(),'记录原始计数的作者或文献依据','wb-evidence'],
  ];
  const area=$('readiness');area.replaceChildren();for(const [ready,label,target]of checks){const row=document.createElement('p'),text=document.createElement('span');text.textContent=ft(ready?'已完成：{item}':'待完成：{item}',{item:ft(label)});row.append(text);if(!ready){const button=document.createElement('button');button.type='button';button.className='btn btn-outline';button.textContent=ft('去完成');button.onclick=()=>{const control=document.getElementById(target);control?.scrollIntoView({behavior:'smooth',block:'center'});control?.focus();};row.append(button);}area.append(row);}
  if(scope?.deferred?.length){const note=document.createElement('p');note.textContent=ft('本次先运行已接入的计数分析；以下步骤保留为待继续：{steps}。',{steps:scope.deferred.map(op=>textPair(designer.composer.library.steps[op].label,getLocale())).join('、')});area.append(note);}
  return checks.every(row=>row[0]);
}
function showPreparedSummary(data){
  const area=$('review-summary');area.replaceChildren();if(!data.valid)return;const plan=data.plan,rows=plan.samples,groups=[...new Set(rows.map(row=>row.group))];
  for(const text of [ft('已准备 {samples} 个样本、{groups} 个组。',{samples:rows.length,groups:groups.length}),...groups.map(group=>`${group}: n=${rows.filter(row=>row.group===group).length}`),ft('本次执行：{steps}',{steps:plan.steps.map(step=>textPair(designer.composer.library.steps[step.operation].label,getLocale())).join(' → ')}),...(plan.design.contrasts||[]).map(pair=>`${pair.test} / ${pair.reference}`),ft('排除的非样本列：{columns}',{columns:plan.excluded_columns.join(', ')||ft('无')})]){const row=document.createElement('p');row.textContent=text;area.append(row);}
}
function applyProposal(value) {
  if (!designer) throw Error(ft('流程目录未加载'));
  if (value.status !== 'draft' || !value.steps?.length) throw Error(ft('所述数据或设计需要专门流程；当前执行器仅支持独立样本 bulk RNA-seq raw counts。'));
  designer.applyCountProposal(value);
}

const NS = 'http://www.w3.org/2000/svg';
function node(name, attrs, text) {
  const el = document.createElementNS(NS, name);
  for (const [key, value] of Object.entries(attrs || {})) el.setAttribute(key, value);
  if (text !== undefined) el.textContent = text;
  return el;
}
function chart(title) {
  const svg = node('svg', {viewBox:'0 0 640 420', role:'img', 'aria-label':title});
  svg.append(node('text', {x:24, y:28, 'font-size':16, fill:'#0f172a'}, title));
  return svg;
}
function addChart(svg, filename) {
  $('results').append(svg);
  const button = document.createElement('button'); button.className = 'btn btn-outline wb-svg-export'; button.textContent = ft('下载此图 SVG');
  button.onclick = () => { svg.setAttribute('xmlns', NS); save(new XMLSerializer().serializeToString(svg), filename, 'image/svg+xml'); };
  $('results').append(button);
}
function pcaChart(pca) {
  if (!Array.isArray(pca.scores) || !pca.scores.length || !('PC2' in pca.scores[0])) return;
  const svg = chart('PCA · log2 size-factor normalized counts + 1');
  const xs = pca.scores.map(r => r.PC1), ys = pca.scores.map(r => r.PC2);
  const scale = (v, values, low, high) => low + (v - Math.min(...values)) / (Math.max(...values)-Math.min(...values) || 1) * (high-low);
  svg.append(node('path',{d:'M70 60 V350 H610', stroke:'#64748b', fill:'none'}));
  const groups = [...new Set(pca.scores.map(r=>r.group))], colors = ['#0f766e','#c2410c','#4338ca','#be185d'];
  for (let i=0; i<5; i++) {
    const xv = Math.min(...xs)+(Math.max(...xs)-Math.min(...xs))*i/4, yv = Math.min(...ys)+(Math.max(...ys)-Math.min(...ys))*i/4;
    svg.append(node('text',{x:80+i*125,y:370,'font-size':10,'text-anchor':'middle'},xv.toFixed(1)));
    svg.append(node('text',{x:60,y:340-i*65,'font-size':10,'text-anchor':'end'},yv.toFixed(1)));
  }
  for (const row of pca.scores) {
    const circle = node('circle',{cx:scale(row.PC1,xs,80,580),cy:scale(row.PC2,ys,340,80),r:6,fill:colors[groups.indexOf(row.group)%colors.length]});
    circle.append(node('title',{},`${row.sample} · ${row.group}: ${row.PC1}, ${row.PC2}`)); svg.append(circle);
  }
  svg.append(node('text',{x:250,y:402,'font-size':12},`PC1 (${(100*pca.variance_explained[0]).toFixed(1)}%)`));
  svg.append(node('text',{x:20,y:220,'font-size':12,transform:'rotate(-90 20 220)'},`PC2 (${(100*pca.variance_explained[1]).toFixed(1)}%)`));
  groups.forEach((g,i)=>svg.append(node('text',{x:350,y:45+i*15,'font-size':11,fill:colors[i%colors.length]},g)));
  addChart(svg, 'pca.svg');
}
function heatmapChart(heatmap) {
  const rows = heatmap.feature_ids.length, columns = heatmap.sample_ids.length;
  const height = Math.max(420, rows*14+140), svg = chart('High-variance features · row z-score');
  svg.setAttribute('viewBox',`0 0 640 ${height}`);
  const cellH = (height-140)/rows, cellW = 450/columns;
  heatmap.values.forEach((values,i) => {
    values.forEach((z,j) => {
      const t = Math.min(Math.abs(z)/2.5,1), rgb = z >= 0 ? [255,Math.round(255-165*t),Math.round(255-180*t)] : [Math.round(255-215*t),Math.round(255-140*t),255];
      const rect=node('rect',{x:140+j*cellW,y:65+i*cellH,width:cellW+.1,height:cellH+.1,fill:`rgb(${rgb.join(',')})`});
      rect.append(node('title',{},`${heatmap.feature_ids[i]} / ${heatmap.sample_ids[j]}: ${z.toFixed(3)}`));svg.append(rect);
    });
    svg.append(node('text',{x:134,y:65+(i+.75)*cellH,'text-anchor':'end','font-size':Math.min(11,cellH*.8)},heatmap.feature_ids[i]));
  });
  heatmap.sample_ids.forEach((s,j)=>svg.append(node('text',{x:140+(j+.5)*cellW,y:height-60,'text-anchor':'end','font-size':10,transform:`rotate(-45 ${140+(j+.5)*cellW} ${height-60})`},s)));
  svg.append(node('text',{x:140,y:height-8,'font-size':11},'blue ≤ −2.5   white = 0   red ≥ +2.5 (display clipped)'));
  addChart(svg, 'high_variance_heatmap.svg');
}
function table(rows, columns) {
  const el = document.createElement('table'), header = document.createElement('tr');
  columns.forEach(k => { const th=document.createElement('th'); th.textContent=k; header.append(th); }); el.append(header);
  rows.forEach(row => { const tr=document.createElement('tr'); columns.forEach(k => { const td=document.createElement('td'); td.textContent=row[k]??'';tr.append(td); });el.append(tr); });
  $('results').append(el);
}
function displayResult(value) {
  if (value.contract !== CONTRACT || value.execution_performed !== true || !value.success ||
      (state.active?.plan_sha256 && value.plan_sha256 !== state.active.plan_sha256)) throw Error(ft('结果未通过流程身份校验'));
  result=value; $('results').replaceChildren();
  const artifacts=value.artifacts;
  table(artifacts.qc.samples,['sample','library_size','detected_features']);
  if (artifacts.pca) pcaChart(artifacts.pca);
  if (artifacts.heatmap) heatmapChart(artifacts.heatmap);
  const differentials=artifacts.differentials||[artifacts.differential].filter(Boolean);
  if (differentials.length) {
    const declared=value.plan.design.contrasts||[{test:value.plan.design.test,reference:value.plan.design.reference}];
    if(differentials.some(de=>!['DESeq2','edgeR'].includes(de.method)||de.positive_log2fc!=='test / reference'||!declared.some(pair=>pair.test===de.test&&pair.reference===de.reference)))throw Error(ft('差异分析方法或比较方向未验证'));
    selectedDifferential=Math.min(selectedDifferential,differentials.length-1);
    const select=document.createElement('select');select.id='wb-result-contrast';select.setAttribute('aria-label',ft('选择差异方法与比较'));differentials.forEach((de,i)=>{const option=document.createElement('option');option.value=String(i);option.textContent=`${de.method} · ${de.test} / ${de.reference}`;select.append(option);});select.value=String(selectedDifferential);select.onchange=()=>{selectedDifferential=Number(select.value);displayResult(result);};$('results').append(select);
    const de=differentials[selectedDifferential],edger=de.method==='edgeR',fdr=edger?'FDR':'padj';
    const caption=document.createElement('p');caption.textContent=ft('{method} · {test} / {reference} · BH FDR < {alpha}：{significant}/{tested}。前 20 行按 FDR 排序，完整结果可单独下载。',{method:de.method,test:de.test,reference:de.reference,alpha:de.alpha,significant:de.significant_features,tested:de.tested_features});$('results').append(caption);
    table([...de.rows].sort((a,b)=>(a[fdr]??Infinity)-(b[fdr]??Infinity)).slice(0,20),edger?['feature_id','logFC','PValue','FDR']:['feature_id','log2FoldChange','pvalue','padj']);
  }
  const note=document.createElement('p');note.textContent=(value.warnings||[]).join(' ');$('results').append(note);
  $('export-result').disabled=false; $('export-de').disabled=!artifacts.differential;
  const deferred=value.plan.deferred_steps||[];if(deferred.length)message('guide','本次登记分析已完成；以下步骤尚未执行：{steps}。',{steps:deferred.join(', ')});else message('guide','分析完成：检查 QC、样本结构和效应方向，结合来源与生物学背景解释；可导出结果、流程及软件版本。');
}
async function refreshJob() {
  const id=$('analysis-job').value.trim(); if(!id)throw Error(ft('请输入分析任务 ID'));
  const data=await rRequest('GET',`/jobs/${encodeURIComponent(id)}`,null,false,{skipSessionHeader:true,timeoutMs:15000});
  if(id!==$('analysis-job').value.trim())return;
  const job=data.job;
  if(!job||job.kind!=='count_workbench')throw Error(ft('该任务不是当前计数工作流'));
  $('progress').value=job.progress||0;say(`${job.status} · ${job.progress||0}% · ${job.message||job.error||''}`);
  $('cancel').disabled=!['queued','running'].includes(job.status);
  if(job.status==='done') {
    const value=await rRequest('GET',`/jobs/${encodeURIComponent(id)}/result`,null,false,{skipSessionHeader:true,timeoutMs:30000});
    if(id===$('analysis-job').value.trim())displayResult(value);
  } else if(['queued','running','cancel_requested'].includes(job.status)) {
    pollTimer=setTimeout(()=>refreshJob().catch(e=>say('查询中断：{error}。任务可能仍在运行，可手动刷新。',{error:e.message})),2000);
  }
}

$('ingest').onclick=()=>perform(ingest);
$('job').oninput=()=>{input=null;state.dataset=null;$('select').disabled=true;sampleReview.setContext(null);edited();};
document.getElementById('matrix-open-workbench').onclick=()=>perform(async()=>{
  designer.switchScope('bulk_rnaseq');
  $('job').value=document.getElementById('matrix-job-id').value.trim();input=null;state.dataset=null;edited();navigate();await ingest();
});
$('upload').onchange=()=>perform(async()=>{
  const file=$('upload').files[0];
  if(!file){$('file-name').dataset.featureText='未选择文件';$('file-name').textContent=ft('未选择文件');return;}
  delete $('file-name').dataset.featureText;$('file-name').textContent=file.name;
  if(file.size>12*1024**2)throw Error(ft('导入上限 12 MiB'));
  sampleReview.setContext(null);
  input=null;state.dataset=null;edited();const rev=state.revision;
  const data=await api('workbench/upload',null,{headers:{'Content-Type':'application/octet-stream','X-Matrix-Name':encodeURIComponent(file.name)},body:file});
  if(rev!==state.revision)throw Error(ft('输入已改变，旧响应已丢弃'));await acceptInput(data);
});
async function selectColumns(){
  if(!input)throw Error(ft('请先导入矩阵'));const rev=state.revision;
  const columns=[...$('columns').querySelectorAll('input:checked')].map(x=>x.value);
  const data=await api('workbench/select',{input_id:input.input_id,sample_columns:columns});
  if(rev!==state.revision)throw Error(ft('样本列已改变，请重新确认'));
  const context=sampleReview.context;
  if(context?.accession){try{const annotations=await api('processed/annotations',{accession:context.accession,columns:data.sample_ids});if(rev!==state.revision)throw Error(ft('样本列已改变，请重新确认'));sampleReview.setContext({...context,annotations});}catch(error){if(rev!==state.revision)throw error;say(error.message);}}
  state.dataset=data;edited();renderSampleTable(data.sample_ids);
  say('已选择 {count} 样本，明确排除列：{excluded}。请填写组别。',{count:data.sample_ids.length,excluded:data.excluded_columns.join(', ')||ft('无')});guide();
}
$('select').onclick=()=>perform(selectColumns);
for(const id of ['reference','test','evidence','independent','seed'])$(id).addEventListener('input',edited);
$('question').oninput=()=>{proposal=null;$('apply-ai').disabled=true;$('cloud-consent').checked=false;};
$('propose').onclick=()=>perform(async()=>{
  const q=$('question').value;
  if(designer.composer.scope!=='bulk_rnaseq'||designer.composer.inputType!=='raw_counts'){
    try{const draft=proposeForScope(q,designer.composer.scope,designer.composer.inputType);designer.applyBlueprint(draft.blueprint);message('answer','已按当前组学用本地关键词生成步骤草稿；没有运行分析。请核对步骤库和执行能力。');}
    catch{throw Error(ft('本地规则未能生成兼容流程。请明确列出步骤；否定、复杂设计或输入类型冲突请通过步骤库逐项调整。'));}
    return;
  }
  const data=await api('workbench/propose',{question:q});if(q!==$('question').value)throw Error(ft('问题已改变'));message('answer',data.status==='draft'?'已将指令转为可编辑流程。请选数据、分组并审核。':'所述数据或设计需要专门流程；当前执行器仅支持独立样本 bulk RNA-seq raw counts。');applyProposal(data);
});
async function preparePlan(){
  const structural=designer.composer.status();
  if(!structural.valid){message('review','请先修正步骤依赖、顺序或输入类型。');return;}
  if(!structural.nativeExecutable){$('review').textContent=JSON.stringify({blueprint:designer.composer.blueprint(),validation:structural,data_verified:false,execution_performed:false},null,2);delete $('review').dataset.featureMessage;$('export-plan').disabled=false;say('此流程可编排和导出；请通过各步骤的页面入口执行，当前没有整条自动执行适配器。');return;}
  readinessVisible=true;if(!renderReadiness()){say('请完成清单中的准备项，再检查并准备流程。');return;}
  const rev=state.revision;const data=await api('workbench/prepare',{plan:plan()});state.acceptPrepared(data,rev);
  delete $('review').dataset.featureMessage;
  $('review').textContent=JSON.stringify(data,null,2);showPreparedSummary(data);$('confirm').checked=false;$('confirm').disabled=!data.valid;$('run').disabled=true;$('export-plan').disabled=!data.valid;message('run',data.valid?'运行本次已准备的分析':'请先完成输入与准备检查');guide();
  say(data.valid?ft('流程预检通过，请审核完整计划后确认运行。'):data.errors.join('；'));
}
$('prepare').onclick=()=>perform(preparePlan);
$('confirm').onchange=()=>{$('run').disabled=!$('confirm').checked||!state.prepared||!designer.composer.status().nativeExecutable;};
async function runPrepared(){
  if(!designer.composer.status().nativeExecutable)throw Error(ft('当前流程包含尚未连接工作台执行的步骤。'));
  if(!state.prepared||!$('confirm').checked)throw Error(ft('请先审核当前流程'));const rev=state.revision;
  const caps=await rRequest('GET','/workbench/capabilities',null,false,{skipSessionHeader:true,timeoutMs:15000});
  if(caps.contract!==CONTRACT||!caps.ready)throw Error(ft('R 执行器未就绪，请检查软件包并用更新后的项目启动 R API'));
  if(state.prepared.plan?.design?.contrasts&&!caps.multiple_contrasts)throw Error(ft('R 服务尚未加载多组比较功能，请使用更新后的服务。'));
  const payload=await api(`workbench/prepared/${encodeURIComponent(state.prepared.prepared_id)}`);
  if(rev!==state.revision)throw Error(ft('计划已改变，请重新审核'));const request=state.executionRequest(payload,$('confirm').checked);
  const submitted=await rRequest('POST','/workbench/run',request,false,{skipSessionHeader:true,timeoutMs:60000});
  if(submitted.contract!==CONTRACT||!submitted.job_id)throw Error(ft('未收到可验证的任务 ID；请先查看任务列表，避免重复提交'));
  state.active={job_id:submitted.job_id,plan_sha256:submitted.plan_sha256};$('analysis-job').value=submitted.job_id;
  localStorage.setItem('emp_workbench_last_job',JSON.stringify(state.active));$('confirm').checked=false;$('run').disabled=true;
  clearTimeout(pollTimer);await refreshJob();
}
$('run').onclick=()=>perform(runPrepared);
$('refresh').onclick=()=>perform(async()=>{clearTimeout(pollTimer);await refreshJob();});
$('analysis-job').oninput=()=>{clearTimeout(pollTimer);state.active=null;result=null;$('results').replaceChildren();$('export-result').disabled=true;$('export-de').disabled=true;$('cancel').disabled=true;};
$('cancel').onclick=()=>perform(async()=>{clearTimeout(pollTimer);const id=$('analysis-job').value.trim();const response=await rRequest('POST',`/jobs/${encodeURIComponent(id)}/cancel`,{},false,{skipSessionHeader:true});say('取消请求：{status}',{status:response.cancellation?.status||ft('未确认')});await refreshJob();});
$('export-plan').onclick=()=>perform(async()=>{const blueprint=designer.composer.blueprint();if(!designer.composer.status().valid)throw Error(ft('请先修正步骤依赖、顺序或输入类型。'));if(state.prepared){const prepared_input=await api(`workbench/prepared/${encodeURIComponent(state.prepared.prepared_id)}`);save({blueprint,prepared_input},'emp-count-workflow-input.json');}else save(blueprint,'emp-workflow-blueprint.json');});
$('export-result').onclick=()=>{if(result)save(result,'emp-count-workflow-results.json');};
$('export-de').onclick=()=>{const items=result?.artifacts.differentials||[result?.artifacts.differential].filter(Boolean);const de=items[selectedDifferential];if(de)save(resultTSV(de.rows,de.method),`contrast-${selectedDifferential+1}-${de.method}.tsv`,'text/tab-separated-values;charset=utf-8');};
$('context').onclick=()=>perform(async()=>{
  const rev=state.revision;const ids=state.prepared?{workbench_id:state.prepared.prepared_id}:{};
  const data=await api('agent/context-preview',{context_ids:ids});if(rev!==state.revision)throw Error(ft('流程已改变，请重新预览'));
  state.context=data;$('context-result').textContent=JSON.stringify(data,null,2);$('cloud-consent').checked=false;
});
$('cloud').onclick=()=>perform(async()=>{
  if(!provider)throw Error(ft('模型状态未就绪'));if(!$('cloud-consent').checked)throw Error(ft('请先确认本次问题的数据发送范围'));
  if(state.prepared&&!state.context)throw Error(ft('请先预览流程摘要再同意发送'));
  const question=$('question').value, rev=state.revision;
  say('AI 正在查询或生成建议，请等待；尚未执行分析。');
  const data=await api('agent/respond',{question,consent:true,expected_provider:provider,expected_config_revision:agentInfo?.config_revision,context_ids:state.prepared?{workbench_id:state.prepared.prepared_id}:{},context_consent:!!state.context,context_sha256:state.context?.snapshot_sha256});
  if(question!==$('question').value||rev!==state.revision)throw Error(ft('问题或流程已改变，旧 AI 响应已丢弃'));
  $('cloud-consent').checked=false;delete $('answer').dataset.featureMessage;$('answer').textContent=data.answer||data.status;
  let audit=$('ai-audit');if(!audit){audit=document.createElement('p');audit.id='wb-ai-audit';$('answer').after(audit);}audit.textContent=`${data.status} · `+(data.audit||[]).map(row=>`${row.tool}: ${row.status} (${row.duration_ms} ms)`).join(' · ');
  say('AI 建议已返回；请核对工具记录与步骤，实际运行仍需审核。');
  proposal=(data.tool_results||[]).find(x=>x.tool==='propose_count_workflow'&&x.result.status==='draft')?.result||null;
  $('apply-ai').disabled=!proposal;
});
$('apply-ai').onclick=()=>{try{if(proposal)applyProposal(proposal);$('apply-ai').disabled=true;}catch(e){say(e.message);}};

async function boot() {
  await Promise.allSettled([
    api('workbench/catalog').then(data=>{catalog=data;}),
    api('agent/status').then(data=>{agentInfo=data;provider=data.provider;renderConnections();}),
    rRequest('GET','/workbench/capabilities',null,false,{skipSessionHeader:true,timeoutMs:15000}).then(data=>{runtimeInfo=data;renderConnections();}).catch(()=>{runtimeInfo=false;renderConnections();}),
  ]);
  if(!catalog)say(ft('元数据服务未连接；本地流程编排仍可使用。'));
  try {const active=JSON.parse(localStorage.getItem('emp_workbench_last_job'));if(active?.job_id){state.active=active;$('analysis-job').value=active.job_id;say(ft('已恢复上次任务 ID；点击刷新查询，不会重复运行。'));}}catch{}
  guide();
}
function renderConnections() {
  if (agentInfo) {
    message('agent-status',agentInfo.status==='ready'?'模型已配置：{provider} / {model}':'模型未配置：可先使用本地流程生成与引导。',{provider:agentInfo.provider,model:agentInfo.model});
    message('cloud-label','同意将本次问题、预览的流程摘要发送到 {provider}，并将必要的公开检索词发送至 NCBI/ENA。矩阵数值、样本标签和文件不发送。',{provider:agentInfo.provider});
  }
  if(runtimeInfo?.contract===CONTRACT&&runtimeInfo.ready)message('runtime','R 执行器已连接 · R {r} · DESeq2 {deseq2}',{r:runtimeInfo.r_version,deseq2:runtimeInfo.packages.DESeq2});
  else if(runtimeInfo===false)message('runtime','R 执行器未连接；数据导入和流程编辑可先进行。');
  else if(runtimeInfo)message('runtime','当前 R 服务未提供此执行器；请用更新后的项目启动 R API。');
}
window.addEventListener('emp:locale-change',()=>{
  applyFeatureLocale(document,getLocale());renderSteps();renderConnections();
  if(designer)$('external-scope').textContent=textPair(designer.composer.library.label,getLocale());
  for(const control of $('samples').querySelectorAll('input[data-sample]'))control.setAttribute('aria-label',ft('{sample} 的组别',{sample:control.dataset.sample}));
  if(result)displayResult(result);
});
function openWorkflowPage(scope,definition={}){
  const entry=designer.composer.library;const page=scope==='multiomics'&&!definition.page?'integration':definition.page||entry.page;
  const omics=document.getElementById('omics-pipeline');
  if(omics&&[...omics.options].some(o=>o.value===entry.omics)){omics.value=entry.omics;omics.dispatchEvent(new Event('change',{bubbles:true}));}
  document.querySelector(`.nav-item[data-page="${page}"]`)?.click();
  if(page==='clinical'&&definition.tab){const select=document.getElementById('clin-analysis-strategy');if([...select.options].some(o=>o.value===definition.tab)){select.value=definition.tab;select.dispatchEvent(new Event('change',{bubbles:true}));}}
  else if(definition.tab)document.querySelector(`#page-${page} .tab[data-tab="${definition.tab}"]`)?.click();
}
function refreshAgentConnection(){api('agent/status').then(data=>{if(data.config_revision!==agentInfo?.config_revision)$('cloud-consent').checked=false;agentInfo=data;provider=data.provider;renderConnections();}).catch(()=>{});}
window.addEventListener('emp:agent-config-change',refreshAgentConnection);
window.addEventListener('focus',refreshAgentConnection);
window.addEventListener('storage',event=>{if(event.key==='emp_agent_config_revision')refreshAgentConnection();});
document.addEventListener('visibilitychange',()=>{if(!document.hidden)refreshAgentConnection();});
function editorChanged(composer){
  state.steps=composer.steps;edited();
  const native=composer.scope==='bulk_rnaseq'&&composer.inputType==='raw_counts';
  $('count-inputs').hidden=!native;$('external-data').hidden=native;
  $('external-scope').textContent=textPair(composer.library.label,getLocale());
  $('export-plan').disabled=!composer.status().valid;
}
designer=mountWorkflowDesigner({onChange:editorChanged,onNavigate:openWorkflowPage});
sampleReview=mountSampleReview($('study-review'),{getSamples:samples,onChange:edited,onGroups:rows=>{for(const control of $('samples').querySelectorAll('input[data-sample]'))control.value=rows.find(row=>row.id===control.dataset.sample)?.group||'';}});
window.addEventListener('emp:study-reset',()=>{
  input=null;state.dataset=null;proposal=null;sampleReview.setContext(null);
  for(const id of ['job','reference','test','evidence','upload'])$(id).value='';
  $('independent').checked=false;$('select').disabled=true;$('apply-ai').disabled=true;
  for(const id of ['columns','samples','input-info','context-result'])$(id).replaceChildren();
  message('file-name','未选择文件');edited();
  say('当前文章与数据选择已清空；原下载文件和分析任务保留。');
});
editorChanged(designer.composer);
quickUI=mountSimpleWorkbench({
 isNative:()=>designer.composer.scope==='bulk_rnaseq'&&designer.composer.inputType==='raw_counts',
 describe:()=>{const rows=samples(),groups=[...new Set(rows.map(r=>r.group).filter(Boolean))],steps=designer.composer.steps.filter(s=>!['data_input','sample_metadata','export'].includes(s.operation)).map(s=>textPair(designer.composer.library.steps[s.operation].label,getLocale())).join(' → ');return{steps,lines:[input?`${input.source_name} · ${rows.length} ${getLocale()==='en'?'samples':'个样本'}`:ft('读取下载矩阵或上传本地矩阵'),...groups.map(group=>`${group}: n=${rows.filter(row=>row.group===group).length}`),$('comparison-preview')?.textContent||'']};},
 onStart:()=>perform(async()=>{
  if(designer.composer.scope!=='bulk_rnaseq'||designer.composer.inputType!=='raw_counts'){openWorkflowPage(designer.composer.scope);return;}
  if(!input){quickUI.focus('upload');throw Error(ft('请先导入矩阵'));}
  if(!state.dataset){await selectColumns();quickUI.focus('samples');return;}
  if(samples().some(row=>!row.group)){quickUI.focus('samples');throw Error(ft('填写全部样本的真实分组'));}
  try{sampleReview.design();}catch{quickUI.focus('reference');throw Error(ft('选择有效的参考组与比较方向'));}
  if(!quickUI.reviewed()){quickUI.focus('simple-consent');throw Error(ft('请核对分组、比较方向和来源后确认本次分析。'));}
  $('group-reviewed').checked=true;$('independent').checked=true;
  await preparePlan();if(!state.prepared)return;$('confirm').checked=true;await runPrepared();quickUI.invalidate();
 })
});
$('external-open').onclick=()=>openWorkflowPage(designer.composer.scope);
window.addEventListener('emp:workbench-proposal',event=>{try{const {proposal,question}=event.detail||{};if(!proposal)return;designer.applyCountProposal(proposal);if(typeof question==='string')$('question').value=question;}catch(e){say(e.message);}});

boot();
