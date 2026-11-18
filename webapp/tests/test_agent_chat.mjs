import {createChatHistory,conversationMarkdown,downloadMarkdown} from '../frontend/js/chat_history.mjs';
import {buildUIIndex,localizeUI} from '../frontend/js/ui_language.mjs';
import {UI_LANGUAGE_ALIASES} from '../frontend/js/ui_language_aliases.mjs';
import {UI_LANGUAGE_PAIRS} from '../frontend/js/ui_language_catalog.mjs';
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
 Object.assign(sandbox,{createChatHistory,conversationMarkdown,downloadMarkdown,assertAgentSubmission,agentMemory,bindChatFollow,mountChatComposer:(_,options)=>mountChatComposer(_,{...options,doc:sandbox.document}),appendTaskReceipt:(root,id,options)=>appendTaskReceipt(root,id,{...options,doc:sandbox.document}),appendChatMessage:(root,role,text,options)=>appendChatMessage(root,role,text,{...options,doc:sandbox.document}),createActivity:(root,options)=>createActivity(root,{...options,doc:sandbox.document}),appendWorkflowCard:(root,proposal,apply,options)=>appendWorkflowCard(root,proposal,apply,{...options,doc:sandbox.document})});
 vm.runInContext(code+';globalThis.mount=mountAnalysisGuide',sandbox);
 sandbox.mount(root,{snapshot:()=>context,focusSettings(){},openWorkbench(){}});
 await new Promise(r=>setImmediate(r));
 find('analysis-guide-question').value='运行当前分析';
 assert.equal(find('analysis-guide-consent'),undefined);
 find('analysis-agent-mode').value=reviewed?'agent':'chat';
 await find('analysis-guide-ask').onclick();
 return {submitted,root,find};
}
test('chat dispatches one reviewed action and retains the requested agent preference',async()=>{
 const f=await fixture(true);assert.equal(f.submitted,1);assert.equal(f.find('analysis-agent-mode').value,'agent');
 assert.ok(flatten(f.root).some(n=>n.textContent.includes('页面校验')));
});
test('a model tool request cannot submit an analysis without the local review grant',async()=>{
 const f=await fixture(false);assert.equal(f.submitted,0);
 assert.ok(!flatten(f.root).some(n=>n.textContent.includes('页面校验')));
});
test('unconfigured models leave the question and send control available with a clear configuration hint',async()=>{
 const f=await fixture(false,false);assert.equal(f.submitted,0);
 assert.equal(f.find('analysis-guide-question').value,'运行当前分析');
 assert.equal(f.find('analysis-guide-ask').disabled,false);
 assert.ok(flatten(f.root).some(n=>n.textContent.includes('当前模型配置尚未加载')));
});

test('Markdown and TXT attachments use document MIME types and remain visibly removable for follow-up',async()=>{
 const root=new El('div'),doc={createElement:tag=>new El(tag)},status=new El('p');
 const composer=mountChatComposer(root,{question:new El('textarea'),agentLabel:new El('label'),actions:new El('div'),status,doc});
 const oldFetch=globalThis.fetch,requests=[];
 globalThis.fetch=async(path,opts)=>{
  requests.push(opts.headers['Content-Type']);
  const name=decodeURIComponent(opts.headers['X-Attachment-Name']);
  return {ok:true,json:async()=>({kind:'text',id:String(requests.length),name,chars_inspected:100,truncated:true})};
 };
 try{
  await composer.addFiles([{name:'paper.MD',type:'',size:100},{name:'notes.txt',type:'application/octet-stream',size:200}]);
  assert.deepEqual(requests,['text/markdown','text/plain']);
  assert.equal(composer.take().length,2);assert.equal(composer.take().length,2);
  const chip=flatten(root).find(n=>n.className==='agent-attachment-chip');
  assert.match(chip.children[0].textContent,/paper.MD.*100.*节选/);
  chip.children.at(-1).onclick();assert.deepEqual(composer.take().map(item=>item.name),['notes.txt']);
  await composer.addFiles([{name:'large.md',type:'',size:1024**2+1}]);
  assert.match(status.textContent,/1 MiB/);assert.equal(requests.length,2);
 }finally{globalThis.fetch=oldFetch;}
});

test('response format labels retain their own meaning through full UI localization and locale switches',()=>{
 const root=new El('div'),doc={createElement:tag=>new El(tag)};
 let locale='zh';
 const composer=mountChatComposer(root,{question:new El('textarea'),agentLabel:new El('label'),actions:new El('div'),status:new El('p'),doc,getLanguage:()=>locale,isEnglish:()=>locale!=='zh'});
 const output=flatten(root).find(element=>element.id==='analysis-output-type');
 const index=buildUIIndex({},UI_LANGUAGE_PAIRS,UI_LOCALES_FULL,UI_LANGUAGE_ALIASES);
 for(const [language,expected] of [['zh',['回答','摘要','比较表','研究笔记','要点','研究方法','局限性','流程图']],['ja',['回答','要約','比較表','研究ノート','要点','研究方法','限界','図解']],['en',['Answer','Summary','Comparison table','Research note','Key points','Methodology','Limitations','Diagram']],['zh',['回答','摘要','比较表','研究笔记','要点','研究方法','局限性','流程图']]]){
  locale=language;composer.render();
  const optionNode=option=>({tagName:'OPTION',value:option.value,closest:selector=>selector==='select'?output:null,childNodes:[{nodeType:3,textContent:option.textContent}]});
  const options=output.children.map(optionNode),navigation={nodeType:3,textContent:'Summary'};
  localizeUI({querySelectorAll:()=>[...options,{tagName:'SPAN',closest:()=>null,childNodes:[navigation]}]},{locale,index,translate:key=>key});
  assert.deepEqual(options.map(option=>option.childNodes[0].textContent),expected);
  if(locale==='zh')assert.equal(navigation.textContent,'概览');
 }
});

test('paper reading shortcuts select a matching style without overwriting a draft or sending it',()=>{
  const root=new El('div'),doc={createElement:tag=>new El(tag)},question=new El('textarea');
  const composer=mountChatComposer(root,{question,agentLabel:new El('label'),actions:new El('div'),status:new El('p'),doc});
  composer.refreshModels({chat_contract_version:2});
  question.value='Compare study designs';
  const buttons=flatten(root).find(node=>node.className==='agent-reading-actions').children;
  for(const [i,type] of ['summary','points','methods','limits','diagram'].entries()){
    buttons[i].onclick();
    assert.equal(flatten(root).find(node=>node.id==='analysis-output-type').value,type);
    assert.equal(question.value,'Compare study designs');
    assert.match(composer.outputInstruction(),/evidence|supported|study design|reported/i);
  }
});

test('PMC excerpts retain evidence from later sections and account for omitted text',async()=>{
  const {sectionExcerpts}=await import('../frontend/js/paper_reading.mjs');
  const sections=['Introduction '+'A'.repeat(500),'Methods','Results '+'B'.repeat(550),'Discussion '+'C'.repeat(600)];
  const short=sectionExcerpts(sections,400);
  assert.equal(short.excerpt,true);assert(short.text.length<=400);
  for(const name of ['Introduction','Methods','Results','Discussion','[…]'])assert(short.text.includes(name));
  assert.deepEqual(sectionExcerpts(['Source','Result']),{text:'Source\n\nResult',excerpt:false});
});
