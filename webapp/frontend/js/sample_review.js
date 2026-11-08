import {annotationFields,annotationRows,comparisonPairs,paperSummary,suggestGrouping} from './study_model.mjs';
import {getLocale} from './locale.js?v=nav-language-20261108';
const TEXT={
 title:['文章证据与样本分组','Paper evidence and sample grouping'],noPaper:['可关联 PDF / 论文证据；本地上传也可填写人工分组并记录来源。','Attach PDF/paper evidence, or enter manual groups with documented provenance for a local upload.'],
 field:['选择 GEO 原始特征字段作为分组候选','Choose an original GEO characteristic as candidate groups'],manual:['人工填写（不自动猜测）','Manual entry (no inferred assignments)'],apply:['按此字段填写候选分组','Fill candidate groups from this field'],
 evidence:['查看论文中的数据声明与实验设计','Inspect paper data statements and study design'],verified:['已逐样本核对矩阵列、GSM/元数据、分组及所附论文证据；未匹配项已人工处理','I reviewed every matrix column, GSM/metadata, group and attached paper evidence, and handled unmatched samples manually'],
 note:['仅使用精确样本匹配和您选择的原始字段；论文描述不直接转换为样本标签。未匹配或一个字段有多个值时，分组留空。','Only exact sample matches and your selected original field are used. Paper descriptions are not converted into sample labels. Unmatched or ambiguous field values remain blank.'],
 mode:['比较方式','Comparison mode'],one_to_one:['指定两组比较','One selected contrast'],one_to_many:['一个参考组与多个组比较','One reference versus multiple groups'],all_pairs:['所有组两两比较','All pairwise contrasts'],
 targets:['选择需要比较的实验组','Select test groups'],groups:['当前分组样本量','Current group sample sizes'],preview:['已选择的比较（正 log2FC = 实验组 / 参考组）','Selected contrasts (positive log2FC = test / reference)'],
 fit:['所有已选样本共同拟合 ~group 模型，再提取下列比较。BH FDR 在各比较内校正；不是跨全部比较的联合 FDR。','Fit all selected samples together using ~group, then extract the contrasts below. BH FDR is adjusted within each contrast, not jointly across all contrasts.'],
 pending:['请填齐真实分组，再选择参考组及比较方向。','Complete the actual groups, then select the reference and contrast directions.'],
 reviewRequired:['请先逐样本核对分组与证据并勾选确认。','Review each sample group and its evidence, then confirm the review.'],
};
const tr=key=>TEXT[key][['zh','zh-TW'].includes(getLocale())?0:1];
const make=(tag,text,cls)=>{const node=document.createElement(tag);if(text!==undefined)node.textContent=text;if(cls)node.className=cls;return node;};
export function mountSampleReview(root,{getSamples,onGroups,onChange}){
 let context=null;const selectedTargets=new Set();
 const heading=make('h4'),paper=make('div'),note=make('p',undefined,'hint'),fieldLabel=make('label'),fieldText=make('span'),field=make('select');field.id='wb-group-field';fieldLabel.append(fieldText,field);
 const apply=make('button',undefined,'btn btn-outline');apply.type='button';apply.id='wb-apply-groups';
 const checkedLabel=make('label'),checked=make('input'),checkedText=make('span');checked.type='checkbox';checked.id='wb-group-reviewed';checkedLabel.append(checked,checkedText);
 const modeLabel=make('label'),modeText=make('span'),mode=make('select');mode.id='wb-comparison-mode';for(const value of ['one_to_one','one_to_many','all_pairs']){const option=make('option');option.value=value;mode.append(option);}mode.value='one_to_one';modeLabel.append(modeText,mode);
 const counts=make('p',undefined,'wb-group-counts'),targets=make('div',undefined,'wb-targets'),preview=make('pre');preview.id='wb-comparison-preview';const fit=make('p',undefined,'hint');
 root.append(heading,paper,note,fieldLabel,apply,checkedLabel,modeLabel,counts,targets,preview,fit);
 const reference=()=>document.getElementById('wb-reference').value.trim();
 const samples=()=>getSamples();
 function renderPaper(){paper.replaceChildren();if(!context?.paper?.title&&!context?.paper?.doi){paper.append(make('p',tr('noPaper'),'hint'));return;}const value=context.paper;paper.append(make('strong',value.title||value.filename||''),make('p',[value.doi,value.pmid&&'PMID '+value.pmid].filter(Boolean).join(' · ')));
  if(value.evidence?.length){const details=make('details');details.append(make('summary',tr('evidence')));for(const row of value.evidence)details.append(make('p',`${row.page}: ${row.text}`));paper.append(details);}
 }
 function update(){
  const rows=samples(),groups=[...new Set(rows.map(row=>row.group).filter(Boolean))];
  for(const value of selectedTargets)if(!groups.includes(value)||value===reference())selectedTargets.delete(value);
  counts.textContent=tr('groups')+': '+groups.map(group=>`${group} (n=${rows.filter(row=>row.group===group).length})`).join(' · ');
  targets.replaceChildren();targets.hidden=mode.value!=='one_to_many';if(!targets.hidden){targets.append(make('strong',tr('targets')));for(const group of groups.filter(group=>group!==reference())){const label=make('label'),input=make('input');input.type='checkbox';input.dataset.testGroup=group;input.checked=selectedTargets.has(group);input.onchange=()=>{if(input.checked)selectedTargets.add(group);else selectedTargets.delete(group);onChange();updatePreview();};label.append(input,make('span',group));targets.append(label);}}
  const list=document.getElementById('wb-group-options');if(list){list.replaceChildren();for(const group of groups){const option=make('option');option.value=group;list.append(option);}}
  updatePreview();
 }
 function design(){const tests=mode.value==='one_to_many'?[...selectedTargets]:[document.getElementById('wb-test').value.trim()];const pairs=comparisonPairs(samples(),mode.value,reference(),tests);return{test:pairs[0].test,reference:pairs[0].reference,contrasts:pairs,independent_samples:document.getElementById('wb-independent').checked};}
 function updatePreview(){try{preview.textContent=tr('preview')+'\n'+design().contrasts.map((pair,index)=>`${index+1}. ${pair.test} / ${pair.reference}`).join('\n');}catch{preview.textContent=tr('pending');}}
 function render(){heading.textContent=tr('title');note.textContent=tr('note');fieldText.textContent=tr('field');apply.textContent=tr('apply');checkedText.textContent=tr('verified');modeText.textContent=tr('mode');fit.textContent=tr('fit');for(const option of mode.children)option.textContent=tr(option.value);
  const previous=field.value;field.replaceChildren();const manual=make('option',tr('manual'));manual.value='';field.append(manual);for(const item of annotationFields(context?.annotations?.records||[])){const option=make('option',`${item.name} (${item.samples}; ${item.values.length})`);option.value=item.name;field.append(option);}const suggestion=suggestGrouping(samples().map(r=>r.id),context?.annotations||{});if(suggestion?.keys.length>1){const option=make('option',suggestion.keys.join(' + ')+'（精确元数据候选）');option.value=suggestion.field;field.append(option);}field.value=previous;apply.disabled=!field.value;renderPaper();update();
 }
 field.onchange=()=>{checked.checked=false;apply.disabled=!field.value;onChange();};
 apply.onclick=()=>{checked.checked=false;const rows=annotationRows(samples().map(row=>row.id),context?.annotations||{},field.value);onGroups(rows);onChange();update();};
 checked.onchange=onChange;mode.onchange=()=>{onChange();update();};
 for(const id of ['wb-reference','wb-test'])document.getElementById(id).addEventListener('input',()=>{onChange();update();});
 window.addEventListener('emp:locale-change',render);render();
 return{update,design,autoFill(){const suggestion=suggestGrouping(samples().map(r=>r.id),context?.annotations||{});if(!suggestion)return null;if(![...field.options].some(o=>o.value===suggestion.field)){const option=make('option',suggestion.keys.join(' + ')+'（精确元数据候选）');option.value=suggestion.field;field.append(option);}field.value=suggestion.field;apply.disabled=false;onGroups(suggestion.rows);checked.checked=false;onChange();update();return suggestion;},invalidate(){checked.checked=false;update();},setContext(value){context=value;checked.checked=false;field.value='';render();},get context(){return context;},
  rows(ids){return annotationRows(ids,context?.annotations||{},field.value);},
  mapSample(id,gsm){
   const record=context?.annotations?.records.find(row=>row.accession===gsm);if(gsm&&!record)throw Error('Unknown GSM');
   const others=annotationRows(samples().map(row=>row.id).filter(value=>value!==id),context?.annotations||{},field.value);if(gsm&&others.some(row=>row.gsm===gsm))throw Error(['zh','zh-TW'].includes(getLocale())?'该 GSM 已对应其他矩阵列，请核对样本单位。':'This GSM already maps to another column; review analysis units.');
   if(!context?.annotations)return;context.annotations.matches=(context.annotations.matches||[]).filter(row=>row.column!==id);context.annotations.matches.push({column:id,status:'manual',confirmed:true,sample:record||null});checked.checked=false;onChange();
  },
  record(){if(!checked.checked)throw Error(tr('reviewRequired'));const values=samples(),evidence=annotationRows(values.map(row=>row.id),context?.annotations||{},field.value);return{confirmed:true,method:field.value&&evidence.every(row=>row.group&&row.group===values.find(sample=>sample.id===row.id)?.group)?'geo_characteristic':'manual',field:field.value,metadata_sha256:context?.annotations?.sha256||'',paper:context?.paper||paperSummary(),sample_rows:values.map(row=>{const found=evidence.find(item=>item.id===row.id);return{id:row.id,group:row.group,gsm:found.gsm,match:found.match,evidence:found.evidence.slice(0,1000)};})};}
 };
}
