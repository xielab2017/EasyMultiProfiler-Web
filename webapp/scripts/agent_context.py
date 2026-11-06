"""Pure allowlist projection of explicitly selected, server-owned research context.

No filesystem or network access. Never resolve IDs; the host supplies the selection.
"""
import hashlib
import json
import re
import workflow_plans

MAX_INPUT_BYTES = 2 * 1024 * 1024
MAX_CONTEXT_BYTES = 10000
SECTIONS = {'manifest', 'plan', 'inspection'}


class ContextError(ValueError):
    pass


def _count(value):
    return value if type(value) is int and 0 <= value <= 10**15 else None


def _hash(value):
    return value.lower() if isinstance(value, str) and re.fullmatch('[a-fA-F0-9]{64}', value) else None


def _accession(value):
    return value if isinstance(value, str) and re.fullmatch(r'(?:GSE|GSM|SRR|ERR|DRR|SRP|ERP|DRP|PRJNA|PRJEB|PRJDB)[0-9]{1,12}', value) else None


def _list(value):
    if not isinstance(value, list) or len(value) > 10000:
        raise ContextError('Invalid context list')
    return value


def _manifest(value):
    if value.get('status') == 'processed_candidates':
        files = _list(value.get('files', []))
        return {'kind': 'processed_candidates', 'accession': _accession(value.get('accession')),
                'candidate_file_count': len(files), 'sample_count': len(_list(value.get('sample_accessions', []))),
                'source_sha256': _hash(value.get('source', {}).get('sha256')),
                'contents_verified': False}
    if value.get('status') != 'metadata_only':
        raise ContextError('Unsupported manifest')
    runs = _list(value.get('runs', []))
    selected = _list(value.get('selected_runs', []))
    if any(not isinstance(r, dict) for r in runs) or any(not _accession(s) for s in selected):
        raise ContextError('Invalid run selection')
    by_id = {r.get('run_accession'): r for r in runs}
    if any(s not in by_id for s in selected) or len(set(selected)) != len(selected):
        raise ContextError('Unknown run selection')
    chosen = [by_id[s] for s in selected]
    return {'kind': 'sequencing_metadata', 'accession': _accession(value.get('request')),
            'available_run_count': len(runs), 'selected_run_count': len(chosen),
            'selected_runs': selected[:100], 'selection_truncated': len(selected) > 100,
            'selected_bytes': _count(value.get('selected_bytes')), 'contents_verified': False}


def _plan(value):
    try:
        validation = workflow_plans.validate_plan(value)
    except (ValueError, TypeError, KeyError, AttributeError):
        validation = {'valid': False, 'errors': [{'code': 'invalid_plan'}], 'warnings': []}
    def codes(kind):
        # Only internal stable codes, never messages or paths that can contain input.
        return sorted({x['code'] for x in validation[kind] if re.fullmatch('[a-z_]{1,64}', x['code'])})
    datasets = value.get('datasets') if isinstance(value.get('datasets'), list) else []
    samples = value.get('samples') if isinstance(value.get('samples'), list) else []
    steps = value.get('steps') if isinstance(value.get('steps'), list) else []
    step_metadata = []
    for step in steps[:100]:
        if not isinstance(step, dict) or not isinstance(step.get('operation'), str) or step['operation'] not in workflow_plans.OPERATIONS:
            continue
        op = step['operation']
        parameters = {}
        declared = step.get('parameters', {})
        if isinstance(declared, dict):
            for key in workflow_plans.OPERATIONS[op]['parameters']:
                item = declared.get(key)
                if key == 'alpha' and type(item) in (int, float) and 0 < item < 1:
                    parameters[key] = item
                elif key in ('min_count', 'components', 'top_n') and type(item) is int and 1 <= item <= 100000:
                    parameters[key] = item
                elif key == 'transform' and isinstance(item, str) and item in ('log2p1', 'none'):
                    parameters[key] = item
        step_metadata.append({'operation': op, 'parameters': parameters})
    return {'kind': 'declared_workflow', 'steps': step_metadata, 'dataset_count': len(datasets), 'sample_count': len(samples),
            'step_count': len(steps), 'operations': [s['operation'] for s in steps[:100]
                if isinstance(s, dict) and isinstance(s.get('operation'), str) and s['operation'] in workflow_plans.OPERATIONS],
            'input_types': sorted({d['data_type'] for d in datasets if isinstance(d, dict)
                and isinstance(d.get('data_type'), str) and d['data_type'] in workflow_plans.TYPES}),
            'valid': validation['valid'], 'error_codes': codes('errors'), 'warning_codes': codes('warnings'),
            'executable': False, 'matrix_contents_verified': False}


def _inspection(value):
    inspected = value.get('inspection')
    if value.get('status') != 'downloaded' or not isinstance(inspected, dict) or inspected.get('inspection') != 'complete':
        raise ContextError('Only completed local inspections can be selected')
    result = {'kind': 'completed_local_matrix_inspection', 'inspection': 'complete',
              'sha256': _hash(value.get('sha256')), 'bytes': _count(value.get('bytes')),
              'feature_rows': _count(inspected.get('feature_rows')),
              'sample_count': len(_list(inspected.get('column_labels', []))),
              'analysis_executed': False, 'deseq2_ready': False,
              'count_provenance_verified': False}
    for field in ('finite', 'nonnegative', 'integer_valued', 'duplicate_feature_ids'):
        result[field] = inspected.get(field) if type(inspected.get(field)) is bool else None
    return result


def prepare(snapshot=None):
    """Return a detached safe projection. Unknown outer sections fail closed.

    Nested original records are projected, not echoed: unknown nested fields,
    all free text/labels, URLs, IDs, raw arrays and paths are excluded.
    """
    if snapshot is None:
        snapshot = {}
    try:
        if not isinstance(snapshot, dict) or set(snapshot) - SECTIONS:
            raise ContextError('Unsupported context fields')
        raw = json.dumps(snapshot, allow_nan=False)
        if len(raw.encode()) > MAX_INPUT_BYTES:
            raise ContextError('Context too large')
        snapshot = json.loads(raw)
        output = {'schema_version': 1, 'selected_sections': sorted(snapshot),
                  'execution_supported': False}
        for section, projector in [('manifest', _manifest), ('plan', _plan), ('inspection', _inspection)]:
            if section in snapshot:
                if not isinstance(snapshot[section], dict):
                    raise ContextError('Context section must be an object')
                output[section] = projector(snapshot[section])
        canonical = json.dumps(output, sort_keys=True, allow_nan=False)
        if len(canonical.encode()) > MAX_CONTEXT_BYTES:
            raise ContextError('Context projection too large')
        output['snapshot_sha256'] = hashlib.sha256(canonical.encode()).hexdigest()
        return output
    except (ValueError, TypeError, KeyError, AttributeError, RecursionError):
        raise ContextError('Invalid selected context') from None
