const outputLabels={
  en:['Answer','Summary','Comparison table','Research note','Key points','Methodology','Limitations','Diagram'],
  zh:['回答','摘要','比较表','研究笔记','要点','研究方法','局限性','流程图'],
  'zh-TW':['回答','摘要','比較表','研究筆記','重點','研究方法','局限性','流程圖'],
  ja:['回答','要約','比較表','研究ノート','要点','研究方法','限界','図解'],
  ko:['답변','요약','비교표','연구 노트','핵심 요점','연구 방법','한계','흐름도'],
  ar:['إجابة','ملخص','جدول مقارنة','ملاحظة بحثية','النقاط الرئيسية','المنهجية','القيود','مخطط'],
  es:['Respuesta','Resumen','Tabla comparativa','Nota de investigación','Puntos clave','Metodología','Limitaciones','Diagrama'],
  fr:['Réponse','Résumé','Tableau comparatif','Note de recherche','Points clés','Méthode','Limites','Schéma'],
  de:['Antwort','Zusammenfassung','Vergleichstabelle','Forschungsnotiz','Kernaussagen','Methodik','Grenzen','Diagramm'],
  pt:['Resposta','Resumo','Tabela comparativa','Nota de pesquisa','Pontos principais','Metodologia','Limitações','Diagrama'],
  ru:['Ответ','Краткое содержание','Сравнительная таблица','Исследовательская заметка','Ключевые выводы','Методика','Ограничения','Схема'],
};
const outputTypes=['answer','summary','comparison','note','points','methods','limits','diagram'];
const readingStyles = {
  summary:'Lead with the main finding, then the evidence and most important uncertainty.',
  points:'Give a short prioritized list. Pair each finding with its supporting evidence or reported quantity.',
  methods:'Describe study design, inputs, groups, measurements and analysis. Mark unreported details.',
  limits:'Separate limitations reported by the authors from your assessment. Explain which conclusions each affects.',
  diagram:'Draw the supported workflow in a fenced emp-flow block, one short stage per line. Follow with evidence and uncertainties. Omit unsupported links.',
};
const quality='Lead with the result. Attribute claims to the supplied source, page or section when available. Mark missing evidence. Do not narrate internal reasoning.';
const make=(doc,tag,text,cls)=>{const n=doc.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;};
export function savedChatModels(config={},catalogs={},active={}){
  const rows=new Map();const add=(provider,model)=>{if(!provider||!model||['auto','mixed','fusion','__custom__'].includes(model))return;const id=JSON.stringify([provider,model]);rows.set(id,{id,provider,model,label:provider+' / '+model});};
  for(const [provider,p]of Object.entries(config.profiles||{})){
    if(!p.api_key&&!['custom','campus'].includes(provider))continue;
    add(provider,p.model);const catalog=catalogs[provider+(provider==='minimax'?':'+(p.region||'china'):'')];for(const model of (catalog?.models||[]).slice(0,80))add(provider,model.id);
  }
  add(active.provider,active.model);return [...rows.values()];
}
export function mountChatComposer(root,{question,agentLabel,actions,status,modelBridge,onChange,isEnglish=()=>false,getLanguage=()=>isEnglish()?'en':'zh',doc=globalThis.document}){
  const shell=make(doc,'div',undefined,'agent-composer'),top=make(doc,'div',undefined,'agent-composer-top'),picker=make(doc,'select'),attachments=make(doc,'div',undefined,'agent-attachments'),toolbar=make(doc,'div',undefined,'agent-composer-toolbar'),image=make(doc,'button','图片'),docButton=make(doc,'button','文档'),imageInput=make(doc,'input'),docInput=make(doc,'input'),hint=make(doc,'small','所选附件会随每条消息发给模型；移除即可停止附带。PDF 发送提取的文本。','agent-attachment-hint');
  picker.id='analysis-chat-model';picker.setAttribute('aria-label','选择对话模型');imageInput.type=docInput.type='file';imageInput.accept='image/png,image/jpeg,image/webp';docInput.accept='.pdf,.md,.txt,application/pdf,text/markdown,text/plain';imageInput.multiple=docInput.multiple=true;imageInput.hidden=docInput.hidden=true;image.type=docButton.type='button';image.className=docButton.className='agent-tool-button';image.id='analysis-attach-image';docButton.id='analysis-attach-document';imageInput.id='analysis-image-file';docInput.id='analysis-document-file';
  const effortLabel=make(doc,'label',undefined,'agent-thinking'),effortText=make(doc,'span'),effort=make(doc,'select'),effortNote=make(doc,'small',undefined,'agent-thinking-note');
  effort.id='analysis-reasoning-effort';effortLabel.append(effortText,effort);let activeModel={},efforts={},busy=false;try{efforts=JSON.parse(globalThis.localStorage?.getItem('emp_chat_effort_v1')||'{}');}catch{}
  const effortKey=()=>JSON.stringify([activeModel.provider,activeModel.model]);
  function renderEffort(){
    const en=isEnglish(),levels=activeModel.reasoning?.levels||['auto'],saved=efforts[effortKey()]||'auto';effortText.textContent=en?'Thinking depth':'思考深度';effort.setAttribute('aria-label',effortText.textContent);effort.replaceChildren();
    const names={auto:['模型默认','Model default'],low:['浅度','Low'],medium:['标准','Medium'],high:['深度','High'],xhigh:['更深入','Extra high'],max:['最高','Maximum']};
    for(const [value,labels]of Object.entries(names)){const budget=activeModel.reasoning?.budgets?.[value];const option=make(doc,'option',labels[en?1:0]+(budget?' · '+budget+' tokens':''));option.value=value;option.disabled=!levels.includes(value);effort.append(option);}
    effort.value=levels.includes(saved)?saved:'auto';effortNote.textContent=activeModel.reasoning?.supported?(en?'Higher depth may take longer and use more tokens.':'更高深度可能增加等待时间和 token 用量。'):(en?'This model has no documented depth control; using model default.':'当前模型未公布深度控制参数，使用模型默认。');
  }
  effort.onchange=()=>{efforts[effortKey()]=effort.value;try{globalThis.localStorage?.setItem('emp_chat_effort_v1',JSON.stringify(efforts));}catch{}};
  const outputLabel=make(doc,'label',undefined,'agent-output-type'),outputCaption=make(doc,'span'),output=make(doc,'select');
  output.id='analysis-output-type';
  for(const value of outputTypes){const option=make(doc,'option');option.value=value;output.append(option);}
  let preferredOutput='answer';
  try{const saved=globalThis.localStorage?.getItem('emp_chat_output_v1');if(outputTypes.includes(saved))preferredOutput=saved;}catch{}
  const supportsOutput=()=>activeModel.chat_contract_version===2;
  output.onchange=()=>{preferredOutput=output.value;try{globalThis.localStorage?.setItem('emp_chat_output_v1',preferredOutput);}catch{}labelReading();};
  function renderOutput(){
    const en=isEnglish(),legacy=activeModel.status==='ready'&&!supportsOutput();
    output.value=supportsOutput()?preferredOutput:'answer';output.disabled=busy||!supportsOutput();
    outputCaption.textContent=legacy?(en?'Output (update service)':'输出（需更新服务）'):(en?'Output':'输出类型');output.setAttribute('aria-label',outputCaption.textContent);
    labelReading();
    const names=outputLabels[getLanguage()]||outputLabels.en;
    for(const option of output.children)option.textContent=names[outputTypes.indexOf(option.value)];
  }
  outputLabel.append(outputCaption,output);
  const readingBar=make(doc,'div',undefined,'agent-reading-actions');
  const findPaper=make(doc,'button');findPaper.type='button';findPaper.className='agent-tool-button';findPaper.id='analysis-find-paper';
  findPaper.onclick=()=>{
    window.dispatchEvent(new CustomEvent('emp:navigate',{detail:{page:'matrix'}}));
    if(window.matchMedia('(max-width: 900px)').matches)doc.getElementById('code-lab-guide-collapse')?.click();
    doc.getElementById('discovery-input')?.focus();
  };
  for(const type of Object.keys(readingStyles)){
    const button=make(doc,'button');button.type='button';button.value=type;
    button.onclick=()=>{
      output.value=type;output.onchange();
      if(!question.value.trim()){
        question.value=isEnglish()?'Read the selected source. If it is missing, ask me to add it.':'请解读所选资料。如果还没有资料，请提示我添加。';
        question.oninput?.();resize();
      }
      question.focus?.();
    };readingBar.append(button);
  }
  function labelReading(){
    const names=outputLabels[getLanguage()]||outputLabels.en;
    settingsTitle.textContent=isEnglish()?'Model settings':'模型参数';
    findPaper.textContent=isEnglish()?'Find papers':'找论文';
    for(const button of readingBar.children){
      button.textContent=names[outputTypes.indexOf(button.value)];button.disabled=busy||!supportsOutput();
      button.setAttribute('aria-pressed',String(output.value===button.value));
    }
  }
  const settings=make(doc,'details',undefined,'agent-reading-settings'),settingsTitle=make(doc,'summary');
  settings.append(settingsTitle,effortLabel,effortNote);
  toolbar.append(findPaper);
  top.append(agentLabel,outputLabel,picker);toolbar.append(image,docButton,imageInput,docInput,actions);shell.append(top,attachments,readingBar,question,toolbar,settings,hint,status);root.append(shell);let queue=[],uploading=0,epoch=0;
  function render(){
    attachments.replaceChildren();
    for(const item of queue){
      const chip=make(doc,'div',undefined,'agent-attachment-chip');
      if(item.kind==='image'){
        const preview=make(doc,'img');preview.src=item.preview_url;preview.alt=item.name;chip.append(preview);
      }
      const details=[item.name];
      if(item.kind==='pdf')details.push(item.pages_inspected+(isEnglish()?' pages':' 页'));
      if(item.kind==='text'&&Number.isFinite(item.chars_inspected))details.push(item.chars_inspected+(isEnglish()?' characters':' 字符'));
      if(item.truncated)details.push(isEnglish()?'excerpt':'节选');
      chip.append(make(doc,'span',details.join(' · ')));
      const remove=make(doc,'button',isEnglish()?'Remove':'移除');remove.type='button';
      remove.onclick=()=>{queue=queue.filter(x=>x.id!==item.id);render();onChange?.();};
      chip.append(remove);attachments.append(chip);
    }
    hint.hidden=!queue.length;
  }
  async function addFiles(files){
    const generation=epoch;
    for(const file of files){if(generation!==epoch)break;if(queue.length+uploading>=6){status.textContent='每条消息最多 6 个附件。';break;}uploading++;
      try{
        const extension=file.name?.split('.').pop().toLowerCase();
        const mime=({pdf:'application/pdf',md:'text/markdown',txt:'text/plain'})[extension]||file.type;
        const limits={'application/pdf':100,'text/markdown':1,'text/plain':1,'image/png':5,'image/jpeg':5,'image/webp':5};
        if(!Object.hasOwn(limits,mime))throw Error(isEnglish()?'Choose a PNG, JPEG, WebP, PDF, Markdown, or TXT file.':'支持 PNG、JPEG、WebP、PDF、Markdown 和 TXT 文件。');
        if(file.size>limits[mime]*1024**2)throw Error((isEnglish()?'File size limit: ':'此格式文件上限为 ')+limits[mime]+' MiB');
        status.textContent=(isEnglish()?'Reading ':'正在读取附件：')+file.name;
        const response=await fetch('/api/public-data/agent/attachments',{method:'POST',headers:{'Content-Type':mime,'X-Attachment-Name':encodeURIComponent(file.name)},body:file,credentials:'omit',redirect:'error'});const item=await response.json();if(generation!==epoch)continue;if(!response.ok)throw Error(item.error||'附件读取失败');queue.push(item);status.textContent=item.warning||'附件已就绪；发送消息后交给模型。';render();onChange?.();
      }catch(error){if(generation===epoch)status.textContent=error.message;}finally{uploading--;}
    }
  }
  image.onclick=()=>imageInput.click();docButton.onclick=()=>docInput.click();for(const input of [imageInput,docInput])input.onchange=()=>{addFiles([...input.files]);input.value='';};
  question.addEventListener('paste',e=>{const files=[...(e.clipboardData?.items||[])].filter(x=>x.kind==='file'&&x.type.startsWith('image/')).map(x=>x.getAsFile()).filter(Boolean);if(files.length){e.preventDefault();addFiles(files);}});
  shell.addEventListener('dragover',e=>{if(e.dataTransfer?.types?.includes('Files'))e.preventDefault();});shell.addEventListener('drop',e=>{if(e.dataTransfer?.files?.length){e.preventDefault();addFiles([...e.dataTransfer.files]);}});
  picker.onchange=async()=>{if(!modelBridge)return;picker.disabled=true;try{await modelBridge.select(JSON.parse(picker.value));status.textContent='模型已切换。';}catch{status.textContent='模型切换失败，请检查“模型与 API”配置。';}finally{picker.disabled=false;}};
  const resize=()=>{if(question.style){question.style.height='auto';question.style.height=Math.max(60,Math.min(180,question.scrollHeight||60))+'px';}};question.addEventListener('input',resize);
  return {shell,addFiles,resize,outputType:()=>outputTypes.indexOf(output.value)>=4?'answer':output.value,
    outputInstruction:()=>[readingStyles[output.value],quality].filter(Boolean).join(' '),reasoningEffort:()=>effort.value||'auto',render(){renderEffort();renderOutput();image.textContent=isEnglish()?'Image':'图片';docButton.textContent=isEnglish()?'Document':'文档';docButton.title='PDF · Markdown · TXT';picker.setAttribute('aria-label',isEnglish()?'Select chat model':'选择对话模型');hint.textContent=isEnglish()?'Selected attachments accompany each message until removed. PDFs send extracted text.':'所选附件会随每条消息发给模型；移除即可停止附带。PDF 发送提取的文本。';render();},hasAttachments:()=>queue.length>0,isUploading:()=>uploading>0,take(){return [...queue];},restore(items){queue=[...new Map([...items,...queue].map(item=>[item.id,item])).values()].slice(0,6);render();},clear(){epoch++;queue=[];status.textContent='';render();},refreshModels(active={}){activeModel=active;renderEffort();renderOutput();picker.replaceChildren();const models=modelBridge?.list(active)||[];if(!models.length){const option=make(doc,'option','请先加载模型');option.value='';picker.append(option);}for(const row of models){const option=make(doc,'option',row.label);option.value=row.id;picker.append(option);if(row.model===active.model&&(row.provider===active.provider||row.provider==='chatgpt'&&active.provider==='openai'))picker.value=row.id;}},setBusy(value){busy=value;labelReading();output.disabled=busy||!supportsOutput();picker.disabled=value;effort.disabled=value;}};
}
