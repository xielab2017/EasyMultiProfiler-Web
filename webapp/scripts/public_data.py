#!/usr/bin/env python3
"""Read-only public accession discovery. No FASTQ downloads or code execution.

Examples:
  python webapp/scripts/public_data.py resolve SRR390728
  python webapp/scripts/public_data.py search 'breast cancer RNA sequencing'
  python webapp/scripts/public_data.py parse-ena saved-report.tsv
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import io
import json
import re
import sys
import time
from datetime import datetime, timezone
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, build_opener, HTTPRedirectHandler

VERSION = '1.0'
MAX_BYTES = 8 * 1024 * 1024
MAX_RUNS = 10000
ACCESSION = re.compile(r'(?:GSE\d+|[SED]R[RPXS]\d+|PRJ(?:NA|EB|DB)\d+)')
RUN = re.compile(r'[SED]RR\d+')
ENA = 'https://www.ebi.ac.uk/ena/portal/api/filereport'
NCBI = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/'
FIELDS = ['run_accession', 'study_accession', 'sample_accession', 'experiment_accession',
          'scientific_name', 'library_strategy', 'library_layout', 'fastq_ftp', 'fastq_md5', 'fastq_bytes']


class MetadataError(ValueError):
    pass


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise MetadataError('Metadata redirect refused; inspect the official endpoint.')


class Client:
    """Bounded, allowlisted metadata GETs; no arbitrary user URLs."""
    def __init__(self):
        self.opener = build_opener(NoRedirect())
        self.last_ncbi = 0.0
        self.sources = []

    def get(self, base, params):
        if base not in {ENA, NCBI + 'esearch.fcgi', NCBI + 'esummary.fcgi'}:
            raise MetadataError('Unapproved metadata endpoint')
        if base.startswith(NCBI):
            time.sleep(max(0, .35 - (time.monotonic() - self.last_ncbi)))
            self.last_ncbi = time.monotonic()
        url = base + '?' + urlencode(params)
        request = Request(url, headers={'User-Agent': 'EasyMultiProfiler-PublicMetadata/1.0', 'Accept-Encoding': 'identity'})
        try:
            with self.opener.open(request, timeout=30) as response:
                data = response.read(MAX_BYTES + 1)
            if len(data) > MAX_BYTES:
                raise MetadataError('Metadata response exceeds 8 MiB; narrow the accession selection')
            text = data.decode('utf-8-sig')
        except (OSError, UnicodeError) as exc:
            raise MetadataError(f'Metadata retrieval failed: {type(exc).__name__}. Check network access and accession; no sequencing files downloaded.') from exc
        self.sources.append({'url': url, 'sha256': hashlib.sha256(data).hexdigest(),
                             'retrieved_at': datetime.now(timezone.utc).isoformat()})
        return text


def accession(value):
    value = value.strip().upper()
    if not ACCESSION.fullmatch(value):
        raise MetadataError('Expected GSE, SRA/ENA run/study/sample/experiment, or BioProject accession; not a URL or DOI')
    return value


def metadata_json(text):
    try:
        data = json.loads(text)
    except (ValueError, TypeError) as exc:
        raise MetadataError('Invalid metadata JSON') from exc
    if not isinstance(data, dict) or data.get('error'):
        raise MetadataError('Upstream returned an invalid response or error')
    return data


def geo_search(client, term, limit=10):
    if not isinstance(term, str) or not term.strip() or len(term) > 300:
        raise MetadataError('Search term must contain 1–300 characters')
    if not isinstance(limit, int) or not 1 <= limit <= 50:
        raise MetadataError('Search limit must be 1–50')
    data = metadata_json(client.get(NCBI + 'esearch.fcgi', {'db': 'gds', 'term': term, 'retmode': 'json', 'retmax': limit}))
    search = data.get('esearchresult')
    if not isinstance(search, dict) or search.get('ERROR') or search.get('errorlist') or 'idlist' not in search:
        raise MetadataError('Invalid GEO search response or upstream search error')
    ids = search['idlist']
    if not isinstance(ids, list) or any(not str(i).isdigit() for i in ids) or len(ids) > limit:
        raise MetadataError('Invalid GEO search IDs')
    if not ids:
        return []
    summary = metadata_json(client.get(NCBI + 'esummary.fcgi', {'db': 'gds', 'id': ','.join(ids), 'retmode': 'json'}))
    result = summary.get('result')
    if not isinstance(result, dict):
        raise MetadataError('Invalid GEO summary response')
    records = []
    for uid in ids:
        row = result.get(str(uid))
        if not isinstance(row, dict) or row.get('error'):
            raise MetadataError('Missing GEO summary record')
        relations = row.get('extrelations', [])
        if not isinstance(row.get('accession', ''), str) or not isinstance(relations, list) or any(not isinstance(r, dict) for r in relations):
            raise MetadataError('Malformed GEO accession or relations')
        records.append({'uid': str(uid), 'accession': row.get('accession', ''), 'title': row.get('title', ''),
                        'summary': row.get('summary', ''), 'taxon': row.get('taxon', ''),
                        'sample_count': row.get('n_samples'), 'relations': row.get('extrelations', [])})
    return records


def geo_targets(records, requested):
    # Never resolve a fuzzy search match or an arbitrary URL supplied in metadata.
    exact = [r for r in records if r['accession'].upper() == requested]
    if not exact:
        raise MetadataError('Exact GEO series was not found; no accession mapping inferred')
    targets = set()
    for row in exact:
        for rel in row.get('relations', []):
            value = str(rel.get('targetobject', '')).upper()
            if str(rel.get('relationtype', '')).upper() in {'SRA', 'BIOPROJECT'} and ACCESSION.fullmatch(value) and not value.startswith('GSE'):
                targets.add(value)
    return sorted(targets)


def safe_fastq_url(value):
    value = value.strip()
    url = value if '://' in value else 'https://' + value
    try:
        parsed = urlsplit(url)
        port = parsed.port
    except ValueError as exc:
        raise MetadataError('Malformed FASTQ URL') from exc
    if parsed.scheme not in {'https', 'ftp'} or parsed.hostname != 'ftp.sra.ebi.ac.uk' or parsed.username or parsed.password or port or parsed.query or parsed.fragment:
        raise MetadataError('FASTQ metadata contains an unapproved download location')
    if '%' in parsed.path or '\\' in parsed.path or not parsed.path.startswith('/vol1/fastq/') or '..' in parsed.path.split('/') or not parsed.path.endswith(('.fastq.gz', '.fq.gz')):
        raise MetadataError('Unexpected FASTQ archive path')
    return 'https://ftp.sra.ebi.ac.uk' + parsed.path


def parse_ena(text):
    if len(text.encode('utf-8')) > MAX_BYTES:
        raise MetadataError('Metadata exceeds 8 MiB')
    reader = csv.DictReader(io.StringIO(text), delimiter='\t')
    if not reader.fieldnames or not set(FIELDS).issubset(reader.fieldnames):
        raise MetadataError('ENA report is missing required columns')
    runs, seen = [], set()
    for row in reader:
        if len(runs) >= MAX_RUNS:
            raise MetadataError('Too many runs; select a narrower accession')
        run = row.get('run_accession', '')
        if not RUN.fullmatch(run) or run in seen or None in row or any(row.get(k) is None for k in FIELDS):
            raise MetadataError('Invalid, duplicate, or malformed run record')
        seen.add(run)
        columns = [row[k].split(';') if row[k] else [] for k in ('fastq_ftp', 'fastq_md5', 'fastq_bytes')]
        if len({len(v) for v in columns}) != 1:
            raise MetadataError(f'{run}: FASTQ URL/checksum/size counts differ')
        files = []
        for path, md5, size in zip(*columns):
            if not re.fullmatch(r'[a-fA-F0-9]{32}', md5) or not re.fullmatch(r'\d{1,20}', size) or int(size) <= 0:
                raise MetadataError(f'{run}: invalid checksum or byte size')
            files.append({'url': safe_fastq_url(path), 'md5': md5.lower(), 'bytes': int(size), 'downloaded': False})
        runs.append({k: row[k] for k in FIELDS if not k.startswith('fastq_')} | {
            'files': files, 'availability': 'public_fastq_metadata' if files else 'no_public_fastq_links',
            'warnings': [] if files else ['No public FASTQ links returned; this does not prove controlled access or absence of raw data.']})
    return runs


def manifest(runs, requested, sources=(), selected=None):
    by_id = {r['run_accession']: r for r in runs}
    if len(by_id) != len(runs):
        raise MetadataError('Duplicate runs across source reports; review accession overlap')
    chosen = list(dict.fromkeys(selected or []))
    if any(r not in by_id for r in chosen):
        raise MetadataError('Selected run does not exist in the retrieved manifest')
    return {'schema_version': VERSION, 'request': requested, 'status': 'metadata_only',
            'sources': list(sources), 'runs': runs, 'selected_runs': chosen,
            'selected_bytes': sum(f['bytes'] for r in chosen for f in by_id[r]['files']),
            'download_enabled': False, 'analysis_executed': False,
            'notes': ['Selection is not execution approval.', 'Review organism, assay, layout and experimental groups before analysis.',
                      'DOI/PMID resolution and raw-read processing are not implemented.']}


def resolve(client, value, selected=None):
    value = accession(value)
    targets = [value]
    geo = []
    if value.startswith('GSE'):
        geo = geo_search(client, value + '[ACCN]', 10)
        targets = geo_targets(geo, value)
    by_run = {}
    for target in targets:
        rows = parse_ena(client.get(ENA, {'accession': target, 'result': 'read_run', 'fields': ','.join(FIELDS), 'format': 'tsv'}))
        for row in rows:
            key = row['run_accession']
            if key in by_run and by_run[key] != row:
                raise MetadataError('Conflicting run metadata across source reports')
            by_run[key] = row
        if len(by_run) > MAX_RUNS:
            raise MetadataError('Too many combined runs; select a narrower accession')
    runs = list(by_run.values())
    result = manifest(runs, value, client.sources, selected)
    result['geo_records'] = geo
    if not runs:
        result['notes'].append('No runs resolved. Do not interpret this as evidence that no sequencing data exist.')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('resolve'); p.add_argument('accession'); p.add_argument('--select', action='append', default=[])
    p = sub.add_parser('search'); p.add_argument('term'); p.add_argument('--limit', type=int, default=10)
    p = sub.add_parser('parse-ena'); p.add_argument('file'); p.add_argument('--select', action='append', default=[])
    args = parser.parse_args()
    try:
        client = Client()
        if args.command == 'resolve':
            result = resolve(client, args.accession, args.select)
        elif args.command == 'search':
            result = {'records': geo_search(client, args.term, args.limit), 'sources': client.sources, 'status': 'metadata_only'}
        else:
            with open(args.file, encoding='utf-8-sig') as handle:
                text = handle.read(MAX_BYTES + 1)
            result = manifest(parse_ena(text), 'local_ena_report', selected=args.select)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except (MetadataError, OSError) as exc:
        print(json.dumps({'success': False, 'error': str(exc), 'download_enabled': False}), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
