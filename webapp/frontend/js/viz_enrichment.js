// R-rendered enrichment plots: no client-side reconstruction of statistics.
export function initEnrichmentVisualization({API,showPlot,navigateTo,currentColorOptions=()=>({})}) {
 const byId=id=>document.getElementById(id);
 if(!byId('viz-enrichment-dotplot'))return;
 const value=id=>byId(id)?.value||'';
 const number=id=>Number(value(id));
 const sid=()=>localStorage.getItem('emp_session_id');
 let sources=[],pendingJob=null,sourceVersion=0,termVersion=0,contextVersion=0,refreshVersion=0;
 const selectedOmics=()=>value('omics-pipeline');
 const sourceScope=()=>selectedOmics()==='multiomics'?'multiomics':'single';
 const sourceOmics=item=>String(item.omics||'unknown');
 const sourceKey=item=>item.source_job==='current_gsea'?`${encodeURIComponent(item.experiment||'')}::current_gsea`:item.source_job;
 const chosenSource=prefix=>sources.find(item=>sourceKey(item)===value(prefix+'-source'));
 const recognizedOmics=new Set(['transcriptomics','proteomics','metabolomics','microbiome_16s','metagenomics','chipseq','clinical']);
 const queryOmics=()=>recognizedOmics.has(selectedOmics())||selectedOmics()==='multiomics'?selectedOmics():'';
 function sourceAllowed(item){
  if(sourceScope()==='multiomics')return true;
  const kind=sourceOmics(item),current=selectedOmics(),experiment=window._emp?.currentExp;
  if(!recognizedOmics.has(current))return item.experiment===experiment;
  return kind===current||(!recognizedOmics.has(kind)&&item.experiment===experiment);
 }
 const status=(prefix,message)=>{byId(prefix+'-status').textContent=message;};
 const splitTerms=text=>text.split(/[,\n]/).map(s=>s.trim()).filter(Boolean);
 function requestBody(prefix){
  const session_id=sid();if(!session_id)throw Error('请先导入数据以建立会话。 / Import data to establish a session.');
  const source=chosenSource(prefix);
  return {session_id,omics:selectedOmics(),scope:sourceScope(),experiment:source?.experiment||window._emp?.currentExp,
    ...currentColorOptions(),source_job:source?.source_job||'',width:number(prefix+'-width'),height:number(prefix+'-height'),
    base_size:number(prefix+'-font'),title:value(prefix+'-title')};
 }
 async function results(item){
  if(!item)throw Error('请选择有效分析来源 / Select a valid analysis source');
  const result=await API.request('POST','/visualize/enrichment/results',{session_id:sid(),source_job:item.source_job,experiment:item.experiment||window._emp?.currentExp});
  let rows=result.data||[];if(typeof rows==='string')rows=JSON.parse(rows);
  return Array.isArray(rows)?rows:[];
 }
 async function refresh(){
  if(!sid())return;
  const requestVersion=++refreshVersion;
  const previous=[value('enrich-viz-source'),value('gsea-viz-source')];
  try{
   const result=await API.request('GET',`/visualize/enrichment/sources/${encodeURIComponent(sid())}?experiment=${encodeURIComponent(window._emp?.currentExp||'')}&omics=${encodeURIComponent(queryOmics())}&scope=${sourceScope()}`);
   if(requestVersion!==refreshVersion)return;
   sources=(result.sources||[]).filter(sourceAllowed);
   for(const [index,prefix]of ['enrich-viz','gsea-viz'].entries()){
    const select=byId(prefix+'-source');select.replaceChildren();
    const empty=document.createElement('option');empty.value='';empty.textContent='请选择分析结果 / Select analysis result';select.append(empty);
    for(const item of sources){
     if(prefix==='enrich-viz'&&item.kind==='gsea')continue;
     const option=document.createElement('option');option.value=sourceKey(item);const label=item.label||`${item.experiment||''} · ${item.source_job}`;option.textContent=`${label.startsWith('['+sourceOmics(item)+']')?'':'['+sourceOmics(item)+'] '}${label}${recognizedOmics.has(sourceOmics(item))?'':' · 类型未知，请核对 / unknown type'}`;
     select.append(option);
    }
    if([...select.options].some(option=>option.value===previous[index]))select.value=previous[index];
   }
   if(pendingJob){const item=sources.find(row=>row.source_job===pendingJob&&row.experiment===window._emp?.currentExp)||sources.find(row=>row.source_job===pendingJob);if(item)for(const prefix of ['enrich-viz','gsea-viz']){const select=byId(prefix+'-source');if([...select.options].some(option=>option.value===sourceKey(item)))select.value=sourceKey(item);}pendingJob=null;}
   status('enrich-viz',sources.length?'已载入分析来源；请选择结果并生成图。 / Select a source to plot.':'暂无已完成的富集结果，请先运行 GO / KEGG 或 GSEA 分析。');
   await Promise.all([updateDotTerms(),updateGseaPathways()]);
  }catch(error){if(requestVersion===refreshVersion){status('enrich-viz',error.message);status('gsea-viz',error.message);}}
 }
 async function updateDotTerms(){
  const current=++termVersion,select=byId('enrich-viz-terms');
  const selected=new Set([...select.selectedOptions].map(option=>option.value));select.replaceChildren();
  if(!value('enrich-viz-source'))return;
  try{const rows=await results(chosenSource('enrich-viz'));if(current!==termVersion)return;
   for(const row of rows){const option=document.createElement('option');option.value=row.ID||row.id||row.Description;option.textContent=`${row.Description||row.ID} (${row.ID||''})`;option.selected=selected.has(option.value);select.append(option);}
  }catch(error){status('enrich-viz',error.message);}
 }
 function updateSetName(){
  const source=chosenSource('gsea-viz');
  const input=byId('gsea-viz-set');input.readOnly=source?.kind==='gsea';
  if(input.readOnly){const option=[...byId('gsea-viz-pathway').options].find(row=>row.value===value('gsea-viz-pathway'));input.value=option?.textContent||'';}
 }
 async function updateGseaPathways(){
  const version=++sourceVersion,select=byId('gsea-viz-pathway');select.replaceChildren();
  const source=chosenSource('gsea-viz');
  if(source?.kind!=='gsea'){
   updateSetName();
   status('gsea-viz',source?'该结果为普通富集表；请前往 GSEA 分析，或提供完整排名表绘制描述性 ES 曲线。':'选择已完成的 GSEA 来源及通路，或提供完整排名表。');return;
  }
  try{
   const rows=await results(source);if(version!==sourceVersion)return;
   for(const row of rows){const option=document.createElement('option');option.value=row.ID||row.id||row.set_id;option.textContent=row.Description||row.description||option.value;select.append(option);}
   updateSetName();
   status('gsea-viz',`已读取 ${rows.length} 个 GSEA 通路；选择通路后生成曲线。`);
  }catch(error){status('gsea-viz',error.message);}
 }
 function safeDownloadUrl(path){
  if(typeof path!=='string')throw Error('Missing download URL');
  const api=API.apiBase().replace(/\/$/,'');
  const target=path.startsWith('/api/')?api+path.slice(4):path.startsWith('/visualize/')?api+path:path;
  const result=new URL(target,location.href),base=new URL(api,location.href);
  if(result.origin!==base.origin||!result.pathname.startsWith(base.pathname+'/visualize/enrichment/file/'))throw Error('Unexpected figure download URL');
  return result.href;
 }
 async function download(path,filename){
  const headers={'X-Session-Id':sid()||''};
  const token=window.EMP_API_TOKEN||localStorage.getItem('emp_api_token');if(token)headers.Authorization=`Bearer ${token}`;
  const student=localStorage.getItem('emp_student_token');if(student)headers['X-Student-Token']=student;
  const response=await fetch(safeDownloadUrl(path),{headers,credentials:'omit',redirect:'error'});
  if(!response.ok)throw Error(`下载失败 / Download failed: HTTP ${response.status}`);
  const url=URL.createObjectURL(await response.blob()),link=document.createElement('a');link.href=url;link.download=filename;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
 }
 function showResult(prefix,result){
  if(!result.plot)throw Error('服务器没有返回图形 / No plot was returned');
  const plot=result.plot.replace(/^data:image\/png;base64,/,'');
  showPlot(prefix+'-output',plot,{downloadStem:prefix});
  const out=byId(prefix+'-output');
  // Use the authenticated enrichment file endpoint for vector and source exports.
  const toolbar=out.querySelector('.plot-toolbar');
  for(const format of ['pdf','svg','png','manifest','data']){
   if(!result.download_urls?.[format])continue;
   if(format==='png')toolbar?.querySelector('a')?.remove();
   const button=document.createElement('button');button.type='button';button.className='btn btn-outline';button.textContent=format.toUpperCase();
   button.onclick=async()=>{try{await download(result.download_urls[format],`${prefix}.${format==='manifest'?'json':format==='data'?'csv':format}`);}catch(error){status(prefix,error.message);}};
   toolbar?.append(button);
  }
 }
 async function generate(prefix,kind){
  const drawingContext=contextVersion;
  const button=byId(prefix+'-generate');button.disabled=true;status(prefix,'R 正在绘图及导出… / Rendering and exporting in R…');
  try{
   const body=requestBody(prefix);
   if(kind==='dotplot'){
    if(!body.source_job)throw Error('请选择 GO / KEGG 分析结果。 / Select an enrichment result.');
    Object.assign(body,{selected_terms:[...byId('enrich-viz-terms').selectedOptions].map(option=>option.value),top_n:number(prefix+'-top-n'),sort_by:value(prefix+'-sort'),p_cutoff:number(prefix+'-cutoff'),
     label_wrap:number(prefix+'-wrap'),max_point_size:number(prefix+'-size'),low_color:value(prefix+'-low'),high_color:value(prefix+'-high'),highlight_terms:splitTerms(value(prefix+'-highlight'))});
   }else{
    const source=chosenSource(prefix);
    Object.assign(body,{weight:number(prefix+'-weight'),line_color:value(prefix+'-line'),set_label:value(prefix+'-set')});
    if(source?.kind==='gsea'){body.set_id=value(prefix+'-pathway');if(!body.set_id)throw Error('请选择 GSEA 通路。 / Select a GSEA pathway.');}
    else{body.ranked_csv=value(prefix+'-ranked');if(!body.ranked_csv.trim())throw Error('请先运行 GSEA 分析，或提供完整基因排名表。普通富集表不能推导 ES 曲线。');}
   }
   const result=await API.request('POST',`/visualize/enrichment/${kind}`,body,false,{timeoutMs:180000});
   if(drawingContext!==contextVersion)return;
   showResult(prefix,result);status(prefix,result.note||'已生成 R 图形；可下载 PDF、SVG、PNG 与来源记录。 / R figure exported.');
  }catch(error){if(drawingContext===contextVersion)status(prefix,error.message);}finally{button.disabled=false;}
 }
 function resetSourceContext(){
  contextVersion++;sourceVersion++;termVersion++;refreshVersion++;sources=[];pendingJob=null;
  for(const prefix of ['enrich-viz','gsea-viz']){
   byId(prefix+'-source').replaceChildren();
   const output=byId(prefix+'-output');output.replaceChildren();output.classList.add('hidden');
   status(prefix,'组学已切换，正在刷新对应分析来源… / Refreshing sources for selected omics…');
  }
  byId('enrich-viz-terms').replaceChildren();byId('gsea-viz-pathway').replaceChildren();
  byId('gsea-viz-ranked').value='';byId('gsea-viz-file').value='';
  byId('gsea-viz-set').value='';byId('gsea-viz-set').readOnly=false;
  return refresh();
 }
 byId('omics-pipeline')?.addEventListener('change',resetSourceContext);
 window.addEventListener('emp:omics-change',resetSourceContext);
 byId('enrich-viz-refresh').onclick=refresh;byId('gsea-viz-refresh').onclick=refresh;
 byId('enrich-viz-generate').onclick=()=>generate('enrich-viz','dotplot');
 byId('gsea-viz-generate').onclick=()=>generate('gsea-viz','gsea');
 byId('gsea-viz-source').onchange=updateGseaPathways;
 byId('gsea-viz-pathway').onchange=updateSetName;
 byId('enrich-viz-source').onchange=()=>{byId('enrich-viz-terms').replaceChildren();updateDotTerms();};
 byId('gsea-viz-file').onchange=async event=>{const file=event.target.files?.[0],uploadContext=contextVersion;if(!file)return;try{if(file.size>10*1024*1024)throw Error('排名表最大 10 MiB / Ranked table limit: 10 MiB');const text=await file.text();if(uploadContext!==contextVersion)return;byId('gsea-viz-ranked').value=text;status('gsea-viz',`已载入 / Loaded: ${file.name}`);}catch(error){status('gsea-viz',error.message);}};
 byId('gsea-viz-analysis').onclick=()=>{navigateTo('analysis');document.querySelector('.tab[data-tab="ana-gsea"]')?.click();window.dispatchEvent(new CustomEvent('emp:open-gsea-analysis'));};
 byId('page-visualization').querySelector('.tab-bar').addEventListener('click',event=>{if(['viz-enrichment-dotplot','viz-gsea'].includes(event.target.closest('.tab')?.dataset.tab))refresh();});
 window.addEventListener('emp:plot-enrichment',async event=>{pendingJob=event.detail?.source_job||event.detail?.job_id||null;navigateTo('visualization');document.querySelector(`.tab[data-tab="${event.detail?.kind==='gsea'?'viz-gsea':'viz-enrichment-dotplot'}"]`)?.click();await refresh();});
 window.addEventListener('emp:page-view',event=>{if(event.detail?.page==='visualization'&&['viz-enrichment-dotplot','viz-gsea'].includes(document.querySelector('#page-visualization .tab.active')?.dataset.tab))refresh();});
}
