"""Contract/security tests with mocked HTTP only; these do not execute R."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest import mock
import urllib.error

spec = importlib.util.spec_from_file_location('r_analysis_bridge', Path(__file__).parents[1] / 'scripts/r_analysis_bridge.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
NOW = 2000000000
SESSION = 'A' * 24
JOB = '20261106123456.123-abcdefgh'


def dataset():
    return {'id': 'rna', 'omics': 'bulk_rnaseq', 'data_type': 'raw_counts',
            'sample_ids': ['A one', 'A two', 'B one', 'B two'],
            'feature_ids': ['1', '2', '3', '4'],
            'values': [[100, 120, 30, 40], [20, 30, 200, 230], [3, 20, 8, 12], [0, 0, 0, 0]],
            'provenance': {'source': 'Synthetic test fixture', 'sha256': 'd' * 64}}


def metadata():
    return [{'id': x, 'group': x[0]} for x in dataset()['sample_ids']]


def profile():
    return {'api_version': '1.0', 'package_version': '9.0.3',
            'package_versions': {'EasyMultiProfiler': '9.0.3', 'DESeq2': '1.44.0', 'tidybulk': '2.0.0', 'callr': '3.7.6'},
            'source_contract': m.SOURCE_CONTRACT, 'source_sha256': 'b' * 64, 'runtime_id': 'c' * 64,
            'running_code_verified': True, 'verified_at': NOW - 10, 'expires_at': NOW + 3000}


def plan_request():
    return {'data_id': 'matrix-id', 'metadata_id': 'metadata-id', 'ref_group': 'A', 'test_group': 'B',
            'design': {'group': 'group', 'independent_samples': True}, 'filter_low': True,
            'raw_counts_evidence': 'Synthetic unit-test counts generated as integers, not normalized expression.'}


class FakeAPI:
    def __init__(self):
        self.calls = []
        self.overrides = {}
        self.job_status = 'running'
        self.cancel_status = 'cancel_requested'
        self.experiment = None

    def request(self, method, path, payload=None):
        self.calls.append((method, path, copy.deepcopy(payload)))
        if path in self.overrides:
            result = self.overrides[path]
            if isinstance(result, Exception):
                raise result
            return result(method, path, payload) if callable(result) else copy.deepcopy(result)
        if path == '/api/health':
            return {'status': 'ok', 'version': '9.0.3'}
        if path == '/api/capabilities':
            return {'success': True, 'api_version': '1.0', 'package_version': '9.0.3',
                    'features': {'path_import': True, 'async_jobs': True, 'job_cancel': True},
                    'workflows': ['transcriptomics'], 'tools': ['emp.analyze.differential']}
        if path == '/api/import/path/preview':
            return {'success': True,
                    'data': {'path': payload['data_path'], 'sha256': hashlib.sha256(Path(payload['data_path']).read_bytes()).hexdigest(), 'orientation': 'features_in_rows', 'columns': 5},
                    'metadata': {'path': payload['metadata_path'], 'sha256': hashlib.sha256(Path(payload['metadata_path']).read_bytes()).hexdigest(), 'sample_id_column': 'sample_id'},
                    'sample_overlap': {'assay': 4, 'metadata': 4, 'matched': 4, 'assay_only': [], 'metadata_only': []}, 'warnings': []}
        if path == '/api/import/path':
            self.experiment = payload['experiment_name']
            return {'success': True, 'session_id': SESSION, 'experiment_name': self.experiment,
                    'samples': 4, 'features': 3, 'assay': 'counts'}
        if path == '/api/analyze/differential/async':
            return {'success': True, 'job_id': JOB}
        if path == '/api/jobs/' + JOB:
            return {'success': True, 'job': {'id': JOB, 'session_id': SESSION, 'kind': 'differential',
                    'status': self.job_status, 'progress': 80, 'error': 'never expose secret token/path', 'pid': 999}}
        if path == '/api/jobs/' + JOB + '/cancel':
            return {'success': True, 'cancellation': {'job_id': JOB, 'status': self.cancel_status}}
        if path.startswith('/api/analyze/diff_raw/'):
            rows = [{'feature': 'emp_feature_000001', 'baseMean': 80.5, 'log2FoldChange': -1.5, 'lfcSE': 0.2, 'stat': -7.5, 'pvalue': 0.0001, 'padj': 0.001},
                    {'feature': 'emp_feature_000002', 'baseMean': 120, 'log2FoldChange': 3.5, 'lfcSE': 0.6, 'stat': 5.8, 'pvalue': 0.03, 'padj': None}]
            return {'success': True, 'method': 'DESeq2', 'group_var': 'emp_group', 'ref_group': 'reference', 'test_group': 'test',
                    'n_rows': len(rows), 'columns': list(rows[0]), 'data': json.dumps(rows)}
        raise AssertionError('Unexpected endpoint: ' + path)


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.api = FakeAPI()
        self.now = NOW
        self.observed = {k: profile()[k] for k in ('runtime_id', 'source_sha256', 'package_versions')}
        self.bridge = m.RAnalysisBridge(self.temp.name, client=self.api, runtime_profile=profile(),
                                       runtime_probe=lambda: self.observed, clock=lambda: self.now)
        self.bridge.register_matrix('matrix-id', dataset())
        self.bridge.register_metadata('metadata-id', metadata())

    def prepare(self):
        result = self.bridge.prepare(plan_request())
        self.assertTrue(result['executable'], result.get('blockers'))
        return result

    def execute(self, plan=None):
        plan = plan or self.prepare()
        request = {'plan_id': plan['plan_id'], 'plan_sha256': plan['plan_sha256'], 'confirmed': True}
        return self.bridge.execute(request)

    def assertError(self, code, function, *args):
        with self.assertRaises(m.BridgeError) as caught:
            function(*args)
        self.assertEqual(caught.exception.code, code)
        return caught.exception

    def test_prepare_is_preview_only_and_exact_deterministic_digest(self):
        plan = self.prepare()
        self.assertFalse(plan['execution_performed'])
        self.assertTrue(plan['confirmation_required'])
        self.assertEqual(plan['contrast']['log2_fold_change'], 'test / reference')
        self.assertEqual(plan['n_features_after_zero_removal'], 3)
        digest = plan.pop('plan_sha256')
        self.assertEqual(digest, m._digest(plan))
        self.assertEqual([x[1] for x in self.api.calls], ['/api/health', '/api/capabilities', '/api/import/path/preview'])
        public = json.dumps(plan)
        self.assertNotIn(self.temp.name, public)
        content = (Path(self.temp.name) / plan['plan_id'] / 'counts.csv').read_text()
        self.assertIn('emp_feature_000001', content)
        self.assertNotIn('A one', content)
        self.assertIn('"100"', content)

    def test_no_profile_or_probe_is_fail_closed(self):
        for attr in ['_profile', '_probe']:
            with mock.patch.object(self.bridge, attr, None):
                plan = self.bridge.prepare(plan_request())
                self.assertFalse(plan['executable'])
                self.assertEqual(plan['blockers'][0]['code'], 'runtime_unverified')
                self.assertEqual(self.api.calls, [])

    def test_runtime_blocked_plan_does_not_generate_csv_or_write_inputs(self):
        with mock.patch.object(self.bridge, '_profile', None), mock.patch.object(self.bridge, '_csv', side_effect=AssertionError('No CSV serialization for blocked runtime')):
            plan = self.bridge.prepare(plan_request())
        self.assertFalse(plan['executable'])
        self.assertFalse(plan['inputs_staged'])
        self.assertEqual(plan['input_sha256'], {})
        self.assertEqual(list(Path(self.temp.name).iterdir()), [])
        self.assertEqual(plan['blockers'][0]['code'], 'runtime_unverified')
        self.assertEqual(self.api.calls, [])

    def test_matrix_and_metadata_registry_caps_reject_without_replacement(self):
        with mock.patch.object(m, 'MAX_MATRIX_RECORDS', 1):
            self.assertError('registry_limit', self.bridge.register_matrix, 'new', dataset())
        with mock.patch.object(m, 'MAX_REGISTRY_CELLS', 16):
            self.assertError('registry_limit', self.bridge.register_matrix, 'new', dataset())
        with mock.patch.object(m, 'MAX_REGISTRY_FEATURES', 4):
            self.assertError('registry_limit', self.bridge.register_matrix, 'new', dataset())
        with mock.patch.object(m, 'MAX_METADATA_RECORDS', 1):
            self.assertError('registry_limit', self.bridge.register_metadata, 'new', metadata())
        self.assertEqual(list(self.bridge._matrices), ['matrix-id'])
        self.assertEqual(list(self.bridge._metadata), ['metadata-id'])
        self.assertEqual(self.bridge._registry_cells, 16)
        self.assertEqual(self.bridge._registry_features, 4)

    def test_blocked_plans_count_toward_plan_limit_before_work(self):
        with mock.patch.object(self.bridge, '_profile', None), mock.patch.object(m, 'MAX_PLANS', 1):
            plan = self.bridge.prepare(plan_request())
            self.assertError('plan_limit', self.bridge.prepare, plan_request())
        self.assertEqual(list(self.bridge._plans), [plan['plan_id']])
        self.assertEqual(list(Path(self.temp.name).iterdir()), [])
        self.assertEqual(self.api.calls, [])

    def test_single_flight_prepare_prevents_concurrent_limit_bypass(self):
        self.assertTrue(self.bridge._prepare_lock.acquire(blocking=False))
        try:
            self.assertError('prepare_busy', self.bridge.prepare, plan_request())
        finally:
            self.bridge._prepare_lock.release()
        self.assertEqual(self.api.calls, [])
        self.assertEqual(self.bridge._plans, {})
        self.prepare()  # The rejected call did not poison the lock.

    def test_low_disk_blocks_staging_without_deletion(self):
        marker = Path(self.temp.name) / 'owner-retained.txt'; marker.write_text('retain')
        with mock.patch.object(m.shutil, 'disk_usage', return_value=mock.Mock(free=m.MIN_DISK_FREE_BYTES)):
            plan = self.bridge.prepare(plan_request())
        self.assertFalse(plan['executable'])
        self.assertFalse(plan['inputs_staged'])
        self.assertEqual(plan['blockers'][0]['code'], 'disk_reserve')
        self.assertEqual(marker.read_text(), 'retain')
        self.assertEqual(list(Path(self.temp.name).iterdir()), [marker])
        self.assertNotIn('/api/import/path/preview', [path for _, path, _ in self.api.calls])

    def test_per_plan_and_total_staging_byte_caps(self):
        with mock.patch.object(m, 'MAX_PLAN_STAGING_BYTES', 1):
            plan = self.bridge.prepare(plan_request())
        self.assertEqual(plan['blockers'][0]['code'], 'staging_limit')
        self.assertFalse(plan['inputs_staged'])
        self.assertEqual(list(Path(self.temp.name).iterdir()), [])
        marker = Path(self.temp.name) / 'prior-instance.csv'; marker.write_bytes(b'x' * 100)
        with mock.patch.object(m, 'MAX_TOTAL_STAGING_BYTES', 100):
            plan = self.bridge.prepare(plan_request())
        self.assertEqual(plan['blockers'][0]['code'], 'staging_limit')
        self.assertEqual(marker.read_bytes(), b'x' * 100)
        self.assertEqual(list(Path(self.temp.name).iterdir()), [marker])

    def test_staging_entry_bound_and_symlink_fail_closed(self):
        marker = Path(self.temp.name) / 'retained'; marker.mkdir()
        with mock.patch.object(m, 'MAX_STAGING_ENTRIES', 3):
            plan = self.bridge.prepare(plan_request())
        self.assertEqual(plan['blockers'][0]['code'], 'staging_limit')
        link = Path(self.temp.name) / 'linked'; link.symlink_to(marker, target_is_directory=True)
        plan = self.bridge.prepare(plan_request())
        self.assertEqual(plan['blockers'][0]['code'], 'staging_unavailable')
        self.assertTrue(link.is_symlink())
        self.assertEqual(sorted(path.name for path in Path(self.temp.name).iterdir()), ['linked', 'retained'])

    def test_disk_reserve_rechecked_before_import(self):
        plan = self.prepare()
        with mock.patch.object(m.shutil, 'disk_usage', return_value=mock.Mock(free=m.MIN_DISK_FREE_BYTES - 1)):
            execution = self.execute(plan)
        self.assertEqual(execution['status'], 'preflight_failed')
        self.assertEqual(execution['error']['code'], 'disk_reserve')
        self.assertFalse(execution['execution_performed'])
        self.assertFalse(any(path == '/api/import/path' for _, path, _ in self.api.calls))

    def test_disk_probe_failure_is_a_safe_blocker(self):
        with mock.patch.object(m.shutil, 'disk_usage', side_effect=OSError('private filesystem path')):
            plan = self.bridge.prepare(plan_request())
        self.assertEqual(plan['blockers'][0]['code'], 'staging_unavailable')
        self.assertNotIn('private filesystem', json.dumps(plan))
        self.assertEqual(list(Path(self.temp.name).iterdir()), [])

    def test_runtime_identity_source_packages_and_running_attestation(self):
        for field in ['runtime_id', 'source_sha256', 'package_versions']:
            saved = self.observed[field]
            self.observed[field] = 'changed'
            plan = self.bridge.prepare(plan_request())
            self.assertEqual(plan['blockers'][0]['code'], 'runtime_changed')
            self.observed[field] = saved
        self.bridge._profile['running_code_verified'] = False
        self.assertEqual(self.bridge.prepare(plan_request())['blockers'][0]['code'], 'runtime_unverified')

    def test_versions_capabilities_and_missing_package_block(self):
        self.api.overrides['/api/health'] = {'status': 'ok', 'version': '9.1.0'}
        self.assertEqual(self.bridge.prepare(plan_request())['blockers'][0]['code'], 'r_version_mismatch')
        self.api.overrides.clear()
        self.api.overrides['/api/capabilities'] = {'success': True, 'api_version': '1.0', 'package_version': '9.0.3', 'features': {}}
        self.assertEqual(self.bridge.prepare(plan_request())['blockers'][0]['code'], 'r_capabilities')
        self.bridge._profile['package_versions'].pop('DESeq2')
        self.assertEqual(self.bridge.prepare(plan_request())['blockers'][0]['code'], 'runtime_unverified')

    def test_profile_expiry_blocks_new_execution(self):
        plan = self.prepare()
        self.now = NOW + 4000
        execution = self.execute(plan)
        self.assertEqual(execution['status'], 'preflight_failed')
        self.assertNotIn('/api/import/path', [x[1] for x in self.api.calls])

    def test_expired_attestation_can_poll_and_cancel_existing_identical_process(self):
        execution = self.execute()
        self.now = NOW + 4000
        self.assertEqual(self.bridge.poll({'execution_id': execution['execution_id']})['status'], 'running')
        self.assertEqual(self.bridge.cancel({'execution_id': execution['execution_id']})['status'], 'cancel_requested')
        self.observed['runtime_id'] = 'f' * 64
        self.assertError('runtime_changed', self.bridge.cancel, {'execution_id': execution['execution_id']})

    def test_raw_counts_never_rounded_and_type_bounds(self):
        for value in [0.00000000001, 2.000000000000001, -1, 2147483648, float('nan'), float('inf'), True, '2', None, 10 ** 1000]:
            data = dataset(); data['values'][0][0] = value
            self.assertError('invalid_raw_counts', self.bridge.register_matrix, 'new', data)
        data = dataset(); data['values'][0][0] = 100.0
        self.bridge.register_matrix('integer-float', data)

    def test_only_raw_bulk_rna_and_bounded_matrix(self):
        for field, value in [('omics', 'proteomics'), ('data_type', 'tpm'), ('data_type', 'normalized')]:
            data = dataset(); data[field] = value
            self.assertError('unsupported_input', self.bridge.register_matrix, 'new', data)
        data = dataset(); data['values'][0].pop()
        self.assertError('matrix_shape', self.bridge.register_matrix, 'new', data)
        data = dataset(); data['sample_ids'][0] = data['sample_ids'][1]
        self.assertError('duplicate_id', self.bridge.register_matrix, 'new', data)

    def test_provenance_and_explicit_raw_count_evidence_required(self):
        for provenance in [{}, {'source': 'Synthetic test'}, {'source': '', 'sha256': 'd' * 64}, {'source': 'Synthetic test', 'sha256': 'bad'}]:
            data = dataset(); data['provenance'] = provenance
            self.assertError('provenance', self.bridge.register_matrix, 'new', data)
        for value in [None, '', '  guessed', 'line\nsecret', 'x' * 2049]:
            request = plan_request(); request['raw_counts_evidence'] = value
            self.assertError('raw_counts_evidence', self.bridge.prepare, request)
        plan = self.prepare()
        self.assertEqual(plan['raw_counts_evidence'], plan_request()['raw_counts_evidence'])
        self.assertFalse(plan['raw_count_provenance_verified'])

    def test_native_filter_always_disclosed_even_when_filter_low_false(self):
        request = plan_request(); request['filter_low'] = False
        plan = self.bridge.prepare(request)
        self.assertTrue(plan['executable'])
        self.assertFalse(plan['parameters']['filter_low'])
        self.assertEqual(plan['native_result_filter'], {'minimum_positive_samples': 3, 'eligible_features': 3,
                         'applies_even_if_filter_low_false': True, 'drops_missing_pvalue_rows': True})

    def test_zero_libraries_and_unsupported_size_factors(self):
        data = dataset()
        for row in data['values']: row[0] = 0
        self.assertError('zero_counts', self.bridge.register_matrix, 'zero', data)
        data = dataset()
        for i, row in enumerate(data['values']): row[i % 4] = 0
        self.assertError('size_factors_unavailable', self.bridge.register_matrix, 'sparse', data)

    def test_registry_snapshots_immutable(self):
        data = dataset(); self.bridge.register_matrix('second', data)
        data['values'][0][0] = -100
        request = plan_request(); request['data_id'] = 'second'
        self.assertTrue(self.bridge.prepare(request)['executable'])
        self.assertError('duplicate_record', self.bridge.register_matrix, 'matrix-id', dataset())
        self.assertError('duplicate_record', self.bridge.register_metadata, 'metadata-id', metadata())

    def test_public_schema_never_accepts_paths_urls_code_credentials(self):
        for key in ['data_path', 'metadata_path', 'url', 'token', 'code', 'formula', 'alpha', 'min_count']:
            request = plan_request(); request[key] = 'untrusted'
            self.assertError('invalid_request', self.bridge.prepare, request)
        for value in ['../data', '/tmp/data', 'https://example.test', 'a?x=1']:
            request = plan_request(); request['data_id'] = value
            self.assertError('invalid_id', self.bridge.prepare, request)
        self.assertEqual(self.api.calls, [])

    def test_design_rejects_batch_paired_covariates_and_no_confirmation(self):
        for key in ['batch', 'subject', 'paired', 'formula', 'covariates']:
            request = plan_request(); request['design'][key] = 'unsupported'
            self.assertError('invalid_request', self.bridge.prepare, request)
        request = plan_request(); request['design']['independent_samples'] = False
        self.assertError('unsupported_design', self.bridge.prepare, request)
        for mode in ['batch', 'subject']:
            samples = metadata()
            for row in samples: row[mode] = 'same'
            self.bridge.register_metadata(mode, samples)
            request = plan_request(); request['metadata_id'] = mode
            self.assertError('unsupported_design', self.bridge.prepare, request)

    def test_exact_two_groups_replicates_and_sample_matching(self):
        request = plan_request(); request['test_group'] = 'A'
        self.assertError('unsupported_contrast', self.bridge.prepare, request)
        for name, alter in [('mismatch', lambda rows: rows[0].update(id='unknown')), ('replicates', lambda rows: rows[0].update(group='B')), ('extra_group', lambda rows: rows[0].update(group='C'))]:
            rows = metadata(); alter(rows)
            self.bridge.register_metadata(name, rows)
            request = plan_request(); request['metadata_id'] = name
            self.assertError('sample_mismatch' if name == 'mismatch' else 'unsupported_contrast', self.bridge.prepare, request)

    def test_exact_confirmation_and_duplicate_submit(self):
        plan = self.prepare()
        for confirmed, digest in [(False, plan['plan_sha256']), (True, 'wrong'), ('true', plan['plan_sha256'])]:
            self.assertError('confirmation_required', self.bridge.execute, {'plan_id': plan['plan_id'], 'confirmed': confirmed, 'plan_sha256': digest})
        first, second = self.execute(plan), self.execute(plan)
        self.assertEqual(first, second)
        submissions = [x for x in self.api.calls if x[1] == '/api/analyze/differential/async']
        self.assertEqual(len(submissions), 1)
        payload = submissions[0][2]
        self.assertEqual(payload['method'], 'DESeq2')
        self.assertEqual(payload['group_var'], 'emp_group')
        self.assertEqual(payload['ref_group'], 'reference')
        self.assertEqual(payload['test_group'], 'test')
        self.assertEqual(payload['cores'], 1)
        self.assertNotIn('tx_run_differential', str(self.api.calls))

    def test_concurrent_duplicate_execute_submits_once(self):
        plan = self.prepare()
        gate, release = threading.Event(), threading.Event()
        def imported(method, path, payload):
            gate.set(); release.wait(3)
            return {'success': True, 'session_id': SESSION, 'experiment_name': payload['experiment_name'], 'samples': 4, 'features': 3, 'assay': 'counts'}
        self.api.overrides['/api/import/path'] = imported
        results = []
        thread = threading.Thread(target=lambda: results.append(self.execute(plan)))
        thread.start(); self.assertTrue(gate.wait(2))
        other = self.execute(plan)
        self.assertEqual(other['status'], 'importing')
        release.set(); thread.join(3)
        self.assertFalse(thread.is_alive())
        self.assertEqual(results[0]['execution_id'], other['execution_id'])
        self.assertEqual(sum(path == '/api/analyze/differential/async' for _, path, _ in self.api.calls), 1)

    def test_changed_file_checksum_or_symlink_stops_before_import(self):
        plan = self.prepare()
        path = Path(self.temp.name) / plan['plan_id'] / 'counts.csv'
        path.write_text('changed')
        result = self.execute(plan)
        self.assertEqual(result['status'], 'preflight_failed')
        self.assertEqual(result['error']['code'], 'input_changed')
        plan = self.prepare(); path = Path(self.temp.name) / plan['plan_id'] / 'metadata.csv'
        content = path.read_bytes(); path.unlink()
        target = Path(self.temp.name) / 'other.csv'; target.write_bytes(content); path.symlink_to(target)
        self.assertEqual(self.execute(plan)['error']['code'], 'input_changed')
        self.assertFalse(any(path == '/api/import/path' for _, path, _ in self.api.calls))

    def test_preview_bad_hash_or_matching_blocks(self):
        original = self.api.request
        def mismatch(method, path, payload):
            self.api.overrides.pop(path)
            result = original(method, path, payload)
            result['data']['sha256'] = '0' * 64
            return result
        self.api.overrides['/api/import/path/preview'] = mismatch
        self.assertEqual(self.bridge.prepare(plan_request())['blockers'][0]['code'], 'r_preview_mismatch')

    def test_import_dimensions_verified_before_analysis(self):
        self.api.overrides['/api/import/path'] = {'success': True, 'session_id': SESSION, 'samples': 1, 'features': 3, 'assay': 'counts'}
        result = self.execute()
        self.assertEqual(result['status'], 'error')
        self.assertTrue(result['session_created'])
        self.assertFalse(result['execution_performed'])
        self.assertFalse(any(path == '/api/analyze/differential/async' for _, path, _ in self.api.calls))

    def test_uncertain_post_is_never_retried_or_claimed_not_run(self):
        self.api.overrides['/api/analyze/differential/async'] = m.BridgeError('r_unavailable', 'Sanitized error', uncertain=True)
        plan = self.prepare(); result = self.execute(plan)
        self.assertEqual(result['status'], 'submission_uncertain')
        self.assertTrue(result['needs_reconciliation'])
        self.assertIsNone(result['execution_performed'])
        self.assertFalse(result['retry_allowed'])
        self.assertEqual(self.execute(plan), result)
        self.assertEqual(sum(path == '/api/analyze/differential/async' for _, path, _ in self.api.calls), 1)

    def test_poll_done_returns_actual_native_table_and_original_feature_ids(self):
        result = self.execute(); self.api.job_status = 'done'
        completed = self.bridge.poll({'execution_id': result['execution_id']})
        self.assertEqual(completed['status'], 'completed')
        self.assertEqual(completed['result']['source'], 'local_R_native_diff_raw')
        self.assertEqual(completed['result']['data'][0]['feature'], '1')
        self.assertEqual(completed['result']['data'][0]['log2FoldChange'], -1.5)
        self.assertIsNone(completed['result']['data'][1]['padj'])
        self.assertNotIn('never expose', json.dumps(completed))
        self.assertNotIn('_session_id', completed)
        calls = len(self.api.calls)
        self.assertEqual(self.bridge.poll({'execution_id': result['execution_id']}), completed)
        self.assertEqual(len(self.api.calls), calls)

    def test_missing_or_fallback_raw_result_never_becomes_success(self):
        for problem in ['missing', 'limma', 'contrast', 'feature', 'pvalue', 'compact_fallback']:
            result = self.execute(); self.api.job_status = 'done'
            path = '/api/analyze/diff_raw/' + SESSION + '/' + self.api.experiment
            raw = self.api.request('GET', path)
            if problem == 'missing': self.api.overrides[path] = m.BridgeError('r_http_error', 'Missing result')
            else:
                if problem == 'limma': raw['method'] = 'limma'
                if problem == 'contrast': raw['ref_group'] = 'test'
                if problem == 'compact_fallback':
                    rows = json.loads(raw['data']); rows[0]['lfcSE'] = None; rows[0]['stat'] = None; raw['data'] = json.dumps(rows)
                if problem in {'feature', 'pvalue'}:
                    rows = json.loads(raw['data']); rows[0][problem] = 'unknown' if problem == 'feature' else 3.0; raw['data'] = json.dumps(rows)
                self.api.overrides[path] = raw
            completed = self.bridge.poll({'execution_id': result['execution_id']})
            self.assertEqual(completed['status'], 'result_unverified', problem)
            self.assertNotIn('result', completed)

    def test_remote_error_no_fallback_and_no_server_error_leak(self):
        result = self.execute(); self.api.job_status = 'error'
        self.assertEqual(self.bridge.poll({'execution_id': result['execution_id']})['status'], 'error')
        state = self.bridge.poll({'execution_id': result['execution_id']})
        self.assertNotIn('secret', json.dumps(state))
        self.assertEqual(sum(path == '/api/analyze/differential/async' for _, path, _ in self.api.calls), 1)

    def test_job_poll_ownership_and_cancel_contract(self):
        result = self.execute()
        self.assertError('unknown_execution', self.bridge.poll, {'execution_id': 'not-owned'})
        self.assertError('invalid_request', self.bridge.cancel, {'execution_id': result['execution_id'], 'job_id': JOB})
        cancelled = self.bridge.cancel({'execution_id': result['execution_id']})
        self.assertEqual(cancelled['status'], 'cancel_requested')
        self.api.cancel_status = 'cancelled'
        self.assertEqual(self.bridge.cancel({'execution_id': result['execution_id']})['status'], 'cancelled')
        count = len(self.api.calls)
        self.bridge.cancel({'execution_id': result['execution_id']})
        self.assertEqual(len(self.api.calls), count)

    def test_already_finished_cancel_is_not_claimed_cancelled(self):
        result = self.execute(); self.api.cancel_status = 'already_finished'
        state = self.bridge.cancel({'execution_id': result['execution_id']})
        self.assertEqual(state['status'], 'queued')
        self.assertEqual(state['cancellation']['status'], 'already_finished')

    def test_cancel_timeout_stays_uncertain_without_false_cancel_state(self):
        result = self.execute()
        self.api.overrides['/api/jobs/' + JOB + '/cancel'] = m.BridgeError('r_unavailable', 'Timeout', uncertain=True)
        error = self.assertError('r_unavailable', self.bridge.cancel, {'execution_id': result['execution_id']})
        self.assertTrue(error.uncertain)
        self.assertEqual(self.bridge._executions[result['execution_id']]['status'], 'queued')


class HTTPClientTests(unittest.TestCase):
    def client(self, response):
        client = m.LocalRClient('SERVER-ONLY-SECRET')
        response.status = 200
        client._opener = mock.MagicMock()
        client._opener.open.return_value.__enter__.return_value = response
        return client

    def test_fixed_loopback_bearer_no_redirect_no_proxy(self):
        response = mock.Mock(); response.read.return_value = b'{"status":"ok","version":"9.0.3"}'
        client = self.client(response)
        self.assertEqual(client.request('GET', '/api/health')['status'], 'ok')
        request = client._opener.open.call_args.args[0]
        self.assertEqual(request.full_url, 'http://127.0.0.1:8000/api/health')
        self.assertEqual(request.get_header('Authorization'), 'Bearer SERVER-ONLY-SECRET')
        self.assertNotIn('SERVER-ONLY-SECRET', repr(client))
        self.assertIsNone(m._NoRedirect().redirect_request(None, None, 302, '', {}, 'https://evil.test'))
        with mock.patch.object(m.urllib.request, 'build_opener') as builder:
            m.LocalRClient()
            self.assertEqual(builder.call_args.args[0].proxies, {})

    def test_arbitrary_endpoints_and_query_strings_blocked_before_http(self):
        response = mock.Mock(); client = self.client(response)
        for method, path in [('POST', '/api/workflows/transcriptomics/differential'), ('POST', '/api/user_r'), ('GET', '/api/health?token=secret'), ('GET', 'https://evil.test/api/health'), ('GET', '/api/jobs/../other')]:
            with self.assertRaises(m.BridgeError): client.request(method, path)
        client._opener.open.assert_not_called()

    def test_no_auth_headers_or_remote_errors_leaked(self):
        response = mock.Mock(); client = self.client(response)
        client._opener.open.side_effect = urllib.error.HTTPError('http://secret@host/private', 500, 'SERVER-ONLY-SECRET', {}, None)
        with self.assertRaises(m.BridgeError) as caught:
            client.request('POST', '/api/import/path', {})
        self.assertTrue(caught.exception.uncertain)
        self.assertNotIn('SECRET', json.dumps(caught.exception.as_dict()))
        self.assertNotIn('private', str(caught.exception))

    def test_invalid_json_and_size_limits(self):
        for data in [b'not json', b'[]', b'{"x":NaN}', b'{"success":false,"error":"SECRET"}', b'x' * (m.MAX_RESPONSE_BYTES + 1)]:
            response = mock.Mock(); response.read.return_value = data
            client = self.client(response)
            with self.assertRaises(m.BridgeError) as caught: client.request('POST', '/api/import/path', {})
            self.assertTrue(caught.exception.uncertain)
            self.assertNotIn('SECRET', str(caught.exception))

    def test_crlf_or_non_ascii_tokens_rejected(self):
        for token in ['bad\r\nX: token', '密钥', None]:
            with self.assertRaises(m.BridgeError): m.LocalRClient(token)


if __name__ == '__main__':
    unittest.main()
