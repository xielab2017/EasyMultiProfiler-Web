// Declarative local guidance. Presence of UI selections is not scientific QC.
const ROWS = {
  matrix: {title:['数据发现与下载','Data discovery and download'],goal:['从文章与数据库证据定位处理矩阵，核对来源后下载。','Locate processed matrices from article and repository evidence.'],checks:[['区分原始测序文件与处理矩阵；下载后检查数值尺度和样本映射。','Separate raw reads from processed matrices and inspect scales and sample alignment.']],steps:[['定位数据来源','Locate sources'],['核对文件并下载','Review and download files'],['检查矩阵与样本信息','Inspect matrix and metadata']],target:'discovery-input'},
  integration: {title:['多研究与多组学整合','Multi-study integration'],goal:['核对各数据块的组学类型、尺度与样本对应，再选择整合方法。','Review modality, scale and sample alignment before integration.'],checks:[['不同研究不默认具有配对样本；不能直接拼接不同尺度的矩阵。','Do not assume paired samples across studies or concatenate incompatible scales.']],steps:[['登记数据块与来源','Register blocks and sources'],['检查样本对应与设计','Review alignment and design'],['选择并验证整合方案','Select and validate integration']],target:'rp-project'},
  workbench: {title:['数据驱动的流程编排','Data-guided workflow'],goal:['依据上传矩阵的检查摘要生成可编辑流程，明确待核对项。','Build editable steps from matrix inspection and identify missing information.'],checks:[['整数只说明数值兼容计数；原始计数来源、分组、批次和配对仍需证据。','Integers do not establish raw-count provenance, groups, batches or pairing.']],steps:[['识别矩阵结构与尺度','Inspect matrix structure and scale'],['核对样本设计','Review sample design'],['生成并检查步骤草案','Build and review draft steps']],target:'wb-file'},
  three_line: {
    title: ['临床基线三线表', 'Clinical baseline table'],
    goal: ['描述各组的基线特征，并核对变量类型、缺失和比较方法。', 'Describe baseline characteristics by group; review variable types, missingness and comparison methods.'],
    checks: [
      ['每行对应一个受试者或明确的分析单位；重复测量需另行设计。', 'Each row represents a participant or a declared analysis unit; repeated measures need a separate design.'],
      ['确认分组列、分类/连续变量及缺失值处理，不从列名猜测。', 'Verify the grouping column, categorical/continuous types and missing-data policy; do not infer them from names.'],
      ['审核比较方法和多重比较；基线差异不能证明因果关系。', 'Review comparison methods and multiplicity; baseline differences do not establish causality.'],
    ],
    steps: [['核对受试者与分组', 'Review participants and groups'], ['审核变量、缺失与比较设置', 'Review variables, missingness and comparisons'], ['在临床页生成并检查三线表', 'Generate and inspect the table on the Clinical page'], ['导出表格与方法说明', 'Export the table and methods']],
    target: 'clin-three-group',
  },
  clinical: {
    title: ['临床表型分析', 'Clinical phenotype analysis'],
    goal: ['先明确分析单位和科学问题，再选择描述、关联或预测分析。', 'Define the analysis unit and scientific question before descriptive, association or prediction analysis.'],
    checks: [
      ['核对样本对应、变量类型、缺失与潜在混杂因素。', 'Review sample alignment, variable types, missingness and potential confounders.'],
      ['相关不等于因果；预测任务还需分离训练、验证与测试。', 'Association is not causation; prediction also needs separate training, validation and testing.'],
      ['按当前子步骤核对统计假设与分析单位，不把不同模型互相替代。', 'Review assumptions and units for the selected step; distinct models are not interchangeable.'],
    ],
    steps: [['检查临床表结构', 'Inspect the clinical table'], ['审核当前子步骤参数', 'Review the selected analysis settings'], ['在临床页执行并检查结果', 'Run on the Clinical page and inspect results']],
    target: 'clin-analysis-strategy',
  },
  preparation: {
    title: ['数据准备', 'Data preparation'],
    goal: ['记录数据尺度和缺失机制，再选择过滤与归一化。', 'Document the data scale and missingness before choosing filtering and normalization.'],
    checks: [
      ['保留原始数据；明确每一步排除或变换的对象。', 'Preserve raw inputs and record exclusions and transformations.'],
      ['先确认 raw counts、丰度或强度类型；不要对 DESeq2 输入提前做 log 变换。', 'Verify raw counts, abundance or intensity type; do not log-transform DESeq2 inputs beforehand.'],
    ],
    steps: [['检查数据类型与缺失', 'Check data type and missingness'], ['审核准备参数', 'Review preparation parameters'], ['比较处理前后 QC', 'Compare QC before and after preparation']], target: 'prep-mode',
  },
  analysis: {
    title: ['统计分析', 'Statistical analysis'],
    goal: ['明确数据类型、比较方向、设计与重复，再选择统计方法。', 'Define data type, contrast direction, design and replication before choosing a method.'],
    checks: [
      ['核对实际数据、分组、独立生物学重复及批次/配对结构。', 'Review actual data, groups, independent biological replicates and batch/pairing structure.'],
      ['审核效应量、不确定性和多重检验，避免只按 P 值下结论。', 'Review effects, uncertainty and multiple testing; do not interpret P values alone.'],
    ],
    steps: [['核对数据与设计', 'Review data and design'], ['审核方法及参数', 'Review method and parameters'], ['运行后检查诊断与结果', 'Inspect diagnostics and results after execution']], target: null,
  },
  visualization: {
    title: ['结果可视化', 'Result visualization'],
    goal: ['先确认图所使用的数据和比较，再调整呈现。', 'Verify the plotted data and comparison before changing presentation.'],
    checks: [
      ['图值必须对应真实结果；标注变换、单位、样本数与阈值。', 'Match plotted values to actual results; label transforms, units, sample counts and thresholds.'],
      ['图形呈现不能替代统计检验或证明因果关系。', 'Visualization does not replace statistical tests or establish causality.'],
    ],
    steps: [['确认图形来源', 'Verify plot inputs'], ['审核分组、单位和阈值', 'Review groups, units and thresholds'], ['导出可编辑图与图例', 'Export editable figures and legends']], target: null,
  },
  runall: {
    title: ['整合分析流程', 'Integrated analysis workflow'],
    goal: ['把研究问题转成有输入、参数和输出的明确步骤，再审核执行。', 'Turn the research question into explicit inputs, parameters and outputs, then review execution.'],
    checks: [
      ['核对每一步输入类型与依赖；不能用一个模板覆盖所有组学。', 'Check input types and dependencies; a single template cannot cover all omics.'],
      ['逐项审核分组、比较、过滤与富集物种，保留运行记录。', 'Review groups, contrasts, filtering and enrichment organism, and retain run records.'],
    ],
    steps: [['审核输入与比较', 'Review inputs and contrasts'], ['检查步骤依赖与参数', 'Review dependencies and parameters'], ['确认后执行并保存运行记录', 'Confirm execution and retain the run record']], target: 'ra-pipeline',
  },
};

export function guideFor(context = {}, locale = 'zh') {
  const language = locale === 'zh' || locale === 'zh-TW' ? 0 : 1;
  const workflow = ['clinical','preparation','analysis','visualization','runall','matrix','integration','workbench'].includes(context.workflow) ? context.workflow : 'analysis';
  const row = workflow === 'clinical' && context.tab === 'three_line' ? ROWS.three_line : ROWS[workflow]||ROWS.analysis;
  const clinical = workflow === 'clinical';
  const hasData = clinical ? !!(context.hasExperiment || context.hasStandaloneClinical) : !!context.hasExperiment;
  const needsGroup = clinical && ['three_line','systematic'].includes(context.tab);
  const requirements = [{id:'data', present:hasData, text:clinical
    ? ['选择临床数据来源，并核对实际表结构。','Select a clinical data source and review its actual table structure.'][language]
    : ['选择实验，并核对实际输入类型与 QC。','Select an experiment and review the actual input type and QC.'][language]}];
  if(needsGroup) requirements.push({id:'group',present:!!context.hasGroup,text:['选择分组列，并核对组别含义与分析单位。','Select a grouping column and review its meaning and analysis units.'][language]});
  return {workflow, tab:typeof context.tab==='string'?context.tab:'', title:row.title[language], goal:row.goal[language],
    requirements, checks:row.checks.map(pair=>pair[language]), steps:row.steps.map((pair,i)=>({id:`review${i+1}`,label:pair[language],status:'needs_review'})),
    inputSelectionComplete:requirements.every(r=>r.present), executable:false, analysisExecuted:false, target:row.target,
    countWorkflowAvailable:!clinical && (context.omics==='transcriptomics' || context.tab==='runall-rnaseq'),
    mode:'local_guidance'};
}

export function modelQuestion(question, context = {}) {
  if(typeof question!=='string'||!question.trim()||question.length>3500)throw Error('question');
  const workflow=/^[a-z_]{1,30}$/.test(context.workflow||'')?context.workflow:'analysis';
  const step=typeof context.tab==='string'&&/^[A-Za-z0-9_-]{1,64}$/.test(context.tab)?context.tab:'unspecified';
  if(context.plotSettings&&step==='viz-heatmap')question+='\nCurrent heatmap settings: '+JSON.stringify(Object.fromEntries(Object.entries(context.plotSettings).filter(([key,value])=>['width_inches','height_inches','top_n'].includes(key)&&typeof value==='number'&&Number.isFinite(value))));
  let message=`UI scope: ${workflow}; registered step: ${step}.\nQuestion: ${question.trim()}`;
  if(context.locale)message+='\nRespond in '+(['zh','zh-TW'].includes(context.locale)?'Chinese':'the selected UI language ('+context.locale+')')+'.';
  const cap=3700;
  if(context.completedUi?.length){const log=JSON.stringify(context.completedUi.slice(-5));if(message.length+log.length+100<=cap)message+='\nAlready completed local actions (do not repeat; proceed to the next requested action): '+log;}
  if(context.pageContext){
    const input=context.pageContext,p={page:workflow};
    if(context.availableAction)p.submit_current=context.availableAction;
    if(input.experiment)p.experiment=input.experiment;
    p.navigation={differential:'analysis:ana-diff',PCA:'analysis:ana-dim',volcano:'visualization:viz-volcano',heatmap:'visualization:viz-heatmap',ordination:'visualization:viz-scatter',GO_KEGG:'visualization:viz-enrichment-dotplot'};
    if(input.workbench&&['workbench','matrix'].includes(workflow)){const w=input.workbench;p.readiness={active_input:workflow==='workbench',input:w.has_input,dataset:w.has_dataset,groups:w.group_count,unassigned:w.unassigned,design_review:w.needs_design_review,relationship:w.sample_relationship,pairing:w.pairing_review,grouping_warnings:w.grouping_warnings};if(w.accession)p.accession=w.accession;}
    if(input.profile)p.matrix={features:input.profile.feature_count,samples:input.profile.candidate_sample_columns,count_compatible:input.profile.count_compatible,negative:input.profile.negative_cells,missing:input.profile.missing_or_nonfinite_cells};
    const append=()=>{const json=JSON.stringify(p);return message.length+json.length+23<=cap;};
    if(!append()){delete p.matrix;}
    if(append()){
      const controls=[];for(const f of input.fields||[]){const row={id:f.id,type:f.type,value:String(f.value||'').slice(0,80),options:f.options?.slice(0,12)};controls.push(row);p.fields=controls;if(!append()){controls.pop();break;}}
      if(!controls.length)delete p.fields;
      if(input.workbench?.steps){p.selected_steps=input.workbench.steps;if(!append())delete p.selected_steps;}
      if(input.files?.length){p.files=input.files.slice(0,5);if(!append())delete p.files;}
      p.status=(input.statuses||[]).map(x=>String(x).slice(0,160)).slice(-1);if(!append())delete p.status;
      if(input.headings?.length){p.headings=input.headings.slice(0,3);if(!append())delete p.headings;}
      message+='\nCurrent page controls: '+JSON.stringify(p);
    }
  }
  if(context.memory){const memory=JSON.stringify(context.memory);if(memory.length<700&&message.length+memory.length+50<=cap)message+='\nPreferences only, never scientific evidence: '+memory;}
  return message;
}
