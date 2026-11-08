import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const source=fs.readFileSync(new URL('../frontend/js/viz_method_library.js',import.meta.url),'utf8').replaceAll('export function ','function ');
const sandbox=vm.createContext({URL});vm.runInContext(source+';globalThis.label=figureMethodLabel;globalThis.catalog=applicableFigureMethods;globalThis.payload=methodLibraryPayload',sandbox);
const ids=omics=>Array.from(sandbox.catalog(omics),item=>item.id);
test('plot directory respects omics and keeps clinical/ChIP separate from gene-based analyses',()=>{
 assert.deepEqual(ids('clinical'),['clinical']);assert.deepEqual(ids('chipseq'),['tracks']);
 assert.ok(ids('microbiome_16s').includes('ternary'));assert.ok(!ids('microbiome_16s').includes('gsea'));
 assert.ok(!ids('metabolomics').includes('enrichment'));assert.ok(ids('metabolomics').includes('de_scatter'));
 assert.ok(ids('proteomics').includes('ordination'));assert.ok(ids('proteomics').includes('heatmap'));
 assert.ok(ids('metagenomics').includes('ternary'));assert.ok(!ids('transcriptomics').includes('ternary'));
});
test('ternary API contract preserves group order, feature labels, colors and data provenance',()=>{
 const body=sandbox.payload('ternary',{width:9,height:7,base_size:12,title:'Fixture',group_var:'Condition',groups:['A','B','C'],top_n:25,label_features:'Taxon1,Taxon2\nTaxon3',max_point_size:8,point_alpha:.7,group_colors:['#111111','#222222','#333333']},{session_id:'session',experiment:'Counts',omics:'microbiome_16s'});
 assert.equal(body.method,'ternary');assert.equal(body.experiment,'Counts');assert.equal(body.group_var,'Condition');
 assert.deepEqual(Array.from(body.groups),['A','B','C']);assert.deepEqual(Array.from(body.label_features),['Taxon1','Taxon2','Taxon3']);
 assert.equal(body.top_n,25);assert.equal(body.point_alpha,.7);assert.equal(body.matrix,undefined);
 assert.deepEqual(Array.from(body.group_colors),['#111111','#222222','#333333']);
});
test('invalid ternary groups or incompatible omics are blocked before an API request',()=>{
 const context={session_id:'session',experiment:'Counts',omics:'microbiome_16s'};
 assert.throws(()=>sandbox.payload('ternary',{groups:['A','A','B'],group_var:'Group'},context),/three distinct groups/);
 assert.throws(()=>sandbox.payload('ternary',{groups:['A','B','C'],group_var:'Group'},{...context,omics:'clinical'}),/not available/);
 assert.throws(()=>sandbox.payload('ternary',{},{}),/Import and select/);
});
test('DE scatter requests saved statistics with explicit axes and adjusted-P thresholds',()=>{
 const body=sandbox.payload('de_scatter',{width:9,height:7,base_size:12,x_transform:'sqrt',padj_threshold:'.01',lfc_threshold:'1.5',label_genes:'Gene1,Gene2',n_labels:'5',point_size:'1.5',up_color:'#C96144',down_color:'#5185C0',ns_color:'#B2BAC2'},{session_id:'session',experiment:'Proteins',omics:'proteomics'});
 assert.equal(body.source,'current_diff');assert.equal(body.x_transform,'sqrt');assert.equal(body.padj_threshold,.01);
 assert.equal(body.lfc_threshold,1.5);assert.equal(body.n_labels,5);assert.deepEqual(Array.from(body.label_genes),['Gene1','Gene2']);
 assert.equal(body.fit_model,undefined);assert.equal(body.phenotype,undefined);
});

test('method downloads use their own authenticated API route and reject other routes',()=>{
 const url=vm.runInContext("methodLibraryDownloadUrl('/api/visualize/method-library/file/session/method_plot_123.pdf','http://localhost:8000/api','http://localhost:8080/')",sandbox);
 assert.equal(url,'http://localhost:8000/api/visualize/method-library/file/session/method_plot_123.pdf');
 assert.throws(()=>vm.runInContext("methodLibraryDownloadUrl('/api/visualize/enrichment/file/session/other.pdf','http://localhost:8000/api','http://localhost:8080/')",sandbox),/Unexpected/);
});

test('plot directory labels follow Chinese and English without changing stable method IDs',()=>{assert.match(sandbox.label('ternary','zh'),/三元/);assert.equal(sandbox.label('ternary','en'),'Ternary composition · Method library');assert.equal(sandbox.catalog('microbiome_16s').find(x=>x.id==='ternary').tab,'viz-ternary');});
