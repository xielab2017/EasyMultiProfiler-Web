// One translation pass for static and dynamically mounted UI chrome.
// User values, result data, model replies, identifiers and code are excluded.
export const normalizeUI=value=>String(value||'').replace(/\s+/g,' ').trim();
export function buildUIIndex(catalogs,pairs={},full={},aliases={}){
 const invalid=source=>/^(?:[a-z][\w-]*(?:\.[\w-]+)+|[a-z][a-z0-9]*(?:_[a-z0-9]+)+)$/.test(source)||['div','span','small','p','label','button','hint','hidden','form-group','card','checkbox','text','number','option','input','textarea'].includes(source);
 const index=new Map();index.forward=new Set();index.native=new Map();
 const plain=value=>normalizeUI(String(value).replace(/<[^>]*>/g,''));
 for(const [locale,entries]of Object.entries(catalogs))for(const [key,value]of Object.entries(entries)){
  if(typeof value!=='string'||value.includes('<')||value.includes('{'))continue;
  const source=plain(value);if(source.length>1&&!index.has(source))index.set(source,{key});
 }
 for(const [source,translated]of Object.entries(pairs)){if(invalid(source))continue;const row={zh:translated,en:source};index.set(normalizeUI(source),{row});index.set(normalizeUI(translated),{row});}
 const forwards=new Map();
 for(const [english,translations]of Object.entries(full)){
  if(invalid(english))continue;
  const row={en:english,zh:translations.zh||pairs[english]||translations['zh-TW']||english,...translations};
  const entry={row};forwards.set(normalizeUI(english),entry);index.forward.add(normalizeUI(english));
  for(const [locale,text]of Object.entries(row)){if(!index.native.has(locale))index.native.set(locale,new Set());index.native.get(locale).add(normalizeUI(text));}
  for(const text of Object.values(row))if(typeof text==='string'&&!text.includes('<'))index.set(normalizeUI(text),entry);
 }
 for(const [source,entry]of forwards)index.set(source,entry);
 for(const [alias,english]of Object.entries(aliases))if(index.has(normalizeUI(english)))index.set(normalizeUI(alias),index.get(normalizeUI(english)));
 return index;
}
export function uiTranslation(value,locale,index,translate){
 const raw=String(value),source=normalizeUI(raw);
 if(index.native?.get(locale)?.has(source)&&!index.forward?.has(source))return raw;
 const entry=index.get(source);if(!entry)return raw;
 let target=entry.row?(entry.row[locale]||entry.row.en):translate(entry.key,locale);
 target=String(target).trim();
 return (raw.match(/^\s*/)?.[0]||'')+target+(raw.match(/\s*$/)?.[0]||'');
}
const SKIP='script,style,pre,code,textarea,[contenteditable="true"],table,.plot-area,.code-lab-console,.agent-message,.agent-attachments,.agent-sent-attachment,[data-retired-page],#matrix-files,#matrix-series,#matrix-receipt,#rp-studies,#wb-samples,#scat-groups-filter label';
const DATA_SELECT=/(?:group|reference|ref|test|subject|sample|feature|experiment|snapshot|source|project|pathway|omics-pipeline|locale-select|llm-model|chat-model)/i;
const uiNodeSources=new WeakMap();
function translateNode(node,key,current,locale,index,translate){
 let records=uiNodeSources.get(node);if(!records){records=new Map();uiNodeSources.set(node,records);}
 const prior=records.get(key),source=prior?.last===current?prior.source:current;const value=uiTranslation(source,locale,index,translate);records.set(key,{source,last:value});return value;
}
export function localizeUI(root,{locale,index,translate,doc=root.ownerDocument||root}){
 const visit=element=>{
  if(element.closest?.(SKIP))return;
  if(element.tagName==='OPTION'){
   const select=element.closest('select');if(select&&DATA_SELECT.test(select.id)&&!['omics-pipeline'].includes(select.id)&&!['','auto','current','__custom__'].includes(element.value))return;
  }
  for(const node of element.childNodes||[])if(node.nodeType===3&&normalizeUI(node.textContent)){
   const text=translateNode(node,'text',node.textContent,locale,index,translate);if(text!==node.textContent)node.textContent=text;
  }
  for(const attr of ['placeholder','title','aria-label'])if(element.hasAttribute?.(attr)){
   const source=element.getAttribute(attr),text=translateNode(element,attr,source,locale,index,translate);if(text!==source)element.setAttribute(attr,text);
  }
 };
 if(root.nodeType===1)visit(root);
 for(const element of root.querySelectorAll?.('button,label,option,summary,h1,h2,h3,h4,h5,p,small,span,div,a,input,select,nav,li,strong,em,b')||[])visit(element);
}
export function observeUILanguage(doc,options){
 let pending=false,observer;
 const config={subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:['title','placeholder','aria-label']};
 const apply=()=>{pending=false;observer?.disconnect();try{localizeUI(doc.body,options());}finally{observer?.observe(doc.body,config);}};
 observer=new MutationObserver(records=>{if(pending||!records.some(r=>!(r.target.nodeType===1?r.target:r.target.parentElement)?.closest?.(SKIP)))return;pending=true;(doc.defaultView?.requestAnimationFrame||queueMicrotask)(apply);});
 observer.observe(doc.body,config);apply();return {apply,disconnect:()=>observer.disconnect()};
}
