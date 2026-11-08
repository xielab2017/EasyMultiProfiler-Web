"""Real local parsing and HTTP boundaries; no external downloads or model calls."""
import copy
import gzip
import hashlib
import http.client
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
import omics_workbench as wb
import public_data_server
import agent_context
import agent_adapter

RAW = b'gene\tLength\tA1\tA2\tB1\tB2\ng1\t500\t10\t12\t30\t32\ng2\t800\t50\t55\t9\t8\ng0\t900\t0\t0\t0\t0\n'


class MatrixProfileTests(unittest.TestCase):
    def test_numeric_profile_is_evidence_not_an_omics_or_group_claim(self):
        p=wb.matrix_profile(wb.inspect(RAW,'counts.tsv'))
        self.assertTrue(p['count_compatible']);self.assertEqual(p['candidate_sample_columns'],4)
        self.assertEqual(p['omics_candidates'],[]);self.assertFalse(p['raw_count_provenance_verified'])
        p=wb.matrix_profile(wb.inspect(b'Protein.Group\tProtein.Ids\tA\tB\nP1\tU1\t1.5\tNA\nP2\tU2\t2.5\t-1\n','protein.tsv'))
        self.assertFalse(p['count_compatible']);self.assertEqual(p['omics_candidates'],['proteomics'])
        self.assertEqual(p['missing_or_nonfinite_cells'],1);self.assertEqual(p['negative_cells'],1)

class WorkbenchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.service = wb.Workbench(self.temp.name)
        self.input = self.service.ingest(gzip.compress(RAW), 'counts.tsv.gz', 'Synthetic integer test fixture')
        self.dataset = self.service.select(self.input['input_id'], ['A1', 'A2', 'B1', 'B2'])
        self.plan = {'version': 1, 'dataset_id': self.dataset['dataset_id'], 'omics': 'bulk_rnaseq', 'data_type': 'raw_counts',
                     'samples': [{'id': x, 'group': x[0]} for x in self.dataset['sample_ids']],
                     'design': {'test': 'B', 'reference': 'A', 'independent_samples': True},
                     'seed': 1234, 'raw_counts_evidence': 'Synthetic test fixture, unnormalized counts.',
                     'steps': wb.steps_for(['qc', 'normalize', 'pca', 'deseq2', 'heatmap'])}
        self.plan['steps'][-1]['parameters']['top_n'] = 3

    def test_explicit_columns_preserve_original_and_digest(self):
        self.assertEqual(self.input['data_type'], 'unknown')
        self.assertEqual(self.input['suggested_annotation_columns'], ['Length'])
        self.assertEqual(self.dataset['excluded_columns'], ['Length'])
        self.assertEqual(self.dataset['all_zero_features'], 1)
        self.assertEqual(self.dataset['library_sizes'], [60, 67, 39, 40])
        original = next(Path(self.temp.name).glob('*.original')).read_bytes()
        self.assertEqual(gzip.decompress(original), RAW)
        self.assertEqual(hashlib.sha256(original).hexdigest(), self.input['source_sha256'])

    def test_immutable_preparation_matches_matrix_and_plan_hash(self):
        prepared = self.service.prepare(self.plan)
        self.assertTrue(prepared['valid'], prepared)
        payload = self.service.payload(prepared['prepared_id'])
        self.assertEqual(hashlib.sha256(payload['plan_json'].encode()).hexdigest(), payload['plan_sha256'])
        self.assertEqual(hashlib.sha256(payload['matrix_csv'].encode()).hexdigest(), prepared['plan']['input_sha256'])
        self.plan['samples'][0]['group'] = 'changed'
        self.assertEqual(json.loads(payload['plan_json'])['samples'][0]['group'], 'A')
        payload['matrix_csv'] = 'changed'
        self.assertNotEqual(self.service.payload(prepared['prepared_id'])['matrix_csv'], 'changed')
        self.assertFalse(prepared['execution_performed'])

    def test_scientific_and_operation_boundaries(self):
        changes = [lambda p: p.update(data_type='tpm'),
                   lambda p: p['samples'][0].update(id='missing'),
                   lambda p: p['samples'][0].update(batch='b1'),
                   lambda p: p['design'].update(independent_samples=False),
                   lambda p: p['design'].update(reference='B'),
                   lambda p: p['samples'][0].update(group='B'),
                   lambda p: p.update(raw_counts_evidence=''),
                   lambda p: p.update(steps=wb.steps_for(['qc', 'pca'])),
                   lambda p: p['steps'][3]['parameters'].update(alpha=2),
                   lambda p: p['steps'][3]['parameters'].update(min_samples=999),
                   lambda p: p['steps'][0].update(operation='system'),
                   lambda p: p['steps'][0].update(code='stop()')]
        for change in changes:
            p = copy.deepcopy(self.plan); change(p)
            self.assertFalse(self.service.prepare(p)['valid'], p)
        self.assertEqual(list(Path(self.temp.name).glob('*.plan.json')), [])

    def test_no_rounding_filling_or_silent_duplicate_removal(self):
        for value in [b'-1', b'NaN', b'1.2', b'', b'2147483648', b'1e2']:
            data = wb.inspect(RAW.replace(b'\t10\t', b'\t' + value + b'\t'), 'counts.tsv')
            with self.assertRaises(ValueError): wb.select_counts(data, ['A1', 'A2', 'B1', 'B2'])
        with self.assertRaises(ValueError): wb.inspect(RAW.replace(b'g2\t', b'g1\t'), 'counts.tsv')
        with self.assertRaises(ValueError): wb.inspect(RAW.replace(b'\tA2\t', b'\tA1\t'), 'counts.tsv')
        with self.assertRaises(ValueError): wb.inspect(b'binary', 'counts.h5ad')

    def test_rule_mode_never_invents_metadata_or_claims_execution(self):
        draft = wb.propose('对 GSE60450 做完整 RNA-seq 差异分析和 PCA')
        self.assertEqual(draft['mode'], 'local_rules')
        self.assertEqual(draft['accession'], 'GSE60450')
        self.assertEqual([s['operation'] for s in draft['steps']], ['qc', 'normalize', 'pca', 'deseq2', 'heatmap'])
        self.assertIn('edger', [s['operation'] for s in wb.propose('使用 edgeR 做完整差异分析')['steps']])
        self.assertFalse(draft['execution_performed'])
        for question in ['TPM 做差异', '配对 RNA-seq', '单细胞', '包含批次', '代谢组分析']:
            self.assertEqual(wb.propose(question)['status'], 'needs_specialist_workflow')

    def test_agent_tool_cannot_execute_and_context_excludes_sensitive_labels(self):
        call = {'id': 'tool1', 'type': 'function', 'function': {'name': 'propose_count_workflow', 'arguments': json.dumps({'question': 'PCA'})}}
        name, args = agent_adapter._arguments(call)
        self.assertEqual([s['operation'] for s in agent_adapter._run(name, args)['steps']], ['qc', 'normalize', 'pca'])
        prepared = self.service.prepare(self.plan)
        summary = agent_context.prepare({'workbench': prepared['plan']})
        text = json.dumps(summary)
        self.assertNotIn('Synthetic', text)
        self.assertNotIn('A1', text)
        self.assertNotIn('raw_counts_evidence', text)
        self.assertFalse(summary['workbench']['execution_performed'])

    def test_multi_group_contrasts_and_review_are_part_of_immutable_plan(self):
        raw = b'gene\tA1\tA2\tB1\tB2\tC1\tC2\ng1\t10\t20\t30\t40\t50\t60\ng2\t60\t50\t40\t30\t20\t10\n'
        item = self.service.ingest(raw, 'synthetic.tsv', 'Synthetic test only')
        dataset = self.service.select(item['input_id'], ['A1','A2','B1','B2','C1','C2'])
        plan = copy.deepcopy(self.plan)
        plan.update(dataset_id=dataset['dataset_id'],samples=[{'id':name,'group':name[0]} for name in dataset['sample_ids']],steps=wb.steps_for(['qc','edger']))
        plan['design']['contrasts']=[{'test':'B','reference':'A'},{'test':'C','reference':'A'}]
        plan['grouping_review']={'confirmed':True,'method':'manual','field':'','metadata_sha256':'','paper':{},'sample_rows':[dict(row,gsm='',match='unmatched',evidence='Manual test label') for row in plan['samples']]}
        prepared=self.service.prepare(plan)
        self.assertTrue(prepared['valid'],prepared)
        self.assertEqual(len(prepared['plan']['design']['contrasts']),2)
        snapshot=json.loads(self.service.payload(prepared['prepared_id'])['plan_json'])
        self.assertTrue(snapshot['grouping_review']['confirmed'])
        for modify in [lambda p:p['design']['contrasts'].append({'test':'B','reference':'A'}),lambda p:p['design']['contrasts'][0].update(test='unknown'),lambda p:p['grouping_review'].update(confirmed=False),lambda p:p['grouping_review']['sample_rows'][0].update(group='changed')]:
            changed=copy.deepcopy(plan);modify(changed);self.assertFalse(self.service.prepare(changed)['valid'])


class WorkbenchHTTPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.server = public_data_server.make_server(0)
        cls.server.omics_workbench = wb.Workbench(cls.temp.name)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True); cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.thread.join(); cls.temp.cleanup()

    def call(self, path, body=None, headers=None):
        conn = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=5)
        h = {'Content-Type': 'application/json', **(headers or {})}
        conn.request('GET' if body is None else 'POST', '/api/public-data/' + path,
                     body=body if isinstance(body, bytes) else json.dumps(body) if body is not None else None, headers=h)
        response = conn.getresponse(); result = response.status, json.loads(response.read()); conn.close(); return result

    def test_upload_select_prepare_context_and_origin(self):
        status, value = self.call('workbench/upload', RAW, {'Content-Type': 'application/octet-stream', 'X-Matrix-Name': 'counts.tsv'})
        self.assertEqual(status, 200, value)
        status, dataset = self.call('workbench/select', {'input_id': value['input_id'], 'sample_columns': ['A1', 'A2', 'B1', 'B2']})
        self.assertEqual(status, 200)
        plan = {'version': 1, 'dataset_id': dataset['dataset_id'], 'omics': 'bulk_rnaseq', 'data_type': 'raw_counts',
                'samples': [{'id': x, 'group': x[0]} for x in dataset['sample_ids']],
                'design': {'test': 'B', 'reference': 'A', 'independent_samples': True},
                'seed': 1234, 'raw_counts_evidence': 'Synthetic unnormalized counts.', 'steps': wb.steps_for(['qc'])}
        status, prepared = self.call('workbench/prepare', {'plan': plan})
        self.assertEqual(status, 200); self.assertTrue(prepared['valid'], prepared)
        status, context = self.call('agent/context-preview', {'context_ids': {'workbench_id': prepared['prepared_id']}})
        self.assertEqual(status, 200); self.assertEqual(context['workbench']['sample_count'], 4)
        self.assertEqual(self.call('workbench/prepared/' + prepared['prepared_id'])[0], 200)
        self.assertEqual(self.call('workbench/catalog', headers={'Origin': 'https://evil.test'})[0], 403)
        self.assertEqual(self.call('workbench/catalog', headers={'X-Forwarded-Host': 'public.example'})[0], 403)
        self.assertEqual(self.call('workbench/upload', RAW, {'Content-Type': 'text/plain'})[0], 415)
        self.assertEqual(self.call('workbench/execute', {})[0], 404)

    def test_ingest_uses_completed_manager_only_never_client_paths(self):
        self.assertEqual(self.call('workbench/ingest', {'job_id': 'fake', 'path': '/tmp/x'})[0], 400)
        fake_manager = mock.Mock()
        receipt = {'source_name': 'counts.tsv', 'source_url': 'Synthetic fixture', 'bytes': len(RAW)}
        fake_manager.get.return_value = {'status': 'completed', 'receipt': receipt}
        fake_manager.open_completed.return_value = (__import__('io').BytesIO(RAW), receipt)
        with mock.patch('workbench_api.matrix_api.manager', return_value=fake_manager):
            self.assertEqual(self.call('workbench/ingest', {'job_id': 'opaque-completed-id'})[0], 200)
            fake_manager.open_completed.assert_called_once_with('opaque-completed-id')
        fake_manager.open_completed.reset_mock()
        fake_manager.get.return_value = {'status': 'completed', 'receipt': {**receipt, 'bytes': wb.MAX_BYTES + 1}}
        with mock.patch('workbench_api.matrix_api.manager', return_value=fake_manager):
            self.assertEqual(self.call('workbench/ingest', {'job_id': 'opaque-completed-id'})[0], 400)
            fake_manager.open_completed.assert_not_called()


if __name__ == '__main__': unittest.main()
