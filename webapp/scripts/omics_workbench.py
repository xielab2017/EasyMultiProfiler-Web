"""Count-matrix ingestion and deterministic workflow preparation.

No model, R or shell execution. Only completed managed downloads or explicit
uploads are read. The R API independently validates the prepared payload.
"""
from __future__ import annotations

from collections import Counter
from copy import deepcopy
import csv
import gzip
import hashlib
import io
import json
import re
import threading
import uuid
from pathlib import Path

CONTRACT = 'emp-count-workbench-v1'
MAX_BYTES = 12 * 1024 * 1024
MAX_FEATURES = 50000
MAX_SAMPLES = 256
MAX_CELLS = 1000000
OPERATIONS = {
    'qc': {'label': '计数质量检查', 'parameters': {}},
    'normalize': {'label': 'DESeq2 size-factor 归一化', 'parameters': {}},
    'pca': {'label': 'PCA', 'parameters': {'components': 2}},
    'deseq2': {'label': 'DESeq2 差异分析', 'parameters': {'alpha': 0.05, 'min_count': 10, 'min_samples': 2}},
    'heatmap': {'label': '高变基因热图', 'parameters': {'top_n': 50}},
    'edger': {'label': 'edgeR 多组差异分析', 'parameters': {'alpha': 0.05, 'min_count': 10, 'min_samples': 2}},
}


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def fields(value, allowed):
    if not isinstance(value, dict) or set(value) - set(allowed):
        raise ValueError('Unsupported workbench fields')


def catalog():
    return {'contract': CONTRACT, 'operations': deepcopy(OPERATIONS),
            'templates': [{'id': 'bulk_counts', 'label': 'Bulk RNA-seq · raw counts',
                           'steps': list(OPERATIONS)}],
            'supported_omics': ['bulk_rnaseq'],
            'limits': {'file_bytes': MAX_BYTES, 'features': MAX_FEATURES, 'samples': MAX_SAMPLES, 'cells': MAX_CELLS},
            'other_omics': 'Use the existing omics pages; this execution adapter supports bulk RNA-seq raw counts only.'}


def steps_for(operations):
    return [{'id': 'step' + str(i + 1), 'operation': op, 'parameters': deepcopy(OPERATIONS[op]['parameters'])}
            for i, op in enumerate(operations)]


def propose(question):
    """Transparent local command parser, also usable as a model tool.

    Does not guess groups, matrix type, provenance or biological independence.
    """
    if not isinstance(question, str) or not 1 <= len(question.strip()) <= 4000:
        raise ValueError('Provide a question of 1–4000 characters')
    if re.search(r'TPM|FPKM|single.cell|单细胞|蛋白|代谢|16S|微生物|batch|批次|配对|paired|多组学', question, re.I):
        return {'mode': 'local_rules', 'status': 'needs_specialist_workflow', 'steps': [],
                'message': '此执行器仅支持独立样本的 bulk RNA-seq raw counts。所述数据或设计请使用对应组学页面，不能套用本流程。',
                'execution_performed': False}
    ops = ['qc']
    if re.search(r'完整|全流程|一键|full|pipeline|workflow|工作流|差异|differential|DESeq', question, re.I):
        ops = ['qc', 'normalize', 'pca', 'deseq2', 'heatmap']
    else:
        if re.search(r'PCA|主成分|热图|heatmap|归一|normaliz', question, re.I): ops.append('normalize')
        if re.search(r'PCA|主成分', question, re.I): ops.append('pca')
        if re.search(r'热图|heatmap', question, re.I): ops.append('heatmap')
    accession = re.search(r'\bGSE[0-9]{1,9}\b', question, re.I)
    if re.search(r'\bedgeR\b', question, re.I):
        if re.search(r'\bDESeq2?\b', question, re.I):
            ops.insert(ops.index('heatmap') if 'heatmap' in ops else len(ops), 'edger')
        else:
            ops = ['edger' if op == 'deseq2' else op for op in ops]
            if 'edger' not in ops: ops.append('edger')
    return {'mode': 'local_rules', 'status': 'draft', 'steps': steps_for(ops),
            'accession': accession.group().upper() if accession else None,
            'message': '已将指令转为可编辑流程。请选择真实矩阵、填写样本分组并审核后运行。',
            'execution_performed': False}


def inspect(raw, name):
    if not isinstance(raw, bytes) or not 0 < len(raw) <= MAX_BYTES:
        raise ValueError('Count matrix must be at most 12 MiB compressed and decompressed')
    if not re.search(r'\.(txt|tsv|csv)(\.gz)?$', name, re.I):
        raise ValueError('Only UTF-8 CSV/TSV/TXT and gzip are supported; archives/HDF5/MTX remain downloadable originals')
    source_sha = sha(raw)
    if raw.startswith(b'\x1f\x8b'):
        with gzip.GzipFile(fileobj=io.BytesIO(raw)) as zipped:
            raw = zipped.read(MAX_BYTES + 1)
        if len(raw) > MAX_BYTES: raise ValueError('Decompressed matrix exceeds 12 MiB')
    text = raw.decode('utf-8-sig')
    lines = (line for line in text.splitlines() if line.strip() and not line.startswith('#'))
    first = next(lines, '')
    delimiter = '\t' if '\t' in first else ','
    reader = csv.reader(io.StringIO(first + '\n' + '\n'.join(lines)), delimiter=delimiter, strict=True)
    header = next(reader, [])
    if not 2 <= len(header) <= MAX_SAMPLES + 33 or len(set(header)) != len(header):
        raise ValueError('Matrix needs distinct header labels and 1–256 selected samples')
    if any(not x or len(x) > 256 or any(ord(c) < 32 for c in x) for x in header[1:]):
        raise ValueError('Nonempty bounded column labels required')
    rows, seen = [], set()
    for row in reader:
        if len(row) != len(header): raise ValueError('Every matrix row must match the header; no values were filled')
        feature = row[0]
        if not feature or len(feature) > 256 or any(ord(c) < 32 for c in feature) or feature in seen:
            raise ValueError('Feature IDs must be nonempty, bounded and distinct')
        seen.add(feature); rows.append(row)
        if len(rows) > MAX_FEATURES or len(rows) * (len(header) - 1) > MAX_CELLS:
            raise ValueError('Matrix exceeds 50,000 features or one million cells')
    if len(rows) < 2: raise ValueError('At least two feature rows are required')
    return {'source_sha256': source_sha, 'header': header, 'rows': rows}


def select_counts(parsed, sample_columns):
    header, rows = parsed['header'], parsed['rows']
    if not isinstance(sample_columns, list) or not 2 <= len(sample_columns) <= MAX_SAMPLES or any(not isinstance(x, str) for x in sample_columns) or len(set(sample_columns)) != len(sample_columns) or not set(sample_columns) <= set(header[1:]):
        raise ValueError('Explicitly select 2–256 distinct count columns from this matrix')
    positions = [header.index(x) for x in sample_columns]
    values, totals = [], [0] * len(positions)
    for row in rows:
        numbers = []
        for j, pos in enumerate(positions):
            value = row[pos]
            # Deliberate text parsing, not numeric inference/rounding/imputation.
            if not re.fullmatch(r'[0-9]{1,10}(?:\.0+)?', value) or int(value.split('.')[0]) > 2147483647:
                raise ValueError('Selected counts must be exact nonnegative integers within R range; missing/negative/decimal values are rejected')
            number = int(value.split('.')[0]); totals[j] += number; numbers.append(number)
        values.append(numbers)
    if any(x == 0 for x in totals): raise ValueError('Every selected sample must have a positive library size')
    output = io.StringIO(newline='')
    writer = csv.writer(output, lineterminator='\n', quoting=csv.QUOTE_ALL)
    writer.writerow(['feature_id', *sample_columns])
    writer.writerows([[row[0], *numbers] for row, numbers in zip(rows, values)])
    return {'matrix_csv': output.getvalue(), 'library_sizes': totals,
            'sample_ids': list(sample_columns), 'feature_count': len(rows),
            'excluded_columns': [x for x in header[1:] if x not in sample_columns],
            'all_zero_features': sum(not any(row) for row in values)}


def contrast_pairs(design, groups):
    fields(design, {'test', 'reference', 'independent_samples', 'contrasts'})
    pairs = design.get('contrasts', [{'test': design.get('test'), 'reference': design.get('reference')}])
    if not isinstance(pairs, list) or not 1 <= len(pairs) <= 20:
        raise ValueError('Select 1–20 explicit comparisons')
    seen = set()
    for row in pairs:
        fields(row, {'test', 'reference'})
        test, reference = row.get('test'), row.get('reference')
        if not isinstance(test, str) or not isinstance(reference, str) or test == reference or test not in groups or reference not in groups:
            raise ValueError('Every contrast requires two distinct declared groups')
        if (test, reference) in seen: raise ValueError('Duplicate contrasts are unsupported')
        seen.add((test, reference))
    if (design.get('test'), design.get('reference')) != (pairs[0]['test'], pairs[0]['reference']):
        raise ValueError('Primary comparison must match the first displayed contrast')
    if 'contrasts' not in design and len(groups) != 2:
        raise ValueError('Explicit comparisons are required for more than two groups')
    return pairs


def validate_group_review(review, samples):
    fields(review, {'confirmed', 'method', 'field', 'metadata_sha256', 'paper', 'sample_rows'})
    if review.get('confirmed') is not True or review.get('method') not in {'manual', 'geo_characteristic'} or len(canonical(review).encode('utf-8')) > 48000:
        raise ValueError('Review the sample grouping evidence before analysis')
    rows = review.get('sample_rows')
    if not isinstance(rows, list) or len(rows) != len(samples): raise ValueError('Grouping review must cover every sample')
    for row in rows:
        fields(row, {'id', 'group', 'gsm', 'match', 'evidence'})
        if any(not isinstance(value, str) or len(value) > 1000 for value in row.values()): raise ValueError('Invalid grouping evidence')
    if len({row.get('id') for row in rows}) != len(rows) or {row.get('id'): row.get('group') for row in rows} != {row['id']: row['group'] for row in samples}:
        raise ValueError('Grouping evidence no longer matches the declared samples')
    paper = review.get('paper') or {}
    fields(paper, {'title', 'doi', 'pmid', 'filename', 'pdf_sha256', 'source_url', 'evidence'})
    if any(not isinstance(value, str) or len(value) > 2048 for key, value in paper.items() if key != 'evidence'):
        raise ValueError('Invalid paper evidence metadata')
    if not isinstance(paper.get('evidence', []), list) or len(paper.get('evidence', [])) > 12:
        raise ValueError('Paper evidence must be bounded')
    for row in paper.get('evidence', []):
        fields(row, {'page', 'text', 'kind'})
        if type(row.get('page')) is not int or not 1 <= row['page'] <= 100 or not isinstance(row.get('text'), str) or len(row['text']) > 700:
            raise ValueError('Invalid paper page evidence')


def validate(plan, dataset):
    errors, warnings = [], []
    try:
        fields(plan, {'version', 'dataset_id', 'omics', 'data_type', 'samples', 'design', 'steps', 'seed', 'raw_counts_evidence', 'grouping_review', 'deferred_steps'})
        if type(plan.get('version')) is not int or plan['version'] != 1: raise ValueError('version must be 1')
        if plan.get('dataset_id') != dataset['dataset_id']: raise ValueError('Choose the current verified dataset')
        if plan.get('omics') != 'bulk_rnaseq' or plan.get('data_type') != 'raw_counts': raise ValueError('Only bulk RNA-seq raw counts are executable')
        if type(plan.get('seed')) is not int or not 1 <= plan['seed'] <= 2147483647: raise ValueError('Provide an integer random seed')
        evidence = plan.get('raw_counts_evidence')
        if not isinstance(evidence, str) or not evidence.strip() or len(evidence) > 2048: raise ValueError('Record author documentation or reviewed evidence of unnormalized raw counts')
        samples = plan.get('samples')
        if not isinstance(samples, list) or len(samples) != len(dataset['sample_ids']): raise ValueError('Annotate every selected sample exactly once')
        ids = []
        for row in samples:
            fields(row, {'id', 'group'})
            if not all(isinstance(row.get(k), str) and 0 < len(row[k].strip()) <= 256 and not any(ord(c) < 32 for c in row[k]) for k in ('id', 'group')): raise ValueError('Every sample needs an ID and a group; batch/paired designs are unsupported')
            ids.append(row['id'])
        if len(set(ids)) != len(ids) or set(ids) != set(dataset['sample_ids']): raise ValueError('Sample IDs must match matrix columns exactly; no implicit exclusion')
        deferred = plan.get('deferred_steps', [])
        if not isinstance(deferred, list) or len(deferred) > 3 or len(set(deferred)) != len(deferred) or any(op not in {'volcano', 'enrichment', 'wgcna'} for op in deferred): raise ValueError('Invalid deferred workflow steps')
        if 'grouping_review' in plan: validate_group_review(plan['grouping_review'], samples)
        design = plan.get('design'); fields(design, {'test', 'reference', 'independent_samples', 'contrasts'})
        steps = plan.get('steps')
        if not isinstance(steps, list) or not 1 <= len(steps) <= 6: raise ValueError('Select 1–6 registered steps')
        seen, step_ids = set(), set()
        for step in steps:
            fields(step, {'id', 'operation', 'parameters'})
            op, sid = step.get('operation'), step.get('id')
            if not isinstance(op, str) or op not in OPERATIONS or op in seen: raise ValueError('Each registered operation may appear once')
            if not isinstance(sid, str) or not re.fullmatch(r'[a-zA-Z0-9_-]{1,64}', sid) or sid in step_ids: raise ValueError('Step IDs must be unique')
            step_ids.add(sid)
            params = step.get('parameters'); fields(params, OPERATIONS[op]['parameters'])
            if set(params) != set(OPERATIONS[op]['parameters']): raise ValueError('Provide all displayed step parameters')
            for key, value in params.items():
                if key == 'alpha':
                    if type(value) not in (float, int) or not 0 < value < 1: raise ValueError('alpha must be between 0 and 1')
                else:
                    maximum = {'components': min(len(ids)-1, 10), 'top_n': min(dataset['feature_count'], 500), 'min_count': 1000000, 'min_samples': len(ids)}[key]
                    if type(value) is not int or not 1 <= value <= maximum: raise ValueError('Invalid parameter ' + key)
            if op in {'pca', 'heatmap'} and 'normalize' not in seen: raise ValueError('Place size-factor normalization before PCA/heatmap')
            if op == 'qc' and seen: raise ValueError('QC must be the first step')
            seen.add(op)
        if 'qc' not in seen: raise ValueError('Include QC as the first step')
        if {'deseq2', 'edger'} & seen:
            groups = Counter(s['group'] for s in samples)
            if design.get('independent_samples') is not True: raise ValueError('Confirm biological independence; paired/repeated samples are unsupported')
            if not 2 <= len(groups) <= 12 or min(groups.values()) < 2: raise ValueError('Differential analysis requires 2–12 groups with >=2 independent replicates in every group')
            pairs = contrast_pairs(design, groups)
            if len(pairs) > 1: warnings.append('All groups are fitted together. BH FDR is controlled within each comparison, not across the whole contrast family.')
            if min(groups.values()) < 3: warnings.append('Two replicates per group offer limited power; prefer at least three.')
        if dataset['all_zero_features']: warnings.append('All-zero features are retained in QC and explicitly reported if filtered for DESeq2.')
        warnings.append('Integer values do not establish raw-count provenance. No batch, pairing, covariates or automatic outlier removal.')
    except (ValueError, TypeError, KeyError) as exc:
        errors.append(str(exc))
    return {'valid': not errors, 'errors': errors, 'warnings': warnings, 'execution_performed': False}


class Workbench:
    """One local-owner registry. Immutable input/prepared records, no auto-deletion."""
    def __init__(self, root):
        self.root = Path(root).resolve()
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.lock = threading.RLock()
        self.records, self.datasets, self.prepared = {}, {}, {}

    def ingest(self, raw, name, source):
        parsed = inspect(raw, name)
        with self.lock:
            if len(self.records) >= 8: raise ValueError('Eight input records retained; start a new owner session after reviewing saved files')
            key = str(uuid.uuid4())
            (self.root / (key + '.original')).write_bytes(raw)
            (self.root / (key + '.original')).chmod(0o600)
            self.records[key] = {**parsed, 'source': source, 'source_name': name}
        return {'input_id': key, 'source_name': name, 'source_sha256': parsed['source_sha256'],
                'feature_count': len(parsed['rows']), 'columns': parsed['header'][1:],
                'suggested_annotation_columns': [x for x in parsed['header'][1:] if x.lower() in {'length', 'gene_length', 'symbol', 'gene_name', 'description', 'entrezid', 'entrez_id', 'ensembl', 'ensembl_id', 'gene_id'}],
                'data_type': 'unknown', 'raw_count_provenance_verified': False}

    def select(self, input_id, columns):
        with self.lock:
            record = self.records.get(input_id)
            if record is None: raise ValueError('Input unavailable; ingest again after service restart')
            if len(self.datasets) >= 16: raise ValueError('Dataset limit reached; review retained records')
            data = select_counts(record, columns)
            key = str(uuid.uuid4())
            data.update(dataset_id=key, source=record['source'], source_sha256=record['source_sha256'],
                        matrix_sha256=sha(data['matrix_csv'].encode()))
            self.datasets[key] = data
            return {k: deepcopy(v) for k, v in data.items() if k != 'matrix_csv'}

    def prepare(self, plan):
        with self.lock:
            fields(plan, {'version', 'dataset_id', 'omics', 'data_type', 'samples', 'design', 'steps', 'seed', 'raw_counts_evidence', 'grouping_review', 'deferred_steps'})
            dataset = self.datasets.get(plan.get('dataset_id'))
            if dataset is None: raise ValueError('Select count columns first')
            result = validate(plan, dataset)
            if not result['valid']: return result
            if len(self.prepared) >= 16: raise ValueError('Prepared-plan limit reached; review retained records')
            payload_plan = json.loads(canonical(plan))
            payload_plan.update(contract=CONTRACT, input_sha256=dataset['matrix_sha256'],
                                source_sha256=dataset['source_sha256'], source=dataset['source'],
                                excluded_columns=dataset['excluded_columns'], raw_count_provenance_verified=False)
            plan_json = canonical(payload_plan)
            key = str(uuid.uuid4())
            payload = {'plan_json': plan_json, 'plan_sha256': sha(plan_json.encode()), 'matrix_csv': dataset['matrix_csv']}
            self.prepared[key] = payload
            (self.root / (key + '.plan.json')).write_text(canonical(payload), encoding='utf-8')
            (self.root / (key + '.plan.json')).chmod(0o600)
            return {**result, 'prepared_id': key, 'plan_sha256': payload['plan_sha256'], 'plan': payload_plan,
                    'confirmation_required': True, 'dataset': {k: v for k, v in dataset.items() if k != 'matrix_csv'}}

    def payload(self, key):
        with self.lock:
            if key not in self.prepared: raise ValueError('Prepared plan unavailable; prepare it again')
            return deepcopy(self.prepared[key])
