import {WORKFLOW_LIBRARY,WorkflowComposer,dependencies,textPair} from './workflow_library.mjs';
import {getLocale} from './locale.js?v=i18n-zh-default-v1';
const words={required:['必需 · 锁定','Required · locked'],optional:['可选','Optional'],conditional:['依赖所需','Required dependency'],
 count:['工作台可执行','Workbench execution'],gate:['必需审核 / 交付','Review / delivery gate'],page:['需在已有页面执行','Use existing analysis page'],planning:['仅编排 · 未连接执行','Planning only · execution not connected'],
 omics:['组学类型','Omics type'],type:['输入类型（需核对）','Input type (verify)'],preset:['流程模板','Workflow template'],minimal:['最小必需流程','Required steps only'],exploratory:['探索性分析','Exploratory analysis'],differential:['差异 / 比较分析','Differential / comparative analysis'],
 library:['步骤库：按需加入','Step library: add as needed'],selected:['已加入','Selected'],add:['加入','Add'],remove:['删除','Remove'],up:['上移','Move up'],down:['下移','Move down'],open:['打开对应页面','Open analysis page'],deps:['前置步骤','Prerequisites'],
 valid:['流程结构通过；数据、设计和运行能力仍须审核。','Workflow structure passes; data, design and execution capabilities still need review.'],invalid:['请补齐依赖或修正顺序 / 输入类型。','Resolve dependencies, order or input-type conflicts.'],locked:['必需步骤不能删除。','Required steps cannot be removed.'],consumers:['请先删除依赖此步骤的后续分析。','Remove dependent analyses first.'],order:['此排序不满足前置依赖；已保留原顺序。','This order breaks prerequisites; the previous order was retained.'],
 applied:['已套用模板；请重新审核输入与参数。','Template applied; review inputs and parameters again.'],auto:['所需前置步骤会自动加入；没有执行分析。','Required prerequisites are added automatically; no analysis is executed.'],template:['套用模板','Apply template'],label:['流程名称（可选）','Workflow name (optional)'],
};
const tr=key=>textPair(words[key],getLocale());
const parameters={alpha:['FDR 阈值','FDR threshold'],min_count:['最低计数','Minimum count'],min_samples:['满足计数阈值的样本数','Samples meeting count threshold'],components:['主成分数','PCA components'],top_n:['展示基因数','Genes to show']};
const inputNames={raw_counts:['原始计数（raw counts）','Raw counts'],tpm:['TPM','TPM'],fpkm:['FPKM','FPKM'],normalized:['已归一化数据','Normalized data'],intensity:['强度 / 丰度','Intensity / abundance'],spectral_counts:['谱图计数','Spectral counts'],taxon_counts:['分类单元计数','Taxon counts'],relative_abundance:['相对丰度','Relative abundance'],functional_counts:['功能计数','Functional counts'],peaks:['峰集合（peaks）','Peak sets'],bam:['比对文件（BAM）','Alignment files (BAM)'],clinical_table:['临床表型表','Clinical phenotype table'],multiple_assays:['多份组学矩阵','Multiple omics matrices']};
const errors={schema:['不支持的流程格式','Unsupported workflow format'],input_type:['不支持的输入类型','Unsupported input type'],steps:['步骤列表无效','Invalid step list'],operation:['未知或重复步骤','Unknown or duplicate step'],dependency:['缺少前置步骤或顺序错误','Missing or out-of-order prerequisite'],type:['输入类型不兼容','Incompatible input type'],terminal:['结果导出应在流程最后','Result export must be last'],parameters:['参数不符合步骤要求','Parameters do not match the step'],parameter_value:['参数超出范围或类型错误','Parameter out of range or wrong type'],required:['缺少必需步骤','Missing required step']};
const make=(tag,text,cls)=>{const el=document.createElement(tag);if(text!==undefined)el.textContent=text;if(cls)el.className=cls;return el;};

export function mountWorkflowDesigner({onChange,onNavigate}){
  const get=id=>document.getElementById('wb-'+id);const setting=get('designer-settings');const libraryArea=get('step-library');
  const drafts={};let composer=new WorkflowComposer();
  try{const saved=JSON.parse(localStorage.getItem('emp_workflow_blueprints_v1'));if(saved&&typeof saved==='object')Object.assign(drafts,saved);if(drafts.bulk_rnaseq)composer.load(drafts.bulk_rnaseq);}catch{}
  const selects={};
  for(const [id,key]of [['scope','omics'],['input-type','type'],['preset','preset']]){const label=make('label');const span=make('span');span.dataset.designerLabel=key;const select=make('select');select.id='wb-'+id;label.append(span,select);setting.append(label);selects[id]=select;}
  const status=get('graph-status');const steps=get('steps');
  function name(op){return textPair(composer.library.steps[op].label,getLocale());}
  function persist(){drafts[composer.scope]=composer.blueprint();try{localStorage.setItem('emp_workflow_blueprints_v1',JSON.stringify(drafts));}catch{}}
  function changed(){persist();onChange(composer);render();}
  function notify(outcome){if(!outcome.ok){status.textContent=tr(outcome.code==='required'?'locked':outcome.code==='dependency'?'consumers':'order');return false;}return true;}
  function render(){
    for(const el of setting.querySelectorAll('[data-designer-label]'))el.textContent=tr(el.dataset.designerLabel);
    const selectedPreset=selects.preset.value||'differential';selects.scope.replaceChildren();
    for(const [id,entry]of Object.entries(WORKFLOW_LIBRARY)){const option=make('option',textPair(entry.label,getLocale()));option.value=id;selects.scope.append(option);}selects.scope.value=composer.scope;
    selects['input-type'].replaceChildren();for(const type of composer.library.inputTypes){const option=make('option',textPair(inputNames[type],getLocale()));option.value=type;selects['input-type'].append(option);}selects['input-type'].value=composer.inputType;
    selects.preset.replaceChildren();for(const key of Object.keys(composer.library.presets)){const option=make('option',tr(key));option.value=key;selects.preset.append(option);}selects.preset.value=selectedPreset;
    get('template').textContent=tr('template');get('add').textContent=tr('add');get('operation').replaceChildren();libraryArea.replaceChildren(make('h4',tr('library')),make('p',tr('auto'),'hint'));
    const cards=make('div',undefined,'wb-library-grid');
    for(const [op,def]of Object.entries(composer.library.steps)){
      const chosen=composer.steps.some(s=>s.operation===op);const option=make('option',name(op));option.value=op;option.disabled=chosen;get('operation').append(option);
      const conditional=chosen&&composer.requiredBy(op).length;const card=make('div',undefined,'wb-library-step');card.append(make('strong',name(op)),make('span',tr(def.required?'required':conditional?'conditional':'optional'),'wb-step-badge '+(def.required?'is-required':conditional?'is-conditional':'is-optional')),make('small',tr(def.mode),'wb-capability'));
      const button=make('button',tr(chosen?'selected':'add'),'btn btn-outline');button.type='button';button.disabled=chosen;button.dataset.operation=op;button.onclick=()=>{composer.add(op);changed();};card.append(button);cards.append(card);
    }
    libraryArea.append(cards);steps.replaceChildren();
    composer.steps.forEach((node,i)=>{
      const def=composer.library.steps[node.operation];const consumers=composer.requiredBy(node.operation);const li=make('li');li.draggable=!def.terminal;li.dataset.operation=node.operation;
      li.append(make('strong',name(node.operation)),make('span',tr(def.required?'required':consumers.length?'conditional':'optional'),'wb-step-badge '+(def.required?'is-required':consumers.length?'is-conditional':'is-optional')),make('small',tr(def.mode),'wb-capability'));
      const deps=dependencies(composer.scope,node.operation,composer.inputType);if(deps.length)li.append(make('p',tr('deps')+': '+deps.map(name).join(' → '),'hint'));
      if(def.note)li.append(make('p',textPair(def.note,getLocale()),'hint'));
      const params=make('div',undefined,'wb-params');
      for(const [key,spec]of Object.entries(def.parameters)){const label=make('label',parameters[key]?textPair(parameters[key],getLocale()):key);const input=make(spec.type==='choice'?'select':'input');input.setAttribute('aria-label',name(node.operation)+' '+(parameters[key]?textPair(parameters[key],getLocale()):key));
        if(spec.type==='choice')for(const choice of spec.options){const option=make('option',choice);option.value=choice;input.append(option);}
        else{input.type='number';input.min=spec.min;input.max=spec.max;input.step=spec.step;}
        input.value=node.parameters[key];input.oninput=()=>{node.parameters[key]=spec.type==='choice'?input.value:Number(input.value);persist();onChange(composer);renderStatus();};label.append(input);params.append(label);
      }li.append(params);
      const actions=make('div',undefined,'wb-actions');
      for(const [key,action,disabled]of [['up',()=>composer.move(i,i-1),i===0],['down',()=>composer.move(i,i+1),i===composer.steps.length-1],['remove',()=>composer.remove(node.operation),def.required]]){
        const button=make('button',tr(key),'btn btn-outline');button.type='button';button.disabled=disabled;button.dataset.stepAction=key;button.onclick=()=>{if(notify(action()))changed();};actions.append(button);
      }
      if(def.mode==='page'){const button=make('button',tr('open'),'btn btn-outline');button.type='button';button.onclick=()=>onNavigate(composer.scope,def);actions.append(button);}
      li.append(actions);li.ondragstart=e=>e.dataTransfer.setData('text/plain',String(i));li.ondragover=e=>e.preventDefault();li.ondrop=e=>{e.preventDefault();if(notify(composer.move(Number(e.dataTransfer.getData('text/plain')),i)))changed();};steps.append(li);
    });renderStatus();
  }
  function renderStatus(){const checked=composer.status();status.textContent=tr(checked.valid?'valid':'invalid');if(checked.nativeExecutable&&checked.deferred.length)status.textContent+=' '+(['zh','zh-TW'].includes(getLocale())?`本次可先执行 ${composer.connectedCountSteps().length} 个计数步骤，另有 ${checked.deferred.length} 个待继续步骤。`:`Run ${composer.connectedCountSteps().length} connected count steps first; ${checked.deferred.length} steps remain deferred.`);status.dataset.valid=String(checked.valid);if(!checked.valid){const list=make('ul');for(const error of checked.errors)list.append(make('li',[textPair(errors[error.code],getLocale()),error.operation&&name(error.operation),error.dependency&&name(error.dependency)].filter(Boolean).join(' · ')));status.append(list);}}
  selects.scope.onchange=()=>{persist();const scope=selects.scope.value;composer=new WorkflowComposer(scope);try{if(drafts[scope])composer.load(drafts[scope]);}catch{}changed();};
  selects['input-type'].onchange=()=>{composer.inputType=selects['input-type'].value;composer.reconcile();changed();};
  get('template').onclick=()=>{composer.preset(selects.preset.value);changed();};
  get('add').onclick=()=>{composer.add(get('operation').value);changed();};
  window.addEventListener('emp:locale-change',render);render();
  return {get composer(){return composer;},render,applyBlueprint(value){composer.load(value);changed();},switchScope(scope){if(scope!==composer.scope){persist();composer=new WorkflowComposer(scope);changed();}},
    applyCountProposal(value){composer=new WorkflowComposer('bulk_rnaseq');composer.preset('minimal');for(const item of value.steps){if(!composer.library.steps[item.operation]?.engine)throw Error('operation');composer.add(item.operation);const node=composer.steps.find(s=>s.operation===item.operation);node.parameters={...node.parameters,...item.parameters};}changed();}};
}
