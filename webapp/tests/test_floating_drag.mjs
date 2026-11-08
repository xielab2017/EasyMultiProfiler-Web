import test from 'node:test';import assert from 'node:assert/strict';
import {bindFloatingDrag} from '../frontend/js/floating_drag.mjs';
test('task badge dragging stays within the viewport, persists position and does not accidentally open the tray',()=>{
 const events={},winEvents={},data={},node={style:{},getBoundingClientRect(){return{left:parseFloat(this.style.left)||20,top:parseFloat(this.style.top)||30,width:100,height:32};}},handle={style:{},addEventListener:(name,fn)=>events[name]=fn,setPointerCapture(){}},win={innerWidth:600,innerHeight:400,addEventListener:(name,fn)=>winEvents[name]=fn},storage={getItem:k=>data[k],setItem:(k,v)=>data[k]=v};
 bindFloatingDrag(node,handle,{win,storage});events.pointerdown({button:0,clientX:30,clientY:40,pointerId:1});events.pointermove({clientX:1000,clientY:900});events.pointerup();
 assert.equal(node.style.left,'500px');assert.equal(node.style.top,'368px');assert.deepEqual(JSON.parse(data.emp_jobtray_position_v1),{x:500,y:368});
 let prevented=false;events.click({preventDefault:()=>prevented=true,stopImmediatePropagation(){}});assert(prevented);
 win.innerWidth=300;win.innerHeight=200;winEvents.resize();assert.equal(node.style.left,'200px');assert.equal(node.style.top,'168px');
});
