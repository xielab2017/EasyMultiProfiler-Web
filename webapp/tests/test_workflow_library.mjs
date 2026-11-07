import test from 'node:test';
import assert from 'node:assert/strict';
import {WORKFLOW_LIBRARY,WorkflowComposer,validateBlueprint,proposeForScope} from '../frontend/js/workflow_library.mjs';
import {guideFor,modelQuestion} from '../frontend/js/analysis_guide_model.mjs';
import {parseDiscovery,geoCandidates} from '../frontend/js/discovery_model.mjs';

test('all eight omics have valid minimal, exploratory and comparative presets',()=>{
  assert.equal(Object.keys(WORKFLOW_LIBRARY).length,8);
  for(const scope of Object.keys(WORKFLOW_LIBRARY))for(const name of ['minimal','exploratory','differential']){
    const c=new WorkflowComposer(scope);c.preset(name);assert.ok(c.status().valid,scope+' '+name);
    for(const [op,def]of Object.entries(c.library.steps))if(def.required)assert.ok(c.steps.some(s=>s.operation===op));
    if(scope!=='bulk_rnaseq')assert.equal(c.status().executable,false);
  }
});
test('required gates cannot be removed and dependent analysis cannot precede normalization',()=>{
  const c=new WorkflowComposer();const before=c.blueprint();
  assert.equal(c.remove('qc').code,'required');assert.deepEqual(c.blueprint(),before);
  assert.equal(c.remove('normalize').code,'dependency');
  const i=c.steps.findIndex(s=>s.operation==='pca');assert.equal(c.move(i,i-1).code,'order');assert.deepEqual(c.blueprint(),before);
  c.remove('pca');c.remove('heatmap');assert.equal(c.remove('normalize').ok,true);assert.ok(c.status().valid);
});
test('adding a step restores dependencies, while rarefaction and imputation remain optional',()=>{
  const c=new WorkflowComposer();c.preset('minimal');c.add('heatmap');
  assert.deepEqual(c.steps.map(s=>s.operation),['data_input','sample_metadata','qc','normalize','heatmap','export']);
  for(const scope of ['proteomics','metabolomics']){const p=new WorkflowComposer(scope);assert.equal(p.library.steps.impute.required,false);assert.ok(!p.steps.some(s=>s.operation==='impute'));}
  assert.equal(new WorkflowComposer('microbiome_16s').library.steps.rarefy.required,false);
});
test('input types reject count-only methods and conditionally require peak calling for BAM',()=>{
  const c=new WorkflowComposer();c.inputType='tpm';assert.equal(c.status().valid,false);assert.equal(c.status().executable,false);assert.throws(()=>c.countSteps());
  const chip=new WorkflowComposer('chipseq');chip.inputType='bam';chip.preset('exploratory');
  const ops=chip.steps.map(s=>s.operation);assert.ok(ops.indexOf('peak_call')<ops.indexOf('annotation'));assert.ok(chip.status().valid);
});
test('only supported count operations compile, and incompatible additions block execution',()=>{
  const c=new WorkflowComposer();assert.deepEqual(c.countSteps().map(s=>s.operation),['qc','normalize','pca','deseq2','heatmap']);
  c.add('enrichment');assert.ok(c.status().valid);assert.equal(c.status().executable,false);assert.throws(()=>c.countSteps());
  assert.equal(c.status().nativeExecutable,true);assert.deepEqual(c.status().deferred,['enrichment']);assert.ok(c.connectedCountSteps().some(step=>step.operation==='deseq2'));
  const plan=c.blueprint();plan.steps[0].code='stop()';assert.equal(validateBlueprint(plan).valid,false);assert.throws(()=>new WorkflowComposer().load(plan));
  const broken=new WorkflowComposer().blueprint();broken.steps[0]=null;assert.equal(validateBlueprint(broken).valid,false);
});
test('saved plans are detached and preserve user parameter choices',()=>{
  const c=new WorkflowComposer();c.steps.find(s=>s.operation==='deseq2').parameters.min_count=23;
  const saved=c.blueprint();const loaded=new WorkflowComposer().load(saved);saved.steps[0].parameters.fake=1;
  assert.equal(loaded.steps.find(s=>s.operation==='deseq2').parameters.min_count,23);assert.deepEqual(loaded.steps[0].parameters,{});
});
test('local natural language respects selected omics and cannot turn ambiguous negation into actions',()=>{
  const draft=proposeForScope('代谢组做 PCA、差异分析和热图','metabolomics','intensity');
  assert.equal(draft.blueprint.scope,'metabolomics');assert.equal(draft.execution_performed,false);assert.ok(validateBlueprint(draft.blueprint).valid);assert.ok(draft.blueprint.steps.some(n=>n.operation==='differential'));
  assert.equal(validateBlueprint(draft.blueprint).executable,false);
  const clinical=proposeForScope('基线三线表','clinical','clinical_table');assert.ok(clinical.blueprint.steps.some(n=>n.operation==='three_line'));assert.ok(!clinical.blueprint.steps.some(n=>n.operation==='systematic'));
  assert.throws(()=>proposeForScope('不要填补，PCA','proteomics','intensity'));
  assert.throws(()=>proposeForScope('PCA','bulk_rnaseq','tpm'));
});
test('clinical guide distinguishes selection from validation and never proposes count execution',()=>{
  const g=guideFor({workflow:'clinical',tab:'three_line',hasStandaloneClinical:true,hasGroup:false,omics:'transcriptomics'});
  assert.equal(g.inputSelectionComplete,false);assert.equal(g.countWorkflowAvailable,false);assert.equal(g.executable,false);assert.equal(g.analysisExecuted,false);
  const q=modelQuestion('Explain missingness',{workflow:'clinical',tab:'three_line',experimentName:'private-name',sample_ids:['private-sample']});
  assert.ok(q.includes('clinical'));assert.ok(!q.includes('private-'));
});
test('discovery recognizes batched GEO, DOI, PMID, URLs and titles with explicit bounds',()=>{
  assert.deepEqual(parseDiscovery('gse60450, GSE305056\nGSE60450').accessions,['GSE60450','GSE305056']);
  assert.equal(parseDiscovery('https://doi.org/10.1186/s13059-014-0550-8').kind,'doi');
  assert.equal(parseDiscovery('PMID:25516281').pmid,'25516281');
  assert.equal(parseDiscovery('https://pubmed.ncbi.nlm.nih.gov/25516281/').kind,'pmid');
  assert.equal(parseDiscovery('A paper title containing GSE60450').kind,'title');
  assert.throws(()=>parseDiscovery(Array.from({length:11},(_,i)=>'GSE'+(i+1)).join(',')));
  assert.throws(()=>parseDiscovery('https://private.example/path'));assert.throws(()=>parseDiscovery(''));
  assert.equal(geoCandidates({accessions:[{accession:'GSE1'},{accession:'GSE1'},{accession:'SRP1'}]}).length,1);
});
