"""Pure JSON workflow preflight. This module never executes analysis or reads data."""
from collections import Counter
from copy import deepcopy
import hashlib
import json
import re

SCHEMA_VERSION = 1
TYPES = {'raw_counts', 'tpm', 'fpkm', 'normalized', 'unknown'}
OPERATIONS = {
    'qc': {'inputs': sorted(TYPES - {'unknown'}), 'output': 'qc_report', 'parameters': {}},
    'deseq2': {'inputs': ['raw_counts'], 'output': 'differential_expression',
                'parameters': {'alpha': 0.05, 'min_count': 10}},
    'pca': {'inputs': sorted(TYPES - {'unknown'}), 'output': 'pca_coordinates',
            'parameters': {'components': 2, 'transform': 'log2p1'}},
    'heatmap': {'inputs': sorted(TYPES - {'unknown'}), 'output': 'heatmap',
                'parameters': {'top_n': 50, 'transform': 'log2p1'}},
}


def templates() -> dict:
    """Return independent editable templates; these are not executable jobs."""
    return deepcopy({
        'schema_version': SCHEMA_VERSION, 'execution_supported': False,
        'operations': OPERATIONS,
        'templates': [
            {'id': 'bulk_counts', 'label': 'Bulk RNA-seq counts', 'omics': 'bulk_rnaseq',
             'input_type': 'raw_counts', 'steps': ['qc', 'pca', 'deseq2', 'heatmap'],
             'requires': ['count provenance', 'sample metadata', 'replicated group contrast'],
             'supported': True},
            {'id': 'bulk_exploratory', 'label': 'Normalized RNA-seq exploration only',
             'omics': 'bulk_rnaseq', 'input_type': ['tpm', 'fpkm', 'normalized'],
             'steps': ['qc', 'pca', 'heatmap'], 'supported': True},
            *[{'id': name, 'label': label, 'omics': name, 'supported': False,
               'steps': [], 'reason': 'Schema placeholder; analysis adapter not implemented.'}
              for name, label in [('single_cell', 'Single-cell RNA-seq'),
                                  ('proteomics', 'Proteomics'), ('metabolomics', 'Metabolomics'),
                                  ('epigenomics', 'Epigenomics'), ('microbiome', 'Microbiome'),
                                  ('multiomics', 'Multiomics integration')]],
        ]})


def validate_plan(plan: dict) -> dict:
    """Validate declared metadata, not matrix contents. Always executable=False.

    No formula evaluation, external programs, file reads, or network access occurs.
    Identifiers are data only. Errors/warnings use stable codes and JSON paths.
    """
    result = {'valid': False, 'executable': False, 'errors': [], 'warnings': [],
              'execution_blockers': ['Analysis execution is not implemented in this validator; '
                                     'R/Bioconductor runtime and adapters are not verified.'],
              'recommended_template_ids': [], 'record': None}

    def error(code, path, message):
        result['errors'].append({'code': code, 'path': path, 'message': message})

    def warn(code, path, message):
        result['warnings'].append({'code': code, 'path': path, 'message': message})

    try:
        canonical = json.dumps(plan, sort_keys=True, separators=(',', ':'), allow_nan=False)
        snapshot = json.loads(canonical)
    except (TypeError, ValueError, RecursionError):
        error('invalid_json', '$', 'Plan must contain finite JSON values only.')
        return result
    if not isinstance(snapshot, dict):
        error('invalid_plan', '$', 'Plan must be a JSON object.')
        return result
    plan = snapshot
    result['record'] = {'schema_version': SCHEMA_VERSION,
                        'plan_sha256': hashlib.sha256(canonical.encode()).hexdigest(), 'plan': plan}
    if type(plan.get('version')) is not int or plan['version'] != SCHEMA_VERSION:
        error('schema_version', 'version', 'version must be 1.')
    allowed = {'version', 'datasets', 'samples', 'design', 'steps', 'integration', 'name'}
    for key in plan.keys() - allowed:
        error('unknown_field', key, 'Unknown plan field; arbitrary code/formulas are not supported.')

    def items(key):
        value = plan.get(key)
        if not isinstance(value, list) or not value:
            error('required_list', key, 'Provide a nonempty list.')
            return []
        if not all(isinstance(x, dict) for x in value):
            error('invalid_items', key, 'Every entry must be an object.')
        return [x for x in value if isinstance(x, dict)]

    def identifier(value):
        return isinstance(value, str) and bool(value.strip())

    datasets, samples, steps = items('datasets'), items('samples'), items('steps')
    sample_map = {}
    for i, sample in enumerate(samples):
        sid = sample.get('id')
        if not identifier(sid):
            error('sample_id', f'samples[{i}].id', 'A nonempty sample ID is required.')
        elif sid in sample_map:
            error('duplicate_sample', f'samples[{i}].id', 'Sample IDs must be distinct.')
        else:
            sample_map[sid] = sample
        if not identifier(sample.get('group')):
            error('sample_group', f'samples[{i}].group', 'A nonempty group is required.')

    dataset_map = {}
    used_samples = set()
    for i, dataset in enumerate(datasets):
        path = f'datasets[{i}]'
        did = dataset.get('id')
        if not identifier(did):
            error('dataset_id', path + '.id', 'A nonempty dataset ID is required.')
        elif did in dataset_map:
            error('duplicate_dataset', path + '.id', 'Dataset IDs must be distinct.')
        else:
            dataset_map[did] = dataset
        if dataset.get('omics') != 'bulk_rnaseq':
            error('unsupported_omics', path + '.omics', 'Only bulk_rnaseq plan validation is supported.')
        dtype = dataset.get('data_type')
        if not isinstance(dtype, str) or dtype not in TYPES or dtype == 'unknown':
            error('unknown_data_type', path + '.data_type', 'Declare verified raw_counts, tpm, fpkm or normalized input.')
        else:
            recommendation = 'bulk_counts' if dtype == 'raw_counts' else 'bulk_exploratory'
            if recommendation not in result['recommended_template_ids']:
                result['recommended_template_ids'].append(recommendation)
            if dtype != 'raw_counts':
                warn('exploratory_only', path, 'Normalized abundance supports exploration only, not DESeq2.')
        provenance = dataset.get('provenance')
        if not isinstance(provenance, dict) or not identifier(provenance.get('source')) or not (
                isinstance(provenance.get('sha256'), str) and re.fullmatch(r'[0-9a-fA-F]{64}', provenance['sha256'])):
            error('provenance', path + '.provenance', 'Provide source and the actual input file SHA-256 (64 hex characters).')
        ids = dataset.get('sample_ids')
        if not isinstance(ids, list) or not ids or not all(identifier(x) for x in ids):
            error('dataset_samples', path + '.sample_ids', 'Provide nonempty string sample IDs in matrix column order.')
            continue
        if len(set(ids)) != len(ids):
            error('duplicate_matrix_sample', path + '.sample_ids', 'Matrix sample IDs must be distinct.')
        missing = set(ids) - sample_map.keys()
        if missing:
            error('sample_mismatch', path + '.sample_ids', 'Matrix samples missing metadata: ' + ', '.join(sorted(missing)))
        used_samples.update(ids)
    if sample_map.keys() - used_samples:
        warn('unused_metadata', 'samples', 'Some metadata samples are absent from all datasets.')
    if len(datasets) > 1:
        warn('independent_datasets', 'datasets', 'Datasets are assessed separately; no pooling or cross-study inference is implemented.')
    if plan.get('integration') is not None:
        error('integration_unsupported', 'integration', 'Multiomics integration is schema-only and cannot be validated for execution.')

    design = plan.get('design', {})
    if not isinstance(design, dict):
        error('design', 'design', 'Design must be an object, not an executable formula.')
        design = {}
    if set(design) - {'group', 'batch', 'contrast'}:
        error('unsupported_design', 'design', 'Only categorical group and optional categorical batch are supported; no formulas, pairing or covariates.')
    if design.get('group', 'group') != 'group' or design.get('batch') not in (None, 'batch'):
        error('unsupported_design', 'design', 'Supported design fields are group and optional batch.')
    seen_steps = set()
    for i, step in enumerate(steps):
        path = f'steps[{i}]'
        sid, op, did = step.get('id'), step.get('operation'), step.get('dataset_id')
        if not identifier(sid) or sid in seen_steps:
            error('step_id', path + '.id', 'Step IDs must be nonempty and unique.')
        else:
            seen_steps.add(sid)
        if set(step) - {'id', 'operation', 'dataset_id', 'parameters'}:
            error('unsupported_step_field', path, 'Only registry operations on an explicit dataset are supported.')
        if not isinstance(op, str) or op not in OPERATIONS:
            error('unsupported_operation', path + '.operation', 'Select an operation from the typed registry.')
            continue
        dataset = dataset_map.get(did) if isinstance(did, str) else None
        if dataset is None:
            error('step_dataset', path + '.dataset_id', 'Step must reference an existing dataset.')
            continue
        dtype = dataset.get('data_type')
        if dtype not in OPERATIONS[op]['inputs']:
            error('input_type', path, f'{op} does not accept the declared input type.')
        params = step.get('parameters', {})
        if not isinstance(params, dict):
            error('parameters', path, 'Parameters must be an object.')
            params = {}
        for key, value in params.items():
            valid = key in OPERATIONS[op]['parameters']
            if key == 'alpha':
                valid = type(value) in (int, float) and 0 < value < 1
            elif key in ('min_count', 'components', 'top_n'):
                valid = type(value) is int and 1 <= value <= 100000
            elif key == 'transform':
                valid = value in ('log2p1', 'none')
            if not valid or key not in OPERATIONS[op]['parameters']:
                error('parameter_value', path + '.parameters.' + key, 'Unknown or invalid parameter.')
        ids = dataset.get('sample_ids', [])
        ids = ids if isinstance(ids, list) else []
        rows = [sample_map[x] for x in ids if isinstance(x, str) and x in sample_map]
        if op in ('pca', 'heatmap') and dtype == 'raw_counts':
            warn('exploratory_transform', path, 'Raw-count exploration requires library-size normalization and an appropriate transform; this validator does not perform either.')
        if op == 'pca' and type(params.get('components', 2)) is int and params.get('components', 2) >= len(rows):
            error('pca_sample_size', path, 'PCA components must be fewer than matched samples.')
        if op == 'deseq2':
            groups = Counter(row['group'] for row in rows if identifier(row.get('group')))
            contrast = design.get('contrast')
            if not isinstance(contrast, list) or len(contrast) != 2 or not all(identifier(x) for x in contrast) or len(set(contrast)) != 2 or any(x not in groups for x in contrast):
                error('contrast', 'design.contrast', 'Provide two distinct existing group labels: [test, reference].')
            if len(groups) < 2 or any(n < 2 for n in groups.values()):
                error('replicates', path, 'DESeq2 requires at least two biological replicates per group in this validator.')
            elif any(n < 3 for n in groups.values()):
                warn('low_replicates', path, 'Two replicates per group provide limited power; prefer at least three.')
            if design.get('batch') == 'batch':
                if any(not identifier(row.get('batch')) for row in rows):
                    error('missing_batch', path, 'Every matched sample needs a batch value.')
                elif rows:
                    # A connected group-batch bipartite graph gives full rank for additive categorical design.
                    edges = [(('g', row['group']), ('b', row['batch'])) for row in rows if identifier(row.get('group'))]
                    nodes = {node for edge in edges for node in edge}
                    reached = {next(iter(nodes))} if nodes else set()
                    while True:
                        expanded = reached | {node for edge in edges if reached.intersection(edge) for node in edge}
                        if expanded == reached:
                            break
                        reached = expanded
                    if reached != nodes:
                        error('confounded_design', path, 'Group and batch design is rank deficient (disconnected group-batch combinations).')
                    rank = len({a for a, _ in edges}) + len({b for _, b in edges}) - 1
                    if len(rows) <= rank:
                        error('no_residual_df', path, 'Design has no residual degrees of freedom.')
            elif any(identifier(row.get('batch')) for row in rows):
                warn('batch_ignored', path, 'Batch metadata exists but batch is not included in the design.')
    warn('metadata_only', '$', 'File checksums, numeric matrix values, feature IDs, biological independence and transform suitability have not been verified. No files were read.')
    result['valid'] = not result['errors']
    return result
