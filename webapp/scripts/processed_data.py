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
        for item in result['files'][:10]:
            try:
                with opener.open(Request(item['url'], method='HEAD'), timeout=5) as response:
                    size = response.headers.get('Content-Length', '')
                    if size.isdigit(): item['bytes'] = int(size)
            except OSError:
                item['size_status'] = 'unavailable'
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


def parse_sample_annotations(text):
    rows = list(csv.reader(io.StringIO(text), delimiter='\t'))
    selected = [r for r in rows if r and r[0].startswith('!Sample_')]
    ids = next((r[1:] for r in selected if r[0] == '!Sample_geo_accession'), [])
    if not ids or len(set(ids)) != len(ids): raise m.MetadataError('Missing or duplicate GEO sample accessions')
    records = [{'accession': key, 'descriptions': [], 'characteristics': []} for key in ids]
    for row in selected:
        if len(row) != len(ids) + 1: continue
        for index, value in enumerate(row[1:]):
            if row[0] == '!Sample_title': records[index]['title'] = value
            if row[0] == '!Sample_description': records[index]['descriptions'].append(value)
            if row[0].startswith('!Sample_characteristics'): records[index]['characteristics'].append(value)
    return records


def match_samples(labels, records):
    matches = []
    for label in labels:
        candidates = [r for r in records if label == r['accession'] or label in r['descriptions']]
        matches.append({'column': label, 'status': 'exact' if len(candidates) == 1 else 'unmatched_or_ambiguous',
                        'sample': candidates[0] if len(candidates) == 1 else None})
    return matches


def fetch_annotations(accession):
    if not re.fullmatch(r'GSE\d+', accession): raise m.MetadataError('Expected GSE accession')
    group = re.sub(r'\d{1,3}$', 'nnn', accession)
    url = f'https://ftp.ncbi.nlm.nih.gov/geo/series/{group}/{accession}/matrix/{accession}_series_matrix.txt.gz'
    with build_opener(m.NoRedirect()).open(url, timeout=20) as response:
        data = response.read(2 * 1024 * 1024 + 1)
    if len(data) > 2 * 1024 * 1024: raise m.MetadataError('Annotation download exceeds 2 MiB; explicit selection needed')
    with gzip.GzipFile(fileobj=io.BytesIO(data)) as handle: unpacked = handle.read(MAX_UNCOMPRESSED + 1)
    if len(unpacked) > MAX_UNCOMPRESSED: raise m.MetadataError('Expanded annotation exceeds limit')
    return {'records': parse_sample_annotations(unpacked.decode('utf-8-sig')),
            'source_url': url, 'sha256': hashlib.sha256(data).hexdigest()}
