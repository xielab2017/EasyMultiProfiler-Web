export const nearBottom=(node,gap=70)=>node.scrollHeight-node.clientHeight-node.scrollTop<=gap;
export function bindChatFollow(view,jump,win=globalThis){
  let follow=true,scheduled=false;const frame=win.requestAnimationFrame?.bind(win)||((fn)=>setTimeout(fn,0));
  const reconcile=()=>{scheduled=false;if(follow){view.scrollTop=view.scrollHeight;jump.hidden=true;}else jump.hidden=nearBottom(view);};
  const changed=()=>{if(!scheduled){scheduled=true;frame(reconcile);}};
  view.addEventListener('scroll',()=>{follow=nearBottom(view);jump.hidden=follow;},{passive:true});
  view.addEventListener('wheel',e=>{if(e.deltaY<0)follow=false;},{passive:true});
  view.addEventListener('keydown',e=>{if(['PageUp','Home','ArrowUp'].includes(e.key))follow=false;});
  const observer=win.MutationObserver?new win.MutationObserver(changed):null;observer?.observe(view,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:['open','hidden','class']});
  const resize=win.ResizeObserver?new win.ResizeObserver(changed):null;resize?.observe(view);
  // Observe message sizes as well as the flex viewport (images and details can resize later).
  const observed=new Set();const watchChildren=()=>{for(const child of observed)if(![...(view.children||[])].includes(child)){resize?.unobserve?.(child);observed.delete(child);}for(const child of view.children||[])if(!observed.has(child)){resize?.observe(child);observed.add(child);}};
  const children=win.MutationObserver?new win.MutationObserver(watchChildren):null;children?.observe(view,{childList:true});
  const latest=()=>{follow=true;changed();};jump.onclick=latest;
  return {latest,changed,dispose(){observer?.disconnect();children?.disconnect();resize?.disconnect();observed.clear();}};
}
export function panelWidth(value,viewport,sidebar=220){return Math.max(300,Math.min(Number(value)||420,Math.max(300,viewport-sidebar-280),1000));}
export function bindPanelResize(panel,handle,win=window,storage=localStorage){
  const key='emp_chat_panel_width_v1',style=panel.ownerDocument.documentElement.style;let width=420,start=null;
  const apply=value=>{width=panelWidth(value,win.innerWidth,Number.parseFloat(win.getComputedStyle(panel.ownerDocument.documentElement).getPropertyValue('--sidebar-w'))||220);style.setProperty('--code-lab-user-width',width+'px');handle.setAttribute('aria-valuenow',String(Math.round(width)));};
  try{const saved=Number(storage.getItem(key));if(saved)apply(saved);}catch{}
  handle.addEventListener('pointerdown',e=>{if(e.button!==0)return;e.preventDefault();start={x:e.clientX,width:panel.getBoundingClientRect().width};handle.setPointerCapture(e.pointerId);panel.ownerDocument.body.classList.add('chat-resizing');});
  handle.addEventListener('pointermove',e=>{if(start)apply(start.width+start.x-e.clientX);});
  const stop=()=>{if(!start)return;start=null;panel.ownerDocument.body.classList.remove('chat-resizing');try{storage.setItem(key,String(width));}catch{}};
  handle.addEventListener('pointerup',stop);handle.addEventListener('pointercancel',stop);handle.addEventListener('lostpointercapture',stop);
  handle.addEventListener('keydown',e=>{if(['ArrowLeft','ArrowRight'].includes(e.key)){e.preventDefault();apply((panel.getBoundingClientRect().width||width)+(e.key==='ArrowLeft'?24:-24));try{storage.setItem(key,String(width));}catch{}}});
  handle.addEventListener('dblclick',()=>{apply(420);try{storage.removeItem(key);}catch{}});
  win.addEventListener('resize',()=>apply(width));
}
