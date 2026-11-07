import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import {StudyContexts} from '../frontend/js/study_model.mjs';
import {featureText, applyFeatureLocale} from '../frontend/js/feature_i18n.mjs';
const html=fs.readFileSync(new URL('../frontend/index.html',import.meta.url),'utf8');
const source=fs.readFileSync(new URL('../frontend/js/matrix_panel.js',import.meta.url),'utf8').replace(/^import .*;$/mg,'').replace('export function','function');
class Element{
 constructor(){this.value='';this.textContent='';this.children=[];this.disabled=false;this.listeners={};this.attributes={};}
 append(...x){this.children.push(...x);} replaceChildren(...x){this.children=[...x];}
 addEventListener(k,f){(this.listeners[k]??=[]).push(f);} setAttribute(k,v){this.attributes[k]=v;} removeAttribute(k){delete this.attributes[k];}
 async fire(k){for(const fn of [this['on'+k],...(this.listeners[k]||[])].filter(Boolean))await fn({target:this});} click(){return this.fire('click');}
}
const id='12345678-1234-1234-1234-123456789abc';
const file=(over={})=>({id:'0',name:'counts.h5ad',url:'https://ftp.ncbi.nlm.nih.gov/geo/series/GSE60nnn/GSE60450/suppl/counts.h5ad',bytes:50*1024**2,format_hint:'other',...over});
const manifest=files=>({manifest_id:id,manifest:{accession:'GSE60450',title:'Test',sample_accessions:['GSM1'],files}});
function harness(routes={},agree=true){
 const elements=new Map([...html.matchAll(/\bid="([^"]+)"/g)].map(x=>[x[1],new Element()]));
 const g=x=>{const node=elements.get('matrix-'+x);assert.ok(node,x);return node;};g('budget').value='5';g('accession').value='GSE60450';
 const calls=[],prompts=[],exports=[],listeners={};const doc={defaultView:{addEventListener:(key,fn)=>listeners[key]=fn},getElementById:x=>elements.get(x),createElement:()=>new Element(),querySelectorAll:()=>[],querySelector:()=>null};
 const fetch=async(url,opts)=>{const op=url.replace('/api/public-data/','');assert.ok(url.startsWith('/api/public-data/'));assert.equal(opts.redirect,'error');assert.equal(opts.credentials,'omit');const payload=JSON.parse(opts.body);calls.push({op,payload});assert.ok(routes[op],'Unexpected request '+op);return {ok:true,json:async()=>typeof routes[op]==='function'?routes[op](payload):routes[op]};};
 const ctx=vm.createContext({featureText,applyFeatureLocale,studyContexts:new StudyContexts(),document:doc,fetch,confirm:q=>{prompts.push(q);return agree;},Blob,URL:{createObjectURL:b=>{exports.push(b);return 'blob:local';},revokeObjectURL(){}},setTimeout(){}});vm.runInContext(source,ctx);return{g,calls,prompts,exports,emit:(type,detail={})=>listeners[type]?.({detail})};
}
const tick=()=>new Promise(r=>setImmediate(r));
const pending=()=>{let resolve;const promise=new Promise(r=>resolve=r);return{promise,resolve};};
const plan={plan_id:id,plan_sha256:'a'.repeat(64),plan:{status:'ready_for_confirmation',download_enabled:true,blockers:[]}};
const queued={job_id:id,status:'queued',bytes_downloaded:0,total_bytes:null,max_bytes:5*1024**3,source_url:file().url,source_name:file().name,plan_sha256:'a'.repeat(64)};
async function discover(h){await h.g('resolve').click();return h.g('files').children[0].children.at(-1);}
test('matrix is embedded in main navigation, not an iframe or external-only link',()=>{assert.match(html,/data-page="matrix"/);assert.match(html,/id="page-matrix" class="page"/);assert.match(html,/js\/matrix_panel.js/);assert.doesNotMatch(source,/iframe|advanced\/|raw\/|agent\//);});
test('startup and example fill never query or download automatically',async()=>{const h=harness();assert.equal(h.calls.length,0);await h.g('example').click();assert.equal(h.g('accession').value,'GSE60450');assert.equal(h.calls.length,0);});
test('large and unknown-size original matrix formats are selectable',async()=>{for(const bytes of [50*1024**2,null]){const h=harness({'processed/resolve':manifest([file({bytes})]),'matrix/plan':plan,'matrix/start':queued});const b=await discover(h);assert.equal(b.disabled,false);await b.click();assert.equal(h.calls.at(-2).payload.max_bytes,5*1024**3);assert.equal(h.calls.at(-1).op,'matrix/start');assert.equal(h.prompts.length,1);}});
test('explicit cancellation never starts a download',async()=>{const h=harness({'processed/resolve':manifest([file()]),'matrix/plan':plan},false);await(await discover(h)).click();assert.equal(h.calls.filter(x=>x.op==='matrix/start').length,0);});
test('obvious raw reads are not eligible in matrix-only panel',async()=>{const h=harness({'processed/resolve':manifest([file({name:'reads.fastq.gz'})])});assert.equal((await discover(h)).disabled,true);});
test('invalid budget and blocked plan never start a download',async()=>{const h=harness({'processed/resolve':manifest([file()]),'matrix/plan':{...plan,plan:{status:'blocked',download_enabled:false,blockers:['disk']}}});const b=await discover(h);h.g('budget').value='101';await b.click();assert.equal(h.calls.length,1);h.g('budget').value='5';await b.click();assert.equal(h.prompts.length,0);});
test('stale GSE discovery response is discarded',async()=>{const p=pending();const h=harness({'processed/resolve':()=>p.promise});const work=h.g('resolve').click();await tick();h.g('accession').value='GSE1';await h.g('accession').fire('input');p.resolve(manifest([file()]));await work;assert.equal(h.g('files').children.length,0);});
test('changed download budget revokes in-flight plan',async()=>{const p=pending();const h=harness({'processed/resolve':manifest([file()]),'matrix/plan':()=>p.promise});const b=await discover(h);const work=b.click();await tick();h.g('budget').value='10';p.resolve(plan);await work;assert.equal(h.prompts.length,0);});
test('duplicate clicks do not submit concurrent downloads',async()=>{const p=pending();const h=harness({'processed/resolve':manifest([file()]),'matrix/plan':()=>p.promise,'matrix/start':queued});const b=await discover(h);const work=b.click();await tick();await b.click();p.resolve(plan);await work;assert.equal(h.calls.filter(x=>x.op==='matrix/start').length,1);});
test('completed file uses same-origin streaming attachment and previews only on annotation request',async()=>{const receipt={source_name:'counts.tsv.gz',bytes:513592,sha256:'a'.repeat(64)};const h=harness({'matrix/status':{...queued,status:'completed',receipt},'matrix/preview':{inspection:{column_labels:['c1']}},'processed/annotations':{records:[{accession:'GSM1',title:'Title',characteristics:['group: author label']}],matches:[{column:'c1',status:'exact',sample:{accession:'GSM1',title:'Title',characteristics:['group: author label']}}],source_url:'https://ftp.ncbi.nlm.nih.gov/example',sha256:'b'.repeat(64)}});h.g('job-id').value=id;await h.g('refresh').click();assert.equal(h.g('save').children[0].href,`/api/public-data/matrix/files/${id}`);assert.equal(h.calls.length,1);await h.g('annotations').click();assert.deepEqual(Array.from(h.calls.at(-1).payload.columns),['c1']);assert.equal(h.g('export-samples').disabled,false);});
test('resumption separately confirms stored job digest, not current file choice',async()=>{const job={...queued,status:'interrupted',resume_supported:true,plan:{source:'approved'}};const h=harness({'matrix/status':job,'matrix/resume':queued});h.g('job-id').value=id;await h.g('refresh').click();await h.g('resume').click();assert.equal(h.calls.at(-1).payload.plan_sha256,job.plan_sha256);assert.equal(h.prompts.length,1);});
test('GEO search exposes GSE choices only and does not resolve or download them',async()=>{const h=harness({'search':{records:[{accession:'GSM1'},{accession:'GSE2',title:'Example'}]},'processed/resolve':{...manifest([]),manifest:{accession:'GSE2',files:[]}}});h.g('query').value='public keyword';await h.g('search').click();assert.equal(h.g('search-results').children.length,1);await h.g('search-results').children[0].children[0].click();assert.equal(h.g('accession').value,'GSE2');assert.equal(h.calls.length,2);assert.ok(h.calls.every(c=>c.op!=='matrix/start'));});

test('switching jobs clears previous file, receipt and sample column artifacts',async()=>{
 const id2='22345678-1234-1234-1234-123456789abc';
 const h=harness({'matrix/status':p=>({...queued,job_id:p.job_id,status:p.job_id===id?'completed':'running',receipt:p.job_id===id?{source_name:'A.tsv'}:null}),'matrix/preview':{inspection:{column_labels:['A-column']}},'processed/annotations':{records:[],matches:[],source_url:'official',sha256:'a'}});
 h.g('job-id').value=id;await h.g('refresh').click();await h.g('annotations').click();
 assert.equal(h.g('export-receipt').disabled,false);
 h.g('job-id').value=id2;await h.g('refresh').click();
 assert.equal(h.g('save').children.length,0);assert.equal(h.g('receipt').textContent,'');assert.equal(h.g('samples').children.length,0);assert.equal(h.g('export-receipt').disabled,true);assert.equal(h.g('export-samples').disabled,true);
 await h.g('annotations').click();assert.deepEqual(Array.from(h.calls.at(-1).payload.columns),[]);
});
test('editing job id immediately invalidates exports before refresh',async()=>{
 const h=harness({'matrix/status':{...queued,status:'completed',receipt:{source_name:'A.tsv'}}});h.g('job-id').value=id;await h.g('refresh').click();await h.g('job-id').fire('input');assert.equal(h.g('save').children.length,0);assert.equal(h.g('export-receipt').disabled,true);
});

test('editing job selection discards pending annotations and cancel responses',async()=>{
 for(const op of ['processed/annotations','matrix/cancel']){
 const p=pending();const h=harness({'matrix/status':{...queued,status:'completed',receipt:{source_name:'A.tsv'}},'matrix/preview':{inspection:{column_labels:['A']}},[op]:()=>p.promise});
 h.g('job-id').value=id;await h.g('refresh').click();const work=h.g(op==='matrix/cancel'?'cancel':'annotations').click();await tick();h.g('job-id').value='22345678-1234-1234-1234-123456789abc';await h.g('job-id').fire('input');p.resolve(op==='matrix/cancel'?{...queued,status:'completed',receipt:{source_name:'A.tsv'}}:{records:[],matches:[]});await work;
 assert.equal(h.g('save').children.length,0);assert.equal(h.g('samples').children.length,0);assert.equal(h.g('export-samples').disabled,true);assert.equal(h.g('export-receipt').disabled,true);
 }
});

test('start response after selection change exposes recoverable job ID without stale artifacts',async()=>{
 const p=pending();const h=harness({'processed/resolve':manifest([file()]),'matrix/plan':plan,'matrix/start':()=>p.promise});const b=await discover(h);const work=b.click();await tick();h.g('accession').value='GSE2';await h.g('accession').fire('input');p.resolve(queued);await work;assert.ok(h.g('status').textContent.includes(id));assert.equal(h.g('save').children.length,0);
});

test('sample TSV and provenance are separate user downloads and both invalidate',async()=>{
 const h=harness({'processed/annotations':{records:[{accession:'GSM1',title:'Sample'}],matches:[],source_url:'official',sha256:'a',provenance_download_url:'/api/public-data/matrix/exports/'+id}});
 await h.g('annotations').click();assert.equal(h.g('export-provenance').disabled,false);
 await h.g('export-samples').click();assert.equal(h.exports.length,1);assert.match(await h.exports[0].text(),/matrix_column/);
 assert.equal(h.g('export-provenance').href,'/api/public-data/matrix/exports/'+id);await h.g('export-provenance').click();assert.equal(h.exports.length,1);
 await h.g('job-id').fire('input');assert.equal(h.g('export-samples').disabled,true);assert.equal(h.g('export-provenance').disabled,true);
 await h.g('annotations').click();await h.g('accession').fire('input');assert.equal(h.g('export-provenance').disabled,true);
});

test('provenance link rejects arbitrary external or unsafe download destinations',async()=>{
 for(const url of ['https://evil.test/file','/api/public-data/matrix/exports/../../data']){const h=harness({'processed/annotations':{records:[],matches:[],provenance_download_url:url}});await h.g('annotations').click();assert.equal(h.g('export-provenance').disabled,true);}
});
test('new paper detaches old files and samples while history restores the retained job without another download',async()=>{
 const h=harness({'processed/resolve':manifest([file()]),'matrix/status':{...queued,status:'completed',receipt:{source_name:'A.tsv'}},'matrix/history':{jobs:[{job_id:id,source_name:'A.tsv',status:'completed'}]}});
 await discover(h);h.g('job-id').value=id;await h.g('refresh').click();assert.equal(h.g('save').children.length,1);
 h.emit('emp:study-reset');for(const name of ['files','save','samples'])assert.equal(h.g(name).children.length,0);
 assert.equal(h.g('job-id').value,'');assert.equal(h.g('accession').value,'');assert.equal(h.g('open-workbench').disabled,true);
 await h.g('history-refresh').click();h.g('history').value=id;await h.g('history').fire('change');await tick();
 assert.equal(h.g('save').children.length,1);assert.equal(h.g('accession').value,'GSE60450');
 assert.ok(h.calls.every(call=>!['matrix/start','matrix/cancel','matrix/resume'].includes(call.op)));
});
