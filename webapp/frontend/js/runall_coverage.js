// The preview is a plan; completion is only taken from the server manifest.
export function readRunallCoverageOptions(pipeline,doc=document){
 const get=id=>doc.getElementById(id),number=(id,fallback)=>{const raw=get(id)?.value;if(raw===undefined||raw==='')return fallback;const n=Number(raw);if(!Number.isFinite(n))throw Error(`Invalid numeric option: ${id}`);return n;};
 const checked=id=>get(id)?.checked!==false;
 const options={do_correlation:checked('ra-do-correlation'),do_cluster:checked('ra-do-cluster'),do_method_figures:checked('ra-do-method-figures'),feature_top_n:number('ra-feature-top-n',100),network_cutoff:number('ra-network-cutoff',.6),seed:number('ra-seed',1)};
 if(options.feature_top_n<10||options.feature_top_n>500||!Number.isInteger(options.feature_top_n))throw Error('Feature cap must be an integer from 10 to 500.');
 if(options.network_cutoff<=0||options.network_cutoff>1)throw Error('Network cutoff must be within (0,1].');
 if(!Number.isInteger(options.seed)||options.seed<0||options.seed>2147483647)throw Error('Seed must be a nonnegative 32-bit integer.');
 if(pipeline==='rnaseq'){
  options.do_gsea=get('ra-do-gsea')?.checked===true;options.gsea_database=get('ra-gsea-database')?.value||'GO_BP';options.gsea_top_n=number('ra-gsea-top-n',3);
  if(!['GO_BP','KEGG'].includes(options.gsea_database)||!Number.isInteger(options.gsea_top_n)||options.gsea_top_n<1||options.gsea_top_n>10)throw Error('Check GSEA gene sets and number of curves (1–10).');
 }else{
  const groups=String(get('ra-ternary-groups')?.value||'').split(',').map(value=>value.trim()).filter(Boolean);
  if(groups.length&&(groups.length!==3||new Set(groups).size!==3))throw Error('三元图需三个不同分组；或留空仅对恰好三组自动运行。 / Ternary requires three distinct groups.');
  options.ternary_groups=groups.length?groups:null;
 }
 return options;
}
export function runallCoveragePlan(pipeline,options,{enrichment=true,groups=[]}={}){
 const stage=(id,label,enabled=true,condition='')=>({id,label,enabled,condition});
 const common=[stage('qc','输入 QC 与数据摘要 / Input QC'),stage('metadata','样本分组与来源 / Sample metadata')];
 if(pipeline==='rnaseq')return [...common,stage('pca','PCA 坐标与散点 / PCA scores + scatter'),stage('differential','差异分析与统计表 / Differential analysis'),stage('volcano','火山图与 MA / Volcano + MA'),stage('deg_heatmap','差异特征热图 / DEG heatmap'),stage('top_variance_heatmap','高变特征热图 / Variable-feature heatmap'),stage('sample_correlation','样本相关热图 / Sample correlation'),stage('sample_clustering','样本聚类 / Sample clustering',options.do_cluster),stage('feature_correlation_network','特征相关与网络 / Feature correlation + network',options.do_correlation),stage('de_significance_scatter','差异显著性图 / DE significance scatter',options.do_method_figures,'需要方法库和有效校正 P / Requires method library + valid adjusted P'),stage('ora_go','GO 富集表与气泡图 / GO tables + dotplot',enrichment),stage('ora_kegg','KEGG 富集表与气泡图 / KEGG tables + dotplot',enrichment),stage('gsea_analysis','GSEA 完整排名检验 / Full-ranking GSEA',options.do_gsea,'需要可映射完整排名 / Full mapped rankings required'),stage('gsea_curves','GSEA ES 曲线 / Running ES curves',options.do_gsea,'仅有真实 GSEA 结果时 / Requires successful GSEA')];
 const requested=options.ternary_groups||groups,ternaryCondition=requested.length===3?'需要非负丰度和可用方法库 / Nonnegative abundance + method library required':'未恰好选择三组；此阶段将记录跳过 / Requires exactly three groups';
 return [...common,stage('taxonomy','分类层级整理 / Taxonomy'),stage('alpha','Alpha 指数表与箱线图 / Alpha metrics + boxplots'),stage('beta_pca','PCA 排序 / PCA'),stage('beta_pcoa','PCoA 排序 / PCoA'),stage('beta_nmds','NMDS 排序 / NMDS'),stage('composition','群落组成柱状/热图 / Composition plots'),stage('differential','差异菌统计 / Differential taxa'),stage('volcano','差异效应火山图 / Taxon volcano',true,'仅差异结果包含效应量时 / Requires a fold-change column'),stage('top_variance_heatmap','高变菌热图 / Variable-taxa heatmap'),stage('sample_correlation','样本相关 / Sample correlation'),stage('sample_clustering','样本聚类 / Sample clustering',options.do_cluster),stage('feature_correlation_network','特征相关与网络 / Feature network',options.do_correlation),stage('ternary','三元组成图 / Ternary composition',options.do_method_figures,ternaryCondition)];
}
export function summarizeRunallStages(result){
 const rows=Array.isArray(result?.stages)?result.stages:[];
 const counts={done:0,skipped:0,error:0};for(const row of rows)if(Object.hasOwn(counts,row.status))counts[row.status]++;
 return {rows,counts,partial:result?.partial===true||counts.error>0||counts.skipped>0};
}
export function initRunallCoverage(){
 const el=id=>document.getElementById(id);if(!el('ra-coverage-preview'))return;
 const node=(tag,text)=>{const item=document.createElement(tag);if(text!==undefined)item.textContent=text;return item;};
 let lastRecord=null;
 const grouping=()=>{const name=el('ra-group')?.value;return (window._emp?.coldataCols||[]).find(row=>row.name===name)|| (window._emp?.coldataCols||[]).find(row=>String(row.name).toLowerCase()==='group');};
 function update(){
  const pipeline=el('ra-pipeline')?.value||'rnaseq';
  document.querySelectorAll('.ra-coverage-rna').forEach(item=>item.classList.toggle('hidden',pipeline!=='rnaseq'));
  document.querySelectorAll('.ra-coverage-m16s').forEach(item=>item.classList.toggle('hidden',pipeline!=='m16s'));
  const preview=el('ra-coverage-preview');preview.replaceChildren();
  try{
   const options=readRunallCoverageOptions(pipeline),group=grouping(),groups=group?.values||[];
   const plan=runallCoveragePlan(pipeline,options,{enrichment:el('ra-enrich')?.value==='true',groups});
   preview.append(node('h3','本次覆盖预览 / Planned analysis and figures'));
   const list=node('ul');for(const stage of plan)list.append(node('li',`${stage.enabled?'计划运行 / Planned':'已关闭 / Disabled'} · ${stage.label}${stage.condition?' — '+stage.condition:''}`));preview.append(list);
   const messages=[];
   if(!window._emp?.currentExp)messages.push('请先导入数据并选择实验 / Import data and select an experiment.');
   if(!group||Number(group.n_unique)<2)messages.push('需要至少两组的真实样本分组；请核对分组列 / Check a grouping variable with at least two groups.');
   if(pipeline==='rnaseq')messages.push('DESeq2 要求原始非负计数与独立重复；组织来源和物种需与分析设计一致 / RNA-seq requires valid raw counts and biological replicates.');
   if(pipeline==='m16s'&&options.do_method_figures&&groups.length!==3&&!options.ternary_groups)messages.push('当前不是恰好三组，三元图会跳过；其余分析仍可运行 / Ternary will be skipped unless three groups are explicitly selected.');
   el('ra-coverage-preflight').textContent=messages.join(' ');
  }catch(error){el('ra-coverage-preflight').textContent=error.message;}
 }
 function showResult(result,job_id){
  const {rows,counts,partial}=summarizeRunallStages(result);lastRecord={job_id,run_id:result?.run_id,zip_name:result?.zip_name,stages:rows,counts,partial};
  el('ra-stage-results').classList.remove('hidden');
  el('ra-stage-summary').textContent=rows.length?`完成 ${counts.done} · 跳过 ${counts.skipped} · 失败 ${counts.error} / Done · skipped · failed. ${partial?'请检查各阶段原因。 / Review stage reasons.':'各已报告阶段已完成。'} 结果包包含 manifest.json。`:'此服务未提供阶段清单；不能从进度 100% 推断所有模块成功。请检查结果包日志。';
  const table=node('table');table.className='data-table';const header=node('tr');for(const label of ['阶段 / Stage','状态 / Status','原因 / Reason','秒 / Seconds','产物 / Files'])header.append(node('th',label));table.append(header);
  for(const row of rows){const tr=node('tr');for(const text of [row.label||row.id,row.status,row.reason||'—',row.elapsed_s??'—',Array.isArray(row.files)?row.files.join(', '):''])tr.append(node('td',String(text)));table.append(tr);}
  el('ra-stage-table').replaceChildren(table);
 }
 el('ra-stage-download').onclick=()=>{if(!lastRecord)return;const url=URL.createObjectURL(new Blob([JSON.stringify(lastRecord,null,2)],{type:'application/json'})),link=node('a');link.href=url;link.download=`runall-stages-${lastRecord.run_id||'result'}.json`;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};
 el('page-runall').addEventListener('change',update);
 el('btn-run-all').addEventListener('click',event=>{
  try{readRunallCoverageOptions(el('ra-pipeline').value);if(!window._emp?.currentExp)throw Error('请先导入数据并选择实验。 / Import data and select an experiment.');
   el('ra-stage-results').classList.add('hidden');lastRecord=null;
  }catch(error){event.preventDefault();event.stopImmediatePropagation();el('ra-coverage-preflight').textContent=error.message;}
 },true);
 window.addEventListener('emp:runall-result',event=>showResult(event.detail?.result,event.detail?.job_id));
 window.addEventListener('emp:page-view',event=>{if(event.detail?.page==='runall')update();});
 update();
}
