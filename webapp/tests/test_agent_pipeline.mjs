import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
import {AgentPipeline,selectProcessedFile} from '../frontend/js/agent_pipeline.mjs';
import {AgentMemory} from '../frontend/js/agent_memory.mjs';
import {suggestGrouping} from '../frontend/js/study_model.mjs';
test('automatic download prefers counts, excludes reads and quota excess, submits without a modal and imports only after completion',async()=>{
 const files=[{id:'raw',name:'reads.fastq.gz',bytes:10},{id:'fpkm',name:'All_gene_fpkm.txt.gz',bytes:30},{id:'counts',name:'All_gene_count.txt.gz',bytes:50}];assert.equal(selectProcessedFile(files,100).id,'counts');assert.equal(selectProcessedFile(files,40).id,'fpkm');
 const calls=[],events=[];let imported=false;const pipeline=new AgentPipeline({budget:()=>10*1024**2,emit:e=>events.push(e),onComplete:async()=>{imported=true;},api:async(op,b)=>{calls.push([op,b]);if(op==='matrix/resolve')return{manifest_id:'m',manifest:{files}};if(op==='matrix/history')return{jobs:[]};if(op==='matrix/plan')return{plan_id:'p',plan_sha256:'hash',plan:{download_enabled:true,status:'ready_for_confirmation'}};if(op==='matrix/start')return{job_id:'real-server-job',status:'queued'};if(op==='matrix/status')return{job_id:'real-server-job',status:'completed',receipt:{}};}});
 const job=await pipeline.start('GSE123');await new Promise(r=>setImmediate(r));assert.equal(job.job_id,'real-server-job');assert(imported);assert.equal(calls.find(([op])=>op==='matrix/plan')[1].file_id,'counts');assert.equal(calls.find(([op])=>op==='matrix/start')[1].confirmed,true);assert(events.some(e=>e.status==='completed'));await assert.rejects(()=>pipeline.start('https://evil.test'));
});
test('a completed download is reused rather than started twice',async()=>{
 let starts=0;const pipeline=new AgentPipeline({api:async op=>op==='matrix/resolve'?{manifest:{files:[{id:'0',name:'counts.tsv',url:'official'}]}}:op==='matrix/history'?{jobs:[{job_id:'existing',source_url:'official',status:'completed'}]}:op==='matrix/status'?{job_id:'existing',status:'completed'}:(starts++,{} )});assert.equal((await pipeline.start('GSE1')).job_id,'existing');assert.equal(starts,0);
});
test('six metadata groups are derived only from exact complete evidence, never sample order or prefixes',()=>{
 const records=[],matches=[];for(const tissue of ['BAT','iWAT'])for(const treatment of ['22C','6C_6h','6C_24h'])for(let i=1;i<=5;i++){const accession='GSM'+records.length,id='sample'+records.length,sample={accession,characteristics:['tissue: '+tissue,'treatment: '+treatment]};records.push(sample);matches.push({column:id,status:'exact',sample});}
 const annotations={records,matches},ids=matches.map(r=>r.column),s=suggestGrouping(ids,annotations);assert.equal(s.groups.length,6);assert.equal(s.rows.length,30);assert.equal(s.design_verified,false);assert(s.rows.every(r=>r.evidence.includes('tissue:')));assert.equal(suggestGrouping(['unknown'],annotations),null);
});
test('bounded preference learning persists across instances and cannot remember groups or credentials',()=>{
 const data={},storage={getItem:k=>data[k],setItem:(k,v)=>{data[k]=v;}},a=new AgentMemory(storage);assert(a.remember('plot_height',10));assert(!a.remember('api_key','SECRET'));assert(!a.remember('group','control'));a.success('bulk_rnaseq',['qc','normalize','pca']);const b=new AgentMemory(storage);assert.equal(b.snapshot('bulk_rnaseq').preferences.plot_height,10);assert.equal(b.snapshot('bulk_rnaseq').successful_patterns[0].successes,1);b.clear();assert.equal(new AgentMemory(storage).snapshot('bulk_rnaseq').successful_patterns.length,0);
});
test('every navigation page is registered for the same persistent AI dock',()=>{
 const html=fs.readFileSync(new URL('../frontend/index.html',import.meta.url),'utf8'),code=fs.readFileSync(new URL('../frontend/js/code_lab.js',import.meta.url),'utf8');const registered=code.match(/const PAGES = new Set\(\[([^\]]+)\]/)[1];for(const match of html.matchAll(/data-page="([a-z_]+)"/g))assert(registered.includes("'"+match[1]+"'"),'missing '+match[1]);
});
test('excluded varying batch or partially recorded time fields remain explicit review warnings',()=>{
 const records=[{accession:'GSM1',characteristics:['tissue: BAT','treatment: RT']},{accession:'GSM2',characteristics:['tissue: BAT','treatment: cold','batch: 6 h']},{accession:'GSM3',characteristics:['tissue: BAT','treatment: cold','batch: 24 h']}];
 const matches=records.map((sample,i)=>({column:'S'+i,status:'exact',sample}));
 const result=suggestGrouping(matches.map(m=>m.column),{records,matches});
 assert.equal(result.groups.length,2);assert.deepEqual(result.warnings,[{field:'batch',values:['6 h','24 h'],missing:1}]);assert.equal(result.design_verified,false);
});
