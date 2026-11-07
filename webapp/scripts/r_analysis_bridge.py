"""Fail-closed bridge to the existing, local EMP R API. No R/shell execution.

Only server-owned registry entries may supply data. Public methods accept IDs
and a small fixed DESeq2 plan, never paths, URLs, code, credentials or formulas.
The hosting server owns authentication, user confirmation and runtime attestation.
"""
from __future__ import annotations

from collections import Counter
from copy import deepcopy
import csv
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import secrets
import shutil
import threading
import time
import urllib.error
import urllib.request

BRIDGE_VERSION = '1.0.0'
API_ORIGIN = 'http://127.0.0.1:8000'
SOURCE_CONTRACT = 'emp-direct-deseq2-v1'
MAX_CELLS = 1_000_000
MAX_FEATURES = 50_000
MAX_SAMPLES = 256
MAX_RESPONSE_BYTES = 32 * 1024 * 1024
MAX_MATRIX_RECORDS = 8
MAX_METADATA_RECORDS = 32
MAX_PLANS = 16
MAX_REGISTRY_CELLS = 2_000_000
MAX_REGISTRY_FEATURES = 100_000
MAX_PLAN_STAGING_BYTES = 16 * 1024 * 1024
MAX_TOTAL_STAGING_BYTES = 128 * 1024 * 1024
MAX_STAGING_ENTRIES = 1024
MIN_DISK_FREE_BYTES = 512 * 1024 * 1024
ID = re.compile(r'[A-Za-z0-9][A-Za-z0-9_-]{0,127}\Z')
SHA = re.compile(r'[a-f0-9]{64}\Z')
JOB = r'[0-9]{14}\.[0-9]{3}-[a-z0-9]{8}'
SESSION = r'[A-Za-z0-9]{24}'
VERSION = re.compile(r'[0-9]+(?:\.[0-9]+){1,3}(?:[.-][A-Za-z0-9]+)*\Z')
TERMINAL = {'completed', 'error', 'cancelled', 'preflight_failed', 'submission_uncertain', 'result_unverified'}


class BridgeError(ValueError):
    def __init__(self, code, message, *, uncertain=False):
        super().__init__(message)
        self.code, self.message, self.uncertain = code, message, uncertain

    def as_dict(self):
        return {'code': self.code, 'message': self.message, 'outcome_uncertain': self.uncertain}


def _fail(code, message, **kwargs):
    raise BridgeError(code, message, **kwargs) from None


def _object(value, allowed):
    if type(value) is not dict or value.keys() - allowed:
        _fail('invalid_request', 'Only the documented object fields are accepted.')


def _id(value):
    if type(value) is not str or not ID.fullmatch(value):
        _fail('invalid_id', 'A server-managed record ID is required.')
    return value


def _label(value):
    if type(value) is not str or not value or len(value) > 128 or value.strip() != value or any(ord(c) < 32 or ord(c) == 127 for c in value):
        _fail('invalid_label', 'Labels must be nonblank, at most 128 characters and free of control characters.')
    return value


def _labels(values, maximum):
    if type(values) is not list or not 1 <= len(values) <= maximum:
        _fail('input_limit', 'The number of identifiers is outside the supported limits.')
    for value in values:
        _label(value)
    if len(set(values)) != len(values):
        _fail('duplicate_id', 'Sample and feature IDs must be unique.')
    return values


def _digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False).encode()).hexdigest()


def _sha_bytes(value):
    return hashlib.sha256(value).hexdigest()


def _finite_number(value):
    if type(value) not in (int, float):
        return False
    try:
        return math.isfinite(value)
    except OverflowError:
        return False


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class LocalRClient:
    """Server-only token; fixed origin, endpoint allowlist, no proxy or redirect.

    No request/response/header/error text is logged. Never pass a browser token
    or a caller-controlled URL. Empty token is valid only for existing local R
    deployments that do not require bearer authentication.
    """
    def __init__(self, token='', *, timeout=30):
        if type(token) is not str or len(token) > 4096 or any(ord(c) < 32 or ord(c) > 126 for c in token):
            _fail('auth_configuration', 'Invalid server-side R authentication configuration.')
        if type(timeout) not in (int, float) or not 0 < timeout <= 120:
            _fail('transport_configuration', 'Timeout must be between zero and 120 seconds.')
        self.__token = token
        self.timeout = timeout
        self._opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), _NoRedirect())

    def __repr__(self):
        return 'LocalRClient(origin=loopback, credentials=redacted)'

    @staticmethod
    def _allowed(method, path):
        exact = {'GET': {'/api/health', '/api/capabilities'},
                 'POST': {'/api/import/path/preview', '/api/import/path', '/api/analyze/differential/async'}}
        if path in exact.get(method, set()):
            return True
        if method == 'GET':
            return bool(re.fullmatch(r'/api/jobs/' + JOB + r'(?:/result)?', path) or
                        re.fullmatch(r'/api/analyze/diff_raw/' + SESSION + r'/emp_bridge_[a-f0-9]{32}', path))
        return method == 'POST' and bool(re.fullmatch(r'/api/jobs/' + JOB + '/cancel', path))

    def request(self, method, path, payload=None):
        if not self._allowed(method, path):
            _fail('endpoint_blocked', 'The R endpoint is outside the reviewed bridge contract.')
        headers = {'Accept': 'application/json', 'Content-Type': 'application/json'}
        if self.__token:
            headers['Authorization'] = 'Bearer ' + self.__token
        body = None if payload is None else json.dumps(payload, allow_nan=False).encode()
        request = urllib.request.Request(API_ORIGIN + path, data=body, headers=headers, method=method)
        try:
            with self._opener.open(request, timeout=self.timeout) as response:
                if response.status != 200:
                    _fail('r_http_error', 'The local R API returned an unexpected HTTP status.', uncertain=method == 'POST')
                data = response.read(MAX_RESPONSE_BYTES + 1)
                if len(data) > MAX_RESPONSE_BYTES:
                    _fail('r_response_limit', 'The local R API response exceeded the size limit.', uncertain=method == 'POST')
                value = json.loads(data.decode('utf-8'), parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
        except BridgeError:
            raise
        except urllib.error.HTTPError as error:
            # Never expose URLs, server error text, credentials or file paths.
            _fail('r_http_error', 'The local R API rejected the request.',
                  uncertain=method == 'POST' and error.code not in (401, 403, 404, 405))
        except (OSError, ValueError, UnicodeError, RecursionError, urllib.error.URLError):
            _fail('r_unavailable', 'The local R API is unavailable or returned an invalid response.', uncertain=method == 'POST')
        if type(value) is not dict:
            _fail('r_contract', 'The local R API response does not match its contract.', uncertain=method == 'POST')
        if value.get('success') is False:
            _fail('r_rejected', 'The local R API reported failure. No substitute analysis will run.', uncertain=method == 'POST')
        return value


class RAnalysisBridge:
    """One server/owner scoped instance. Registry methods are never HTTP routes.

    runtime_probe is a trusted local callable, not an HTTP or user input. It must
    return the currently verified runtime_id, source_sha256 and package_versions.
    It must check the listener process identity/start time and source/package
    evidence. None (the default) intentionally keeps execution unavailable.
    """
    def __init__(self, managed_root, *, client=None, runtime_profile=None, runtime_probe=None, clock=time.time):
        root = Path(managed_root)
        if root.is_symlink():
            _fail('storage_configuration', 'The bridge root must not be a symbolic link.')
        root.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.root = root.resolve(strict=True)
        self.client = client if client is not None else LocalRClient()
        self._profile = deepcopy(runtime_profile)
        self._probe, self._clock = runtime_probe, clock
        self._matrices, self._metadata, self._plans, self._executions = {}, {}, {}, {}
        self._lock = threading.RLock()
        self._prepare_lock = threading.Lock()
        self._registry_cells, self._registry_features = 0, 0

    def _matrix_capacity(self, data_id, cells=0, features=0):
        # Caller holds _lock. Check again immediately before the snapshot commit.
        if data_id in self._matrices:
            _fail('duplicate_record', 'Matrix registry IDs are immutable; register a new ID for changed data.')
        if len(self._matrices) >= MAX_MATRIX_RECORDS or self._registry_cells + cells > MAX_REGISTRY_CELLS or self._registry_features + features > MAX_REGISTRY_FEATURES:
            _fail('registry_limit', 'The bridge matrix registry reached its record, cell or feature limit. The owner must review retained records before starting a fresh instance; no data was deleted.')

    def _metadata_capacity(self, metadata_id):
        # Caller holds _lock.
        if metadata_id in self._metadata:
            _fail('duplicate_record', 'Metadata registry IDs are immutable; register a new ID for changed metadata.')
        if len(self._metadata) >= MAX_METADATA_RECORDS:
            _fail('registry_limit', 'The bridge metadata registry is full. Reuse existing immutable metadata IDs or ask the owner to review retained records; no data was deleted.')

    def register_matrix(self, data_id, dataset):
        """Internal: register a validated local matrix, then independently recheck it.

        Provenance is retained only as a bounded source label/digest. Numerical
        checks cannot establish biological provenance; the exact plan requires
        the user to confirm that this is unnormalized bulk RNA-seq count data.
        """
        _id(data_id)
        with self._lock:
            self._matrix_capacity(data_id)
        _object(dataset, {'id', 'omics', 'data_type', 'sample_ids', 'feature_ids', 'values', 'provenance'})
        if dataset.get('omics') != 'bulk_rnaseq' or dataset.get('data_type') != 'raw_counts':
            _fail('unsupported_input', 'This bridge supports only bulk RNA-seq raw counts, not TPM, FPKM or normalized data.')
        samples = _labels(dataset.get('sample_ids'), MAX_SAMPLES)
        features = _labels(dataset.get('feature_ids'), MAX_FEATURES)
        if len(samples) * len(features) > MAX_CELLS:
            _fail('input_limit', 'The count matrix exceeds one million cells.')
        with self._lock:
            self._matrix_capacity(data_id, len(samples) * len(features), len(features))
        values = dataset.get('values')
        if type(values) is not list or len(values) != len(features):
            _fail('matrix_shape', 'Each feature must have one count row.')
        totals, nonzero = [0] * len(samples), 0
        for row in values:
            if type(row) is not list or len(row) != len(samples):
                _fail('matrix_shape', 'Each count row must match the sample order.')
            for j, value in enumerate(row):
                # Exact integer check: no tolerance, no rounding, no bool/string.
                if type(value) not in (int, float) or value < 0 or value > 2147483647 or not math.isfinite(value) or value != int(value):
                    _fail('invalid_raw_counts', 'Counts must be finite nonnegative exact integers within the R integer range. Values are never rounded.')
                totals[j] += int(value)
            nonzero += any(row)
        if any(total == 0 for total in totals) or nonzero < 2:
            _fail('zero_counts', 'Every sample must have nonzero library size and at least two nonzero features are required.')
        if not any(all(value > 0 for value in row) for row in values):
            _fail('size_factors_unavailable', 'The supported default DESeq2 size-factor estimator requires at least one feature positive in all samples.')
        provenance = dataset.get('provenance', {})
        _object(provenance, {'source', 'sha256'})
        if set(provenance) != {'source', 'sha256'}:
            _fail('provenance', 'A source description and original-file SHA-256 are required; integer values alone do not prove raw-count provenance.')
        if 'source' in provenance and (type(provenance['source']) is not str or not 1 <= len(provenance['source']) <= 2048):
            _fail('provenance', 'A bounded provenance source description is required.')
        if 'sha256' in provenance and (type(provenance['sha256']) is not str or not SHA.fullmatch(provenance['sha256'])):
            _fail('provenance', 'Provenance checksum must be SHA-256.')
        with self._lock:
            self._matrix_capacity(data_id, len(samples) * len(features), len(features))
            self._matrices[data_id] = {
                'sample_ids': deepcopy(samples), 'feature_ids': deepcopy(features),
                'values': [[int(x) for x in row] for row in values], 'provenance': deepcopy(provenance)}
            self._registry_cells += len(samples) * len(features)
            self._registry_features += len(features)
        return {'data_id': data_id, 'n_features': len(features), 'n_samples': len(samples), 'raw_count_provenance_verified': False}

    def register_metadata(self, metadata_id, samples):
        """Internal: snapshot sample metadata. Batch or repeated subjects block plans."""
        _id(metadata_id)
        with self._lock:
            self._metadata_capacity(metadata_id)
        if type(samples) is not list or not 4 <= len(samples) <= MAX_SAMPLES:
            _fail('sample_count', 'Independent two-group analysis requires 4 to 256 samples.')
        seen = set()
        for row in samples:
            _object(row, {'id', 'group', 'batch', 'subject'})
            for value in row.values():
                _label(value)
            if 'id' not in row or 'group' not in row or row['id'] in seen:
                _fail('sample_metadata', 'Every sample needs a unique ID and a group label.')
            seen.add(row['id'])
        with self._lock:
            self._metadata_capacity(metadata_id)
            self._metadata[metadata_id] = deepcopy(samples)
        return {'metadata_id': metadata_id, 'n_samples': len(samples)}

    def _runtime(self, *, require_fresh=True):
        p = self._profile
        required = {'api_version', 'package_version', 'package_versions', 'source_contract', 'source_sha256',
                    'runtime_id', 'running_code_verified', 'verified_at', 'expires_at'}
        if type(p) is not dict or set(p) != required or self._probe is None:
            _fail('runtime_unverified', 'The local R runtime has not been independently verified for this bridge.')
        if p['api_version'] != '1.0' or p['source_contract'] != SOURCE_CONTRACT or p['running_code_verified'] is not True:
            _fail('runtime_unverified', 'The running R source contract is not verified.')
        if not all(type(p[k]) is str and SHA.fullmatch(p[k]) for k in ('source_sha256', 'runtime_id')):
            _fail('runtime_unverified', 'Runtime and source fingerprints are required.')
        packages = p['package_versions']
        if type(packages) is not dict or not {'EasyMultiProfiler', 'DESeq2', 'tidybulk', 'callr'} <= packages.keys() or any(type(v) is not str or not VERSION.fullmatch(v) for v in packages.values()) or p['package_version'] != packages['EasyMultiProfiler']:
            _fail('runtime_unverified', 'Verified R package versions, including DESeq2, are required.')
        now = self._clock()
        if not all(_finite_number(p[k]) for k in ('verified_at', 'expires_at')) or not p['verified_at'] < p['expires_at'] <= p['verified_at'] + 3600 or now < p['verified_at'] or (require_fresh and now >= p['expires_at']):
            _fail('runtime_expired', 'The local R verification expired; verify the current process before preparing a new plan.')
        try:
            observed = self._probe()
        except Exception:
            _fail('runtime_changed', 'The local R runtime identity could not be checked.')
        expected = {k: p[k] for k in ('runtime_id', 'source_sha256', 'package_versions')}
        if type(observed) is not dict or observed != expected:
            _fail('runtime_changed', 'The running process, reviewed source or R packages changed; verify the runtime again.')
        health = self.client.request('GET', '/api/health')
        caps = self.client.request('GET', '/api/capabilities')
        if health.get('status') != 'ok' or health.get('version') != p['package_version'] or caps.get('package_version') != p['package_version'] or caps.get('api_version') != p['api_version']:
            _fail('r_version_mismatch', 'R API or package versions do not match the verified runtime.')
        features = caps.get('features')
        if type(caps.get('workflows')) is not list or type(caps.get('tools')) is not list:
            _fail('r_capabilities', 'R capability lists are missing or malformed.')
        if caps.get('success') is not True or type(features) is not dict or any(features.get(k) is not True for k in ('path_import', 'async_jobs', 'job_cancel')) or 'transcriptomics' not in caps.get('workflows', []) or 'emp.analyze.differential' not in caps.get('tools', []):
            _fail('r_capabilities', 'R path import, transcriptomics differential analysis, async jobs and cancellation must be available.')
        return {k: deepcopy(p[k]) for k in ('api_version', 'package_version', 'package_versions', 'source_contract', 'source_sha256', 'runtime_id', 'expires_at')}

    @staticmethod
    def _csv(rows):
        output = io.StringIO(newline='')
        writer = csv.writer(output, lineterminator='\n', quoting=csv.QUOTE_ALL)
        writer.writerows(rows)
        return output.getvalue().encode('utf-8')

    def _files(self, plan):
        try:
            directory = self.root / plan['public']['plan_id']
            if directory.is_symlink() or directory.resolve() != directory:
                _fail('input_changed', 'The staged input directory changed.')
            paths = {}
            for name, digest in plan['file_hashes'].items():
                path = directory / name
                if path.is_symlink() or not path.is_file() or path.stat().st_size > 32 * 1024 * 1024 or _sha_bytes(path.read_bytes()) != digest:
                    _fail('input_changed', 'Staged input changed after validation. Prepare a new plan.')
                paths[name] = str(path)
            return paths
        except (OSError, RuntimeError):
            _fail('input_changed', 'The staged input files are no longer safely readable.')

    def _preview(self, plan):
        paths = self._files(plan)
        response = self.client.request('POST', '/api/import/path/preview',
                                       {'data_path': paths['counts.csv'], 'metadata_path': paths['metadata.csv'], 'data_type': 'normal'})
        public = plan['public']
        for field, name in [('data', 'counts.csv'), ('metadata', 'metadata.csv')]:
            item = response.get(field)
            if type(item) is not dict or item.get('sha256') != plan['file_hashes'][name] or item.get('path') != paths[name]:
                _fail('r_preview_mismatch', 'R preview did not verify the exact staged file checksums and paths.')
        overlap = response.get('sample_overlap', {})
        if type(overlap) is not dict:
            _fail('r_preview_mismatch', 'R preview sample matching is missing or malformed.')
        count = len(public['sample_order'])
        if response.get('success') is not True or response['data'].get('orientation') != 'features_in_rows' or response['data'].get('columns') != count + 1 or response['metadata'].get('sample_id_column') != 'sample_id' or any(overlap.get(k) != count for k in ('assay', 'metadata', 'matched')) or overlap.get('assay_only') != [] or overlap.get('metadata_only') != [] or response.get('warnings') != []:
            _fail('r_preview_mismatch', 'R preview sample matching or orientation differs from the confirmed inputs.')
        return paths

    def _disk_reserve(self, additional_bytes):
        try:
            free = shutil.disk_usage(self.root).free
        except OSError:
            _fail('staging_unavailable', 'The bridge cannot verify free disk space; no new staging or import is permitted.')
        if free < additional_bytes + MIN_DISK_FREE_BYTES:
            _fail('disk_reserve', 'Staging or import would violate the 512 MiB minimum free-disk reserve. No files were deleted to make space.')

    def _stage(self, plan_id, files):
        if self.root.is_symlink() or self.root.resolve() != self.root:
            _fail('staging_unavailable', 'The bridge staging root changed; owner review is required.')
        requested_bytes = sum(len(content) for content in files.values())
        if requested_bytes > MAX_PLAN_STAGING_BYTES:
            _fail('staging_limit', 'This plan exceeds the 16 MiB staging limit; no input files were written.')
        # Include retained files from earlier instances. Never follow symlinks or
        # delete files. The dedicated root belongs to one hosting bridge instance.
        total, entries, pending = 0, 0, [self.root]
        try:
            while pending:
                with os.scandir(pending.pop()) as directory:
                    for entry in directory:
                        entries += 1
                        if entries + 1 + len(files) > MAX_STAGING_ENTRIES:
                            _fail('staging_limit', 'The bridge staging directory has reached its entry limit; owner review is required.')
                        if entry.is_symlink():
                            _fail('staging_unavailable', 'A symbolic link exists in the dedicated bridge staging directory; owner review is required.')
                        if entry.is_dir(follow_symlinks=False):
                            pending.append(Path(entry.path))
                        elif entry.is_file(follow_symlinks=False):
                            total += entry.stat(follow_symlinks=False).st_size
                        else:
                            _fail('staging_unavailable', 'An unsupported file type exists in the bridge staging directory.')
                        if total + requested_bytes > MAX_TOTAL_STAGING_BYTES:
                            _fail('staging_limit', 'Retained bridge staging data would exceed 128 MiB. Owner review is required; no files were deleted.')
            if total + requested_bytes > MAX_TOTAL_STAGING_BYTES:
                _fail('staging_limit', 'Retained bridge staging data would exceed 128 MiB. Owner review is required; no files were deleted.')
            self._disk_reserve(requested_bytes)
            directory = self.root / plan_id
            directory.mkdir(mode=0o700)
            for name, content in files.items():
                path = directory / name
                with path.open('xb') as handle:
                    handle.write(content)
                path.chmod(0o600)
        except OSError:
            _fail('staging_failed', 'Input staging failed. Partial bridge files may remain for owner review; no analysis was submitted and no files were deleted.')

    def prepare(self, request):
        """Validate and preview only, with bounded, single-flight preparation."""
        if not self._prepare_lock.acquire(blocking=False):
            _fail('prepare_busy', 'Another R plan is being prepared; wait for it to finish before preparing another.')
        try:
            with self._lock:
                if len(self._plans) >= MAX_PLANS:
                    _fail('plan_limit', 'The bridge has reached its 16-plan limit, including blocked plans. Owner review is required; no records or files were deleted.')
            return self._prepare(request)
        finally:
            self._prepare_lock.release()

    def _prepare(self, request):
        """Private implementation; prepare() owns the single-flight/capacity gate."""
        _object(request, {'data_id', 'metadata_id', 'ref_group', 'test_group', 'design', 'filter_low', 'raw_counts_evidence'})
        data_id, metadata_id = _id(request.get('data_id')), _id(request.get('metadata_id'))
        evidence = request.get('raw_counts_evidence')
        if type(evidence) is not str or not 1 <= len(evidence) <= 2048 or evidence.strip() != evidence or any(ord(c) < 32 or ord(c) == 127 for c in evidence):
            _fail('raw_counts_evidence', 'Provide documented evidence that this matrix contains unnormalized RNA-seq raw counts; use an explicit synthetic-fixture statement for tests.')
        ref, test = _label(request.get('ref_group')), _label(request.get('test_group'))
        design = request.get('design')
        _object(design, {'group', 'independent_samples'})
        if design.get('group') != 'group' or design.get('independent_samples') is not True:
            _fail('unsupported_design', 'Only ~group with explicitly independent biological samples is supported; batch, pairing and covariates are not supported.')
        filter_low = request.get('filter_low', True)
        if type(filter_low) is not bool:
            _fail('invalid_parameter', 'filter_low must be a boolean.')
        with self._lock:
            if data_id not in self._matrices or metadata_id not in self._metadata:
                _fail('unknown_record', 'The selected server-managed matrix or metadata record is unavailable.')
            # Registry snapshots are immutable and private; avoid copying a
            # million-cell matrix for each blocked or repeated preparation.
            data, samples = self._matrices[data_id], self._metadata[metadata_id]
        if any('batch' in row for row in samples) or len({row['subject'] for row in samples if 'subject' in row}) != sum('subject' in row for row in samples):
            _fail('unsupported_design', 'Batch metadata or repeated subjects require an adjusted design this endpoint cannot fit.')
        if set(data['sample_ids']) != {row['id'] for row in samples}:
            _fail('sample_mismatch', 'Matrix and metadata must have exactly the same sample IDs; no implicit samples are dropped.')
        groups = Counter(row['group'] for row in samples)
        if ref == test or set(groups) != {ref, test} or min(groups.values()) < 2:
            _fail('unsupported_contrast', 'Choose exactly two groups with at least two independent biological replicates each.')
        by_id = {row['id']: row for row in samples}
        plan_id = secrets.token_hex(16)
        feature_aliases = {f'emp_feature_{i:06d}': name for i, name in enumerate(data['feature_ids'], 1)}
        sample_aliases = [f'emp_sample_{i:04d}' for i in range(1, len(data['sample_ids']) + 1)]
        nonzero = sum(any(row) for row in data['values'])
        minimum_positive = max(3, math.ceil(len(samples) * 0.1))
        eligible = {alias for alias, row in zip(feature_aliases, data['values']) if sum(x > 0 for x in row) >= minimum_positive}
        public = {'plan_id': plan_id, 'bridge_version': BRIDGE_VERSION, 'data_id': data_id, 'metadata_id': metadata_id,
                  'method': 'DESeq2', 'omics': 'bulk_rnaseq', 'data_type': 'raw_counts',
                  'design': {'group': 'group', 'independent_samples': True},
                  'contrast': {'test': test, 'reference': ref, 'log2_fold_change': 'test / reference'},
                  'group_counts': dict(groups), 'sample_order': list(data['sample_ids']),
                  'n_features_input': len(data['feature_ids']), 'n_features_after_zero_removal': nonzero,
                  'all_zero_features_removed_at_import': len(data['feature_ids']) - nonzero,
                  'native_result_filter': {'minimum_positive_samples': minimum_positive, 'eligible_features': len(eligible),
                                           'applies_even_if_filter_low_false': True, 'drops_missing_pvalue_rows': True},
                  'parameters': {'filter_low': filter_low, 'comparison_mode': 'pairwise', 'subset_two_groups': True, 'cores': 1},
                  'input_sha256': {}, 'inputs_staged': False,
                  'provenance': deepcopy(data['provenance']), 'raw_counts_evidence': evidence, 'raw_count_provenance_verified': False,
                  'confirmation_required': True, 'execution_performed': False,
                  'warnings': ['Confirm these are unnormalized raw bulk RNA-seq counts and independent biological replicates. Integer values alone do not prove count provenance.',
                               'Only an unadjusted two-group design is supported; no batch, pairing, covariates, fallback method or automatic outlier removal.',
                               'R imports remove all-zero features. The returned native table always filters to features positive in at least max(3, ceil(10% of samples)), even when filter_low is false, and removes rows with missing p-values.',
                               'DESeq2 uses its existing default normalization, dispersion fitting, independent filtering and p-value settings; this bridge does not add alpha or shrinkage parameters.'],
                  'runtime': None, 'blockers': [], 'executable': False}
        plan = {'public': public, 'file_hashes': public['input_sha256'].copy(), 'features': feature_aliases, 'eligible_features': eligible, 'execution_id': None}
        try:
            # Runtime rejection precedes CSV generation and ALL plan-directory
            # writes. A blocked plan has an empty input_sha256 and no staged files.
            public['runtime'] = self._runtime()
            files = {'counts.csv': self._csv([['feature', *sample_aliases]] + [[alias, *row] for alias, row in zip(feature_aliases, data['values'])]),
                     'metadata.csv': self._csv([['sample_id', 'emp_group']] + [[alias, 'reference' if by_id[sid]['group'] == ref else 'test'] for alias, sid in zip(sample_aliases, data['sample_ids'])])}
            public['input_sha256'] = {name: _sha_bytes(content) for name, content in files.items()}
            plan['file_hashes'] = public['input_sha256'].copy()
            self._stage(plan_id, files)
            public['inputs_staged'] = True
            self._preview(plan)
            public['executable'] = True
        except BridgeError as error:
            public['blockers'].append(error.as_dict())
        public['plan_sha256'] = _digest(public)
        with self._lock:
            self._plans[plan_id] = plan
        return deepcopy(public)

    def _public_execution(self, execution):
        return deepcopy({k: v for k, v in execution.items() if not k.startswith('_')})

    def execute(self, request):
        """Confirm exact prepared plan, recheck runtime/files, import, submit once.

        A valid confirmation is an explicit user action captured by the host,
        never a model-generated boolean. Repeated submission returns its original
        execution state. Any uncertain POST outcome requires owner reconciliation.
        """
        _object(request, {'plan_id', 'confirmed', 'plan_sha256'})
        plan_id = _id(request.get('plan_id'))
        with self._lock:
            plan = self._plans.get(plan_id)
            if plan is None:
                _fail('unknown_plan', 'The prepared plan is unavailable; do not blindly resubmit an earlier execution.')
            public = plan['public']
            if request.get('confirmed') is not True or type(request.get('plan_sha256')) is not str or not secrets.compare_digest(request['plan_sha256'], public['plan_sha256']):
                _fail('confirmation_required', 'Explicit confirmation of this exact plan digest is required.')
            if not public['executable']:
                _fail('plan_blocked', 'Resolve all preflight blockers and prepare a new plan before execution.')
            if plan['execution_id']:
                return self._public_execution(self._executions[plan['execution_id']])
            execution_id = secrets.token_hex(16)
            execution = {'execution_id': execution_id, 'plan_id': plan_id, 'plan_sha256': public['plan_sha256'],
                         'status': 'preflight', 'session_created': False, 'execution_performed': False,
                         'retry_allowed': False, 'needs_reconciliation': False, '_session_id': None, '_job_id': None,
                         '_experiment': 'emp_bridge_' + plan_id, '_io_lock': threading.Lock()}
            plan['execution_id'] = execution_id
            self._executions[execution_id] = execution
        phase = 'preflight'
        try:
            if self._runtime() != public['runtime']:
                _fail('runtime_changed', 'Runtime verification changed after plan confirmation.')
            paths = self._preview(plan)
            # Recheck bytes immediately before import. Protect the managed root
            # from other writers; the R path import API cannot lock across HTTP.
            self._files(plan)
            self._disk_reserve(0)
            phase = 'import'
            execution['status'] = 'importing'
            imported = self.client.request('POST', '/api/import/path', {'data_path': paths['counts.csv'],
                'metadata_path': paths['metadata.csv'], 'data_type': 'normal', 'assay_name': 'counts',
                'experiment_name': execution['_experiment']})
            session = imported.get('session_id')
            if type(session) is not str or not re.fullmatch(SESSION, session):
                _fail('r_import_contract', 'R import did not return a valid session identifier.', uncertain=True)
            execution.update(_session_id=session, session_created=True)
            if imported.get('success') is not True or imported.get('experiment_name') != execution['_experiment'] or imported.get('samples') != len(public['sample_order']) or imported.get('features') != public['n_features_after_zero_removal'] or imported.get('assay') != 'counts':
                _fail('r_import_mismatch', 'R import dimensions or assay differ from the exact plan; no analysis was submitted.')
            phase = 'submit'
            execution['status'] = 'submitting'
            submitted = self.client.request('POST', '/api/analyze/differential/async', {'session_id': session,
                'experiment': execution['_experiment'], 'method': 'DESeq2', 'group_var': 'emp_group',
                'ref_group': 'reference', 'test_group': 'test', **public['parameters']})
            job_id = submitted.get('job_id')
            if submitted.get('success') is not True or type(job_id) is not str or not re.fullmatch(JOB, job_id):
                _fail('r_job_contract', 'R submission did not return a valid job identifier.', uncertain=True)
            execution.update(_job_id=job_id, status='queued', execution_performed=True, progress=0)
        except BridgeError as error:
            uncertain = error.uncertain and phase in {'import', 'submit'}
            execution.update(status='submission_uncertain' if uncertain else 'preflight_failed' if phase == 'preflight' else 'error',
                             error=error.as_dict(), needs_reconciliation=uncertain)
            if uncertain and phase == 'submit':
                execution['execution_performed'] = None
        return self._public_execution(execution)

    def _execution(self, request):
        _object(request, {'execution_id'})
        key = _id(request.get('execution_id'))
        with self._lock:
            if key not in self._executions:
                _fail('unknown_execution', 'This execution is not owned by the current bridge instance.')
            return self._executions[key]

    def _result(self, execution):
        # The compact table can have legacy contrast-label conventions. Require
        # the separate native DESeq2 cache with explicit test/reference metadata.
        path = f"/api/analyze/diff_raw/{execution['_session_id']}/{execution['_experiment']}"
        raw = self.client.request('GET', path)
        if raw.get('success') is not True or raw.get('method') != 'DESeq2' or raw.get('group_var') != 'emp_group' or raw.get('ref_group') != 'reference' or raw.get('test_group') != 'test':
            _fail('result_unverified', 'The R result does not attest the requested DESeq2 method and contrast.')
        required = {'feature', 'baseMean', 'log2FoldChange', 'lfcSE', 'stat', 'pvalue', 'padj'}
        columns = raw.get('columns')
        if type(columns) is not list or any(type(x) is not str for x in columns) or len(set(columns)) != len(columns) or not required <= set(columns):
            _fail('result_unverified', 'The native DESeq2 result columns are missing.')
        try:
            rows = json.loads(raw['data']) if type(raw.get('data')) is str else raw.get('data')
        except (ValueError, TypeError, RecursionError):
            _fail('result_unverified', 'The native DESeq2 result table is invalid.')
        plan = self._plans[execution['plan_id']]
        if type(rows) is not list or not 1 <= len(rows) <= plan['public']['native_result_filter']['eligible_features'] or raw.get('n_rows') != len(rows):
            _fail('result_unverified', 'The native DESeq2 result row count is invalid.')
        seen, output = set(), []
        for row in rows:
            if type(row) is not dict or not required <= row.keys():
                _fail('result_unverified', 'The native DESeq2 result rows are incomplete.')
            feature = row['feature']
            if type(feature) is not str or feature not in plan['eligible_features'] or feature in seen:
                _fail('result_unverified', 'Result features do not match the staged matrix.')
            seen.add(feature)
            for field in required - {'feature'}:
                value = row[field]
                if value is not None and (not _finite_number(value) or (field in {'pvalue', 'padj'} and not 0 <= value <= 1) or (field in {'baseMean', 'lfcSE'} and value < 0)):
                    _fail('result_unverified', 'The native DESeq2 result contains invalid statistics.')
            if any(row[k] is None for k in ('baseMean', 'log2FoldChange', 'lfcSE', 'stat', 'pvalue')):
                _fail('result_unverified', 'Native DESeq2 statistics are incomplete; a renamed compact-result fallback is not accepted.')
            output.append({**{k: row[k] for k in required - {'feature'}}, 'feature': plan['features'][feature]})
        return {'method': 'DESeq2', 'contrast': deepcopy(plan['public']['contrast']),
                'columns': ['feature', 'baseMean', 'log2FoldChange', 'lfcSE', 'stat', 'pvalue', 'padj'],
                'n_rows': len(output), 'data': output, 'source': 'local_R_native_diff_raw',
                'runtime': deepcopy(plan['public']['runtime']), 'input_sha256': deepcopy(plan['file_hashes']),
                'native_result_filter': deepcopy(plan['public']['native_result_filter']),
                'notes': ['Adjusted p-values may be null. The existing native R cache removes rows with missing p-values; none are imputed.',
                          'Positive log2FoldChange means higher in the test group. No limma or other fallback is accepted.']}

    def poll(self, request):
        execution = self._execution(request)
        with execution['_io_lock']:
            if execution['status'] in TERMINAL or not execution['_job_id']:
                return self._public_execution(execution)
            # Results must belong to the attested server process as well.
            self._runtime(require_fresh=False)
            response = self.client.request('GET', '/api/jobs/' + execution['_job_id'])
            job = response.get('job')
            if response.get('success') is not True or type(job) is not dict or job.get('id') != execution['_job_id'] or job.get('session_id') != execution['_session_id'] or job.get('kind') != 'differential':
                _fail('r_job_contract', 'The R job does not match this execution.')
            state = job.get('status')
            if type(state) is not str or state not in {'queued', 'running', 'done', 'error', 'cancel_requested', 'cancelled'}:
                _fail('r_job_contract', 'The R job status is unknown.')
            progress = job.get('progress', 0)
            execution['progress'] = progress if _finite_number(progress) and 0 <= progress <= 100 else 0
            execution['status'] = state
            if state == 'error':
                execution['error'] = {'code': 'r_analysis_failed', 'message': 'DESeq2 failed in R. No fallback was run; inspect the local R job log without sharing credentials.', 'outcome_uncertain': False}
            elif state == 'done':
                try:
                    execution['result'] = self._result(execution)
                    execution['status'] = 'completed'
                except BridgeError as error:
                    execution.update(status='result_unverified', error=error.as_dict())
            return self._public_execution(execution)

    def cancel(self, request):
        """Request cancellation only for a job created by this instance; never delete."""
        execution = self._execution(request)
        with execution['_io_lock']:
            if execution['status'] in TERMINAL:
                return self._public_execution(execution)
            if not execution['_job_id']:
                _fail('cancel_not_available', 'Submission is still pending or uncertain; inspect its outcome before cancellation.')
            self._runtime(require_fresh=False)
            response = self.client.request('POST', '/api/jobs/' + execution['_job_id'] + '/cancel', {})
            cancellation = response.get('cancellation')
            if response.get('success') is not True or type(cancellation) is not dict or cancellation.get('job_id') != execution['_job_id'] or type(cancellation.get('status')) is not str or cancellation.get('status') not in {'cancel_requested', 'cancelled', 'already_finished'}:
                _fail('r_cancel_contract', 'R did not confirm the cancellation request. Poll the existing execution; do not claim it stopped.')
            state = cancellation['status']
            if state != 'already_finished':
                execution['status'] = state
            execution['cancellation'] = {'status': state}
            return self._public_execution(execution)
