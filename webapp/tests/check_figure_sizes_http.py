import functools
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path.cwd()
sys.path.insert(0,str(ROOT/'webapp/tests'))
from isolated_r_api import isolated_r_api, api_environment, call

with tempfile.TemporaryDirectory(prefix='emp107-figures-') as temp:
    work=Path(temp)
    matrix=work/'counts.csv'
    matrix.write_text('feature,A,B,C,D\n'+''.join(f'gene{i},{i*2+10},{i*3+12},{i*5+21},{i*4+20}\n' for i in range(1,13)))
    metadata=work/'metadata.csv'
    metadata.write_text('sample,Group\nA,Control\nB,Control\nC,Treatment\nD,Treatment\n')
    diff=work/'diff.csv'
    diff.write_text('feature,log2FoldChange,pvalue,padj\n'+''.join(f'gene{i},2,0.001,0.01\n' for i in range(1,13)))
    def upload(base,path,filename,fields):
        command=['curl','-fsS','-F','data_file=@'+str(filename)]
        if path=='/import': command+=['-F','metadata_file=@'+str(metadata)]
        for key,value in fields.items():command+=['-F',key+'='+value]
        return json.loads(subprocess.check_output(command+[base+path]))
    with isolated_r_api(ROOT,str(ROOT/'.local_run/r-runtime/bin/Rscript'),work,api_environment(work)) as base:
        imported=upload(base,'/import',matrix,{'data_type':'normal','experiment_name':'synthetic_degs'})
        sid=imported['session_id']
        experiment=call(base,'/session/'+sid+'/experiments')[1]['experiments'][0]['name']
        res=upload(base,'/import/diff_raw',diff,{'session_id':sid,'experiment_name':experiment,'group_var':'Group','ref_group':'Control','test_group':'Treatment'})
        assert res['success'],res
        class QuietHandler(SimpleHTTPRequestHandler):
            def log_message(self,*args): pass
        handler=functools.partial(QuietHandler,directory=str(ROOT/'webapp/frontend'))
        with ThreadingHTTPServer(('127.0.0.1',0),handler) as server:
            thread=threading.Thread(target=server.serve_forever,daemon=True)
            thread.start()
            try:
                subprocess.run([os.environ['EMP_NODE'],str(ROOT/'webapp/tests/check_figure_sizes_browser.cjs'),base,f'http://127.0.0.1:{server.server_port}',sid,str(work)],check=True)
            finally:server.shutdown()

        from pypdf import PdfReader
        from PIL import Image
        for name,w,h in [('volcano-local',152.4,101.6),('volcano-unified',180,120),('deg-unified',180,120),('boxplot-unified',180,120),('volcano-restored',152.4,101.6)]:
            page=PdfReader(work/(name+'.pdf')).pages[0]
            assert abs(float(page.mediabox.width)-w/25.4*72)<0.02,(name,page.mediabox)
            assert abs(float(page.mediabox.height)-h/25.4*72)<0.02,(name,page.mediabox)
            # No bitmap XObjects in the PDF: plot geometry/text must remain vectors.
            for obj in page.get('/Resources',{}).get('/XObject',{}).values():
                assert obj.get_object().get('/Subtype')!='/Image',name
            image=Image.open(work/(name+'.png'))
            dpi=150 if name.endswith('unified') else 300
            assert abs(image.width-w/25.4*dpi)<=1 and abs(image.height-h/25.4*dpi)<=1,(name,image.size)
            print('PASS vector PDF / PNG dimensions:',name, w,h,flush=True)
        for ext,fmt in [('jpg','JPEG'),('tiff','TIFF')]:
            image=Image.open(work/('volcano-unified.'+ext))
            assert image.format==fmt,(ext,image.format)
            assert abs(float(image.info['dpi'][0])-150)<0.1,image.info
            assert image.size==Image.open(work/'volcano-unified.png').size
            print('PASS real raster format / DPI:',fmt,image.size,image.info['dpi'],flush=True)
        # Server-side checks reject malformed values and release request-local sizing.
        status,data=call(base,'/visualize/volcano',{'session_id':sid,'experiment':experiment,'export_size':{'width_mm':0,'height_mm':120,'dpi':150}})
        assert status!=200 or not data.get('success'),data
        target=ROOT/'.local_run/verification/figure-sizes'
        target.mkdir(exist_ok=True,parents=True)
        import shutil
        for filename in work.glob('*.pdf'): shutil.copyfile(filename,target/filename.name)
        shutil.copyfile(work/'figure-canvas-controls.png',target/'figure-canvas-controls.png')
        print('Physical figure acceptance passed; fixture PDF proofs:',target,flush=True)
