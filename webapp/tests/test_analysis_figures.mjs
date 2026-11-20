import test from 'node:test';import assert from 'node:assert/strict';
import {matchingAnalysisSources,normalizedAnalysisMethod,analysisFigureDownloadUrl,ANALYSIS_FIGURES} from '../frontend/js/analysis_figures.js';
import {figureKindForRequest,figureStandardOptions,FIGURE_RENDER_BUTTONS,appearanceFields} from '../frontend/js/figure_standards.mjs';
test('all four analysis sections have separate physical settings and render targets',()=>{
 for(const kind of Object.keys(ANALYSIS_FIGURES)){assert.equal(figureKindForRequest('/visualize/analysis-result',{kind}),'analysis_'+kind);assert.equal(figureStandardOptions('analysis_'+kind,{width:60,height:80,font:4}).publication.font_pt,4);assert.equal(FIGURE_RENDER_BUTTONS['analysis_'+kind],'analysis-'+kind+'-generate');}
 assert.equal(figureKindForRequest('/visualize/analysis-result/describe',{}),null);
 assert.ok(appearanceFields('analysis_correlation').includes('scale_position'));assert.ok(!appearanceFields('analysis_marker').includes('cell_line'));
});
test('source selection keeps distinct methods and RF fallback request identities',()=>{
 const sources=[{kind:'marker',requested_method:'LEfSe',actual_method:'Random Forest'},{kind:'marker',requested_method:'randomForest'},{kind:'dimension',requested_method:'tSNE'},{kind:'dimension',requested_method:'UMAP'}];
 assert.deepEqual(matchingAnalysisSources(sources,'marker','LEfSe'),[sources[0]]);assert.deepEqual(matchingAnalysisSources(sources,'marker','rf'),[sources[1]]);assert.deepEqual(matchingAnalysisSources(sources,'dimension','t-SNE'),[sources[2]]);assert.equal(normalizedAnalysisMethod('tSNE'),normalizedAnalysisMethod('t-SNE'));
});
test('analysis figure downloads are confined to the authenticated figure route',()=>{
 assert.equal(analysisFigureDownloadUrl('/api/visualize/analysis-result/file/s/analysis_plot_123.pdf','http://localhost:8000/api','http://localhost:8080/'),'http://localhost:8000/api/visualize/analysis-result/file/s/analysis_plot_123.pdf');
 assert.throws(()=>analysisFigureDownloadUrl('https://other.test/api/visualize/analysis-result/file/s/x.pdf','http://localhost:8000/api','http://localhost:8080/'),/Invalid/);
 assert.throws(()=>analysisFigureDownloadUrl('/api/visualize/method-library/file/s/x.pdf','http://localhost:8000/api','http://localhost:8080/'),/Invalid/);
});
