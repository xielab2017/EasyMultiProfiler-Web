import {UI_LOCALES_FULL} from '../frontend/js/ui_locales_full.mjs';
import {resolveAgentAction,assertAgentSubmission} from '../frontend/js/agent_actions.mjs';
import {agentMemory} from '../frontend/js/agent_memory.mjs';
import {bindChatFollow} from '../frontend/js/chat_layout.mjs';
import {mountChatComposer} from '../frontend/js/chat_composer.mjs';
import {appendChatMessage,createActivity,appendWorkflowCard,appendTaskReceipt} from '../frontend/js/chat_presentation.mjs';
import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import vm from 'node:vm';
const code=fs.readFileSync(new URL('../frontend/js/analysis_guide.js',import.meta.url),'utf8').replace(/^import .*;$/mg,'').replace('export function mountAnalysisGuide','function mountAnalysisGuide');
function fixture(store={}){
 const nodes=new Map(),events={},sent=[],applied=[];let reply={status:'ok',answer:'fixture'};let context={workflow:'analysis',tab:'ana-diff',hasExperiment:true};
 class El{constructor(){this.children=[];this.handlers={};this.value='';this.checked=false;}set id(v){this._id=v;nodes.set(v,this);}get id(){return this._id;}append(...x){this.children.push(...x);}replaceChildren(...x){this.children=x;}setAttribute(){}addEventListener(k,f){this.handlers[k]=f;}}
 const sandbox=vm.createContext({UI_LOCALES_FULL,document:{createElement:()=>new El(),getElementById:id=>nodes.get(id)||null,querySelector:()=>null},window:{addEventListener:(k,f)=>{events[k]=f;},dispatchEvent(){}},localStorage:{getItem:k=>store[k],setItem:(k,v)=>{store[k]=v;}},getLocale:()=> 'zh',guideFor:()=>({title:'test',requirements:[],checks:[],steps:[]}),modelQuestion:(x,c)=>x+'\nScope: '+c.workflow,currentAgentAction:()=>({}),resolveAgentAction,assertAgentSubmission,resolveHeatmapSize(){},rRequest:async()=>({success:true,features:{}}),fetch:async(path,options)=>{if(options?.body)sent.push(JSON.parse(options.body));return {ok:true,json:async()=>options?.body?reply:{status:'ready',provider:'fixture',config_revision:1}};},Blob,URL,setTimeout});
 Object.assign(sandbox,{agentMemory,bindChatFollow,mountChatComposer:(_,options)=>mountChatComposer(_,{...options,doc:sandbox.document}),appendTaskReceipt:(root,id,options)=>appendTaskReceipt(root,id,{...options,doc:sandbox.document}),appendChatMessage:(root,role,text,options)=>appendChatMessage(root,role,text,{...options,doc:sandbox.document}),createActivity:(root,options)=>createActivity(root,{...options,doc:sandbox.document}),appendWorkflowCard:(root,proposal,apply,options)=>appendWorkflowCard(root,proposal,apply,{...options,doc:sandbox.document})});
 vm.runInContext(code+';globalThis.mount=mountAnalysisGuide',sandbox);const controller=sandbox.mount(new El(),{snapshot:()=>context,focusSettings(){},openWorkbench(value){applied.push(value);}});
 return {nodes,events,sent,applied,setReply:x=>{reply=x;},controller,setContext:x=>{context=x;},store};
}
const tick=()=>new Promise(resolve=>setImmediate(resolve));
test('agent mode persists across replies, context changes, and remounts',async()=>{
 const f=fixture();await tick();const mode=f.nodes.get('analysis-agent-mode');mode.checked=true;mode.handlers.change();
 f.setContext({workflow:'analysis',tab:'ana-cor',hasExperiment:true});f.controller.refresh();assert.equal(mode.checked,true);
 f.nodes.get('analysis-guide-question').value='fixture question';await f.nodes.get('analysis-guide-ask').onclick();assert.equal(mode.checked,true);
 const again=fixture(f.store);assert.equal(again.nodes.get('analysis-agent-mode').checked,true);
 mode.checked=false;mode.handlers.change();assert.equal(fixture(f.store).nodes.get('analysis-agent-mode').checked,false);
});
test('result interpretation remains read-only without turning persistent agent mode off',async()=>{
 const f=fixture({'emp_agent_mode_enabled_v1':'true'});await tick();f.events['emp:interpret-result']({detail:{question:'Interpret only',analysis_type:'differential'}});await tick();
 assert.equal(f.nodes.get('analysis-agent-mode').checked,true);assert.match(f.sent[0].question,/Local task submission is not granted/);
});

test('uploaded matrix triggers LLM guidance and count-compatible draft can populate steps without running',async()=>{
 const f=fixture({'emp_agent_mode_enabled_v1':'true'});await tick();
 const profile={feature_count:20,candidate_sample_columns:6,count_compatible:true,raw_count_provenance_verified:false};
 f.setContext({workflow:'workbench',tab:'main',hasExperiment:false,pageContext:{profile}});
 f.setReply({status:'ok',answer:'已准备 QC 与 PCA 步骤，分组仍需核对。',tool_results:[{tool:'propose_count_workflow',result:{status:'draft',steps:[{operation:'qc',parameters:{}}],execution_performed:false}}]});
 f.events['emp:dataset-profile']({detail:{profile}});await tick();await tick();
 assert.equal(f.sent.length,1);assert.match(f.sent[0].question,/count_compatible/);assert.equal(f.applied.length,1);
 assert.equal(f.applied[0].proposal.execution_performed,false);
});

test('send clears the input immediately, retains a new draft, and still shows the in-flight reply',async()=>{
 const f=fixture();await tick();let resolve;f.setReply(new Promise(r=>{resolve=r;}));
 const input=f.nodes.get('analysis-guide-question');input.value='first question';const pending=f.nodes.get('analysis-guide-ask').onclick();assert.equal(input.value,'');
 input.value='next draft';input.oninput();resolve({status:'ok',answer:'answer to first question'});await pending;
 assert.equal(input.value,'next draft');const text=n=>(n.textContent||'')+(n.children||[]).map(text).join('');assert.match(text(f.nodes.get('analysis-guide-answer')),/answer to first question/);assert.match(f.sent[0].question,/first question/);assert(!f.sent[0].question.includes('next draft'));
});
test('failed send restores an empty composer without losing the sent message',async()=>{
 const f=fixture();await tick();f.setReply({status:'error',answer:'Provider unavailable'});const input=f.nodes.get('analysis-guide-question');input.value='retry me';await f.nodes.get('analysis-guide-ask').onclick();assert.equal(input.value,'retry me');
});

test('send refreshes the actual page before capturing its context and Plan is optional',async()=>{
 const f=fixture({'emp_agent_mode_enabled_v1':'true'});await tick();f.setContext({workflow:'import',tab:'main',hasExperiment:false});
 f.nodes.get('analysis-guide-question').value='Import this selected matrix';await f.nodes.get('analysis-guide-ask').onclick();
 assert.match(f.sent[0].question,/Scope: import/);assert(!f.sent[0].question.includes('Call propose_agent_plan first'));
 f.nodes.get('analysis-plan-toggle').onclick();f.nodes.get('analysis-guide-question').value='Inspect the current matrix';await f.nodes.get('analysis-guide-ask').onclick();assert.match(f.sent[1].question,/Call propose_agent_plan first/);
});

test('an agent-submitted background job resumes the original request once after completion',async()=>{
 const f=fixture({'emp_agent_mode_enabled_v1':'true'});await tick();f.setContext({workflow:'analysis',tab:'ana-dim',hasExperiment:true,experimentName:'Fixture'});
 f.nodes.set('btn-dim',{closest:()=>({}),click:()=>f.events['emp:job-submitted']({detail:{job_id:'fixture-pca',experiment:'Fixture'}})});
 f.setReply({status:'ok',answer:'Submit PCA',tool_results:[{tool:'request_page_action',result:{action:'submit_current'}}]});
 f.nodes.get('analysis-guide-question').value='Run PCA then plot';await f.nodes.get('analysis-guide-ask').onclick();assert.equal(f.sent.length,1);
 f.setReply({status:'ok',answer:'Plot ready'});f.events['emp:jobs-updated']({detail:{jobs:[{id:'fixture-pca',status:'done',progress:100}]}});await new Promise(r=>setTimeout(r,10));
 assert.equal(f.sent.length,2);assert.match(f.sent[1].question,/fixture-pca/);assert.match(f.sent[1].question,/不要重复提交/);
 f.events['emp:jobs-updated']({detail:{jobs:[{id:'fixture-pca',status:'done',progress:100}]}});await tick();assert.equal(f.sent.length,2);
});
