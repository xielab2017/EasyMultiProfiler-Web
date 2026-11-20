import {physicalSize, convertFigureDimension} from './figure_exports.mjs';
export const A4 = Object.freeze({width:210,height:297,margin:15,gap:6});
export const PUBLICATION_PRESETS = Object.freeze({
 'a4-portrait':{width:210,height:297,columns:1,rows:1,page:true},
 'a4-landscape':{width:297,height:210,columns:1,rows:1,page:true,landscape:true},
 'a4-wide':{width:180,height:120,columns:1,rows:2},
 'a4-two':{width:87,height:87,columns:2,rows:2},
 'a4-three':{width:56,height:56,columns:3,rows:4},
});
export function publicationOptions(values) {
 const font=Number(values.font), minimum=Number(values.minimum);
 if(!Number.isFinite(font)||!Number.isFinite(minimum)||minimum<=0||font<minimum)throw Error('Text sizes must be positive; base font must meet the custom minimum.');
 const publication={font_pt:font,min_font_pt:minimum,label_mode:values.labels==='strict'?'strict':'auto'};
 return {publication,...(values.enabled?{export_size:physicalSize(values.width,values.height,values.unit,values.dpi)}:{})};
}
export function initializePublicationLayout({doc=document,storage=localStorage,translate=key=>key}={}) {
 const get=id=>doc.getElementById('viz-export-'+id);
 if(!get('enabled'))return ()=>({});
 const syncSingleFigure=createPublicationSizeLinks(doc,translate);
 const values=()=>({enabled:get('enabled').checked,unit:get('unit').value,width:get('width').value,height:get('height').value,dpi:get('dpi').value,font:get('font').value,minimum:get('minimum').value,labels:get('labels').value,preset:get('preset').value});
 try{const old=JSON.parse(storage.getItem('emp_publication_profile_v1')||'null');if(old){publicationOptions(old);for(const key of ['unit','width','height','dpi','font','minimum','labels','preset'])if(old[key]!=null)get(key).value=String(old[key]);get('enabled').checked=old.enabled!==false;}}catch{/* Keep accessible defaults if a saved profile is invalid. */}
 if(storage.getItem('emp_per_figure_layout_v1')!=='true'){get('enabled').checked=false;storage.setItem('emp_per_figure_layout_v1','true');}
 let previousUnit=get('unit').value;
 function update(){
  get('status').classList.remove('publication-notes');
  // Typography applies to all native chart exports; physical size is optional.
  for(const key of ['unit','width','height','dpi','preset','font','minimum','labels'])get(key).disabled=!get('enabled').checked;
  const v=values();
  try{
   const options=publicationOptions(v), size=options.export_size;
   syncSingleFigure(options);
   get('status').textContent=size?`${size.width_mm.toFixed(1)} × ${size.height_mm.toFixed(1)} mm · ${v.font} pt (${translate('viz.minimumShort')} ${v.minimum} pt)`:translate('viz.individualCanvas');
   const preset=PUBLICATION_PRESETS[v.preset],landscape=!!preset?.landscape;
   const pw=landscape?297:210,ph=landscape?210:297;
   const cols=preset?.columns||1,rows=preset?.rows||1;
   const width=size?.width_mm||180,height=size?.height_mm||120;
   const page=preset?.page;
   const preview=get('preview');preview.setAttribute('viewBox',`0 0 ${pw} ${ph}`);preview.replaceChildren();
   const rect=(x,y,w,h,active=false)=>{const el=doc.createElementNS('http://www.w3.org/2000/svg','rect');for(const [k,val]of Object.entries({x,y,width:w,height:h,fill:active?'#dbeafe':'#f8fafc',stroke:active?'#2563eb':'#cbd5e1','stroke-width':active?1.2:.5}))el.setAttribute(k,val);preview.append(el);};
   rect(0,0,pw,ph);
   if(page)rect(0,0,pw,ph,true);
   else for(let row=0;row<rows;row++)for(let col=0;col<cols;col++)rect(15+col*(width+6),15+row*(height+6),width,height,row===0&&col===0);
   if(size&&(width>pw||height>ph))get('status').textContent+=' · '+translate('viz.exceedsA4');
   storage.setItem('emp_publication_profile_v1',JSON.stringify(v));
   doc.defaultView?.dispatchEvent(new CustomEvent('emp:publication-change')); 
  }catch(error){get('status').textContent=translate('viz.invalidPublication');}
 }
 get('single-a4')?.addEventListener('click',()=>{get('enabled').checked=true;get('preset').value='a4-portrait';const unit=get('unit').value;get('width').value=String(convertFigureDimension(210,'mm',unit));get('height').value=String(convertFigureDimension(297,'mm',unit));update();});
 get('preset').addEventListener('change',()=>{const p=PUBLICATION_PRESETS[get('preset').value];if(p){const unit=get('unit').value;get('width').value=String(convertFigureDimension(p.width,'mm',unit));get('height').value=String(convertFigureDimension(p.height,'mm',unit));}update();});
 get('unit').addEventListener('change',()=>{const next=get('unit').value;for(const key of ['width','height'])get(key).value=String(convertFigureDimension(get(key).value,previousUnit,next));previousUnit=next;update();});
 for(const key of ['width','height'])get(key).addEventListener('input',()=>{get('preset').value='custom';update();});
 for(const key of ['enabled','dpi','font','minimum','labels'])get(key).addEventListener('change',update);
 doc.defaultView?.addEventListener('emp:locale-change',update);
 update();
 return ()=>{
  for(const key of ['font','minimum',...(get('enabled').checked?['width','height']:[])])if(!get(key).reportValidity())throw Error(translate('viz.invalidPublication'));
  try{return publicationOptions(values());}catch{throw Error(translate('viz.invalidPublication'));}
 };
}

// Local inch controls are dormant while the single publication profile is active.
// Store their independent values so turning the profile off is reversible.
export function createPublicationSizeLinks(doc,translate=key=>key) {
 const ids=['heat','deg','vol','scat','scat-proj','enrich-viz','gsea-viz','ternary-viz','de-significance'].flatMap(prefix=>[prefix+'-width',prefix+'-height']);
 const originals=new Map(),notes=new Map();
 for(const id of ids){const input=doc.getElementById(id);if(!input)continue;const group=input.closest('.form-group'),grid=group?.parentElement;
  originals.set(id,{value:input.value,disabled:input.disabled,hidden:group?.hidden||false});
  if(grid&&!notes.has(grid)){const note=doc.createElement('p');note.className='publication-linked-size';note.setAttribute('role','status');
   const text=doc.createElement('span'),button=doc.createElement('button');button.type='button';button.className='btn btn-outline';button.dataset.publicationSettings='';note.append(text,button);grid.parentElement.insertBefore(note,grid);notes.set(grid,{note,text,button});}
 }
 let linked=false;
 return options=>{
  const size=options.export_size;
  for(const [id,old]of originals){const input=doc.getElementById(id),group=input.closest('.form-group');
   if(size){input.value=String(Number(((id.endsWith('width')?size.width_mm:size.height_mm)/25.4).toFixed(8)));input.disabled=true;if(group)group.hidden=true;}
   else if(linked){input.value=old.value;input.disabled=old.disabled;if(group)group.hidden=old.hidden;}
  }
  for(const {note,text,button}of notes.values()){note.hidden=!size;if(size){text.textContent=`${translate('viz.singleSizeSource')} ${size.width_mm.toFixed(1)} × ${size.height_mm.toFixed(1)} mm · ${options.publication.font_pt} pt`;button.textContent=translate('viz.openPublication');}}
  linked=!!size;
 };
}
