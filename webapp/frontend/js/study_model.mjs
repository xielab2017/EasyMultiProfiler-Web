// Evidence and sample labels stay local; no probabilistic assignment or fuzzy ID matching.
const clone=value=>JSON.parse(JSON.stringify(value));
export class StudyContexts{
  constructor(storage){this.storage=storage;this.jobs=new Map();try{const rows=JSON.parse(storage?.getItem('emp_study_contexts_v1')||'[]');if(Array.isArray(rows)&&JSON.stringify(rows).length<=2*1024**2)for(const [id,value]of rows.slice(-16))if(typeof id==='string'&&value&&typeof value==='object')this.jobs.set(id,value);}catch{}}
  set(jobId,value){if(typeof jobId!=='string')return;this.jobs.set(jobId,clone(value));if(this.jobs.size>16)this.jobs.delete(this.jobs.keys().next().value);try{let rows=[...this.jobs];if(JSON.stringify(rows).length>2*1024**2)rows=rows.map(([id,v])=>[id,{...v,annotations:null}]);this.storage?.setItem('emp_study_contexts_v1',JSON.stringify(rows));}catch{}}
  get(jobId){const value=this.jobs.get(jobId);return value?clone(value):null;}
}
let storage;try{if(typeof window!=='undefined')storage=window.localStorage;}catch{}
export const studyContexts=new StudyContexts(storage);
export function paperSummary(extraction={},filename=''){
  const doi=(extraction.primary_doi_candidates||extraction.dois||[]).find(row=>row.pages?.includes(1))?.doi||extraction.dois?.[0]?.doi||'';
  return {title:extraction.title||extraction.paper_title_candidate||'',doi,pmid:extraction.pmid||'',filename,
    pdf_sha256:extraction.pdf_sha256||'',source_url:extraction.url||'',
    evidence:(extraction.evidence||[]).slice(0,12).map(row=>({page:row.page,text:String(row.text||'').slice(0,700),kind:row.kind||'study_design'}))};
}
function fieldsFor(sample){
  const fields={};
  for(const line of sample?.characteristics||[]){const index=line.indexOf(':');if(index<1)continue;const key=line.slice(0,index).trim(),value=line.slice(index+1).trim();if(!value)continue;(fields[key]??=[]).push(value);}
  return fields;
}
export function annotationFields(records=[]){
  const fields=new Map();for(const sample of records)for(const [key,values]of Object.entries(fieldsFor(sample))){const entry=fields.get(key)||{name:key,samples:0,values:new Set()};entry.samples++;for(const value of values)entry.values.add(value);fields.set(key,entry);}
  return [...fields.values()].map(row=>({...row,values:[...row.values]}));
}
export function annotationRows(sampleIds,annotations={},field=''){
  return sampleIds.map(id=>{
    const match=(annotations.matches||[]).find(row=>row.column===id);
    const sample=(match?.status==='exact'||(match?.status==='manual'&&match.confirmed===true))?match.sample:(annotations.records||[]).find(row=>row.accession===id);
    const values=[...new Set(fieldsFor(sample)[field]||[])];
    return{id,group:values.length===1?values[0]:'',gsm:sample?.accession||'',match:sample?(match?.status==='manual'?'manual':'exact'):match?.status||'unmatched',
      evidence:field&&sample?(sample.characteristics||[]).filter(line=>line.slice(0,line.indexOf(':')).trim()===field).join(' | '):'',
      title:sample?.title||'',ambiguous:values.length>1};
  });
}
export function comparisonPairs(samples,mode,reference,targets=[]){
  if(!Array.isArray(samples)||!samples.length||samples.some(row=>!row.id||!row.group?.trim()))throw Error('missing_groups');
  if(new Set(samples.map(row=>row.id)).size!==samples.length)throw Error('duplicate_samples');
  const groups=[...new Set(samples.map(row=>row.group))];let pairs=[];
  if(groups.length<2||groups.length>12)throw Error('group_count');
  if(mode==='all_pairs')for(let i=0;i<groups.length;i++)for(let j=i+1;j<groups.length;j++)pairs.push({test:groups[j],reference:groups[i]});
  else{
    if(!groups.includes(reference))throw Error('reference');
    if(!Array.isArray(targets)||!targets.length||new Set(targets).size!==targets.length||targets.some(test=>test===reference||!groups.includes(test)))throw Error('targets');
    if(mode==='one_to_one'&&targets.length!==1)throw Error('targets');
    if(!['one_to_one','one_to_many'].includes(mode))throw Error('mode');
    pairs=targets.map(test=>({test,reference}));
  }
  if(pairs.length>20)throw Error('contrast_limit');return pairs;
}
