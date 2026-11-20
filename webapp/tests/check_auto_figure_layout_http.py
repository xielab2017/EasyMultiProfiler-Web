"""Offline full-stack regression for the user's 60 mm / 6 pt volcano."""
import functools,json,math,os,subprocess,sys,tempfile,threading,shutil,urllib.request
from contextlib import contextmanager
from pathlib import Path
from http.server import SimpleHTTPRequestHandler,ThreadingHTTPServer
ROOT=Path.cwd();sys.path.insert(0,str(ROOT/'webapp/tests'))
from isolated_r_api import isolated_r_api,api_environment,call
from pypdf import PdfReader
from PIL import Image
LIVE=os.environ.get('EMP_AUTO_LAYOUT_LIVE')=='1'
sid=None
@contextmanager
def test_api(work):
 if not LIVE:
  with isolated_r_api(ROOT,str(ROOT/'.local_run/r-runtime/bin/Rscript'),work,api_environment(work)) as base:yield base
 else:
  base='http://127.0.0.1:8000/api'
  try:yield base
  finally:
   if sid:
    with urllib.request.urlopen(urllib.request.Request(base+'/session/'+sid,method='DELETE')) as response:assert json.load(response)['success']
with tempfile.TemporaryDirectory(prefix='emp-auto-layout-') as temp:
 work=Path(temp);counts=work/'counts.csv';meta=work/'meta.csv';diff=work/'diff.csv';n=1564
 counts.write_text('feature,A,B,C,D\n'+''.join(f'Gene{i},{i+10},{2*i+12},{3*i+13},{4*i+15}\n' for i in range(1,n+1)))
 meta.write_text('sample,Group\nA,Control\nB,Control\nC,Treatment\nD,Treatment\n')
 rows=[]
 for i in range(1,n+1):
  if i<=66:fc,p=-(1+2*(i%67)/66),10**(-1.5-5*(i%61)/60)
  elif i<=1392:fc,p=math.sin(i)*.9,.06+.93*(i%101)/100
  else:fc,p=1+4*(i%173)/172,10**(-1.5-5.5*(i%61)/60)
  rows.append(f'Gene{i},{fc},{p},{p}\n')
 diff.write_text('feature,log2FoldChange,pvalue,padj\n'+''.join(rows))
 target=ROOT/'.local_run/verification/auto-layout';target.mkdir(parents=True,exist_ok=True)
 with test_api(work) as base:
  data=json.loads(subprocess.check_output(['curl','-fsS','-F','data_file=@'+str(counts),'-F','metadata_file=@'+str(meta),'-F','data_type=normal','-F','experiment_name=synthetic_auto_layout',base+'/import']));assert data['success'],data;sid=data['session_id']
  data=json.loads(subprocess.check_output(['curl','-fsS','-F','data_file=@'+str(diff),'-F','session_id='+sid,'-F','experiment_name=synthetic_auto_layout','-F','group_var=Group','-F','ref_group=Control','-F','test_group=Treatment',base+'/import/diff_raw']));assert data['success'],data
  class QuietHandler(SimpleHTTPRequestHandler):
   def log_message(self,*args):pass
  handler=functools.partial(QuietHandler,directory=str(ROOT/'webapp/frontend'))
  with ThreadingHTTPServer(('127.0.0.1',0),handler) as server:
   threading.Thread(target=server.serve_forever,daemon=True).start()
   try:subprocess.run([os.environ['EMP_NODE'],str(ROOT/'webapp/tests/check_auto_figure_layout_browser.cjs'),base,('http://127.0.0.1:8080' if LIVE else f'http://127.0.0.1:{server.server_port}'),sid,str(work)],check=True)
   finally:server.shutdown()
 for name in ['browser-auto-60.pdf','browser-auto-60.png','browser-auto-60.json','browser-auto-result.png','browser-visible-defaults.png','browser-auto-heatmap-60.pdf','browser-auto-heatmap-60.png','browser-heatmap-mixed.pdf','browser-heatmap-mixed.png']:shutil.copyfile(work/name,target/name)
 r=PdfReader(work/'browser-auto-60.pdf');assert len(r.pages)==1;page=r.pages[0]
 assert abs(float(page.mediabox.width)-60/25.4*72)<.02 and abs(float(page.mediabox.height)-60/25.4*72)<.02
 fonts=[];legend_positions={}
 def visit(text,cm,tm,font,size):
  if text.strip():fonts.append(size*math.hypot(cm[0]*tm[2]+cm[2]*tm[3],cm[1]*tm[2]+cm[3]*tm[3]))
  for label in ['Down (n=66)','NS (n=1326)','Up (n=172)']:
   if label in text:legend_positions[label]=(cm[0]*tm[4]+cm[2]*tm[5]+cm[4],cm[1]*tm[4]+cm[3]*tm[5]+cm[5])
 text=page.extract_text(visitor_text=visit)
 for label in ['Down (n=66)','NS (n=1326)','Up (n=172)']:assert label in text,(label,text)
 assert fonts and min(fonts)>=3.9-1e-4,fonts
 assert len(legend_positions)==3,legend_positions
 ordered=[legend_positions[label] for label in ['NS (n=1326)','Up (n=172)','Down (n=66)']]
 assert max(x for x,y in ordered)-min(x for x,y in ordered)<.1,ordered
 assert ordered[0][1]>ordered[1][1]>ordered[2][1],ordered
 image=Image.open(work/'browser-auto-60.png').convert('RGB');w,h=image.size
 edge=image.crop((w-3,int(h*.65),w,h))
 assert all(low>245 for low,high in edge.getextrema()),'Legend crosses the right canvas edge'
 assert not any(obj.get_object().get('/Subtype')=='/Image' for obj in page.get('/Resources',{}).get('/XObject',{}).values()),'PDF contains a raster image'
 print('PASS actual vector PDF: 60x60 mm, base text 6 pt, all three count labels; PNG legend has a clear right margin; outputs:',target,flush=True)
