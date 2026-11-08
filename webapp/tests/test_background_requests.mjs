import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const src=fs.readFileSync(new URL('../frontend/js/api.js',import.meta.url),'utf8');
const code=src.slice(src.indexOf('let backgroundRoutes ='),src.indexOf('// ── SESSION'));
test('registered requests submit once, retain auth, notify the tray and return background results',async()=>{
 const seen=[],events=[];
 const sandbox=vm.createContext({headers:()=>({'Authorization':'Bearer fixture','X-Session-Id':'current'}),resolveApiCandidates:()=>['/api'],
 window:{dispatchEvent:e=>events.push(e)},CustomEvent:class{constructor(type,opts){this.type=type;this.detail=opts.detail;}},
 fetch:async(url,opts)=>{seen.push({url,opts});return {ok:true,status:200,headers:{get:()=> 'application/json'},json:async()=>url.endsWith('capabilities')?{success:true,routes:['/analyze/dimension']}:{success:true,job_id:'registered-job'}};},
 pollJobUntilDone:async id=>{assert.equal(id,'registered-job');return {result:{success:true,data:'[]'}};},setTimeout,clearTimeout});
 vm.runInContext(code+';globalThis.run=request',sandbox);
 const result=await sandbox.run('POST','/analyze/dimension',{session_id:'current',experiment:'test',method:'PCA'});
 assert.equal(result.data,'[]');assert.deepEqual(seen.map(x=>x.url),['/api/tasks/capabilities','/api/tasks/submit']);
 assert.equal(seen[1].opts.headers.Authorization,'Bearer fixture');
 assert.equal(JSON.parse(seen[1].opts.body).payload.method,'PCA');
 assert.equal(events.filter(e=>e.type==='emp:job-submitted').length,1);
});
