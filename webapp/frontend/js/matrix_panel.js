import {featureText, applyFeatureLocale} from './feature_i18n.mjs?v=2';
import {studyContexts} from './study_model.mjs';
/* Main-application matrix-only panel. No R, raw-read, QC or model calls. */
export function initMatrixPanel(doc=document, transport=fetch, ask=confirm) {
  const locale=()=>doc.defaultView?._empLocale?.getLocale?.() || doc.documentElement?.dataset?.empLocale || 'zh';
  const ft=(source,vars)=>featureText(source,locale(),vars);
  function labelNode(el,source,vars={}) { el.dataset??={};el.dataset.featureMessage=source;el.dataset.featureVars=JSON.stringify(vars);el.textContent=ft(source,vars); }
  doc.defaultView?.addEventListener('emp:locale-change',()=>applyFeatureLocale(doc,locale()));
  const get=id=>doc.getElementById(`matrix-${id}`);
  if(!get('accession')) return;
  let revision=0,busy=false,manifest=null,download=null,annotations=null,job=null,jobAccession=null,artifactJobId=null;
  let paperContext=null,paperAccessions=[],pollTimer=null;const automaticJobs=new Set(),annotationAttempts=new Set();
  const remember=()=>{if(job?.job_id)studyContexts.set(job.job_id,{accession:jobAccession,paper:paperContext,annotations:job.status==='completed'?annotations:null});};
  const set=(id,value,vars={})=>{if(typeof value==='string')labelNode(get(id),value,vars);else{get(id).dataset??={};delete get(id).dataset.featureMessage;get(id).textContent=JSON.stringify(value,null,2);}};
  const getAgentDownloadPermission=()=>doc.getElementById('analysis-agent-mode')?.checked===true;
  const accession=()=>get('accession').value.trim().toUpperCase();
  const validGSE=x=>/^GSE[0-9]+$/.test(x);
  function reset(){revision++;manifest=null;download=null;annotations=null;get('files').replaceChildren();get('save').replaceChildren();get('samples').replaceChildren();set('receipt','');get('export-samples').disabled=true;get('export-provenance').disabled=true;get('export-provenance').removeAttribute('href');get('export-provenance').setAttribute('aria-disabled','true');get('export-receipt').disabled=true;}
  async function api(op,body){
    if(!['search','processed/resolve','processed/annotations','matrix/plan','matrix/start','matrix/status','matrix/cancel','matrix/resume','matrix/preview','matrix/history'].includes(op))throw Error(ft('不支持的矩阵操作'));
    const response=await transport(`/api/public-data/${op}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),redirect:'error',credentials:'omit'});
    let data;try{data=await response.json();}catch{throw Error(ft('矩阵服务未就绪或返回非JSON。请检查主页面的本机同源代理与元数据服务。'));}
    if(!response.ok)throw Error(data.error||ft('矩阵请求失败 HTTP {status}',{status:response.status}));
    return data;
  }
  async function run(action){if(busy)return;busy=true;get('panel').setAttribute('aria-busy','true');set('status',ft('正在处理，请等待；没有执行分析。'));try{await action();}catch(e){set('status',e.message||ft('矩阵请求失败'));}finally{busy=false;get('panel').removeAttribute('aria-busy');}}
  function unchanged(v,a){if(v!==revision||a!==accession())throw Error(ft('GSE已改变，已丢弃旧响应。请重新查找；已确认的服务器下载可能已完成。'));}
  function saveJSON(value,name){const url=URL.createObjectURL(new Blob([JSON.stringify(value,null,2)],{type:'application/json'}));const a=doc.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
  function saveTSV(){
    if(!annotations)throw Error(ft('请先读取样本信息'));
    const clean=x=>{const value=String(x??'').replace(/[\t\r\n]+/g,' ');return /^[=+@-]/.test(value)?"'"+value:value;};
    const rows=[['matrix_column','match_status','GSM','title','characteristics','descriptions']];
    const matches=annotations.matches||[];
    if(matches.length)for(const m of matches)rows.push([m.column,m.status,m.sample?.accession,m.sample?.title,(m.sample?.characteristics||[]).join(' | '),(m.sample?.descriptions||[]).join(' | ')]);
    else for(const r of annotations.records||[])rows.push(['','not_matched',r.accession,r.title,(r.characteristics||[]).join(' | '),(r.descriptions||[]).join(' | ')]);
    const value=rows.map(row=>row.map(clean).join('\t')).join('\n')+'\n';
    const url=URL.createObjectURL(new Blob([value],{type:'text/tab-separated-values;charset=utf-8'}));const a=doc.createElement('a');a.href=url;a.download=`${accession()}_samples.tsv`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
  }
  function clearArtifacts(){download=null;annotations=null;artifactJobId=null;get('save').replaceChildren();get('samples').replaceChildren();set('receipt','');get('export-samples').disabled=true;get('export-provenance').disabled=true;get('export-provenance').removeAttribute('href');get('export-provenance').setAttribute('aria-disabled','true');get('export-receipt').disabled=true;}
  get('job-id').addEventListener('input',()=>{revision++;clearArtifacts();job=null;jobAccession=null;get('resume').disabled=true;});
  function displayJob(value){
    if(artifactJobId!==value.job_id||value.status!=='completed')clearArtifacts();
    artifactJobId=value.job_id;
    set('job-result',value);set('status','下载状态：{status} · 已接收 {bytes} / {total} bytes。{error}',{status:value.status,bytes:value.bytes_downloaded??0,total:value.total_bytes??ft('未知'),error:value.error||''});
    get('resume').disabled=!value.resume_supported;
    get('open-workbench').disabled=value.status!=='completed';
    if(value.status==='completed'&&value.receipt){download={...value.receipt,...(download?.inspection?{inspection:download.inspection}:{})};set('receipt',download);get('export-receipt').disabled=false;const link=doc.createElement('a');link.href=`/api/public-data/matrix/files/${encodeURIComponent(value.job_id)}`;link.download=value.receipt.source_name;labelNode(link,'保存原文件到电脑：{name}',{name:value.receipt.source_name});get('save').replaceChildren(link);set('status',ft('下载完成，已生成本地SHA-256。文件可直接保存；发布方校验是否验证见回执。矩阵内容预览和样本匹配仍有独立小范围限制。'));}
    remember();
    if(value.status==='completed'&&value.receipt)doc.defaultView?.dispatchEvent?.(new CustomEvent('emp:matrix-downloaded',{detail:{job_id:value.job_id,name:value.source_name,accession:jobAccession,sha256:value.receipt.sha256,bytes:value.receipt.bytes,paper:paperContext}}));
    globalThis.clearTimeout?.(pollTimer);
    if(automaticJobs.has(value.job_id)&&['queued','running'].includes(value.status))pollTimer=setTimeout(()=>get('refresh').click(),1800);
  }
  get('refresh').onclick=()=>run(async()=>{const id=get('job-id').value.trim(),v=revision;if(!/^[a-f0-9-]{36}$/.test(id))throw Error(ft('请输入当前下载任务ID'));const loaded=await api('matrix/status',{job_id:id});if(v!==revision||get('job-id').value.trim()!==id)throw Error(ft('任务ID已改变，旧进度已丢弃'));job=loaded;const match=(job.source_url||'').match(/\/(GSE[0-9]+)\/suppl\//);jobAccession=match?match[1]:null;if(jobAccession)get('accession').value=jobAccession;displayJob(job);if(job.status==='completed'&&automaticJobs.has(id)&&!annotationAttempts.has(id)&&jobAccession){annotationAttempts.add(id);try{await readAnnotations();}catch(error){set('status','下载已完成；样本信息读取未完成：{error}。可点击读取样本信息重试。',{error:error.message});}}});
  get('cancel').onclick=()=>run(async()=>{if(!job||get('job-id').value.trim()!==job.job_id)throw Error(ft('先读取并核对此任务'));const selected=job.job_id,v=revision;const updated=await api('matrix/cancel',{job_id:selected});if(v!==revision||get('job-id').value.trim()!==selected)throw Error(ft('任务选择已改变，取消响应已丢弃'));job=updated;displayJob(job);});
  get('resume').onclick=()=>run(async()=>{if(!job||get('job-id').value.trim()!==job.job_id)throw Error(ft('先读取并核对此任务'));const selected=job.job_id,v=revision;const loaded=await api('matrix/status',{job_id:selected});if(v!==revision||get('job-id').value.trim()!==selected)throw Error(ft('任务选择已改变，旧响应已丢弃'));job=loaded;set('plan',job.plan);if(!job.resume_supported)throw Error(ft('当前文件不可验证续传；不会自动从头重新下载'));if(!ask(ft('确认继续此任务？\n{name}\n{url}\n已接收 {bytes} bytes，上限 {max} bytes。仅在服务器版本和 Range 验证通过时续传。',{name:job.source_name,url:job.source_url,bytes:job.bytes_downloaded,max:job.max_bytes})))return;const resumed=await api('matrix/resume',{job_id:selected,confirmed:true,plan_sha256:job.plan_sha256});if(v!==revision||get('job-id').value.trim()!==selected)throw Error(ft('任务选择已改变，续传响应已丢弃；已确认的续传可能仍在运行'));job=resumed;displayJob(job);});
  get('accession').addEventListener('input',reset);
  get('example').onclick=()=>{get('accession').value='GSE60450';reset();set('status',ft('已填入公开示例GSE60450。请点击“查找矩阵文件”；不会自动下载。'));};
  get('search').onclick=()=>run(async()=>{
    const term=get('query').value.trim();if(!term||term.length>300)throw Error(ft('请输入1–300字符的公开检索词'));
    const v=revision;const result=await api('search',{term});if(v!==revision||term!==get('query').value.trim())throw Error(ft('选择已改变，旧检索结果已丢弃'));get('search-results').replaceChildren();
    for(const record of result.records||[]){if(!validGSE(record.accession))continue;const row=doc.createElement('p');row.textContent=`${record.accession} · ${record.title||''} · ${record.sample_count??ft('未知')} samples `;const button=doc.createElement('button');button.type='button';labelNode(button,'选择该GSE');button.onclick=()=>run(async()=>{if(!paperAccessions.includes(record.accession))paperContext=null;get('accession').value=record.accession;reset();const selectedRevision=revision;const selected=await api('processed/resolve',{accession:record.accession});unchanged(selectedRevision,record.accession);renderManifest(selected,record.accession,selectedRevision);});row.append(button);get('search-results').append(row);}
    set('status',get('search-results').children.length?ft('请选择一个GSE；检索没有下载数据。'):ft('没有可选GSE结果，请调整检索词或直接输入GSE编号。'));
  });
  function renderManifest(result,a,v){
    if(!result.manifest||result.manifest.accession!==a||!Array.isArray(result.manifest.files)||typeof result.manifest_id!=='string')throw Error(ft('矩阵清单格式无效'));
    manifest=result;set('series','{accession} · {title} · {count} GSM样本',{accession:a,title:result.manifest.title||'',count:result.manifest.sample_accessions?.length??0});
    for(const file of result.manifest.files){
      const row=doc.createElement('div');row.className='card';const title=doc.createElement('p');labelNode(title,'{name} | {format} | {size} | 数据类型待来源确认',{name:file.name,format:file.format_hint,size:Number.isSafeInteger(file.bytes)?file.bytes.toLocaleString()+' bytes':ft('大小未知')});row.append(title);
      const source=doc.createElement('p');labelNode(source,'来源：{url}',{url:file.url});row.append(source);
      const button=doc.createElement('button');button.type='button';button.setAttribute('data-agent-file',file.id);button.setAttribute('data-agent-name',file.name);labelNode(button,'查看下载计划并确认');
      button.disabled=/\.(fastq|fq|sra|bam|cram)(\.gz)?$/i.test(file.name||'');
      if(button.disabled){const reason=doc.createElement('p');labelNode(reason,'这是原始reads/比对文件，本矩阵入口不下载。');row.append(reason);}
      button.onclick=()=>run(async()=>{
        unchanged(v,a);if(manifest!==result||button.disabled)throw Error(ft('请重新选择有效文件'));
        const cap=Number(get('budget').value);if(!Number.isFinite(cap)||cap<0.001||cap>100)throw Error(ft('下载额度应为0.001–100 GiB，且仍受可用磁盘限制'));
        const prepared=await api('matrix/plan',{manifest_id:result.manifest_id,file_id:file.id,max_bytes:Math.floor(cap*1024**3)});unchanged(v,a);if(Number(get('budget').value)!==cap)throw Error(ft('下载额度已改变，请重新审核计划'));set('plan',prepared.plan);
        if(prepared.plan.status!=='ready_for_confirmation'||!prepared.plan.download_enabled)throw Error((prepared.plan.blockers||[]).join('; ')||ft('当前文件不能下载'));
        if(!getAgentDownloadPermission()&&!ask(ft('下载原文件 {name}\n大小：{size} bytes\n本次最大额度：{cap} GiB\n{url}\n注意：{warnings}\n文件内容未必是适用的矩阵。不自动解包、调用 AI、下载其他文件或执行分析。是否确认？',{name:file.name,size:file.bytes??ft('未知'),cap,url:file.url,warnings:(prepared.plan.warnings||[]).join('; ')}))){set('status',ft('已取消，没有发起下载。'));return;}
        const started=await api('matrix/start',{plan_id:prepared.plan_id,plan_sha256:prepared.plan_sha256,confirmed:true});if(v!==revision||a!==accession())throw Error(ft('选择已改变；已确认的下载可能仍在运行。请保存任务 ID 后读取进度或取消：{id}',{id:started.job_id}));job=started;jobAccession=a;automaticJobs.add(job.job_id);get('job-id').value=job.job_id;displayJob(job);
      });row.append(button);get('files').append(row);
    }
    set('status',result.manifest.files.length?ft('请选择具体文件并确认后下载。文件名/整数表不证明raw counts。'):ft('未发现Series级补充文件，不代表没有处理矩阵。'));
  }
  get('resolve').onclick=()=>run(async()=>{
    const a=accession();if(!validGSE(a))throw Error(ft('请输入有效GSE编号，例如GSE60450'));reset();const v=revision;const result=await api('processed/resolve',{accession:a});unchanged(v,a);
    renderManifest(result,a,v);
  });
  doc.defaultView?.addEventListener('emp:matrix-pick',event=>run(async()=>{
    const detail=event.detail||{},a=detail.accession;
    if(typeof a!=='string'||!validGSE(a))throw Error(ft('请输入有效GSE编号，例如GSE60450'));
    get('accession').value=a;reset();paperContext=detail.paper||null;const v=revision;
    const result=detail.result||await api('processed/resolve',{accession:a});unchanged(v,a);renderManifest(result,a,v);
  }));
  doc.defaultView?.addEventListener('emp:matrix-search',event=>{get('query').value=event.detail?.term||'';paperContext=event.detail?.paper||null;paperAccessions=event.detail?.paperAccessions||[];get('search').click();});
  async function readAnnotations(){
    const a=accession();if(!validGSE(a))throw Error(ft('请先输入有效GSE编号'));const v=revision;
    if(job?.status==='completed'&&jobAccession===a&&!download?.inspection){const checked=await api('matrix/preview',{job_id:job.job_id});unchanged(v,a);download={...job.receipt,inspection:checked.inspection};set('receipt',download);}
    const result=await api('processed/annotations',{accession:a,columns:job?.status==='completed'&&artifactJobId===job.job_id&&jobAccession===a?(download?.inspection?.column_labels||[]):[]});unchanged(v,a);
    if(!Array.isArray(result.records)||!Array.isArray(result.matches))throw Error(ft('样本信息格式无效'));annotations=result;get('samples').replaceChildren();
    const source=doc.createElement('p');labelNode(source,'注释来源：{url} | SHA-256：{sha} | {note}',{url:result.source_url,sha:result.sha256,note:result.provenance_download_note||''});get('samples').append(source);
    const table=doc.createElement('table');const header=doc.createElement('tr');for(const label of [ft('矩阵列 / GSM'),ft('匹配'),ft('标题'),ft('原始特征信息')]){const th=doc.createElement('th');labelNode(th,label);header.append(th);}table.append(header);
    const rows=result.matches.length?result.matches.map(x=>({label:x.column,status:x.status,sample:x.sample})):result.records.map(x=>({label:x.accession,status:ft('未与矩阵匹配'),sample:x}));
    for(const row of rows){const tr=doc.createElement('tr');for(const value of [row.label,row.status,row.sample?.title||'',(row.sample?.characteristics||[]).join(' | ')]){const td=doc.createElement('td');td.textContent=value;tr.append(td);}table.append(tr);}get('samples').append(table);get('export-samples').disabled=false;const exportPath=result.provenance_download_url;const exportReady=typeof exportPath==='string'&&/^\/api\/public-data\/matrix\/exports\/[a-f0-9-]{36}$/.test(exportPath);get('export-provenance').disabled=!exportReady;get('export-provenance').setAttribute('aria-disabled',String(!exportReady));if(exportReady){get('export-provenance').href=exportPath;get('export-provenance').download=`${a}_sample_provenance.json`;}else{get('export-provenance').removeAttribute('href');}
    const exact=result.matches.filter(x=>x.status==='exact').length;set('status','已读取 {count} 个样本；矩阵列精确匹配 {exact}/{total}。不推断分组，未匹配项需人工核对。',{count:result.records.length,exact,total:result.matches.length});
    remember();
  }
  get('annotations').onclick=()=>run(readAnnotations);
  function detachStudy(){
    remember();globalThis.clearTimeout?.(pollTimer);reset();clearArtifacts();job=null;jobAccession=null;manifest=null;paperContext=null;paperAccessions=[];
    get('job-id').value='';get('accession').value='';get('query').value='';get('search-results').replaceChildren();set('series','');set('plan','');set('job-result','');get('resume').disabled=true;get('open-workbench').disabled=true;
    set('status','当前文章与数据选择已清空；原下载文件保留，可从历史下载恢复。');
    if(get('history'))get('history').value='';
  }
  doc.defaultView?.addEventListener('emp:study-reset',detachStudy);
  if(get('history-refresh'))get('history-refresh').onclick=()=>run(async()=>{const data=await api('matrix/history',{});get('history').replaceChildren();const empty=doc.createElement('option');empty.value='';labelNode(empty,'选择历史下载（保留原文件）');get('history').append(empty);for(const item of data.jobs||[]){const option=doc.createElement('option');option.value=item.job_id;option.textContent=`${item.source_name} · ${item.status} · ${item.created_at}`;get('history').append(option);}set('status','历史下载只恢复引用，不重新下载，也不删除文件。');});
  if(get('history'))get('history').onchange=()=>{const id=get('history').value;if(!id)return;detachStudy();get('history').value=id;const context=studyContexts.get(id);paperContext=context?.paper||null;get('job-id').value=id;get('refresh').click();};
  get('export-samples').onclick=()=>run(async()=>{saveTSV();set('status',ft('已生成样本TSV下载；来源JSON请单独点击保存。'));});
  get('export-provenance').onclick=(event)=>{if(!annotations||get('export-provenance').disabled){event?.preventDefault?.();set('status',ft('请重新读取样本信息以生成有效来源JSON链接。'));}};
  get('export-receipt').onclick=()=>{if(download)saveJSON(download,`${jobAccession||accession()}_matrix_receipt.json`);};
  for(const button of doc.querySelectorAll('[data-open-matrix]'))button.addEventListener('click',()=>doc.querySelector('.nav-item[data-page="matrix"]')?.click());
  set('status',ft('直接在主页面查找和下载处理矩阵。不会自动下载原始reads、调用AI或执行分析。'));
  get('open-workbench').disabled=true;
}
if(typeof document!=='undefined')initMatrixPanel();
