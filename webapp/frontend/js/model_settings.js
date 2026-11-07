import {getLocale} from './locale.js?v=i18n-zh-default-v1';
import {mountModelConnections} from './model_connections.js';
const TEXT={
 title:['模型与 API','Models and API'],intro:['在这里统一管理模型服务、模型名称与 API。原右侧面板的配置已移到此处；分析引导和代码优化继续使用各自的明确操作入口。','Manage providers, model names and APIs here. Configuration from the right-side panel is consolidated here; analysis guidance and code optimization retain their explicit action buttons.'],
 load:['保存并加载到 AI 分析助手','Save and load into analysis agent'],refresh:['刷新连接状态','Refresh connection status'],reset:['停用本次加载与自动恢复','Disable runtime loading and auto-restore'],
 hint:['配置按服务保存在当前浏览器。保存并加载后，下次打开页面会向本机服务恢复该配置；不会自动发送问题。加载和刷新状态不调用外部模型；每次发送问题仍需确认发送范围。','Settings are saved per provider in this browser. Saved and loaded settings restore to the local service when reopening the page, without sending questions. Loading and status refresh make no external model call; each question still requires consent to its data scope.'],
 ready:['配置已加载；尚未验证真实模型请求。','Configuration loaded; a live model request has not been verified.'],unconfigured:['分析助手尚未配置模型，可先使用本地流程与引导。','The analysis agent is not configured; local workflows and guidance remain available.'],
 verified:['真实对话与流程工具调用已验证。','Live chat and workflow tool invocation verified.'],
 loading:['正在加载配置…','Loading configuration…'],error:['配置未加载：请选择一个实际聊天模型、支持的 Provider 和 API 地址，并检查 API Key。Auto / Fusion / Mixed 不能作为研究助手的单模型。','Configuration was not loaded. Select one actual chat model, a supported provider/API URL and its API key. Auto / Fusion / Mixed are not single chat models for the research agent.'],
 unavailable:['无法连接配置服务，请检查当前应用服务。','Cannot reach the configuration service; check the application service.'],
};
const tr=key=>TEXT[key][['zh','zh-TW'].includes(getLocale())?0:1];
const make=(tag,cls)=>{const node=document.createElement(tag);if(cls)node.className=cls;return node;};
export function mountModelSettings(root,{legacyWrap,readConfiguration}){
 if(!root||root.dataset.mounted)return;root.dataset.mounted='true';
 const heading=make('h2'),intro=make('p'),form=make('div','models-form'),hint=make('p','hint'),actions=make('div','wb-actions'),load=make('button','btn btn-primary'),refresh=make('button','btn btn-outline'),reset=make('button','btn btn-outline'),status=make('p');hint.id='models-api-hint';status.id='models-status';status.setAttribute('role','status');
 load.id='models-load';refresh.id='models-refresh';reset.id='models-reset';for(const button of [load,refresh,reset]){button.type='button';actions.append(button);}
 for(const node of [...legacyWrap.children])if(node.tagName!=='SUMMARY'&&!node.classList.contains('code-lab-llm-instruction')&&!node.classList.contains('code-lab-llm-actions'))form.append(node);
 const legacyStatus=make('p');legacyStatus.id='models-legacy-status';legacyStatus.setAttribute('role','status');root.append(heading,intro,form,legacyStatus,hint,actions,status);let info=null,busy=false,message=null;
 function render(){heading.textContent=tr('title');intro.textContent=tr('intro');hint.textContent=tr('hint');load.textContent=tr('load');refresh.textContent=tr('refresh');reset.textContent=tr('reset');status.textContent=message?tr(message):info?`${tr(info.status==='ready'?(info.live_verified?'verified':'ready'):'unconfigured')} ${info.provider||''} · ${info.model||''}${info.endpoint_origin?' · '+info.endpoint_origin:''}`:'';}
 async function api(body){const response=await fetch('/api/public-data/agent/config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),credentials:'omit',redirect:'error'});if(!response.ok)throw Error('configuration');return response.json();}
 async function refreshStatus(){const response=await fetch('/api/public-data/agent/status',{credentials:'omit',redirect:'error'});if(!response.ok)throw Error('status');info=await response.json();message=null;render();}
 async function action(callback){if(busy)return;busy=true;load.disabled=true;reset.disabled=true;message='loading';render();try{await callback();await refreshStatus();window.dispatchEvent(new CustomEvent('emp:agent-config-change'));localStorage.setItem('emp_agent_config_revision',String(Date.now()));}catch{message='error';render();}finally{busy=false;load.disabled=false;reset.disabled=false;}}
 load.onclick=()=>action(async()=>{const selected=readConfiguration(true),config=selected.config;await api({provider:selected.provider==='chatgpt'?'openai':selected.provider,model:config.model,api_key:config.api_key||'',base_url:config.base_url||'',enabled:true,...(selected.provider==='minimax'?{region:config.region,protocol:config.protocol}:{})});localStorage.setItem('emp_agent_autoload_v1',selected.provider);});
 reset.onclick=()=>action(()=>{localStorage.removeItem('emp_agent_autoload_v1');return api({reset_runtime:true});});refresh.onclick=()=>refreshStatus().catch(()=>{message='unavailable';render();});
 mountModelConnections(root,{readConfiguration,load});
 window.addEventListener('emp:locale-change',render);render();refreshStatus().then(()=>{if(!info.runtime_configured&&localStorage.getItem('emp_agent_autoload_v1')===document.getElementById('code-lab-llm-provider')?.value)load.click();}).catch(()=>{message='unavailable';render();});
}
