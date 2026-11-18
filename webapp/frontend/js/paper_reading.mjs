// Allocate the text budget across sections, returning unused space from shorter sections.
export function sectionExcerpts(sections, budget=22200) {
  const full=sections.join('\n\n');
  if(full.length<=budget)return {text:full,excerpt:false};
  const allowance=Array(sections.length).fill(0);
  let remaining=budget-2*(sections.length-1);
  let count=sections.length;
  for (const {n,index} of sections.map((text,index)=>({n:text.length,index})).sort((a,b)=>a.n-b.n)) {
    allowance[index]=Math.max(0,Math.min(n,Math.floor(remaining/count)));
    remaining-=allowance[index];
    count--;
  }
  const pieces=sections.map((text,index)=>{
    const limit=allowance[index];
    if(text.length<=limit)return text;
    if(limit<50)return text.slice(0,limit);
    const head=Math.floor((limit-5)*0.7);
    return text.slice(0,head)+' […] '+text.slice(-(limit-5-head));
  });
  return {text:pieces.join('\n\n'),excerpt:true};
}

// Use only the PMC accession returned for the selected PubMed record.
export async function openPmcText(id) {
  if (!/^PMC[1-9]\d{0,11}$/.test(id)) throw Error('Invalid PMCID');
  const url = new URL('https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi');
  url.search = new URLSearchParams({db:'pmc', id:id.slice(3), retmode:'xml'});
  const response = await fetch(url, {credentials:'omit', redirect:'error', signal:AbortSignal.timeout(20000)});
  if (!response.ok) throw Error('PMC HTTP ' + response.status);
  const reader = response.body.getReader(), decoder = new TextDecoder();
  let xml = '', size = 0;
  for (;;) {
    const {value, done} = await reader.read();
    if (done) break;
    size += value.length;
    if (size > 8 * 1024 * 1024) { await reader.cancel(); throw Error('PMC XML > 8 MiB'); }
    xml += decoder.decode(value, {stream:true});
  }
  xml += decoder.decode();
  const parsed = new DOMParser().parseFromString(xml, 'application/xml');
  const body = parsed.querySelector('article > body');
  if (!body || parsed.querySelector('parsererror')) throw Error('PMC full text unavailable');
  const groups=new Map();
  for(const node of body.querySelectorAll('title, p')){
    if(node.parentElement.closest('p'))continue;
    let group=node.closest('sec');
    while(group?.parentElement.closest('sec'))group=group.parentElement.closest('sec');
    const text=node.textContent.trim();
    if(!text)continue;
    if(!groups.has(group))groups.set(group,[]);
    groups.get(group).push(text);
  }
  if (!groups.size) throw Error('PMC full text unavailable');
  return sectionExcerpts([...groups.values()].map(lines=>lines.join('\n\n')));
}
