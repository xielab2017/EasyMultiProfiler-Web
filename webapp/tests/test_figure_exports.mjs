import test from 'node:test';
import assert from 'node:assert/strict';
import {physicalSize, jpegWithDpi, encodeTiff} from '../frontend/js/figure_exports.mjs';
test('physical size conversion and resource bounds', () => {
  assert.deepEqual(physicalSize(18,12,'cm',300),{width_mm:180,height_mm:120,dpi:300});
  assert.deepEqual(physicalSize(7,5,'in',150),{width_mm:177.79999999999998,height_mm:127,dpi:150});
  for(const args of [[0,12,'mm'],[NaN,12,'cm'],[180,120,'xx'],[900,900,'mm',600],[180,120,'mm',96]]) assert.throws(()=>physicalSize(...args));
});
test('JPEG physical density is written in JFIF, both replace and insert', () => {
  const source=Uint8Array.from([255,216,255,217]);
  const encoded=jpegWithDpi(source,300);
  assert.equal(encoded[13],1);
  assert.deepEqual([...encoded.slice(14,18)],[1,44,1,44]);
  const replaced=jpegWithDpi(encoded,150);
  assert.equal(replaced.length,encoded.length);
  assert.deepEqual([...replaced.slice(14,18)],[0,150,0,150]);
  assert.deepEqual([...source],[255,216,255,217]);
});
test('TIFF is real RGB TIFF with physical size and flattened alpha', () => {
  const bytes=encodeTiff(Uint8ClampedArray.from([255,0,0,255,0,0,0,0]),2,1,300);
  assert.deepEqual([...bytes.slice(0,4)],[73,73,42,0]);
  const v=new DataView(bytes.buffer), tags={};
  for(let i=0;i<v.getUint16(8,true);i++) {const p=10+i*12;tags[v.getUint16(p,true)]=v.getUint32(p+8,true);}
  assert.equal(tags[256],2);assert.equal(tags[257],1);assert.equal(tags[296],2);
  assert.equal(v.getUint32(tags[282],true)/v.getUint32(tags[282]+4,true),300);
  assert.deepEqual([...bytes.slice(tags[273])],[255,0,0,255,255,255]);
});
