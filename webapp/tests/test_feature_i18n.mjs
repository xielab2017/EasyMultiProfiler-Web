import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import {FEATURE_TEXT, FEATURE_NAV, featureText, applyFeatureLocale} from '../frontend/js/feature_i18n.mjs';
import {WorkflowState} from '../frontend/js/workbench_core.mjs';

test('all static matrix/workbench text and placeholders have English translations',()=>{
  const html=fs.readFileSync(new URL('../frontend/index.html',import.meta.url),'utf8');
  const sources=[...html.matchAll(/data-feature-(?:text|placeholder|title|aria)="([^"]+)"/g)].map(m=>m[1].replaceAll('&quot;','"').replaceAll('&amp;','&'));
  assert.ok(sources.length>70);
  for(const source of sources)assert.ok(FEATURE_TEXT[source],source);
  assert.equal(featureText('上移','en'),'Move up');
  assert.equal(featureText('Move up','zh'),'上移');
  assert.equal(featureText('R 执行器已连接 · R {r} · DESeq2 {deseq2}','en',{r:'4.6.1',deseq2:'1.52.0'}),'R executor connected · R 4.6.1 · DESeq2 1.52.0');
  assert.equal(Object.keys(FEATURE_NAV).length,11);
});
test('locale rendering changes UI text without altering input values or plan consent',()=>{
  const button={dataset:{featureText:'运行已审核流程'},textContent:'运行已审核流程'};
  const input={value:'真实组别',checked:true,dataset:{featurePlaceholder:'填写真实组别'},setAttribute(k,v){this[k]=v;}};
  const status={dataset:{featureMessage:'取消请求：{status}',featureVars:'{"status":"cancelled"}'},textContent:''};
  const doc={querySelectorAll(selector){return selector==='[data-feature-text]'?[button]:selector==='[data-feature-placeholder]'?[input]:selector==='[data-feature-message]'?[status]:[];}};
  const state=new WorkflowState();state.steps=[{id:'s',operation:'qc',parameters:{}}];state.prepared={valid:true,plan_sha256:'hash'};
  const before=JSON.stringify(state);
  applyFeatureLocale(doc,'en');assert.equal(button.textContent,'Run reviewed workflow');assert.equal(input.placeholder,'Enter the documented group');assert.equal(status.textContent,'Cancellation request: cancelled');
  assert.equal(input.value,'真实组别');assert.equal(input.checked,true);assert.equal(JSON.stringify(state),before);
  applyFeatureLocale(doc,'zh');assert.equal(button.textContent,'运行已审核流程');assert.equal(input.value,'真实组别');
});
test('file entry notice works without modules and leaves HTTP pages alone',()=>{
  const source=fs.readFileSync(new URL('../frontend/js/file_entry.js',import.meta.url),'utf8');
  for(const protocol of ['file:','http:']){
    const elements=Object.fromEntries(['file-open-notice','file-open-link','file-open-title','file-open-description','file-open-help'].map(id=>[id,{hidden:true,textContent:'',focus(){this.focused=true;}}]));
    const doc={readyState:'complete',documentElement:{lang:'en'},getElementById:id=>elements[id]};
    vm.runInNewContext(source,{window:{location:{protocol},EMP_RUNTIME_PORTS:{web:18080}},document:doc,localStorage:{getItem:()=> 'en'}});
    assert.equal(elements['file-open-notice'].hidden,protocol!=='file:');
    if(protocol==='file:'){assert.equal(elements['file-open-link'].href,'http://127.0.0.1:18080/');assert.equal(elements['file-open-title'].textContent,'Open the running application');}
  }
});
