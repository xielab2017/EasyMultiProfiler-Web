// Plot directory describes actual routes, separately identifying live methods.
const ALL_MATRIX=['transcriptomics','proteomics','metabolomics','microbiome_16s','metagenomics'];
const ITEMS=[
 {id:'ordination',label:'PCA / PCoA · 现有 R',omics:ALL_MATRIX,tab:'viz-scatter'},
 {id:'heatmap',label:'聚类热图 · 现有 R',omics:ALL_MATRIX,tab:'viz-heatmap'},
 {id:'boxplot',label:'箱线图 · 现有 R',omics:ALL_MATRIX,tab:'viz-boxplot'},
 {id:'volcano',label:'火山图 · 现有 R',omics:['transcriptomics','proteomics','metabolomics','metagenomics'],tab:'viz-volcano'},
 {id:'enrichment',label:'GO / KEGG 气泡图 · R 绘图',omics:['transcriptomics','proteomics','metagenomics'],tab:'viz-enrichment-dotplot'},
 {id:'gsea',label:'GSEA · R 绘图',omics:['transcriptomics','proteomics','metagenomics'],tab:'viz-gsea'},
 {id:'ternary',label:'三元组成图 · 实时方法',omics:['microbiome_16s','metagenomics'],tab:'viz-ternary',live:true},
 {id:'de_scatter',label:'差异显著性图 · 实时方法',omics:['transcriptomics','proteomics','metabolomics'],tab:'viz-de-significance',live:true},
 {id:'microbiome',label:'组成 / 多样性 · 现有 R',omics:['microbiome_16s','metagenomics'],tab:'viz-structure'},
 {id:'tracks',label:'ChIP 信号轨道 · 现有 R / deepTools',omics:['chipseq'],page:'chipseq_downstream'},
 {id:'clinical',label:'临床相关与生存图 · 现有 R',omics:['clinical'],page:'clinical'},
];
const EN_LABELS={ordination:'PCA / PCoA · R',heatmap:'Clustered heatmap · R',boxplot:'Boxplot · R',volcano:'Volcano · R',enrichment:'GO / KEGG dotplot · R',gsea:'GSEA · R',ternary:'Ternary composition · Method library',de_scatter:'DE significance scatter · Method library',microbiome:'Composition / Diversity · R',tracks:'ChIP signal tracks · R / deepTools',clinical:'Clinical association and survival · R'};
export function figureMethodLabel(id,locale='zh'){return ['zh','zh-TW'].includes(locale)?ITEMS.find(row=>row.id===id)?.label||id:EN_LABELS[id]||id;}
export function methodLibraryDownloadUrl(path, apiBase, pageUrl) {
 const base=apiBase.replace(/\/$/,'');
 const url=new URL(path.startsWith('/api/')?base+path.slice(4):path.startsWith('/visualize/')?base+path:path,pageUrl);
 const expected=new URL(base,pageUrl);
 if(url.origin!==expected.origin||!url.pathname.startsWith(expected.pathname+'/visualize/method-library/file/'))throw Error('Unexpected figure download URL');
 return url.href;
}
export function applicableFigureMethods(omics){return ITEMS.filter(item=>item.omics.includes(omics)||!omics||omics==='all');}
export function methodLibraryPayload(method,values,{session_id,experiment,omics}){
 if(!session_id||!experiment)throw Error('请先导入并选择实验 / Import and select an experiment first.');
 const item=ITEMS.find(row=>row.id===method);
 if(!item||!item.omics.includes(omics))throw Error('此图型不适用于当前组学 / This method is not available for the selected omics.');
 const body={session_id,experiment,omics,method,width:Number(values.width),height:Number(values.height),base_size:Number(values.base_size),title:values.title||''};
 const terms=text=>String(text||'').split(/[,\n]/).map(x=>x.trim()).filter(Boolean);
 if(method==='ternary'){
  const groups=values.groups||[];
  if(!values.group_var||groups.length!==3||new Set(groups).size!==3||groups.some(x=>!x))throw Error('请选择分组列及三个不同的组 / Select three distinct groups.');
  Object.assign(body,{group_var:values.group_var,groups,top_n:Number(values.top_n),label_features:terms(values.label_features),max_point_size:Number(values.max_point_size),point_alpha:Number(values.point_alpha),group_colors:values.group_colors});
 }else Object.assign(body,{source:'current_diff',exclude_unavailable_p:values.exclude_unavailable_p===true,x_transform:values.x_transform,padj_threshold:Number(values.padj_threshold),lfc_threshold:Number(values.lfc_threshold),label_genes:terms(values.label_genes),n_labels:Number(values.n_labels),point_size:Number(values.point_size),up_color:values.up_color,down_color:values.down_color,ns_color:values.ns_color});
 return body;
}
export function initMethodLibraryVisualization({API,showPlot,navigateTo,currentColorOptions}){
 const el=id=>document.getElementById(id);if(!el('viz-method-directory'))return;
 const val=id=>el(id)?.value||'';
 const omics=()=>val('omics-pipeline');let available=false,groupVersion=0;const generating=new Set();
 const say=(prefix,text)=>{el(prefix+'-status').textContent=text;};
 function directory(){
  const locale=window._empLocale?.getLocale?.()||document.documentElement?.dataset?.empLocale||'zh',en=!['zh','zh-TW'].includes(locale);
  if(el('viz-method-directory-title'))el('viz-method-directory-title').textContent=en?'Available plot types':'适用图型';
  const style=el('viz-figure-method');for(const option of style?.options||[])if(['original','self_built'].includes(option.value))option.textContent=option.value==='original'?(en?'Original R style':'原有 R 样式'):(en?'Self-built methods':'自建方法');
  const tabs={'viz-ternary':['三元组成图','Ternary composition'],'viz-de-significance':['差异显著性图','DE significance scatter'],'viz-enrichment-dotplot':['富集气泡图','Enrichment dotplot'],'viz-gsea':['GSEA 曲线','GSEA curves']};
  for(const tab of document.querySelectorAll?.('#page-visualization .tab[data-tab]')||[]){const labels=tabs[tab.dataset.tab];if(labels)tab.textContent=labels[en?1:0];}
  const container=el('viz-method-directory-links');container.replaceChildren();
  for(const item of applicableFigureMethods(omics())){
   const button=document.createElement('button');button.type='button';button.className='btn btn-outline';button.textContent=figureMethodLabel(item.id,locale);
   button.disabled=item.live&&!available;
   button.onclick=()=>{if(item.page)navigateTo(item.page);else document.querySelector(`#page-visualization .tab[data-tab="${item.tab}"]`)?.click();};container.append(button);
  }
 }
 function updateButtons(){
  for(const prefix of ['ternary-viz','de-significance']){
   const groups=['a','b','c'].map(key=>val('ternary-viz-'+key));
   const valid=prefix!=='ternary-viz'||(!!val('ternary-viz-group')&&groups.every(Boolean)&&new Set(groups).size===3);
   el(prefix+'-generate').disabled=!available||generating.has(prefix)||!valid;
  }
 }
 async function check(){
  try{const result=await API.request('GET','/visualize/method-library/catalog');available=result.available===true;
   const message=available?'已连接自建方法库。现有 R 图沿用原绘图链路；实时方法调用当前库，不重新拟合差异模型。':'自建方法库不可用；现有 R 图仍可使用。'+(result.message||result.status||'请配置 EMP_FIGURE_METHODS_ROOT。');
   el('viz-method-library-status').textContent=message;
   if(!available){say('de-significance',message);say('ternary-viz',message);}
   else if(!generating.has('de-significance'))say('de-significance','绘图接口已连接；将读取当前实验 '+(window._emp?.currentExp||'（尚未选择）')+' 保存的差异结果。');
  }catch(error){available=false;const message='无法连接绘图接口 '+API.apiBase()+'；点击重新检查连接。'+error.message;el('viz-method-library-status').textContent=message;say('de-significance',message);say('ternary-viz',message);}
  updateButtons();directory();return available;
 }
 function displayGroupColumns(){
  const select=el('ternary-viz-group'),previous=select.value;select.replaceChildren();
  const cols=(window._emp?.coldataCols||[]).filter(column=>Number(column.n_unique)>=2);
  cols.sort((a,b)=>Number(/^(group|condition|treatment|cohort)$/i.test(b.name))-Number(/^(group|condition|treatment|cohort)$/i.test(a.name)));
  for(const column of cols){const option=document.createElement('option');option.value=column.name;option.textContent=column.name+' ('+column.n_unique+' 种取值)';select.append(option);}
  if([...select.options].some(x=>x.value===previous))select.value=previous;
  updateGroups();
 }
 async function refreshGroups(){
  const version=++groupVersion,experiment=window._emp?.currentExp,sid=localStorage.getItem('emp_session_id');
  if(!experiment||!sid){say('ternary-viz','请先导入数据并选择实验。');return;}
  try{
   const result=await API.request('GET',`/coldata/${encodeURIComponent(sid)}/${encodeURIComponent(experiment)}`);
   if(version!==groupVersion||experiment!==window._emp?.currentExp)return;
   window._emp.coldataCols=result.columns||[];displayGroupColumns();
  }catch(error){if(version===groupVersion)say('ternary-viz','分组读取失败：'+error.message);}
 }
 function updateGroups(){
  const column=(window._emp?.coldataCols||[]).find(c=>c.name===val('ternary-viz-group'));
  const raw=column?.values||[],groups=[...new Set((Array.isArray(raw)?raw:[raw]).map(String).filter(Boolean))];
  for(const [index,key]of ['a','b','c'].entries()){
   const select=el('ternary-viz-'+key),previous=select.value;select.replaceChildren();
   for(const group of groups){const option=document.createElement('option');option.value=group;option.textContent=group;select.append(option);}
   select.value=groups.includes(previous)?previous:String(groups[index]??'');
  }
  updateButtons();
  if(groups.length<3)say('ternary-viz',column?'所选分组列 '+column.name+' 只有 '+groups.length+' 个组；三元图需要三个不同的真实组，不能拆分样本凑组。':'未找到分组列，请检查当前实验的样本信息。');
  else say('ternary-viz','来源：'+(window._emp?.currentExp||'')+'；选择 A/B/C 三组，使用当前非负丰度。');
 }
 async function download(path,filename){
  const href=methodLibraryDownloadUrl(path,API.apiBase(),location.href);
  const headers={'X-Session-Id':localStorage.getItem('emp_session_id')||''};
  const token=window.EMP_API_TOKEN||localStorage.getItem('emp_api_token');if(token)headers.Authorization=`Bearer ${token}`;
  const student=localStorage.getItem('emp_student_token');if(student)headers['X-Student-Token']=student;
  const response=await fetch(href,{headers,credentials:'omit',redirect:'error'});if(!response.ok)throw Error(`Download failed: HTTP ${response.status}`);
  const objectUrl=URL.createObjectURL(await response.blob()),link=document.createElement('a');link.href=objectUrl;link.download=filename;link.click();setTimeout(()=>URL.revokeObjectURL(objectUrl),1000);
 }
 function render(prefix,result){
  if(!result.plot)throw Error('服务器未返回图形 / Server did not return a plot.');showPlot(prefix+'-output',result.plot.replace(/^data:image\/png;base64,/,''),{downloadStem:prefix});
  const toolbar=el(prefix+'-output').querySelector('.plot-toolbar');
  for(const format of ['pdf','svg','png','manifest','data']){const path=result.download_urls?.[format];if(!path)continue;if(format==='png')toolbar?.querySelector('a')?.remove();const button=document.createElement('button');button.className='btn btn-outline';button.type='button';button.textContent=format.toUpperCase();button.onclick=async()=>{try{await download(path,`${prefix}.${format==='manifest'?'json':format==='data'?'csv':format}`);}catch(error){say(prefix,error.message);}};toolbar?.append(button);}
 }
 async function generate(method,prefix){
  const button=el(prefix+'-generate');generating.add(prefix);button.disabled=true;say(prefix,'R 正在读取真实结果并绘图… / Rendering in R…');
  try{
   if(!available)throw Error('自建方法库未连接；请检查 EMP_FIGURE_METHODS_ROOT。');
   const values={width:val(prefix+'-width'),height:val(prefix+'-height'),base_size:val(prefix+'-font'),title:val(prefix+'-title')};
   if(method==='ternary')Object.assign(values,{group_var:val(prefix+'-group'),groups:['a','b','c'].map(x=>val(prefix+'-'+x)),top_n:val(prefix+'-top'),label_features:val(prefix+'-labels'),max_point_size:val(prefix+'-size'),point_alpha:val(prefix+'-alpha'),group_colors:['a','b','c'].map(x=>val(prefix+'-color-'+x))});
   else Object.assign(values,{exclude_unavailable_p:el('de-significance-exclude-na')?.checked===true,x_transform:val(prefix+'-transform'),padj_threshold:val(prefix+'-p'),lfc_threshold:val(prefix+'-fc'),label_genes:val(prefix+'-labels'),n_labels:val(prefix+'-nlabels'),point_size:val(prefix+'-size'),up_color:val(prefix+'-color-up'),down_color:val(prefix+'-color-down'),ns_color:val(prefix+'-color-ns')});
   const body={...currentColorOptions?.(),...methodLibraryPayload(method,values,{session_id:localStorage.getItem('emp_session_id'),experiment:window._emp?.currentExp,omics:omics()})};
   const result=await API.request('POST','/visualize/method-library',body,false,{timeoutMs:180000});render(prefix,result);say(prefix,`已读取 ${result.n_rows??''} 个真实条目并导出；${result.source?.excluded_unavailable_p?`排除校正 P 不可用的 ${result.source.excluded_unavailable_p} 行，清单已保存；`:''}统计结果不重新拟合。 / Rendered from actual data.`);
  }catch(error){say(prefix,error.message);}finally{generating.delete(prefix);updateButtons();}
 }
 el('ternary-viz-refresh').onclick=async()=>{await check();await refreshGroups();};
 el('de-significance-recheck')?.addEventListener('click',check);
 for(const key of ['a','b','c'])el('ternary-viz-'+key).onchange=updateButtons;el('ternary-viz-group').onchange=updateGroups;
 el('ternary-viz-generate').onclick=()=>generate('ternary','ternary-viz');el('de-significance-generate').onclick=()=>generate('de_scatter','de-significance');
 window.addEventListener('emp:locale-change',()=>{directory();if(typeof queueMicrotask==='function')queueMicrotask(directory);});
 el('omics-pipeline')?.addEventListener('change',()=>{directory();refreshGroups();});
 window.addEventListener('emp:omics-change',()=>{directory();refreshGroups();});
 window.addEventListener('emp:experiment-change',()=>{directory();refreshGroups();});
 window.addEventListener('emp:page-view',event=>{if(event.detail?.page==='visualization'){check();refreshGroups();}});
 el('page-visualization').querySelector('.tab-bar').addEventListener('click',event=>{if(['viz-ternary','viz-de-significance'].includes(event.target.closest('.tab')?.dataset.tab)){check();refreshGroups();}});
 check();refreshGroups();
}
