const make=(doc,tag,text,cls)=>{const n=doc.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;};
export function savedChatModels(config={},catalogs={},active={}){
  const rows=new Map();const add=(provider,model)=>{if(!provider||!model||['auto','mixed','fusion','__custom__'].includes(model))return;const id=JSON.stringify([provider,model]);rows.set(id,{id,provider,model,label:provider+' / '+model});};
  for(const [provider,p]of Object.entries(config.profiles||{})){
    if(!p.api_key&&!['custom','campus'].includes(provider))continue;
    add(provider,p.model);const catalog=catalogs[provider+(provider==='minimax'?':'+(p.region||'china'):'')];for(const model of (catalog?.models||[]).slice(0,80))add(provider,model.id);
  }
  add(active.provider,active.model);return [...rows.values()];
}
export function mountChatComposer(root,{question,agentLabel,actions,status,modelBridge,onChange,isEnglish=()=>false,doc=globalThis.document}){
  const shell=make(doc,'div',undefined,'agent-composer'),top=make(doc,'div',undefined,'agent-composer-top'),picker=make(doc,'select'),attachments=make(doc,'div',undefined,'agent-attachments'),toolbar=make(doc,'div',undefined,'agent-composer-toolbar'),image=make(doc,'button','图片'),pdf=make(doc,'button','PDF'),imageInput=make(doc,'input'),pdfInput=make(doc,'input'),hint=make(doc,'small','发送时将附件交给所选模型；PDF 提取文本，不做 OCR。','agent-attachment-hint');
  picker.id='analysis-chat-model';picker.setAttribute('aria-label','选择对话模型');imageInput.type=pdfInput.type='file';imageInput.accept='image/png,image/jpeg,image/webp';pdfInput.accept='application/pdf,.pdf';imageInput.multiple=pdfInput.multiple=true;imageInput.hidden=pdfInput.hidden=true;image.type=pdf.type='button';image.className=pdf.className='agent-tool-button';image.id='analysis-attach-image';pdf.id='analysis-attach-pdf';imageInput.id='analysis-image-file';pdfInput.id='analysis-pdf-file';
  const effortLabel=make(doc,'label',undefined,'agent-thinking'),effortText=make(doc,'span'),effort=make(doc,'select'),effortNote=make(doc,'small',undefined,'agent-thinking-note');
  effort.id='analysis-reasoning-effort';effortLabel.append(effortText,effort);let activeModel={},efforts={};try{efforts=JSON.parse(globalThis.localStorage?.getItem('emp_chat_effort_v1')||'{}');}catch{}
  const effortKey=()=>JSON.stringify([activeModel.provider,activeModel.model]);
  function renderEffort(){
    const en=isEnglish(),levels=activeModel.reasoning?.levels||['auto'],saved=efforts[effortKey()]||'auto';effortText.textContent=en?'Thinking depth':'思考深度';effort.setAttribute('aria-label',effortText.textContent);effort.replaceChildren();
    const names={auto:['模型默认','Model default'],low:['浅度','Low'],medium:['标准','Medium'],high:['深度','High'],xhigh:['更深入','Extra high'],max:['最高','Maximum']};
    for(const [value,labels]of Object.entries(names)){const budget=activeModel.reasoning?.budgets?.[value];const option=make(doc,'option',labels[en?1:0]+(budget?' · '+budget+' tokens':''));option.value=value;option.disabled=!levels.includes(value);effort.append(option);}
    effort.value=levels.includes(saved)?saved:'auto';effortNote.textContent=activeModel.reasoning?.supported?(en?'Higher depth may take longer and use more tokens.':'更高深度可能增加等待时间和 token 用量。'):(en?'This model has no documented depth control; using model default.':'当前模型未公布深度控制参数，使用模型默认。');
  }
  effort.onchange=()=>{efforts[effortKey()]=effort.value;try{globalThis.localStorage?.setItem('emp_chat_effort_v1',JSON.stringify(efforts));}catch{}};
  top.append(agentLabel,picker,effortLabel);shell.append(effortNote);toolbar.append(image,pdf,imageInput,pdfInput,actions);shell.append(top,attachments,question,toolbar,hint,status);root.append(shell);let queue=[],uploading=0,epoch=0;
  const render=()=>{attachments.replaceChildren();for(const item of queue){const chip=make(doc,'div',undefined,'agent-attachment-chip');if(item.kind==='image'){const preview=make(doc,'img');preview.src=item.preview_url;preview.alt=item.name;chip.append(preview);}chip.append(make(doc,'span',item.name+(item.kind==='pdf'?' · '+item.pages_inspected+(isEnglish()?' pages':' 页')+(item.truncated?(isEnglish()?' · excerpt':' · 文本节选'):''):'')));const remove=make(doc,'button',isEnglish()?'Remove':'移除');remove.type='button';remove.onclick=()=>{queue=queue.filter(x=>x.id!==item.id);render();onChange?.();};chip.append(remove);attachments.append(chip);}hint.hidden=!queue.length;};
  async function addFiles(files){
    const generation=epoch;
    for(const file of files){if(generation!==epoch)break;if(queue.length+uploading>=6){status.textContent='每条消息最多 6 个附件。';break;}uploading++;
      try{if(!['image/png','image/jpeg','image/webp','application/pdf'].includes(file.type)&&!file.name?.toLowerCase().endsWith('.pdf'))throw Error('支持 PNG、JPEG、WebP 和 PDF。');
        if(file.size>(file.type==='application/pdf'||file.name?.toLowerCase().endsWith('.pdf')?100:5)*1024**2)throw Error('图片上限 5 MiB；PDF 上限 100 MiB。');
        status.textContent='正在读取附件：'+file.name;
        const response=await fetch('/api/public-data/agent/attachments',{method:'POST',headers:{'Content-Type':file.type||'application/pdf','X-Attachment-Name':encodeURIComponent(file.name)},body:file,credentials:'omit',redirect:'error'});const item=await response.json();if(generation!==epoch)continue;if(!response.ok)throw Error(item.error||'附件读取失败');queue.push(item);status.textContent=item.warning||'附件已就绪；发送消息后交给模型。';render();onChange?.();
      }catch(error){if(generation===epoch)status.textContent=error.message;}finally{uploading--;}
    }
  }
  image.onclick=()=>imageInput.click();pdf.onclick=()=>pdfInput.click();for(const input of [imageInput,pdfInput])input.onchange=()=>{addFiles([...input.files]);input.value='';};
  question.addEventListener('paste',e=>{const files=[...(e.clipboardData?.items||[])].filter(x=>x.kind==='file'&&x.type.startsWith('image/')).map(x=>x.getAsFile()).filter(Boolean);if(files.length){e.preventDefault();addFiles(files);}});
  shell.addEventListener('dragover',e=>{if(e.dataTransfer?.types?.includes('Files'))e.preventDefault();});shell.addEventListener('drop',e=>{if(e.dataTransfer?.files?.length){e.preventDefault();addFiles([...e.dataTransfer.files]);}});
  picker.onchange=async()=>{if(!modelBridge)return;picker.disabled=true;try{await modelBridge.select(JSON.parse(picker.value));status.textContent='模型已切换。';}catch{status.textContent='模型切换失败，请检查“模型与 API”配置。';}finally{picker.disabled=false;}};
  const resize=()=>{if(question.style){question.style.height='auto';question.style.height=Math.max(60,Math.min(180,question.scrollHeight||60))+'px';}};question.addEventListener('input',resize);
  return {shell,addFiles,resize,reasoningEffort:()=>effort.value||'auto',render(){renderEffort();image.textContent=isEnglish()?'Image':'图片';picker.setAttribute('aria-label',isEnglish()?'Select chat model':'选择对话模型');hint.textContent=isEnglish()?'Attachments are sent to the selected model when you send. PDFs use extracted text; no OCR.':'发送时将附件交给所选模型；PDF 提取文本，不做 OCR。';render();},hasAttachments:()=>queue.length>0,isUploading:()=>uploading>0,take(){return [...queue];},restore(items){queue=[...new Map([...items,...queue].map(item=>[item.id,item])).values()].slice(0,6);render();},clear(){epoch++;queue=[];status.textContent='';render();},refreshModels(active={}){activeModel=active;renderEffort();picker.replaceChildren();const models=modelBridge?.list(active)||[];if(!models.length){const option=make(doc,'option','请先加载模型');option.value='';picker.append(option);}for(const row of models){const option=make(doc,'option',row.label);option.value=row.id;picker.append(option);if(row.model===active.model&&(row.provider===active.provider||row.provider==='chatgpt'&&active.provider==='openai'))picker.value=row.id;}},setBusy(value){picker.disabled=value;effort.disabled=value;}};
}
