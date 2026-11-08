import {resultRows,snapshotPlot,availableSnapshotPlots} from './analysis_snapshot_model.mjs';
const node=(tag,text)=>{const el=document.createElement(tag);if(text!==undefined)el.textContent=text;return el;};
function figure(model){
 const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.setAttribute('viewBox','0 0 900 650');svg.setAttribute('width','900');svg.setAttribute('height','650');svg.style.maxWidth='100%';svg.style.height='auto';svg.style.background='white';
 const add=(tag,attrs={},text)=>{const el=document.createElementNS(svg.namespaceURI,tag);for(const [key,value]of Object.entries(attrs))el.setAttribute(key,String(value));if(text!==undefined)el.textContent=text;svg.append(el);return el;};
 add('text',{x:35,y:35,'font-size':21,fill:'#172033'},model.title);
 if(model.type==='scatter'){
  const xs=model.points.map(p=>p.x),ys=model.points.map(p=>p.y),minX=Math.min(...xs),maxX=Math.max(...xs),minY=Math.min(...ys),maxY=Math.max(...ys);
  add('line',{x1:90,y1:550,x2:820,y2:550,stroke:'#475569'});add('line',{x1:90,y1:80,x2:90,y2:550,stroke:'#475569'});
  for(let i=0;i<=4;i++){const x=minX+(maxX-minX)*i/4,y=minY+(maxY-minY)*i/4;add('text',{x:90+730*i/4,y:573,'font-size':12,'text-anchor':'middle'},x.toPrecision(3));add('text',{x:80,y:554-470*i/4,'font-size':12,'text-anchor':'end'},y.toPrecision(3));}
  for(const point of model.points)add('circle',{cx:90+730*(point.x-minX)/(maxX-minX||1),cy:550-470*(point.y-minY)/(maxY-minY||1),r:4,fill:point.color||'#0f766e','fill-opacity':.7});
  add('text',{x:450,y:610,'font-size':16},model.xLabel);add('text',{x:30,y:310,'font-size':16,transform:'rotate(-90 30 310)'},model.yLabel);
 }else if(model.type==='bubble'){
  const maximum=Math.max(.01,...model.dots.map(dot=>dot.ratio)),countMax=Math.max(1,...model.dots.map(dot=>dot.count)),step=480/model.dots.length;
  model.dots.forEach((dot,i)=>{const y=90+i*step;add('text',{x:310,y:y+5,'font-size':12,'text-anchor':'end'},dot.label.slice(0,38));add('circle',{cx:330+440*dot.ratio/maximum,cy:y,r:Math.max(2,13*Math.sqrt(dot.count/countMax)),fill:dot.p!==null&&dot.p<.05?'#b91c1c':'#64748b','fill-opacity':.75});});
  for(let i=0;i<=4;i++)add('text',{x:330+440*i/4,y:605,'font-size':12,'text-anchor':'middle'},(maximum*i/4).toPrecision(3));add('text',{x:500,y:635,'font-size':16},'GeneRatio');
 }else if(model.type==='network'){
  const places=new Map(model.labels.map((label,i)=>{const angle=2*Math.PI*i/model.labels.length;return[label,{x:450+220*Math.cos(angle),y:320+220*Math.sin(angle)}];}));
  for(const pair of model.pairs){if(pair.a===pair.b)continue;const a=places.get(pair.a),b=places.get(pair.b);add('line',{x1:a.x,y1:a.y,x2:b.x,y2:b.y,stroke:pair.r>=0?'#b91c1c':'#1d4ed8','stroke-width':Math.max(.3,Math.abs(pair.r)*3),'stroke-opacity':.4});}
  for(const [label,point]of places){add('circle',{cx:point.x,cy:point.y,r:7,fill:'#0f766e'});add('text',{x:point.x+10,y:point.y+4,'font-size':11},label.slice(0,22));}
 }else if(model.type==='correlation'){
  const size=450/Math.max(1,model.labels.length),lookup=new Map(model.labels.map((label,i)=>[label,i]));
  for(const pair of model.pairs){const intensity=Math.round(255-175*Math.abs(pair.r)),fill=pair.r>=0?`rgb(255,${intensity},${intensity})`:`rgb(${intensity},${intensity},255)`;add('rect',{x:210+lookup.get(pair.b)*size,y:80+lookup.get(pair.a)*size,width:size,height:size,fill});}
  model.labels.forEach((label,i)=>{add('text',{x:203,y:80+(i+.7)*size,'font-size':Math.max(9,Math.min(13,size*.6)),'text-anchor':'end'},label.slice(0,24));add('text',{x:210+(i+.5)*size,y:542,'font-size':10,transform:`rotate(55 ${210+(i+.5)*size} 542)`},label.slice(0,24));});
  add('text',{x:690,y:95,'font-size':13},'−1 蓝 / 0 白 / +1 红');
 }else{
  const bars=model.bars.slice(0,24),minimum=Math.min(0,...bars.map(row=>row.value)),maximum=Math.max(1,...bars.map(row=>row.value)),height=490/Math.max(1,bars.length),x=value=>320+440*(value-minimum)/(maximum-minimum);
  bars.forEach((row,i)=>{const y=75+i*height;add('text',{x:310,y:y+height*.6,'font-size':12,'text-anchor':'end'},row.label.slice(0,38));add('rect',{x:Math.min(x(0),x(row.value)),y,width:Math.abs(x(row.value)-x(0)),height:height*.72,fill:row.value<0?'#1d4ed8':'#0f766e'});add('text',{x:x(row.value)+(row.value<0?-5:5),y:y+height*.6,'font-size':12,'text-anchor':row.value<0?'end':'start'},Number(row.value.toPrecision(4)));});
 }
 return svg;
}
export function mountAnalysisSnapshots(root,{request,showTable,attachAI}){
 if(!root)return null;
 const unified=document.getElementById?.('viz-snapshot-select');
 const section=document.getElementById?.('page-visualization');
 const select=unified||node('select'),plotType=node('select');
 const controls=node('div'),refresh=unified?document.getElementById('viz-refresh-all-snapshots'):node('button','刷新分析快照');
 const render=node('button','绘制所选分析快照'),download=node('button','下载 SVG'),status=node('p'),chart=node('div'),table=node('div');
 controls.className='wb-actions';table.id='analysis-snapshot-table';chart.id='analysis-snapshot-plot';status.setAttribute('role','status');download.disabled=true;
 for(const button of [refresh,render,download]){if(button){button.type='button';button.className='btn btn-outline';}}
 plotType.id='analysis-snapshot-chart-type';plotType.setAttribute('aria-label','当前分析可用图形');plotType.disabled=true;
 if(unified){plotType.hidden=true;controls.append(render,download,plotType);root.hidden=true;}
 else{select.id='analysis-snapshot-select';select.setAttribute('aria-label','分析结果快照');controls.append(select,refresh,plotType,render,download);}
 root.append(controls,status,chart,table);
 let jobs=[],version=0,currentSvg=null,cached=null,cachedId=null;
 const jobId=()=>unified?(select.value.startsWith('job:')?select.value.slice(4):''):select.value;
 const tabFor=kind=>/dimension/.test(kind)?'viz-scatter':/correlation/.test(kind)?'viz-correlation-matrix':/cluster/.test(kind)?'viz-cluster-summary':/enrich/.test(kind)?'viz-bubble':/differential/.test(kind)?'viz-volcano':'viz-barplot';
 const activeTab=()=>section?.querySelector('.tab-bar .tab.active')?.dataset.tab;
 function requestedMode(job){
  if(!unified)return plotType.value||'default';
  const tab=activeTab(),kind=job.kind||'';
  if(tab==='viz-bubble')return 'bubble';
  if(tab==='viz-effect-bars')return 'effect_bar';
  if(tab==='viz-volcano')return 'volcano';
  if(tab==='viz-correlation-network')return /correlation/.test(kind)?'network':'unsupported';
  if(tab==='viz-correlation-matrix'||tab==='viz-heatmap')return /correlation/.test(kind)?'default':'unsupported';
  if(tab==='viz-scatter')return /dimension/.test(kind)?'default':'unsupported';
  if(tab==='viz-cluster-summary')return /cluster/.test(kind)?'default':'unsupported';
  if(tab==='viz-barplot')return /differential/.test(kind)?'effect_bar':/cluster|enrich/.test(kind)?'default':'unsupported';
  return 'unsupported';
 }
 function moveOutput(){
  if(!unified)return;
  root.hidden=!jobId();
  const panel=document.getElementById(activeTab());
  if(panel&&panel!==root.parentElement)panel.append(root);
 }
 async function load(){
  const previous=select.value;
  try{
   const value=await request('GET','/jobs?limit=500',null,false,{skipSessionHeader:true});jobs=value.jobs||[];
   let group;
   if(unified){select.querySelector('optgroup[data-analysis-jobs]')?.remove();group=node('optgroup');group.label='后台分析结果';group.dataset.analysisJobs='true';}
   else{select.replaceChildren(node('option','请选择已完成的后台分析'));select.children[0].value='';group=select;}
   for(const job of jobs){
    const when=job.finished?new Date(job.finished*1000).toLocaleString():'';
    const option=node('option',`${job.experiment||'会话'} · ${job.kind} · ${job.parameters?.method||''} · ${when} · ${job.status} · ${job.id}`);
    option.value=unified?'job:'+job.id:job.id;option.disabled=job.status!=='done';group.append(option);
   }
   if(unified)select.append(group);
   if(unified||jobs.some(job=>job.id===previous))select.value=previous;
   status.textContent=`已读取 ${jobs.filter(job=>job.status==='done').length} 个完成任务。运行中或失败的任务已标记，尚不能出图。`;
  }catch(error){status.textContent=error.message;}
 }
 function clearResult(){version++;cached=null;cachedId=null;plotType.replaceChildren();plotType.disabled=true;currentSvg=null;download.disabled=true;chart.replaceChildren();table.replaceChildren();}
 async function draw(){
  const id=jobId(),job=jobs.find(job=>job.id===id);
  if(!job||job.status!=='done'){status.textContent='请在上方选择已完成的分析结果快照。';return;}
  moveOutput();const current=++version;render.disabled=true;currentSvg=null;download.disabled=true;status.textContent='正在读取已保存结果…';
  try{
   const result=cachedId===id?cached:await request('GET',`/jobs/${encodeURIComponent(id)}/result`,null,false,{skipSessionHeader:true});
   if(current!==version)return;
   if(cachedId!==id){cachedId=id;cached=result;plotType.replaceChildren();const choices=availableSnapshotPlots(job.kind,result);if(typeof result.plot==='string'&&result.plot.startsWith('data:image/png;base64,'))choices.unshift({id:'original',label:'任务保存的原始图形'});for(const choice of choices){const option=node('option',choice.label);option.value=choice.id;plotType.append(option);}plotType.disabled=!choices.length;}
   chart.replaceChildren();const rows=resultRows(result);showTable(table.id,rows,500,{aiContext:{analysis_type:job.kind,source_job:id}});
   const mode=requestedMode(job);
   if(mode==='unsupported')throw Error('此图形模式与所选分析快照不匹配。请选择对应的降维、相关性、聚类、富集或差异结果，或切换图形标签。');
   const png=result.plot;
   if(mode==='original'&&typeof png==='string'&&/^data:image\/png;base64,[A-Za-z0-9+/=\s]+$/.test(png)){const img=node('img');img.src=png;img.style.maxWidth='100%';chart.append(img);status.textContent=`已读取快照 ${id} 的原始图形。`;}
   else{const model=snapshotPlot(job.kind,result,mode);currentSvg=figure(model);chart.append(currentSvg,node('p',model.note));download.disabled=false;status.textContent=`绘图来源：${id} · ${job.experiment||''}；使用已保存的数值。`;}
   attachAI(chart,{analysis_type:job.kind,kind:'plot',source_job:id});
  }catch(error){if(current===version){chart.replaceChildren();status.textContent=error.message;}}
  finally{if(current===version)render.disabled=false;}
 }
 function chooseResult(){
  clearResult();moveOutput();
  if(!jobId())return;
  const job=jobs.find(job=>job.id===jobId());
  const tab=job&&section?.querySelector(`.tab[data-tab="${tabFor(job.kind)}"]`);
  if(unified&&tab)tab.click();else draw();
 }
 if(unified)select.addEventListener('change',chooseResult);else select.onchange=clearResult;
 if(refresh)refresh.onclick=async()=>{if(unified)window.dispatchEvent(new CustomEvent('emp:refresh-prepare-snapshots'));await load();};
 render.onclick=draw;plotType.onchange=()=>render.click();
 download.onclick=()=>{if(!currentSvg)return;const url=URL.createObjectURL(new Blob([new XMLSerializer().serializeToString(currentSvg)],{type:'image/svg+xml;charset=utf-8'})),link=node('a');link.href=url;link.download=`analysis-${jobId()}.svg`;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};
 section?.querySelector('.tab-bar')?.addEventListener('click',event=>{if(event.target.closest('.tab')&&jobId()){moveOutput();draw();}});
 const plotButtons=new Set(['btn-barplot','btn-boxplot','btn-heatmap','btn-heatmap-custom','btn-deg-heatmap','btn-volcano','btn-scatter','btn-alpha-plot','btn-structure']);
 section?.addEventListener('click',event=>{const button=event.target.closest('button');if(jobId()&&plotButtons.has(button?.id)){event.preventDefault();event.stopImmediatePropagation();moveOutput();draw();}},true);
 window.addEventListener('emp:page-view',event=>{if(event.detail?.page==='visualization'){load();moveOutput();}});
 window.addEventListener('emp:select-analysis-snapshot',async event=>{await load();if(jobs.some(job=>job.id===event.detail?.job_id)){select.value=(unified?'job:':'')+event.detail.job_id;chooseResult();}});
 return {refresh:load};
}
