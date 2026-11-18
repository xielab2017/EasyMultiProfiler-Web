"""Run offline plugin installation, authorization, job execution and visualization checks."""
import argparse
import hashlib
import json
import math
import subprocess
from pathlib import Path
import shutil
import tempfile
import time
from urllib.request import Request, urlopen
from urllib.error import HTTPError

from isolated_r_api import api_environment, isolated_r_api

ROOT=Path(__file__).resolve().parents[2]


def authenticated(base,token,path,data=None):
    req=Request(base+path, data=None if data is None else json.dumps(data).encode(),
                headers={'Content-Type':'application/json','Authorization':'Bearer '+token})
    try: res=urlopen(req,timeout=20)
    except HTTPError as error: res=error
    with res: return res.status,json.load(res)


def run(base):
    def call(path,data=None,code=200,token='fixture-A'):
        status,value=authenticated(base,token,path,data)
        assert status==code,(path,status,value)
        return value
    extension='/extensions'
    catalog=lambda:call(extension)
    def plugin(id):return next(p for p in catalog()['installed'] if p['id']==id)
    def enable(id):
        p=plugin(id);call(extension+'/enable',dict(id=id,sha256=p['sha256'],enabled=True));return p
    discovery=call('/capabilities')
    assert discovery['features']['analysis_plugins'] and discovery['extensions']['catalog']=='/api/extensions'
    assert {p['id'] for p in catalog()['examples']}=={'sample-quality','quality-bars','zotero-style-chat'}
    assert catalog()['invalid'][0]['id']=='invalid-view'
    shared=plugin('lab-summary')
    assert not shared['enabled'] and shared['definition']['axis']=='sample'
    for id in ['sample-quality','quality-bars']:
        assert call(extension+'/install',{'example_id':id})['status']=='installed'
        assert not plugin(id)['enabled']
    manifest=json.loads((ROOT/'plugins/examples/sample-quality/plugin.json').read_text());manifest['id']='third-party'
    manifest['definition']['metrics']=[{'key':'twice','expression':{'op':'multiply','left':{'stat':'mean'},'right':{'constant':2}}}]
    assert call(extension+'/install',{'manifest':manifest})['status']=='installed'
    assert call(extension+'/install',{'manifest':manifest})['status']=='already_installed'
    assert [p['id'] for p in call(extension,token='fixture-B')['installed']]==['lab-summary']
    call(extension+'/install',{'manifest':dict(manifest,id='lab-summary',version='2.0.0')},400)
    for field,bad in [('version','9'),('abi','emp.analysis.v99'),('permissions',['assay.read','network']),('id','../x')]:
        call(extension+'/install',{'manifest':dict(manifest,**{field:bad})},400)
    bad=json.loads(json.dumps(manifest));bad['definition']['metrics'][0]['expression']={'code':'anything'}
    call(extension+'/install',{'manifest':bad},400)
    return call,enable,plugin,manifest


def verify(base,tmp):
    call,enable,plugin,manifest=run(base)
    # Fixture data are posted through the normal authenticated multipart import path.
    matrix=tmp/'matrix.csv'
    matrix.write_text('feature,A,B,C,D\nf1,1,0,5,4\nf2,3,0,7,8\nf3,5,0,9,12\n')
    uploaded=json.loads(subprocess.check_output(['curl','-fsS','-H','Authorization: Bearer fixture-A','-F','data_type=normal',
        '-F','experiment_name=plugin_fixture','-F','data_file=@'+str(matrix),base+'/import']))
    sid=uploaded['session_id']
    exp=call('/session/'+sid+'/experiments')['experiments'][0]
    def submit(id,expected=200):
        p=plugin(id)
        return call('/extensions/run',dict(id=id,sha256=p['sha256'],session_id=sid,experiment=exp['name'],assay=exp['assay']),expected)
    submit('sample-quality',400)
    enable('sample-quality');enable('quality-bars');enable('third-party')
    def result(id):
        receipt=submit(id)
        for _ in range(200):
            job=call('/jobs/'+receipt['job_id'])['job']
            if job['status']=='done':break
            assert job['status'] in ('queued','running'),job
            time.sleep(.15)
        else:raise TimeoutError(receipt)
        return receipt['job_id'],call('/jobs/'+receipt['job_id']+'/result')
    def settings(id, value, code=200):
        return call('/extensions/settings',dict(id=id,sha256=plugin(id)['sha256'],settings=value),code)
    settings('sample-quality', {'metrics':[]}, 400)
    settings('sample-quality', {'metrics':['unknown']}, 400)
    settings('quality-bars', {'layout':'table','limit':201}, 400)
    settings('lab-summary', {'metrics':['mean']})
    shared_b=next(p for p in call('/extensions',token='fixture-B')['installed'] if p['id']=='lab-summary')
    assert len(shared_b['settings']['metrics'])>1
    settings('sample-quality', {'metrics':['observed','mean','sd','cv']})
    jid,a=result('sample-quality')
    assert a['plugin']['settings']['metrics']==['observed','mean','sd','cv']
    assert 'missing' not in a['rows'][0]
    print('rows',a['rows'],'contract',a['contract'],flush=True)
    assert a['contract']=='emp.metric-table.v1' and a['input']['samples']==4 and a['input']['features']==3
    by=dict((r['item'],r) for r in a['rows'])
    assert by['A']['mean']==3 and by['A']['sd']==2 and math.isclose(by['A']['cv'],2/3)
    assert by['B']['cv'] is None and by['B']['observed']==3
    assert a['plugin']['version']=='1.0.0' and a['plugin']['sha256']==plugin('sample-quality')['sha256']
    other_id,b=result('third-party');assert [r['twice'] for r in b['rows']]==[6,0,14,16]
    v=plugin('quality-bars')
    view=dict(id=v['id'],sha256=v['sha256'],session_id=sid,job_id=jid)
    rendered=call('/extensions/display',view)
    assert rendered['layout']=='bars' and rendered['rows'][0]=={'item':'A','mean':3}
    settings('quality-bars', {'layout':'table','limit':2})
    changed=call('/extensions/display',view)
    assert changed['layout']=='table' and len(changed['rows'])==2 and changed['total']==4
    assert settings('quality-bars',None)['settings']=={'layout':'bars','limit':30}
    call('/extensions/display',dict(view,job_id=other_id),400)
    call('/extensions/display',view,403,token='fixture-B')
    history=call('/extensions/jobs/'+sid)['jobs'];assert len(history)==2
    call('/extensions/enable',dict(id=v['id'],sha256=v['sha256'],enabled=False));call('/extensions/display',view,400)
    assert call('/extensions/install',{'manifest':dict(manifest,version='1.1.0')})['status']=='installed'
    assert not plugin('third-party')['enabled']
    call('/extensions/install',{'manifest':manifest},400)
    print('PASS: authorization, independent plugin, limits, pinned jobs, disable/upgrade, display and history',flush=True)
    return jid


def verify_browser(base, tmp, node):
    from functools import partial
    from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
    from threading import Thread

    class StaticFiles(SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass

    uploaded = subprocess.check_output([
        'curl', '-fsS', '-H', 'Authorization: Bearer fixture-B',
        '-F', 'data_type=normal', '-F', 'experiment_name=plugin_fixture',
        '-F', 'data_file=@' + str(tmp/'matrix.csv'), base+'/import'
    ])
    handler = partial(StaticFiles, directory=str(ROOT/'webapp/frontend'))
    with ThreadingHTTPServer(('127.0.0.1', 0), handler) as server:
        Thread(target=server.serve_forever, daemon=True).start()
        try:
            subprocess.run([
                node, str(ROOT/'webapp/tests/check_platform_extensions_browser.cjs'),
                base, 'http://127.0.0.1:' + str(server.server_port), json.loads(uploaded)['session_id'],
                str(ROOT/'plugins/examples/sample-quality/plugin.json')
            ], check=True)
        finally:
            server.shutdown()


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    project_r=ROOT/'.local_run/r-runtime/bin/Rscript'
    parser.add_argument('--rscript',default=str(project_r) if project_r.exists() else shutil.which('Rscript'))
    parser.add_argument('--browser', action='store_true', help='Also exercise the actual workbench using Node and Playwright Chromium')
    parser.add_argument('--node', default='node')
    args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='emp-platform-plugins-') as work:
        tmp=Path(work);env=api_environment(tmp)
        plugin_root=tmp/'plugins'
        shutil.copytree(ROOT/'plugins/examples',plugin_root/'examples')
        for plugin_id in ('lab-summary','invalid-view'):
            template=json.loads((plugin_root/'examples/sample-quality/plugin.json').read_text())
            template['id']=plugin_id
            if plugin_id=='invalid-view':
                template['abi']='emp.view.v0'
            dest=plugin_root/'extensions'/plugin_id
            dest.mkdir(parents=True)
            (dest/'plugin.json').write_text(json.dumps(template))
        env['EMP_PLUGIN_ROOT']=str(plugin_root)
        env['EMP_API_TOKEN_SHA256S']=json.dumps({f'owner{c}':hashlib.sha256(('fixture-'+c).encode()).hexdigest() for c in 'AB'})
        with isolated_r_api(ROOT,args.rscript,tmp,env) as base:
            job_id=verify(base,tmp)
            if args.browser:
                verify_browser(base,tmp,args.node)
        with isolated_r_api(ROOT,args.rscript,tmp,env) as base:
            status,catalog=authenticated(base,'fixture-A','/extensions')
            assert status==200
            persisted={p['id']:p for p in catalog['installed']}
            assert persisted['sample-quality']['enabled'] and not persisted['quality-bars']['enabled']
            assert persisted['sample-quality']['settings']['metrics']==['observed','mean','sd','cv']
            assert persisted['third-party']['version']=='1.1.0' and not persisted['third-party']['enabled']
            status,result=authenticated(base,'fixture-A','/jobs/'+job_id+'/result')
            assert status==200 and result['plugin']['sha256']==persisted['sample-quality']['sha256']
            print('PASS: install, version grant, revocation and completed result survive R service restart',flush=True)
