import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {currentAgentAction,resolveAgentAction,resolveHeatmapSize,assertAgentSubmission} from '../frontend/js/agent_actions.mjs';
test('a PCA request cannot accidentally submit the differential button and plot-only requests cannot rerun analysis',()=>{
 assert.throws(()=>assertAgentSubmission({workflow:'analysis',tab:'ana-diff'},'请进行PCA。不要重复差异分析。'),/ana-dim/);
 assert.doesNotThrow(()=>assertAgentSubmission({workflow:'analysis',tab:'ana-dim'},'请进行PCA。不要重复差异分析。'));
 assert.throws(()=>assertAgentSubmission({workflow:'analysis',tab:'ana-diff'},'使用已保存的DESeq2结果出图，不重新做分析'),/可视化/);
 assert.throws(()=>assertAgentSubmission({workflow:'analysis',tab:'ana-diff'},'运行当前步骤','ana-dim'),/不匹配/);
});
test('agent actions require a reviewed current experiment and cannot supply selectors or code',()=>{
 const context={workflow:'analysis',tab:'ana-diff',hasExperiment:true};
 assert.equal(resolveAgentAction({workflow:'visualization',tab:'viz-heatmap',hasExperiment:true},'submit_current',true).button,'btn-heatmap');
 const heat={workflow:'visualization',tab:'viz-heatmap',hasExperiment:true};
 assert.equal(resolveHeatmapSize(heat,{width_inches:11,height_inches:14},true).height,14);
 assert.throws(()=>resolveHeatmapSize(heat,{width_inches:11,height_inches:Infinity},true));
 assert.throws(()=>resolveHeatmapSize(heat,{width_inches:11,height_inches:14},false));
 assert.equal(resolveAgentAction(context,'submit_current',true).button,'btn-diff');
 assert.throws(()=>resolveAgentAction(context,'submit_current',false));
 assert.throws(()=>resolveAgentAction({...context,hasExperiment:false},'submit_current',true));
 assert.throws(()=>resolveAgentAction(context,'document.body.click()',true));
 assert.throws(()=>resolveAgentAction({...context,tab:'ana-cross'},'submit_current',true));
 assert.equal(resolveAgentAction({},'refresh_tasks',false).type,'refresh_tasks');
 const html=readFileSync(new URL('../frontend/index.html',import.meta.url),'utf8');
 for(const tab of ['prep-filter','prep-normalize','prep-impute','prep-rarefy','prep-collapse','prep-m16s-taxonomy']) {
  assert.ok(html.includes(`id="${currentAgentAction({workflow:'preparation',tab})}"`));
 }
});
