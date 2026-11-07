import {getLocale} from './locale.js?v=i18n-zh-default-v1';
const tx=(zh,en)=>['zh','zh-TW'].includes(getLocale())?zh:en;
export function mountSimpleWorkbench({onStart,describe,isNative}){
 const page=document.getElementById('page-workbench'),get=id=>document.getElementById('wb-'+id);
 const make=(tag,cls)=>{const node=document.createElement(tag);if(cls)node.className=cls;return node;};page.classList.add('wb-simple');
 const shell=make('div','wb-simple-shell'),data=get('count-inputs'),designer=page.querySelector('.wb-designer-card'),editor=get('steps').closest('.card'),assistant=get('question').closest('.card'),tasks=get('analysis-job').closest('.card'),external=get('external-data');
 const dataStage=make('section','card wb-simple-data'),flowStage=make('section','card wb-simple-flow'),startStage=make('section','card wb-simple-start'),dataTitle=make('h3'),flowTitle=make('h3'),startTitle=make('h3');
 const dataHeading=data.querySelector('h3');if(dataHeading)dataHeading.hidden=true;data.classList.remove('card');designer.querySelector('h3').hidden=true;designer.classList.remove('card');
 dataStage.append(dataTitle,data,external);flowStage.append(flowTitle,designer);const flowSummary=make('p');flowSummary.id='wb-simple-flow-summary';flowStage.append(flowSummary);
 const ai=make('button','btn btn-outline');ai.type='button';flowStage.append(ai);
 const review=make('div','wb-simple-summary'),consentLabel=make('label'),consent=make('input'),consentText=make('span'),start=make('button','btn btn-primary');consent.type='checkbox';consent.id='wb-simple-consent';start.id='wb-simple-start';start.type='button';consentLabel.append(consent,consentText);startStage.append(startTitle,review,consentLabel,start,get('status'));
 const advanced=make('details','wb-simple-advanced card'),advancedTitle=make('summary'),aiPanel=make('details','wb-simple-ai card'),aiTitle=make('summary');advanced.append(advancedTitle,editor,get('runtime'));aiPanel.append(aiTitle,assistant);shell.append(dataStage,flowStage,startStage,aiPanel,advanced,tasks);
 const first=page.querySelector('.card');first.after(shell);const oldGrid=page.querySelector('.wb-grid');if(oldGrid)oldGrid.hidden=true;
 for(const child of first.querySelectorAll('p.hint'))child.hidden=true;
 const columns=make('details'),columnTitle=make('summary');columns.id='wb-simple-columns';columns.append(columnTitle,get('columns'),get('select'));data.append(columns);
 const sampleDetails=make('details'),sampleTitle=make('summary');sampleDetails.id='wb-simple-samples';sampleDetails.open=true;sampleDetails.append(sampleTitle,get('samples'));data.append(sampleDetails);
 const legacyGroup=get('group-reviewed')?.closest('label'),legacyIndependent=get('independent')?.closest('label');if(legacyGroup)legacyGroup.hidden=true;if(legacyIndependent)legacyIndependent.hidden=true;
 get('template').hidden=true;get('preset').addEventListener('change',()=>get('template').click());
 consent.onchange=()=>{get('group-reviewed').checked=consent.checked;get('independent').checked=consent.checked;};
 start.onclick=()=>onStart();ai.onclick=()=>{aiPanel.open=true;get('question').focus();};
 function labels(){dataTitle.textContent=tx('1. 导入数据与分组','1. Import data and groups');flowTitle.textContent=tx('2. 选择分析流程','2. Choose a workflow');startTitle.textContent=tx('3. 开始分析','3. Start analysis');advancedTitle.textContent=tx('高级设置：步骤、参数、随机种子与检查记录','Advanced: steps, parameters, random seed and validation records');aiTitle.textContent=tx('AI 帮我选择或调整流程','Ask AI to choose or adjust the workflow');ai.textContent=tx('让 AI 帮我选流程','Ask AI about this workflow');columnTitle.textContent=tx('数据列设置（自动排除已识别的注释列）','Column settings (recognized annotation columns excluded)');sampleTitle.textContent=tx('样本分组与对应表','Sample groups and mapping');consentText.textContent=tx('我已核对分组、比较方向和数据来源；本次为独立样本原始计数，无需批次或配对调整。','I reviewed groups, contrast directions and provenance. These are independent raw-count samples requiring no batch or paired-design adjustment.');update();}
 function update(){const native=isNative(),summary=describe();consentLabel.hidden=!native;start.textContent=native?tx('开始分析','Start analysis'):tx('进入所选组学分析','Continue to selected omics analysis');flowSummary.textContent=summary.steps||'';review.replaceChildren();for(const line of summary.lines||[]){const p=make('p');p.textContent=line;review.append(p);}sampleDetails.hidden=!get('samples').children.length;}
 window.addEventListener('emp:locale-change',labels);labels();
 return {update,invalidate(){consent.checked=false;update();},reviewed:()=>consent.checked,focus(id){const el=get(id);const details=el?.closest('details');if(details)details.open=true;el?.scrollIntoView({behavior:'smooth',block:'center'});el?.focus();}};
}
