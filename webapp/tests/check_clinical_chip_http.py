"""Offline clinical and ChIP-seq acceptance against a temporary R/Plumber instance."""
import argparse
import base64
import csv
import io
import json
import math
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import time

from isolated_r_api import api_environment, isolated_r_api, call

ROOT=Path(__file__).resolve().parents[2]


def upload(base,route,**fields):
    args=['curl','--silent','--show-error','--max-time','40','--write-out','\n%{http_code}']
    for key,value in fields.items():
        args.extend(['--form',key+'='+ ('@'+str(value) if isinstance(value,Path) else value)])
    raw=subprocess.check_output(args+[base+route]).decode()
    data,status=raw.rsplit('\n',1)
    return int(status),json.loads(data)


def ok(response):
    status,data=response
    assert status==200 and data.get('success'), (status,data.get('error'))
    return data


def png(value):
    raw=base64.b64decode(value,validate=True)
    assert raw[:8]==b'\x89PNG\r\n\x1a\n' and raw[12:16]==b'IHDR' and raw[-8:-4]==b'IEND'
    dims=struct.unpack('>II',raw[16:24])
    assert min(dims)>=200
    # Decode and check the drawing when Pillow is installed in the test environment.
    try:
        from PIL import Image
    except ImportError:
        return dims
    with Image.open(io.BytesIO(raw)) as img:
        assert img.size==dims
        pixels=img.convert('RGB').resize((128,128))
        colors = pixels.getcolors(maxcolors=pixels.width * pixels.height)
        assert len(colors) > 16
        assert sum(count for count, rgb in colors if min(rgb) < 220) > 40
    return dims


def clinical(base,tmp):
    cross=tmp/'cross.csv'
    cross.write_text('SampleID,Group,Age,Measure,Sex,Tag\n'+'\n'.join(
        f'S{i+1},{"A" if i<4 else "B"},{20+i},{10+i if i!=5 else ""},{"M" if i%2==0 else "F"},z{i+1}' for i in range(8)))
    def standalone(path):
        data=ok(upload(base,'/import',data_type='clinical_raw',data_file=path))
        assert data['import_mode']=='clinical_standalone'
        return dict(session_id=data['session_id'],source='standalone',group_var='Group',table_engine='base',max_levels=3)
    args=standalone(cross)
    table=ok(call(base,'/clinical/three_line',args))['data']
    rows={r['Variable']:r for r in table}
    assert set(rows)=={'Age','Measure','Sex: M','Sex: F'}
    assert rows['Age']['Overall']=='23.50 ± 2.45' and rows['Measure']['B']=='15.67 ± 1.53'
    assert rows['Sex: M']['B']=='2 (50.0%)'
    cross_summary=ok(call(base,'/clinical/systematic_summary',args))
    assert cross_summary['design_type']=='cross_sectional' and cross_summary['n_pairs']==0
    assert cross_summary['n_between']==2 and cross_summary['n_within']==0
    assert math.isclose(rows['Age']['P_value'],2/math.comb(8,4),abs_tol=5e-5)
    assert math.isclose(rows['Measure']['P_value'],2/math.comb(7,3),abs_tol=5e-5)

    paired=tmp/'paired.csv'
    paired.write_text('SampleID,patient,Group,Measure,Partial\n'+'\n'.join(
        f'{cohort}{i}-{visit},{cohort}{i},{cohort}_{visit},{value},{value if i!=4 or visit!="after" or cohort!="UC" else ""}'
        for cohort,delta in [('UC',1),('IBS',8)] for i in range(1,5)
        for visit in ['before','after'] for value in [i if visit=='before' else i+delta+i/4]))
    args=standalone(paired)
    out=ok(call(base,'/clinical/systematic_summary',args))
    assert out['design_type']=='longitudinal' and out['n_pairs']==8
    baseline=next(r for r in out['baseline'] if r['Variable']=='Measure')
    assert baseline['Overall']=='2.50 ± 1.20' and 'UC_after' not in baseline and 'IBS_after' not in baseline
    complete=next(r for r in out['within'] if r['Cohort']=='UC' and r['Variable']=='Measure')
    assert complete['N_pairs']==4 and complete['P_value']==0.125 and complete['Delta'].startswith('1.62 ')
    assert next(r for r in out['within'] if r['Cohort']=='UC' and r['Variable']=='Partial')['N_pairs']==3
    assert math.isclose(next(r for r in out['between'] if r['Variable']=='Measure')['P_value'],2/math.comb(8,4),abs_tol=5e-5)
    one=ok(call(base,'/clinical/systematic_summary',dict(args,cohort_filter=['UC'])))
    assert one['n_pairs']==4 and one['n_between']==0 and all(r['Cohort']=='UC' for r in one['within'])
    paired.write_text(paired.read_text()+'\nrepeat,UC1,UC_before,999,999')
    status,rejected=call(base,'/clinical/systematic_summary',standalone(paired))
    assert status==400 and 'duplicate' in rejected['error']

    feature=tmp/'features.csv'
    feature.write_text('Gene,S1,S2,S3,S4,S5,S6,S7,S8\nTrend,1,3,5,7,9,11,13,15\nInverse,20,19,18,17,16,15,14,13\nOther,3,4,6,5,1,8,3,6\n')
    data=ok(upload(base,'/import',experiment_name='synthetic',data_type='normal',data_file=feature,metadata_file=cross))
    args=dict(session_id=data['session_id'],experiment='synthetic')
    fit=ok(call(base,'/clinical/fitline',dict(args,feature='Trend',trait='Age',group='Group')))
    assert fit['n']==8 and fit['r']==1 and fit['pdf_available']
    dims=png(fit['plot'])
    cor=ok(call(base,'/clinical/cor',dict(args,traits=['Age','Measure'],method='spearman',top_n_features=3)))
    assert cor['table_n']==6 and cor['pdf_available'] and cor['n_samp']==8
    assert any(r['feature']=='Inverse' and r['trait']=='Age' and r['r']==-1 for r in cor['table'])
    for result in [fit,cor]:
        assert (tmp/'sessions'/args['session_id']/'plots'/result['pdf_name']).read_bytes().startswith(b'%PDF')
    print(f'Clinical: 8 cross-sectional, 8 matched subjects × 2 visits, 6 correlations; PNG {dims}, {png(cor["plot"])} and PDFs.',flush=True)


def chip(base,tmp):
    route='/workflows/chipseq/'
    status=ok(call(base,route+'tools/status'))['tools']
    print('ChIP tools:',{k:v['available'] for k,v in status.items() if isinstance(v,dict) and 'available' in v},flush=True)
    inputs=[('a',[('chr1',0,10,100),('chr1',10,20,200),('chr1',100,110,300),('chr2',10,20,400)]),
            ('b',[('chr1',5,12,100),('chr1',105,115,200),('chr2',30,40,300)])]
    args=dict(genome='hs')
    records=[]
    for name,intervals in inputs:
        path=tmp/(name+'.narrowPeak')
        path.write_text(''.join(f'{ch}\t{x}\t{y}\tp{k}\t{s}\t.\t{s/10}\t5\t3\t2\n' for k,(ch,x,y,s) in enumerate(intervals)))
        result=ok(upload(base,route+'peaks/upload',peak_file=path,**args))
        assert result['n_peaks']==len(intervals) and result['assembly']=='hg38'
        records.append(result);args['session_id']=result['session_id']
    a,b=records
    registry=ok(call(base,route+'peaks/list?session_id='+args['session_id']))
    assert len(registry['peak_files'])==2
    qc=ok(call(base,route+'peak_qc',dict(args,peak_file=a['peak_file'])))
    assert qc['n_peaks']==4 and qc['width_summary']['mean']==10 and qc['score_summary']['median']==250
    assert {r['chrom']:r['n'] for r in qc['chrom_counts']}=={'chr1':3,'chr2':1}
    def ops(op,**kwargs):
        return ok(call(base,route+'analyze/peaks_ops',dict(args,op=op,peak_file=a['peak_file'],**kwargs)))
    overlap=ops('overlap',peak_b=b['peak_file'])
    assert overlap['intersection_bp']==12 and math.isclose(overlap['jaccard'],12/55,abs_tol=5e-5)
    assert (overlap['n_shared_a'],overlap['n_unique_a'],overlap['n_unique_b'])==(3,1,1)
    merged=ops('merge',merge_gap=0)
    assert merged['n_after']==3 and merged['width_summary']['max']==20
    summit=ops('summit',summit_size=10)
    windows=list(csv.reader(Path(summit['output_bed']).read_text().splitlines(),delimiter='\t'))
    assert summit['window_bp']==20 and windows[2][1:3]==['92','112'] and windows[0][1]=='0'
    rank=ops('super_enhancer',stitch_gap=0,exclude_promoter=False)
    assert rank['n_stitched']==3 and rank['n_super']+rank['n_typical']==3
    scores=[float(row['score']) for row in csv.DictReader(Path(rank['rank_csv']).read_text().splitlines())]
    assert scores==[400,300,300]
    dims=png(rank['plots']['se_rank'])
    for text in ['chr1\t40\t10','chr2\t-3\t8','chr2\t1.5\t8','chr2\t3\tbad']:
        path=tmp/'invalid.bed';path.write_text(text+'\n')
        status,rejected=upload(base,route+'peaks/upload',peak_file=path,**args)
        assert status==400 and 'Invalid BED coordinates' in rejected['error']
    point=tmp/'point.bed';point.write_text('chr1\t10\t10\n')
    preserved=ok(upload(base,route+'peaks/upload',peak_file=point,**args))
    assert ok(call(base,route+'peak_qc',dict(args,peak_file=preserved['peak_file'])))['width_summary']['mean']==1
    print(f'ChIP: 4 vs 3 peaks, intersection=12 bp, union=55 bp, scores={scores}, rank PNG={dims}; four invalid coordinate cases rejected.',flush=True)


def main():
    project_r=ROOT/'.local_run/r-runtime/bin/Rscript'
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rscript',default=str(project_r) if project_r.exists() else shutil.which('Rscript'))
    args=parser.parse_args()
    if not args.rscript: parser.error('Rscript is required')
    with tempfile.TemporaryDirectory(prefix='emp-clin-chip-') as work:
        tmp=Path(work)
        with isolated_r_api(ROOT,args.rscript,tmp,api_environment(tmp)) as base:
            for check in (clinical,chip):
                start=time.monotonic();check(base,tmp);print(f'{check.__name__} elapsed {time.monotonic()-start:.2f}s',flush=True)

if __name__=='__main__':main()
