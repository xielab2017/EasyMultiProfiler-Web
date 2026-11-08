// Only an explicitly reviewed current page can be dispatched by the agent.
// The model never supplies a selector, parameters or executable code.
const ACTIONS = {
 matrix:{'matrix-main':'discovery-search'},integration:{'integration-main':'rp-preview'},workbench:{'workbench-main':'wb-prepare'},
 preparation:{'prep-filter':'btn-filter','prep-normalize':'btn-normalize','prep-impute':'btn-impute',
   'prep-rarefy':'btn-rarefy','prep-collapse':'btn-collapse','prep-m16s-taxonomy':'m16s-btn-prepare-taxonomy'},
 analysis:{'ana-alpha':'btn-alpha','ana-diff':'btn-diff','ana-dim':'btn-dim','ana-cor':'btn-cor',
   'ana-cluster':'btn-cluster','ana-marker':'btn-marker','ana-enrich':'btn-enrich'},
 visualization:{'viz-heatmap':'btn-heatmap','viz-barplot':'btn-barplot','viz-boxplot':'btn-boxplot',
   'viz-scatter':'btn-scatter','viz-alpha':'btn-alpha-plot','viz-volcano':'btn-volcano','viz-gsea':'gsea-viz-generate','viz-enrichment-dotplot':'enrich-viz-generate','viz-ternary':'ternary-viz-generate','viz-de-significance':'de-significance-generate'},
};
const UPLOAD_OMICS=['transcriptomics','proteomics','microbiome_16s','metagenomics','metabolomics','clinical'];
export function currentAgentAction(context={}) {
 if(context.workflow==='import'&&UPLOAD_OMICS.includes(context.omics))return 'agent-upload-'+context.omics;
 return ACTIONS[context.workflow]?.[context.tab] || null;
}
export function resolveAgentNavigation(target) {
 const pages=['guide','models','import','summary','inspector','chipseq','chipseq_downstream','export','matrix','integration','workbench','preparation','analysis','visualization','runall','clinical'];
 const tabs={analysis:['ana-alpha','ana-diff','ana-dim','ana-cor','ana-cluster','ana-marker','ana-enrich','ana-gsea'],preparation:['prep-filter','prep-normalize','prep-impute','prep-rarefy','prep-collapse'],visualization:['viz-barplot','viz-boxplot','viz-heatmap','viz-scatter','viz-volcano','viz-enrichment-dotplot','viz-gsea','viz-ternary','viz-de-significance']};
 let [page,tab,...extra]=String(target||'').replace(/^(analysis|preparation|visualization)\//,'$1:').split(':');
 if(!tab){const owner=Object.keys(tabs).find(key=>tabs[key].includes(page));if(owner){tab=page;page=owner;}}
 if(extra.length||!pages.includes(page)||(tab&&!tabs[page]?.includes(tab)))throw Error('无效的分析页面 / Unknown workflow page.');
 return {page,tab};
}
export function assertAgentSubmission(context,request,target) {
 if(target&&target!==context.tab&&target!==currentAgentAction(context))throw Error('任务步骤已不匹配，请读取当前步骤后再提交。');
 if(context.workflow!=='analysis')return;
 const clauses=String(request||'').split(/[。；;\n]/).filter(s=>!/(不要|不重新|不重复|已完成|已保存|do not|don.t|already completed|already saved)/i.test(s));
 const positive=clauses.join(' '),intent={
  'ana-dim':/PCA|PCoA|降维|dimension|ordination/i,
  'ana-diff':/DESeq2|edgeR|差异分析|differential/i,
  'ana-cor':/相关分析|相关性分析|correlation/i,
  'ana-cluster':/聚类分析|clustering/i,
  'ana-enrich':/富集分析|enrichment/i,
 };
 const wanted=Object.keys(intent).filter(tab=>intent[tab].test(positive));
 if(wanted.length===1&&context.tab!==wanted[0])throw Error('本次分析应先前往 analysis:'+wanted[0]+'；当前运行按钮属于另一分析，未提交。');
 if(!wanted.length&&/绘图|出图|visualization|plot/i.test(request)&&/不重新|不要重新|不重复|not.*rerun/i.test(request))throw Error('本次只使用已有结果出图，未提交新的分析；请前往可视化页面。');
}
export function resolveHeatmapSize(context, args, reviewed) {
 if(!reviewed||!context.hasExperiment||context.workflow!=='visualization'||context.tab!=='viz-heatmap')throw Error('请在热图页面启用 Agent 模式后再调整图形尺寸。');
 if(typeof args.width_inches!=='number'||!Number.isFinite(args.width_inches)||args.width_inches<4||args.width_inches>30||typeof args.height_inches!=='number'||!Number.isFinite(args.height_inches)||args.height_inches<4||args.height_inches>36)throw Error('图宽须为 4–30 英寸，图高须为 4–36 英寸。');
 return {type:'resize_heatmap',button:'btn-heatmap',width:args.width_inches,height:args.height_inches};
}
export function resolveAgentAction(context, action, reviewed) {
 if(action==='refresh_tasks')return {type:'refresh_tasks'};
 if(reviewed!==true)throw Error('请先选择数据，并启用 Agent 模式。');
 const pageActions={matrix:{search_sources:'discovery-search',find_matrix_files:'matrix-resolve',read_downloaded_matrix:'matrix-open-workbench'},integration:{inspect_integration:'rp-preview',run_integration:'rp-run'},workbench:{build_workflow:'wb-template',prepare_workflow:'wb-prepare',run_workflow:'wb-run'}};
 const pageButton=pageActions[context.workflow]?.[action];if(pageButton)return {type:'submit_current',button:pageButton};
 if(action!=='submit_current'||(!context.hasExperiment&&!['matrix','integration','workbench','import'].includes(context.workflow)))throw Error('请先选择数据，并审核当前页面的方法、参数和分组，再启用 Agent 模式。');
 const button=currentAgentAction(context);if(!button)throw Error('当前步骤尚未接入 Agent 自动提交，请在对应页面准备并运行。');
 return {type:'submit_current',button};
}
