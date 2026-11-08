import test from 'node:test';
import assert from 'node:assert/strict';
import {attachResultPlot,plotImageDimensions} from '../frontend/js/plot_attachment.mjs';
test('selected plot is bounded and uploaded as an image attachment without page content',async()=>{
 assert.deepEqual(plotImageDimensions(3600,2400),{width:1800,height:1200});
 assert.throws(()=>plotImageDimensions(0,20));
 let sent;const image={naturalWidth:2400,naturalHeight:1800,closest:()=>null,decode:async()=>{}};
 const canvas={getContext:()=>({fillRect(){},drawImage(){}}),toBlob:cb=>cb(new Blob(['png'],{type:'image/png'}))};
 const item=await attachResultPlot({querySelectorAll:()=>[image]},{doc:{createElement:()=>canvas},upload:async(path,options)=>{sent={path,options};return {ok:true,json:async()=>({id:'a'.repeat(32),kind:'image',preview_url:'/local'})};}});
 assert.equal(item.kind,'image');assert.equal(canvas.width,1800);assert.equal(canvas.height,1350);
 assert.equal(sent.options.headers['Content-Type'],'image/png');assert.ok(sent.options.body instanceof Blob);
 assert.equal(await attachResultPlot({querySelectorAll:()=>[]}),null);
});
