import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const code=fs.readFileSync(new URL('../frontend/js/viz_enrichment.js',import.meta.url),'utf8').replace('export function initEnrichmentVisualization','function initEnrichmentVisualization');
class El{
 constructor(tag='div'){this.tag=tag;this.children=[];this.textContent='';this.style={};this.dataset={};this.listeners={};this.classList={add(){},remove(){}};this._value=undefined;}
 get value(){return this._value??this.children[0]?.value??'';}set value(value){this._value=value;}
 get options(){return this.children;}get selectedOptions(){return this.children.filter(row=>row.selected);}
 replaceChildren(...children){this.children=children;this._value=undefined;}append(...children){this.children.push(...children);}
 querySelector(selector){if(selector==='.plot-toolbar')return this.toolbar;if(selector==='.tab-bar')return this.bar;return null;}
 addEventListener(name,fn){this.listeners[name]=fn;}
 click(){this.clicked=true;return this.onclick?.();}remove(){}
}
function fixture(){
 const ids=new Map(),posts=[],downloads=[],rendered=[],listeners={};
 const get=id=>{if(!ids.has(id))ids.set(id,new El());return ids.get(id);};
 for(const prefix of ['enrich-viz','gsea-viz']){
  for(const name of ['source','terms','pathway','status','generate','refresh','output','file','analysis','ranked'])get(prefix+'-'+name);
  for(const [name,val]of Object.entries({width:'9',height:'6',font:'12',title:'Title',weight:'1',line:'#228855',set:'Set',sort:'p.adjust','top-n':'20',cutoff:'.05',wrap:'45',size:'8',low:'#ff0000',high:'#0000ff',highlight:''}))get(prefix+'-'+name).value=val;
 }
 get('page-visualization').bar=new El();get('viz-enrichment-dotplot');get('omics-pipeline').value='transcriptomics';
 const sources=[{source_job:'ora-job',kind:'ora',omics:'transcriptomics',experiment:'RNA / sample',label:'GO result'}, {source_job:'current_gsea',kind:'gsea',omics:'transcriptomics',experiment:'RNA / sample',label:'GSEA result'}];
 const storage={emp_session_id:'test-session',emp_api_token:'test-token',emp_student_token:'test-student'};
 const API={apiBase:()=> 'http://localhost:8000/api',request:async(method,path,body)=>{
  posts.push({method,path,body});
  if(method==='GET')return {sources};
  if(path.endsWith('/results'))return {data:[{ID:'GO:001',Description:'Pathway',Count:5,GeneRatio:'5/20'}]};
  return {plot:'cGxvdA==',download_urls:{pdf:'/api/visualize/enrichment/file/test-session/figure.pdf'}};
 }};
 const sandbox=vm.createContext({document:{getElementById:get,createElement:tag=>new El(tag),querySelector:()=>null},
  window:{_emp:{currentExp:'RNA / sample'},addEventListener:(name,fn)=>{listeners[name]=fn;},dispatchEvent(){}},
  localStorage:{getItem:key=>storage[key]||null},location:{href:'http://localhost:8080/'},URL,Blob,CustomEvent:class{},setTimeout(){},
  fetch:async(url,options)=>{downloads.push({url,options});return {ok:true,blob:async()=>new Blob(['pdf'])};}});
 vm.runInContext(code+';globalThis.init=initEnrichmentVisualization',sandbox);
 sandbox.init({API,showPlot:(id,png)=>{rendered.push({id,png});get(id).toolbar=new El();},navigateTo(){}});
 return {get,posts,downloads,rendered,sources,listeners,window:sandbox.window};
}
test('source refresh passes experiment context, separates ORA sources and retains the selected job',async()=>{
 const f=fixture();await f.get('enrich-viz-refresh').click();
 assert.equal(f.posts[0].path,'/visualize/enrichment/sources/test-session?experiment=RNA%20%2F%20sample&omics=transcriptomics&scope=single');
 assert.equal(f.get('enrich-viz-source').options.length,2);
 assert.equal(f.get('gsea-viz-source').options.length,3);
 f.get('enrich-viz-source').value='ora-job';await f.get('enrich-viz-refresh').click();
 assert.equal(f.get('enrich-viz-source').value,'ora-job');
 assert.equal(f.get('enrich-viz-terms').options[0].value,'GO:001');
});
test('an ORA source with empty full rankings cannot submit a GSEA plot',async()=>{
 const f=fixture();await f.get('gsea-viz-refresh').click();f.get('gsea-viz-source').value='ora-job';
 await f.get('gsea-viz-generate').click();
 assert.equal(f.posts.filter(row=>row.path.endsWith('/gsea')).length,0);
 assert.match(f.get('gsea-viz-status').textContent,/普通富集表不能推导/);
 assert.equal(f.get('gsea-viz-generate').disabled,false);
});
test('GSEA manual mode submits the complete uploaded rankings unchanged and authenticates figure downloads',async()=>{
 const f=fixture();await f.get('gsea-viz-refresh').click();f.get('gsea-viz-source').value='ora-job';
 const ranked='gene_id,metric,in_set\nG1,2,TRUE\nG2,1,FALSE\nG3,-1,TRUE\n';
 f.get('gsea-viz-ranked').value=ranked;await f.get('gsea-viz-generate').click();
 const body=f.posts.find(row=>row.path.endsWith('/gsea')).body;
 assert.equal(body.ranked_csv,ranked);assert.equal(body.session_id,'test-session');assert.equal(body.weight,1);assert.equal(body.width,9);
 assert.equal(body.data,undefined);assert.equal(body.GeneRatio,undefined);
 assert.equal(f.rendered.length,1);
 const download=f.get('gsea-viz-output').toolbar.children.find(el=>el.textContent==='PDF');await download.click();
 assert.equal(f.downloads[0].url,'http://localhost:8000/api/visualize/enrichment/file/test-session/figure.pdf');
 assert.equal(f.downloads[0].options.headers['X-Session-Id'],'test-session');
 assert.equal(f.downloads[0].options.headers.Authorization,'Bearer test-token');
 assert.equal(f.downloads[0].options.headers['X-Student-Token'],'test-student');
});
test('stored GSEA mode submits the selected real pathway and ignores manual rank input',async()=>{
 const f=fixture();await f.get('gsea-viz-refresh').click();f.get('gsea-viz-source').value='RNA%20%2F%20sample::current_gsea';
 await f.get('gsea-viz-source').onchange();f.get('gsea-viz-ranked').value='stale manually pasted content';
 await f.get('gsea-viz-generate').click();
 const body=f.posts.find(row=>row.path.endsWith('/gsea')).body;
 assert.equal(body.source_job,'current_gsea');assert.equal(body.set_id,'GO:001');assert.equal(body.ranked_csv,undefined);
});

test('single-omics sources defensively filter mismatches; multiomics explicitly permits a combined list',async()=>{
 const f=fixture();f.sources.push({source_job:'protein-job',kind:'ora',omics:'proteomics',experiment:'Protein',label:'Protein result'}, {source_job:'unknown-here',kind:'ora',omics:'unknown',experiment:'RNA / sample',label:'Legacy'}, {source_job:'unknown-other',kind:'ora',omics:'unknown',experiment:'Other',label:'Other legacy'});
 await f.get('enrich-viz-refresh').click();
 const single=Array.from(f.get('enrich-viz-source').options,option=>option.value);
 assert.ok(!single.includes('protein-job'));assert.ok(single.includes('unknown-here'));assert.ok(!single.includes('unknown-other'));
 assert.match(f.get('enrich-viz-source').options.find(option=>option.value==='unknown-here').textContent,/unknown type/);
 f.get('omics-pipeline').value='multiomics';await f.get('omics-pipeline').listeners.change();
 assert.match(f.posts.filter(row=>row.method==='GET').at(-1).path,/omics=multiomics&scope=multiomics/);
 assert.ok(Array.from(f.get('enrich-viz-source').options,option=>option.value).includes('protein-job'));
});
test('switching omics clears sources, rendered plots, ranks, selected terms and pathways before refreshing',async()=>{
 const f=fixture();await f.get('gsea-viz-refresh').click();f.get('gsea-viz-source').value='RNA%20%2F%20sample::current_gsea';await f.get('gsea-viz-source').onchange();
 await f.get('gsea-viz-generate').click();assert.equal(f.rendered.length,1);
 f.get('gsea-viz-output').append(new El('img'));f.get('gsea-viz-ranked').value='old ranked table';f.get('enrich-viz-terms').append(new El('option'));
 f.get('omics-pipeline').value='microbiome_16s';await f.get('omics-pipeline').listeners.change();
 assert.equal(f.get('gsea-viz-source').value,'');assert.equal(f.get('enrich-viz-source').value,'');
 assert.equal(f.get('gsea-viz-output').children.length,0);assert.equal(f.get('gsea-viz-pathway').options.length,0);assert.equal(f.get('enrich-viz-terms').options.length,0);
 assert.equal(f.get('gsea-viz-ranked').value,'');assert.equal(f.get('gsea-viz-set').readOnly,false);
});
test('all/customize remain a single-experiment scope rather than a multiomics aggregation',async()=>{
 for(const omics of ['all','customize']){
  const f=fixture();f.sources.push({source_job:'other-rna',kind:'ora',omics:'transcriptomics',experiment:'Other RNA'});f.get('omics-pipeline').value=omics;
  await f.get('enrich-viz-refresh').click();assert.match(f.posts[0].path,/omics=&scope=single/);
  assert.ok(!Array.from(f.get('enrich-viz-source').options,option=>option.value).includes('other-rna'));
 }
});
test('multiomics current GSEA caches have distinct choices and submit the selected experiment',async()=>{
 const f=fixture();f.get('omics-pipeline').value='multiomics';f.sources.push({source_job:'current_gsea',kind:'gsea',omics:'proteomics',experiment:'Proteins',label:'Protein GSEA'});
 await f.get('gsea-viz-refresh').click();const cacheOptions=f.get('gsea-viz-source').options.filter(option=>option.value.endsWith('::current_gsea'));
 assert.equal(new Set(cacheOptions.map(option=>option.value)).size,2);
 f.get('gsea-viz-source').value='Proteins::current_gsea';await f.get('gsea-viz-source').onchange();await f.get('gsea-viz-generate').click();
 const body=f.posts.filter(row=>row.path.endsWith('/gsea')).at(-1).body;assert.equal(body.experiment,'Proteins');assert.equal(body.source_job,'current_gsea');assert.equal(body.scope,'multiomics');
});
