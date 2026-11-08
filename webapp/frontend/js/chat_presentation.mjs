// Construct DOM nodes only: model HTML, images and unsafe URLs never execute.
const make=(doc,tag,text,cls)=>{const n=doc.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;};
const safeURL=value=>{try{const u=new URL(value);return ['https:','http:'].includes(u.protocol)?u.href:null;}catch{return null;}};
function inline(parent,text,doc){
  const pattern=/(`[^`\n]+`|\*\*[^*\n]+\*\*|\[[^\]\n]+\]\([^\s)]+\))/g;let last=0;
  for(const m of String(text).matchAll(pattern)){
    if(m.index>last)parent.append(make(doc,'span',text.slice(last,m.index)));
    const token=m[0];
    if(token.startsWith('`'))parent.append(make(doc,'code',token.slice(1,-1)));
    else if(token.startsWith('**'))parent.append(make(doc,'strong',token.slice(2,-2)));
    else {const parts=/^\[([^\]]+)\]\(([^)]+)\)$/.exec(token),url=safeURL(parts[2]);const a=make(doc,url?'a':'span',parts[1]);if(url){a.href=url;a.target='_blank';a.rel='noopener noreferrer';}parent.append(a);}
    last=m.index+token.length;
  }
  if(last<text.length)parent.append(make(doc,'span',text.slice(last)));
}
export function renderRichText(root,value,doc=globalThis.document){
  const lines=String(value||'').slice(0,16000).replace(/\r\n?/g,'\n').split('\n');root.replaceChildren();let i=0;
  const cells=line=>line.trim().replace(/^\||\|$/g,'').split('|').map(x=>x.trim());
  const separator=line=>/^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$/.test(line||'');
  while(i<lines.length){
    const line=lines[i];if(!line.trim()){i++;continue;}
    if(/^\s*```/.test(line)){const pre=make(doc,'pre'),code=make(doc,'code'),body=[];i++;while(i<lines.length&&!/^\s*```/.test(lines[i]))body.push(lines[i++]);code.textContent=body.join('\n');pre.append(code);root.append(pre);i++;continue;}
    if(line.includes('|')&&separator(lines[i+1])){
      const wrap=make(doc,'div',undefined,'agent-table-scroll'),table=make(doc,'table'),head=make(doc,'thead'),tr=make(doc,'tr');
      for(const c of cells(line)){const th=make(doc,'th');inline(th,c,doc);tr.append(th);}head.append(tr);table.append(head);i+=2;const body=make(doc,'tbody');
      while(i<lines.length&&lines[i].includes('|')&&lines[i].trim()){const row=make(doc,'tr');for(const c of cells(lines[i++])){const td=make(doc,'td');inline(td,c,doc);row.append(td);}body.append(row);}table.append(body);wrap.append(table);root.append(wrap);continue;
    }
    const heading=/^\s*#{1,6}\s+(.+)$/.exec(line);if(heading){const h=make(doc,'h4');inline(h,heading[1],doc);root.append(h);i++;continue;}
    const list=/^\s*(?:[-*+]\s+|\d+[.)]\s+)/.exec(line);if(list){const ordered=/^\s*\d/.test(line),ul=make(doc,ordered?'ol':'ul');while(i<lines.length&&/^\s*(?:[-*+]\s+|\d+[.)]\s+)/.test(lines[i])){const li=make(doc,'li');inline(li,lines[i++].replace(/^\s*(?:[-*+]\s+|\d+[.)]\s+)/,''),doc);ul.append(li);}root.append(ul);continue;}
    if(/^\s*[-*_]{3,}\s*$/.test(line)){root.append(make(doc,'hr'));i++;continue;}
    const p=make(doc,'p');inline(p,line,doc);root.append(p);i++;
  }
  return root;
}
export function appendChatMessage(root,role,text,{doc=globalThis.document,english=false}={}){
  const card=make(doc,'article',undefined,'agent-message agent-message--'+role);card.append(make(doc,'div',role==='user'?(english?'You':'我'):'AI','agent-message-role'));
  const body=make(doc,'div',undefined,'agent-message-body');if(role==='user')body.textContent=String(text);else renderRichText(body,text,doc);card.append(body);root.append(card);return card;
}
const LABELS={provider_request:['正在生成方案','Preparing response'],tool_started:['正在调用工具','Calling tool'],tool_finished:['工具已返回','Tool returned'],completed:['本轮完成','Turn complete'],error:['本轮未完成','Turn incomplete'],round_limit:['已达到工具调用上限','Tool limit reached'],configuration_changed:['模型配置已变化','Model configuration changed'],unconfigured:['请先加载模型配置','Load model settings first']};
const TOOLS={propose_count_workflow:'生成分析步骤草案',fill_page_fields:'准备页面参数',request_page_action:'请求页面操作',set_heatmap_size:'调整热图尺寸',search_papers:'检索论文',fetch_paper_abstract:'读取论文摘要',discover_processed:'查找处理矩阵',discover_pride_files:'查找蛋白质组文件',search_metadata:'检索数据库',resolve_accession:'核对数据编号',get_selected_context:'读取已选数据摘要',validate_plan:'检查流程依赖'};
export function createActivity(root,{doc=globalThis.document,english=false}={}){
  const card=make(doc,'details',undefined,'agent-activity');card.open=true;const summary=make(doc,'summary',english?'Reading page and preparing response':'正在读取页面并准备回应');const list=make(doc,'ol');card.append(summary,list);root.append(card);let last='';
  return {card,update(events=[]){const key=JSON.stringify(events);if(key===last)return;last=key;list.replaceChildren();for(const event of events.slice(-24)){const label=(LABELS[event.stage]||[event.stage,event.stage])[english?1:0];const name=event.tool?(english?event.tool:(TOOLS[event.tool]||event.tool)):'';const state=event.status&&event.status!=='ok'?' · '+event.status:'';list.append(make(doc,'li',label+(name?'：'+name:'')+state+(Number.isFinite(event.duration_ms)?' · '+(event.duration_ms/1000).toFixed(1)+'s':'')));}if(events.length){const final=events.at(-1);summary.textContent=(LABELS[final.stage]||[final.stage,final.stage])[english?1:0];}},note(text){list.append(make(doc,'li',text));},finish(ok){summary.textContent=english?(ok?'Actions and results':'Action needs attention'):(ok?'本轮操作与结果':'本轮需要处理');card.open=!ok;}};
}
export function appendWorkflowCard(root,proposal,onApply,{doc=globalThis.document,english=false}={}){
  if(!proposal?.steps?.length)return;
  const card=make(doc,'section',undefined,'agent-workflow-card');card.append(make(doc,'h4',english?'Workflow draft · not executed':'分析流程草案 · 尚未执行'));const list=make(doc,'ol');
  const names={qc:'计数质量检查',normalize:'Size-factor 归一化',pca:'PCA',deseq2:'DESeq2 差异分析',edger:'edgeR 差异分析',heatmap:'热图'};
  for(const step of proposal.steps){const row=make(doc,'li');row.append(make(doc,'strong',english?step.operation:(names[step.operation]||step.operation)));const params=Object.entries(step.parameters||{}).map(([k,v])=>k+' = '+String(v)).join(' · ');if(params)row.append(make(doc,'small',params));list.append(row);}card.append(list);
  if(onApply){const button=make(doc,'button',english?'Use draft in Workbench':'将草案填入工作台','btn btn-primary');button.type='button';button.onclick=onApply;card.append(button);}root.append(card);return card;
}
export function appendTaskReceipt(root,id,{doc=globalThis.document,english=false}={}){
  const card=make(doc,'section',undefined,'agent-task-receipt'),title=make(doc,'strong',english?'Background task accepted':'后台任务已接收'),state=make(doc,'p',english?'Waiting for server progress':'等待服务端进度'),progress=make(doc,'progress');progress.max=100;progress.value=0;
  card.append(title,make(doc,'small',id),progress,state);root.append(card);
  return {card,update(job){if(!job)return;const pct=Math.max(0,Math.min(100,Number(job.progress)||0));progress.value=pct;const labels={queued:['排队中','Queued'],running:['运行中','Running'],done:['已完成','Completed'],error:['失败','Failed'],cancelled:['已取消','Cancelled']};state.textContent=(labels[job.status]||[job.status,job.status])[english?1:0]+' · '+pct+'%'+(job.message?' · '+String(job.message).slice(0,300):'');}};
}
