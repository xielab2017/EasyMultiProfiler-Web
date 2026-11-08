import {UI_LOCALES_FULL} from '../frontend/js/ui_locales_full.mjs';
import {agentMemory} from '../frontend/js/agent_memory.mjs';
import {bindChatFollow} from '../frontend/js/chat_layout.mjs';
import {mountChatComposer} from '../frontend/js/chat_composer.mjs';
import {appendChatMessage,createActivity,appendWorkflowCard,appendTaskReceipt} from '../frontend/js/chat_presentation.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {currentAgentAction,resolveAgentAction,assertAgentSubmission} from '../frontend/js/agent_actions.mjs';
const code=fs.readFileSync(new URL('../frontend/js/analysis_guide.js',import.meta.url),'utf8').replace(/^import .*;$/mg,'').replace('export function mountAnalysisGuide','function mountAnalysisGuide');
class El {
 constructor(tag,text){this.tag=tag;this.textContent=text||'';this.children=[];this.value='';this.checked=false;this.disabled=false;}
 append(...nodes){this.children.push(...nodes);} replaceChildren(...nodes){this.children=nodes;}
 setAttribute(){} addEventListener(){} closest(){return this;} click(){this.onclick?.();}
}
const flatten=e=>[e,...e.children.filter(n=>typeof n==='object').flatMap(flatten)];
async function fixture(reviewed, ready=true){
 const root=new El('div'),events=[],context={workflow:'analysis',tab:'ana-diff',hasExperiment:true};let submitted=0;
 const button=new El('button');button.onclick=()=>{submitted++;};
 const find=id=>id==='btn-diff'?button:flatten(root).find(n=>n.id===id);
 const fetch=async url=>({ok:true,json:async()=>url.endsWith('/status')?{status:ready?'ready':'unconfigured',provider:'fixture',config_revision:1}:{status:'ok',answer:'Requesting local submission.',tool_results:[{tool:'request_page_action',result:{action:'submit_current'}}]}});
 const sandbox=vm.createContext({UI_LOCALES_FULL,document:{createElement:tag=>new El(tag),getElementById:find},window:{addEventListener(){},dispatchEvent:e=>events.push(e)},fetch,getLocale:()=> 'zh',guideFor:()=>({title:'Test',goal:'Test',requirements:[],checks:[],steps:[],countWorkflowAvailable:true}),modelQuestion:q=>q,currentAgentAction,resolveAgentAction,rRequest:async()=>({success:true,features:{}}),Blob,URL,setTimeout,CustomEvent:class{constructor(type,opts){this.type=type;this.detail=opts?.detail;}}});
 Object.assign(sandbox,{assertAgentSubmission,agentMemory,bindChatFollow,mountChatComposer:(_,options)=>mountChatComposer(_,{...options,doc:sandbox.document}),appendTaskReceipt:(root,id,options)=>appendTaskReceipt(root,id,{...options,doc:sandbox.document}),appendChatMessage:(root,role,text,options)=>appendChatMessage(root,role,text,{...options,doc:sandbox.document}),createActivity:(root,options)=>createActivity(root,{...options,doc:sandbox.document}),appendWorkflowCard:(root,proposal,apply,options)=>appendWorkflowCard(root,proposal,apply,{...options,doc:sandbox.document})});
 vm.runInContext(code+';globalThis.mount=mountAnalysisGuide',sandbox);
 sandbox.mount(root,{snapshot:()=>context,focusSettings(){},openWorkbench(){}});
 await new Promise(r=>setImmediate(r));
 find('analysis-guide-question').value='运行当前分析';
 assert.equal(find('analysis-guide-consent'),undefined);
 find('analysis-agent-mode').checked=reviewed;
 await find('analysis-guide-ask').onclick();
 return {submitted,root,find};
}
test('chat dispatches one reviewed action and retains the requested agent preference',async()=>{
 const f=await fixture(true);assert.equal(f.submitted,1);assert.equal(f.find('analysis-agent-mode').checked,true);
 assert.ok(flatten(f.root).some(n=>n.textContent.includes('页面校验')));
});
test('a model tool request cannot submit an analysis without the local review grant',async()=>{
 const f=await fixture(false);assert.equal(f.submitted,0);
 assert.ok(flatten(f.root).some(n=>n.textContent.includes('请先选择数据')));
});
test('unconfigured models leave the question and send control available with a clear configuration hint',async()=>{
 const f=await fixture(false,false);assert.equal(f.submitted,0);
 assert.equal(f.find('analysis-guide-question').value,'运行当前分析');
 assert.equal(f.find('analysis-guide-ask').disabled,false);
 assert.ok(flatten(f.root).some(n=>n.textContent.includes('当前模型配置尚未加载')));
});
