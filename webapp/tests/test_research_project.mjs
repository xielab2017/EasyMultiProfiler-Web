import test from 'node:test';import assert from 'node:assert/strict';
import {ResearchProjects} from '../frontend/js/research_project.mjs';
test('multiple papers and matrices remain separate, persist references and never infer modality/scale',()=>{
 const values=new Map(),storage={getItem:k=>values.get(k),setItem:(k,v)=>values.set(k,v)};const projects=new ResearchProjects(storage);
 projects.paper({title:'Paper A',doi:'10.test/A'});projects.paper({title:'Paper B',doi:'10.test/B'});projects.paper({title:'Paper A',doi:'10.test/A'});
 const a=projects.block({job_id:'jobA',name:'counts.csv',paper:{title:'Paper A',doi:'10.test/A'}});const b=projects.block({job_id:'jobB',name:'protein.csv',paper:{title:'Paper B',doi:'10.test/B'}});
 assert.notEqual(a.id,b.id);assert.equal(a.omics,'unknown');assert.equal(a.scale,'unknown');projects.block({job_id:'jobA',name:'same.csv'});
 assert.equal(projects.current().papers.length,2);assert.equal(projects.current().blocks.length,2);
 const restored=new ResearchProjects(storage);assert.equal(restored.current().blocks.length,2);const exported=restored.export();assert.equal(exported.matrix_values_included,false);assert.equal(exported.analysis_executed,false);
 projects.create('Second project');assert.equal(projects.current().blocks.length,0);assert.equal(projects.data.projects[0].blocks.length,2);
});
