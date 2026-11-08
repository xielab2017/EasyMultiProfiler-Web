// GSEA analysis is separate from ORA and from descriptive running-score plotting.
export function initGseaAnalysis({API,showResultTable,navigateTo}) {
  const parent=document.getElementById('ana-enrich');if(!parent)return;
  const section=document.createElement('section');section.id='gsea-analysis';
  section.innerHTML=`<hr><h3>GSEA 基因集富集分析</h3>
    <p class="hint">使用当前差异比较的完整可检验基因排名，不按差异 P/FDR 或倍数阈值筛选。GO/KEGG 过度代表分析（上方）与 GSEA 分开运行。完成后选择通路绘制曲线。</p>
    <div class="form-grid">
      <div class="form-group"><label>GSEA 数据库</label><select id="gsea-analysis-db"><option>GO_BP</option><option>GO_CC</option><option>GO_MF</option><option>KEGG</option></select></div>
      <div class="form-group"><label>物种</label><select id="gsea-analysis-org"><option value="hsa">Human</option><option value="mmu">Mouse</option><option value="rno">Rat</option></select></div>
      <div class="form-group"><label>输入基因 ID 类型</label><select id="gsea-analysis-id"><option>SYMBOL</option><option>ENTREZID</option><option>ENSEMBL</option></select></div>
      <div class="form-group"><label>排名指标（降序）</label><select id="gsea-analysis-metric"><option value="stat">差异检验统计量 stat（如 DESeq2 Wald）</option><option value="log2FoldChange">log2 fold change</option><option value="signed_log10p">sign(log2FC) × −log10(raw P)</option></select></div>
      <div class="form-group"><label>加权指数</label><input id="gsea-analysis-weight" type="number" min="0" max="2" step="0.1" value="1"></div>
      <div class="form-group"><label>最小基因集大小</label><input id="gsea-analysis-min" type="number" min="5" value="15"></div>
      <div class="form-group"><label>最大基因集大小</label><input id="gsea-analysis-max" type="number" max="10000" value="500"></div>
      <div class="form-group"><label>随机种子</label><input id="gsea-analysis-seed" type="number" value="20261108"></div>
    </div>
    <p class="hint">统计量列缺失时会提示选择其他指标。输出 ES、NES、P、BH-FDR 和 leading-edge；保留所有已计算通路，显著性筛选在查看结果时进行。未匹配、歧义 ID、无效排名与并列排名数量会记录，不自动选取最有利映射。</p>
    <button id="gsea-analysis-run" class="btn btn-primary">运行 GSEA（后台任务）</button>
    <button id="gsea-analysis-plot" class="btn btn-outline" disabled>选择通路与绘制 GSEA 曲线</button>
    <p id="gsea-analysis-status" role="status"></p><div id="gsea-analysis-result" class="result-area hidden"></div>`;
  parent.append(section);
  const el=id=>document.getElementById('gsea-analysis-'+id);
  let source=null;
  el('run').onclick=async()=>{
    el('run').disabled=true;el('plot').disabled=true;source=null;
    try {
      const session_id=localStorage.getItem('emp_session_id'),experiment=window._emp?.currentExp;
      if(!session_id||!experiment)throw Error('请先导入数据并完成差异分析。');
      el('status').textContent='GSEA 已提交后台；可在后台任务列表查看进度。';
      const result=await API.request('POST','/analyze/gsea',{session_id,experiment,database:el('db').value,organism:el('org').value,
        id_type:el('id').value,metric:el('metric').value,exponent:Number(el('weight').value),
        min_size:Number(el('min').value),max_size:Number(el('max').value),seed:Number(el('seed').value)});
      source=result._job_id||'current_gsea';
      showResultTable('gsea-analysis-result',result.data,500,{aiContext:{analysis_type:'gsea'}});
      el('status').textContent=`GSEA 完成：${result.n_rows||0} 个通路。输入核验：${JSON.stringify(result.input_audit||{})}`;
      el('plot').disabled=!result.n_rows;
    }catch(error){el('status').textContent=error.message;}finally{el('run').disabled=false;}
  };
  el('plot').onclick=()=>window.dispatchEvent(new CustomEvent('emp:plot-enrichment',{detail:{source_job:source,kind:'gsea'}}));
  window.addEventListener('emp:open-gsea-analysis',()=>{navigateTo('analysis');document.querySelector('.tab[data-tab="ana-enrich"]')?.click();section.scrollIntoView({block:'start',behavior:'smooth'});});
}
