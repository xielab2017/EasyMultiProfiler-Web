import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import {WorkflowState, resultTSV} from '../frontend/js/workbench_core.mjs';
const catalog={operations:{qc:{parameters:{}},normalize:{parameters:{}},pca:{parameters:{components:2}}}};
const steps=[{operation:'qc',parameters:{}},{operation:'normalize',parameters:{}},{operation:'pca',parameters:{components:2}}];
test('sample/parameter/order edits revoke exact plan and block stale responses',()=>{
  const state=new WorkflowState();state.setSteps(steps,catalog);const rev=state.revision;
  state.acceptPrepared({valid:true,plan_sha256:'abc'},rev);
  assert.throws(()=>state.executionRequest({plan_sha256:'abc'},false));
  assert.throws(()=>state.executionRequest({plan_sha256:'wrong'},true));
  assert.equal(state.executionRequest({plan_sha256:'abc'},true).confirmed,true);
  state.move(2,1);assert.equal(state.prepared,null);
  assert.throws(()=>state.acceptPrepared({valid:true},rev));
  assert.equal(state.steps[1].operation,'pca');
});
test('model proposals cannot smuggle code, unknown operations or duplicates into execution',()=>{
  const state=new WorkflowState();
  for(const invalid of [[{operation:'system',parameters:{}}],[steps[0],steps[0]],[{operation:'qc',parameters:{code:'stop()'}}]])assert.throws(()=>state.setSteps(invalid,catalog));
  state.setSteps(steps,catalog);steps[2].parameters.components=5;assert.equal(state.steps[2].parameters.components,2);
});
test('TSV retains missing statistics and protects spreadsheet text without changing numeric signs',()=>{
  const text=resultTSV([{feature_id:'=formula',log2FoldChange:-2,pvalue:null,padj:null}]);
  assert.match(text,/'=formula\t\t-2/);assert.doesNotMatch(text,/null|undefined/);
});
test('main page embeds workbench, explicit review, separate cloud consent and matrix handoff',()=>{
  const html=fs.readFileSync(new URL('../frontend/index.html',import.meta.url),'utf8');
  for(const id of ['page-workbench','matrix-open-workbench','wb-confirm','wb-cloud-consent','wb-context','wb-steps'])assert.ok(html.includes(`id="${id}"`));
  assert.match(html,/js\/workbench.js/);
});
