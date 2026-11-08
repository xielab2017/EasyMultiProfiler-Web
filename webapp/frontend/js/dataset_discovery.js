import {parseDiscovery,geoCandidates,repositoryCandidate} from './discovery_model.mjs';
import {paperSummary} from './study_model.mjs';
import {getLocale} from './locale.js?v=nav-language-20261108';
const TEXT={
 title:['论文与组学数据工作区','Paper and omics data workspace'],
 hint:['输入数据库编号、DOI、PMID 或论文题目，也可以上传 PDF。系统按论文中实际的数据来源提供后续入口；GEO 文件可在本页审核下载，其他数据库先查看其文件与访问条件。','Enter repository accessions, DOI, PMID or a paper title, or upload PDFs. Follow the actual sources. Review and download GEO files here; inspect files and access conditions at other repositories.'],
 placeholder:['例如：GSE60450、PXD000001、MTBLS1、PRJNA123456；或 DOI / PMID / 论文题目','e.g. GSE60450, PXD000001, MTBLS1, PRJNA123456; or DOI / PMID / paper title'],
 mode:['检索范围','Search scope'],auto:['编号 / 论文','Accession / paper'],geo:['GEO 关键词','GEO keywords'],
 search:['查询数据来源','Find data sources'],stop:['停止后续查询','Stop remaining queries'],export:['导出检索与论文证据','Export discovery and paper evidence'],
 pdf:['上传多篇论文，逐篇提取文章信息','Upload papers to extract information'],file:['选择一篇或多篇 PDF','Choose one or more PDFs'],none:['未选择文件','No file selected'],clear:['清空当前文章与数据选择','Clear current paper and data selection'],
 remove:['移除当前 PDF','Remove current PDF'],
 pdfHint:['应用服务提取题目候选、DOI、数据声明、编号和分组相关原文，并保留页码。最多 {max} MiB / 前 100 页；不发送给模型，不做 OCR。','The application service extracts title candidates, DOIs, data statements, accessions and study-design excerpts with page evidence. At most {max} MiB / first 100 pages; no model transmission or OCR.'],
 invalid:['请输入有效编号或论文题目，或先选择 PDF。','Enter an accession or paper title, or choose a PDF first.'],limit:['一次最多查询 10 个不同的 GEO。','Query at most 10 distinct GEO accessions at once.'],
 loading:['正在查询公开元数据…','Searching public metadata…'],pdfLoading:['正在提取 PDF 文章信息与数据声明…','Extracting paper information and data statements from PDF…'],
 pdfDone:['PDF 已读取：检查 {pages} 页，找到 {count} 个数据编号。请核对下方文章信息。','PDF read: inspected {pages} pages and found {count} accessions. Review the paper information below.'],
 progress:['已完成 {done}/{total} 个 GEO 查询。','Completed {done}/{total} GEO lookups.'],cancelled:['已停止后续查询；当前请求可能仍会完成。','Remaining queries stopped; the current request may still finish.'],
 failed:['操作未完成：{error}。可重试；已保留当前输入。','Operation incomplete: {error}. Retry; the current input is retained.'],
 articles:['请选择匹配论文，再读取摘要中的数据编号。','Select the matching paper, then inspect its abstract for accessions.'],abstract:['读取论文信息与摘要','Read paper information and abstract'],
 pick:['选择文件与下载','Choose files and download'],noPaper:['PubMed 未定位到匹配论文。可改用完整题目、PMID 或 PDF；这不表示没有公开数据。','No matching PubMed paper located. Try a full title, PMID or PDF; this does not establish absence of public data.'],
 paper:['文章信息与来源证据（待核对）','Paper information and source evidence (review pending)'],unknownTitle:['PDF 未提供可靠题目元数据；可查看首页文字。','No reliable PDF title metadata; inspect the first-page text.'],
 evidence:['查看数据声明与实验设计原文','Inspect data statements and study-design excerpts'],firstPage:['查看 PDF 首页提取文字','Inspect first-page extracted text'],
 source:['证据来源','Evidence source'],candidate:['数据编号来自文章原文，尚未证明文件可用或样本分组正确。','Accessions are literal paper mentions; file availability and sample grouping remain unverified.'],
 noGse:['已识别其他数据来源，请打开对应数据库核对文件、访问权限和数据类型；也可请 AI 指导。','Other data sources were identified. Inspect the repository files, access conditions and data types, or ask AI for guidance.'],
 noAccessions:['暂未识别到数据库编号。请查看论文数据声明及补充材料，或请 AI 根据已提供的公开论文信息指导检索；这不代表没有公开数据。','No repository accession was identified. Inspect the data availability statement and supplements, or ask AI for search guidance using public paper information. This does not mean data are unavailable.'],
 noText:['PDF 没有可提取的文字，可能是扫描件；当前不做 OCR。','No extractable PDF text; this may be a scanned document. OCR is unavailable.'],
 resolve:['继续查询候选 GEO 文件','Continue to candidate GEO files'],open:['打开数据库并按此编号检索','Open repository and search this accession'],doi:['按此 DOI 查论文','Find the paper by this DOI'],
 original:['补充文件候选：{count}；文件内容与数据尺度待核对。','Supplementary-file candidates: {count}; contents and data scale need review.'],
 empty:['未找到 Series 级补充文件；数据可能位于其他入口。','No Series-level supplementary files; data may be available elsewhere.'],
 pdfSize:['PDF 文件不能超过 {max} MiB。','PDF files must be at most {max} MiB.'],candidateLimit:['共 {count} 个 GSE，每次查询前 10 个；其余可分批输入。','Found {count} GSE accessions; query the first 10 now and enter the remainder in another batch.'],page:['第 {pages} 页','page {pages}'],
 noInference:['原文用于核对研究设计；不会从论文描述或文件名自动猜测每个样本的组别。','Excerpts support design review; individual sample groups are never guessed from paper descriptions or filenames.'],
 unrelated:['该编号未出现在当前论文提取结果中，下载时不自动关联这篇论文。','This accession is absent from the current paper extraction; the paper will not be attached to its download automatically.'],
 aiGuide:['请 AI 指导检索与分析','Ask AI for data and analysis guidance'],
 repositoryNote:['编号是论文原文或用户输入的候选来源；文件是否公开、是否为可分析矩阵及样本分组均需核对。非 GEO 文件通过官方服务器或数据库页面下载，不会自动下载。','Accessions are candidates from the paper or user input. Confirm file access, matrix suitability and sample groups. Non-GEO files are downloaded from official servers or repository pages, not automatically.'],
 prideFiles:['查看 PRIDE 表格文件','Find PRIDE table files'],prideNotice:['这些是 PRIDE 发布的候选表格，尚未确认是样本矩阵；点击文件名从官方服务器下载，核对后可手动上传到工作台。','These are candidate tables published by PRIDE, not verified sample matrices. Download from the official server and upload to the workbench after review.'],prideEmpty:['本次检查的文件中没有找到候选表格，请在官方项目页检查其他文件或分页。','No candidate table was found in this bounded scan; inspect other files or pages at PRIDE.'],prideMore:['仅检查前 100 个文件，结果可能不完整；请同时查看官方项目页。','Only the first 100 files were checked; results may be incomplete. Also inspect the official project page.'],
};
const tr=(key,vars={})=>{let value=TEXT[key][['zh','zh-TW'].includes(getLocale())?0:1];for(const [k,v]of Object.entries(vars))value=value.replaceAll(`{${k}}`,String(v));return value;};
const make=(tag,text,cls)=>{const el=document.createElement(tag);if(text!==undefined)el.textContent=text;if(cls)el.className=cls;return el;};
const root=document.getElementById('discovery-entry')||document.getElementById('dataset-discovery');
if(root){
 let pdfMaxBytes=100*1024**2;
 let generation=0,pdfBatch=0,working=false,stopped=false,paperResults=null,extraction=null,pdfExtraction=null,studies=[],statusMessage=null,currentFile=null;
 const record={schema:2,requests:[],analysis_executed:false,data_files_downloaded:false};
 const heading=make('h2'),hint=make('p',undefined,'hint'),input=make('textarea');input.id='discovery-input';input.rows=3;input.maxLength=2000;
 const modeLabel=make('label'),modeText=make('span'),mode=make('select');mode.id='discovery-mode';for(const value of ['auto','geo']){const option=make('option');option.value=value;mode.append(option);}mode.value='auto';modeLabel.append(modeText,mode);
 const controls=make('div',undefined,'wb-actions'),search=make('button',undefined,'btn btn-primary'),stop=make('button',undefined,'btn btn-outline'),exportButton=make('button',undefined,'btn btn-outline');for(const button of [search,stop,exportButton]){button.type='button';controls.append(button);}search.id='discovery-search';stop.disabled=true;
 const pdfHeading=make('h3'),pdfInput=make('input');pdfInput.id='discovery-pdf';pdfInput.type='file';pdfInput.multiple=true;pdfInput.accept='.pdf,application/pdf';pdfInput.className='wb-file-input';
 const pdfLabel=make('label',undefined,'btn btn-outline wb-file-picker');pdfLabel.htmlFor=pdfInput.id;const filename=make('span'),clear=make('button',undefined,'btn btn-outline'),pdfHint=make('p',undefined,'hint');clear.type='button';clear.hidden=false;
 const removePDF=make('button',undefined,'btn btn-outline');removePDF.type='button';removePDF.id='discovery-remove-pdf';removePDF.hidden=true;
 const paperList=make('section');paperList.id='discovery-paper-list';const uploaded=[];
 const status=make('p');status.id='discovery-status';status.setAttribute('role','status');
 const articles=make('div'),paper=make('section',undefined,'discovery-paper'),candidates=make('div'),results=make('div');paper.id='discovery-paper';results.id='discovery-results';let manualCandidates=[];
 controls.append(clear);
 root.append(heading,hint,input,modeLabel,controls,pdfHeading,pdfInput,pdfLabel,filename,removePDF,pdfHint,paperList,status,articles,paper,candidates,results);
 const currentPaper=()=>paperSummary({...pdfExtraction,...extraction,evidence:[...(pdfExtraction?.evidence||[]),...(extraction?.evidence||[])]},currentFile?.name||'');
 async function api(op,body,extra={}){const response=await fetch('/api/public-data/'+op,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),credentials:'omit',redirect:'error',...extra});const data=await response.json();if(!response.ok)throw Error(data.error||`HTTP ${response.status}`);return data;}
 function setStatus(key,vars={}){statusMessage=key?{key,vars}:null;status.textContent=key?tr(key,vars):'';}
 function labels(){
  heading.textContent=tr('title');hint.textContent=tr('hint');input.placeholder=tr('placeholder');input.setAttribute('aria-label',tr('title'));modeText.textContent=tr('mode');for(const option of mode.children)option.textContent=tr(option.value);
  search.textContent=tr('search');stop.textContent=tr('stop');pdfHeading.textContent=tr('pdf');pdfLabel.textContent=tr('file');clear.textContent=tr('clear');removePDF.textContent=tr('remove');pdfHint.textContent=tr('pdfHint',{max:pdfMaxBytes/1024**2});if(!pdfInput.files?.length)filename.textContent=tr('none');exportButton.textContent=tr('export');
  renderArticles();renderPaper();renderCandidates();renderStudies();renderPaperList();if(statusMessage)status.textContent=tr(statusMessage.key,statusMessage.vars);
 }
 function reset(){generation++;stopped=true;paperResults=null;studies=[];articles.replaceChildren();results.replaceChildren();}
 const paperAccessions=()=>[...(pdfExtraction?.accessions||[]),...(extraction?.accessions||[])].map(row=>row.accession);
 function pick(item){window.dispatchEvent(new CustomEvent('emp:matrix-pick',{detail:{accession:item.accession,result:item.result,paper:paperAccessions().includes(item.accession)?currentPaper():null}}));document.getElementById('matrix-panel')?.scrollIntoView({behavior:'smooth',block:'start'});}
 function renderStudies(){results.replaceChildren();for(const item of studies){const card=make('article',undefined,'discovery-study');card.append(make('h4',item.accession));if(item.error)card.append(make('p',item.error));else if(item.result){const m=item.result.manifest;card.append(make('p',m.title),make('p',tr('original',{count:m.files.length}),'hint'));if((pdfExtraction||extraction)&&!paperAccessions().includes(item.accession))card.append(make('p',tr('unrelated'),'hint'));if(!m.files.length)card.append(make('p',tr('empty'),'hint'));const button=make('button',tr('pick'),'btn btn-outline');button.type='button';button.onclick=()=>pick(item);card.append(button);}else card.append(make('p',tr('loading')));results.append(card);}}
 async function lookup(accessions,version){
  studies=accessions.map(accession=>({accession}));renderStudies();let done=0;
  for(const item of studies){if(stopped||version!==generation)break;try{const data=await api('processed/resolve',{accession:item.accession});if(version!==generation)return;item.result=data;record.requests.push({kind:'geo',accession:item.accession,source:data.manifest.source||null,file_count:data.manifest.files.length});}catch(error){if(version!==generation)return;item.error=error.message;record.requests.push({kind:'geo',accession:item.accession,error:error.message});}done++;renderStudies();setStatus('progress',{done,total:accessions.length});}
  if(stopped&&version===generation)setStatus('cancelled');
 }
 async function readAbstract(pmid,version){const data=await api('papers/abstract',{pmid});if(version!==generation)return;extraction=data;record.requests.push({kind:'abstract',pmid,source_url:data.url,candidates:data.accessions});window.dispatchEvent(new CustomEvent('emp:paper-archive',{detail:currentPaper()}));renderPaper();renderCandidates();setStatus();}
 function renderArticles(){articles.replaceChildren();for(const article of paperResults?.articles||[]){const card=make('article',undefined,'discovery-study');const link=make('a',article.title);link.href=`https://pubmed.ncbi.nlm.nih.gov/${article.pmid}/`;link.target='_blank';link.rel='noopener';card.append(link,make('p',`PMID ${article.pmid} · ${article.date||''}`));const button=make('button',tr('abstract'),'btn btn-outline');button.type='button';button.onclick=()=>perform(version=>readAbstract(article.pmid,version));card.append(button);articles.append(card);}}
 function renderPaper(){
  paper.replaceChildren();paper.hidden=!extraction&&!pdfExtraction;if(paper.hidden)return;const context=currentPaper();paper.append(make('h3',tr('paper')),make('strong',context.title||tr('unknownTitle')));
  if(context.pdf_sha256)paper.append(make('p','SHA-256 '+context.pdf_sha256,'discovery-file'));
  const dois=pdfExtraction?.primary_doi_candidates?.length?pdfExtraction.primary_doi_candidates:(extraction?.dois||[]).slice(0,3);
  for(const row of dois){const button=make('button',tr('doi')+': '+row.doi,'btn btn-outline');button.type='button';button.onclick=()=>{input.value=row.doi;search.click();};paper.append(button);}
  if(context.evidence.length){const details=make('details'),summary=make('summary',tr('evidence'));details.append(summary);for(const row of context.evidence)details.append(make('p',tr('page',{pages:row.page})+' · '+row.text));paper.append(details);}
  if(pdfExtraction?.first_page_preview){const details=make('details');details.append(make('summary',tr('firstPage')),make('p',pdfExtraction.first_page_preview));paper.append(details);}
  if(extraction?.abstract)paper.append(make('p',extraction.abstract.slice(0,1800),'hint'));
  paper.append(make('p',tr('noInference'),'hint'));
 }
 function renderCandidates(){
  candidates.replaceChildren();const sources=[...(pdfExtraction?.accessions||[]),...(extraction?.accessions||[]),...manualCandidates];if(!sources.length&&!extraction&&!pdfExtraction&&!manualCandidates.length)return;const unique=[...new Map(sources.map(item=>[item.accession,item])).values()];const data={accessions:unique},mentions=geoCandidates(data);candidates.append(make('p',tr(unique.length?(mentions.length?'candidate':'noGse'):'noAccessions'),'hint'));
  for(const item of unique){candidates.append(make('p',`${item.accession} · ${item.kind||''} · ${item.pages?.length?tr('page',{pages:item.pages.join(', ')}):(item.sections||[]).join(', ')}`));
   if(!/^GSE\d+$/.test(item.accession)){const link=make('a',tr('open')+': '+item.accession,'btn btn-outline');try{const verified=repositoryCandidate(item.accession);link.href=verified.url;link.target='_blank';link.rel='noopener';candidates.append(link);}catch{/* Unknown identifiers cannot supply external links. */}}
   if(/^PXD\d{5,9}$/.test(item.accession)){const button=make('button',tr('prideFiles'),'btn btn-outline'),files=make('div');button.type='button';button.onclick=()=>perform(async version=>{const data=await api('repositories/pride-files',{accession:item.accession});if(version!==generation)return;files.replaceChildren();files.append(make('p',tr(data.files.length?'prideNotice':'prideEmpty'),'hint'));for(const file of data.files){let url;try{url=new URL(file.url);}catch{continue;}if(url.protocol!=='https:'||url.hostname!=='ftp.pride.ebi.ac.uk')continue;const link=make('a',`${file.name} · ${file.size_bytes??'?'} bytes · ${file.category}`,'btn btn-outline');link.href=url.href;link.target='_blank';link.rel='noopener';files.append(link);}if(data.may_have_more)files.append(make('p',tr('prideMore'),'hint'));setStatus();});candidates.append(button,files);}
  }
  if(pdfExtraction?.text_extracted===false)candidates.append(make('p',tr('noText'),'hint'));
  if(unique.length)candidates.append(make('p',tr('repositoryNote'),'hint'));
  const ai=make('button',tr('aiGuide'),'btn btn-outline');ai.type='button';ai.id='discovery-ai-guide';ai.onclick=()=>{const context=currentPaper(),allSources=[...unique,...uploaded.flatMap(row=>row.data.accessions||[])],ids=[...new Map(allSources.map(row=>[row.accession,row])).values()].map(row=>`${row.kind||'repository'}: ${row.accession}`).join('; '),papers=uploaded.map(row=>paperSummary(row.data,row.file.name)).map(row=>[row.title,row.doi].filter(Boolean).join(' / ')).filter(Boolean).join('; ');const q=document.getElementById('wb-question');document.querySelector('.nav-item[data-page="workbench"]')?.click();if(q){q.value=tr('aiGuide')+'：'+[context.title&&`Title: ${context.title}`,context.doi&&`DOI: ${context.doi}`,papers&&`Papers: ${papers}`,ids&&`Accessions: ${ids}`].filter(Boolean).join(' · ')+(['zh','zh-TW'].includes(getLocale())?'。请按实际数据库指导检索文件、确认公开或受限访问、判断原始数据和处理矩阵、核对样本与分组，并提出适用的组学分析流程。明确哪些步骤需要人工确认，不要假设存在 GSE 或已下载。':'. Guide repository-specific file discovery, access conditions, raw versus processed data, sample review and a suitable workflow. Do not assume GSE or completed downloads.');q.dispatchEvent(new Event('input',{bubbles:true}));const details=q.closest('details');if(details)details.open=true;q.focus();}};candidates.append(ai);
  if(mentions.length>10)candidates.append(make('p',tr('candidateLimit',{count:mentions.length}),'hint'));
  if(mentions.length){const button=make('button',tr('resolve'),'btn btn-primary');button.type='button';button.onclick=()=>perform(version=>lookup(mentions.slice(0,10).map(row=>row.accession),version));candidates.append(button);}
 }
 async function perform(action,loading='loading'){if(working)return;working=true;stopped=false;const version=generation;search.disabled=true;pdfInput.disabled=true;stop.disabled=false;setStatus(loading);try{await action(version);}catch(error){if(version===generation)setStatus('failed',{error:error.message});}finally{working=false;search.disabled=false;pdfInput.disabled=false;stop.disabled=true;}}
 function renderPaperList(){paperList.replaceChildren();if(!uploaded.length)return;paperList.append(make('h4',(['zh','zh-TW'].includes(getLocale())?'已读取论文：':'Papers read: ')+uploaded.length));for(const entry of uploaded){const row=make('div',undefined,'wb-actions'),open=make('button',entry.file.name,'btn btn-outline'),remove=make('button',['zh','zh-TW'].includes(getLocale())?'移除':'Remove','btn btn-outline');open.type=remove.type='button';open.onclick=()=>{reset();currentFile=entry.file;pdfExtraction=entry.data;extraction=null;filename.textContent=entry.file.name;removePDF.hidden=false;renderPaper();renderCandidates();setStatus();};remove.onclick=()=>{const i=uploaded.indexOf(entry);if(i>=0)uploaded.splice(i,1);if(currentFile===entry.file){currentFile=null;pdfExtraction=null;extraction=null;pdfInput.value='';filename.textContent=tr('none');removePDF.hidden=true;renderPaper();renderCandidates();}renderPaperList();};row.append(open,remove);paperList.append(row);}}
 async function extractPDF(file){
  if(working)return;window.dispatchEvent(new CustomEvent('emp:study-reset',{detail:{reason:'new_pdf'}}));record.requests=[];
  input.value='';manualCandidates=[];currentFile=file;filename.textContent=file.name;removePDF.hidden=false;
  reset();extraction=null;pdfExtraction=null;renderPaper();renderCandidates();if(file.size>pdfMaxBytes){setStatus('pdfSize',{max:pdfMaxBytes/1024**2});return;}
  return perform(async version=>{const data=await api('papers/pdf',null,{headers:{'Content-Type':'application/pdf'},body:file});if(version!==generation)return;pdfExtraction=data;const previous=uploaded.findIndex(row=>row.data.pdf_sha256&&row.data.pdf_sha256===data.pdf_sha256);if(previous>=0)uploaded.splice(previous,1);uploaded.push({file,data});renderPaperList();record.requests.push({kind:'local_pdf',filename:file.name,candidates:data.accessions,dois:data.dois,pdf_sha256:data.pdf_sha256});window.dispatchEvent(new CustomEvent('emp:paper-archive',{detail:currentPaper()}));renderPaper();renderCandidates();setStatus('pdfDone',{pages:data.pages_inspected??'?',count:data.accessions?.length||0});},'pdfLoading');
 }
 input.oninput=()=>{reset();setStatus();};stop.onclick=()=>{stopped=true;setStatus('cancelled');};
 search.onclick=()=>{
  if(!input.value.trim()&&pdfInput.files?.[0]){
   if(pdfExtraction){renderPaper();renderCandidates();const ids=geoCandidates(pdfExtraction).slice(0,10).map(row=>row.accession);if(ids.length)return perform(version=>lookup(ids,version));setStatus('pdfDone',{pages:pdfExtraction.pages_inspected??'?',count:pdfExtraction.accessions?.length||0});return;}
   return extractPDF(pdfInput.files[0]);
  }
  if(mode.value==='geo'){const term=input.value.trim();if(!term||term.length>300){setStatus('invalid');return;}window.dispatchEvent(new CustomEvent('emp:matrix-search',{detail:{term,paper:currentPaper(),paperAccessions:paperAccessions()}}));return;}
  let parsed;try{parsed=parseDiscovery(input.value);}catch(error){setStatus(error.message==='limit'?'limit':'invalid');return;}
  const samePaper=parsed.kind==='doi'&&(pdfExtraction?.primary_doi_candidates||pdfExtraction?.dois||[]).some(row=>row.doi?.toLowerCase()===parsed.doi)||parsed.kind==='pmid'&&extraction?.pmid===parsed.pmid;
  window.dispatchEvent(new CustomEvent('emp:study-reset',{detail:{reason:'new_query'}}));
  if(parsed.kind!=='geo'&&!samePaper){pdfExtraction=null;extraction=null;pdfInput.value='';currentFile=null;removePDF.hidden=true;filename.textContent=tr('none');record.requests=[];renderPaper();renderCandidates();}
  reset();
  return perform(async version=>{record.input=parsed;record.started_at=new Date().toISOString();if(parsed.kind==='geo'){manualCandidates=[];await lookup(parsed.accessions,version);return;}if(parsed.kind==='repositories'){manualCandidates=parsed.accessions.map(repositoryCandidate);renderCandidates();const geo=parsed.accessions.filter(id=>id.startsWith('GSE'));if(geo.length)await lookup(geo,version);else setStatus();return;}manualCandidates=[];if(parsed.kind==='pmid'){await readAbstract(parsed.pmid,version);return;}
   const data=await api('papers/search',{term:parsed.term});if(version!==generation)return;paperResults=parsed.kind==='doi'?{...data,articles:(data.articles||[]).filter(article=>(article.dois||[]).some(doi=>doi.toLowerCase()===parsed.doi))}:data;record.requests.push({kind:parsed.kind,term:parsed.term,pmids:paperResults.articles.map(article=>article.pmid)});setStatus(paperResults.articles.length?'articles':'noPaper');renderArticles();});
 };
 pdfInput.onchange=async()=>{const batch=++pdfBatch;const files=Array.from(pdfInput.files||[]);for(const file of files){if(batch!==pdfBatch)break;clear.hidden=false;await extractPDF(file);}};
 clear.onclick=()=>{pdfBatch++;window.dispatchEvent(new CustomEvent('emp:study-reset',{detail:{reason:'clear'}}));reset();record.requests=[];input.value='';pdfInput.value='';currentFile=null;manualCandidates=[];removePDF.hidden=true;filename.textContent=tr('none');pdfExtraction=null;extraction=null;clear.hidden=false;renderPaper();renderCandidates();setStatus();};
 removePDF.onclick=()=>{const entry=uploaded.find(row=>row.file===currentFile);if(entry){uploaded.splice(uploaded.indexOf(entry),1);renderPaperList();}clear.click();};
 exportButton.onclick=()=>{const value={...record,paper:currentPaper()};const url=URL.createObjectURL(new Blob([JSON.stringify(value,null,2)],{type:'application/json'}));const link=make('a');link.href=url;link.download='emp-study-discovery.json';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};
 window.addEventListener('emp:locale-change',labels);labels();
 fetch('/api/public-data/papers/capabilities',{credentials:'omit',redirect:'error'}).then(response=>response.ok?response.json():null).then(value=>{if(value&&Number.isInteger(value.max_bytes)&&value.max_bytes>=1024**2&&value.max_bytes<=512*1024**2){pdfMaxBytes=value.max_bytes;labels();}}).catch(()=>{});
}
