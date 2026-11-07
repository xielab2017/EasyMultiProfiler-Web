import {getLocale} from './locale.js?v=i18n-zh-default-v1';

const sidebar=document.getElementById('sidebar'),list=sidebar?.querySelector('.nav-list');
if(list){
  const key='emp_sidebar_order_v1',items=[...list.querySelectorAll('.nav-item')];
  const defaults=items.map(item=>item.dataset.page);
  const text=(zh,en)=>['zh','zh-TW'].includes(getLocale())?zh:en;
  const controls=document.createElement('div');controls.className='sidebar-navigation-controls';
  const up=document.createElement('button'),down=document.createElement('button'),edit=document.createElement('button'),reset=document.createElement('button');
  up.textContent='↑';down.textContent='↓';edit.id='sidebar-edit-order';reset.id='sidebar-reset-order';
  for(const button of [up,down,edit,reset])button.type='button';
  controls.append(up,down,edit,reset);list.before(controls);
  list.tabIndex=0;
  const status=document.createElement('span');status.className='sr-only';status.setAttribute('role','status');controls.append(status);
  let editing=false;
  function ordered(){return [...list.querySelectorAll('.nav-item')];}
  function visible(){return ordered().filter(item=>!item.hidden&&!item.classList.contains('hidden')&&getComputedStyle(item).display!=='none');}
  function save(){try{localStorage.setItem(key,JSON.stringify(ordered().map(item=>item.dataset.page)));}catch{status.textContent=text('本次顺序已改变，浏览器未允许保存。','Order changed; browser storage is unavailable.');}}
  function restore(order){if(!Array.isArray(order))return;for(const page of [...new Set([...order,...defaults])]){const item=items.find(row=>row.dataset.page===page);if(item)list.append(item);}}
  try{restore(JSON.parse(localStorage.getItem(key)||'null'));}catch{/* Keep the default order when storage is unavailable. */}
  function update(){
    const rows=visible();list.classList.toggle('nav-list--editing',editing);edit.setAttribute('aria-pressed',String(editing));
    up.setAttribute('aria-label',text('向上滚动导航','Scroll navigation up'));down.setAttribute('aria-label',text('向下滚动导航','Scroll navigation down'));
    list.setAttribute('aria-label',text('导航菜单，可上下滚动','Navigation menu; scroll up or down'));
    edit.textContent=editing?text('完成','Done'):text('排序','Order');reset.textContent=text('还原','Reset');reset.title=text('还原默认菜单顺序','Restore default menu order');
    for(const item of items){const name=item.querySelector('span')?.textContent||item.dataset.page,index=rows.indexOf(item),buttons=item.querySelectorAll('.nav-reorder');
      buttons[0].disabled=index<=0;buttons[1].disabled=index<0||index===rows.length-1;
      buttons[0].setAttribute('aria-label',text('上移','Move up')+' '+name);buttons[1].setAttribute('aria-label',text('下移','Move down')+' '+name);
    }
  }
  function move(item,direction){
    const rows=visible(),index=rows.indexOf(item),other=rows[index+direction];if(!other)return;
    if(direction<0)list.insertBefore(item,other);else list.insertBefore(other,item);
    save();update();item.scrollIntoView({block:'nearest'});
    status.textContent=text('已移动：','Moved: ')+(item.querySelector('span')?.textContent||item.dataset.page);
  }
  for(const item of items){
    for(const [symbol,direction]of [['↑',-1],['↓',1]]){const button=document.createElement('button');button.type='button';button.className='nav-reorder';button.textContent=symbol;button.onclick=event=>{event.stopPropagation();move(item,direction);};item.append(button);}
  }
  up.onclick=()=>list.scrollBy({top:-180,behavior:'smooth'});down.onclick=()=>list.scrollBy({top:180,behavior:'smooth'});
  edit.onclick=()=>{editing=!editing;update();};reset.onclick=()=>{restore(defaults);save();update();};
  window.addEventListener('emp:locale-change',update);window.addEventListener('emp:page-view',update);
  document.getElementById('omics-pipeline')?.addEventListener('change',()=>requestAnimationFrame(update));update();
}
