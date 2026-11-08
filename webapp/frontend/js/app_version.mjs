let version='';
export const getAppVersion=()=>version;
export function versionText(text,current){return String(text).replace(/\bv?\d+\.\d+\.\d+(?:[-+][\w.-]+)?\b/gi,'v'+current);}
export function applyAppVersion(doc=document){
 if(!version)return;
 const title=versionText(doc.title,version);if(title!==doc.title)doc.title=title;
 for(const element of doc.querySelectorAll('.version-badge,#welcome-card h2,.guide-hero-head h2,[data-app-version]')){
  for(const child of element.childNodes)if(child.nodeType===3){const next=versionText(child.textContent,version);if(next!==child.textContent)child.textContent=next;}
 }
}
export async function initAppVersion(doc=document){
 const response=await fetch('/version.json',{cache:'no-store'});if(!response.ok)throw Error('Web release version unavailable');
 const data=await response.json();if(!/^\d+\.\d+\.\d+(?:[-+][\w.-]+)?$/.test(data.version))throw Error('Invalid web release version');version=data.version;
 let pending=false;const observer=new MutationObserver(()=>{if(pending)return;pending=true;queueMicrotask(()=>{pending=false;applyAppVersion(doc);});});observer.observe(doc.body,{subtree:true,childList:true,characterData:true});applyAppVersion(doc);
}
