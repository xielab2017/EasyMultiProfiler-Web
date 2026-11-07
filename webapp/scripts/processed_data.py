"""GEO supplementary-file discovery and bounded downloads; no analysis execution."""
import csv
import gzip
import hashlib
import io
import math
import os
from pathlib import Path
import re
import shutil
import time
import uuid
from urllib.parse import urlencode, urlsplit, unquote
from urllib.request import Request, build_opener
import public_data as m

GEO = 'https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi'
MAX_DOWNLOAD = 32 * 1024 * 1024
MAX_UNCOMPRESSED = 64 * 1024 * 1024


def safe_url(value, accession):
    try:
        parsed = urlsplit(value)
        path = unquote(parsed.path)
        if parsed.scheme not in {'https', 'ftp'} or parsed.hostname != 'ftp.ncbi.nlm.nih.gov' or parsed.port or parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise ValueError('unapproved origin')
        expected = re.sub(r'\d{1,3}$', 'nnn', accession)
        prefix = f'/geo/series/{expected}/{accession}/suppl/'
        if '%' in path or not path.startswith(prefix) or '..' in path.split('/') or '\\' in path or any(ord(c) < 32 for c in path):
            raise ValueError('unapproved path')
    except ValueError as exc:
        raise m.MetadataError('Unapproved GEO supplementary-file URL') from exc
    return 'https://ftp.ncbi.nlm.nih.gov' + parsed.path


def parse_soft(text, accession):
    if not re.fullmatch(r'GSE\d+', accession): raise m.MetadataError('Expected GEO series accession')
    files, samples, seen = [], [], set()
    title = ''
    for line in text.splitlines():
        if ' = ' not in line: continue
        key, value = line.split(' = ', 1)
        if key == '!Series_title': title = value
        if key == '!Series_sample_id': samples.append(value)
        if key.startswith('!Series_supplementary_file') and value.upper() != 'NONE':
            url = safe_url(value, accession)
            if url in seen: continue
            seen.add(url)
            name = unquote(urlsplit(url).path.rsplit('/', 1)[-1])
            fmt = 'archive' if name.lower().endswith(('.tar', '.tar.gz', '.zip')) else 'tabular_candidate' if name.lower().endswith(('.txt','.tsv','.csv','.txt.gz','.tsv.gz','.csv.gz')) else 'other'
            files.append({'id': str(len(files)), 'name': name, 'url': url, 'format_hint': fmt,
                          'data_type': 'unknown', 'bytes': None, 'checksum': None,
                          'warning': 'Filename and GEO supplementary status do not establish raw counts or analysis suitability.'})
    if not title: raise m.MetadataError('GEO response has no series metadata; accession may be invalid or inaccessible')
    return {'accession': accession, 'title': title, 'sample_accessions': samples, 'files': files,
            'sample_annotation_status': 'GSM accession links only; sample groups are not inferred',
            'maximum_download_bytes': MAX_DOWNLOAD, 'status': 'processed_candidates'}


def discover(accession):
    accession = m.accession(accession)
    if not accession.startswith('GSE'): raise m.MetadataError('Processed discovery requires a GSE accession')
    url = GEO + '?' + urlencode({'acc': accession, 'targ': 'self', 'form': 'text', 'view': 'quick'})
    opener = build_opener(m.NoRedirect())
    try:
        with opener.open(Request(url, headers={'User-Agent': 'EasyMultiProfiler-PublicMetadata/1.0'}), timeout=30) as response:
            data = response.read(m.MAX_BYTES + 1)
        if len(data) > m.MAX_BYTES: raise m.MetadataError('GEO metadata is too large')
        result = parse_soft(data.decode('utf-8'), accession)
        deadline = time.monotonic() + 45
        # Prefer likely matrices; the budget is shared across at most ten files.
        for item in sorted(result['files'], key=lambda f: f['format_hint'] != 'tabular_candidate')[:10]:
            item['size_status'] = 'unavailable'
            remaining = deadline - time.monotonic()
            if remaining <= 0: item['size_status'] = 'probe_budget_exhausted'; continue
            try:
                with opener.open(Request(item['url'], method='HEAD'), timeout=min(20, remaining)) as response:
                    size = response.headers.get('Content-Length', '')
                    if size.isdigit(): item['bytes'] = int(size); item['size_status'] = 'head'
            except OSError: pass
            remaining = deadline - time.monotonic()
            if item['bytes'] is None and remaining > 0:
                try:
                    with opener.open(Request(item['url'], headers={'Range':'bytes=0-0'}), timeout=min(15, remaining)) as response:
                        content_range = response.headers.get('Content-Range', '')
                        match = re.fullmatch(r'bytes 0-0/([0-9]+)', content_range)
                        length = response.headers.get('Content-Length', '')
                        if response.status == 206 and match:
                            item['bytes'] = int(match.group(1)); item['size_status'] = 'range_header'
                        elif response.status == 200 and length.isdigit():
                            item['bytes'] = int(length); item['size_status'] = 'get_header'
                        # Never consume the full body during a size probe.
                except OSError: pass
        result['source'] = {'url': url, 'sha256': hashlib.sha256(data).hexdigest()}
        return result
    except (OSError, UnicodeError) as exc:
        raise m.MetadataError('GEO metadata unavailable; check network and accession') from exc


def inspect_table(path, name):
    output = {'data_type': 'unknown', 'deseq2_ready': False, 'sample_annotation': 'not_validated',
              'warning': 'Numerical structure is not proof of raw counts. Confirm author documentation, feature IDs and sample groups.'}
    if not name.lower().endswith(('.txt','.csv','.tsv','.txt.gz','.csv.gz','.tsv.gz')):
        return output | {'inspection': 'unsupported_format_not_extracted'}
    try:
        opener = gzip.open if name.lower().endswith('.gz') else open
        with opener(path, 'rb') as handle: data = handle.read(MAX_UNCOMPRESSED + 1)
        if len(data) > MAX_UNCOMPRESSED: return output | {'inspection': 'uncompressed_size_limit'}
        text = data.decode('utf-8-sig')
        first = next((line for line in text.splitlines() if line and not line.startswith('#')), '')
        delimiter = '\t' if '\t' in first else ','
        rows = csv.reader(io.StringIO(text), delimiter=delimiter)
        header = next((r for r in rows if r and not r[0].startswith('#')), [])
        if len(header) < 2: return output | {'inspection': 'not_a_supported_matrix'}
        annotation_columns = [i for i, label in enumerate(header) if i > 0 and label.lower() in {'length', 'gene_length', 'gene_name', 'symbol', 'description'}]
        sample_indices = [i for i in range(1, len(header)) if i not in annotation_columns]
        if not sample_indices: return output | {'inspection': 'no_sample_columns'}
        count = 0; integers = True; nonnegative = True; consistent = len(set(header)) == len(header); finite = True; feature_ids = set(); duplicate_features = False
        for row in rows:
            if not row or row[0].startswith('#'): continue
            if len(row) != len(header): consistent = False; break
            if row[0] in feature_ids: duplicate_features = True
            feature_ids.add(row[0])
            if count >= 1000000: return output | {'inspection': 'feature_row_limit'}
            try: values = [float(row[i]) for i in sample_indices]
            except ValueError: consistent = False; break
            finite = finite and all(math.isfinite(v) for v in values)
            nonnegative = nonnegative and all(v >= 0 for v in values)
            integers = integers and all(math.isfinite(v) and v.is_integer() for v in values)
            count += 1
        output.update({'inspection': 'complete' if consistent and count else 'unsupported_or_malformed_table',
                       'feature_rows': count, 'column_labels': [header[i] for i in sample_indices], 'excluded_annotation_columns': [header[i] for i in annotation_columns], 'finite': finite,
                       'nonnegative': nonnegative, 'integer_valued': integers, 'duplicate_feature_ids': duplicate_features})
        if consistent and count and finite:
            output['data_type'] = 'count_like_unverified' if integers and nonnegative else 'noninteger_or_transformed_not_raw_count_input'
        return output
    except (OSError, UnicodeError, csv.Error) as exc:
        return output | {'inspection': 'unreadable_or_invalid_compression', 'error': type(exc).__name__}


def download(value, file_id, destination, confirmed=False):
    if confirmed is not True: raise m.MetadataError('Explicit per-file download confirmation required')
    if not isinstance(value, dict) or value.get('status') != 'processed_candidates': raise m.MetadataError('A processed-file manifest is required')
    matches = [f for f in value['files'] if f['id'] == file_id]
    if len(matches) != 1: raise m.MetadataError('Unknown file ID')
    item = matches[0]; url = safe_url(item['url'], value['accession'])
    if item['bytes'] is None or not 0 < item['bytes'] <= MAX_DOWNLOAD:
        raise m.MetadataError('Download requires a known size of at most 32 MiB')
    if item['format_hint'] != 'tabular_candidate': raise m.MetadataError('Only plain/gzip TXT, TSV or CSV candidates supported; archives are not extracted')
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(destination).free < item['bytes'] + MAX_UNCOMPRESSED + 1024**3:
        raise m.MetadataError('Insufficient space for download, inspection and 1 GiB reserve')
    key = str(uuid.uuid4()); temporary = destination / (key + '.part'); final = destination / (key + '.data')
    digest = hashlib.sha256(); actual = 0
    try:
        with build_opener(m.NoRedirect()).open(Request(url), timeout=30) as response, temporary.open('xb') as output:
            while True:
                block = response.read(65536)
                if not block: break
                actual += len(block)
                if actual > MAX_DOWNLOAD or actual > item['bytes']: raise m.MetadataError('Download exceeds declared size or limit')
                digest.update(block); output.write(block)
        if actual != item['bytes']: raise m.MetadataError('Downloaded size differs from metadata; refresh and retry')
        os.replace(temporary, final)
        result = {'status': 'downloaded', 'download_id': key, 'source_url': url, 'source_name': item['name'],
                  'bytes': actual, 'sha256': digest.hexdigest(), 'publisher_checksum_verified': False,
                  'inspection': inspect_table(final, item['name']), 'analysis_executed': False}
        (destination / (key + '.json')).write_text(__import__('json').dumps(result, ensure_ascii=False, indent=2))
        return result
    finally:
        temporary.unlink(missing_ok=True)


# Annotation retrieval never follows URLs supplied by metadata or matrix contents.
MAX_ANNOTATION_DOWNLOAD = 2 * 1024 * 1024


def _sample_record(accession):
    return {'accession': accession, 'descriptions': [], 'characteristics': [],
            'source_names': [], 'platform_ids': []}


def _sample_field(record, key, value):
    if key == '!Sample_title': record['title'] = value
    elif key == '!Sample_description': record['descriptions'].append(value)
    elif re.fullmatch(r'!Sample_characteristics(?:_ch\d+)?', key): record['characteristics'].append(value)
    elif re.fullmatch(r'!Sample_source_name(?:_ch\d+)?', key): record['source_names'].append(value)
    elif key == '!Sample_platform_id': record['platform_ids'].append(value)


def _matrix_annotation_rows(text):
    # Do not construct a second in-memory copy of the expression table.
    rows = []
    for row in csv.reader(io.StringIO(text), delimiter='\t'):
        if row and row[0] == '!series_matrix_table_begin': break
        if row and row[0].startswith(('!Sample_', '!Series_')): rows.append(row)
    return rows


def parse_sample_annotations(text, accession=None):
    """Read tab-separated series-matrix metadata, never infer sample groups."""
    rows = _matrix_annotation_rows(text)
    if accession is not None:
        series = [r[1:] for r in rows if r[0] == '!Series_geo_accession']
        if series != [[accession]]: raise m.MetadataError('Series matrix accession does not match the requested GSE')
    id_rows = [r[1:] for r in rows if r[0] == '!Sample_geo_accession']
    ids = id_rows[0] if len(id_rows) == 1 else []
    if not ids or any(not re.fullmatch(r'GSM\d+', key) for key in ids) or len(set(ids)) != len(ids):
        raise m.MetadataError('Missing, invalid or duplicate GEO sample accessions')
    records = [_sample_record(key) for key in ids]
    for row in rows:
        if not row[0].startswith('!Sample_'): continue
        if len(row) != len(ids) + 1:
            raise m.MetadataError('Sample annotation row does not match the sample count')
        for record, value in zip(records, row[1:]): _sample_field(record, row[0], value)
    return records


def parse_family_sample_annotations(text, accession):
    """Read only sample fields from an official GEO family SOFT response."""
    if not isinstance(accession, str) or not re.fullmatch(r'GSE\d+', accession):
        raise m.MetadataError('Expected GSE accession')
    records, members, series_ids = [], [], []
    current = None
    section = None
    seen_series = False
    for line in io.StringIO(text):
        line = line.rstrip('\r\n')
        if ' = ' not in line: continue
        key, value = line.split(' = ', 1)
        if key.startswith('^'):
            section = key
            current = None
            if key == '^SERIES':
                if seen_series or value != accession:
                    raise m.MetadataError('Family SOFT series does not match the requested GSE')
                seen_series = True
            elif key == '^SAMPLE':
                if not re.fullmatch(r'GSM\d+', value): raise m.MetadataError('Invalid family SOFT sample accession')
                current = _sample_record(value)
                records.append(current)
            continue
        if section == '^SERIES':
            if key == '!Series_sample_id': members.append(value)
            elif key == '!Series_geo_accession': series_ids.append(value)
        elif current is not None:
            if key == '!Sample_geo_accession' and value != current['accession']:
                raise m.MetadataError('Family SOFT sample accession mismatch')
            _sample_field(current, key, value)
    ids = [record['accession'] for record in records]
    if not seen_series or series_ids != [accession]:
        raise m.MetadataError('Missing or mismatched family SOFT series accession')
    if not ids or len(set(ids)) != len(ids) or not members or len(set(members)) != len(members) or set(ids) != set(members):
        raise m.MetadataError('Missing, duplicate or incomplete family SOFT sample membership')
    return records


def match_samples(labels, records):
    """Require exact, unique and one-to-one identifiers; never use row order."""
    if not isinstance(labels, (list, tuple)) or any(not isinstance(label, str) for label in labels):
        raise m.MetadataError('Column labels must be strings')
    matches = []
    for label in labels:
        candidates = [r for r in records if label and (label == r['accession'] or label in r['descriptions'])]
        sample = candidates[0] if len(candidates) == 1 else None
        fields = []
        if sample is not None:
            if label == sample['accession']: fields.append('Sample_geo_accession')
            if label in sample['descriptions']: fields.append('Sample_description')
        matches.append({'column': label, 'status': 'exact' if sample else 'unmatched_or_ambiguous',
                        'sample': sample, 'matched_fields': fields})
    used = {}
    for item in matches:
        if item['sample'] is not None:
            key = item['sample']['accession']
            used[key] = used.get(key, 0) + 1
    for item in matches:
        if item['sample'] is not None and used[item['sample']['accession']] != 1:
            item.update(status='unmatched_or_ambiguous', sample=None, matched_fields=[])
    return matches


def _read_annotation_source(url, source_format):
    with build_opener(m.NoRedirect()).open(Request(url, headers={
            'User-Agent': 'EasyMultiProfiler-PublicMetadata/1.0', 'Accept-Encoding': 'identity'}), timeout=20) as response:
        data = response.read(MAX_ANNOTATION_DOWNLOAD + 1)
    if len(data) > MAX_ANNOTATION_DOWNLOAD:
        raise m.MetadataError('Annotation download exceeds 2 MiB; explicit selection needed')
    with gzip.GzipFile(fileobj=io.BytesIO(data)) as handle: unpacked = handle.read(MAX_UNCOMPRESSED + 1)
    if len(unpacked) > MAX_UNCOMPRESSED: raise m.MetadataError('Expanded annotation exceeds limit')
    return unpacked.decode('utf-8-sig'), {
        'source_url': url, 'source_format': source_format,
        'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data),
        'uncompressed_bytes': len(unpacked), 'publisher_checksum_verified': False}


def fetch_annotations(accession, labels=None):
    """Try one series matrix, then at most one bounded official family SOFT.

    Pass matrix column labels to detect partial/mismatched sample metadata.
    No supplementary files, platform matrices, raw reads or expression tables
    are downloaded separately by this function.
    """
    from urllib.error import HTTPError
    if not isinstance(accession, str) or not re.fullmatch(r'GSE\d+', accession):
        raise m.MetadataError('Expected GSE accession')
    if labels is not None and (not isinstance(labels, (list, tuple)) or any(not isinstance(c, str) for c in labels)):
        raise m.MetadataError('Column labels must be strings')
    group = re.sub(r'\d{1,3}$', 'nnn', accession)
    base = f'https://ftp.ncbi.nlm.nih.gov/geo/series/{group}/{accession}'
    matrix_url = f'{base}/matrix/{accession}_series_matrix.txt.gz'
    sources, warnings = [], []
    result = None
    try:
        text, source = _read_annotation_source(matrix_url, 'series_matrix')
    except HTTPError as exc:
        # Do not retry access denials, throttling or security redirects through
        # another endpoint. Only an absent default matrix warrants fallback.
        if exc.code not in {404, 410}:
            raise m.MetadataError(f'GEO series matrix unavailable (HTTP {exc.code})') from exc
        warnings.append('series_matrix_unavailable')
    except (OSError, EOFError, UnicodeError):
        warnings.append('series_matrix_unavailable_or_invalid')
    else:
        sources.append(source)
        try:
            records = parse_sample_annotations(text, accession)
        except (m.MetadataError, csv.Error):
            warnings.append('series_matrix_metadata_mismatch_or_invalid')
        else:
            result = dict(source, records=records)
            platforms = {value for row in _matrix_annotation_rows(text)
                         if row[0] == '!Series_platform_id' for value in row[1:] if value}
            platforms.update(value for record in records for value in record['platform_ids'] if value)
            if len(platforms) > 1:
                warnings.append('series_matrix_multiple_platforms')
            elif labels and any(item['status'] != 'exact' for item in match_samples(labels, records)):
                warnings.append('series_matrix_columns_not_uniquely_matched')
            else:
                result.update(sources=sources, warnings=[])
                return result
    soft_url = f'{base}/soft/{accession}_family.soft.gz'
    try:
        text, source = _read_annotation_source(soft_url, 'family_soft')
        sources.append(source)
        records = parse_family_sample_annotations(text, accession)
    except (OSError, EOFError, UnicodeError) as exc:
        if result is None:
            raise m.MetadataError('GEO sample metadata unavailable from the series matrix and bounded family SOFT') from exc
        # Retain explicitly incomplete same-series metadata; callers still see
        # unmatched columns rather than fabricated positional assignments.
        result.update(sources=sources, warnings=warnings + ['family_soft_unavailable_or_invalid'])
        return result
    if labels and any(item['status'] != 'exact' for item in match_samples(labels, records)):
        warnings.append('family_soft_columns_not_uniquely_matched')
    return dict(source, records=records, sources=sources, warnings=warnings)
