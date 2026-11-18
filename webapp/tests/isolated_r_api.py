"""Private loopback R API and storage for live, offline acceptance checks."""
from contextlib import contextmanager
import json
import os
from pathlib import Path
import socket
import subprocess
import time
import urllib.error
import urllib.request


def call(base, path, body=None):
    request = urllib.request.Request(base + path, data=None if body is None else json.dumps(body).encode(),
                                     headers={'Content-Type': 'application/json'})
    try:
        response = urllib.request.urlopen(request, timeout=45)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        return response.status, json.load(response)


def api_environment(tmp):
    env=dict(os.environ,API_HOST='127.0.0.1',EMP_DATA_DIR=str(tmp),EMP_SESSION_DIR=str(tmp/'sessions'),
             EMP_JOB_DIR=str(tmp/'jobs'),EMP_PROJECT_DIR=str(tmp/'projects'),
             EMP_API_TOKEN='',EMP_API_TOKEN_SHA256S='',EMP_ENABLE_USER_R='false')
    libs=Path(__file__).resolve().parents[2]/'.local_run/R_libs'
    if libs.is_dir():
        env['R_LIBS']=str(libs.resolve())+os.pathsep+env.get('R_LIBS','')
    return env


@contextmanager
def isolated_r_api(root, rscript, tmp, env):
    for port in range(39280,39480):
        try:
            with socket.socket() as check:
                check.bind(('127.0.0.1',port))
            break
        except OSError:
            continue
    else:
        raise RuntimeError('No free test port')
    base=f'http://127.0.0.1:{port}/api'
    with (tmp/'api.log').open('w') as log:
        proc=subprocess.Popen([rscript,'--vanilla',str(root/'webapp/backend/run_api.R')],env={**env,'API_PORT':str(port)},
                              cwd=tmp,stdout=log,stderr=log)
        try:
            for _ in range(300):
                if proc.poll() is not None:
                    raise RuntimeError((tmp/'api.log').read_text()[-1000:])
                try:
                    if call(base,'/health')[0]==200:
                        break
                except OSError:
                    pass
                time.sleep(.2)
            else:
                raise TimeoutError('R API startup')
            print(f'isolated API port {port}',flush=True)
            yield base
        finally:
            proc.terminate()
            proc.wait(timeout=15)
