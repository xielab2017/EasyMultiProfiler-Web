// Persist references and public paper evidence only. Matrix values stay in tab memory.
export class ResearchProjects {
  constructor(storage){this.storage=storage;this.key='emp_research_projects_v1';try{const saved=JSON.parse(storage?.getItem(this.key)||'null');this.data=saved?.version===1&&Array.isArray(saved.projects)?saved:null;}catch{}this.data??={version:1,active:null,projects:[]};if(!this.data.projects.length)this.create('Research project');}
  save(){this.storage?.setItem(this.key,JSON.stringify(this.data));}
  current(){return this.data.projects.find(p=>p.id===this.data.active)||this.data.projects[0];}
  create(name){if(this.data.projects.length>=20)throw Error('At most 20 retained projects');const p={id:crypto.randomUUID(),name:String(name).slice(0,100),papers:[],blocks:[],mapping:[]};this.data.projects.push(p);this.data.active=p.id;this.save();return p;}
  paper(value){const p=this.current(),id=value.pdf_sha256||value.doi||value.pmid||value.title;if(!id)return;if(!p.papers.some(row=>row.id===id)){if(p.papers.length>=100)throw Error('At most 100 papers per project');p.papers.push({id,...structuredClone(value)});this.save();}}
  block(value){const p=this.current();if(value.job_id&&p.blocks.some(row=>row.job_id===value.job_id))return p.blocks.find(row=>row.job_id===value.job_id);if(p.blocks.length>=80)throw Error('At most 80 matrices per project');const row={id:'b_'+crypto.randomUUID().replaceAll('-',''),study_id:value.accession||'',omics:'unknown',scale:'unknown',selected:true,...structuredClone(value)};p.blocks.push(row);if(value.paper)this.paper(value.paper);this.save();return row;}
  export(){return structuredClone({...this.current(),schema:'emp-multistudy-project-v1',matrix_values_included:false,analysis_executed:false});}
}
