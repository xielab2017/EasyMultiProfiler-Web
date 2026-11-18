import {validateBlueprint} from './workflow_library.mjs';

const templateFormat = 'emp-rnaseq-template-v1';
const isZh = locale => ['zh', 'zh-TW'].includes(locale);
const el = (tag, text) => {
  const node = document.createElement(tag);
  if (text !== undefined) node.textContent = text;
  return node;
};

export function makeTemplate(blueprint, seed) {
  if (blueprint?.scope !== 'bulk_rnaseq' || blueprint.input_type !== 'raw_counts' ||
      !validateBlueprint(blueprint).valid || !Number.isInteger(seed) || seed < 1 || seed > 2147483647)
    throw Error('Invalid RNA-seq workflow or seed');
  // Only operations and registered settings travel to the next study.
  const steps = blueprint.steps.map(({operation, parameters}) => ({id: operation, operation, parameters: {...parameters}}));
  return {format: templateFormat, blueprint: {...blueprint, steps}, seed};
}

export function readTemplate(value) {
  if (value?.format !== templateFormat || Object.keys(value).some(key => !['format','blueprint','seed'].includes(key)))
    throw Error('Expected an EMP RNA-seq template');
  return makeTemplate(value.blueprint, value.seed);
}

const questions = {
  input: ['请导入原始计数矩阵，并确认哪些列对应生物样本。', 'Which matrix contains the raw counts, and which columns are biological samples?', 'wb-upload'],
  evidence: ['哪份作者说明或资料证实这是未经归一化的计数？', 'Which author statement or source establishes that these are unnormalized counts?', 'wb-evidence'],
  groups: ['每个样本来自哪个组？请核对样本与分组的对应关系。', 'Which group does each sample belong to? Review the sample mapping.', 'wb-simple-samples'],
  contrast: ['哪个是参考组？希望与哪些实验组比较？', 'Which group is the reference, and which groups should be compared?', 'wb-reference'],
  independence: ['样本是否相互独立？有无配对、重复测量或批次？', 'Are samples independent, paired, repeated or affected by batch?', 'wb-simple-consent'],
};

export function pendingQuestions(context) {
  const missing = [];
  if (!context.hasDataset) missing.push('input');
  if (!context.hasEvidence) missing.push('evidence');
  if (!context.groupsReviewed) missing.push('groups');
  if (context.differential && !context.hasContrast) missing.push('contrast');
  if (context.differential && !context.independent) missing.push('independence');
  return missing;
}

export function designSummary(context, locale) {
  const t=(zh,en)=>isZh(locale)?zh:en;
  const rows=context.samples || [], comparisons=context.contrasts || [];
  if (!rows.length) return [];
  const groups=new Map();
  for (const row of rows) if (row.group) groups.set(row.group,(groups.get(row.group)||0)+1);
  const missing=rows.filter(row=>!row.group).length;
  const counts=[...groups].map(([name,n])=>name+' (n='+n+')');
  if(missing) counts.push(t('待分组','Unassigned')+' (n='+missing+')');
  const lines=[t('本次输入','Input')+' · '+rows.length+' '+t('个样本','samples')+' · '+counts.join(', ')];
  if(context.differential) {
    if(!context.groupsReviewed) lines.push(t('样本分组待核对。','Sample group assignments await review.'));
    for(const {test,reference} of comparisons) lines.push(t('实验组','Test')+' '+test+' / '+t('参考组','reference')+' '+reference+' · '+t('正 log2FC 表示实验组表达更高。','Positive log2FC means higher expression in the test group.'));
  }
  return lines;
}

export function directionRows(de) {
  const edge = de.method === 'edgeR', up=[],down=[];
  for(const row of de.rows || []) {
    const fdr=edge?row.FDR:row.padj, fold=edge?row.logFC:row.log2FoldChange;
    if(!Number.isFinite(fdr)||!Number.isFinite(fold)||!(fdr<de.alpha)||fold===0) continue;
    (fold>0?up:down).push({gene:row.feature_id,fold,fdr});
  }
  for (const rows of [up,down]) rows.sort((a,b)=>a.fdr-b.fdr||Math.abs(b.fold)-Math.abs(a.fold));
  return {up,down};
}

export function clarification(reason, locale) {
  const messages = {
    analysis_goal: ['想先看质控、PCA、差异表达，还是高变基因热图？请在问题中写明目标。','Which analysis do you want: QC, PCA, differential expression or a high-variance heatmap? Add it to your request.'],
    explicit_steps: ['请列出本次希望保留的步骤，例如“质控和 PCA”。','List the steps to include, for example “QC and PCA”.'],
    unconnected_steps: ['该请求涉及其他分析页面。请在步骤库中选择相应分析，并明确这次需要运行哪些计数步骤。','This request includes steps on other analysis pages. Choose them in the step library and specify which count steps to run here.'],
    parameters: ['请为每个步骤指定一个有效参数，例如“差异分析 FDR 0.05”或“热图前 20 个基因”。','Please specify one valid value per step, for example “differential expression FDR 0.05” or “heatmap top 20 genes”.'],
  };
  return (messages[reason] || messages.analysis_goal)[isZh(locale) ? 0 : 1];
}

function linkToControl(id, label) {
  const link = el('a', label);
  link.href = '#' + id;
  link.onclick = event => {
    event.preventDefault();
    const control = document.getElementById(id);
    if (!control) return;
    for (let parent=control; parent; parent=parent.parentElement) if (parent.tagName === 'DETAILS') parent.open = true;
    control.scrollIntoView({block:'center'});
    if (!control.matches('input, textarea, button, select, a, summary')) control.tabIndex = -1;
    control.focus({preventScroll:true});
  };
  return link;
}

export function mountPlanReview({composer, seed, context, locale, apply, save, notice}) {
  const t = (zh,en) => isZh(locale()) ? zh : en;
  const area = el('div'), templates = el('div'), file = el('input');
  const exportButton = el('button'), importButton = el('button');
  templates.className = 'wb-actions';
  for (const b of [exportButton, importButton]) { b.type = 'button'; b.className = 'btn btn-outline'; }
  file.type = 'file'; file.accept = '.json,application/json'; file.hidden = true;
  templates.id = 'wb-rnaseq-templates'; area.id = 'wb-plan-questions';
  const requestPanel=el('details'), title=el('summary');
  requestPanel.id='wb-rnaseq-request';
  requestPanel.append(title,document.getElementById('wb-question'),document.getElementById('wb-propose'),document.getElementById('wb-answer'),area);
  document.getElementById('wb-designer-settings').after(requestPanel,templates);
  templates.append(exportButton, importButton, file);
  let reviewing = false;
  function update() {
    const workflow = composer();
    templates.hidden = workflow.scope !== 'bulk_rnaseq' || workflow.inputType !== 'raw_counts';
    requestPanel.hidden=templates.hidden;
    title.textContent=t('用自然语言生成 RNA-seq 计划','Draft an RNA-seq plan from a request');
    area.replaceChildren();
    exportButton.textContent = t('导出 RNA-seq 参数模板','Export RNA-seq parameter template');
    importButton.textContent = t('套用 RNA-seq 参数模板','Apply RNA-seq parameter template');
    if (!reviewing || templates.hidden) return;
    if (!workflow.status().nativeExecutable) {
      area.append(el('p',t('请在高级设置中检查步骤的顺序和参数。','Check step order and parameters in Advanced settings.')));
      return;
    }
    const design=context();
    for(const line of designSummary(design,locale())) area.append(el('p',line));
    const line=el('p');
    for(const s of workflow.connectedCountSteps()) {
      const params = Object.entries(s.parameters).map(([k,v])=>k+'='+v).join(', ');
      const label=workflow.library.steps[s.operation].label[isZh(locale())?0:1]+(params?' ('+params+')':'');
      if(line.childNodes.length) line.append(' → ');
      line.append(linkToControl('wb-step-parameters-'+s.operation,label));
    }
    area.append(line);
    const missing = pendingQuestions(design);
    if (missing.length) {
      const list = el('ul');
      for (const key of missing) {
        const [zh,en,id] = questions[key], item = el('li');
        item.append(linkToControl(id,t(zh,en))); list.append(item);
      }
      area.append(list);
    } else area.append(el('p',t('资料已填写，请在开始分析前核对本次计划。','Inputs are complete. Review the plan before starting.')));
  }
  exportButton.onclick = () => {
    try { save(makeTemplate(composer().blueprint(), seed()), 'emp-rnaseq-template.json'); }
    catch { notice(t('请先修正步骤、参数或随机种子。','Check the steps, parameters and seed first.')); }
  };
  importButton.onclick = () => file.click();
  file.onchange = async () => {
    const selected = file.files[0]; file.value = '';
    if (!selected) return;
    try {
      if (selected.size > 65536) throw Error();
      const template = readTemplate(JSON.parse(await selected.text()));
      if (composer().scope !== 'bulk_rnaseq' || context().incompatible) {
        notice(t('当前输入需要原始 bulk RNA-seq 计数矩阵。','This template requires a raw bulk RNA-seq count matrix.')); return;
      }
      apply(template); reviewing = true; update();
      notice(t('参数模板已载入。请核对本次矩阵、样本分组和设计。','Parameters loaded. Review this matrix, its sample groups and design.'));
    } catch { notice(t('模板格式、步骤或参数无效（JSON 上限 64 KiB）。','Invalid template format, steps or parameters (64 KiB JSON limit).')); }
  };
  return {update, show(){reviewing=true;requestPanel.open=true;update();}, reset(){reviewing=false;update();}};
}

export function resultEvidence(value) {
  const plan = value.plan || {}, env = value.environment || {}, qc = value.artifacts?.qc || {};
  return {
    data: {source:plan.source, source_sha256:plan.source_sha256, input_sha256:plan.input_sha256 || qc.input_sha256,
      features:qc.feature_count, samples:plan.samples, excluded_columns:plan.excluded_columns,
      raw_counts_evidence:plan.raw_counts_evidence, grouping_review:plan.grouping_review},
    parameters: {plan_sha256:value.plan_sha256, seed:plan.seed, design:plan.design, steps:plan.steps,
      deferred_steps:plan.deferred_steps},
    software: {web_version:env.web_version, r_version:env.r_version, packages:env.packages, session_info:value.session_info},
  };
}

export function appendResultEvidence(root, result, locale, selectedContrast=0) {
  const t = (zh,en) => isZh(locale) ? zh : en;
  const evidence = resultEvidence(result), section = el('section'), links = el('p');
  section.id = 'wb-result-evidence';
  section.append(el('h4',t('结果证据与复现记录','Result evidence and provenance')),links);
  const labels = {data:t('输入数据与分组','Input data and groups'),parameters:t('执行参数和比较方向','Parameters and contrasts'),software:t('运行时软件版本','Software at execution')};
  for (const [key, record] of Object.entries(evidence)) {
    const details = el('details'), id = 'wb-evidence-'+key;
    details.id=id;
    details.append(el('summary',labels[key]));
    const rows = Object.entries(record);
    for (const [name, val] of rows) {
      const missing = val == null;
      const field = el('p'); field.append(el('strong',name));
      details.append(field);
      if (!missing && name === 'source' && typeof val === 'string' && /^https:\/\//i.test(val)) {
        const url = el('a',val); url.href=val; url.target='_blank'; url.rel='noreferrer noopener'; details.append(url);
      } else {
        const content=el('pre',missing?t('该任务未记录','Not recorded for this job'):typeof val==='string'?val:JSON.stringify(val,null,2));
        content.className='wb-pre'; details.append(content);
      }
    }
    section.append(details);
    if (links.childNodes.length) links.append(' · ');
    links.append(linkToControl(id, labels[key]));
  }
  for (const [id, label] of [['wb-result-qc','QC'],['wb-result-pca','PCA'],['wb-result-heatmap',t('热图','Heatmap')],['wb-result-differential',t('差异结果','Differential results')]]) {
    if (document.getElementById(id)) links.append(' · ',linkToControl(id,label));
  }
  const de=result.artifacts?.differentials?.[selectedContrast] || result.artifacts?.differential;
  if (de) {
    const directions=directionRows(de);
    for(const [key,rows] of Object.entries(directions)) {
      const name=key==='up'?t('上调基因','Upregulated genes'):t('下调基因','Downregulated genes');
      const label=name+' ('+rows.length+')', id='wb-evidence-'+key, details=el('details');
      links.append(' · ',linkToControl(id,label));
      details.id=id;details.append(el('summary',label+' · '+de.test+' / '+de.reference+' · '+de.method));
      details.append(el('p','BH FDR < '+de.alpha+' · log2FC '+(key==='up'?'> 0':'< 0')));
      if(rows.length){
        const table=el('table'), thead=el('thead'), tr=el('tr'), body=el('tbody');
        for(const column of ['feature_id','log2FC','BH FDR']) tr.append(el('th',column));
        thead.append(tr); table.append(thead,body);details.append(table);
        const prev=el('button',t('上一页','Previous')), next=el('button',t('下一页','Next')), range=el('span');
        for(const button of [prev,next]){button.type='button';button.className='btn btn-outline';}
        let start=0;
        function draw(){
          body.replaceChildren();
          const end=Math.min(start+20,rows.length);
          for(const row of rows.slice(start,end)){
            const tr=el('tr');
            for(const value of [row.gene,row.fold,row.fdr])tr.append(el('td',String(value)));
            body.append(tr);
          }
          prev.disabled=start===0;next.disabled=end===rows.length;range.textContent=' '+(start+1)+'–'+end+' / '+rows.length+' ';
        }
        prev.onclick=()=>{start-=20;draw();};next.onclick=()=>{start+=20;draw();};
        if(rows.length>20) details.append(prev,range,next);
        draw();
      }else details.append(el('p',t('此比较中没有满足上述条件的基因。','No genes meet these criteria in this contrast.')));
      section.append(details);
    }
  }
  root.append(section);
}
