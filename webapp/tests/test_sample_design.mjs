import test from 'node:test';
import assert from 'node:assert/strict';
import {reviewSampleDesign} from '../frontend/js/sample_design.mjs';
const samples=[{id:'A1',group:'before'},{id:'A2',group:'before'},{id:'B1',group:'after'},{id:'B2',group:'after'}];
test('sample relationships are explicit user choices, never inferred from matrix labels',()=>{
  assert.throws(()=>reviewSampleDesign(samples,''),/Select/);
  assert.equal(reviewSampleDesign(samples,'unknown').execution_allowed,false);
  assert.equal(reviewSampleDesign(samples,'independent').confirmed_by,'user');
});
test('paired review requires actual subject IDs and preserves the entered mapping instead of pairing by row order',()=>{
  assert.throws(()=>reviewSampleDesign(samples,'paired'),/every sample/);
  assert.throws(()=>reviewSampleDesign(samples,'paired',{A1:'1',A2:'2',B1:'3',B2:'4'}),/No repeated/);
  const r=reviewSampleDesign(samples,'paired',{A1:'mouse1',A2:'mouse2',B1:'mouse2',B2:'mouse1'});
  assert.equal(r.subject_count,2);assert.equal(r.incomplete_subjects,0);assert.equal(r.execution_allowed,false);
  assert.equal(r.subjects.find(s=>s.id==='B1').subject,'mouse2');
});
test('partial pairing is reported without dropping or imputing observations',()=>{
  const r=reviewSampleDesign(samples,'paired',{A1:'1',A2:'2',B1:'1',B2:'3'});
  assert.equal(r.incomplete_subjects,2);assert.equal(r.subjects.length,4);assert.equal(r.execution_allowed,false);
  assert.throws(()=>reviewSampleDesign([...samples,samples[0]],'independent'),/Complete/);
});
