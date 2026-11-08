// The sidebar is the single source for labels, order and omics visibility.
export const RETIRED_PAGES=new Set(['course','prompts']);
export function navigationEntries(items,isVisible=item=>!item.hidden&&!item.classList.contains('hidden')){
 return items.filter(item=>!RETIRED_PAGES.has(item.dataset.page)&&isVisible(item)).map(item=>({page:item.dataset.page,label:item.querySelector('span')?.textContent?.trim()||item.dataset.page,active:item.classList.contains('active')}));
}
export function syncTopNavigation(doc=document){
 const list=doc.querySelector('#sidebar .nav-list'),top=doc.getElementById('workflow-stepper');if(!list||!top)return;
 const sourceItems=[...list.querySelectorAll('.nav-item')];
 const entries=navigationEntries(sourceItems,item=>!item.hidden&&!item.classList.contains('hidden')&&getComputedStyle(item).display!=='none');
 const nodes=new Map([...top.children].map(node=>[node.dataset.wf,node]));
 for(const entry of entries){const side=sourceItems.find(item=>item.dataset.page===entry.page);if(side.title!==entry.label)side.title=entry.label;let node=nodes.get(entry.page);if(!node||node.tagName!=='BUTTON'){node?.remove();node=doc.createElement('button');node.type='button';node.className='wf-step';node.dataset.wf=entry.page;}
  if(node.textContent!==entry.label)node.textContent=entry.label;node.title=entry.label;node.classList.toggle('is-active',entry.active);node.classList.remove('is-done');if(entry.active)node.setAttribute('aria-current','page');else node.removeAttribute('aria-current');top.append(node);nodes.delete(entry.page);
 }
 for(const node of [...top.children])if(!entries.some(entry=>entry.page===node.dataset.wf))node.remove();
 top.setAttribute('aria-label',doc.documentElement.lang.startsWith('zh')?'页面导航':'Page navigation');
}
