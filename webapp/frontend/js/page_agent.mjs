// Typed form bridge. Page text and model output never become code or selectors.
const FIELDS={
 matrix:['discovery-input','discovery-mode','matrix-accession','matrix-query','matrix-budget','matrix-job-id'],
 integration:['rp-project','rp-name','rp-mode'],
 workbench:['wb-job','wb-scope','wb-input-type','wb-preset','wb-reference','wb-test','wb-operation','wb-seed'],
 import:['import-data-type','import-exp-name','import-assay-name','import-start-level','import-tax-sep'],
 preparation:['filter-min-count','filter-min-detect-rate','filter-min-prevalence','filter-max-na','norm-method'],
 analysis:['diff-method','diff-group','diff-ref','diff-test','diff-comparison-mode','dim-method','cor-method','cluster-method','cluster-k','enrich-database','enrich-organism','enrich-fc-cutoff','enrich-p-cutoff'],
 visualization:['heat-group','heat-width','heat-height','heat-topn','heat-font-size','heat-cluster-rows','heat-cluster-cols','heat-show-rn','bar-mode','bar-group','bar-topn','box-group','box-feature','scat-group','scat-ordination','scat-dim1','scat-dim2','scat-width','scat-height','scat-proj-width','scat-proj-height','vol-fc','vol-p','vol-use-padj','vol-topn','enrich-viz-source','enrich-viz-top-n','enrich-viz-cutoff','gsea-viz-source','gsea-viz-pathway'],
 runall:['ra-pipeline','ra-group','ra-ref','ra-test','ra-organism'],chipseq:['chip-genome','chip-macs-preset'],
};
const STATUS={analysis:['analysis-latest-task'],visualization:['analysis-latest-task'],import:['import-result'],matrix:['discovery-status','matrix-status','matrix-series','matrix-receipt'],integration:['rp-status'],workbench:['wb-input-info','wb-guide','wb-graph-status','wb-status']};
function fieldIds(workflow,doc){
 const ids=[...(FIELDS[workflow]||[])];
 if(workflow==='import'){const kind=doc.getElementById('omics-pipeline')?.value;if(['transcriptomics','proteomics','microbiome_16s','metagenomics','metabolomics','clinical'].includes(kind))for(const key of ['name','mode','assay'])ids.push('agent-upload-'+key+'-'+kind);}
 if(workflow==='integration')for(const node of doc.querySelectorAll('#rp-blocks select[id]'))if(/^rp-block-(omics|scale)-[A-Za-z0-9-]{1,64}$/.test(node.id))ids.push(node.id);
 return ids;
}
const panelUnavailable=panel=>panel&&(panel.classList&&!panel.classList.contains('active')||panel.classList?.contains('hidden')||panel.hidden||panel.style?.display==='none');
export function pageAgentContext(workflow,doc=document){
 const fields=[];
 for(const id of fieldIds(workflow,doc)){const node=doc.getElementById(id);if(!node)continue;const panel=node.closest('.tab-panel');if(panelUnavailable(panel))continue;if(workflow==='import'&&node.closest('.legacy-import-details')&&!node.closest('.legacy-import-details').open)continue;
  fields.push({id,type:node.tagName==='SELECT'?'select':node.type||'text',value:String(node.value||'').slice(0,500),
   options:node.tagName==='SELECT'?[...node.options].filter(o=>!o.disabled).slice(0,40).map(o=>({value:o.value,label:o.textContent.slice(0,100)})):undefined});
 }
 const statuses=(STATUS[workflow]||[]).map(id=>doc.getElementById(id)?.textContent?.slice(0,600)).filter(Boolean);
 const files=workflow==='matrix'?[...doc.querySelectorAll('#matrix-files [data-agent-file]')].slice(0,30).map(node=>({id:node.dataset.agentFile,name:node.dataset.agentName,disabled:node.disabled})):[];
 if(workflow==='import')for(const node of doc.querySelectorAll('#page-import .upload-data-file,#page-import .upload-meta-file'))for(const file of node.files||[])files.push({id:node.id,name:file.name,bytes:file.size});
 const experiment=typeof window!=='undefined'?{name:window._emp?.currentExp||'',omics:doc.getElementById('omics-pipeline')?.value,metadata_columns:(window._emp?.coldataCols||[]).map(c=>({name:c.name,n_unique:c.n_unique})).slice(0,20)}:undefined;
 return {fields,statuses,files,experiment,page:workflow,headings:[...doc.querySelectorAll?.('.page.active h2,.page.active .tab-panel.active h3')||[]].slice(0,8).map(n=>n.textContent?.slice(0,100)),workbench:typeof window!=='undefined'?window._empWorkbenchState:undefined,profile:workflow==='workbench'&&typeof window!=='undefined'?window._empWorkbenchProfile:undefined,integration:workflow==='integration'&&typeof window!=='undefined'?window._empIntegrationSummary:undefined,scope:'Whitelisted page controls and numerical readiness only; no keys, matrices, sample tables, scripts or PDF text.'};
}
export function applyPageFields(workflow,fields,doc=document){
 if(!fields||Array.isArray(fields)||typeof fields!=='object'||Object.keys(fields).length>12)throw Error('Invalid page fields');
 const updates=[];
 for(const [id,value]of Object.entries(fields)){
  if(!fieldIds(workflow,doc).includes(id))throw Error('当前页面不允许填写字段：'+id);
  const node=doc.getElementById(id);if(!node||node.disabled||node.readOnly||!node.closest('.page.active'))throw Error('字段当前不可用：'+id);
  const panel=node.closest('.tab-panel');if(panelUnavailable(panel))throw Error('字段不在当前步骤：'+id);
  if(!['string','number','boolean'].includes(typeof value)||String(value).length>1000)throw Error('Invalid field value');
  const text=String(value);
  if(id==='wb-operation'&&[...node.options].some(o=>o.value===text&&o.disabled))continue; // Already present in the workflow: idempotent success.
  if(node.tagName==='SELECT'&&String(node.value)!==text&&![...node.options].some(o=>o.value===text&&!o.disabled))throw Error('请选择页面已有选项：'+id);
  if(node.type==='number'&&(!Number.isFinite(Number(value))||(node.min!==''&&Number(value)<Number(node.min))||(node.max!==''&&Number(value)>Number(node.max))))throw Error('参数超出页面范围：'+id);
  if(String(node.value)!==text)updates.push([node,text]);
 }
 for(const [node,text]of updates){node.value=text;node.dispatchEvent(new Event('input',{bubbles:true}));node.dispatchEvent(new Event('change',{bubbles:true}));}
 return updates.map(([node])=>node.id);
}
