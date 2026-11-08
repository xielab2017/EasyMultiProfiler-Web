// Dataset-scoped scientific review. A model cannot confirm biological independence.
export function reviewSampleDesign(samples, choice, subjects = {}) {
  if (!['independent', 'paired', 'unknown'].includes(choice)) throw Error('请选择样本关系 / Select the sample relationship.');
  if (!samples.length || new Set(samples.map(s => s.id)).size !== samples.length || samples.some(s => !s.id || !s.group)) throw Error('请先完成样本分组 / Complete the sample groups first.');
  const review = {relationship:choice, confirmed_by:'user', sample_count:samples.length, execution_allowed:false};
  if (choice === 'paired') {
    const mapping = samples.map(s => ({id:s.id, group:s.group, subject:String(subjects[s.id] || '').trim()}));
    if (mapping.some(s => !s.subject || s.subject.length > 256 || /[\x00-\x1f]/.test(s.subject))) throw Error('请为每个样本填写真实受试者/生物个体编号 / Enter a subject ID for every sample.');
    const units = new Map();
    for (const row of mapping) { const values = units.get(row.subject) || []; values.push(row); units.set(row.subject, values); }
    if (![...units.values()].some(rows => rows.length > 1)) throw Error('未发现重复的个体编号，无法建立配对关系 / No repeated subject IDs; pairing has not been established.');
    review.subjects = mapping; review.subject_count = units.size;
    review.incomplete_subjects = [...units.values()].filter(rows => new Set(rows.map(s => s.group)).size < new Set(samples.map(s => s.group)).size).length;
  }
  return review;
}

export function openSampleDesignDialog({samples, reference='', warnings=[], getRevision, onIndependent, onReview, locale=()=> 'zh', doc=document}) {
  const previous=doc.getElementById('wb-design-dialog');if(previous){previous.focus();return previous;}
  const revision=getRevision(), en=()=>!['zh','zh-TW'].includes(locale()), tx=(zh,eng)=>en()?eng:zh;
  const make=(tag,text)=>{const n=doc.createElement(tag);if(text)n.textContent=text;return n;};
  const dialog=make('dialog');dialog.id='wb-design-dialog';dialog.setAttribute('aria-labelledby','wb-design-title');
  const title=make('h3',tx('确认样本关系与分析设计','Confirm sample relationships and analysis design'));title.id='wb-design-title';
  const groups=[...new Set(samples.map(s=>s.group))], summary=make('p',groups.map(g=>`${g}: n=${samples.filter(s=>s.group===g).length}`).join(' · '));
  const label=(text,node)=>{const n=make('label',text);n.append(node);return n;};
  const select=(id,choices)=>{const n=make('select');n.id=id;for(const [value,text]of choices){const o=make('option',text);o.value=value;n.append(o);}return n;};
  const relationship=select('wb-design-relationship',[
    ['',tx('请选择，不自动推断','Select; never inferred automatically')],
    ['independent',tx('独立样本：每个样本来自不同生物个体','Independent: each sample is a separate biological unit')],
    ['paired',tx('配对 / 重复测量：同一个体有多个样本','Paired / repeated measures: multiple samples per subject')],
    ['unknown',tx('暂不确定，请 AI 协助核对论文证据','Unsure: ask AI to review the paper evidence')],
  ]);
  const note=make('p',tx('不能根据样本顺序、名称或组数判断配对关系。','Pairing cannot be inferred from sample order, names or group count.'));
  if(warnings.length)note.append(make('p',tx('候选分组尚未使用下列变化字段，请核对它们代表时间点、批次还是其他因素：','Candidate groups do not include these varying fields. Check whether they represent time points, batches or other factors: ')+warnings.map(w=>`${w.field}: ${w.values.join(' / ')} (${tx('缺失','missing')} ${w.missing})`).join('; ')));
  const mapping=make('div'),table=make('table'),header=make('tr'),subjectInputs=new Map();
  for(const text of [tx('样本','Sample'),tx('分组','Group'),tx('受试者 / 生物个体编号','Subject / biological unit ID')])header.append(make('th',text));table.append(header);
  for(const sample of samples){const tr=make('tr'),cell=make('td'),input=make('input');input.maxLength=256;input.setAttribute('aria-label',sample.id+tx(' 的个体编号',' subject ID'));subjectInputs.set(sample.id,input);cell.append(input);tr.append(make('td',sample.id),make('td',sample.group),cell);table.append(tr);}
  mapping.append(make('p',tx('同一个体的样本填写相同编号；不按行号自动配对。当前计数工作台仅支持独立样本；保存后 AI 会继续核对设计，不会按独立样本运行。','Use the same ID for samples from the same subject; rows are never paired by order. The count workbench currently supports independent samples only. Saving continues design review without running an independent-sample model.')),table);
  const ref=select('wb-design-reference',[['',tx('请选择参考组','Select the reference group')],...groups.map(g=>[g,g])]);if(groups.includes(reference))ref.value=reference;
  const mode=select('wb-design-comparisons',[
    ['one_to_many',tx('参考组分别与其他组比较','Reference versus each other group')],
    ['all_pairs',tx('所有组两两比较','All pairwise contrasts')],
  ]);
  const raw=make('input');raw.type='checkbox';raw.id='wb-design-raw-counts';
  const rawLabel=label('',raw);rawLabel.append(doc.createTextNode(tx('我已核对分组、比较方向和来源；矩阵为未经 log 或归一化的原始计数。','I reviewed groups, contrast direction and provenance; the matrix contains raw counts without log transformation or normalization.')));
  const batch=make('input');batch.type='checkbox';batch.id='wb-design-batch';
  const batchLabel=label('',batch);batchLabel.append(doc.createTextNode(tx('存在需要调整的批次或其他混杂因素','Batch or other confounders need adjustment')));
  const factors=make('input');factors.type='checkbox';factors.id='wb-design-factors-reviewed';
  const factorLabel=label('',factors);factorLabel.hidden=!warnings.length;factorLabel.append(doc.createTextNode(tx('已核对上述变化字段；当前分组完整保留本次需要比较的生物学条件。','I reviewed those fields; the current groups preserve all biological conditions for this comparison.')));
  const error=make('p');error.setAttribute('role','alert');
  const submit=make('button'),cancel=make('button',tx('暂不运行','Not now'));submit.type=cancel.type='button';submit.className='btn btn-primary';cancel.className='btn btn-outline';cancel.onclick=()=>dialog.close();
  const update=()=>{const independent=relationship.value==='independent';mapping.hidden=relationship.value!=='paired';ref.parentElement.hidden=mode.parentElement.hidden=rawLabel.hidden=!independent;submit.disabled=!relationship.value;submit.textContent=independent&&!batch.checked?tx('确认并开始分析','Confirm and start analysis'):tx('保存选择，继续核对设计','Save and continue design review');error.textContent='';};
  relationship.onchange=update;batch.onchange=update;
  submit.onclick=async()=>{
    if(getRevision()!==revision){error.textContent=tx('数据或流程已改变，请关闭后重新核对。','Data or workflow changed. Close and review the new design.');return;}
    submit.disabled=true;
    try {
      const review=reviewSampleDesign(samples,relationship.value,Object.fromEntries([...subjectInputs].map(([id,n])=>[id,n.value])));
      review.batch_adjustment=batch.checked;
      if(review.relationship==='independent'&&!batch.checked){
        if(warnings.length&&!factors.checked)throw Error(tx('请先核对变化字段与分组；不要把不同时间点静默合并。','Review the varying fields and grouping; do not silently merge time points.'));
        if(!ref.value)throw Error(tx('请选择参考组。','Select a reference group.'));
        if(!raw.checked)throw Error(tx('请核对原始计数来源后勾选确认。','Review and confirm raw-count provenance.'));
        await onIndependent({review,reference:ref.value,mode:mode.value});
      } else await onReview(review);
      dialog.close();
    }catch(e){error.textContent=e.message;submit.disabled=false;}
  };
  dialog.append(title,summary,label(tx('本次数据的样本关系','Sample relationship for these data'),relationship),note,mapping,label(tx('参考组','Reference group'),ref),label(tx('比较方式','Comparison mode'),mode),rawLabel,batchLabel,factorLabel,error,submit,cancel);
  dialog.addEventListener('close',()=>dialog.remove());doc.body.append(dialog);update();dialog.showModal();return dialog;
}
