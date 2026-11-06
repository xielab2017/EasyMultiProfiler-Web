"""Offline context boundary checks: projection never reads a file or URL."""
import json
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import agent_context as context


def snapshot():
    return {'manifest': {'status': 'processed_candidates', 'accession': 'GSE123',
        'title': '/private/secrets', 'files': [{'url': 'https://private', 'raw': [42]}],
        'sample_accessions': ['secret-sample'], 'source': {'sha256': 'a'*64}},
        'plan': {'version': 1, 'name': 'SECRET', 'datasets': [], 'samples': [], 'steps': [],
                 'path': '/private/file'},
        'inspection': {'status': 'downloaded', 'download_id': 'SECRET-ID',
            'source_name': 'SECRET.tsv', 'source_url': 'https://private', 'sha256': 'b'*64,
            'bytes': 1234, 'inspection': {'inspection': 'complete', 'feature_rows': 50,
            'column_labels': ['SECRET-SAMPLE'], 'integer_valued': True, 'finite': True,
            'nonnegative': True, 'raw_matrix': [[9, 8]], 'pdf': 'SECRET-PDF'}}}


class ContextTests(unittest.TestCase):
    def test_projection_and_provenance(self):
        result = context.prepare(snapshot())
        encoded = json.dumps(result)
        for secret in ('SECRET', '/private', 'https://private', 'raw_matrix', 'column_labels', 'pdf'):
            self.assertNotIn(secret, encoded)
        self.assertEqual(result['inspection']['feature_rows'], 50)
        self.assertEqual(result['inspection']['sample_count'], 1)
        self.assertEqual(result['inspection']['sha256'], 'b'*64)
        self.assertFalse(result['inspection']['count_provenance_verified'])
        self.assertFalse(result['inspection']['deseq2_ready'])
        self.assertEqual(result, context.prepare(snapshot()))
        self.assertFalse(result['plan']['valid'])
        self.assertIn('unknown_field', result['plan']['error_codes'])

    def test_unsupported_outer_context(self):
        for value in ('/tmp/matrix', {'file': '/tmp/matrix'}, {'manifest_id': 'abc'},
                      {'inspection': {'status': 'downloaded', 'inspection': {'inspection': 'failed'}}},
                      {'plan': {'number': float('nan')}}, {'manifest': None}):
            with self.subTest(value=value), self.assertRaises(context.ContextError):
                context.prepare(value)

    def test_empty_detached_and_bounded(self):
        self.assertEqual(context.prepare()['selected_sections'], [])
        original = snapshot()
        result = context.prepare(original)
        original['inspection']['inspection']['feature_rows'] = 999
        self.assertEqual(result['inspection']['feature_rows'], 50)
        with self.assertRaises(context.ContextError):
            context.prepare({'plan': {'name': 'a'*(context.MAX_INPUT_BYTES+1)}})

    def test_arbitrary_selection_rejected(self):
        for value in ('/tmp/file', 'GSE999'):
            with self.assertRaises(context.ContextError):
                context.prepare({'manifest': {'status': 'metadata_only', 'runs': [], 'selected_runs': [value]}})

    def test_invalid_plans_still_described(self):
        for plan in ({}, {'samples': 'no', 'datasets': None, 'steps': {}},
                     {'datasets': [{'id': []}], 'samples': [{'id': []}], 'steps': [{}]}):
            result = context.prepare({'plan': plan})['plan']
            self.assertFalse(result['valid'])
            self.assertFalse(result['executable'])

    def test_selected_runs_and_safe_parameters(self):
        manifest = {'status': 'metadata_only', 'request': 'PRJNA123',
                    'runs': [{'run_accession': 'SRR1', 'title': 'SECRET'},
                             {'run_accession': 'SRR2'}], 'selected_runs': ['SRR2'], 'selected_bytes': 17}
        result = context.prepare({'manifest': manifest, 'plan': {'steps': [
            {'operation': 'pca', 'parameters': {'components': 2, 'transform': 'log2p1', 'path': '/SECRET'}},
            {'operation': 'run_code', 'parameters': {'code': 'SECRET'}}]}})
        self.assertEqual(result['manifest']['selected_runs'], ['SRR2'])
        self.assertEqual(result['manifest']['selected_run_count'], 1)
        self.assertEqual(result['plan']['steps'], [{'operation': 'pca',
                         'parameters': {'components': 2, 'transform': 'log2p1'}}])
        self.assertNotIn('SECRET', json.dumps(result))

    def test_non_schema_strings_and_numbers_excluded(self):
        value = snapshot()
        value['inspection']['inspection']['finite'] = 'SECRET'
        value['inspection']['bytes'] = True
        result = context.prepare(value)
        self.assertIsNone(result['inspection']['finite'])
        self.assertIsNone(result['inspection']['bytes'])

if __name__ == '__main__':
    unittest.main()
