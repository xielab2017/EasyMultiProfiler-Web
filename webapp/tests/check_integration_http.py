"""Run the repository's synthetic integration fixture through an isolated real R API.

Usage: python3 webapp/tests/check_integration_http.py [--rscript PATH]
The temporary API, storage and CLI outputs are created and removed by this check.
"""
import argparse
import copy
import csv
import hashlib
import io
import json
import math
import os
from pathlib import Path
from isolated_r_api import api_environment, isolated_r_api, call
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def run_job(base, payload):
    start = time.monotonic()
    status, receipt = call(base, '/integration/run', payload)
    assert status == 200 and receipt['kind'] == 'integration_exploration', receipt
    job_id = receipt['job_id']
    route = '/jobs/' + job_id
    while time.monotonic() - start < 120:
        status, state = call(base, route)
        assert status == 200, state
        job = state['job']
        if job['status'] == 'done':
            assert job['progress'] == 100
            break
        assert job['status'] in ('queued', 'running'), job
        time.sleep(.2)
    else:
        raise TimeoutError(job_id)
    status, result = call(base, route + '/result')
    assert status == 200 and result['contract'] == 'emp-integration-exploration-v1' and result['execution_performed']
    print(f"job={job_id} elapsed={time.monotonic()-start:.2f}s subjects={len(result['scores'])} tests={len(result['associations'])}", flush=True)
    return result


def update_block(payload, transform):
    block = payload['blocks'][0]
    rows = list(csv.reader(io.StringIO(block['data_csv'])))
    transform(rows)
    output = io.StringIO()
    csv.writer(output, lineterminator='\n').writerows(rows)
    block['data_csv'] = output.getvalue()
    block['source_sha256'] = hashlib.sha256(block['data_csv'].encode()).hexdigest()


def verify(base, fixture, reference, cli):
    status, preview = call(base, '/integration/preview', {'version': 1, 'blocks': fixture['blocks']})
    assert status == 200 and not preview['analysis_executed'] and len(preview['blocks']) == 6
    assert all(b['declared_source_sha256'] == b['input_sha256'] for b in preview['blocks'])

    def reject(name, payload, message):
        status, result = call(base, '/integration/run', payload)
        assert status == 400 and not result.get('success') and 'job_id' not in result, (name, status, result)
        assert message.lower() in result['error'].lower(), (name, result)
        print(f'{name}: HTTP {status}', flush=True)

    for field in ['confirmed','design_reviewed','preprocessing_reviewed']:
        reject(field, dict(fixture, **{field:False}), {'confirmed':'confirm','design_reviewed':'design','preprocessing_reviewed':'processed'}[field])
    bad = copy.deepcopy(fixture)
    bad['mapping'][0].pop('group')
    reject('missing group', bad, 'group')
    bad = copy.deepcopy(fixture)
    bad['blocks'][0]['scale'] = 'raw_counts'
    reject('raw counts', bad, 'processed')
    bad = copy.deepcopy(fixture)
    bad['mapping'][1]['subject'] = bad['mapping'][0]['subject']
    reject('duplicate subject', bad, 'repeated subjects')
    bad = copy.deepcopy(fixture)
    bad['mapping'][8]['group'] = 'wrong-group'
    reject('inconsistent group', bad, 'conflicting group')
    bad = copy.deepcopy(fixture)
    for row in bad['mapping'][8:16]:
        row['subject'] = 'independent-' + row['subject']
    reject('unmatched cohorts', dict(bad, allow_unmatched=True), 'fewer than four')
    missing = copy.deepcopy(fixture)

    def incomplete_and_constant(rows):
        rows[1][1] = 'NA'
        rows[2][1:] = ['5'] * (len(rows[2]) - 1)
    update_block(missing, incomplete_and_constant)
    reject('missing measurement', missing, 'missing measurements')
    missing['missing_policy'] = 'exclude_features'
    missing['mapping'][15]['subject'] = 'separate-unit'
    reject('partial overlap requires review', missing, 'unmatched subjects')
    missing['allow_unmatched'] = True
    clean = run_job(base, missing)
    assert len(clean['scores']) == 7 and len(clean['associations']) == 480
    exc = clean['exclusions']['block_1']
    assert exc['constant_features'] == ['feature_2'] and exc['incomplete_features'] == ['feature_1']
    assert exc['unmatched_subjects'] == ['simulated_subject_8']
    assert all(row['n'] == 7 for row in clean['associations']) and not clean['preprocessing']['imputation']

    def compare(result):
        assert len(result['scores'])==8 and len(result['associations'])==540
        for other in (reference,cli):
            for key in ['scores','associations']:
                assert len(other[key]) == len(result[key])
                for actual, expected in zip(result[key], other[key]):
                    for field, v in expected.items():
                        if field == '_row':
                            continue
                        if isinstance(v, (int,float)):
                            assert math.isclose(actual[field], v, rel_tol=1e-11, abs_tol=1e-12), (key,field,actual[field],v)
                        else:
                            assert actual[field] == v, (key,field,actual[field],v)
            assert all(math.isclose(x,y,abs_tol=1e-12) for x,y in zip(result['variance_explained'],other['variance_explained']))
    compare(run_job(base, fixture))
    # Reorder both a matrix's physical sample columns and its mapping rows.
    # The first block's subject order remains canonical, so numerical rows match.
    permuted = copy.deepcopy(fixture)
    permuted['blocks'][0], permuted['blocks'][1] = permuted['blocks'][1], permuted['blocks'][0]
    def reverse_samples(rows):
        for row in rows:
            row[1:] = reversed(row[1:])
    update_block(permuted, reverse_samples)
    permuted['blocks'][0], permuted['blocks'][1] = permuted['blocks'][1], permuted['blocks'][0]
    permuted['mapping'][8:16] = reversed(permuted['mapping'][8:16])
    compare(run_job(base, permuted))

    # 24 features per block, with deliberate ties and a perfectly matched high-variance pair.
    # This exercises the 20-feature cap and finite serialized probabilities at the boundary.
    capped = copy.deepcopy(fixture)
    capped['blocks'] = capped['blocks'][:2]
    capped['mapping'] = capped['mapping'][:16]
    for block in capped['blocks']:
        header = next(csv.reader(io.StringIO(block['data_csv'])))
        rows = [header] + [[f'rank_{i}', *[i*k for k in [0,0,1,1,2,2,3,3]]] for i in range(1,25)]
        output = io.StringIO()
        csv.writer(output,lineterminator='\n').writerows(rows)
        block['data_csv'] = output.getvalue()
        block['source_sha256'] = hashlib.sha256(block['data_csv'].encode()).hexdigest()
    selected = run_job(base,capped)
    assert len(selected['associations'])==400
    for field in ('feature_a','feature_b'):
        assert {e[field] for e in selected['associations']} == {f'rank_{i}' for i in range(5,25)}
    assert all(abs(e['rho']-1)<1e-12 and 0<=e['pvalue']<=e['padj']<1e-12 for e in selected['associations'])
    assert math.isclose(selected['variance_explained'][0],1,abs_tol=1e-12)
    assert math.isclose(selected['variance_explained'][1],0,abs_tol=1e-12)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rscript', default=str(ROOT/'.local_run/r-runtime/bin/Rscript') if (ROOT/'.local_run/r-runtime/bin/Rscript').exists() else shutil.which('Rscript'))
    args=parser.parse_args()
    if not args.rscript:
        parser.error('Rscript is required')
    with tempfile.TemporaryDirectory(prefix='emp-integration-http-') as temp:
        tmp=Path(temp)
        env=api_environment(tmp)
        env['EMP_INTEGRATION_TEST_OUT']=str(tmp/'fixture')
        subprocess.run([args.rscript,'--vanilla','webapp/tests/test_integration_workbench.R'],check=True,env=env,cwd=ROOT)
        src=tmp/'fixture/synthetic-input.json'
        out=tmp/'output with spaces'
        cmd=[args.rscript,'--vanilla',str(ROOT/'webapp/scripts/run_integration_workflow.R'),str(src),str(out)]
        subprocess.run(cmd,check=True,env=env,cwd=tmp)
        assert (out/'joint-pca.pdf').read_bytes().startswith(b'%PDF-')
        assert subprocess.run(cmd,env=env,cwd=tmp,capture_output=True).returncode!=0
        with isolated_r_api(ROOT,args.rscript,tmp,env) as base:
            verify(base,json.loads(src.read_text()),json.loads((tmp/'fixture/results.json').read_text()),json.loads((out/'integration-results.json').read_text()))

if __name__=='__main__':
    main()
