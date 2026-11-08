import test from 'node:test';
import assert from 'node:assert/strict';
import {snapshotPlot,availableSnapshotPlots,resultRows} from '../frontend/js/analysis_snapshot_model.mjs';
test('dimension snapshots plot retained coordinate columns and reject unrelated numeric metadata',()=>{
 const stored={data:JSON.stringify([{PC1:2,PC2:-1},{PC1:3,PC2:4}])};
 assert.deepEqual(snapshotPlot('analysis:/analyze/dimension',stored).points,[{x:2,y:-1},{x:3,y:4}]);
 assert.throws(()=>snapshotPlot('dimension',{data:[{age:30,bmi:24}]}));
});
test('correlation and cluster plots use saved coefficients and labels without recomputation',()=>{
 const cor={data:[{var1:'A',var2:'B',coefficient:-.8},{var1:'A',var2:'C',coefficient:null}]};
 const model=snapshotPlot('correlation',cor);assert.equal(model.pairs.length,1);assert.equal(model.pairs[0].r,-.8);
 assert.equal(snapshotPlot('correlation',cor,'network').type,'network');
 assert.deepEqual(snapshotPlot('cluster',{data:[{cluster:'C1'},{cluster:'C2'},{cluster:'C1'}]}).bars,[{label:'C1',value:2},{label:'C2',value:1}]);
});
test('enrichment exposes bubble plots only with ratios and counts; parses actual ratios',()=>{
 const data=[{Description:'Pathway',Count:4,GeneRatio:'4/20','p.adjust':.03}];
 assert.ok(availableSnapshotPlots('enrichment',{data}).some(row=>row.id==='bubble'));
 assert.equal(snapshotPlot('enrichment',{data},'bubble').dots[0].ratio,.2);
 assert.ok(!availableSnapshotPlots('enrichment',{data:[{Description:'Pathway',Count:4}]}).some(row=>row.id==='bubble'));
});
test('volcano and effect bars preserve negative effects and distinguish FDR from raw p',()=>{
 const data=[{feature:'g1',log2FoldChange:-2,padj:.01,pvalue:.001},{feature:'g2',log2FoldChange:3,padj:null,pvalue:.02}];
 const plot=snapshotPlot('differential',{data},'volcano');assert.equal(plot.points.length,1);assert.equal(plot.points[0].x,-2);assert.equal(plot.points[0].y,2);assert.equal(plot.yLabel,'−log10(padj)');
 assert.equal(snapshotPlot('differential',{data},'effect_bar').bars[0].value,-2);
 assert.deepEqual(resultRows({data:'[{"Count":2}]'}),[{Count:2}]);
});
