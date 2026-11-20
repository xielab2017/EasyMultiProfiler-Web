"""Live isolated ordination overlays, statistical audit, and vector export checks."""
import csv,functools,json,os,random,subprocess,sys,tempfile,threading,shutil
from pathlib import Path
from http.server import SimpleHTTPRequestHandler,ThreadingHTTPServer
from pypdf import PdfReader
ROOT=Path.cwd();sys.path.insert(0,str(ROOT/'webapp/tests'))
from isolated_r_api import isolated_r_api,api_environment,call
with tempfile.TemporaryDirectory(prefix='emp-ordination-') as temp:
 work=Path(temp);env=api_environment(work);rng=random.Random(233);samples=[f'S{i}' for i in range(28)];groups=['A']*8+['B']*8+['C']*7+['Single']+['']*4
 with (work/'counts.csv').open('w') as f:
  w=csv.writer(f);w.writerow(['feature']+samples)
  for i in range(36):w.writerow([f'G{i}']+[rng.randint(10,30)+(45 if (g=='A' and i<10) or (g=='B' and 10<=i<20) else 0) for g in groups])
 with (work/'meta.csv').open('w') as f:w=csv.writer(f);w.writerow(['sample','Group']);w.writerows(zip(samples,groups))
 with isolated_r_api(ROOT,str(ROOT/'.local_run/r-runtime/bin/Rscript'),work,env) as base:
  imported=json.loads(subprocess.check_output(['curl','-fsS','-F','data_file=@'+str(work/'counts.csv'),'-F','metadata_file=@'+str(work/'meta.csv'),'-F','data_type=normal','-F','experiment_name=SYNTHETIC_ORDINATION',base+'/import']));assert imported['success'];sid=imported['session_id']
  status,result=call(base,'/analyze/dimension',dict(session_id=sid,experiment='SYNTHETIC_ORDINATION',method='PCA'));assert status==200 and result['success'];frozen=json.loads(result['data'])
  class Quiet(SimpleHTTPRequestHandler):
   def log_message(self,*args):pass
  with ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=str(ROOT/'webapp/frontend'))) as server:
   threading.Thread(target=server.serve_forever,daemon=True).start()
   try:subprocess.run([os.environ['EMP_NODE'],str(ROOT/'webapp/tests/check_ordination_browser.cjs'),base,f'http://127.0.0.1:{server.server_port}',sid,str(work)],check=True)
   finally:server.shutdown()
  pdf=PdfReader(work/'grouped.pdf').pages[0];assert abs(float(pdf.mediabox.width)-180/25.4*72)<.02 and abs(float(pdf.mediabox.height)-160/25.4*72)<.02
  assert not any(o.get_object().get('/Subtype')=='/Image' for o in pdf.get('/Resources',{}).get('/XObject',{}).values())
  text=pdf.extract_text();assert text.count('Group')==1,text;assert 'Overall P' in text and 'Brackets: pairwise P' in text and 'BH q' in text and 'data ellipse' in text and 'Missing (n=4)' in text
  manifest=json.loads((work/'grouped.json').read_text());assert len(manifest['axis_statistics'])==2 and len(manifest['pairwise_statistics'])==6 and manifest['analysis_recomputed'] is False
  plotted=list(csv.DictReader((work/'grouped.csv').open()));assert len(plotted)==len(frozen)==28
  for a,b in zip(plotted,frozen):assert abs(float(a['x'])-b['PC1'])<1e-10 and abs(float(a['y'])-b['PC2'])<1e-10
 target=ROOT/'.local_run/verification/ordination-browser';target.mkdir(parents=True,exist_ok=True)
 for f in work.glob('grouped.*'):shutil.copyfile(f,target/f.name)
 shutil.copyfile(work/'browser.png',target/'browser.png');print('PASS physical vector PDF, one group legend, ellipse and test definitions, exact frozen coordinates and missing-label audit; proofs:',target,flush=True)
