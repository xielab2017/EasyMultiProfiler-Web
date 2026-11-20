"""Regression for a restart losing the optional method-library environment."""
import csv,functools,json,os,subprocess,sys,tempfile,threading,shutil,math
from pathlib import Path
from http.server import SimpleHTTPRequestHandler,ThreadingHTTPServer
from pypdf import PdfReader
ROOT=Path.cwd();sys.path.insert(0,str(ROOT/'webapp/tests'))
from isolated_r_api import isolated_r_api,api_environment,call
with tempfile.TemporaryDirectory(prefix='emp-method-ready-') as temp:
 work=Path(temp);env=api_environment(work);env.pop('EMP_FIGURE_METHODS_ROOT',None);env.pop('EMP_FIGURE_METHODS_CONFIG',None)
 counts=work/'counts.csv';meta=work/'meta.csv';diff=work/'diff.csv'
 counts.write_text('feature,A,B,C,D\n'+''.join(f'Gene{i},{i+10},{2*i+12},{3*i+13},{4*i+15}\n' for i in range(1,41)));meta.write_text('sample,Group\nA,Control\nB,Control\nC,Treatment\nD,Treatment\n')
 diff.write_text('feature,log2FoldChange,pvalue,padj\n'+''.join(f'Gene{i},{(-1 if i%2 else 1)*(i%7)/2},{i/1000},{"NA" if i==1 else i/1000}\n' for i in range(1,41)))
 with isolated_r_api(ROOT,str(ROOT/'.local_run/r-runtime/bin/Rscript'),work,env) as base:
  status,catalog=call(base,'/visualize/method-library/catalog');assert status==200 and catalog['available'],catalog
  assert catalog['configuration_source'].endswith('figure_methods.local.json'),catalog
  data=json.loads(subprocess.check_output(['curl','-fsS','-F','data_file=@'+str(counts),'-F','metadata_file=@'+str(meta),'-F','data_type=normal','-F','experiment_name=synthetic_method_ready',base+'/import']));assert data['success'];sid=data['session_id']
  data=json.loads(subprocess.check_output(['curl','-fsS','-F','data_file=@'+str(diff),'-F','session_id='+sid,'-F','experiment_name=synthetic_method_ready','-F','group_var=Group','-F','ref_group=Control','-F','test_group=Treatment',base+'/import/diff_raw']));assert data['success'],data
  class Quiet(SimpleHTTPRequestHandler):
   def log_message(self,*args):pass
  with ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=str(ROOT/'webapp/frontend'))) as server:
   threading.Thread(target=server.serve_forever,daemon=True).start()
   try:subprocess.run([os.environ['EMP_NODE'],str(ROOT/'webapp/tests/check_method_library_browser.cjs'),base,f'http://127.0.0.1:{server.server_port}',sid,str(work)],check=True)
   finally:server.shutdown()
 target=ROOT/'.local_run/verification/method-library-readiness';target.mkdir(parents=True,exist_ok=True)
 for path in work.glob('de-significance.*'):shutil.copyfile(path,target/path.name)
 page=PdfReader(work/'de-significance.pdf').pages[0];assert abs(float(page.mediabox.width)-120/25.4*72)<.02 and abs(float(page.mediabox.height)-110/25.4*72)<.02
 assert 'Differential significance scatter' in page.extract_text().replace('\n',' ')
 assert 'excluded (audited)' in page.extract_text().replace('\n',' ')
 assert not any(obj.get_object().get('/Subtype')=='/Image' for obj in page.get('/Resources',{}).get('/XObject',{}).values())
 with (work/'de-significance.csv').open() as f:rows=list(csv.DictReader(f))
 assert len(rows)==39
 for row in rows:
  i=int(row['gene_id'][4:]);assert i!=1;assert abs(float(row['padj'])-i/1000)<1e-12;assert abs(float(row['log2FC'])-(-1 if i%2 else 1)*(i%7)/2)<1e-12
 print('PASS persisted configuration after fresh R startup; exact vector PDF size; frozen FC and adjusted P unchanged; proofs:',target,flush=True)
