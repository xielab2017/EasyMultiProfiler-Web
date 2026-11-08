import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const code=fs.readFileSync(new URL('../frontend/js/runall_coverage.js',import.meta.url),'utf8').replaceAll('export function ','function ');
const context=vm.createContext({});vm.runInContext(code+';globalThis.read=readRunallCoverageOptions;globalThis.plan=runallCoveragePlan;globalThis.summary=summarizeRunallStages;',context);
function doc(overrides={}){
 const fields={'ra-do-correlation':{checked:true},'ra-do-cluster':{checked:true},'ra-do-method-figures':{checked:true},'ra-do-gsea':{checked:false},'ra-gsea-database':{value:'GO_BP'},'ra-gsea-top-n':{value:'3'},'ra-feature-top-n':{value:'100'},'ra-network-cutoff':{value:'.6'},'ra-seed':{value:'1'},'ra-ternary-groups':{value:''},...overrides};
 return {getElementById:id=>fields[id]};
}
test('one-click RNA options keep GSEA explicitly optional and emit bounded backend parameters',()=>{
 const options=context.read('rnaseq',doc());assert.equal(options.do_gsea,false);assert.equal(options.do_correlation,true);assert.equal(options.do_cluster,true);assert.equal(options.feature_top_n,100);assert.equal(options.ternary_groups,undefined);
 const enabled=context.read('rnaseq',doc({'ra-do-gsea':{checked:true},'ra-gsea-database':{value:'KEGG'},'ra-gsea-top-n':{value:'2'}}));assert.equal(enabled.do_gsea,true);assert.equal(enabled.gsea_database,'KEGG');assert.equal(enabled.gsea_top_n,2);
});
test('16S cannot silently choose the first three of four groups for a ternary diagram',()=>{
 const options=context.read('m16s',doc());assert.equal(options.ternary_groups,null);assert.equal(options.do_gsea,undefined);
 const plan=context.plan('m16s',options,{groups:['A','B','C','D']});const ternary=plan.find(row=>row.id==='ternary');assert.match(ternary.condition,/Requires exactly three groups/);
 const explicit=context.read('m16s',doc({'ra-ternary-groups':{value:'A,C,D'}}));assert.deepEqual(Array.from(explicit.ternary_groups),['A','C','D']);
 assert.throws(()=>context.read('m16s',doc({'ra-ternary-groups':{value:'A,A,C'}})),/three distinct groups/);
});
test('coverage plan represents disabled optional analyses without pretending they completed',()=>{
 const options=context.read('rnaseq',doc({'ra-do-correlation':{checked:false}}));const plan=context.plan('rnaseq',options,{enrichment:false});
 for(const id of ['ora_go','ora_kegg','gsea_analysis','gsea_curves','feature_correlation_network'])assert.equal(plan.find(row=>row.id===id).enabled,false);
 assert.equal(plan.find(row=>row.id==='differential').enabled,true);assert.equal(plan.find(row=>row.id==='sample_correlation').enabled,true);
 assert.ok(plan.every(row=>row.status===undefined));
});
test('stage summary uses server outcomes, retaining failed/skipped reasons rather than trusting 100 percent',()=>{
 const summary=context.summary({progress:100,counts:{done:100},stages:[{id:'pca',status:'done'},{id:'gsea',status:'skipped',reason:'Disabled'},{id:'de',status:'error',reason:'Invalid counts'}]});
 assert.equal(summary.counts.done,1);assert.equal(summary.counts.skipped,1);assert.equal(summary.counts.error,1);assert.equal(summary.partial,true);assert.equal(summary.rows[2].reason,'Invalid counts');
 assert.equal(context.summary({progress:100}).rows.length,0);
});
test('invalid expensive analysis bounds are rejected before submission',()=>{
 assert.throws(()=>context.read('rnaseq',doc({'ra-feature-top-n':{value:'100000'}})),/Feature cap/);
 assert.throws(()=>context.read('rnaseq',doc({'ra-network-cutoff':{value:'0'}})),/Network cutoff/);
 assert.throws(()=>context.read('rnaseq',doc({'ra-gsea-top-n':{value:'20'}})),/GSEA/);
 assert.throws(()=>context.read('m16s',doc({'ra-seed':{value:'1.5'}})),/Seed/);
});

test('full RNA workflow enables GSEA by default in the actual page',()=>{
 const html=fs.readFileSync(new URL('../frontend/index.html',import.meta.url),'utf8');assert.match(html,/<input id="ra-do-gsea"[^>]*checked/);
});
