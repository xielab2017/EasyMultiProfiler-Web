#!/usr/bin/env python3
"""Loopback-only metadata sidecar and UI. No download/analysis execution endpoint."""
from __future__ import annotations
import json
import os
import re
import shutil
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
import public_data as metadata
import processed_data
import paper_sources
import workflow_plans
import agent_adapter
import agent_context

ROOT = Path(__file__).resolve().parents[2]
PREFIX = '/api/public-data/'
MAX_BODY = 16384


class Store:
    def __init__(self):
        self.lock = threading.Lock()
        self.items = {}
    def put(self, value):
        with self.lock:
            self.items = {k: v for k, v in self.items.items() if time.monotonic() - v[0] < 1800}
            if len(self.items) >= 20:
                oldest = min(self.items, key=lambda k: self.items[k][0]); del self.items[oldest]
            key = str(uuid.uuid4()); self.items[key] = (time.monotonic(), value)
            return key
    def get(self, key):
        with self.lock:
            found = self.items.get(key)
            if not found or time.monotonic() - found[0] >= 1800:
                raise metadata.MetadataError('Manifest expired or unavailable; resolve the accession again')
            return found[1]


def download_plan(value, selected, free_bytes):
    if not isinstance(selected, list) or not selected or len(selected) > metadata.MAX_RUNS or any(not isinstance(x, str) for x in selected):
        raise metadata.MetadataError('Select at least one valid run')
    if not isinstance(value, dict) or value.get('status') != 'metadata_only': raise metadata.MetadataError('A sequencing-run manifest is required')
    current = metadata.manifest(value['runs'], value['request'], value['sources'], selected)
    chosen = [r for r in current['runs'] if r['run_accession'] in current['selected_runs']]
    raw_bytes = current['selected_bytes']
    reserve = 1024 ** 3
    required = raw_bytes + reserve
    blockers = []
    if any(not r['files'] for r in chosen): blockers.append('One or more selected runs have no public FASTQ files')
    if required > free_bytes: blockers.append('Insufficient space for compressed downloads plus 1 GiB reserve')
    strategies = sorted({r['library_strategy'] for r in chosen})
    if len({r['scientific_name'] for r in chosen}) > 1: blockers.append('Mixed organisms require separate review')
    return {'schema_version': '1.0', 'status': 'review_only', 'selected_runs': current['selected_runs'],
            'archive_bytes': raw_bytes, 'free_bytes': free_bytes, 'minimum_download_space': required,
            'blockers': blockers, 'download_enabled': False, 'analysis_enabled': False,
            'confirmation_required': True, 'checksums_verified': False,
            'files': [f for r in chosen for f in r['files']],
            'analysis_handoff': {'strategies': strategies, 'status': 'not_executable',
                'required': ['Confirm organism, experimental groups and biological replicates',
                             'Choose and provision a versioned raw-read workflow and reference',
                             'Verify downloaded checksums and perform raw-read QC',
                             'Import validated count/abundance matrices or BAMs into EMP'],
                'warning': 'Download space excludes decompression, references, alignment and analysis intermediates. R backend integration is not available.'}}


def selected_context(server, ids):
    """Resolve only server-owned IDs; no client-supplied context or paths."""
    if ids is None: ids = {}
    if not isinstance(ids, dict) or set(ids) - {'manifest_id', 'plan_id', 'download_id'}:
        raise metadata.MetadataError('Unsupported context selection')
    snapshot = {}
    for kind, key in ids.items():
        if not isinstance(key, str) or not re.fullmatch(r'[a-f0-9-]{36}', key):
            raise metadata.MetadataError('Invalid context ID')
        if kind == 'manifest_id':
            record = server.store.get(key)
            if record.get('status') not in {'metadata_only', 'processed_candidates'}:
                raise metadata.MetadataError('A data manifest is required')
            snapshot['manifest'] = record
        elif kind == 'plan_id':
            record = server.store.get(key)
            if record.get('kind') != 'workflow_validation':
                raise metadata.MetadataError('A validated plan record is required')
            snapshot['plan'] = record['plan']
        else:
            record = ROOT / '.local_run/public_data' / (key + '.json')
            if not record.is_file() or record.stat().st_size > 2 * 1024 * 1024:
                raise metadata.MetadataError('Completed inspection record unavailable')
            snapshot['inspection'] = json.loads(record.read_text())
    return snapshot


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        # Do not log query strings, prompts, IDs or request bodies.
        pass
    def reply(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status); self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body))); self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff'); self.end_headers(); self.wfile.write(body)
    def valid_origin(self):
        host = self.headers.get('Host', '')
        origin = self.headers.get('Origin')
        return host in self.server.allowed_hosts and (origin is None or origin in self.server.allowed_origins)
    def do_GET(self):
        if not self.valid_origin(): return self.reply(403, {'error': 'Origin or host not allowed'})
        path = urlsplit(self.path).path
        if path.startswith(PREFIX + 'files/'):
            key = path.removeprefix(PREFIX + 'files/')
            if not re.fullmatch(r'[a-f0-9-]{36}', key): return self.reply(404, {'error': 'Invalid file ID'})
            base = ROOT / '.local_run/public_data'
            file = base / (key + '.data'); record = base / (key + '.json')
            if not file.is_file() or not record.is_file(): return self.reply(404, {'error': 'File unavailable'})
            info = json.loads(record.read_text())
            name = re.sub(r'[^A-Za-z0-9._-]', '_', info['source_name'])
            body = file.read_bytes()
            self.send_response(200); self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Disposition', f'attachment; filename="{name}"')
            self.send_header('Content-Length', str(len(body))); self.send_header('X-Content-Type-Options', 'nosniff'); self.end_headers(); self.wfile.write(body); return
        if path == PREFIX + 'agent/status': return self.reply(200, agent_adapter.status())
        if path == PREFIX + 'workflows/templates': return self.reply(200, workflow_plans.templates())
        if path == PREFIX + 'health':
            return self.reply(200, {'status': 'metadata_only', 'download_enabled': False, 'analysis_enabled': False})
        files = {'/': 'public_data.html', '/public_data.html': 'public_data.html', '/js/public_data_ui.js': 'js/public_data_ui.js'}
        if path not in files: return self.reply(404, {'error': 'Not found'})
        data = (ROOT / 'webapp/frontend' / files[path]).read_bytes()
        self.send_response(200); self.send_header('Content-Type', 'text/javascript; charset=utf-8' if path.endswith('.js') else 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(data))); self.send_header('Cache-Control', 'no-store'); self.end_headers(); self.wfile.write(data)
    def do_POST(self):
        if not self.valid_origin(): return self.reply(403, {'error': 'Origin or host not allowed'})
        if urlsplit(self.path).path == PREFIX + 'papers/pdf':
            if self.headers.get('Content-Type', '').split(';')[0] != 'application/pdf': return self.reply(415, {'error': 'PDF body required'})
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if not 0 < size <= 15 * 1024 * 1024: return self.reply(413, {'error': 'PDF must be at most 15 MiB'})
                if not self.server.pdf_slots.acquire(blocking=False): return self.reply(429, {'error': 'PDF parser busy; retry later'})
                try:
                    self.connection.settimeout(30)
                    return self.reply(200, paper_sources.extract_pdf(self.rfile.read(size)))
                finally: self.server.pdf_slots.release()
            except (ValueError, OSError) as exc: return self.reply(400, {'error': str(exc)})
        if self.headers.get('Content-Type', '').split(';')[0] != 'application/json': return self.reply(415, {'error': 'JSON required'})
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= MAX_BODY: return self.reply(413, {'error': 'Invalid request size'})
            request = json.loads(self.rfile.read(size))
            if not isinstance(request, dict): raise metadata.MetadataError('Object required')
            path = urlsplit(self.path).path
            if path == PREFIX + 'agent/context-preview':
                if set(request) - {'context_ids'}: raise metadata.MetadataError('Only context IDs are accepted')
                return self.reply(200, agent_context.prepare(selected_context(self.server, request.get('context_ids'))))
            if path == PREFIX + 'agent/respond':
                if set(request) - {'question', 'consent', 'expected_provider', 'context_ids', 'context_consent', 'context_sha256'}:
                    raise metadata.MetadataError('Unsupported agent request fields')
                if request.get('consent') is True and request.get('expected_provider') != agent_adapter.status()['provider']:
                    return self.reply(409, {'error': 'Provider changed or not confirmed; reload status and consent again'})
                context = selected_context(self.server, request.get('context_ids'))
                if context:
                    preview = agent_context.prepare(context)
                    if request.get('context_sha256') != preview['snapshot_sha256']:
                        return self.reply(409, {'error': 'Selected context changed; preview and consent again'})
                return self.reply(200, agent_adapter.respond(request.get('question', ''), request.get('consent', False),
                    context=context, context_consent=request.get('context_consent', False)))
            if path == PREFIX + 'workflows/validate':
                result = workflow_plans.validate_plan(request.get('plan'))
                if result.get('record'):
                    result['plan_id'] = self.server.store.put({'kind': 'workflow_validation', 'plan': result['record']['plan']})
                return self.reply(200, result)
            if path == PREFIX + 'papers/abstract': return self.reply(200, paper_sources.fetch_pubmed_abstract(request.get('pmid', '')))
            if path == PREFIX + 'papers/search':
                return self.reply(200, paper_sources.search_pubmed(request.get('term', ''), 10))
            if path == PREFIX + 'processed/resolve':
                result = processed_data.discover(request.get('accession', ''))
                return self.reply(200, {'manifest_id': self.server.store.put(result), 'manifest': result})
            if path == PREFIX + 'processed/download':
                key = request.get('manifest_id')
                if not isinstance(key, str): raise metadata.MetadataError('Manifest ID required')
                result = processed_data.download(self.server.store.get(key), request.get('file_id'), ROOT / '.local_run/public_data', request.get('confirmed', False))
                return self.reply(200, result)
            if path == PREFIX + 'processed/annotations':
                result = processed_data.fetch_annotations(request.get('accession', ''))
                columns = request.get('columns', [])
                if not isinstance(columns, list) or any(not isinstance(c, str) for c in columns): raise metadata.MetadataError('Column labels must be strings')
                result['matches'] = processed_data.match_samples(columns, result['records'])
                return self.reply(200, result)
            if path == PREFIX + 'resolve':
                result = metadata.resolve(self.server.client_factory(), request.get('accession', ''))
                return self.reply(200, {'manifest_id': self.server.store.put(result), 'manifest': result})
            if path == PREFIX + 'search':
                client = self.server.client_factory()
                result = metadata.geo_search(client, request.get('term', ''), 10)
                return self.reply(200, {'records': result, 'sources': client.sources})
            if path == PREFIX + 'plan':
                key = request.get('manifest_id')
                if not isinstance(key, str): raise metadata.MetadataError('Manifest ID required')
                value = self.server.store.get(key)
                result = download_plan(value, request.get('selected_runs'), shutil.disk_usage(ROOT).free)
                selected = metadata.manifest(value['runs'], value['request'], value['sources'], request.get('selected_runs'))
                result['context_manifest_id'] = self.server.store.put(selected)
                return self.reply(200, result)
            return self.reply(404, {'error': 'No such operation; download and execution are disabled'})
        except (ValueError, TypeError, AttributeError, OSError) as exc:
            return self.reply(400, {'error': str(exc), 'download_enabled': False})


def make_server(port=8081):
    server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    server.store = Store(); server.pdf_slots = threading.BoundedSemaphore(2); server.client_factory = metadata.Client
    server.allowed_hosts = {f'127.0.0.1:{server.server_port}', f'localhost:{server.server_port}'}
    gateway_port = int(os.environ.get('GATEWAY_PORT', '8090'))
    server.allowed_origins = {'http://' + h for h in server.allowed_hosts} | {f'http://127.0.0.1:{gateway_port}', f'http://localhost:{gateway_port}'}
    return server


if __name__ == '__main__':
    server = make_server(int(os.environ.get('EMP_PUBLIC_DATA_PORT', '8081')))
    print(f'Metadata-only UI: http://127.0.0.1:{server.server_port}/public_data.html', flush=True)
    server.serve_forever()
