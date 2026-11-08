import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {parseDiscovery,geoCandidates,repositoryCandidate} from '../frontend/js/discovery_model.mjs';
import {paperSummary} from '../frontend/js/study_model.mjs';
const source=fs.readFileSync(new URL('../frontend/js/dataset_discovery.js',import.meta.url),'utf8').replace(/^import .*;$/mg,'');
class Element{
  constructor(tag){this.tag=tag;this.textContent='';this.value='';this.children=[];this.files=[];this.disabled=false;}
  append(...children){this.children.push(...children);}replaceChildren(...children){this.children=children;}
  setAttribute(){}scrollIntoView(){}click(){return this.onclick?.();}
}
const flatten=el=>[el,...el.children.flatMap(flatten)];
const tick=async()=>{for(let i=0;i<8;i++)await new Promise(r=>setImmediate(r));};
function pending(){let resolve;const promise=new Promise(r=>resolve=r);return{promise,resolve};}
function harness(routes={}){
  const root=new Element('section');root.id='dataset-discovery';let locale='zh';const calls=[],events=[],listeners={};
  const find=id=>flatten(root).find(e=>e.id===id);
  const document={getElementById:find,createElement:tag=>new Element(tag)};
  const window={addEventListener:(key,fn)=>listeners[key]=fn,dispatchEvent:event=>events.push(event)};
  const fetch=async(url,opts)=>{if(url.endsWith('/papers/capabilities'))return{ok:true,json:async()=>({max_bytes:100*1024**2})};assert.ok(url.startsWith('/api/public-data/'));assert.equal(opts.redirect,'error');assert.equal(opts.credentials,'omit');const op=url.replace('/api/public-data/','');const body=opts.headers['Content-Type']==='application/pdf'?opts.body:JSON.parse(opts.body);calls.push({op,body});assert.ok(routes[op],'Unexpected request '+op);return{ok:true,json:async()=>typeof routes[op]==='function'?routes[op](body):routes[op]};};
  vm.runInContext(source,vm.createContext({document,window,fetch,parseDiscovery,geoCandidates,repositoryCandidate,paperSummary,getLocale:()=>locale,CustomEvent:class{constructor(type,options){this.type=type;this.detail=options.detail;}},Blob,URL,setTimeout}));
  return{root,find,calls,events,button:text=>flatten(root).find(e=>e.tag==='button'&&e.textContent===text),async search(value){find('discovery-input').value=value;find('discovery-input').oninput();this.button('查询数据来源').click();await tick();},setLocale(value){locale=value;listeners['emp:locale-change']();}};
}
const manifest=accession=>({manifest_id:'registered-id',manifest:{accession,title:'Study',files:[{name:'counts.tsv',bytes:100}]}});
test('discovery startup is read only; batched accessions deduplicate and require explicit download handoff',async()=>{
  const h=harness({'processed/resolve':p=>manifest(p.accession)});assert.equal(h.calls.length,0);
  await h.search('GSE60450,GSE305056,GSE60450');assert.equal(h.calls.length,2);assert.ok(h.calls.every(c=>c.op==='processed/resolve'));
  h.button('选择文件与下载').click();assert.equal(h.calls.length,2);assert.equal(h.events.at(-1).type,'emp:matrix-pick');assert.equal(h.events.at(-1).detail.result.manifest_id,'registered-id');
});
test('DOI results require exact DOI metadata and article selection before fetching the abstract',async()=>{
  const h=harness({'papers/search':{articles:[{pmid:'1',title:'Wrong',dois:['10.1234/wrong']},{pmid:'2',title:'Match',dois:['10.1234/exact']}]},'papers/abstract':{accessions:[{accession:'GSE1'}]}});
  await h.search('10.1234/exact');assert.equal(h.calls.length,1);assert.equal(h.calls[0].body.term,'10.1234/exact[AID]');
  assert.ok(!flatten(h.root).some(e=>e.textContent==='Wrong'));h.button('读取论文信息与摘要').click();await tick();assert.equal(h.calls[1].body.pmid,'2');assert.equal(h.calls.length,2);assert.ok(h.button('继续查询候选 GEO 文件'));
});
test('changing query discards an earlier in-flight response',async()=>{
  const wait=pending();const h=harness({'processed/resolve':()=>wait.promise});await h.search('GSE1');
  h.find('discovery-input').value='GSE2';h.find('discovery-input').oninput();wait.resolve(manifest('GSE1'));await tick();
  assert.equal(h.find('discovery-results').children.length,0);
});
test('stop retains current response and never sends remaining batch queries',async()=>{
  const wait=pending();const h=harness({'processed/resolve':()=>wait.promise});await h.search('GSE1,GSE2');h.button('停止后续查询').click();wait.resolve(manifest('GSE1'));await tick();
  assert.equal(h.calls.length,1);assert.match(h.find('discovery-status').textContent,/已停止/);
});
test('PMID and no-accession results complete with an explicit bounded-evidence message',async()=>{
  const h=harness({'papers/abstract':{pmid:'25516281',accessions:[]}});await h.search('PMID:25516281');assert.equal(h.calls[0].op,'papers/abstract');assert.equal(h.find('discovery-status').textContent,'');assert.ok(flatten(h.root).some(e=>e.textContent.includes('暂未识别到数据库编号')));
});
test('non-GEO identifiers produce repository links and an AI guidance entry without a misleading GSE search',async()=>{
 const h=harness();await h.search('PXD012345, MTBLS123, NMDC10020869');
 assert.equal(h.calls.length,0);assert.ok(h.button('请 AI 指导检索与分析'));
 const links=flatten(h.root).filter(el=>el.tag==='a').map(el=>el.href);
 assert.ok(links.includes('https://www.ebi.ac.uk/pride/archive/projects/PXD012345'));
 assert.ok(links.includes('https://www.ebi.ac.uk/metabolights/MTBLS123'));
 assert.ok(links.includes('https://nmdc.cn/'));
});
test('PDF goes only to local parser and oversize files are rejected before request',async()=>{
  const h=harness({'papers/pdf':{source:'pdf',accessions:[{accession:'GSE1',pages:[1]}],dois:[]}});const input=h.find('discovery-pdf');
  input.files=[{name:'oversize.pdf',size:101*1024**2}];input.onchange();assert.equal(h.calls.length,0);
  const file={name:'synthetic.pdf',size:1000};input.files=[file];input.onchange();await tick();assert.equal(h.calls.length,1);assert.equal(h.calls[0].body,file);assert.equal(h.calls[0].op,'papers/pdf');assert.ok(h.button('继续查询候选 GEO 文件'));
});
test('locale changes preserve entered query and render existing results without new requests',async()=>{
  const h=harness({'processed/resolve':p=>manifest(p.accession)});await h.search('GSE60450');h.setLocale('en');assert.equal(h.find('discovery-input').value,'GSE60450');assert.equal(h.calls.length,1);assert.ok(h.button('Choose files and download'));assert.equal(h.find('discovery-status').textContent,'Completed 1/1 GEO lookups.');
});
test('PDF with NMDC evidence remains a successful extraction when the empty query button is clicked',async()=>{
 const h=harness({'papers/pdf':{source:'pdf',pages_inspected:20,text_extracted:true,paper_title_candidate:'Actual title',pdf_sha256:'a'.repeat(64),accessions:[{accession:'NMDC10020869',kind:'NMDC',url:'https://nmdc.cn/',pages:[19]}],dois:[],evidence:[{page:19,kind:'data_availability',text:'Data availability: NMDC10020869.'}]}});
 h.find('discovery-pdf').files=[{name:'paper.pdf',size:1000}];await h.find('discovery-pdf').onchange();await tick();
 assert.match(h.find('discovery-status').textContent,/PDF 已读取/);await h.button('查询数据来源').click();await tick();assert.equal(h.calls.length,1);assert.match(h.find('discovery-status').textContent,/PDF 已读取/);
 assert.ok(flatten(h.root).some(el=>el.textContent==='Actual title'));assert.ok(flatten(h.root).some(el=>el.textContent.includes('NMDC10020869')));
});
test('a replacement PDF clears the previous paper and data reference before parsing, including parse failures',async()=>{
 const wait=pending();let n=0;
 const h=harness({'papers/pdf':()=>++n===1?{paper_title_candidate:'Old paper',accessions:[{accession:'GSE1'}],dois:[]}:wait.promise});
 h.find('discovery-pdf').files=[{name:'old.pdf',size:1000}];await h.find('discovery-pdf').onchange();
 h.find('discovery-input').value='old query';h.find('discovery-pdf').files=[{name:'new.pdf',size:1000}];const work=h.find('discovery-pdf').onchange();
 assert.equal(h.find('discovery-input').value,'');assert.equal(h.events.at(-1).type,'emp:study-reset');
 assert.ok(!flatten(h.root).some(el=>el.textContent==='Old paper'));
 h.button('清空当前文章与数据选择').click();wait.resolve({paper_title_candidate:'New paper',accessions:[],dois:[]});await work;
 assert.ok(!flatten(h.root).some(el=>el.textContent==='New paper'));assert.equal(h.find('discovery-results').children.length,0);
});
test('a different article query removes previous PDF evidence instead of attaching it to the new paper',async()=>{
 const h=harness({'papers/pdf':{paper_title_candidate:'Old paper',accessions:[],dois:[]},'papers/search':{articles:[]}});
 h.find('discovery-pdf').files=[{name:'old.pdf',size:1000}];await h.find('discovery-pdf').onchange();await h.search('10.1234/new');
 assert.ok(!flatten(h.root).some(el=>el.textContent==='Old paper'));assert.equal(h.find('discovery-pdf').value,'');assert.equal(h.events.at(-1).type,'emp:study-reset');
});
test('multiple PDFs remain independently selectable after one batch',async()=>{
 const h=harness({'papers/pdf':file=>({paper_title_candidate:file.name,accessions:[{accession:file.name==='one.pdf'?'GSE1':'GSE2'}],dois:[],pdf_sha256:file.name})});
 const input=h.find('discovery-pdf');input.files=[{name:'one.pdf',size:1000},{name:'two.pdf',size:1000}];await input.onchange();
 assert.equal(h.calls.length,2);assert.ok(h.button('one.pdf'));assert.ok(h.button('two.pdf'));
 h.button('one.pdf').click();assert.ok(flatten(h.root).some(el=>el.textContent==='GSE1 ·  · '));
 h.button('two.pdf').click();assert.ok(flatten(h.root).some(el=>el.textContent==='GSE2 ·  · '));
});
