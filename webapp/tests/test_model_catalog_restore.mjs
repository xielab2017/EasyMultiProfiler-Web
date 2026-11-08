import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
test('provider catalog preserves a saved custom model when it exists in the returned directory',()=>{
 const source=fs.readFileSync(new URL('../frontend/js/model_connections.js',import.meta.url),'utf8');
 const code=source.slice(source.indexOf(' function applyCatalog('),source.indexOf('\n function changeProvider'));
 const model={value:'__custom__',options:[],replaceChildren(){this.options=[];},append(row){this.options.push(row);},dispatchEvent(){}};
 const context=vm.createContext({model,document:{getElementById:()=>({value:'MiniMax-M2.7'})},make:(tag,text)=>({tag,text}),tx:(zh)=>zh,status:{},Event:class{}});
 vm.runInContext(code+';applyCatalog({models:[{id:"MiniMax-M3.1-Flash",created:2},{id:"MiniMax-M2.7",created:1}],latest_is_known:true})',context);
 assert.equal(model.value,'MiniMax-M2.7');assert.equal(model.options.length,3);
});
