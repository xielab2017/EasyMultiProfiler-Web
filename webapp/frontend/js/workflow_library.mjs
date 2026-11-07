// Scientific review gates and registered UI routes, not a claim of execution.
export const LIBRARY_VERSION='emp-workflow-editor-v1';
const copy=x=>JSON.parse(JSON.stringify(x));
const number=(value,min,max,step=1)=>({value,min,max,step,type:'number'});
const choice=(value,options)=>({value,options,type:'choice'});
const step=(zh,en,deps=[],options={})=>({label:[zh,en],deps,required:false,mode:'page',page:'analysis',tab:null,parameters:{},...options});
const common=()=>({
  data_input:step('导入数据与记录来源','Import data and provenance',[],{required:true,mode:'gate',page:'import',note:['保留原文件、数据尺度与来源。','Preserve original inputs, data scale and provenance.']}),
  sample_metadata:step('核对样本与实验设计','Review samples and design',['data_input'],{required:true,mode:'gate',page:'import',note:['明确分析单位、样本对应、分组、独立重复及批次/配对结构。','Declare analysis units, sample alignment, groups, independent replication and batch/pairing structure.']}),
  qc:step('质量检查','Quality checks',['sample_metadata'],{required:true,mode:'gate',page:'summary',note:['必须核对输入质量；预检本身不执行 QC。','Review input quality; structural validation does not execute QC.']}),
  export:step('导出结果与复现记录','Export results and reproducibility',['qc'],{required:true,mode:'gate',page:'export',terminal:true}),
});
const rna={...common(),
  qc:step('计数质量检查','Count QC',['sample_metadata'],{required:true,mode:'count',engine:'qc',page:'summary'}),
  normalize:step('Size-factor 归一化','Size-factor normalization',['qc'],{mode:'count',engine:'normalize',accepts:['raw_counts'],produces:'normalized_counts',note:['用于探索图；DESeq2 差异分析自行估计 size factors。','For exploratory plots; DESeq2 differential analysis estimates its own size factors.']}),
  pca:step('PCA','PCA',['normalize'],{mode:'count',engine:'pca',parameters:{components:number(2,1,10)}}),
  deseq2:step('DESeq2 差异分析','DESeq2 differential analysis',['qc'],{mode:'count',engine:'deseq2',accepts:['raw_counts'],parameters:{alpha:number(.05,.001,.999,.01),min_count:number(10,1,1000000),min_samples:number(2,1,256)}}),
  edger:step('edgeR 多组差异分析','edgeR multi-group differential analysis',['qc'],{mode:'count',engine:'edger',accepts:['raw_counts'],parameters:{alpha:number(.05,.001,.999,.01),min_count:number(10,1,1000000),min_samples:number(2,1,256)},note:['TMM 归一化与准似然 F 检验；全部组共同拟合，再提取已审核比较。','TMM normalization and quasi-likelihood F-tests; fit all groups together, then extract reviewed contrasts.']}),
  heatmap:step('高变基因热图','High-variance gene heatmap',['normalize'],{mode:'count',engine:'heatmap',parameters:{top_n:number(50,1,500)}}),
  volcano:step('差异火山图','Differential volcano plot',['deseq2'],{page:'visualization',tab:'viz-volcano'}),
  enrichment:step('GO / KEGG 富集','GO / KEGG enrichment',['deseq2'],{tab:'ana-enrich',note:['需明确物种、ID 映射及背景基因集。','Specify organism, ID mapping and the background gene set.']}),
  wgcna:step('WGCNA 共表达分析','WGCNA coexpression analysis',['qc'],{tab:'ana-wgcna',mode:'planning',note:['需要独立审核样本量、变换与混杂；未连接本编排器执行。','Review sample adequacy, transforms and confounding; no execution adapter in this builder.']}),
};
const abundance=(kind)=>({...common(),
  filter:step('特征过滤','Feature filtering',['qc'],{page:'preparation',tab:'prep-filter'}),
  impute:step('缺失值处理（按机制选用）','Missing-data handling (mechanism dependent)',['qc'],{page:'preparation',tab:'prep-impute',note:['可选，不能静默填补；先评估缺失机制并记录处理决定。','Optional; assess missingness and record the decision. Never impute silently.']}),
  normalize:step('尺度与归一化审核','Scale and normalization review',['qc'],{page:'preparation',tab:'prep-normalize'}),
  pca:step('PCA / 样本结构','PCA / sample structure',['normalize'],{tab:'ana-dim'}),
  differential:step(kind==='protein'?'蛋白差异分析':'代谢物差异分析',kind==='protein'?'Protein differential analysis':'Metabolite differential analysis',['normalize'],{tab:'ana-diff'}),
  heatmap:step('丰度热图','Abundance heatmap',['normalize'],{page:'visualization',tab:'viz-heatmap'}),
  volcano:step('差异火山图','Differential volcano plot',['differential'],{page:'visualization',tab:'viz-volcano'}),
  enrichment:step('通路富集','Pathway enrichment',['differential'],{tab:'ana-enrich',note:['先确认可用的特征 ID、映射资源和统计背景。','Verify feature IDs, mapping resources and statistical background.']}),
});
const microbiome={...common(),
  filter:step('检出率与低丰度过滤','Prevalence / abundance filtering',['qc'],{page:'preparation',tab:'prep-filter'}),
  taxonomy:step('分类层级汇总','Taxonomy aggregation',['qc'],{page:'preparation',tab:'prep-collapse'}),
  normalize:step('组成型数据变换审核','Compositional transformation review',['qc'],{page:'preparation',tab:'prep-normalize'}),
  rarefy:step('稀释抽样（按目的选用）','Rarefaction (purpose dependent)',['qc'],{page:'preparation',tab:'prep-rarefy',accepts:['taxon_counts'],note:['可选；不作为全部 16S 分析的强制前置步骤。','Optional; not a universal prerequisite for 16S analysis.']}),
  alpha:step('Alpha 多样性','Alpha diversity',['qc'],{tab:'ana-alpha',accepts:['taxon_counts']}),
  beta:step('Beta 多样性 / 排序','Beta diversity / ordination',['normalize'],{tab:'ana-dim'}),
  differential:step('差异丰度','Differential abundance',['normalize'],{tab:'ana-diff'}),
  composition:step('群落组成图','Community composition',['qc'],{page:'visualization',tab:'viz-structure'}),
  network:step('关联网络（探索性）','Association network (exploratory)',['normalize'],{tab:'ana-network',mode:'planning'}),
};
const metagenomics={...common(),
  filter:step('功能特征过滤','Functional feature filtering',['qc'],{page:'preparation',tab:'prep-filter'}),
  normalize:step('功能矩阵归一化审核','Functional matrix normalization review',['qc'],{page:'preparation',tab:'prep-normalize'}),
  differential:step('功能差异分析','Functional differential analysis',['normalize'],{tab:'ana-diff'}),
  enrichment:step('功能 / 通路富集','Functional / pathway enrichment',['differential'],{tab:'ana-enrich'}),
  heatmap:step('功能热图','Functional heatmap',['normalize'],{page:'visualization',tab:'viz-heatmap'}),
  network:step('跨组学关联','Cross-omics associations',['normalize'],{mode:'planning'}),
};
const chip={...common(),
  reference:step('核对物种与基因组版本','Verify organism and genome build',['data_input'],{required:true,page:'chipseq',mode:'gate'}),
  qc:step('峰 / 比对质量检查','Peak / alignment QC',['sample_metadata','reference'],{required:true,page:'chipseq',mode:'gate'}),
  peak_call:step('MACS 调峰（BAM 输入）','MACS peak calling (BAM input)',['qc'],{page:'chipseq',accepts:['bam'],produces:'peaks'}),
  annotation:step('峰注释 / TSS 关联','Peak annotation / TSS association',['qc'],{page:'chipseq',accepts:['peaks']}),
  motif:step('Motif 分析','Motif analysis',['qc'],{page:'chipseq',accepts:['peaks']}),
  differential_binding:step('差异结合（重复设计审核）','Differential binding (review replication)',['qc'],{page:'chipseq',accepts:['peaks'],note:['需要额外的样本、重复与 BAM / 共识峰设计，编排不证明可运行。','Needs an additional sample/replicate and BAM/consensus-peak design; a plan does not establish runnability.']}),
  joint:step('ChIP × RNA 联合分析','ChIP × RNA analysis',['annotation'],{page:'chipseq'}),
};
const clinical={...common(),
  three_line:step('基线三线表','Baseline table',['qc'],{page:'clinical',tab:'three_line'}),
  systematic:step('系统临床统计','Systematic clinical statistics',['qc'],{page:'clinical',tab:'systematic'}),
  correlation:step('表型关联分析','Phenotype associations',['qc'],{page:'clinical',tab:'cor'}),
  prediction_review:step('预测设计与数据泄漏审核','Prediction design / leakage review',['qc'],{mode:'planning',note:['先分离训练、验证、测试；调参时需合适的嵌套验证。','Separate training, validation and testing; use appropriate nested validation for tuning.']}),
  prediction:step('预测模型（待连接执行）','Prediction model (execution not connected)',['prediction_review'],{mode:'planning'}),
};
const joint={...common(),
  align:step('跨组学样本对应审核','Cross-omics sample alignment',['sample_metadata'],{required:true,mode:'gate'}),
  qc:step('分组学 QC 与尺度审核','Per-omics QC / scale review',['align'],{required:true,mode:'gate'}),
  differential:step('分组学差异结果准备','Prepare per-omics differential results',['qc'],{mode:'planning'}),
  correlation:step('跨组学关联（探索性）','Cross-omics associations (exploratory)',['qc'],{mode:'planning'}),
  joint:step('联合分析 / 特征整合','Joint analysis / feature integration',['qc'],{mode:'planning'}),
  pathway:step('跨组学通路解释','Cross-omics pathway interpretation',['differential'],{mode:'planning'}),
};
export const WORKFLOW_LIBRARY={
  bulk_rnaseq:{label:['转录组 · bulk RNA-seq','Transcriptomics · bulk RNA-seq'],inputTypes:['raw_counts','tpm','fpkm','normalized'],defaultType:'raw_counts',page:'import',omics:'transcriptomics',steps:rna,presets:{minimal:['data_input','sample_metadata','qc','export'],exploratory:['data_input','sample_metadata','qc','normalize','pca','heatmap','export'],differential:['data_input','sample_metadata','qc','normalize','pca','deseq2','heatmap','export']}},
  proteomics:{label:['蛋白质组','Proteomics'],inputTypes:['intensity','normalized','spectral_counts'],defaultType:'intensity',page:'import',omics:'all',steps:abundance('protein'),presets:{minimal:['data_input','sample_metadata','qc','export'],exploratory:['data_input','sample_metadata','qc','normalize','pca','heatmap','export'],differential:['data_input','sample_metadata','qc','normalize','differential','volcano','export']}},
  metabolomics:{label:['代谢组','Metabolomics'],inputTypes:['intensity','normalized'],defaultType:'intensity',page:'import',omics:'metabolomics',steps:abundance('metabolite'),presets:{minimal:['data_input','sample_metadata','qc','export'],exploratory:['data_input','sample_metadata','qc','normalize','pca','heatmap','export'],differential:['data_input','sample_metadata','qc','normalize','differential','volcano','export']}},
  microbiome_16s:{label:['16S 微生物组','16S microbiome'],inputTypes:['taxon_counts','relative_abundance'],defaultType:'taxon_counts',page:'import',omics:'microbiome_16s',steps:microbiome,presets:{minimal:['data_input','sample_metadata','qc','export'],exploratory:['data_input','sample_metadata','qc','normalize','alpha','beta','composition','export'],differential:['data_input','sample_metadata','qc','normalize','differential','export']}},
  metagenomics:{label:['宏基因组 · 功能矩阵','Metagenomics · functional matrices'],inputTypes:['functional_counts','relative_abundance','normalized'],defaultType:'functional_counts',page:'import',omics:'metagenomics',steps:metagenomics,presets:{minimal:['data_input','sample_metadata','qc','export'],exploratory:['data_input','sample_metadata','qc','normalize','heatmap','export'],differential:['data_input','sample_metadata','qc','normalize','differential','enrichment','export']}},
  chipseq:{label:['ChIP-seq / CUT&RUN','ChIP-seq / CUT&RUN'],inputTypes:['peaks','bam'],defaultType:'peaks',page:'chipseq',omics:'chipseq',steps:chip,presets:{minimal:['data_input','sample_metadata','reference','qc','export'],exploratory:['data_input','sample_metadata','reference','qc','annotation','motif','export'],differential:['data_input','sample_metadata','reference','qc','differential_binding','export']}},
  clinical:{label:['临床 / 表型','Clinical / phenotype'],inputTypes:['clinical_table'],defaultType:'clinical_table',page:'clinical',omics:'clinical',steps:clinical,presets:{minimal:['data_input','sample_metadata','qc','export'],exploratory:['data_input','sample_metadata','qc','three_line','export'],differential:['data_input','sample_metadata','qc','systematic','export']}},
  multiomics:{label:['多组学联合分析','Multi-omics integration'],inputTypes:['multiple_assays'],defaultType:'multiple_assays',page:'import',omics:'multiomics',steps:joint,presets:{minimal:['data_input','sample_metadata','align','qc','export'],exploratory:['data_input','sample_metadata','align','qc','correlation','export'],differential:['data_input','sample_metadata','align','qc','differential','pathway','export']}},
};

export function textPair(pair,locale='zh'){return pair[['zh','zh-TW'].includes(locale)?0:1];}
export function dependencies(scope,op,inputType){
  const def=WORKFLOW_LIBRARY[scope]?.steps[op];if(!def)return[];
  const deps=[...def.deps];
  if(scope==='chipseq'&&inputType==='bam'&&def.accepts?.includes('peaks'))deps.push('peak_call');
  return [...new Set(deps)];
}
export function validateBlueprint(plan){
  const errors=[];const library=WORKFLOW_LIBRARY[plan?.scope];
  if(!library)return{valid:false,errors:[{code:'scope'}],execution:'planning',executable:false};
  if(plan.schema!==LIBRARY_VERSION||Object.keys(plan).some(k=>!['schema','scope','input_type','steps'].includes(k)))errors.push({code:'schema'});
  if(!library.inputTypes.includes(plan.input_type))errors.push({code:'input_type'});
  if(!Array.isArray(plan.steps)||!plan.steps.length||plan.steps.length>32)return{valid:false,errors:[{code:'steps'}],execution:'planning',executable:false};
  const seen=new Set(),ids=new Set(),artifacts=new Set([plan.input_type]);
  for(const [i,node]of plan.steps.entries()){
    if(!node||typeof node!=='object'||Object.keys(node).some(k=>!['id','operation','parameters'].includes(k))){errors.push({code:'operation'});continue;}
    const def=Object.hasOwn(library.steps,node.operation)?library.steps[node.operation]:null;
    if(!def||seen.has(node.operation)||typeof node.id!=='string'||!node.id||ids.has(node.id)){errors.push({code:'operation',operation:node.operation});continue;}
    ids.add(node.id);
    for(const dep of dependencies(plan.scope,node.operation,plan.input_type))if(!seen.has(dep))errors.push({code:'dependency',operation:node.operation,dependency:dep});
    if(def.accepts&&!def.accepts.some(type=>artifacts.has(type)))errors.push({code:'type',operation:node.operation,accepts:def.accepts});
    if(def.terminal&&i!==plan.steps.length-1)errors.push({code:'terminal',operation:node.operation});
    const params=node.parameters;
    if(!params||typeof params!=='object'||Array.isArray(params)||Object.keys(params).length!==Object.keys(def.parameters).length||Object.keys(params).some(k=>!Object.hasOwn(def.parameters,k)))errors.push({code:'parameters',operation:node.operation});
    else for(const [key,spec]of Object.entries(def.parameters)){
      const value=params[key];
      if(spec.type==='number'&&(typeof value!=='number'||!Number.isFinite(value)||value<spec.min||value>spec.max||(spec.step===1&&!Number.isInteger(value))))errors.push({code:'parameter_value',operation:node.operation,parameter:key});
      if(spec.type==='choice'&&!spec.options.includes(value))errors.push({code:'parameter_value',operation:node.operation,parameter:key});
    }
    seen.add(node.operation);if(def.produces)artifacts.add(def.produces);
  }
  for(const [op,def]of Object.entries(library.steps))if(def.required&&!seen.has(op))errors.push({code:'required',operation:op});
  const executable=plan.scope==='bulk_rnaseq'&&plan.input_type==='raw_counts'&&plan.steps.every(node=>node&&['gate','count'].includes(library.steps[node.operation]?.mode));
  const nativeExecutable=!errors.length&&plan.scope==='bulk_rnaseq'&&plan.input_type==='raw_counts'&&plan.steps.some(node=>library.steps[node?.operation]?.mode==='count');
  const deferred=plan.steps.filter(node=>node&&!['gate','count'].includes(library.steps[node.operation]?.mode)).map(node=>node.operation);
  return{valid:!errors.length,errors,execution:executable?'count_executor':nativeExecutable?'partial_count_executor':'review_in_pages',executable:!errors.length&&executable,nativeExecutable,deferred};
}

export class WorkflowComposer{
  constructor(scope='bulk_rnaseq'){this.scope=scope;this.inputType=WORKFLOW_LIBRARY[scope].defaultType;this.steps=[];this.preset('differential');}
  get library(){return WORKFLOW_LIBRARY[this.scope];}
  node(op){const def=this.library.steps[op];return{id:op,operation:op,parameters:Object.fromEntries(Object.entries(def.parameters).map(([key,spec])=>[key,spec.value]))};}
  preset(name){const operations=this.library.presets[name];if(!operations)throw Error('preset');this.steps=operations.map(op=>this.node(op));this.reconcile();return this.blueprint();}
  reconcile(){
    const existing=new Map(this.steps.map(s=>[s.operation,s]));const ordered=[],seen=new Set();
    const visit=op=>{if(seen.has(op))return;seen.add(op);for(const dep of dependencies(this.scope,op,this.inputType))visit(dep);ordered.push(existing.get(op)||this.node(op));};
    for(const node of this.steps)if(!this.library.steps[node.operation].terminal)visit(node.operation);
    for(const node of this.steps)if(this.library.steps[node.operation].terminal)visit(node.operation);
    this.steps=ordered;return this;
  }
  blueprint(){return{schema:LIBRARY_VERSION,scope:this.scope,input_type:this.inputType,steps:copy(this.steps)};}
  status(){return validateBlueprint(this.blueprint());}
  requiredBy(op){return this.steps.filter(s=>dependencies(this.scope,s.operation,this.inputType).includes(op)).map(s=>s.operation);}
  add(op){
    if(!this.library.steps[op])return{ok:false,code:'operation'};
    const added=[];const insert=name=>{if(this.steps.some(s=>s.operation===name))return;for(const dep of dependencies(this.scope,name,this.inputType))insert(dep);const index=this.steps.findIndex(s=>this.library.steps[s.operation].terminal);this.steps.splice(index<0?this.steps.length:index,0,this.node(name));added.push(name);};
    insert(op);this.reconcile();return{ok:true,added,status:this.status()};
  }
  remove(op){
    if(this.library.steps[op]?.required)return{ok:false,code:'required',operation:op};
    const consumers=this.requiredBy(op);if(consumers.length)return{ok:false,code:'dependency',operation:op,consumers};
    this.steps=this.steps.filter(s=>s.operation!==op);return{ok:true};
  }
  move(from,to){
    if(!Number.isInteger(from)||!Number.isInteger(to)||from<0||to<0||from>=this.steps.length||to>=this.steps.length)return{ok:false,code:'position'};
    const before=copy(this.steps);const [node]=this.steps.splice(from,1);this.steps.splice(to,0,node);
    const result=this.status();if(!result.valid){this.steps=before;return{ok:false,code:'order',errors:result.errors};}return{ok:true};
  }
  load(value){
    if(value?.schema!==LIBRARY_VERSION||value.scope!==this.scope)throw Error('schema');
    const valid=validateBlueprint(value);if(!valid.valid)throw Error('invalid_blueprint');
    this.inputType=value.input_type;this.steps=copy(value.steps);return this;
  }
  countSteps(){if(!this.status().executable)throw Error('execution_not_connected');return this.steps.filter(s=>this.library.steps[s.operation].mode==='count').map(s=>({...copy(s),operation:this.library.steps[s.operation].engine}));}
  connectedCountSteps(){if(!this.status().nativeExecutable)throw Error('execution_not_connected');return this.steps.filter(s=>this.library.steps[s.operation].mode==='count').map(s=>({...copy(s),operation:this.library.steps[s.operation].engine}));}
}

// Bounded local keyword drafting. Uses the selected scope and never executes.
export function proposeForScope(question,scope,inputType){
  if(typeof question!=='string'||!question.trim()||question.length>4000)throw Error('question');
  if(/不要|不做|跳过|排除|\b(?:without|skip|not|no)\b/i.test(question))throw Error('ambiguous_negation');
  const composer=new WorkflowComposer(scope);composer.inputType=inputType;composer.preset('minimal');
  let matched=false;
  if(/完整|全部|\b(?:full|complete)\b/i.test(question)){composer.preset('differential');matched=true;}
  else if(/探索|\bexplor\w*/i.test(question)){composer.preset('exploratory');matched=true;}
  else if(/最小|仅.*质控|\bminimal\b|\bqc\s+only\b/i.test(question)){matched=true;}
  const operations={pca:/\bPCA\b/i,beta:/\b(?:PCoA|beta)\b|β|贝塔/i,alpha:/\balpha\b|α|阿尔法/i,
    normalize:/归一化|标准化|\bnormaliz\w*/i,filter:/过滤|\bfilter\w*/i,impute:/缺失|填补|\bimput\w*/i,
    differential:/差异|比较|\bdifferential\b/i,deseq2:/差异|比较|\b(?:differential|DESeq2)\b/i,
    edger:/\bedgeR\b/i,
    heatmap:/热图|\bheatmap\b/i,volcano:/火山|\bvolcano\b/i,enrichment:/富集|通路|\b(?:enrich\w*|GO|KEGG|pathway)\b/i,
    pathway:/富集|通路|\bpathway\b/i,wgcna:/\bWGCNA\b/i,taxonomy:/分类汇总|\btaxonom\w*/i,
    rarefy:/稀释|\braref\w*/i,composition:/组成图|\bcomposition\b/i,network:/网络|\bnetwork\b/i,
    annotation:/注释|\bannotat\w*/i,motif:/\bmotif\b/i,peak_call:/调峰|\bMACS\w*/i,
    differential_binding:/差异结合|\bdifferential\b/i,three_line:/三线表|基线表|\bbaseline\b/i,
    systematic:/系统临床|\bsystematic\b/i,correlation:/相关|关联|\b(?:correlation|association)\b/i,
    prediction:/预测|\bpredict\w*/i,joint:/联合|整合|\b(?:joint|integration)\b/i};
  for(const [operation,pattern]of Object.entries(operations))if(composer.library.steps[operation]&&pattern.test(question)){composer.add(operation);matched=true;}
  if(!matched)throw Error('unrecognized');
  if(!composer.status().valid)throw Error('input_type');
  return{status:'draft',source:'local_keywords',blueprint:composer.blueprint(),execution_performed:false};
}
