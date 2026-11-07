import test from 'node:test';
import assert from 'node:assert/strict';
import {StudyContexts,annotationFields,annotationRows,comparisonPairs,paperSummary} from '../frontend/js/study_model.mjs';
const sample={accession:'GSM1',title:'Original sample',characteristics:['treatment: A','tissue: liver']};
test('candidate groups require a selected source field and an exact sample match',()=>{
 const data={records:[sample],matches:[{column:'sample-1',status:'exact',sample},{column:'similar-name',status:'ambiguous',sample}]};
 assert.equal(annotationRows(['sample-1'],data)[0].group,'');
 assert.equal(annotationRows(['sample-1'],data,'treatment')[0].group,'A');
 assert.equal(annotationRows(['similar-name'],data,'treatment')[0].group,'');
 assert.equal(annotationRows(['missing'],data,'treatment')[0].match,'unmatched');
 assert.equal(annotationFields(data.records).find(row=>row.name==='treatment').values[0],'A');
 const conflicting={records:[{...sample,characteristics:['treatment: A','treatment: B']}]};
 assert.equal(annotationRows(['GSM1'],conflicting,'treatment')[0].group,'');
});
test('one, multiple and all-pair comparisons declare each direction without dropping fitting groups',()=>{
 const samples=['control','B','C'].flatMap(group=>[1,2,3].map(i=>({id:group+i,group})));
 assert.deepEqual(comparisonPairs(samples,'one_to_many','control',['B','C']),[{test:'B',reference:'control'},{test:'C',reference:'control'}]);
 assert.equal(comparisonPairs(samples,'all_pairs','').length,3);
 assert.equal(comparisonPairs(samples,'one_to_one','control',['C']).length,1);
 assert.throws(()=>comparisonPairs(samples,'one_to_many','control',['control']));
 assert.throws(()=>comparisonPairs(samples,'one_to_many','control',['B','B']));
 assert.throws(()=>comparisonPairs([...samples,{id:'unlabeled',group:''}],'all_pairs',''));
});
test('paper evidence and download contexts are detached, bounded and bound to one job',()=>{
 const store=new StudyContexts(),context={paper:{title:'Paper'},accession:'GSE1'};store.set('job-1',context);context.paper.title='changed';
 assert.equal(store.get('job-1').paper.title,'Paper');assert.equal(store.get('job-2'),null);const copy=store.get('job-1');copy.accession='GSE2';assert.equal(store.get('job-1').accession,'GSE1');
 const summary=paperSummary({paper_title_candidate:'Candidate',pdf_sha256:'a'.repeat(64),primary_doi_candidates:[{doi:'10.1234/main',pages:[1]}],evidence:Array.from({length:20},()=>({page:2,text:'x'.repeat(900)}))},'paper.pdf');
 assert.equal(summary.doi,'10.1234/main');assert.equal(summary.evidence.length,12);assert.equal(summary.evidence[0].text.length,700);
});
