export function parseDiscovery(value){
  if(typeof value!=='string'||!value.trim()||value.length>2000)throw Error('input');
  const text=value.trim();const accessions=[...text.matchAll(/\bGSE[0-9]{1,9}\b/gi)].map(m=>m[0].toUpperCase());
  const repositoryIds=[...text.matchAll(/(?<![A-Za-z0-9_])(?:GSE[0-9]{1,9}|SRP[0-9]{1,9}|PRJ(?:NA|EB|DB|CA)[0-9]{1,9}|NMDC[0-9]{6,12}|PXD[0-9]{5,9}|MTBLS[0-9]{1,9}|(?:HRA|CRA)[0-9]{5,9}|EGA[SAD][0-9]{5,15}|E-(?:MTAB|MEXP|GEOD)-[0-9]{1,9})(?![A-Za-z0-9_])/gi)].map(m=>m[0].toUpperCase());
  const rest=text.replace(/(?<![A-Za-z0-9_])(?:GSE[0-9]{1,9}|SRP[0-9]{1,9}|PRJ(?:NA|EB|DB|CA)[0-9]{1,9}|NMDC[0-9]{6,12}|PXD[0-9]{5,9}|MTBLS[0-9]{1,9}|(?:HRA|CRA)[0-9]{5,9}|EGA[SAD][0-9]{5,15}|E-(?:MTAB|MEXP|GEOD)-[0-9]{1,9})(?![A-Za-z0-9_])/gi,'').replace(/[\s,;，；、]+/g,'');
  if(repositoryIds.length&&!rest&&repositoryIds.some(id=>!id.startsWith('GSE'))){const ids=[...new Set(repositoryIds)];if(ids.length>10)throw Error('limit');return{kind:'repositories',accessions:ids};}
  const residue=text.replace(/\bGSE[0-9]{1,9}\b/gi,'').replace(/[\s,;，；、]+/g,'');
  if(accessions.length&&!residue){const ids=[...new Set(accessions)];if(ids.length>10)throw Error('limit');return{kind:'geo',accessions:ids};}
  const pmid=text.match(/^(?:(?:PMID|PubMed)\s*:?\s*|https?:\/\/pubmed\.ncbi\.nlm\.nih\.gov\/)?([1-9][0-9]{0,11})\/?$/i);
  if(pmid)return{kind:'pmid',pmid:pmid[1]};
  const doi=text.replace(/^https?:\/\/(?:dx\.)?doi\.org\//i,'').replace(/^doi\s*:\s*/i,'').replace(/[.,;]+$/,'');
  if(/^10\.[0-9]{4,9}\/[^\s<>"\x00-\x1f]{1,200}$/i.test(doi))return{kind:'doi',doi:doi.toLowerCase(),term:doi.toLowerCase()+'[AID]'};
  if(text.length>300||/^https?:\/\//i.test(text)||/[\x00-\x08\x0b-\x1f]/.test(text))throw Error('input');
  return{kind:'title',term:text.replace(/\s+/g,' ')};
}
export function repositoryCandidate(id){
 if(/^GSE\d{1,9}$/.test(id))return {accession:id,kind:'GEO',url:`https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=${id}`};
 if(/^PXD\d{5,9}$/.test(id))return {accession:id,kind:'PRIDE',url:`https://www.ebi.ac.uk/pride/archive/projects/${id}`};
 if(/^MTBLS\d{1,9}$/.test(id))return {accession:id,kind:'MetaboLights',url:`https://www.ebi.ac.uk/metabolights/${id}`};
 if(/^HRA\d{5,9}$/.test(id))return {accession:id,kind:'GSA-Human',url:`https://ngdc.cncb.ac.cn/gsa-human/browse/${id}`};
 if(/^CRA\d{5,9}$/.test(id))return {accession:id,kind:'GSA',url:`https://ngdc.cncb.ac.cn/gsa/browse/${id}`};
 if(/^PRJCA\d{1,9}$/.test(id))return {accession:id,kind:'BioProject-CNCB',url:`https://ngdc.cncb.ac.cn/bioproject/browse/${id}`};
 if(/^PRJ(?:NA|EB|DB)\d{1,9}$/.test(id))return {accession:id,kind:'BioProject',url:`https://www.ncbi.nlm.nih.gov/bioproject/?term=${id}`};
 if(/^SRP\d{1,9}$/.test(id))return {accession:id,kind:'SRA',url:`https://www.ncbi.nlm.nih.gov/sra/?term=${id}`};
 if(/^NMDC\d{6,12}$/.test(id))return {accession:id,kind:'NMDC',url:'https://nmdc.cn/'};
 if(/^EGA[SAD]\d{5,15}$/.test(id))return {accession:id,kind:'EGA',url:'https://ega-archive.org/'};
 if(/^E-(?:MTAB|MEXP|GEOD)-\d{1,9}$/.test(id))return {accession:id,kind:'BioStudies',url:`https://www.ebi.ac.uk/biostudies/arrayexpress/studies/${id}`};
 throw Error('input');
}
export function geoCandidates(record){
  const seen=new Set();return(record.accessions||[]).filter(item=>{
    if(typeof item?.accession!=='string'||!/^GSE[0-9]{1,9}$/.test(item.accession)||seen.has(item.accession))return false;
    seen.add(item.accession);return true;
  });
}
