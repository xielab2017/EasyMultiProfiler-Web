import test from 'node:test';import assert from 'node:assert/strict';
import {renderRichText,appendChatMessage,createActivity,appendWorkflowCard,appendTaskReceipt} from '../frontend/js/chat_presentation.mjs';
import {guideFor,modelQuestion} from '../frontend/js/analysis_guide_model.mjs';
class El{constructor(tag){this.tag=tag;this.children=[];this.textContent='';}append(...nodes){this.children.push(...nodes);}replaceChildren(...nodes){this.children=nodes;}}
const doc={createElement:tag=>new El(tag)},all=n=>[n,...n.children.flatMap(all)],text=n=>n.textContent+n.children.map(text).join('');
test('chat renders readable headings, tables, code and lists without executing HTML',()=>{
 const root=new El('div');renderRichText(root,'## 推荐流程\n**先做 QC**\n\n|步骤|操作|\n|---|---|\n|1|`PCA`|\n\n- 核对样本\n- 保存结果\n<img src=x onerror=alert(1)>\n[危险](javascript:alert) [来源](https://example.org)',doc);
 assert.equal(all(root).filter(n=>n.tag==='table').length,1);assert(all(root).some(n=>n.tag==='strong'&&n.textContent==='先做 QC'));assert(!all(root).some(n=>n.tag==='img'||n.tag==='script'));
 assert.equal(all(root).filter(n=>n.tag==='a').length,1);assert.match(text(root),/<img src=x/);assert(!text(root).includes('##'));
});
test('progress records report actual stages, preserve handoff outcomes and separate draft from execution',()=>{
 const root=new El('div');appendChatMessage(root,'user','**literal user input**',{doc});assert.match(text(root),/\*\*literal/);
 const activity=createActivity(root,{doc});activity.update([{stage:'tool_finished',tool:'propose_count_workflow',status:'ok',duration_ms:35}]);activity.note('已填入草案');activity.finish(true);assert.equal(activity.card.open,false);assert.match(text(activity.card),/生成分析步骤草案/);
 let applied=false;const card=appendWorkflowCard(root,{steps:[{operation:'qc',parameters:{}}]},()=>{applied=true;},{doc});assert.match(text(card),/尚未执行/);all(card).find(n=>n.tag==='button').onclick();assert(applied);
});
test('new data pages have usable guidance and preserve their actual scope in model context',()=>{
 for(const workflow of ['matrix','integration','workbench']){assert(guideFor({workflow},'zh').steps.length>0);assert.match(modelQuestion('请推荐流程',{workflow,tab:'main',pageContext:{profile:{count_compatible:false}}}),new RegExp('UI scope: '+workflow));}
 const q=modelQuestion('字'.repeat(3250),{workflow:'workbench',pageContext:{fields:Array.from({length:30},(_,i)=>({id:'id'+i,value:'A'.repeat(1000)}))}});assert(q.length<=3800);
});
test('task receipts use server job progress and do not equate submission with completion',()=>{
 const root=new El('div'),receipt=appendTaskReceipt(root,'fixture-job',{doc});assert.match(text(root),/等待服务端/);assert(!text(root).includes('已完成'));
 receipt.update({status:'running',progress:42,message:'PCA'});assert.match(text(root),/运行中 · 42%/);
 receipt.update({status:'error',progress:42,message:'Missing groups'});assert.match(text(root),/失败/);assert(!text(root).includes('已完成'));
});
