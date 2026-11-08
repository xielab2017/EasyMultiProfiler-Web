// Deterministic local orchestration. A model can request a registered accession, never a URL.
export function selectProcessedFile(files,budget){
 const rows=files.filter(f=>!/(?:\.(?:fastq|fq|sra|bam|cram|raw|mzml|wiff)(?:\.gz)?$|(?:^|[_\-.])RAW(?:[_\-.]|$))/i.test(f.name)&&/\.(?:txt|tsv|csv|mtx|h5|h5ad|rds|xlsx?|zip)(?:\.gz)?$/i.test(f.name)&&(!Number.isFinite(f.bytes)||f.bytes<=budget));
 const score=f=>/count/i.test(f.name)?100:/\.pg_matrix\./i.test(f.name)&&!/first.pass/i.test(f.name)?90:/matrix|abundance|protein/i.test(f.name)?70:/fpkm|tpm/i.test(f.name)?20:40;
 return rows.sort((a,b)=>score(b)-score(a)||String(a.name).localeCompare(String(b.name)))[0]||null;
}
export class AgentPipeline{
 constructor({api,budget=()=>5*1024**3,emit=()=>{},onComplete=()=>{}}){this.api=api;this.budget=budget;this.emit=emit;this.onComplete=onComplete;this.pending=new Map();this.jobs=new Map();this.cancelled=new Set();}
 async start(accession,fileId){
  if(!/^(?:GSE[0-9]{1,9}|PXD[0-9]{5,9})$/.test(accession))throw Error('请提供公开 GSE 或 PXD 编号；不执行任意地址下载。');
  const key=accession+':'+(fileId||'auto');if(this.pending.has(key))return this.pending.get(key);
  const work=this.begin(accession,fileId);this.pending.set(key,work);try{return await work;}finally{this.pending.delete(key);}
 }
 async begin(accession,fileId){
  this.emit({stage:'resolving',accession,message:'正在定位官方处理矩阵…'});
  const result=await this.api('matrix/resolve',{accession}),cap=Math.floor(this.budget());if(!Number.isFinite(cap)||cap<1024**2||cap>100*1024**3)throw Error('下载额度无效。');
  const file=fileId?result.manifest.files.find(f=>f.id===fileId):selectProcessedFile(result.manifest.files,cap);if(!file)throw Error('官方来源未找到额度内可自动下载的处理表；原始测序文件不会替代矩阵。');
  const history=await this.api('matrix/history',{});let job=(history.jobs||[]).find(j=>j.source_url===file.url&&['queued','running','completed'].includes(j.status));
  if(!job){
   const existing=[...this.jobs.values()].find(j=>j.source_url===file.url&&j.local_queue&&!this.cancelled.has(j.job_id));if(existing)return existing;
   const prepared=await this.api('matrix/plan',{manifest_id:result.manifest_id,file_id:file.id,max_bytes:cap});if(!prepared.plan.download_enabled||prepared.plan.status!=='ready_for_confirmation')throw Error((prepared.plan.blockers||[]).join('；')||'下载计划未通过检查');
   const start=()=>this.api('matrix/start',{plan_id:prepared.plan_id,plan_sha256:prepared.plan_sha256,confirmed:true});
   try{job=await start();}catch(error){if(!/already active|already held|another.*download/i.test(error.message))throw error;
    const queued={job_id:'pending-'+accession+'-'+file.id,accession,source_url:file.url,source_name:file.name,status:'queued',local_queue:true,stage:'download',message:'已排队；前一下载完成后自动提交。应用保持打开即可，无需操作。'};this.jobs.set(queued.job_id,queued);this.emit(queued);
    (async()=>{while(!this.cancelled.has(queued.job_id)){await new Promise(r=>setTimeout(r,2200));if(this.cancelled.has(queued.job_id))return;try{const next=await start();this.jobs.delete(queued.job_id);this.emit({...queued,stage:'replaced',replacement_job_id:next.job_id,message:'已自动转为服务端下载任务'});const value={...next,accession};this.jobs.set(value.job_id,value);await this.watch(value);return;}catch(e){if(!/already active|already held|another.*download/i.test(e.message)){this.emit({...queued,status:'error',stage:'error',message:e.message});return;}}}})();return queued;
   }
  }
  const reused=job.status==='completed';job={...job,accession,source_name:file.name,reused};this.jobs.set(job.job_id,{...this.jobs.get(job.job_id),...job});this.emit({...job,stage:'download',message:reused?'复用已完成下载；保留原 SHA-256，远端版本未重新核验。':'已自动提交下载；后台继续，无需留在矩阵页面。'});
  this.watch(job).catch(error=>this.emit({...job,stage:'error',message:error.message}));return job;
 }
 cancelQueued(id){this.cancelled.add(id);const job=this.jobs.get(id);if(job){this.jobs.delete(id);this.emit({...job,status:'cancelled',stage:'download'});}}
 async watch(job){
  if(this.jobs.get(job.job_id)?._watching)return;this.jobs.set(job.job_id,{...job,_watching:true});
  while(true){const current=await this.api('matrix/status',{job_id:job.job_id});this.emit({...current,accession:job.accession,stage:'download'});
   if(current.status==='completed'){await this.onComplete({...current,accession:job.accession});return;}
   if(!['queued','running','cancel_requested'].includes(current.status)){if(['failed','error'].includes(current.status))throw Error(current.error||'下载失败；已保留任务记录。');return;}
   await new Promise(r=>setTimeout(r,1600));
  }
 }
}
export function installAgentPipeline(win=window,transport=fetch){
 const api=async(op,body)=>{const r=await transport('/api/public-data/'+op,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),credentials:'omit',redirect:'error'}),data=await r.json();if(!r.ok)throw Error(data.error||'数据任务请求失败');return data;};
 const pipeline=new AgentPipeline({api,budget:()=>Number(document.getElementById('matrix-budget')?.value||5)*1024**3,emit:detail=>win.dispatchEvent(new CustomEvent('emp:agent-flow',{detail})),onComplete:async job=>{
  if(job.accession.startsWith('GSE')){let annotations=null;try{const preview=await api('matrix/preview',{job_id:job.job_id});annotations=await api('processed/annotations',{accession:job.accession,columns:preview.inspection.column_labels});}catch(error){win.dispatchEvent(new CustomEvent('emp:agent-flow',{detail:{...job,stage:'metadata',message:'下载完成；样本元数据待重试：'+error.message}}));}
   win.dispatchEvent(new CustomEvent('emp:agent-download-ready',{detail:{job,annotations}}));
  }else win.dispatchEvent(new CustomEvent('emp:agent-flow',{detail:{...job,stage:'completed',message:'蛋白质组处理表已下载，可保存并导入蛋白质组页面。'}}));
 }});win.empAgentPipeline=pipeline;return pipeline;
}
