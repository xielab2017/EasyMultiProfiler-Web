import test from 'node:test';
import assert from 'node:assert/strict';
import {A4,PUBLICATION_PRESETS,publicationOptions} from '../frontend/js/publication_layout.mjs';
test('A4 panels fit within 15 mm margins with 6 mm gutters',()=>{
 assert.deepEqual(A4,{width:210,height:297,margin:15,gap:6});
 for(const key of ['a4-wide','a4-two','a4-three']){
  const p=PUBLICATION_PRESETS[key];
  assert.ok(p.width*p.columns+6*(p.columns-1)<=180);
  assert.ok(p.height*p.rows+6*(p.rows-1)<=267);
 }
 assert.deepEqual([PUBLICATION_PRESETS['a4-portrait'].width,PUBLICATION_PRESETS['a4-portrait'].height],[210,297]);
});
test('publication sizes use final physical units; fonts are not scaled with canvas',()=>{
 const v={enabled:true,width:2.1111,height:2.1111,unit:'in',dpi:300,font:10,minimum:8,labels:'auto'};
 const p=publicationOptions(v);
 assert.ok(Math.abs(p.export_size.width_mm-53.62194)<1e-5);
 assert.deepEqual(p.publication,{font_pt:10,min_font_pt:8,label_mode:'auto'});
 const independent=publicationOptions({...v,enabled:false});assert.equal(independent.export_size,undefined);assert.equal(independent.publication.font_pt,10);
 for(const bad of [{font:0},{minimum:0},{minimum:12},{font:NaN}])assert.throws(()=>publicationOptions({...v,...bad}));
});
