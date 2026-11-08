export function bindFloatingDrag(node,handle,{win=window,storage=localStorage,key='emp_jobtray_position_v1'}={}){
 let start=null,moved=false;const clamp=(x,y)=>{const rect=node.getBoundingClientRect();return{x:Math.max(0,Math.min(x,win.innerWidth-rect.width)),y:Math.max(0,Math.min(y,win.innerHeight-rect.height))};};
 const place=(x,y)=>{const p=clamp(x,y);Object.assign(node.style,{left:p.x+'px',top:p.y+'px',right:'auto',bottom:'auto'});return p;};
 try{const saved=JSON.parse(storage.getItem(key)||'null');if(saved&&Number.isFinite(saved.x)&&Number.isFinite(saved.y))place(saved.x,saved.y);}catch{}
 handle.style.touchAction='none';handle.style.cursor='grab';handle.title='拖动移动后台任务；点击展开';
 handle.addEventListener('pointerdown',e=>{if(e.button!==0)return;const r=node.getBoundingClientRect();start={x:e.clientX,y:e.clientY,left:r.left,top:r.top};moved=false;handle.setPointerCapture(e.pointerId);});
 handle.addEventListener('pointermove',e=>{if(!start)return;if(Math.hypot(e.clientX-start.x,e.clientY-start.y)>5)moved=true;if(moved)place(start.left+e.clientX-start.x,start.top+e.clientY-start.y);});
 const end=()=>{if(!start)return;start=null;if(moved){const r=node.getBoundingClientRect();try{storage.setItem(key,JSON.stringify({x:r.left,y:r.top}));}catch{}}};
 handle.addEventListener('pointerup',end);handle.addEventListener('pointercancel',end);handle.addEventListener('click',e=>{if(moved){e.preventDefault();e.stopImmediatePropagation();moved=false;}},true);
 win.addEventListener('resize',()=>{if(node.style.left&&node.style.top)place(Number.parseFloat(node.style.left),Number.parseFloat(node.style.top));});
 return {place};
}
