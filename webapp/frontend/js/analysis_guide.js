import {guideFor, modelQuestion} from './analysis_guide_model.mjs';
import {getLocale} from './locale.js?v=i18n-zh-default-v1';
import {request as rRequest} from './api.js?v=i18n-zh-default-v1';

const TEXT = {
  scope:['当前步骤','Current step'], local:['本地规则引导','Local guidance'],
  input:['输入准备','Input preparation'], review:['科学核对项','Scientific review'], plan:['步骤计划（待审核）','Step plan (review pending)'],
  present:['已选择 · 待核对','Selected · review pending'], missing:['待补充','Missing selection'],
  noData:['尚未选择数据','No data selected'], check:['刷新准备情况','Refresh readiness'],
  focus:['前往页面参数','Review page settings'], workbench:['在计数工作台编排','Build in Count Workbench'],
  askLabel:['你的分析问题','Your analysis question'], askPlaceholder:['例如：生成三线表前，应核对哪些变量、分组和缺失值？','For example: what groups, variable types and missingness should I review before a baseline table?'],
  ask:['请 AI 深入指导','Ask AI for guidance'], preview:['查看本步骤计划','Preview step plan'],
  pending:['尚未执行分析；页面选择不代表数据已验证。','No analysis executed; UI selections do not establish data validity.'],
  loading:['正在检查模型与 R 能力…','Checking model and R capabilities…'],
  modelMissing:['智能体模型未配置，可先使用本地引导。','Agent model is not configured; local guidance is available.'],
  modelReady:['服务端智能体模型已配置','Server agent model configured'],
  rAvailable:['R 分析服务已连接','R analysis service connected'], rUnavailable:['R 服务未连接或能力尚未确认','R service unavailable or capabilities unverified'],
  customOff:['自定义 R 执行已关闭；登记分析流程仍走各自接口。','Custom R execution is off; registered analyses use their own endpoints.'],
  customOn:['自定义 R 执行已开启；可运行性需独立审核。','Custom R execution is enabled; code runnability requires separate review.'],
  consent:['同意将本次问题与页面/步骤名称发送到 {provider}，必要的公开检索词发送到 NCBI/ENA。脚本、文件、样本标签和数值不自动发送；不要粘贴私人数据。','Send this question and page/step names to {provider}, and necessary public search terms to NCBI/ENA. Scripts, files, sample labels and values are not attached. Do not paste private data.'],
  needConsent:['请先确认本次问题的数据发送范围。','Confirm the data-sharing scope for this question first.'],
  needQuestion:['请输入 1–3500 字符的问题。','Enter a question of 1–3500 characters.'],
  busy:['正在请求智能体…','Requesting agent guidance…'],
  changed:['步骤或数据选择已改变，旧回复已丢弃；请按当前上下文重新提问。','Step or data selection changed; stale reply discarded. Ask again for the current context.'],
  unavailable:['智能体服务不可用；本地核对和页面操作仍可使用。','Agent service unavailable; local guidance and page controls remain available.'],
  apply:['将 AI 的计数流程建议送入工作台审核','Review AI count-workflow proposal in Workbench'],
  audit:['导出本次指导记录','Export guidance record'],
};
const tr=(key,vars={})=>{let text=TEXT[key][['zh','zh-TW'].includes(getLocale())?0:1];for(const [k,v]of Object.entries(vars))text=text.replaceAll(`{${k}}`,String(v));return text;};
function el(tag,text,cls){const node=document.createElement(tag);if(text!==undefined)node.textContent=text;if(cls)node.className=cls;return node;}

export function mountAnalysisGuide(root,{snapshot,focusSettings,openWorkbench}) {
  let revision=0, fingerprint='', context={}, guidance=null, agent=null, caps=null, answer=null, proposal=null, busy=false;
  const header=el('div',undefined,'analysis-guide-scope');const badge=el('span',undefined,'analysis-guide-badge');const title=el('h3');const selection=el('p',undefined,'analysis-guide-selection');const goal=el('p');header.append(badge,title,selection,goal);
  const readiness=el('section');const checks=el('section');const planArea=el('section');planArea.hidden=true;
  const actions=el('div',undefined,'analysis-guide-actions');const refresh=el('button');const focus=el('button');const preview=el('button');const workbench=el('button');
  for(const button of [refresh,focus,preview,workbench]){button.type='button';button.className='btn btn-outline';actions.append(button);}
  const pending=el('p',undefined,'analysis-guide-note');
  const services=el('div',undefined,'analysis-guide-service');
  const questionLabel=el('label');const questionCaption=el('span');const question=el('textarea');question.rows=3;question.maxLength=3500;question.id='analysis-guide-question';questionLabel.append(questionCaption,question);
  const consentLabel=el('label',undefined,'analysis-guide-consent');const consent=el('input');consent.type='checkbox';const consentText=el('span');consentLabel.append(consent,consentText);
  const ask=el('button',undefined,'btn btn-primary');ask.type='button';ask.id='analysis-guide-ask';
  const status=el('p');status.setAttribute('role','status');const output=el('div',undefined,'analysis-guide-answer');output.id='analysis-guide-answer';
  const apply=el('button',undefined,'btn btn-outline');apply.type='button';apply.hidden=true;
  const audit=el('button',undefined,'btn btn-outline');audit.type='button';audit.hidden=true;
  root.append(header,readiness,checks,actions,planArea,pending,services,questionLabel,consentLabel,ask,status,output,apply,audit);

  function render(){
    guidance=guideFor(context,getLocale());
    badge.textContent=tr('local');title.textContent=guidance.title;
    selection.textContent=`${tr('scope')}: ${context.workflow||'—'} / ${context.tab||'—'} · ${context.experimentName||tr('noData')}`;
    goal.textContent=guidance.goal;
    readiness.replaceChildren(el('h4',tr('input')));
    for(const req of guidance.requirements){const row=el('p',undefined,'analysis-guide-readiness');row.append(el('strong',tr(req.present?'present':'missing')),el('span',req.text));readiness.append(row);}
    checks.replaceChildren(el('h4',tr('review')));const checklist=el('ul');for(const text of guidance.checks)checklist.append(el('li',text));checks.append(checklist);
    planArea.replaceChildren(el('h4',tr('plan')));const steps=el('ol');for(const step of guidance.steps)steps.append(el('li',step.label));planArea.append(steps);
    for(const [button,key]of [[refresh,'check'],[focus,'focus'],[preview,'preview'],[workbench,'workbench'],[ask,'ask'],[apply,'apply'],[audit,'audit']])button.textContent=tr(key);
    workbench.hidden=!guidance.countWorkflowAvailable;pending.textContent=tr('pending');questionCaption.textContent=tr('askLabel');question.placeholder=tr('askPlaceholder');
    const serviceLines=[agent?tr(agent.status==='ready'?'modelReady':'modelMissing'):tr('loading'),caps?tr('rAvailable'):tr('rUnavailable')];
    if(caps)serviceLines.push(tr(caps.features?.arbitrary_r?'customOn':'customOff'));
    services.textContent=serviceLines.join(' · ');consentText.textContent=tr('consent',{provider:agent?.provider||'configured provider'});
    ask.disabled=busy||agent?.status!=='ready';apply.hidden=!proposal||!guidance.countWorkflowAvailable;
  }
  function refreshContext(){
    const next=snapshot();const nextKey=JSON.stringify(next);
    if(nextKey!==fingerprint){revision++;fingerprint=nextKey;context=next;consent.checked=false;proposal=null;answer=null;output.replaceChildren();audit.hidden=true;status.textContent='';}
    render();
  }
  refresh.onclick=refreshContext;
  focus.onclick=()=>focusSettings(guidance.target);
  preview.onclick=()=>{planArea.hidden=!planArea.hidden;render();};
  workbench.onclick=()=>openWorkbench();
  question.oninput=()=>{revision++;consent.checked=false;proposal=null;answer=null;apply.hidden=true;audit.hidden=true;};
  ask.onclick=async()=>{
    if(busy)return;
    if(!question.value.trim()||question.value.length>3500){status.textContent=tr('needQuestion');return;}
    if(!consent.checked){status.textContent=tr('needConsent');return;}
    const current=revision, expectedQuestion=question.value, currentContext={workflow:context.workflow,tab:context.tab};
    busy=true;ask.disabled=true;status.textContent=tr('busy');
    try{
      const response=await fetch('/api/public-data/agent/respond',{method:'POST',headers:{'Content-Type':'application/json'},credentials:'omit',redirect:'error',body:JSON.stringify({question:modelQuestion(question.value,currentContext),consent:true,expected_provider:agent.provider,expected_config_revision:agent.config_revision,context_ids:{},context_consent:false})});
      if(!response.ok)throw Error('request');const data=await response.json();
      if(current!==revision||expectedQuestion!==question.value){status.textContent=tr('changed');return;}
      // Text-only output. Model tool calls can never dispatch page execution.
      output.textContent=data.answer||data.status;
      answer={scope:currentContext,status:data.status,answer:data.answer,tool_results:data.tool_results||[],audit:data.audit||[],execution_performed:false};
      proposal=(data.tool_results||[]).find(item=>item.tool==='propose_count_workflow'&&item.result?.status==='draft')?.result||null;
      audit.hidden=false;status.textContent='';
    }catch{status.textContent=tr('unavailable');}
    finally{busy=false;consent.checked=false;render();}
  };
  apply.onclick=()=>{if(proposal&&guidance.countWorkflowAvailable)openWorkbench({proposal,question:question.value});};
  audit.onclick=()=>{
    if(!answer)return;const url=URL.createObjectURL(new Blob([JSON.stringify(answer,null,2)],{type:'application/json'}));const link=el('a');link.href=url;link.download='emp-agent-guidance.json';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
  };
  const main=document.getElementById('main');
  main?.addEventListener('change',event=>{if(event.target.closest('.page.active'))refreshContext();});
  window.addEventListener('emp:experiment-change',refreshContext);
  window.addEventListener('emp:locale-change',render);
  window.addEventListener('emp:agent-config-change',()=>{revision++;consent.checked=false;fetch('/api/public-data/agent/status',{credentials:'omit',redirect:'error'}).then(response=>response.json()).then(data=>{agent=data;render();}).catch(()=>{});});
  refreshContext();
  Promise.allSettled([
    fetch('/api/public-data/agent/status',{credentials:'omit',redirect:'error'}).then(r=>{if(!r.ok)throw Error('status');return r.json();}).then(data=>{agent=data;render();}),
    rRequest('GET','/capabilities',null,false,{skipSessionHeader:true,timeoutMs:15000}).then(data=>{if(data.success)caps=data;render();}).catch(()=>render()),
  ]);
  return {refresh:refreshContext,render};
}
