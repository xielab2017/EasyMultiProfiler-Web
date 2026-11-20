import {MM_PER_UNIT, convertFigureDimension} from './figure_exports.mjs';
// Defaults use A4 as a reference; exported sizes are chosen independently.
export const FIGURE_STANDARDS=Object.freeze({
 heatmap:{label:['普通热图','Heatmap'],width:180,height:160,panel:'viz-heatmap',prefixes:['heat']},
 deg_heatmap:{label:['DEG 热图','DEG heatmap'],width:180,height:220,anchor:'deg-width',prefixes:['deg']},
 volcano:{label:['火山图','Volcano'],width:120,height:100,panel:'viz-volcano',prefixes:['vol']},
 boxplot:{label:['箱线图','Boxplot'],width:120,height:100,panel:'viz-boxplot'},
 barplot:{label:['柱状图','Barplot'],width:180,height:120,panel:'viz-barplot'},
 scatter:{label:['PCA / 排序图','PCA / ordination'],width:120,height:100,panel:'viz-scatter',prefixes:['scat','scat-proj']},
 enrichment:{label:['富集气泡图','Enrichment dotplot'],width:180,height:180,panel:'viz-enrichment-dotplot',prefixes:['enrich-viz']},
 gsea:{label:['GSEA 曲线','GSEA curves'],width:180,height:140,panel:'viz-gsea',prefixes:['gsea-viz']},
 ternary:{label:['三元组成图','Ternary'],width:120,height:110,panel:'viz-ternary',prefixes:['ternary-viz']},
 de_significance:{label:['差异显著性图','DE significance'],width:120,height:110,panel:'viz-de-significance',prefixes:['de-significance']},
 alpha:{label:['多样性图','Diversity'],width:120,height:100,panel:'viz-alpha'},
 structure:{label:['组成图','Composition'],width:180,height:120,panel:'viz-structure'},
 sankey:{label:['桑基图','Sankey'],width:180,height:140,panel:'viz-m16s-sankey'},
 network:{label:['网络图','Network'],width:180,height:160,panel:'viz-m16s-network'},
 analysis_dimension:{label:['降维结果图','Saved ordination'],width:120,height:100,panel:'analysis-dimension-figure'},
 analysis_correlation:{label:['相关结果图','Saved correlation'],width:180,height:160,panel:'analysis-correlation-figure'},
 analysis_cluster:{label:['聚类结果图','Saved clustering'],width:180,height:140,panel:'analysis-cluster-figure'},
 analysis_marker:{label:['标志物结果图','Saved marker scores'],width:180,height:160,panel:'analysis-marker-figure'},
 clinical:{label:['临床图','Clinical'],width:180,height:160,panel:'page-clinical'},
});
export function figureKindForRequest(path,body={}){
 if(path==='/visualize/analysis-result')return 'analysis_'+body.kind;
 if(path.endsWith('/analysis-result/describe')||path.includes('/analysis-result/sources/'))return null;
 if(path==='/workbench/figure')return body.kind==='pca'?'scatter':body.kind==='heatmap'?'heatmap':null;
 if(path==='/visualize/method-library')return body.method==='ternary'?'ternary':'de_significance';
 if(path.includes('/enrichment/dotplot'))return 'enrichment';
 if(path.includes('/enrichment/gsea'))return 'gsea';
 const kind=path.match(/\/visualize\/([a-z_]+)$/)?.[1];if(kind&&FIGURE_STANDARDS[kind])return kind;
 if(path.startsWith('/clinical/'))return 'clinical';
 return null;
}
export const FIGURE_APPEARANCE = Object.freeze({
 title_font:['标题字号（pt）','Title text (pt)','font'],axis_font:['坐标刻度字号（pt）','Axis ticks (pt)','font'],axis_title_font:['坐标标题字号（pt）','Axis titles (pt)','font'],legend_font:['图例字号（pt）','Legend text (pt)','font'],label_font:['数据标注字号（pt）','Data labels (pt)','font'],
 axis_line:['坐标轴与外框线宽（pt）','Axes / frame width (pt)','line'],plot_line:['曲线与图形边线宽（pt）','Curve / outline width (pt)','line'],threshold_line:['阈值参考线宽（pt）','Reference line width (pt)','line'],grid_line:['网格线宽（pt）','Grid line width (pt)','line'],cell_line:['单元格边线宽（pt）','Cell border width (pt)','line'],tree_line:['聚类树线宽（pt）','Dendrogram width (pt)','line'],point_size:['数据点大小（mm）','Point size (mm)','positive'],
 scale_position:['色阶位置（Scale）','Color scale position','heatmap_position'],annotation_position:['分组图例位置','Group legend position','heatmap_position'],
 palette:['配色方案','Color palette','palette'],custom_colors:['自定义颜色（逗号分隔）','Custom colors (comma separated)','text'],family:['字体','Font family','family'],legend:['图例位置','Legend position','legend'],background:['背景颜色','Background color','color'],method:['绘图样式','Figure style','method'],dpi:['位图分辨率（DPI）','Raster resolution (DPI)','dpi'],
});
export function appearanceFields(kind){
 const heat=['heatmap','deg_heatmap','analysis_correlation'].includes(kind);
 return Object.keys(FIGURE_APPEARANCE).filter(key=>heat?!['axis_line','plot_line','threshold_line','grid_line','point_size','axis_font','axis_title_font','legend','method','background'].includes(key):!['cell_line','tree_line','scale_position','annotation_position'].includes(key));
}
// Values displayed for inherited fields are not submitted as overrides.
export function figureAppearanceSignature(options={}){
 return JSON.stringify(Object.fromEntries(['export_size','publication','color_panel','custom_colors','figure_method'].map(key=>[key,options[key]??null])));
}
export function automaticFigureOptions(kind,width,height){
 if(!FIGURE_STANDARDS[kind]||![width,height].every(v=>Number.isFinite(v)&&v>0))throw Error('Invalid automatic canvas');
 const short=Math.min(width,height),quarter=value=>Math.max(.25,Math.round(value*4)/4);
 const font=quarter(Math.max(.5,Math.min(12,6*Math.sqrt(short/60))));
 const scale=Math.max(.3,Math.min(2,Math.sqrt(short/60))),line=value=>Number((value*scale).toFixed(4));
 const dpi=[300,150,72].find(value=>Math.ceil(width/25.4*value)*Math.ceil(height/25.4*value)<=40000000)||72;
 const appearance={title_font:quarter(font*1.1),axis_font:font,axis_title_font:font,legend_font:quarter(font*.95),label_font:font,
 axis_line:line(.35),plot_line:line(.5),threshold_line:line(.3),grid_line:line(.15),cell_line:line(.2),tree_line:line(.4),
 palette:'npg',family:'sans',legend:width>=100&&width/height>1.2?'right':'bottom',background:'#FFFFFF',method:'original'};
 if(['heatmap','deg_heatmap','analysis_correlation'].includes(kind)){appearance.scale_position=appearance.legend;appearance.annotation_position=appearance.legend;}
 if(kind==='enrichment')appearance.legend='right';
 if(kind==='volcano')appearance.custom_colors='#2166AC,#BDBDBD,#B2182B';
 return {export_size:{width_mm:width,height_mm:height,dpi},publication:{font_pt:font,min_font_pt:font*.65,label_mode:'auto',auto_params:true,figure_kind:kind,appearance},color_panel:'npg',custom_colors:appearance.custom_colors||null,figure_method:'original'};
}
export function figureAppearanceDefaults(kind,profile={},effective={}){
 const full=profile.auto_params===true;
 const widthMm=profile.width==null?FIGURE_STANDARDS[kind].width:Number(profile.width)*MM_PER_UNIT[profile.unit||'mm'];
 const heightMm=profile.height==null?FIGURE_STANDARDS[kind].height:Number(profile.height)*MM_PER_UNIT[profile.unit||'mm'];
 const generated=full?automaticFigureOptions(kind,widthMm,heightMm):null;
 const font=generated?.publication.font_pt??Number(profile.font||10),automatic=full||profile.labels==='auto'||profile.labels==='strict';
 const width=profile.width==null?FIGURE_STANDARDS[kind].width:Number(profile.width)*MM_PER_UNIT[profile.unit||'mm'];
 const compact=width<100,adaptive=profile.labels==='auto'&&compact,stroke=72.27/25.4*.75;
 const values={title_font:automatic&&!compact?font+2:font,axis_font:font,axis_title_font:font,legend_font:font,label_font:font,
 axis_line:adaptive?.35:.5*stroke,plot_line:adaptive?.5:.5*stroke,threshold_line:adaptive?.35:.4*stroke,grid_line:adaptive?.2:.3*stroke,cell_line:.75,tree_line:.75,
 scale_position:'right',annotation_position:'right',
 point_size:kind==='volcano'?1.75:1.5,palette:'npg',custom_colors:kind==='volcano'?'#2166AC,#BDBDBD,#B2182B':'#E64B35,#4DBBD5,#00A087',family:'sans',legend:automatic&&compact?'bottom':'right',background:'#FFFFFF',method:'original',dpi:300};
 if(full)Object.assign(values,generated.publication.appearance,{dpi:generated.export_size.dpi});
 for(const key of appearanceFields(kind)){
  const value=effective[key],type=FIGURE_APPEARANCE[key][2];if(value==null)continue;
  if(['font','line','positive','dpi'].includes(type)){if(typeof value==='number'&&Number.isFinite(value)&&(type==='line'?value>=0:value>0))values[key]=value;}
  else if(typeof value==='string'&&value.length<=500)values[key]=value;
 }
 return values;
}
export function figureStandardOptions(kind,profile={}){
 const standard=FIGURE_STANDARDS[kind];if(!standard)throw Error('Unknown figure type');
 const unit=profile.unit??'mm';if(!Object.hasOwn(MM_PER_UNIT,unit))throw Error('Unknown figure size unit');
 const dimension=(key)=>Number((profile[key]==null?standard[key]:Number(profile[key])*MM_PER_UNIT[unit]).toPrecision(12));
 const width=dimension('width'),height=dimension('height');
 if(profile.auto_params===true)return automaticFigureOptions(kind,width,height);
 const font=Number(profile.font??10),minimum=Number(profile.minimum??8);
 const mode=['auto','strict'].includes(profile.labels)?profile.labels:'manual';
 if(![width,height,font,minimum].every(Number.isFinite)||width<=0||height<=0||font<=0||minimum<=0||(mode!=='manual'&&font<minimum))throw Error('尺寸和字号必须为正数。 / Sizes and text must be positive.');
 const appearance={};
 for(const key of appearanceFields(kind)){
  const value=profile[key];if(value==null||value==='')continue;
  const type=FIGURE_APPEARANCE[key][2];
  if(['font','line','positive'].includes(type)){const number=Number(value);if(!Number.isFinite(number)||(type==='line'?number<0:number<=0))throw Error('字号和点大小需为正数；线宽可为 0。 / Invalid appearance value');appearance[key]=number;}
  else if(type==='dpi'){if(![72,150,300,600].includes(Number(value)))throw Error('Invalid DPI');}
  else if(type==='palette'){if(!['npg','lancet','nejm','jama','aaas','tableau','set2','dark3','viridis'].includes(value))throw Error('Invalid palette');appearance[key]=value;}
  else if(type==='family'){if(!['sans','serif','mono','Helvetica','Arial','Times','Courier'].includes(value))throw Error('Invalid font family');appearance[key]=value;}
  else if(type==='legend'){if(!['right','left','top','bottom','none'].includes(value))throw Error('Invalid legend position');appearance[key]=value;}
  else if(type==='heatmap_position'){if(!['auto','right','left','top','bottom'].includes(value))throw Error('Invalid heatmap legend position');appearance[key]=value;}
  else if(type==='method'){if(!['original','self_built'].includes(value))throw Error('Invalid figure style');appearance[key]=value;}
  else if(type==='color'){if(!/^#[0-9a-f]{6}$/i.test(value))throw Error('Invalid color');appearance[key]=value;}
  else {const colors=value.split(',').map(s=>s.trim());if(!colors.length||colors.length>30||colors.some(c=>!/^#[0-9a-f]{6}$/i.test(c)))throw Error('请输入十六进制颜色，以逗号分隔。');appearance[key]=colors.join(',');}
 }
 return {export_size:{width_mm:width,height_mm:height,dpi:Number(profile.dpi||300)},publication:{font_pt:font,min_font_pt:minimum,label_mode:mode,...(Object.keys(appearance).length?{appearance}:{})},color_panel:appearance.palette||'npg',custom_colors:appearance.custom_colors||null,figure_method:appearance.method||'original'};
}
export function adjustFigureFont(font, minimum, field, delta, automatic=true) {
 if(!['font','minimum'].includes(field)||!Number.isFinite(delta))throw Error('Invalid font adjustment');
 font=Number(font);minimum=Number(minimum);
 if(!Number.isFinite(font)||font<=0)font=10;
 if(!Number.isFinite(minimum)||minimum<=0)minimum=8;
 if(field==='font'){if(font+delta>0)font=Number((font+delta).toPrecision(12));if(automatic)minimum=Math.min(minimum,font);}
 else{if(minimum+delta>0)minimum=Number((minimum+delta).toPrecision(12));if(automatic)font=Math.max(font,minimum);}
 return {font,minimum};
}
export const FIGURE_RENDER_BUTTONS=Object.freeze({heatmap:'btn-heatmap',deg_heatmap:'btn-deg-heatmap',volcano:'btn-volcano',boxplot:'btn-boxplot',barplot:'btn-barplot',scatter:'btn-scatter',enrichment:'enrich-viz-generate',gsea:'gsea-viz-generate',ternary:'ternary-viz-generate',de_significance:'de-significance-generate',alpha:'btn-alpha-plot',structure:'btn-structure',sankey:'m16s-btn-sankey',network:'m16s-btn-network',analysis_dimension:'analysis-dimension-generate',analysis_correlation:'analysis-correlation-generate',analysis_cluster:'analysis-cluster-generate',analysis_marker:'analysis-marker-generate'});
export function initializeFigureStandards({doc=document,storage=localStorage,isEnglish=()=>false,onAutoGenerate=()=>true}={}){
 let saved={};try{saved=JSON.parse(storage.getItem('emp_figure_standards_v1')||'{}');if(!saved||Array.isArray(saved)||typeof saved!=='object')saved={};}catch{}
 if(storage.getItem('emp_manual_figures_v1')!=='true'){for(const profile of Object.values(saved))if(profile&&typeof profile==='object')profile.labels='manual';storage.setItem('emp_figure_standards_v1',JSON.stringify(saved));storage.setItem('emp_manual_figures_v1','true');}
 let effective={};try{effective=JSON.parse(storage.getItem('emp_figure_effective_v1')||'{}');if(!effective||Array.isArray(effective)||typeof effective!=='object')effective={};}catch{}
 const cards=new Map();
 const create=(tag,text)=>{const node=doc.createElement(tag);if(text)node.textContent=text;return node;};
 for(const [kind,standard]of Object.entries(FIGURE_STANDARDS)){
  const anchor=standard.anchor?doc.getElementById(standard.anchor)?.closest('.form-grid'):doc.getElementById(standard.panel);
  if(!anchor)continue;
  let profile=saved[kind]||{};try{figureStandardOptions(kind,profile);}catch{profile={};delete saved[kind];}
  if(typeof profile.auto_params!=='boolean')profile.auto_params=profile.labels==='auto';
  const manual={...profile,labels:'manual',auto_params:false};
  const card=create('section');card.className='figure-standard-card';card.id='figure-standard-'+kind;
  const heading=create('strong'),grid=create('div');grid.className='form-grid';card.append(heading,grid);
  const inputs={},fontButtons=[];
  for(const name of ['preset','unit','width','height','font','minimum','labels']){
   const group=create('div');group.className='form-group';const label=create('label'),input=create(['preset','labels','unit'].includes(name)?'select':'input');input.id='figure-'+kind+'-'+name;label.htmlFor=input.id;
   if(name==='unit'){for(const value of ['mm','cm','in','pt']){const option=create('option',value==='in'?'inch':value==='pt'?'point (pt)':value);option.value=value;input.append(option);}input.value=profile.unit||'mm';}
   else if(name==='labels'){for(const value of ['manual','auto','strict']){const option=create('option');option.value=value;input.append(option);}input.value=profile.labels||'manual';}
   else if(name==='preset'){for(const value of ['recommended','a4','custom']){const option=create('option');option.value=value;input.append(option);}input.value=profile.preset||'custom';}
   else{input.type='number';input.min='0';input.step='any';input.required=true;input.value=String(profile[name]??(name==='font'?10:name==='minimum'?8:convertFigureDimension(standard[name],'mm',profile.unit||'mm')));}
   if(['font','minimum'].includes(name)){
    const control=create('div');control.className='figure-font-stepper';
    const decrease=create('button','−'),increase=create('button','+');
    for(const [button,delta]of [[decrease,-.5],[increase,.5]]){button.type='button';button.dataset.fontField=name;button.dataset.fontDelta=String(delta);button.addEventListener('click',()=>{
      const next=adjustFigureFont(inputs.font.input.value,inputs.minimum.input.value,name,delta,inputs.labels.input.value!=='manual');
      inputs.font.input.value=String(next.font);inputs.minimum.input.value=String(next.minimum);
      input.dispatchEvent(new Event('input',{bubbles:true}));input.dispatchEvent(new Event('change',{bubbles:true}));
    });fontButtons.push(button);}
    control.append(decrease,input,increase);group.append(label,control);
   }else group.append(label,input);
   grid.append(group);inputs[name]={input,label};
  }
  const autoWrap=create('div');autoWrap.className='figure-auto-control';
  const autoLabel=create('label'),auto=create('input'),autoText=create('span');auto.type='checkbox';auto.id='figure-'+kind+'-auto_params';auto.checked=profile.auto_params===true;autoLabel.htmlFor=auto.id;autoLabel.append(auto,autoText);autoWrap.append(autoLabel);card.insertBefore(autoWrap,grid);
  for(const key of ['labels','minimum']){inputs[key].input.closest('.form-group').hidden=true;inputs[key].input.disabled=true;}
  auto.addEventListener('change',()=>{
    const row=cards.get(kind);clearTimeout(row.timer);
    if(auto.checked)row.manual={...rawProfile(row),labels:'manual',auto_params:false};
    else restoreManual(row);
    change();
  });
  const detail=create('details'),summary=create('summary'),appearanceGrid=create('div');detail.className='figure-appearance';appearanceGrid.className='form-grid';detail.append(summary,appearanceGrid);card.append(detail);
  for(const name of appearanceFields(kind)){
   const [zh,en,type]=FIGURE_APPEARANCE[name],group=create('div'),label=create('label');group.className='form-group';
   const choices={heatmap_position:['auto','right','left','top','bottom'],palette:['npg','lancet','nejm','jama','aaas','tableau','set2','dark3','viridis'],family:['sans','serif','mono','Helvetica','Arial','Times','Courier'],legend:['right','left','top','bottom','none'],method:['original','self_built'],dpi:['72','150','300','600']}[type];
   const input=create(choices?'select':'input');input.id='figure-'+kind+'-'+name;label.htmlFor=input.id;
   if(choices){const inherit=create('option','默认 / Default');inherit.value='';input.append(inherit);for(const value of choices){const opt=create('option',value);opt.value=value;input.append(opt);}}
   else {input.type=['font','line','positive'].includes(type)?'number':'text';if(input.type==='number'){input.min='0';input.step='any';}input.placeholder=type==='text'?'#E64B35,#4DBBD5':type==='color'?'#FFFFFF':'默认 / Default';}
   input.value=profile[name]??'';input.dataset.inherited=String(profile[name]==null||profile[name]==='');
   const info=create('div');info.className='figure-default-info';const source=create('small'),reset=create('button');reset.type='button';reset.className='figure-default-reset';reset.dataset.figureReset=name;info.append(source,reset);
   reset.addEventListener('click',()=>{input.dataset.inherited='true';input.value='';change();});
   input.addEventListener('input',()=>{input.dataset.inherited='false';});
   group.append(label,input,info);appearanceGrid.append(group);inputs[name]={input,label,source,reset};
  }
  const status=create('p');status.className='hint';status.setAttribute('role','status');const fontHint=create('p');fontHint.className='hint figure-font-hint';card.append(status,fontHint);
  if(standard.anchor)anchor.parentElement.insertBefore(card,anchor);else anchor.insertBefore(card,anchor.firstChild);
  cards.set(kind,{card,heading,status,inputs,standard,kind,fontButtons,fontHint,summary,auto,autoText,manual,timer:null});
  const read=()=>profileFor(kind);
  const change=()=>{const profile=read();try{figureStandardOptions(kind,profile);saved[kind]=profile;if(!auto.checked)cards.get(kind).manual={...profile,auto_params:false};storage.setItem('emp_figure_standards_v1',JSON.stringify(saved));status.classList.remove('publication-notes');}catch(error){status.classList.add('publication-notes');status.textContent=error.message;}sync();schedule(kind);};
  let previousUnit=inputs.unit.input.value;
  const updateBounds=()=>{for(const key of ['width','height']){inputs[key].input.min='0';inputs[key].input.removeAttribute('max');}};
  inputs.unit.input.addEventListener('change',()=>{const unit=inputs.unit.input.value;for(const key of ['width','height'])inputs[key].input.value=String(convertFigureDimension(inputs[key].input.value,previousUnit,unit));previousUnit=unit;updateBounds();change();});
  updateBounds();
  inputs.preset.input.addEventListener('change',()=>{const preset=inputs.preset.input.value;if(preset!=='custom'){inputs.width.input.value=String(convertFigureDimension(preset==='a4'?210:standard.width,'mm',inputs.unit.input.value));inputs.height.input.value=String(convertFigureDimension(preset==='a4'?297:standard.height,'mm',inputs.unit.input.value));}change();});
  inputs.labels.input.addEventListener('change',()=>{if(inputs.labels.input.value!=='manual'&&Number(inputs.minimum.input.value)>Number(inputs.font.input.value))inputs.minimum.input.value=inputs.font.input.value;change();});
  for(const name of appearanceFields(kind))inputs[name].input.addEventListener('change',()=>{const input=inputs[name].input;input.dataset.inherited=String(input.value==='');if(inputs.labels.input.value!=='manual'&&FIGURE_APPEARANCE[name][2]==='font'&&Number(inputs[name].input.value)>0&&Number(inputs[name].input.value)<Number(inputs.minimum.input.value))inputs.minimum.input.value=inputs[name].input.value;change();});
  for(const name of ['width','height','font','minimum'])inputs[name].input.addEventListener('change',()=>{if(inputs.labels.input.value!=='manual'&&name==='font'&&Number(inputs.font.input.value)>0&&Number(inputs.font.input.value)<Number(inputs.minimum.input.value))inputs.minimum.input.value=inputs.font.input.value;if(inputs.labels.input.value!=='manual'&&name==='minimum'&&Number(inputs.minimum.input.value)>Number(inputs.font.input.value)&&Number.isFinite(Number(inputs.minimum.input.value)))inputs.font.input.value=inputs.minimum.input.value;inputs.preset.input.value='custom';change();});
 }
 function rawProfile(row){const profile=Object.fromEntries(Object.entries(row.inputs).map(([key,{input}])=>[key,input.dataset.inherited==='true'?'':input.value]));if(row.kind==='volcano')profile._label_top=doc.getElementById('vol-label-top')?.value??15;if(row.kind==='enrichment')for(const key of ['wrap','size','low','high'])profile['_'+key]=doc.getElementById('enrich-viz-'+key)?.value??'';return profile;}
 function restoreManual(row){
   if(row.kind==='enrichment')for(const [key,fallback]of Object.entries({wrap:45,size:8,low:'#C9283E',high:'#3B6FB6'})){const input=doc.getElementById('enrich-viz-'+key);if(input){input.value=String(row.manual['_'+key]??fallback);input.disabled=false;}}
   if(row.kind==='volcano'){const input=doc.getElementById('vol-label-top');if(input){input.value=String(row.manual._label_top??15);input.disabled=false;}}
   for(const key of ['font','minimum','labels',...appearanceFields(row.kind)]){
     const field=row.inputs[key];if(!field)continue;const value=row.manual[key]??(key==='font'?10:key==='minimum'?8:key==='labels'?'manual':'');
     field.input.value=String(value);if(FIGURE_APPEARANCE[key])field.input.dataset.inherited=String(value==='');
   }
 }
 function profileFor(kind){
   const row=cards.get(kind);if(!row)return saved[kind]||{};
   const dims=Object.fromEntries(['preset','unit','width','height'].map(key=>[key,row.inputs[key].input.value]));
   return row.auto.checked?{...row.manual,...dims,auto_params:true}:{...rawProfile(row),labels:'manual',auto_params:false};
 }
 function schedule(kind){
   const row=cards.get(kind);clearTimeout(row.timer);if(!row.auto.checked)return;
   row.timer=setTimeout(function render(){
     if(!row.auto.checked||!row.card.closest('.page.active'))return;
     const panel=row.card.closest('.tab-panel');if(panel&&!panel.classList.contains('active'))return;
     try{figureStandardOptions(kind,profileFor(kind));}catch{return;}
     if(onAutoGenerate(kind)===false)row.timer=setTimeout(render,250);
   },600);
 }
 doc.addEventListener('click',event=>{
   const button=event.target.closest('button');if(!button)return;
   const kind=Object.keys(FIGURE_RENDER_BUTTONS).find(type=>FIGURE_RENDER_BUTTONS[type]===button.id);const row=cards.get(kind);if(row){clearTimeout(row.timer);row.timer=null;}
 });
 function sync(){
  for(const [kind,row]of cards){const en=isEnglish();let options;try{options=figureStandardOptions(kind,profileFor(kind));}catch{continue;}
   const full=row.auto.checked;
   if(full){row.inputs.font.input.value=String(options.publication.font_pt);row.inputs.minimum.input.value=String(options.publication.min_font_pt);row.inputs.labels.input.value='auto';}
   row.heading.textContent=(en?'Figure settings · ':'本图独立设置 · ')+row.standard.label[en?1:0];
   const unit=row.inputs.unit.input.value==='in'?'inch':row.inputs.unit.input.value;
   const names=en?['Preset','Size unit',`Width (${unit})`,`Height (${unit})`,'Text (pt)','Minimum · auto only (pt)','Layout mode']:['本图尺寸方案','尺寸单位',`图片宽度（${unit}）`,`图片高度（${unit}）`,'基准字号（pt）','最小字号 · 仅自动（pt）','排版模式'];
   Object.entries(row.inputs).forEach(([key,{input,label}],i)=>{label.textContent=names[i]??FIGURE_APPEARANCE[key][en?1:0];input.disabled=key==='labels'||key==='minimum'||(full&&!['preset','unit','width','height'].includes(key));});
   [...row.inputs.preset.input.children].forEach((option,i)=>option.textContent=(en?['Recommended for this figure','One A4 page · one figure','Custom']:['本图推荐尺寸','一张 A4 纸 · 一张图','自定义尺寸'])[i]);
   [...row.inputs.labels.input.children].forEach((option,i)=>option.textContent=(en?['Manual · use my settings','Auto · fit points, labels and legends','Strict · require all labels']:['手动 · 按我的设置出图','自动 · 适配点、标签与图例','严格 · 要求全部标签'])[i]);
   row.autoText.textContent=en?'Automatic parameter configuration':'自动参数配置';
   row.summary.textContent=en?'Text, lines, colors and export':'文字、线条、配色与导出设置';
   const profile=profileFor(kind),signature=figureAppearanceSignature(options),last=effective[kind];
   const measured=last?.signature===signature?last.values:{};
   const defaults=figureAppearanceDefaults(kind,profile,measured);
   if(kind==='enrichment')for(const key of ['wrap','size','low','high']){const input=doc.getElementById('enrich-viz-'+key);if(input){input.disabled=full;if(full){const computed={wrap:measured.label_wrap??Math.max(1,Math.floor(options.export_size.width_mm*.42/(options.publication.font_pt*25.4/72))),size:measured.max_point_size??1.2,low:'#554A9A',high:'#E52449'};input.value=String(computed[key]);}}}
   if(kind==='volcano'){const input=doc.getElementById('vol-label-top');if(input){input.disabled=full;if(full)input.value=String(Number.isFinite(measured.label_count)?measured.label_count:Math.max(2,Math.floor(Math.max(1,(options.export_size.width_mm-14)*(options.export_size.height_mm-23))/(options.publication.font_pt*25.4/72)**2*.025)));}}
   const namesByValue={auto:en?'Automatic position':'自动选择位置',npg:'Nature (NPG)',sans:en?'Sans-serif':'无衬线 (sans)',serif:en?'Serif':'衬线 (serif)',mono:en?'Monospace':'等宽 (mono)',original:en?'Original R style':'原有 R 样式',self_built:en?'Self-built style':'自建样式',right:en?'Right':'右侧',left:en?'Left':'左侧',top:en?'Top':'顶部',bottom:en?'Bottom':'底部',none:en?'Hidden':'不显示'};
   for(const key of appearanceFields(kind)){
     const field=row.inputs[key],input=field.input,inherit=full||input.dataset.inherited==='true',value=defaults[key],type=FIGURE_APPEARANCE[key][2];
     const display=typeof value==='number'?String(Number(value.toFixed(4))):(namesByValue[value]||String(value));
     if(full)input.dataset.inherited='true';
     if(input.tagName==='SELECT'){for(const option of [...input.children].slice(1))option.textContent=namesByValue[option.value]||option.value;input.children[0].textContent=display+(type==='dpi'?' DPI':'')+(full?(en?' · auto':' · 自动'):(en?' · inherited':' · 跟随默认'));if(inherit)input.value='';}
     else if(inherit)input.value=typeof value==='number'?String(Number(value.toFixed(4))):String(value);
     input.placeholder='';
     field.source.textContent=inherit?(Object.hasOwn(measured,key)?(en?'Last rendered value · inherited':'最近出图实际值 · 跟随默认'):(en?'Initial reference · inherited':'初始参考值 · 跟随默认')):(en?'Custom value':'自定义值');
     if(full)field.source.textContent=Object.hasOwn(measured,key)?(en?'Auto · rendered value':'自动 · 实际值'):(en?'Auto · canvas reference':'自动 · 按尺寸计算');
     if(inherit&&key==='point_size'&&Array.isArray(measured.point_size_range))field.source.textContent=(en?'Data-mapped size range: ':'数据映射范围：')+measured.point_size_range.map(v=>Number(v).toFixed(3)).join('–')+' mm';
     if(inherit&&key==='axis_line'&&measured.axis_line_details){const d=measured.axis_line_details;if(Number.isFinite(d.frame)&&Math.abs(d.frame-Number(value))>.001)field.source.textContent+=(en?' · frame ':' · 外框 ')+Number(d.frame.toFixed(4))+' pt';}
     field.reset.textContent=en?'Reset':'恢复默认';field.reset.hidden=full||inherit;
     field.reset.setAttribute('aria-label',(en?'Reset ':'恢复默认 · ')+FIGURE_APPEARANCE[key][en?1:0]);
   }
   row.fontHint.textContent=full?(en?'Canvas size and analysis thresholds are user-controlled. Fonts, lines, points, labels, legends, colors and resolution are automatic. Changes to size regenerate the figure; uncheck to restore manual settings.':'图宽高和分析阈值由用户指定；字号、线条、点径、标签、图例、配色及分辨率自动配置。修改尺寸后自动重新出图；取消勾选可恢复手动设置。'):(en?'Manual mode: edit appearance freely, then generate. Enable the checkbox to configure all appearance from the canvas size.':'手动模式：可自由修改绘图参数，再点击生成。勾选上方选项后，所有外观参数按图大小自动配置。');
   for(const button of row.fontButtons){
     const field=button.dataset.fontField,delta=Number(button.dataset.fontDelta),value=Number(row.inputs[field].input.value);
     const low=0;
     button.disabled=full||field==='minimum'||(delta<0?value+delta<=low:false);
     button.setAttribute('aria-label',(en?(delta<0?'Decrease ':'Increase '):(delta<0?'减小':'增大'))+(en?(field==='font'?'text size':'minimum text size'):(field==='font'?'基准字号':'最小字号')));
   }
   const size=options.export_size;
   const display=value=>Number(Number(value).toFixed(6));
   row.status.textContent=`${display(row.inputs.width.input.value)} × ${display(row.inputs.height.input.value)} ${unit}`+(unit!=='mm'?` ≈ ${size.width_mm} × ${size.height_mm} mm`:'')+` · ${options.publication.font_pt} pt`+(en?' · Saved for this figure type':' · 仅此图型，单独保存');
   for(const prefix of row.standard.prefixes||[]){for(const suffix of ['font-size','font']){const input=doc.getElementById(prefix+'-'+suffix);if(input){input.value=String(options.publication.font_pt);input.disabled=true;const group=input.closest('.form-group');if(group)group.hidden=true;}}}
   for(const prefix of row.standard.prefixes||[])for(const axis of ['width','height']){const input=doc.getElementById(prefix+'-'+axis);if(input){input.value=String(Number((size[axis+'_mm']/25.4).toFixed(8)));input.disabled=true;const group=input.closest('.form-group');if(group)group.hidden=true;}}
  }
 }
 doc.defaultView?.addEventListener('emp:figure-appearance',event=>{
  const {kind,signature,values}=event.detail||{};if(!FIGURE_STANDARDS[kind]||typeof signature!=='string'||!values||Array.isArray(values)||typeof values!=='object')return;
  let options;try{options=figureStandardOptions(kind,profileFor(kind));}catch{return;}if(signature!==figureAppearanceSignature(options))return;
  effective[kind]={signature,values};storage.setItem('emp_figure_effective_v1',JSON.stringify(effective));sync();
 });
 doc.defaultView?.addEventListener('emp:publication-change',sync);doc.defaultView?.addEventListener('emp:locale-change',sync);sync();
 return (path,body={})=>{
  const kind=figureKindForRequest(path,body);
  const figure_profiles=Object.fromEntries(Object.keys(FIGURE_STANDARDS).map(type=>{try{return [type,figureStandardOptions(type,profileFor(type))];}catch(error){if(type===kind)throw error;try{return [type,figureStandardOptions(type,saved[type]||{})];}catch{return [type,figureStandardOptions(type)];}}}));if(!kind)return {figure_profiles};
  const row=cards.get(kind);if(row)for(const {input}of Object.values(row.inputs))if(!input.reportValidity())throw Error('请检查当前图型的尺寸和字号。');
  return {...figureStandardOptions(kind,profileFor(kind)),figure_profiles};
 };
}
