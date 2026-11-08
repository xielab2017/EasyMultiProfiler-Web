import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {resultRows,snapshotPlot,availableSnapshotPlots} from '../frontend/js/analysis_snapshot_model.mjs';
class El{
 constructor(tag){this.tag=tag;this.children=[];this.value='';this.textContent='';this.style={};this.dataset={};this.namespaceURI='http://www.w3.org/2000/svg';}
 append(...items){for(const item of items)item.parentElement=this;this.children.push(...items);if(this.tag==='select'&&this.children.length===items.length)this.value=this.children[0]?.value||'';}
 insertBefore(item,before){this.children.splice(this.children.indexOf(before),0,item);}
 replaceChildren(...items){this.children=items;if(this.tag==='select')this.value='';}
 setAttribute(){}click(){if(!this.disabled)return this.onclick?.();}
 addEventListener(){}
 querySelector(){return this.children.find(el=>el.tag==='optgroup'&&el.dataset.analysisJobs);}
 remove(){this.parentElement.children=this.parentElement.children.filter(el=>el!==this);}
}
const flat=e=>[e,...e.children.flatMap(flat)];
test('changing the snapshot chart selector redraws bars as bubbles from the cached result',async()=>{
 const source=fs.readFileSync(new URL('../frontend/js/analysis_snapshot_browser.js',import.meta.url),'utf8').replace(/^import .*;$/mg,'').replace('export function mountAnalysisSnapshots','function mountAnalysisSnapshots');
 const root=new El('div'),calls=[];
 const sandbox=vm.createContext({document:{createElement:tag=>new El(tag),createElementNS:(ns,tag)=>new El(tag)},window:{addEventListener(){}},resultRows,snapshotPlot,availableSnapshotPlots,Blob,URL,XMLSerializer:class{},setTimeout});
 vm.runInContext(source+';globalThis.mount=mountAnalysisSnapshots',sandbox);
 const result={data:[{Description:'Pathway',Count:4,GeneRatio:'4/20','p.adjust':.03}]};
 const controller=sandbox.mount(root,{request:async(method,path)=>{calls.push(path);return path.startsWith('/jobs?')?{jobs:[{id:'snapshot',kind:'enrichment',status:'done'}]}:result;},showTable(){},attachAI(){}});
 await controller.refresh();const find=id=>flat(root).find(el=>el.id===id),select=find('analysis-snapshot-select');select.value='snapshot';
 const render=flat(root).find(el=>el.textContent==='绘制所选分析快照');await render.click();
 assert.ok(flat(find('analysis-snapshot-plot')).some(el=>el.tag==='rect'));
 const chart=find('analysis-snapshot-chart-type');chart.value='bubble';chart.onchange();
 assert.ok(flat(find('analysis-snapshot-plot')).some(el=>el.tag==='circle'));
 assert.ok(!flat(find('analysis-snapshot-plot')).some(el=>el.tag==='rect'));
 assert.equal(calls.filter(path=>path.endsWith('/result')).length,1);
});
test('the unified visualization selector retains preprocessing options and groups all analysis statuses',async()=>{
 const source=fs.readFileSync(new URL('../frontend/js/analysis_snapshot_browser.js',import.meta.url),'utf8').replace(/^import .*;$/mg,'').replace('export function mountAnalysisSnapshots','function mountAnalysisSnapshots');
 const root=new El('div'),select=new El('select'),prep=new El('optgroup'),option=new El('option');option.value='prepared-id';prep.append(option);select.append(prep);select.value='prepared-id';
 const sandbox=vm.createContext({document:{getElementById:id=>id==='viz-snapshot-select'?select:null,createElement:tag=>new El(tag)},window:{addEventListener(){}},resultRows,snapshotPlot,availableSnapshotPlots});
 vm.runInContext(source+';globalThis.mount=mountAnalysisSnapshots',sandbox);
 const controller=sandbox.mount(root,{request:async()=>({jobs:[{id:'done-job',kind:'enrichment',status:'done'},{id:'queued-job',kind:'dimension',status:'queued'}]}),showTable(){},attachAI(){}});
 await controller.refresh();await controller.refresh();
 assert.equal(select.children[0],prep);assert.equal(select.value,'prepared-id');
 assert.equal(select.children.filter(el=>el.dataset.analysisJobs).length,1);
 const options=select.children[1].children;
 assert.equal(options[0].value,'job:done-job');assert.equal(options[1].disabled,true);
 assert.ok(!flat(root).some(el=>el.id==='analysis-snapshot-select'));
});
