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

with tempfile.TemporaryDirectory(prefix='emp108-publication-') as temp:
    work=Path(temp)
    matrix=work/'counts.csv'
    matrix.write_text('feature,A,B,C,D\n'+''.join(f'gene{i},{i*2+10},{i*3+12},{i*5+21},{i*4+20}\n' for i in range(1,201)))
    metadata=work/'metadata.csv'
    metadata.write_text('sample,Group\nA,Control\nB,Control\nC,Treatment\nD,Treatment\n')
    diff=work/'diff.csv'
    diff.write_text('feature,log2FoldChange,pvalue,padj\n'+''.join(f'gene{i},2,0.001,0.01\n' for i in range(1,201)))
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
                subprocess.run([os.environ['EMP_NODE'],str(ROOT/'webapp/tests/check_publication_a4_browser.cjs'),base,f'http://127.0.0.1:{server.server_port}',sid,str(work)],check=True)
            finally:server.shutdown()


        from pypdf import PdfReader
        import math, shutil
        target=ROOT/'.local_run/verification/publication-a4-browser'
        target.mkdir(exist_ok=True,parents=True)
        for file in work.glob('*.pdf'): shutil.copyfile(file,target/file.name)
        for name,w,h in [('volcano-a4-two',87,87),('heatmap-a4-wide',180,120),('boxplot-a4-page',210,297),('heatmap-a4-page',210,297),('heatmap-independent',180,220),('volcano-independent',110,90),('heatmap-per-type-a4',210,297),('heatmap-point-custom',127,152.4),('heatmap-font-8',180,220),('heatmap-font-10',180,220),('heatmap-font-12',180,220),('heatmap-font-9.5',180,220),('heatmap-font-4',180,220),('heatmap-font-7.25',180,220),('heatmap-font-28',180,220),('heatmap-manual-custom',76.2,101.6)]:
            page=PdfReader(work/(name+'.pdf')).pages[0]
            assert abs(float(page.mediabox.width)-w/25.4*72)<.02
            assert abs(float(page.mediabox.height)-h/25.4*72)<.02
            fonts=[];genes=[]
            def visit(text,cm,tm,font,size):
                if not text.strip(): return
                # Quartz encodes Tf=1 plus the effective point size in Tm.
                scale=math.hypot(cm[0]*tm[2]+cm[2]*tm[3],cm[1]*tm[2]+cm[3]*tm[3])
                fonts.append(size*scale)
                if text.startswith('gene'): genes.append(tm[5])
            page.extract_text(visitor_text=visit)
            assert fonts and min(fonts)>0,(name,min(fonts,default=0))
            if name.startswith('heatmap-font-'):
                expected=float(name.removeprefix('heatmap-font-'))
                assert all(abs(font-expected)<1e-4 for font in fonts),(name,fonts)
            if name=='heatmap-manual-custom':
                assert len(genes)==200,len(genes)
                assert all(abs(font-7)<1e-4 for font in fonts),fonts
            if name=='heatmap-a4-wide':
                assert len(genes)==200,len(genes)
            print('PASS actual PDF:',name,w,h,'mm; effective fonts',sorted(set(round(x,3) for x in fonts)),flush=True)
            for ext in ['pdf','png']:shutil.copyfile(work/(name+'.'+ext),target/(name+'.'+ext))
        shutil.copyfile(work/'figure-units.png',target/'figure-units.png')
        shutil.copyfile(work/'a4-publication-controls.png',target/'a4-publication-controls.png')
        print('A4 publication acceptance passed:',target,flush=True)
