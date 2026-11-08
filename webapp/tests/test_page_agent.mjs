import test from 'node:test';import assert from 'node:assert/strict';
import {pageAgentContext,applyPageFields} from '../frontend/js/page_agent.mjs';
import {resolveAgentAction,resolveAgentNavigation} from '../frontend/js/agent_actions.mjs';
function fixture(){const changed=[],nodes={};for(const [id,tag,value]of [['matrix-accession','INPUT',''],['matrix-budget','INPUT','5'],['discovery-mode','SELECT','auto'],['api-key','INPUT','SECRET'],['rp-confirm','INPUT','false']])nodes[id]={id,tagName:tag,value,type:id==='matrix-budget'?'number':'text',min:id==='matrix-budget'?'.001':'',max:id==='matrix-budget'?'100':'',options:[{value:'auto',textContent:'Auto'},{value:'geo',textContent:'GEO'}],closest:()=>({}),dispatchEvent:event=>changed.push([id,event.type])};return {nodes,changed,doc:{getElementById:id=>nodes[id],querySelectorAll:()=>[]}};}
test('page snapshots include approved metadata controls, never key or review inputs',()=>{const f=fixture(),c=pageAgentContext('matrix',f.doc);assert(c.fields.some(x=>x.id==='matrix-accession'));assert(!JSON.stringify(c).includes('SECRET'));assert(!c.fields.some(x=>x.id==='rp-confirm'));});
test('field updates validate every item before mutation and preserve ordinary change events',()=>{const f=fixture();assert.throws(()=>applyPageFields('matrix',{'matrix-accession':'GSE60450','api-key':'bad'},f.doc));assert.equal(f.nodes['matrix-accession'].value,'');assert.throws(()=>applyPageFields('matrix',{'matrix-budget':1000},f.doc));assert.throws(()=>applyPageFields('matrix',{'discovery-mode':'code'},f.doc));applyPageFields('matrix',{'matrix-accession':'GSE60450','matrix-budget':2},f.doc);assert.equal(f.nodes['matrix-accession'].value,'GSE60450');assert.equal(f.changed.length,4);assert.throws(()=>applyPageFields('integration',{'rp-confirm':true},f.doc));});
test('matrix and workflow actions can guide before an R experiment is loaded without bypassing review',()=>{assert.equal(resolveAgentAction({workflow:'matrix',hasExperiment:false},'find_matrix_files',true).button,'matrix-resolve');assert.equal(resolveAgentAction({workflow:'workbench',hasExperiment:false},'build_workflow',true).button,'wb-template');assert.throws(()=>resolveAgentAction({workflow:'matrix'},'find_matrix_files',false));assert.throws(()=>resolveAgentAction({workflow:'matrix'},'run_integration',true));});
test('an authorized upload can run before any experiment exists and navigation only accepts registered routes',()=>{
 assert.equal(resolveAgentAction({workflow:'import',omics:'transcriptomics',hasExperiment:false},'submit_current',true).button,'agent-upload-transcriptomics');
 assert.throws(()=>resolveAgentAction({workflow:'import',omics:'unknown'},'submit_current',true));
 assert.deepEqual(resolveAgentNavigation('analysis:ana-diff'),{page:'analysis',tab:'ana-diff'});assert.throws(()=>resolveAgentNavigation('analysis:javascript'));assert.throws(()=>resolveAgentNavigation('https://elsewhere.test'));
 assert.deepEqual(resolveAgentNavigation('viz-volcano'),{page:'visualization',tab:'viz-volcano'});assert.deepEqual(resolveAgentNavigation('visualization/viz-volcano'),{page:'visualization',tab:'viz-volcano'});
});
test('requesting an already selected workflow operation is idempotent while other disabled options remain unavailable',()=>{
 const f=fixture();f.nodes['wb-operation']={id:'wb-operation',tagName:'SELECT',value:'volcano',options:[{value:'pca',disabled:true},{value:'volcano',disabled:false}],closest:()=>({})};
 assert.deepEqual(applyPageFields('workbench',{'wb-operation':'pca'},f.doc),[]);assert.equal(f.nodes['wb-operation'].value,'volcano');
 assert.throws(()=>applyPageFields('workbench',{'wb-operation':'unknown'},f.doc));
});
test('the agent sees ordination controls and cannot fill fields on an inactive plot tab',()=>{
 const f=fixture();for(const [id,active]of [['scat-group',true],['heat-height',false]])f.nodes[id]={id,tagName:'INPUT',value:'',type:'text',closest:selector=>selector==='.tab-panel'?{classList:{contains:name=>name==='active'&&active}}:{},dispatchEvent(){}};
 const context=pageAgentContext('visualization',f.doc);assert(context.fields.some(x=>x.id==='scat-group'));assert(!context.fields.some(x=>x.id==='heat-height'));
 assert.throws(()=>applyPageFields('visualization',{'heat-height':10},f.doc),/当前步骤/);assert.deepEqual(applyPageFields('visualization',{'scat-group':'Group'},f.doc),['scat-group']);
});

test('a stale active class on a hidden panel never exposes or mutates its controls',()=>{
 const f=fixture();f.nodes['heat-height']={id:'heat-height',tagName:'INPUT',type:'number',value:'9',closest:selector=>selector==='.tab-panel'?{classList:{contains:name=>['active','hidden'].includes(name)}}:{},dispatchEvent(){throw Error('must not mutate');}};
 assert(!pageAgentContext('visualization',f.doc).fields.some(x=>x.id==='heat-height'));
 assert.throws(()=>applyPageFields('visualization',{'heat-height':6},f.doc),/当前步骤/);assert.equal(f.nodes['heat-height'].value,'9');
});
