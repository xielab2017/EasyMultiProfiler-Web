import assert from 'node:assert/strict';
import {WorkflowComposer} from '../frontend/js/workflow_library.mjs';
import {makeTemplate,readTemplate,pendingQuestions,clarification,resultEvidence,designSummary,directionRows} from '../frontend/js/rnaseq_plan_review.mjs';

const composer=new WorkflowComposer();
const original=composer.blueprint();
original.steps.find(s=>s.operation==='deseq2').parameters.alpha=.02;
original.steps[0].id='this-sample-identifier-must-not-travel';
const json=JSON.stringify(makeTemplate(original,91));
assert.ok(!json.includes('this-sample-identifier-must-not-travel'));
const template=readTemplate(JSON.parse(json));
const second=new WorkflowComposer();
second.load(template.blueprint);
assert.equal(template.seed,91);
assert.equal(second.steps.find(s=>s.operation==='deseq2').parameters.alpha,.02);
assert.throws(()=>readTemplate({...template,dataset_id:'old-dataset'}));
assert.throws(()=>readTemplate({...template,seed:0}));
assert.throws(()=>makeTemplate({...original,input_type:'tpm'},91));
assert.throws(()=>readTemplate({...template,blueprint:{...template.blueprint,steps:[]}}));
assert.deepEqual(pendingQuestions({differential:true}),['input','evidence','groups','contrast','independence']);
assert.deepEqual(pendingQuestions({differential:true,hasDataset:true,hasEvidence:true,groupsReviewed:true,hasContrast:true,independent:true}),[]);
assert.match(clarification('analysis_goal','zh'),/PCA/);
const old=resultEvidence({plan:{source:'old.csv',source_sha256:'old-hash',seed:123}, environment:{r_version:'4.2.1'}});
assert.equal(old.data.source,'old.csv');assert.equal(old.parameters.seed,123);
assert.equal(old.software.web_version,undefined);assert.equal(old.software.r_version,'4.2.1');
console.log('Portable parameter templates, missing design questions and historical evidence passed.');

const direction=designSummary({samples:[{group:'处理组'},{group:'处理组'},{group:'对照组'}],contrasts:[{test:'处理组',reference:'对照组'}],differential:true},'zh');
assert.match(direction[0],/3 个样本.*处理组 \(n=2\).*对照组 \(n=1\)/);
assert.match(direction.at(-1),/实验组 处理组 \/ 参考组 对照组/);
for(const method of ['edgeR','DESeq2']){
  const row=(feature_id,fx,q)=>method==='edgeR'?{feature_id,logFC:fx,FDR:q}:{feature_id,log2FoldChange:fx,padj:q};
  const directions=directionRows({method,alpha:.05,rows:[row('positive',3,.01),row('negative',-2,.02),row('boundary',5,.05),row('untested',4,null),row('zero',0,.01)]});
  assert.deepEqual(directions.up.map(x=>x.gene),['positive']);
  assert.deepEqual(directions.down.map(x=>x.gene),['negative']);
}
