"""Run: python -m unittest discover -s webapp/tests -p test_workflow_plans.py"""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('workflow_plans', Path(__file__).parents[1] / 'scripts/workflow_plans.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def plan():
    return {'version': 1,
            'datasets': [{'id': 'rna', 'omics': 'bulk_rnaseq', 'data_type': 'raw_counts',
                          'provenance': {'source': 'GEO:GSE-example', 'sha256': 'a' * 64},
                          'sample_ids': ['A1', 'A2', 'B1', 'B2']}],
            'samples': [{'id': x, 'group': x[0]} for x in ['A1', 'A2', 'B1', 'B2']],
            'design': {'group': 'group', 'contrast': ['B', 'A']},
            'steps': [{'id': 'de', 'operation': 'deseq2', 'dataset_id': 'rna', 'parameters': {'alpha': 0.05}}]}


class WorkflowTests(unittest.TestCase):
    def codes(self, p):
        return {x['code'] for x in module.validate_plan(p)['errors']}

    def test_valid_but_not_executable(self):
        p = plan()
        result = module.validate_plan(p)
        self.assertTrue(result['valid'])
        self.assertFalse(result['executable'])
        self.assertTrue(result['execution_blockers'])
        self.assertIn('low_replicates', [x['code'] for x in result['warnings']])
        self.assertEqual(result['record']['plan'], p)
        self.assertEqual(result['record']['plan_sha256'], module.validate_plan(dict(reversed(list(p.items()))))['record']['plan_sha256'])
        json.dumps(result, allow_nan=False)

    def test_no_mutation(self):
        p = plan()
        before = copy.deepcopy(p)
        result = module.validate_plan(p)
        result['record']['plan']['samples'].clear()
        self.assertEqual(p, before)
        t = module.templates()
        t['operations']['pca']['inputs'].clear()
        self.assertTrue(module.templates()['operations']['pca']['inputs'])

    def test_normalized_never_deseq2(self):
        for dtype in ['tpm', 'fpkm', 'normalized', 'unknown', None, {}, []]:
            p = plan()
            p['datasets'][0]['data_type'] = dtype
            self.assertIn('input_type', self.codes(p))

    def test_normalized_exploration(self):
        p = plan()
        p['datasets'][0]['data_type'] = 'tpm'
        p['steps'] = [{'id': 'pca', 'operation': 'pca', 'dataset_id': 'rna'}]
        r = module.validate_plan(p)
        self.assertTrue(r['valid'])
        self.assertEqual(r['recommended_template_ids'], ['bulk_exploratory'])
        self.assertIn('exploratory_only', {x['code'] for x in r['warnings']})

    def test_duplicate_and_mismatched_samples(self):
        p = plan()
        p['samples'].append(p['samples'][0])
        p['datasets'][0]['sample_ids'] += ['missing', 'A1']
        self.assertTrue({'duplicate_sample', 'duplicate_matrix_sample', 'sample_mismatch'} <= self.codes(p))

    def test_provenance_required(self):
        for value in [None, {}, {'source': 'x', 'sha256': 'fake'}]:
            p = plan()
            p['datasets'][0]['provenance'] = value
            self.assertIn('provenance', self.codes(p))

    def test_replicates_contrast(self):
        p = plan()
        p['datasets'][0]['sample_ids'] = ['A1', 'A2', 'B1']
        self.assertIn('replicates', self.codes(p))
        for contrast in [['A', 'A'], ['B', 'C'], [], {}, ['B', {}]]:
            p['design']['contrast'] = contrast
            self.assertIn('contrast', self.codes(p))

    def test_batch_confounding(self):
        p = plan()
        p['design']['batch'] = 'batch'
        for row in p['samples']:
            row['batch'] = row['group']
        self.assertIn('confounded_design', self.codes(p))
        for row in p['samples']:
            row['batch'] = row['id'][1]
        self.assertNotIn('confounded_design', self.codes(p))
        self.assertTrue(module.validate_plan(p)['valid'])
        p['samples'][0].pop('batch')
        self.assertIn('missing_batch', self.codes(p))

    def test_no_residual_df(self):
        p = plan()
        p['design']['batch'] = 'batch'
        for row in p['samples']:
            row['batch'] = row['id']
        self.assertIn('no_residual_df', self.codes(p))

    def test_unsupported_integration_and_omics(self):
        p = plan()
        p['integration'] = {'method': 'MOFA'}
        p['datasets'][0]['omics'] = 'proteomics'
        self.assertTrue({'integration_unsupported', 'unsupported_omics'} <= self.codes(p))

    def test_multiple_independent_datasets(self):
        p = plan()
        ds = copy.deepcopy(p['datasets'][0])
        ds['id'] = 'replication'
        p['datasets'].append(ds)
        self.assertTrue(module.validate_plan(p)['valid'])
        self.assertIn('independent_datasets', {x['code'] for x in module.validate_plan(p)['warnings']})

    def test_invalid_parameters_and_code(self):
        for value in [True, 0, 1, -1, '0.05', {}, []]:
            p = plan()
            p['steps'][0]['parameters']['alpha'] = value
            self.assertIn('parameter_value', self.codes(p))
        p = plan()
        p['design']['formula'] = '__import__("os").system("false")'
        p['steps'][0]['operation'] = 'shell'
        self.assertTrue({'unsupported_design', 'unsupported_operation'} <= self.codes(p))

    def test_malformed_values_never_raise(self):
        for p in [None, [], 'x', 1, {}, {'version': True}, {'steps': [1]}, {'x': float('nan')}]:
            self.assertFalse(module.validate_plan(p)['valid'])
        for field in ['datasets', 'samples', 'steps', 'design']:
            for value in [None, 1, 'x', [], [{}], [None]]:
                p = plan()
                p[field] = value
                module.validate_plan(p)
        for field in ['id', 'operation', 'dataset_id', 'parameters']:
            for value in [None, [], {}, 1]:
                p = plan()
                p['steps'][0][field] = value
                module.validate_plan(p)

    def test_pca_size_and_unknown_fields(self):
        p = plan()
        p['steps'] = [{'id': 'p', 'operation': 'pca', 'dataset_id': 'rna', 'parameters': {'components': 4}}]
        self.assertIn('pca_sample_size', self.codes(p))
        p['code'] = 'do not execute'
        self.assertIn('unknown_field', self.codes(p))


if __name__ == '__main__':
    unittest.main()
