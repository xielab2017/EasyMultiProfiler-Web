import {UI_LOCALES_FULL} from './ui_locales_full.mjs';
import {appendChatMessage,createActivity,appendWorkflowCard,appendTaskReceipt} from './chat_presentation.mjs';
import {applyPageFields} from './page_agent.mjs';
import {guideFor, modelQuestion} from './analysis_guide_model.mjs';
import {getLocale} from './locale.js?v=nav-language-20261108';
import {request as rRequest} from './api.js?v=nav-language-20261108';
import {currentAgentAction,resolveAgentAction,resolveHeatmapSize,resolveAgentNavigation,assertAgentSubmission} from './agent_actions.mjs';
import {bindChatFollow} from './chat_layout.mjs';
import {mountChatComposer} from './chat_composer.mjs';
import {agentMemory} from './agent_memory.mjs';
import {attachResultPlot} from './plot_attachment.mjs';

const AGENT_MODE_KEY='emp_agent_mode_enabled_v1';
const TEXT = {
  scope:['当前步骤','Current step'], local:['本地规则引导','Local guidance'],
  input:['输入准备','Input preparation'], review:['科学核对项','Scientific review'], plan:['步骤计划（待审核）','Step plan (review pending)'],
  present:['已选择 · 待核对','Selected · review pending'], missing:['待补充','Missing selection'],
  noData:['尚未选择数据','No data selected'], check:['刷新准备情况','Refresh readiness'],
  focus:['前往页面参数','Review page settings'], workbench:['在计数工作台编排','Build in Count Workbench'],
  askLabel:['你的分析问题','Your analysis question'], askPlaceholder:['例如：生成三线表前，应核对哪些变量、分组和缺失值？','For example: what groups, variable types and missingness should I review before a baseline table?'],
  ask:['发送','Send'], preview:['查看本步骤计划','Preview step plan'],
  pending:['尚未执行分析；页面选择不代表数据已验证。','No analysis executed; UI selections do not establish data validity.'],
  loading:['正在检查模型与 R 能力…','Checking model and R capabilities…'],
  modelMissing:['请在“模型与 API”加载已保存配置。','Load your saved configuration in Models and API.'],
  modelReady:['服务端智能体模型已配置','Server agent model configured'],
  rAvailable:['R 分析服务已连接','R analysis service connected'], rUnavailable:['R 服务未连接或能力尚未确认','R service unavailable or capabilities unverified'],
  customOff:['自定义 R 执行已关闭；登记分析流程仍走各自接口。','Custom R execution is off; registered analyses use their own endpoints.'],
  customOn:['自定义 R 执行已开启；可运行性需独立审核。','Custom R execution is enabled; code runnability requires separate review.'],
  consent:['同意将本次问题、最近的对话内容与页面/步骤名称发送到 {provider}，必要的公开检索词发送到 NCBI/ENA。脚本、文件、样本标签和数值不自动发送；不要粘贴私人数据。','Send this question, recent conversation and page/step names to {provider}, and necessary public search terms to NCBI/ENA. Scripts, files, sample labels and values are not attached. Do not paste private data.'],
  needConsent:['请先确认本次问题的数据发送范围。','Confirm the data-sharing scope for this question first.'],
  needQuestion:['请输入 1–3500 字符的问题。','Enter a question of 1–3500 characters.'],
  busy:['正在请求智能体…','Requesting agent guidance…'],
  changed:['步骤或数据选择已改变，旧回复已丢弃；请按当前上下文重新提问。','Step or data selection changed; stale reply discarded. Ask again for the current context.'],
  unavailable:['智能体服务不可用；本地核对和页面操作仍可使用。','Agent service unavailable; local guidance and page controls remain available.'],
  apply:['将 AI 的计数流程建议送入工作台审核','Review AI count-workflow proposal in Workbench'],
  audit:['导出本次指导记录','Export guidance record'], clearChat:['清空对话','Clear chat'], chat:['分析对话','Analysis chat'],
  modelSettings:['模型与 API','Models and API'],reconnect:['刷新模型连接','Refresh model connection'],
  configureFirst:['当前模型配置尚未加载。请点击“模型与 API”，加载已保存的配置后再发送；已保留问题。','The model settings are not loaded. Open Models and API, load your saved settings, then send again. Your question is retained.'],
};
const tr=(key,vars={})=>{let text=UI_LOCALES_FULL[TEXT[key][1]]?.[getLocale()]||TEXT[key][['zh','zh-TW'].includes(getLocale())?0:1];for(const [k,v]of Object.entries(vars))text=text.replaceAll(`{${k}}`,String(v));return text;};
function el(tag,text,cls){const node=document.createElement(tag);if(text!==undefined)node.textContent=text;if(cls)node.className=cls;return node;}

export function mountAnalysisGuide(root,{snapshot,focusSettings,openWorkbench,modelBridge}) {
  const taskReceipts=new Map();const completedUi=new Map();
  const followJobs=new Map();let expectedSubmission=null;
  let approvedPlan=null,planFirst=false;try{planFirst=localStorage.getItem('emp_agent_plan_first_v1')==='true';}catch{}
  let revision=0, fingerprint='', context={}, guidance=null, agent=null, caps=null, answer=null, proposal=null, busy=false,interpretationScope=null;const history=[];let automaticRound=0,rootRequest='';
  const header=el('div',undefined,'analysis-guide-scope');const badge=el('span',undefined,'analysis-guide-badge');const title=el('h3');const selection=el('p',undefined,'analysis-guide-selection');const goal=el('p');header.append(badge,title,selection,goal);
  const readiness=el('section');const checks=el('section');const planArea=el('section');planArea.hidden=true;
  const actions=el('div',undefined,'analysis-guide-actions');const refresh=el('button');const focus=el('button');const preview=el('button');const workbench=el('button');
  for(const button of [refresh,focus,preview,workbench]){button.type='button';button.className='btn btn-outline';actions.append(button);}
  const pending=el('p',undefined,'analysis-guide-note');
  const services=el('div',undefined,'analysis-guide-service');
  const questionLabel=el('label');const questionCaption=el('span');const question=el('textarea');question.rows=3;question.maxLength=3500;question.id='analysis-guide-question';questionLabel.append(questionCaption,question);
  const agentLabel=el('label',undefined,'analysis-guide-consent'),agentMode=el('input'),agentText=el('span');agentMode.type='checkbox';agentMode.id='analysis-agent-mode';agentLabel.append(agentMode,agentText);
  try{agentMode.checked=localStorage.getItem(AGENT_MODE_KEY)==='true';}catch{}
  agentMode.addEventListener('change',()=>{try{localStorage.setItem(AGENT_MODE_KEY,String(agentMode.checked));}catch{}});
  const connectionActions=el('div',undefined,'analysis-guide-actions'),modelSettings=el('button',undefined,'btn btn-outline'),reconnect=el('button',undefined,'btn btn-outline');modelSettings.type=reconnect.type='button';modelSettings.id='analysis-model-settings';reconnect.id='analysis-model-refresh';connectionActions.append(modelSettings,reconnect);
  const planToggle=el('button','先看 Plan：关闭','btn btn-outline');planToggle.type='button';planToggle.id='analysis-plan-toggle';connectionActions.append(planToggle);planToggle.onclick=()=>{planFirst=!planFirst;approvedPlan=null;try{localStorage.setItem('emp_agent_plan_first_v1',String(planFirst));}catch{}render();};
  const ask=el('button',undefined,'btn btn-primary');ask.type='button';ask.id='analysis-guide-ask';
  const taskLine=el('p');taskLine.id='analysis-latest-task';
  const status=el('p');status.setAttribute('role','status');const output=el('div',undefined,'analysis-guide-answer');output.id='analysis-guide-answer';
  const welcome=el('section',undefined,'agent-chat-welcome'),welcomeTitle=el('h3'),welcomeText=el('p'),suggestions=el('div',undefined,'agent-chat-suggestions');welcome.append(welcomeTitle,welcomeText,suggestions);output.append(welcome);
  for(const [zh,en,prompt] of [['读取附件','Read attachments','请读取我选择的论文或图片，说明读到了什么，并推荐下一步。'],['推荐流程','Suggest workflow','请结合当前数据和页面设置推荐适用分析流程，标出缺少的信息。'],['任务进度','Task progress','请检查后台任务进度，指出失败或等待处理的任务。']]){const button=el('button',zh);button.type='button';button._labels=[zh,en];button.title=en;button.onclick=()=>{if(!question.value.trim()){question.value=prompt;question.oninput();composer.resize();question.focus?.();}};suggestions.append(button);}
  const apply=el('button',undefined,'btn btn-outline');apply.type='button';apply.hidden=true;
  const audit=el('button',undefined,'btn btn-outline');audit.type='button';audit.hidden=true;const clearChat=el('button',undefined,'btn btn-outline');clearChat.type='button';const chatHeading=el('h4');
  const localDetails=el('details'),localSummary=el('summary');localDetails.append(localSummary,header,readiness,checks,actions,planArea,pending);
  const chatActions=el('div',undefined,'analysis-guide-actions analysis-chat-actions');chatActions.append(ask,clearChat);
  const jump=el('button','回到最新消息','agent-jump-latest');jump.type='button';jump.hidden=true;
  root.append(services,connectionActions,chatHeading,taskLine,output,jump,apply,audit);
  const follower=bindChatFollow(output,jump);
  const composer=mountChatComposer(root,{question,agentLabel,actions:chatActions,status,modelBridge,onChange:()=>{automaticRound=0;},isEnglish:()=>!['zh','zh-TW'].includes(getLocale()),doc:document});
  output.setAttribute('role','log');output.setAttribute('aria-label','AI 对话消息');output.setAttribute('aria-live','polite');

  function render(){
    guidance=guideFor(context,getLocale());
    localSummary.textContent=['zh','zh-TW'].includes(getLocale())?'当前页面与输入检查':'Current page and input checks';
    badge.textContent=tr('local');title.textContent=guidance.title;
    selection.textContent=`${tr('scope')}: ${context.workflow||'—'} / ${context.tab||'—'} · ${context.experimentName||tr('noData')}`;
    goal.textContent=guidance.goal;
    readiness.replaceChildren(el('h4',tr('input')));
    for(const req of guidance.requirements){const row=el('p',undefined,'analysis-guide-readiness');row.append(el('strong',tr(req.present?'present':'missing')),el('span',req.text));readiness.append(row);}
    checks.replaceChildren(el('h4',tr('review')));const checklist=el('ul');for(const text of guidance.checks)checklist.append(el('li',text));checks.append(checklist);
    planArea.replaceChildren(el('h4',tr('plan')));const steps=el('ol');for(const step of guidance.steps)steps.append(el('li',step.label));planArea.append(steps);
    for(const [button,key]of [[refresh,'check'],[focus,'focus'],[preview,'preview'],[workbench,'workbench'],[ask,'ask'],[apply,'apply'],[audit,'audit']])button.textContent=tr(key);
    clearChat.textContent=tr('clearChat');chatHeading.textContent=tr('chat');output.setAttribute('aria-label',tr('chat'));workbench.hidden=!guidance.countWorkflowAvailable;pending.textContent=tr('pending');questionCaption.textContent=tr('askLabel');question.placeholder=tr('askPlaceholder');
    const en=!['zh','zh-TW'].includes(getLocale());
    for(const button of suggestions.children)button.textContent=button._labels[en?1:0];
    welcome.hidden=history.length>0||busy;welcomeTitle.textContent=en?'AI Omics Assistant':'AI 组学助手';welcomeText.textContent=en?'Attach papers or images, or describe your research question. I can help find data, prepare workflows and interpret results.':'上传论文或图片，或描述您的研究问题。我可以协助定位数据、编排流程和解读结果。';
    const placeholders={matrix:['上传论文、粘贴图片，或告诉我想查找哪项研究的数据…','Attach a paper or image, or describe the study data you need…'],workbench:['描述研究问题，我会结合已上传矩阵推荐分析步骤…','Describe your question; I will suggest steps using the uploaded matrix…'],integration:['告诉我要整合哪些研究与组学，我会先核对样本对应…','Which studies and omics should be integrated? Start with sample alignment…'],visualization:['例如：解释当前图、调整布局，或选择保存的结果重新出图…','Explain this figure, change its layout, or plot saved results…']};
    if(placeholders[context.workflow])question.placeholder=placeholders[context.workflow][en?1:0];
    agentText.textContent=['zh','zh-TW'].includes(getLocale())?'Agent 模式':'Agent mode';agentLabel.title=['zh','zh-TW'].includes(getLocale())?'记住选择；自动调用页面工具，执行前检查输入与参数。':'Remembered; use page tools and validate inputs before execution.';
    agentMode.disabled=busy;
    const serviceLines=[agent?tr(agent.status==='ready'?'modelReady':'modelMissing'):tr('loading'),caps?tr('rAvailable'):tr('rUnavailable')];
    services.textContent=serviceLines.join(' · ')+(agent?.status==='ready'?` · ${agent.provider} / ${agent.model}`:'');
    modelSettings.textContent=tr('modelSettings');reconnect.textContent=tr('reconnect');
    const stateText=UI_LOCALES_FULL[planFirst?'On':'Off']?.[getLocale()]||(planFirst?'On':'Off');planToggle.textContent=(UI_LOCALES_FULL['Plan first: {state}']?.[getLocale()]||'Plan first: {state}').replace('{state}',stateText);planToggle.setAttribute('aria-pressed',String(planFirst));planToggle.disabled=busy;
    jump.textContent=['zh','zh-TW'].includes(getLocale())?'回到最新消息':'Jump to latest';question.setAttribute('aria-label',tr('askLabel'));composer.render();ask.disabled=busy;composer.setBusy(busy);apply.hidden=!proposal||!guidance.countWorkflowAvailable;
  }
  async function refreshAgent(){const response=await fetch('/api/public-data/agent/status',{credentials:'omit',redirect:'error'});if(!response.ok)throw Error('status');const next=await response.json();if(agent&&(next.provider!==agent.provider||next.config_revision!==agent.config_revision)){revision++;}agent=next;composer.refreshModels(agent);render();return agent;}
  modelSettings.onclick=()=>document.querySelector('.nav-item[data-page="models"]')?.click();
  reconnect.onclick=()=>refreshAgent().catch(()=>{status.textContent=tr('unavailable');});
  const contextKey=value=>{
    const stable={...value};if(stable.pageContext)stable.pageContext={...stable.pageContext,statuses:undefined};
    return JSON.stringify(stable);
  };
  function refreshContext(){
    const next=snapshot();const nextKey=contextKey(next);
    if(nextKey!==fingerprint){revision++;fingerprint=nextKey;context=next;proposal=null;answer=null;audit.hidden=true;status.textContent='';}
    render();
  }
  refresh.onclick=refreshContext;
  focus.onclick=()=>focusSettings(guidance.target);
  preview.onclick=()=>{planArea.hidden=!planArea.hidden;render();};
  workbench.onclick=()=>openWorkbench();
  question.oninput=()=>{automaticRound=0;rootRequest='';if(!busy){approvedPlan=null;interpretationScope=null;proposal=null;answer=null;apply.hidden=true;audit.hidden=true;}};
  ask.onclick=async()=>{
    if(busy)return;
    if(agent?.status!=='ready') {
      try{await refreshAgent();}catch{status.textContent=tr('unavailable');return;}
      if(agent?.status!=='ready'){status.textContent=tr('configureFirst');return;}
    }
    if(composer.isUploading()){status.textContent='附件仍在读取，请稍候。';return;}
    if((!question.value.trim()&&!composer.hasAttachments())||question.value.length>3500){status.textContent=tr('needQuestion');return;}
    refreshContext();
    let currentPlot=[];
    if(!automaticRound&&!interpretationScope&&context.workflow==='visualization'&&/解读|解释.*图|看.*图|interpret|explain.*(plot|figure)/i.test(question.value)){
      try{const plot=await attachResultPlot(document.getElementById(context.tab)||document.querySelector('.page.active'));if(plot)currentPlot=[plot];}catch(error){status.textContent=error.message;return;}
    }
    const current=revision, expectedQuestion=question.value.trim()||'请解读这些附件，并结合当前页面给出下一步建议。',sentAttachments=interpretationScope?.attachments||[...currentPlot,...composer.take()].slice(0,6),priorHistory=history.slice(-4),guidanceOnly=interpretationScope?.draftOnly===true, grant=(!interpretationScope||guidanceOnly)&&agentMode.checked, currentContext=interpretationScope||{workflow:context.workflow,tab:context.tab,plotSettings:context.plotSettings,pageContext:context.pageContext};
    currentContext.memory=agentMemory.snapshot(context.omics||context.workflow);
    currentContext.locale=getLocale();
    const currentButton=currentAgentAction(context),currentNode=currentButton&&document.getElementById(currentButton);
    currentContext.availableAction=currentNode?{action:'submit_current',button:currentButton,enabled:!currentNode.disabled,label:currentNode.textContent?.trim().slice(0,100)}:null;
    if(!automaticRound){rootRequest=expectedQuestion;completedUi.clear();}
    currentContext.completedUi=[...completedUi.values()];
    let continueUi=false,submittedTask=false;
    busy=true;ask.disabled=true;status.textContent=tr('busy');
    const english=!['zh','zh-TW'].includes(getLocale());
    const userMessage=automaticRound?el('span',''):appendChatMessage(output,'user',expectedQuestion,{english});
    for(const attachment of sentAttachments){const chip=el('div',attachment.name,'agent-sent-attachment');if(attachment.kind==='image'){const img=el('img');img.src=attachment.preview_url;img.alt=attachment.name;chip.append(img);}userMessage.append(chip);}
    history.push({role:'user',text:expectedQuestion+(sentAttachments.length?' [附件：'+sentAttachments.map(x=>x.name).join(', ')+']':'')});
    welcome.hidden=true;
    question.value='';composer.resize();follower.latest();
    const activity=createActivity(output,{english});activity.note(english?'Reading current page settings and data summary.':'读取当前页面设置与数据检查摘要。');
    const runId=globalThis.crypto?.randomUUID?.().replaceAll('-','');let tracking=true;
    const pollProgress=async()=>{if(!tracking||!runId)return;try{const response=await fetch('/api/public-data/agent/progress/'+runId,{credentials:'omit',redirect:'error'});if(response.ok){const progress=await response.json();if(tracking)activity.update(progress.events);}}catch{}if(tracking)setTimeout(pollProgress,900);};
    if(runId)setTimeout(pollProgress,500);
    try{
      const userPrompt=expectedQuestion,recent=priorHistory.map(row=>row.role+': '+row.text.slice(0,200)).join('\n'),historyRoom=Math.max(0,3000-userPrompt.length),combined=userPrompt+(historyRoom?'\nPrior conversation for reference only; the current request above takes precedence. Earlier task-specific restrictions do not apply to a new request:\n'+recent.slice(-Math.max(0,historyRoom-180)):'');
      const response=await fetch('/api/public-data/agent/respond',{method:'POST',headers:{'Content-Type':'application/json'},credentials:'omit',redirect:'error',body:JSON.stringify({run_id:runId,reasoning_effort:composer.reasoningEffort(),attachment_ids:sentAttachments.map(x=>x.id),question:modelQuestion(combined,currentContext)+(approvedPlan?'\nThe user already approved this plan: '+JSON.stringify(approvedPlan)+'. Continue it; do not propose another approval card.':planFirst&&!interpretationScope?'\nCall propose_agent_plan first and wait for confirmation.':'')+(grant?'\nLocal Agent mode is enabled across registered pages. Plan is optional; act directly unless requested. Dataset-guidance is draft-only.':'\nLocal task submission is not granted. You may refresh tasks or draft and inspect.'),consent:true,expected_provider:agent.provider,expected_config_revision:agent.config_revision,context_ids:{},context_consent:false})});
      if(!response.ok)throw Error('request');const data=await response.json();
      if(['unconfigured','configuration_changed'].includes(data.status)){await refreshAgent();status.textContent=tr('configureFirst');if(!question.value){question.value=expectedQuestion;}activity.finish(false);return;}
      if(current!==revision||contextKey(snapshot())!==fingerprint){const latest=snapshot(),sameInput=latest.workflow===context.workflow&&latest.experimentName===context.experimentName&&JSON.stringify(latest.pageContext?.files||[])===JSON.stringify(context.pageContext?.files||[])&&latest.pageContext?.workbench?.source_sha256===context.pageContext?.workbench?.source_sha256;activity.finish(false);if(sameInput&&automaticRound<2&&agentMode.checked&&!question.value.trim()){continueUi=true;activity.note(english?'Page context refreshed; checking the same input again.':'页面状态已更新，正在重新检查同一输入。');}else{activity.note(tr('changed'));status.textContent=tr('changed');}return;}
      // Model text is inert; only typed actions are dispatched through registered controls.
      history.push({role:'assistant',text:String(data.answer||data.status)});
      tracking=false;activity.update([...(data.audit||[]).map(row=>({stage:'tool_finished',...row})),{stage:data.status==='ok'?'completed':data.status}]);activity.finish(data.status==='ok');
      const handoff=(data.tool_results||[]).find(item=>['request_page_action','fill_page_fields','set_heatmap_size'].includes(item.tool));
      const decision=(data.tool_results||[]).some(item=>['propose_agent_plan','ask_user_choice'].includes(item.tool));
      const visibleAnswer=decision?(english?'Please review the options below to continue.':'请确认下方计划或选择，确认后会继续执行。'):handoff?(english?'I am applying the requested page action. Actual progress and any required choices appear below.':'正在衔接页面操作；实际进度与需要确认的选项会显示在下方。'):String(data.answer||data.status);
      appendChatMessage(output,'assistant',visibleAnswer,{english});follower.changed();
      if(data.status!=='ok'&&!question.value){question.value=expectedQuestion;composer.resize();}
      answer={question:expectedQuestion,scope:currentContext,status:data.status,answer:data.answer,tool_results:data.tool_results||[],audit:data.audit||[],reasoning:data.reasoning,execution_performed:false};
      const planNeedsApproval=planFirst&&!approvedPlan&&!interpretationScope;
      const decisions=[...(data.tool_results||[])];
      if(planNeedsApproval&&!decisions.some(item=>['propose_agent_plan','ask_user_choice'].includes(item.tool)))decisions.push({tool:'propose_agent_plan',result:{steps:[rootRequest||expectedQuestion]}});
      for(const item of decisions){if(!['propose_agent_plan','ask_user_choice'].includes(item.tool))continue;const card=el('section',undefined,'agent-workflow-card'),value=item.result;card.append(el('h4',item.tool==='propose_agent_plan'?'Plan · 待确认':value.question));if(value.steps){const ol=el('ol');for(const step of value.steps)ol.append(el('li',step));card.append(ol);}for(const label of item.tool==='propose_agent_plan'?['确认并执行计划','修改计划']:(value.options||[])){const button=el('button',label,'btn btn-outline');button.type='button';button.onclick=()=>{if(label==='修改计划'){question.value='请修改刚才的计划：';question.focus?.();return;}approvedPlan=value.steps||approvedPlan;automaticRound=1;question.value='用户已选择：'+label+'。继续原始请求：'+(rootRequest||expectedQuestion)+(value.steps?'。已确认计划：'+value.steps.join(' → '):'');for(const b of card.querySelectorAll?.('button')||[])b.disabled=true;setTimeout(()=>ask.onclick(),0);};card.append(button);}output.append(card);}
      proposal=(data.tool_results||[]).find(item=>item.tool==='propose_count_workflow'&&item.result?.status==='draft')?.result||null;
      const draft=proposal;
      appendWorkflowCard(output,draft,()=>openWorkbench({proposal:draft,question:expectedQuestion}),{english});
      if(draft&&grant&&!planNeedsApproval&&(!guidanceOnly||context.pageContext?.profile?.count_compatible)){
        const currentAnswer=answer;openWorkbench({proposal:draft,question:expectedQuestion});refreshContext();answer=currentAnswer;proposal=draft;
        activity.note(english?'Draft steps added to Workbench; no analysis started.':'已将步骤草案填入工作台；尚未启动分析。');continueUi=!guidanceOnly;
      }
      audit.hidden=false;status.textContent='';
      if(data.continuation_required&&grant)continueUi=true;
      const awaitingDecision=planNeedsApproval||(data.tool_results||[]).some(item=>['propose_agent_plan','ask_user_choice'].includes(item.tool));
      if(grant&&!guidanceOnly&&!awaitingDecision&&/下载|download/i.test(rootRequest))for(const item of data.tool_results||[]){if(!['discover_processed','discover_pride_files'].includes(item.tool)||!item.result?.accession)continue;try{const job=await window.empAgentPipeline.start(item.result.accession);history.push({role:'tool',text:'Automatic download: '+job.job_id});submittedTask=true;}catch(error){activity.note(error.message);}}
      const requestedActions=(awaitingDecision?[]:(data.tool_results||[])).filter(item=>['fill_page_fields','set_heatmap_size','request_page_action'].includes(item.tool)).slice(0,6).map(item=>item.result);
      const turnAnswer=answer;
      for(const requested of requestedActions) {
        if(!requested||data.status!=='ok')continue;
        try {
          if(requested.action==='download_matrix'){
            if(!grant||guidanceOnly)throw Error('请启用 Agent 模式以自动下载。');
            const job=await window.empAgentPipeline.start(requested.target);history.push({role:'tool',text:'Download accepted: '+job.job_id+' '+job.status});submittedTask=true;continue;
          }
          if(requested.action==='navigate'){
            if(!grant)throw Error('请启用 Agent 模式。');const route=resolveAgentNavigation(requested.target);
            document.querySelector('.nav-item[data-page="'+route.page+'"]')?.click();
            if(route.tab)document.querySelector('#page-'+route.page+' .tab[data-tab="'+route.tab+'"]')?.click();completedUi.set('navigate:'+requested.target,{action:'navigate',target:requested.target,status:'completed'});refreshContext();answer=turnAnswer;continueUi=true;continue;
          }
          if(requested.action==='review_samples'){
            if(!grant)throw Error('请启用 Agent 模式。');if(context.workflow==='import'&&context.pageContext?.files?.length)throw Error('当前任务使用数据页新文件，不能确认旧工作台数据；请先调用 submit_current 导入。');window.dispatchEvent(new CustomEvent('emp:agent-review-samples'));continue;
          }
          if(guidanceOnly&&!['fill_page_fields','build_workflow','refresh_tasks'].includes(requested.action))throw Error('新数据自动引导只准备流程，不自动启动分析。');
          if(requested.action==='fill_page_fields'){
            if(!grant||!agentMode.checked)throw Error('请启用 Agent 模式后填写页面。');
            if(requested.fields?.['scat-ordination']==='assay_pca'&&/保存.*坐标|已保存.*PCA|保存的.*PCA|saved.*(PCA|coordinate)|不.*重算PCA/i.test(rootRequest))throw Error('用户要求保存的 PCA 坐标，请使用 scat-ordination=emp；不能改为重新计算。');
            const changed=applyPageFields(context.workflow,requested.fields);
            refreshContext();answer=turnAnswer;audit.hidden=false;
            activity.note(changed.length?'已填写页面参数：'+changed.join(', '):'页面参数已一致，无需重复填写。');
            history.push({role:'tool',text:changed.length?'Local UI applied fields: '+changed.join(', '):'No change: these fields already have the requested values. Do not repeat this operation.'});completedUi.set('fields:'+context.workflow,{action:'fill_page_fields',fields:requested.fields,status:'completed'});
            if(!changed.length&&context.workflow==='workbench'&&context.pageContext?.workbench?.has_dataset&&context.pageContext.workbench.unassigned===0&&context.pageContext.workbench.needs_design_review&&/分析|运行|执行|run|analy/i.test(rootRequest)){window.dispatchEvent(new CustomEvent('emp:agent-review-samples'));}else continueUi=true;continue;
          }
          if(requested.action==='select_matrix_file'){
            if(!grant||!agentMode.checked)throw Error('请启用 Agent 模式。');
            const button=[...document.querySelectorAll('#matrix-files [data-agent-file]')].find(node=>node.dataset.agentFile===requested.target);
            if(!button||button.disabled)throw Error('所选文件已不可用；请通过 download_matrix 按编号自动下载。');
            if(typeof button.onclick==='function')await button.onclick();else button.click();submittedTask=true;output.append(el('p','已打开所选文件的下载计划；下载状态以页面任务记录为准。'));continue;
          }
          const action=requested.action==='resize_heatmap'?resolveHeatmapSize(context,requested,grant&&agentMode.checked):resolveAgentAction(context,requested.action,grant&&agentMode.checked);
          if(action.type==='refresh_tasks') {
            if(completedUi.has('refresh_tasks')){activity.note(english?'Task status already read; continuing the requested action.':'已读取任务状态，继续后续操作。');continueUi=true;continue;}
            window.dispatchEvent(new CustomEvent('emp:tasks-refresh'));
            const tasks=await rRequest('GET','/jobs?limit=100',null,false,{skipSessionHeader:true,timeoutMs:10000});
            const currentTasks=(tasks.jobs||[]).filter(task=>!context.experimentName||task.experiment===context.experimentName).slice(0,6);
            const records=currentTasks.map(task=>({id:task.id,experiment:typeof task.experiment==='string'?task.experiment:'',kind:task.kind,status:task.status,progress:task.progress}));
            for(const task of currentTasks){let receipt=taskReceipts.get(task.id);if(!receipt){receipt=appendTaskReceipt(output,task.id,{english});taskReceipts.set(task.id,receipt);}receipt.update(task);}
            completedUi.set('refresh_tasks',{action:'refresh_tasks',status:'completed',tasks:records});
            history.push({role:'tool',text:'Actual task records: '+JSON.stringify(records)});continueUi=true;
          } else {
            if(requested.action==='submit_current')assertAgentSubmission(context,rootRequest,requested.target);
            const button=document.getElementById(action.button);
            if(!button||button.disabled||!button.closest('.page.active'))throw Error('当前任务入口不可用，请先补齐输入。');
            if(action.type==='resize_heatmap'){
              document.getElementById('heat-width').value=action.width;
              document.getElementById('heat-height').value=action.height;
              refreshContext();
            }
            if(['analysis','preparation'].includes(context.workflow)&&requested.action==='submit_current')expectedSubmission={root:rootRequest,experiment:context.experimentName,until:Date.now()+30000};
            if(['matrix','integration','workbench','import'].includes(context.workflow)&&typeof button.onclick==='function')await button.onclick();else button.click();
            if(context.workflow==='import'){refreshContext();history.push({role:'tool',text:'Upload UI returned: '+document.getElementById('import-result')?.textContent});continueUi=true;}
            else if(['search_sources','find_matrix_files','read_downloaded_matrix','build_workflow','inspect_integration'].includes(requested.action))continueUi=true;else submittedTask=true;
            output.append(el('p',context.workflow==='visualization'?'已请求绘图，生成结果与下载入口将在当前页面显示。':'Agent 已发起当前任务的页面校验；后台接收成功后会显示任务编号。'));
          }
          if(answer)answer.local_action=action;
        } catch(error) { activity.note(error.message);output.append(el('p',requested.action+' · '+error.message));history.push({role:'tool',text:'Local UI action was not applied: '+String(error.message).slice(0,300)});if(automaticRound<3)continueUi=true; }
      }
    }catch{activity.finish(false);activity.note(tr('unavailable'));status.textContent=tr('unavailable');if(current===revision&&!question.value){question.value=expectedQuestion;composer.resize();}}
    finally{
      const continuationScope=interpretationScope;tracking=false;busy=false;interpretationScope=null;render();
      if(continueUi&&!submittedTask&&agentMode.checked&&automaticRound<6&&!question.value.trim()&&rootRequest){
        automaticRound++;refreshContext();if(guidanceOnly)interpretationScope=continuationScope;question.value=('继续完成原始请求：'+rootRequest+'\n上一轮页面动作已返回。请读取最新页面状态推进下一步；不要重复已完成的操作。缺少信息时直接提出具体问题。').slice(0,3500);
        setTimeout(()=>{if(!busy&&question.value.trim())ask.onclick();},0);
      }
    }
  };
  clearChat.onclick=()=>{rootRequest='';automaticRound=0;completedUi.clear();revision++;history.length=0;taskReceipts.clear();output.replaceChildren(welcome);question.value='';composer.clear();composer.resize();proposal=null;answer=null;audit.hidden=true;render();};
  question.addEventListener('keydown',event=>{if(event.key==='Enter'&&!event.shiftKey&&!event.isComposing){event.preventDefault();ask.onclick();}});
  apply.onclick=()=>{if(proposal&&guidance.countWorkflowAvailable)openWorkbench({proposal,question:answer?.question||''});};
  audit.onclick=()=>{
    if(!answer)return;const url=URL.createObjectURL(new Blob([JSON.stringify(answer,null,2)],{type:'application/json'}));const link=el('a');link.href=url;link.download='emp-agent-guidance.json';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
  };
  const main=document.getElementById('main');
  main?.addEventListener('change',event=>{if(event.target.closest('.page.active'))refreshContext();});
  window.addEventListener('emp:experiment-change',refreshContext);
  window.addEventListener('emp:study-reset',refreshContext);
  window.addEventListener('emp:interpret-result',event=>{
    question.value=event.detail.question;
    question.oninput();
    const kind=String(event.detail.analysis_type||'');
    interpretationScope={attachments:event.detail.attachments||[],workflow:'interpretation',tab:/enrich/.test(kind)?'ana-enrich':/differential/.test(kind)?'ana-diff':/dimension/.test(kind)?'ana-dim':/correlation/.test(kind)?'ana-cor':/cluster/.test(kind)?'ana-cluster':'result-interpretation'};
    ask.onclick();
  });
  const startQuestion=event=>{
    const profile=event.detail?.profile;
    if(window._empAgentImporting){history.push({role:'tool',text:'Managed matrix imported; numerical profile: '+JSON.stringify(profile)});return;}
    const prompt=event.detail?.question||'请根据新上传矩阵的结构和数值检查摘要，推荐组学分析与绘图流程，列出需要核对的分组、批次、配对、原始计数来源。不要执行分析，不猜分组。';
    refreshContext();
    const summary=profile?'\n检查摘要：'+JSON.stringify(profile):'';
    if(busy||question.value.trim()){output.append(el('p','收到新数据检查摘要，可在当前问题结束后询问流程建议。'+summary));return;}
    question.value=(prompt+summary).slice(0,3500);question.oninput();
    interpretationScope={workflow:'workbench',tab:'dataset-guidance',pageContext:{...context.pageContext,...(profile?{profile}:{})},draftOnly:true};
    document.getElementById('code-lab-root')?.classList.add('code-lab--open');ask.onclick();
  };
  window.addEventListener('emp:dataset-profile',startQuestion);
  window.addEventListener('emp:agent-question',startQuestion);
  window.addEventListener('emp:locale-change',render);
  window.addEventListener('emp:job-submitted',event=>{
    const id=event.detail.job_id;taskLine.textContent=`最近后台任务：${id}（在任务列表中查看进度）`;
    if(expectedSubmission&&Date.now()<expectedSubmission.until&&expectedSubmission.root===rootRequest&&(!event.detail.experiment||event.detail.experiment===expectedSubmission.experiment)){
      followJobs.set(id,expectedSubmission);expectedSubmission=null;
    }
    if(!taskReceipts.has(id))taskReceipts.set(id,appendTaskReceipt(output,id,{english:!['zh','zh-TW'].includes(getLocale())}));
  });
  window.addEventListener('emp:jobs-updated',event=>{for(const job of event.detail?.jobs||[]){
    taskReceipts.get(job.id)?.update(job);const follow=followJobs.get(job.id);
    if(!follow||!['done','error','cancelled'].includes(job.status))continue;
    if(job.status!=='done'){followJobs.delete(job.id);continue;}
    if(busy)continue;
    followJobs.delete(job.id);
    if(follow.root!==rootRequest||question.value.trim()||!agentMode.checked||snapshot().experimentName!==follow.experiment)continue;
    completedUi.set('job:'+job.id,{action:'analysis',job_id:job.id,status:'done',experiment:follow.experiment});
    automaticRound++;refreshContext();question.value=('后台任务 '+job.id+' 已实际完成。不要重复提交该分析。继续原始请求：'+follow.root+'。若还需要出图，请使用保存的分析结果继续；否则报告实际完成状态。').slice(0,3500);setTimeout(()=>ask.onclick(),0);
  }});
  window.addEventListener('emp:agent-flow',event=>{const flow=event.detail;if(!flow)return;const id=flow.job_id||flow.accession;let receipt=taskReceipts.get(id);if(!receipt){receipt=appendTaskReceipt(output,id,{english:false});taskReceipts.set(id,receipt);}receipt.update({status:flow.stage==='error'?'error':flow.status==='completed'?'done':flow.status||'running',progress:flow.total_bytes?100*(flow.bytes_downloaded||0)/flow.total_bytes:0,message:flow.message||flow.stage});history.push({role:'tool',text:'Pipeline '+flow.stage+': '+(flow.message||flow.status||'')});if(history.length>60)history.splice(0,20);follower.changed();});
  window.addEventListener('emp:agent-flow',event=>{if(event.detail?.stage!=='ready'||!agentMode.checked)return;const button=el('button','核对本次设计并继续分析','btn btn-primary');button.onclick=()=>window.dispatchEvent(new CustomEvent('emp:agent-review-samples'));output.append(button);follower.changed();if(rootRequest&&/分析|流程|analy|workflow/i.test(rootRequest)&&event.detail.readiness?.has_dataset&&event.detail.readiness.unassigned===0){window.dispatchEvent(new CustomEvent('emp:agent-review-samples'));return;}if(!busy&&!question.value.trim()&&rootRequest&&/分析|流程|analy|workflow/i.test(rootRequest)){const original=rootRequest;automaticRound=1;refreshContext();question.value=('矩阵已自动下载、导入并精确匹配样本。请读取工作台准备状态，继续原始请求：'+original).slice(0,3500);setTimeout(()=>ask.onclick(),0);}});
  window.addEventListener('emp:agent-config-change',()=>{revision++;refreshAgent().catch(()=>{});});
  window.addEventListener('focus',()=>refreshAgent().catch(()=>{}));
  window.addEventListener('storage',event=>{if(event.key===AGENT_MODE_KEY){agentMode.checked=event.newValue==='true';render();}if(event.key==='emp_agent_config_revision')refreshAgent().catch(()=>{});});
  refreshContext();
  Promise.allSettled([
    fetch('/api/public-data/agent/status',{credentials:'omit',redirect:'error'}).then(r=>{if(!r.ok)throw Error('status');return r.json();}).then(data=>{agent=data;composer.refreshModels(agent);render();}),
    rRequest('GET','/capabilities',null,false,{skipSessionHeader:true,timeoutMs:15000}).then(data=>{if(data.success)caps=data;render();}).catch(()=>render()),
  ]);
  return {refresh:refreshContext,render};
}
