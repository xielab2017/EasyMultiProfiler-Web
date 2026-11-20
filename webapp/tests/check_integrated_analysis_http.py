"""All supported methods and the native Run -> frozen result -> figure workflow."""
import csv,functools,json,os,random,subprocess,sys,tempfile,threading,shutil
from pathlib import Path
from http.server import SimpleHTTPRequestHandler,ThreadingHTTPServer
from pypdf import PdfReader
ROOT=Path.cwd();sys.path.insert(0,str(ROOT/'webapp/tests'))
from isolated_r_api import isolated_r_api,api_environment,call
methods={'dimension':['PCA','PCoA','UMAP','tSNE','MDS'],'correlation':['spearman','pearson','kendall'],'cluster':['hclust','kmeans','pam'],'marker':['randomForest','LEfSe','ANCOM','lasso','xgboost']}
with tempfile.TemporaryDirectory(prefix='emp-integrated-figures-') as temp:
 work=Path(temp);env=api_environment(work);counts=work/'counts.csv';meta=work/'meta.csv';rng=random.Random(712);samples=[f'S{i}' for i in range(1,19)];groups=['A']*6+['B']*6+['C']*6
 with counts.open('w') as f:
  w=csv.writer(f);w.writerow(['feature']+samples)
  for i in range(1,37):w.writerow([f'Gene{i}']+[rng.randint(10,30)+(60 if (i<=10 and g=='A') or (10<i<=20 and g=='B') else 0) for g in groups])
 with meta.open('w') as f:w=csv.writer(f);w.writerow(['sample','Group']);w.writerows(zip(samples,groups))
 with isolated_r_api(ROOT,str(ROOT/'.local_run/r-runtime/bin/Rscript'),work,env) as base:
  result=json.loads(subprocess.check_output(['curl','-fsS','-F','data_file=@'+str(counts),'-F','metadata_file=@'+str(meta),'-F','data_type=normal','-F','experiment_name=synthetic_integrated_figures',base+'/import']));assert result['success'];sid=result['session_id'];records=[]
  for kind,variants in methods.items():
   for method in variants:
    b={'session_id':sid,'experiment':'synthetic_integrated_figures','method':method,'use':method,'k':3,'group_var':'Group','ref_group':'A','test_group':'B'}
    status,result=call(base,'/analyze/'+kind,b);assert status==200 and result['success'],(kind,method,result)
    records.append({'kind':kind,'method':method,'id':result['analysis_result_id']});print('prepared',kind,method,flush=True)
  (work/'sources.json').write_text(json.dumps(records))
  class Quiet(SimpleHTTPRequestHandler):
   def log_message(self,*args):pass
  with ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=str(ROOT/'webapp/frontend'))) as server:
   threading.Thread(target=server.serve_forever,daemon=True).start()
   try:subprocess.run([os.environ['EMP_NODE'],str(ROOT/'webapp/tests/check_integrated_analysis_browser.cjs'),base,f'http://127.0.0.1:{server.server_port}',sid,str(work)],check=True)
   finally:server.shutdown()
  for kind in methods:
   page=PdfReader(work/(kind+'.pdf')).pages[0];expected={'dimension':(120,100),'correlation':(180,160),'cluster':(180,140),'marker':(180,160)}[kind]
   assert abs(float(page.mediabox.width)-expected[0]/25.4*72)<.02 and abs(float(page.mediabox.height)-expected[1]/25.4*72)<.02
   assert not any(o.get_object().get('/Subtype')=='/Image' for o in page.get('/Resources',{}).get('/XObject',{}).values()),kind
   manifest=json.loads((work/(kind+'.json')).read_text());assert manifest['analysis_recomputed'] is False and manifest['source_md5']
 target=ROOT/'.local_run/verification/integrated-analysis-browser';target.mkdir(parents=True,exist_ok=True)
 for pattern in ['*.pdf','*.png','*.svg','*.json']:
  for f in work.glob(pattern):shutil.copyfile(f,target/f.name)
 print('PASS four physical vector PDF sizes, recorded source checksum and no raster objects; proofs:',target,flush=True)
