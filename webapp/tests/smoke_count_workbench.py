"""Isolated real HTTP -> callr -> DESeq2 acceptance with synthetic inputs.

Starts only its own loopback services on free ports and stops them on exit.
Uses installed packages; never installs, restarts other processes or calls a model.
"""
import argparse
import functools
import http.client
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'webapp/scripts'))
import omics_workbench as wb
import public_data_server
import static_server
import emp_gateway


def call(port, path, body=None, *, raw=None, token=None, extra=None):
    headers = {'Content-Type': 'application/octet-stream' if raw is not None else 'application/json', **(extra or {})}
    if token: headers['Authorization'] = 'Bearer ' + token
    conn = http.client.HTTPConnection('127.0.0.1', port, timeout=60)
    conn.request('POST' if raw is not None or body is not None else 'GET', path,
                 body=raw if raw is not None else json.dumps(body) if body is not None else None, headers=headers)
    response = conn.getresponse(); data = response.read(); conn.close()
    if response.status != 200: raise RuntimeError(f'HTTP {response.status}: {data[:400]!r}')
    return json.loads(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('fixture', type=Path)
    parser.add_argument('--serve', action='store_true', help='Keep isolated services alive for a manual browser review')
    args = parser.parse_args()
    fixture = json.loads(args.fixture.read_text())
    with tempfile.TemporaryDirectory(prefix='emp-wb-', dir=ROOT / '.local_run/verification') as folder:
        output = Path(folder)
        # Plumber's port validator rejects the OS ephemeral range above 49151.
        for _ in range(100):
            api_port = 18000 + secrets.randbelow(30000)
            with socket.socket() as reservation:
                try: reservation.bind(('127.0.0.1', api_port)); break
                except OSError: continue
        else: raise RuntimeError('No free supported R API test port')
        token = secrets.token_hex(24)
        env = dict(os.environ, API_HOST='127.0.0.1', API_PORT=str(api_port), EMP_DATA_DIR=str(output / 'r-data'),
                   EMP_API_TOKEN=token, EMP_API_TOKEN_SHA256S='', EMP_ENABLE_USER_R='false',
                   EMP_BACKEND_DIR=str(ROOT / 'webapp/backend'), BACKEND_DIR=str(ROOT / 'webapp/backend'))
        log = open(output / 'r.log', 'w+')
        process = subprocess.Popen(['Rscript', str(ROOT / 'webapp/backend/run_api.R')], cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
        servers = []
        try:
            deadline = time.monotonic() + 90
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    log.seek(0); raise RuntimeError('Isolated R startup failed: ' + log.read()[-3000:])
                try:
                    caps = call(api_port, '/api/workbench/capabilities', token=token)
                    if caps['contract'] == wb.CONTRACT and caps['ready']: break
                except (OSError, RuntimeError): pass
                time.sleep(.5)
            else: raise RuntimeError('Isolated R did not become ready')
            metadata = public_data_server.make_server(0)
            metadata.omics_workbench = wb.Workbench(output / 'workbench')
            metadata_port = metadata.server_port
            web = static_server.EMPThreadingHTTPServer(('127.0.0.1', 0), functools.partial(static_server.RangeHandler, directory=str(ROOT / 'webapp/frontend')))
            web.metadata_port = metadata_port
            emp_gateway.API_PORT = api_port; emp_gateway.WEB_PORT = web.server_port; emp_gateway.PUBLIC_DATA_PORT = metadata_port
            gateway = emp_gateway.ThreadingHTTPServer(('127.0.0.1', 0), emp_gateway.GatewayHandler)
            metadata.allowed_origins.add(f'http://127.0.0.1:{gateway.server_port}')
            # Browser requests to this isolated test origin use its ephemeral test token,
            # never the user's real runtime token. Headers are not logged.
            original_proxy = emp_gateway.GatewayHandler._proxy
            def authenticated_proxy(handler):
                if handler.path.startswith('/api/') and not handler.path.startswith('/api/public-data/'):
                    if 'Authorization' in handler.headers: del handler.headers['Authorization']
                    handler.headers['Authorization'] = 'Bearer ' + token
                return original_proxy(handler)
            gateway.RequestHandlerClass._proxy = authenticated_proxy
            for server in [metadata, web, gateway]:
                thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start(); servers.append((server, thread))
            prefix = '/api/public-data/workbench/'
            upload = call(web.server_port, prefix + 'upload', raw=fixture['matrix_csv'].encode(), extra={'X-Matrix-Name':'synthetic.tsv'})
            cols = json.loads(fixture['plan_json'])['samples']
            dataset = call(web.server_port, prefix + 'select', {'input_id': upload['input_id'], 'sample_columns':[x['id'] for x in cols]})
            plan = json.loads(fixture['plan_json'])
            plan = {k:v for k,v in plan.items() if k in {'version','dataset_id','omics','data_type','samples','design','steps','seed','raw_counts_evidence'}}
            plan['dataset_id'] = dataset['dataset_id']
            prepared = call(web.server_port, prefix + 'prepare', {'plan':plan})
            assert prepared['valid'], prepared
            payload = call(web.server_port, prefix + 'prepared/' + prepared['prepared_id'])
            payload['confirmed'] = True
            run = call(api_port, '/api/workbench/run', payload, token=token)
            duplicate = call(api_port, '/api/workbench/run', payload, token=token)
            assert run['job_id'] == duplicate['job_id'], 'Duplicate submission started another job'
            deadline = time.monotonic() + 120
            while time.monotonic() < deadline:
                job = call(api_port, '/api/jobs/' + run['job_id'], token=token)['job']
                if job['status'] == 'done': break
                if job['status'] in {'error', 'cancelled'}: raise RuntimeError('Worker failed: ' + str(job.get('error')))
                time.sleep(.5)
            else: raise RuntimeError('Job did not finish; isolated worker must be inspected')
            result = call(api_port, '/api/jobs/' + run['job_id'] + '/result', token=token)
            assert result['contract'] == wb.CONTRACT and result['execution_performed'] is True
            assert result['plan_sha256'] == prepared['plan_sha256']
            assert len(result['artifacts']['differential']['rows']) == 400
            assert any(0 < row.get('pvalue', 0) < .0001 for row in result['artifacts']['differential']['rows'])
            evidence = {'status':'passed', 'data':'synthetic fixture only', 'dimensions':[401,6], 'contract':wb.CONTRACT,
                        'job_id':run['job_id'], 'plan_sha256':prepared['plan_sha256'], 'environment':result['environment'],
                        'steps':result['steps'], 'tested_features':400, 'original_file_download_tested':False,
                        'provider_live_tested':False, 'idempotency_tested':True}
            (ROOT / '.local_run/verification/workbench/http-acceptance.json').write_text(json.dumps(evidence, indent=2))
            print(json.dumps(evidence), flush=True)
            if args.serve:
                print(f'BROWSER_REVIEW_URL=http://127.0.0.1:{gateway.server_port}/', flush=True)
                print('Upload fixture: ' + str(args.fixture.resolve()), flush=True)
                # This CSV contains synthetic data only, convenient for browser upload.
                (ROOT / '.local_run/verification/workbench/browser-synthetic.tsv').write_text(fixture['matrix_csv'])
                while True: time.sleep(1)
        finally:
            for server, thread in reversed(servers): server.shutdown(); server.server_close(); thread.join()
            process.terminate()
            try: process.wait(timeout=10)
            except subprocess.TimeoutExpired: process.kill(); process.wait()
            log.close()


if __name__ == '__main__': main()
