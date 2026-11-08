import test from 'node:test';import assert from 'node:assert/strict';
import {bindChatFollow,panelWidth,bindPanelResize} from '../frontend/js/chat_layout.mjs';
import {savedChatModels,mountChatComposer} from '../frontend/js/chat_composer.mjs';
class El{constructor(tag){this.tag=tag;this.children=[];this.handlers={};this.textContent='';this.style={};this.value='';}append(...nodes){this.children.push(...nodes);}replaceChildren(...nodes){this.children=nodes;}setAttribute(k,v){this[k]=v;}addEventListener(k,f){this.handlers[k]=f;}click(){this.onclick?.();}}
const doc={createElement:tag=>new El(tag)};
test('new messages follow the bottom, reading older content pauses, jump resumes',()=>{
 let mutation;const view=new El('div'),jump=new El('button');Object.assign(view,{scrollHeight:1000,clientHeight:500,scrollTop:500});
 const win={requestAnimationFrame:fn=>fn(),MutationObserver:class{constructor(fn){if(!mutation)mutation=fn;}observe(){}disconnect(){}}};const follow=bindChatFollow(view,jump,win);
 view.handlers.scroll();view.scrollHeight=1300;mutation();assert.equal(view.scrollTop,1300);
 view.handlers.wheel({deltaY:-10});view.scrollTop=100;view.handlers.scroll();view.scrollHeight=1800;mutation();assert.equal(view.scrollTop,100);assert.equal(jump.hidden,false);
 jump.onclick();assert.equal(view.scrollTop,1800);assert.equal(jump.hidden,true);follow.dispose();
});
test('panel dragging and keyboard changes are bounded and persisted',()=>{
 assert.equal(panelWidth(2000,1440,220),940);assert.equal(panelWidth(20,1440),300);
 const props={},saved={},body={classList:{add(){},remove(){}}},panel={ownerDocument:{documentElement:{style:{setProperty:(k,v)=>{props[k]=v;}}},body},getBoundingClientRect:()=>({width:420})},handle=new El('div');handle.setPointerCapture=()=>{};
 const win={innerWidth:1440,getComputedStyle:()=>({getPropertyValue:()=> '220px'}),addEventListener(){}};
 bindPanelResize(panel,handle,win,{getItem:k=>saved[k],setItem:(k,v)=>{saved[k]=v;},removeItem:k=>delete saved[k]});handle.handlers.pointerdown({button:0,clientX:1000,pointerId:1,preventDefault(){}});handle.handlers.pointermove({clientX:800});handle.handlers.pointerup();assert.equal(props['--code-lab-user-width'],'620px');assert.equal(saved.emp_chat_panel_width_v1,'620');
 handle.handlers.keydown({key:'ArrowLeft',preventDefault(){}});assert.equal(props['--code-lab-user-width'],'444px');
});
test('model picker exposes saved model names and catalogs without credentials or fake latest claims',()=>{
 const rows=savedChatModels({profiles:{minimax:{api_key:'SECRET',region:'china',model:'M3'},openai:{api_key:'KEY',model:'real-model'},deepseek:{model:'unconfigured'},campus:{model:'mixed'}}},{'minimax:china':{models:[{id:'M3'},{id:'M-VL'}]}});
 assert.equal(rows.length,3);assert(!JSON.stringify(rows).includes('SECRET'));assert(!rows.some(x=>x.model==='mixed'||x.model==='unconfigured'));assert(rows.some(x=>x.model==='M-VL'));
});
test('images uploaded or pasted enter an explicit removable attachment queue',async()=>{
 const original=globalThis.fetch,root=new El('div'),question=new El('textarea'),status=new El('p');let uploaded=0;
 globalThis.fetch=async()=>({ok:true,json:async()=>({id:'id'+(++uploaded),name:'figure.png',kind:'image',preview_url:'/local/image'})});
 try{const c=mountChatComposer(root,{question,agentLabel:new El('label'),actions:new El('div'),status,doc});await c.addFiles([{type:'image/png',name:'figure.png',size:40}]);assert(c.hasAttachments());const sent=c.take();assert.equal(sent.length,1);assert(c.hasAttachments());c.restore(sent);assert(c.hasAttachments());
  let prevented=false;question.handlers.paste({preventDefault:()=>{prevented=true;},clipboardData:{items:[{kind:'file',type:'image/png',getAsFile:()=>({type:'image/png',name:'paste.png',size:30})}]}});await new Promise(r=>setImmediate(r));assert(prevented);assert.equal(c.take().length,2);
 }finally{globalThis.fetch=original;}
});
test('clearing a conversation prevents a late upload from restoring its removed context',async()=>{
 const original=globalThis.fetch;let resolve;
 globalThis.fetch=async()=>({ok:true,json:()=>new Promise(r=>{resolve=r;})});
 try{const c=mountChatComposer(new El('div'),{question:new El('textarea'),agentLabel:new El('label'),actions:new El('div'),status:new El('p'),doc});const pending=c.addFiles([{type:'image/png',name:'late.png',size:40}]);await new Promise(r=>setImmediate(r));c.clear();resolve({id:'late',name:'late.png',kind:'image',preview_url:'/local/image'});await pending;assert(!c.hasAttachments());}finally{globalThis.fetch=original;}
});
test('thinking depth follows server capabilities, persists per model, and leaves unsupported models at default',()=>{
 const prior=globalThis.localStorage,values={};globalThis.localStorage={getItem:k=>values[k],setItem:(k,v)=>values[k]=v};
 try{const root=new El('div'),c=mountChatComposer(root,{question:new El('textarea'),agentLabel:new El('label'),actions:new El('div'),status:new El('p'),doc});
  const find=(node,id)=>node.id===id?node:node.children.map(n=>find(n,id)).find(Boolean);
  c.refreshModels({provider:'minimax',model:'MiniMax-M3.1-Flash',reasoning:{supported:true,levels:['auto','low','medium','high','xhigh','max']}});
  const effort=find(root,'analysis-reasoning-effort');effort.value='high';effort.onchange();assert.equal(c.reasoningEffort(),'high');
  c.refreshModels({provider:'minimax',model:'MiniMax-M3',reasoning:{supported:false,levels:['auto']}});assert.equal(c.reasoningEffort(),'auto');assert(effort.children.filter(n=>n.value!=='auto').every(n=>n.disabled));
  c.refreshModels({provider:'minimax',model:'MiniMax-M3.1-Flash',reasoning:{supported:true,levels:['auto','low','medium','high','xhigh','max']}});assert.equal(c.reasoningEffort(),'high');
 }finally{globalThis.localStorage=prior;}
});
