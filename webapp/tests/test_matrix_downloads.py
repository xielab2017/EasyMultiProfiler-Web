"""Offline unit/security tests plus real loopback HTTP streaming fixtures.

No external data downloads. The fixture opener maps a validated official GEO
URL to an in-process HTTP server while preserving the original response URL.
"""
import hashlib
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import multiprocessing
import os
from pathlib import Path
import sys
import tempfile
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import matrix_downloads as md

BASE = 'https://ftp.ncbi.nlm.nih.gov/geo/series/GSE60nnn/GSE60450/suppl/'
BODY = b'0123456789abcdefghijklmnopqrstuvwxyzABCD'


def manifest(name='counts.h5ad', size=len(BODY), checksum=None):
    return {'status': 'processed_candidates', 'accession': 'GSE60450',
            'files': [{'id': '0', 'name': name, 'url': BASE + name,
                       'bytes': size, 'checksum': checksum, 'format_hint': 'other'}]}


class FixtureResponse:
    def __init__(self, connection, response, url):
        self.connection, self.response, self.url = connection, response, url
        self.status, self.headers = response.status, response.headers

    def read(self, count):
        return self.response.read(count)

    def read1(self, count):
        return self.response.read1(count)

    def geturl(self):
        return self.url

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.response.close(); self.connection.close()


class FixtureOpener:
    def __init__(self, server):
        self.server = server

    def open(self, request, timeout):
        # All production URL checks stay intact; only transport is replaced.
        if not request.full_url.startswith(BASE):
            raise AssertionError('Fixture unexpectedly received a non-GEO source')
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=timeout)
        connection.request(request.get_method(), '/fixture', headers=dict(request.header_items()))
        return FixtureResponse(connection, connection.getresponse(), request.full_url)


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    def do_GET(self):
        self.server.requests.append({key.lower(): value for key, value in self.headers.items()})
        status, headers, body, gate = self.server.respond(self.headers)
        self.send_response(status)
        for key, value in headers.items():
            self.send_header(key, value)
        self.send_header('Connection', 'close'); self.end_headers()
        try:
            if gate:
                self.wfile.write(body[:4]); self.wfile.flush()
                self.server.first_chunk.set()
                gate.wait(5)
                self.wfile.write(body[4:])
            else:
                self.wfile.write(body)
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        self.close_connection = True


def lock_probe(root, result):
    try:
        lease = md._Lease(Path(root)); lease.close(); result.put('acquired')
    except md.DownloadError:
        result.put('blocked')


class MatrixDownloadTests(unittest.TestCase):
    def test_pride_managed_download_is_bound_to_its_official_project(self):
        source={'status':'processed_candidates','accession':'PXD067973','files':[{'id':'0','name':'report.pg_matrix.tsv','url':'https://ftp.pride.ebi.ac.uk/pride/data/archive/2025/08/PXD067973/report.pg_matrix.tsv','bytes':40,'checksum':None}]}
        plan=self.manager.plan(source,'0');self.assertEqual(plan['status'],'ready_for_confirmation')
        for url in ['https://evil.test/pride/data/archive/PXD067973/report.pg_matrix.tsv','https://ftp.pride.ebi.ac.uk/pride/data/archive/PXD000001/report.pg_matrix.tsv','https://ftp.pride.ebi.ac.uk/pride/data/archive/PXD067973/../report.pg_matrix.tsv']:
            data=json.loads(json.dumps(source));data['files'][0]['url']=url
            with self.assertRaises(md.DownloadError):self.manager.plan(data,'0')
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=Path(tempfile.gettempdir()).resolve())
        self.root = Path(self.temp.name) / 'downloads'
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.server.daemon_threads = True
        self.server.requests = []
        self.server.first_chunk = threading.Event()
        self.server.respond = lambda headers: (200, {'Content-Length': str(len(BODY)), 'ETag': '"one"'}, BODY, None)
        self.server_thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.server_thread.start()
        self.free = 200 * md.GIB
        self.manager = self.new_manager()

    def new_manager(self, **kwargs):
        return md.MatrixDownloadManager(self.root, limits=md.Limits(chunk_bytes=4, timeout_seconds=2),
                                        opener=FixtureOpener(self.server),
                                        disk_usage=lambda _: SimpleNamespace(free=self.free), **kwargs)

    def tearDown(self):
        for key, thread in self.manager._threads.items():
            if thread.is_alive():
                self.manager.cancel(key); thread.join(3)
        self.server.shutdown(); self.server.server_close(); self.server_thread.join(3)
        self.temp.cleanup()

    def plan(self, **kwargs):
        return self.manager.plan(manifest(**kwargs), '0')

    def start(self, plan=None):
        plan = plan or self.plan()
        return self.manager.start(plan, confirmed=True, plan_sha256=plan['plan_sha256'])

    def finish(self, plan=None):
        job = self.start(plan)
        return self.manager.wait(job['job_id'], 5)

    def interrupted(self, *, headers=None, name='counts.h5ad'):
        response_headers = {'Content-Length': str(len(BODY)), 'ETag': '"one"'}
        if headers is not None:
            response_headers = headers
        self.server.respond = lambda h: (200, response_headers, BODY[:8], None)
        job = self.finish(self.plan(name=name))
        self.assertEqual(job['status'], 'failed', job)
        self.assertEqual(job['bytes_downloaded'], 8)
        return job

    def resume_response(self, headers, *, status=206, total=None, start=None, etag='"one"', extra=None):
        offset = int(headers['Range'].split('=')[1].split('-')[0])
        size = len(BODY) if total is None else total
        begin = offset if start is None else start
        result_headers = {'Content-Length': str(len(BODY) - offset),
                          'Content-Range': f'bytes {begin}-{size - 1}/{size}', 'ETag': etag}
        if extra:
            result_headers.update(extra)
        return status, result_headers, BODY[offset:], None

    def resume(self, job):
        self.manager.resume(job['job_id'], confirmed=True, plan_sha256=job['plan_sha256'])
        return self.manager.wait(job['job_id'], 5)

    def test_formats_and_large_known_sizes_are_not_old_32mib_limited(self):
        for name in ['counts.h5ad', 'matrix.mtx.gz', 'data.zip', 'GSE60450_RAW.tar', 'counts.loom', 'original.rds']:
            with self.subTest(name=name):
                plan = self.plan(name=name, size=48 * 1024 ** 2)
                self.assertEqual(plan['status'], 'ready_for_confirmation')
                self.assertEqual(plan['max_bytes'], 5 * md.GIB)
        self.assertTrue(any('contents are unknown' in w for w in self.plan(name='GSE60450_RAW.tar')['warnings']))
        self.assertEqual(self.server.requests, [])

    def test_unknown_size_requires_explicit_budget(self):
        with self.assertRaises(md.DownloadError): self.plan(size=None)
        plan = self.manager.plan(manifest(size=None), '0', max_bytes=64)
        self.assertEqual(plan['max_bytes'], 64)
        self.assertIsNone(plan['bytes'])
        self.assertEqual(self.finish(plan)['status'], 'completed')

    def test_unknown_size_without_content_length_streams_under_cap(self):
        self.server.respond = lambda h: (200, {'ETag': '"one"'}, BODY, None)
        plan = self.manager.plan(manifest(size=None), '0', max_bytes=64)
        result = self.finish(plan)
        self.assertEqual(result['total_bytes'], len(BODY))
        self.assertEqual(result['status'], 'completed')

    def test_unknown_size_budget_overflow_retains_bounded_partial(self):
        self.server.respond = lambda h: (200, {'ETag': '"one"'}, BODY, None)
        plan = self.manager.plan(manifest(size=None), '0', max_bytes=12)
        result = self.finish(plan)
        self.assertEqual(result['status'], 'failed')
        self.assertEqual(result['bytes_downloaded'], 12)
        self.assertEqual((self.root / result['job_id'] / (result['job_id'] + '.part')).read_bytes(), BODY[:12])

    def test_caps_sizes_and_disk(self):
        for cap in [True, 0, -1, 100 * md.GIB + 1, '100']:
            with self.subTest(cap=cap), self.assertRaises(md.DownloadError):
                self.manager.plan(manifest(), '0', cap)
        self.assertEqual(self.manager.plan(manifest(size=6 * md.GIB), '0')['status'], 'blocked')
        self.assertEqual(self.manager.plan(manifest(size=6 * md.GIB), '0', 6 * md.GIB)['status'], 'ready_for_confirmation')
        self.free = md.GIB
        self.assertEqual(self.plan()['status'], 'blocked')
        for size in [0, -1, True, '40']:
            with self.subTest(size=size), self.assertRaises(md.DownloadError): self.plan(size=size)

    def test_direct_reads_rejected_but_raw_named_archive_not_assumed_reads(self):
        for name in ['reads.fastq.gz', 'reads.FQ', 'reads.sra', 'alignments.bam', 'x.cram.zip', 'reads.fastq.tar']:
            with self.subTest(name=name), self.assertRaises(md.DownloadError): self.plan(name=name)
        self.assertEqual(self.plan(name='GSE60450_RAW.tar')['status'], 'ready_for_confirmation')

    def test_unsafe_sources_and_names_rejected(self):
        urls = ['https://evil.test/geo/series/GSE60nnn/GSE60450/suppl/x',
                BASE.replace('https:', 'http:') + 'x', BASE + '../x', BASE + '%2e%2e/x',
                BASE + 'x?token=secret', BASE + 'x#fragment', BASE + 'x%0Afoo', BASE + 'x%252fsecret',
                BASE.replace('ftp.ncbi.nlm.nih.gov', 'user:pass@ftp.ncbi.nlm.nih.gov') + 'x',
                BASE.replace('GSE60450/suppl', 'GSE60451/suppl') + 'x']
        for url in urls:
            data = manifest(); data['files'][0]['url'] = url
            with self.subTest(url=url), self.assertRaises(md.DownloadError): self.manager.plan(data, '0')
        data = manifest(); data['files'][0]['name'] = '../../target'
        with self.assertRaises(md.DownloadError): self.manager.plan(data, '0')

    def test_duplicate_selection_bad_manifest_and_empty_selection(self):
        data = manifest(); data['files'].append(dict(data['files'][0]))
        for data, key in [(data, '0'), (manifest(), 'unknown'), ({}, '0'), (manifest(), None)]:
            with self.assertRaises(md.DownloadError): self.manager.plan(data, key)

    def test_exact_consent_expiry_mutation_and_idempotent_start(self):
        plan = self.plan()
        for args in [{}, {'confirmed': True}, {'confirmed': 1, 'plan_sha256': plan['plan_sha256']}, {'confirmed': True, 'plan_sha256': '0' * 64}]:
            with self.assertRaises(md.DownloadError): self.manager.start(plan, **args)
        changed = dict(plan, max_bytes=123)
        with self.assertRaises(md.DownloadError): self.start(changed)
        result = self.finish(plan)
        self.assertEqual(self.start(plan)['job_id'], result['job_id'])
        self.assertEqual(len(self.server.requests), 1)
        other = self.plan()
        self.manager._plans[other['plan_id']] = (time.monotonic() - 1801, other)
        with self.assertRaises(md.DownloadError): self.start(other)

    def test_complete_stream_receipt_private_permissions_and_read_api(self):
        result = self.finish()
        self.assertEqual(result['status'], 'completed', result)
        self.assertEqual(result['sha256'], hashlib.sha256(BODY).hexdigest())
        self.assertFalse(result['publisher_checksum_verified'])
        self.assertFalse(result['receipt']['archive_extracted'])
        handle, receipt = self.manager.open_completed(result['job_id'])
        with handle: self.assertEqual(handle.read(), BODY)
        self.assertEqual(receipt['source_name'], 'counts.h5ad')
        for path in (self.root / result['job_id']).iterdir():
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        other = self.new_manager()
        self.assertEqual(other.get(result['job_id'])['status'], 'completed')
        with other.open_completed(result['job_id'])[0] as handle: self.assertEqual(handle.read(), BODY)

    def test_publisher_checksums_honest_and_mismatch_not_complete(self):
        for algorithm in ['sha256', 'md5']:
            checksum = {'algorithm': algorithm, 'value': hashlib.new(algorithm, BODY).hexdigest()}
            result = self.finish(self.plan(checksum=checksum))
            self.assertEqual(result['status'], 'completed')
            self.assertTrue(result['publisher_checksum_verified'])
        bad = self.finish(self.plan(checksum={'algorithm': 'sha256', 'value': '0' * 64}))
        self.assertEqual(bad['status'], 'failed')
        with self.assertRaises(md.DownloadError): self.manager.open_completed(bad['job_id'])
        with self.assertRaises(md.DownloadError): self.plan(checksum='unverified')

    def test_response_status_encoding_redirect_and_length_fail_closed(self):
        for status, headers in [(302, {'Location': 'https://evil.test/'}),
                                (206, {'Content-Range': 'bytes 0-39/40'}),
                                (200, {'Content-Encoding': 'gzip'}),
                                (200, {'Content-Length': '1000'}),
                                (200, {'Content-Length': 'invalid'})]:
            self.server.respond = lambda h, s=status, x=headers: (s, x, BODY, None)
            result = self.finish()
            self.assertEqual(result['status'], 'failed', (status, headers, result))
            self.assertEqual(result['bytes_downloaded'], 0)
        self.assertEqual(len(self.server.requests), 5)
        with self.assertRaises(md.DownloadError): md.NoRedirect().redirect_request(None, None, None, None, None, None)

    def test_truncated_transfer_resumes_exact_range_and_sha(self):
        job = self.interrupted()
        self.assertTrue(job['resume_supported'])
        self.server.respond = self.resume_response
        result = self.resume(job)
        self.assertEqual(result['status'], 'completed', result)
        self.assertEqual(result['sha256'], hashlib.sha256(BODY).hexdigest())
        self.assertEqual(self.server.requests[-1]['range'], 'bytes=8-')
        self.assertEqual(self.server.requests[-1]['if-range'], '"one"')

    def test_resume_after_process_restart_requires_new_exact_confirmation(self):
        job = self.interrupted()
        self.manager = self.new_manager()
        with self.assertRaises(md.DownloadError): self.manager.resume(job['job_id'])
        self.server.respond = self.resume_response
        self.assertEqual(self.resume(job)['status'], 'completed')

    def test_cancel_keeps_partial_and_explicit_resume(self):
        gate = threading.Event()
        self.server.respond = lambda h: (200, {'Content-Length': str(len(BODY)), 'ETag': '"one"'}, BODY, gate)
        job = self.start()
        self.assertTrue(self.server.first_chunk.wait(2))
        deadline = time.monotonic() + 2
        while self.manager.get(job['job_id'])['bytes_downloaded'] < 4 and time.monotonic() < deadline:
            time.sleep(.01)
        self.manager.cancel(job['job_id']); gate.set()
        stopped = self.manager.wait(job['job_id'], 3)
        self.assertEqual(stopped['status'], 'cancelled')
        self.assertEqual(stopped['bytes_downloaded'], 4)
        self.assertTrue((self.root / job['job_id'] / (job['job_id'] + '.part')).exists())
        self.server.respond = self.resume_response
        self.assertEqual(self.resume(stopped)['status'], 'completed')

    def full_checkpoint_cancelled(self):
        original_update = self.manager._update
        def cancel_at_full_checkpoint(key, **changes):
            original_update(key, **changes)
            if changes.get('bytes_downloaded') == len(BODY):
                self.manager.cancel(key)
        self.manager._update = cancel_at_full_checkpoint
        try:
            job = self.finish()
        finally:
            self.manager._update = original_update
        self.assertEqual(job['status'], 'cancelled')
        self.assertEqual(job['bytes_downloaded'], len(BODY))
        self.assertEqual(job['total_bytes'], len(BODY))
        return job

    def assert_full_partial_resume_refused(self, manager, job):
        self.assertFalse(job['resume_supported'])
        self.assertIn('Create a new explicitly confirmed download plan', job['error'])
        folder = self.root / job['job_id']
        partial = folder / (job['job_id'] + '.part')
        before_requests, before_attempts = len(self.server.requests), job['attempts']
        marker = (folder / 'cancel.request').read_bytes()
        with self.assertRaisesRegex(md.DownloadError, 'Create a new explicitly confirmed download plan'):
            manager.resume(job['job_id'], confirmed=True, plan_sha256=job['plan_sha256'])
        self.assertEqual(len(self.server.requests), before_requests)
        self.assertEqual(manager.get(job['job_id'])['attempts'], before_attempts)
        self.assertEqual(partial.read_bytes(), BODY)
        self.assertEqual((folder / 'cancel.request').read_bytes(), marker)
        self.assertFalse((folder / (job['job_id'] + '.data')).exists())

    def test_full_size_cancel_checkpoint_is_not_resumable_before_or_after_restart(self):
        job = self.full_checkpoint_cancelled()
        self.assert_full_partial_resume_refused(self.manager, job)
        record = json.loads((self.root / job['job_id'] / 'job.json').read_bytes())
        self.assertFalse(record['resume_supported'])
        other = self.new_manager()
        self.assert_full_partial_resume_refused(other, other.get(job['job_id']))

    def test_full_size_running_and_legacy_terminal_records_are_not_resumable(self):
        job = self.full_checkpoint_cancelled()
        record = self.root / job['job_id'] / 'job.json'
        for status in ['running', 'cancelled', 'failed', 'interrupted']:
            with self.subTest(status=status):
                value = json.loads(record.read_bytes())
                value.update(status=status, resume_supported=True, error=None)
                md._write_json(record, value)
                before = len(self.server.requests)
                other = self.new_manager()
                recovered = other.get(job['job_id'])
                self.assertEqual(recovered['status'], 'interrupted' if status == 'running' else status)
                self.assert_full_partial_resume_refused(other, recovered)
                self.assertEqual(len(self.server.requests), before)

    def test_one_active_across_managers_and_processes(self):
        gate = threading.Event()
        self.server.respond = lambda h: (200, {'Content-Length': str(len(BODY)), 'ETag': '"one"'}, BODY, gate)
        job = self.start(); self.assertTrue(self.server.first_chunk.wait(2))
        with self.assertRaises(md.DownloadError): self.start(self.plan())
        other = self.new_manager(); other_plan = other.plan(manifest(), '0')
        with self.assertRaises(md.DownloadError): other.start(other_plan, True, other_plan['plan_sha256'])
        context = multiprocessing.get_context('spawn')
        result = context.Queue(); process = context.Process(target=lock_probe, args=(str(self.root), result))
        process.start(); process.join(4)
        self.assertEqual(process.exitcode, 0)
        self.assertEqual(result.get(timeout=2), 'blocked')
        self.assertEqual(other.get(job['job_id'])['status'], 'running')
        self.manager.cancel(job['job_id']); gate.set(); self.manager.wait(job['job_id'], 3)

    def test_resume_200_changed_validator_wrong_range_or_size_never_appends(self):
        cases = [{'status': 200}, {'etag': '"changed"'}, {'start': 0}, {'total': len(BODY) + 1},
                 {'extra': {'Content-Range': 'bytes 8-39/*'}}, {'extra': {'Content-Length': '1'}}]
        for case in cases:
            with self.subTest(case=case):
                job = self.interrupted()
                self.server.respond = lambda h, args=case: self.resume_response(h, **args)
                result = self.resume(job)
                self.assertEqual(result['status'], 'failed', result)
                partial = self.root / job['job_id'] / (job['job_id'] + '.part')
                self.assertEqual(partial.read_bytes(), BODY[:8])
                self.assertEqual(result['bytes_downloaded'], 8)

    def test_resume_last_modified_and_weak_etag_rules(self):
        modified = 'Wed, 21 Oct 2015 07:28:00 GMT'
        job = self.interrupted(headers={'Content-Length': str(len(BODY)), 'ETag': 'W/"one"', 'Last-Modified': modified})
        self.server.respond = lambda h: self.resume_response(h, extra={'Last-Modified': modified})
        self.assertEqual(self.resume(job)['status'], 'completed')
        self.assertEqual(self.server.requests[-1]['if-range'], modified)
        job = self.interrupted(headers={'Content-Length': str(len(BODY)), 'ETag': 'W/"one"'})
        self.assertFalse(job['resume_supported'])
        with self.assertRaises(md.DownloadError): self.resume(job)

    def test_changed_partial_hash_and_length_never_appends(self):
        for content in [b'xxxxxxxx', b'x']:
            job = self.interrupted()
            partial = self.root / job['job_id'] / (job['job_id'] + '.part')
            partial.write_bytes(content)
            before = len(self.server.requests)
            if len(content) == 8:
                self.assertEqual(self.resume(job)['status'], 'failed')
            else:
                with self.assertRaises(md.DownloadError): self.resume(job)
            self.assertEqual(len(self.server.requests), before)
            self.assertEqual(partial.read_bytes(), content)

    def test_links_and_path_ids_are_rejected(self):
        for key in ['../escape', 'x', '/tmp/escape']:
            with self.assertRaises(md.DownloadError): self.manager.get(key)
        target = Path(self.temp.name) / 'target'; target.mkdir()
        link = Path(self.temp.name) / 'symlink'; link.symlink_to(target, target_is_directory=True)
        with self.assertRaises(md.DownloadError): md.MatrixDownloadManager(link)
        result = self.finish()
        artifact = self.root / result['job_id'] / (result['job_id'] + '.data')
        extra = Path(self.temp.name) / 'hardlink'; os.link(artifact, extra)
        with self.assertRaises(md.DownloadError): self.manager.open_completed(result['job_id'])
        extra.unlink(); artifact.unlink(); artifact.symlink_to(target)
        with self.assertRaises(md.DownloadError): self.manager.open_completed(result['job_id'])

    def test_ctime_only_change_rehashes_same_payload_and_rewinds_without_download(self):
        result = self.finish()
        artifact = self.root / result['job_id'] / (result['job_id'] + '.data')
        before = md._fingerprint(artifact.stat())
        time.sleep(.002)
        os.chmod(artifact, 0o600)
        after = md._fingerprint(artifact.stat())
        self.assertNotEqual(after['ctime_ns'], before['ctime_ns'])
        self.assertEqual({k: v for k, v in after.items() if k != 'ctime_ns'},
                         {k: v for k, v in before.items() if k != 'ctime_ns'})
        requests = len(self.server.requests)
        for manager in [self.manager, self.new_manager()]:
            handle, receipt = manager.open_completed(result['job_id'])
            with handle:
                self.assertEqual(handle.tell(), 0)
                self.assertEqual(handle.read(), BODY)
            self.assertEqual(receipt['sha256'], hashlib.sha256(BODY).hexdigest())
        self.assertEqual(len(self.server.requests), requests)

    def test_ctime_change_during_rehash_refuses_unstable_descriptor(self):
        result = self.finish()
        artifact = self.root / result['job_id'] / (result['job_id'] + '.data')
        time.sleep(.002); os.chmod(artifact, 0o600)
        original_open = md._open
        opened, read_sizes = [], []
        class MutatingReader:
            def __init__(self, handle):
                self.handle, self.changed = handle, False
            def __getattr__(self, name):
                return getattr(self.handle, name)
            def read(self, count):
                read_sizes.append(count)
                block = self.handle.read(count)
                if not self.changed:
                    self.changed = True
                    time.sleep(.002); os.chmod(artifact, 0o600)
                return block
        def guarded_open(path, *args, **kwargs):
            handle = original_open(path, *args, **kwargs)
            if path == artifact:
                opened.append(handle)
                return MutatingReader(handle)
            return handle
        with patch.object(md, '_open', guarded_open):
            with self.assertRaisesRegex(md.DownloadError, 'changed during verification'):
                self.manager.open_completed(result['job_id'])
        self.assertEqual(len(opened), 1)
        self.assertTrue(opened[0].closed)
        self.assertTrue(read_sizes)
        self.assertTrue(all(0 < count <= self.manager.limits.chunk_bytes for count in read_sizes))

    def test_ctime_rehash_does_not_hold_manager_lock(self):
        result = self.finish()
        artifact = self.root / result['job_id'] / (result['job_id'] + '.data')
        time.sleep(.002); os.chmod(artifact, 0o600)
        original_open = md._open
        entered, release, status_done = threading.Event(), threading.Event(), threading.Event()
        outcomes = []
        class PausingReader:
            def __init__(self, handle): self.handle = handle
            def __getattr__(self, name): return getattr(self.handle, name)
            def read(self, count=-1):
                entered.set(); release.wait(3)
                return self.handle.read(count)
        def pausing_open(path, *args, **kwargs):
            handle = original_open(path, *args, **kwargs)
            return PausingReader(handle) if path == artifact else handle
        def retrieve():
            try:
                handle, _ = self.manager.open_completed(result['job_id'])
                try: outcomes.append(handle.read())
                finally: handle.close()
            except Exception as exc: outcomes.append(exc)
        def status():
            self.manager.get(result['job_id']); self.manager.cancel(result['job_id'])
            status_done.set()
        with patch.object(md, '_open', pausing_open):
            worker = threading.Thread(target=retrieve); worker.start()
            self.assertTrue(entered.wait(2))
            status_worker = threading.Thread(target=status); status_worker.start()
            try:
                responsive = status_done.wait(1)
            finally:
                release.set(); worker.join(3); status_worker.join(3)
        self.assertTrue(responsive, 'Status/cancel blocked behind completed-file hashing')
        self.assertEqual(outcomes, [BODY])

    def test_same_size_completed_mutation_is_not_served_with_old_checksum(self):
        result = self.finish()
        artifact = self.root / result['job_id'] / (result['job_id'] + '.data')
        old = artifact.stat()
        artifact.write_bytes(b'x' * len(BODY))
        os.utime(artifact, ns=(old.st_atime_ns, old.st_mtime_ns))
        with self.assertRaises(md.DownloadError): self.manager.open_completed(result['job_id'])
        other = self.new_manager()
        with self.assertRaises(md.DownloadError): other.open_completed(result['job_id'])

    def test_interrupted_record_recovers_without_network_or_automatic_resume(self):
        job = self.interrupted()
        record = self.root / job['job_id'] / 'job.json'
        value = json.loads(record.read_bytes()); value['status'] = 'running'
        md._write_json(record, value)
        before = len(self.server.requests)
        other = self.new_manager()
        recovered = other.get(job['job_id'])
        self.assertEqual(recovered['status'], 'interrupted')
        self.assertTrue(recovered['resume_supported'])
        self.assertEqual(len(self.server.requests), before)
        self.server.respond = self.resume_response
        self.manager = other
        self.assertEqual(self.resume(recovered)['status'], 'completed')

    def test_start_rechecks_disk_and_root_permissions(self):
        plan = self.plan(); self.free = md.GIB
        with self.assertRaises(md.DownloadError): self.start(plan)
        self.assertEqual(self.server.requests, [])
        if os.name != 'nt':
            public_root = Path(self.temp.name) / 'public'
            public_root.mkdir(mode=0o755)
            with self.assertRaises(md.DownloadError): md.MatrixDownloadManager(public_root)

    def test_live_space_drop_stops_and_keeps_reserve(self):
        original = self.manager._disk_usage
        calls = [0]
        def space(path):
            calls[0] += 1
            return SimpleNamespace(free=md.GIB if calls[0] >= 5 else 200 * md.GIB)
        self.manager._disk_usage = space
        result = self.finish()
        self.assertEqual(result['status'], 'failed')
        self.assertLess(result['bytes_downloaded'], len(BODY))
        self.assertIn('disk space', result['error'])
        self.manager._disk_usage = original

    def test_limits_and_deadline_bound(self):
        for kwargs in [{'reserve_bytes': 0}, {'max_file_bytes': 101 * md.GIB}, {'chunk_bytes': 9 * 1024 ** 2}, {'timeout_seconds': 121}, {'max_job_seconds': 24 * 3600 + 1}]:
            with self.assertRaises(md.DownloadError): md.Limits(**kwargs)
        plan = self.plan(); job = self.start(plan); result = self.manager.wait(job['job_id'], 3)
        event = threading.Event()
        with self.assertRaises(md.DownloadError):
            self.manager._stop(result['job_id'], event, time.monotonic() - 24 * 3600 - 1)


if __name__ == '__main__':
    unittest.main()
