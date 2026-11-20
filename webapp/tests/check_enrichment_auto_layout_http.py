"""Isolated ORA fixture; exercises the real UI, API and physical vector exports."""
import csv,functools,json,os,subprocess,sys,tempfile,threading,shutil
from pathlib import Path
from http.server import SimpleHTTPRequestHandler,ThreadingHTTPServer
from pypdf import PdfReader
ROOT=Path.cwd();sys.path.insert(0,str(ROOT/'webapp/tests'))
from isolated_r_api import isolated_r_api,api_environment
with tempfile.TemporaryDirectory(prefix='emp-enrich-layout-') as temp:
 work=Path(temp);env=api_environment(work);counts=work/'counts.csv';meta=work/'meta.csv'
 counts.write_text('feature,A,B,C,D\n'+''.join(f'Gene{i},{i+10},{2*i+12},{3*i+13},{4*i+15}\n' for i in range(1,31)));meta.write_text('sample,Group\nA,Control\nB,Control\nC,Treatment\nD,Treatment\n')
 with isolated_r_api(ROOT,str(ROOT/'.local_run/r-runtime/bin/Rscript'),work,env) as base:
  data=json.loads(subprocess.check_output(['curl','-fsS','-F','data_file=@'+str(counts),'-F','metadata_file=@'+str(meta),'-F','data_type=normal','-F','experiment_name=synthetic_enrichment_layout',base+'/import']));assert data['success'];sid=data['session_id'];job='20261119010000.000-enrich01'
  terms=['Viral protein interaction with cytokine and cytokine receptor','Cytokine-cytokine receptor interaction','Complement and coagulation cascades','Neuroactive ligand-receptor interaction','IL-17 signaling pathway','Lipid and atherosclerosis','Chemokine signaling pathway','Rheumatoid arthritis','Wnt signaling pathway','Influenza A','Amoebiasis','Pertussis','Malaria','Apoptosis','TNF signaling pathway','NF-kappa B signaling pathway','C-type lectin receptor signaling pathway','Cell adhesion molecules','Natural killer cell mediated cytotoxicity','Antigen processing and presentation']
  fixture=work/'terms.csv'
  with fixture.open('w') as f:
   writer=csv.writer(f);writer.writerow(['ID','Description','GeneRatio','Count','p.adjust']);writer.writerows((f'Term{i}',term,f'{i}/100',i,i/1000) for i,term in enumerate(terms,1))
  jobs=work/'jobs';jobs.mkdir(exist_ok=True);(jobs/(job+'.json')).write_text(json.dumps(dict(id=job,status='done',kind='enrichment',session_id=sid,experiment='synthetic_enrichment_layout',omics='transcriptomics',owner_id='local')))
  subprocess.run([str(ROOT/'.local_run/r-runtime/bin/Rscript'),'-e',"a<-commandArgs(TRUE);saveRDS(list(data=read.csv(a[1],check.names=FALSE),database='Synthetic_ORA'),a[2])",str(fixture),str(jobs/(job+'.result'))],env=env,check=True)
  class Quiet(SimpleHTTPRequestHandler):
   def log_message(self,*args):pass
  with ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=str(ROOT/'webapp/frontend'))) as server:
   threading.Thread(target=server.serve_forever,daemon=True).start()
   try:subprocess.run([os.environ['EMP_NODE'],str(ROOT/'webapp/tests/check_enrichment_auto_layout_browser.cjs'),base,f'http://127.0.0.1:{server.server_port}',sid,job,str(work)],check=True)
   finally:server.shutdown()
 target=ROOT/'.local_run/verification/enrichment-complete-layout';target.mkdir(parents=True,exist_ok=True)
 for path in work.glob('browser-*'):shutil.copyfile(path,target/path.name)
 page=PdfReader(work/'browser-enrichment.pdf').pages[0];assert abs(float(page.mediabox.width)-216)<.02 and float(page.mediabox.height)>216
 text=page.extract_text();assert 'Enrichment' in text and 'Count' in text
 assert not any(obj.get_object().get('/Subtype')=='/Image' for obj in page.get('/Resources',{}).get('/XObject',{}).values())
 with (work/'browser-enrichment.csv').open() as f:rows=list(csv.DictReader(f))
 assert len(rows)==20 and [r['Description'] for r in rows]==terms
 assert '…' not in text
 normalized=''.join(text.split())
 for term in terms:assert ''.join(term.split()) in normalized,term
 print('PASS complete vector PDF: all 20 full names visible, no ellipses or raster images, width preserved and suggested height explicitly accepted; outputs:',target,flush=True)
