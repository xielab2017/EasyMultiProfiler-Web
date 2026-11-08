"""Explicit, streamed GEO supplementary-original downloads; never extracts/executes.

Instantiate with a private service-owned directory. ``plan`` accepts only a
server-owned processed_data manifest, never an HTTP-client URL or filesystem
path. No dependency on the optional advanced/raw-download installation.
"""
from __future__ import annotations

from copy import deepcopy
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import shutil
import stat
import threading
import time
from urllib.parse import unquote, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
import uuid

import processed_data
import public_data

GIB = 1024 ** 3
DEFAULT_MAX_BYTES = 5 * GIB
MAX_BYTES = 100 * GIB
ID = re.compile(r'[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}')
TERMINAL = {'completed', 'cancelled', 'interrupted', 'failed'}
FULL_PARTIAL_RECOVERY = ('The retained partial already reaches its known total size but is not finalized. '
                         'Create a new explicitly confirmed download plan; existing bytes are retained '
                         'without automatic deletion or redownload.')


class DownloadError(public_data.MetadataError):
    """Rejected consent, unsafe source/response, or resource/integrity failure."""


class _Cancelled(DownloadError):
    pass


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise DownloadError('Download redirects are refused; refresh the official GEO metadata.')


@dataclass(frozen=True)
class Limits:
    """Trusted service configuration, not HTTP request parameters."""
    default_max_bytes: int = DEFAULT_MAX_BYTES
    max_file_bytes: int = MAX_BYTES
    reserve_bytes: int = GIB
    chunk_bytes: int = 1024 * 1024
    timeout_seconds: int = 30
    max_job_seconds: int = 24 * 3600

    def __post_init__(self):
        if any(type(v) is not int or v < 1 for v in asdict(self).values()):
            raise DownloadError('All download limits must be positive integers.')
        if not self.default_max_bytes <= self.max_file_bytes <= MAX_BYTES:
            raise DownloadError('Maximum download budget is 100 GiB.')
        if self.reserve_bytes < GIB or self.chunk_bytes > 8 * 1024 ** 2:
            raise DownloadError('A 1 GiB disk reserve and a bounded stream buffer are required.')
        if self.timeout_seconds > 120 or self.max_job_seconds > 24 * 3600:
            raise DownloadError('Socket timeout or attempt deadline is too large.')


def _full_partial(value):
    total, retained = value.get('total_bytes'), value.get('bytes_downloaded')
    return type(total) is int and total > 0 and type(retained) is int and retained >= total


def _resume_state(value, error):
    if _full_partial(value):
        message = error or ''
        if FULL_PARTIAL_RECOVERY not in message:
            message = (message + ' ' + FULL_PARTIAL_RECOVERY).strip()
        return False, message
    return bool(value.get('validator') and value.get('bytes_downloaded')), error


def _now():
    return datetime.now(timezone.utc).isoformat()


def _canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode('utf-8')


def _digest(value):
    return hashlib.sha256(_canonical(value)).hexdigest()


def _directory(path, create=False):
    path = Path(os.path.abspath(path))
    for component in reversed([path, *path.parents]):
        try:
            info = component.lstat()
        except FileNotFoundError:
            if not create:
                raise DownloadError('Download directory is unavailable.')
            component.mkdir(mode=0o700)
            info = component.lstat()
        if not stat.S_ISDIR(info.st_mode):
            raise DownloadError('Symlink and non-directory download paths are refused.')
    return path


def _regular(path):
    try:
        info = path.lstat()
    except FileNotFoundError:
        return False
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        raise DownloadError('Download artifacts must be private regular files without links.')
    if os.name != 'nt' and info.st_mode & 0o077:
        raise DownloadError('Download artifacts must have private filesystem permissions.')
    return True


def _open(path, flags, mode='rb'):
    _regular(path)
    fd = os.open(path, flags | getattr(os, 'O_NOFOLLOW', 0), 0o600)
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or (os.name != 'nt' and info.st_mode & 0o077):
        os.close(fd)
        raise DownloadError('Unsafe download artifact.')
    return os.fdopen(fd, mode)


def _write_json(path, value):
    _regular(path)
    temporary = path.with_name('.' + uuid.uuid4().hex + '.tmp')
    try:
        with _open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 'wb') as handle:
            handle.write(_canonical(value)); handle.flush(); os.fsync(handle.fileno())
        _regular(path)
        os.replace(temporary, path)
    finally:
        if _regular(temporary):
            temporary.unlink()


def _fingerprint(info):
    return {'device': info.st_dev, 'inode': info.st_ino, 'size': info.st_size,
            'mtime_ns': info.st_mtime_ns, 'ctime_ns': info.st_ctime_ns}


def _read_json(path):
    with _open(path, os.O_RDONLY) as handle:
        data = handle.read(256 * 1024 + 1)
    if len(data) > 256 * 1024:
        raise DownloadError('Download record exceeds its size limit.')
    try:
        value = json.loads(data)
    except (ValueError, UnicodeError) as exc:
        raise DownloadError('Invalid persisted download record.') from exc
    if not isinstance(value, dict):
        raise DownloadError('Invalid persisted download record.')
    return value


class _Lease:
    """One root-wide OS lock; automatically released on process exit."""
    def __init__(self, root):
        self.handle = _open(root / 'manager.lock', os.O_RDWR | os.O_CREAT, 'r+b')
        try:
            if os.name == 'nt':
                import msvcrt
                if os.fstat(self.handle.fileno()).st_size == 0:
                    self.handle.write(b'0'); self.handle.flush()
                self.handle.seek(0)
                msvcrt.locking(self.handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except (OSError, ImportError) as exc:
            self.handle.close()
            raise DownloadError('A matrix download is already active or the filesystem cannot lock safely.') from exc

    def close(self):
        if self.handle.closed:
            return
        try:
            if os.name == 'nt':
                import msvcrt
                self.handle.seek(0); msvcrt.locking(self.handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.handle, fcntl.LOCK_UN)
        finally:
            self.handle.close()


def _checksum(value):
    if value is None:
        return None
    if not isinstance(value, dict) or set(value) != {'algorithm', 'value'}:
        raise DownloadError('Publisher checksum must specify algorithm and value, or be unavailable.')
    algorithm, expected = value['algorithm'], value['value']
    if algorithm not in {'md5', 'sha256'} or not isinstance(expected, str) or not re.fullmatch('[a-fA-F0-9]{' + str(32 if algorithm == 'md5' else 64) + '}', expected):
        raise DownloadError('Unsupported or malformed publisher checksum.')
    return {'algorithm': algorithm, 'value': expected.lower()}


def _spec(item, accession):
    if not isinstance(item, dict) or not isinstance(item.get('url'), str) or len(item['url']) > 4096:
        raise DownloadError('Malformed GEO file metadata.')
    try:
        if re.fullmatch(r'PXD[0-9]{5,9}',accession):
            parts=urlsplit(item['url']);path=unquote(parts.path)
            if parts.scheme!='https' or parts.hostname!='ftp.pride.ebi.ac.uk' or parts.port or parts.username or parts.password or parts.query or parts.fragment or not path.startswith('/pride/data/archive/') or accession not in path.split('/') or '%' in path or '\\' in path or '..' in path.split('/') or any(ord(c)<32 for c in path):raise ValueError('unapproved PRIDE source')
            url='https://ftp.pride.ebi.ac.uk'+parts.path
        else:url = processed_data.safe_url(item['url'], accession)
    except (ValueError, public_data.MetadataError) as exc:
        raise DownloadError('Only official GEO supplementary files for this series are allowed.') from exc
    parts = urlsplit(url)
    # safe_url is the source whitelist; also refuse ambiguous, nested file keys.
    name = unquote(parts.path.rsplit('/', 1)[-1])
    if not name or len(name) > 512 or '/' in name or '\\' in name or name in {'.', '..'} or any(ord(c) < 32 or ord(c) == 127 for c in name):
        raise DownloadError('Invalid supplementary filename.')
    if any(component in {'', '.', '..'} for component in unquote(parts.path).split('/')[1:]):
        raise DownloadError('Noncanonical supplementary-file path.')
    if item.get('name', name) != name:
        raise DownloadError('Supplementary filename does not match its official source URL.')
    if re.search(r'\.(?:fastq|fq|sra|bam|cram)(?:\.|$)', name, re.I):
        raise DownloadError('Direct FASTQ/FQ/SRA/BAM/CRAM reads are outside matrix-download scope.')
    size = item.get('bytes')
    if size is not None and (type(size) is not int or size <= 0):
        raise DownloadError('File size must be positive bytes or unknown.')
    identifier = item.get('id', item.get('file_id'))
    if not isinstance(identifier, str) or len(identifier) > 256:
        raise DownloadError('Invalid supplementary file ID.')
    return {'file_id': identifier, 'name': name, 'url': url, 'bytes': size,
            'checksum': _checksum(item.get('checksum'))}


def _validator(headers):
    etag = headers.get('ETag')
    if isinstance(etag, str) and len(etag) <= 1024 and re.fullmatch(r'"[\x21\x23-\x7e]*"', etag):
        return {'header': 'ETag', 'value': etag}
    modified = headers.get('Last-Modified')
    if isinstance(modified, str) and len(modified) <= 128:
        try:
            if parsedate_to_datetime(modified).tzinfo is not None:
                return {'header': 'Last-Modified', 'value': modified}
        except (ValueError, TypeError, OverflowError):
            pass
    return None


def _length(headers):
    values = headers.get_all('Content-Length') if hasattr(headers, 'get_all') else None
    if values is not None and len(values) > 1:
        raise DownloadError('Ambiguous Content-Length response.')
    raw = headers.get('Content-Length')
    if raw is None:
        return None
    if not isinstance(raw, str) or not re.fullmatch(r'[0-9]{1,20}', raw):
        raise DownloadError('Invalid Content-Length response.')
    return int(raw)


class MatrixDownloadManager:
    """One bounded worker across processes, persistent progress, explicit resume.

    ``opener`` and ``disk_usage`` are trusted offline-test injection seams only.
    All returned records are independent JSON-compatible snapshots.
    """
    def __init__(self, directory, limits=None, *, opener=None, disk_usage=None):
        self.root = _directory(directory, create=True)
        if os.name != 'nt' and self.root.stat().st_mode & 0o077:
            raise DownloadError('Use a private (0700) service-owned matrix download directory.')
        self.limits = limits or Limits()
        self._destination_id = hashlib.sha256(str(self.root).encode()).hexdigest()
        self._opener = opener or build_opener(NoRedirect())
        self._disk_usage = disk_usage or shutil.disk_usage
        self._lock = threading.RLock()
        self._plans, self._jobs, self._threads, self._events, self._plan_jobs = {}, {}, {}, {}, {}

    def _space(self, remaining):
        _directory(self.root)
        if self._disk_usage(self.root).free < remaining + self.limits.reserve_bytes:
            raise DownloadError('Insufficient free disk space for the download and 1 GiB reserve.')

    def plan(self, manifest, file_id, max_bytes=None):
        """Select one original file, without network access or automatic selection."""
        if not isinstance(manifest, dict) or manifest.get('status') != 'processed_candidates':
            raise DownloadError('A server-owned GEO supplementary-file manifest is required.')
        accession = manifest.get('accession')
        if not isinstance(accession, str) or not re.fullmatch(r'(?:GSE\d+|PXD[0-9]{5,9})', accession):
            raise DownloadError('A GEO series accession is required.')
        rows = manifest.get('files')
        if not isinstance(rows, list) or len(rows) > 10000 or not isinstance(file_id, str):
            raise DownloadError('Invalid supplementary-file selection.')
        matches = [row for row in rows if isinstance(row, dict) and row.get('id') == file_id]
        if len(matches) != 1:
            raise DownloadError('Select exactly one file ID from this GEO manifest.')
        item = _spec(matches[0], accession)
        if item['bytes'] is None and max_bytes is None:
            raise DownloadError('Unknown-size downloads require an explicit per-file max_bytes budget.')
        cap = self.limits.default_max_bytes if max_bytes is None else max_bytes
        if type(cap) is not int or not 0 < cap <= self.limits.max_file_bytes:
            raise DownloadError('Choose a positive byte budget no larger than 100 GiB.')
        blockers = []
        if item['bytes'] is not None and item['bytes'] > cap:
            blockers.append('The declared file size exceeds the selected download budget.')
        try:
            self._space(item['bytes'] if item['bytes'] is not None else cap)
        except DownloadError as exc:
            blockers.append(str(exc))
        warnings = ['Downloads the selected original file only; no extraction, conversion, inspection or analysis.',
                    'A GEO supplementary filename does not prove that the contents are a matrix or scientifically suitable.',
                    'Local SHA-256 identifies downloaded bytes; publisher integrity is verified only when an explicit publisher checksum is available.']
        if re.search(r'\.(?:zip|tar|tgz|tbz2|txz|7z)(?:\.(?:gz|bz2|xz|zst))?$', item['name'], re.I):
            warnings.append('Archive contents are unknown and will not be extracted. GEO *_RAW.tar may contain processed matrices or other data; choose it only after checking the author description.')
        if item['bytes'] is None:
            warnings.append('Source size is unknown. The explicit byte budget is a hard stop; a partial file is retained if the limit is exceeded.')
        value = {'kind': 'matrix_download_plan', 'schema_version': 1, 'plan_id': str(uuid.uuid4()),
                 'created_at': _now(), 'accession': accession, 'file': item,
                 'source_name': item['name'], 'source_url': item['url'], 'bytes': item['bytes'],
                 'total_bytes': item['bytes'], 'max_bytes': cap, 'limits': asdict(self.limits),
                 'destination_id': self._destination_id, 'manifest_sha256': _digest(manifest),
                 'status': 'blocked' if blockers else 'ready_for_confirmation',
                 'blockers': blockers, 'warnings': warnings, 'download_enabled': not blockers,
                 'confirmation_required': True, 'archive_extracted': False, 'analysis_executed': False}
        value['plan_sha256'] = _digest(value)
        with self._lock:
            now = time.monotonic()
            self._plans = {k: v for k, v in self._plans.items() if now - v[0] < 1800}
            if len(self._plans) >= 128:
                del self._plans[next(iter(self._plans))]
            self._plans[value['plan_id']] = (now, deepcopy(value))
        return deepcopy(value)

    def _check_plan(self, value, confirmed, expected, registered=False):
        if confirmed is not True or not isinstance(expected, str):
            raise DownloadError('Explicit confirmation of the exact plan_sha256 is required.')
        if not isinstance(value, dict):
            raise DownloadError('A server-owned matrix download plan is required.')
        digest = value.get('plan_sha256')
        if not isinstance(digest, str) or not hmac.compare_digest(digest, expected) or not hmac.compare_digest(_digest({k: v for k, v in value.items() if k != 'plan_sha256'}), digest):
            raise DownloadError('The download plan changed; review and confirm its exact digest.')
        if value.get('kind') != 'matrix_download_plan' or value.get('destination_id') != self._destination_id or value.get('limits') != asdict(self.limits):
            raise DownloadError('Download destination or limits changed; prepare a new plan.')
        if registered:
            found = self._plans.get(value.get('plan_id'))
            if not found or time.monotonic() - found[0] >= 1800 or found[1] != value:
                raise DownloadError('Plan expired or was not created by this manager.')
        if value.get('status') != 'ready_for_confirmation' or value.get('blockers'):
            raise DownloadError('Resolve plan blockers and prepare a new plan before downloading.')
        item = value.get('file')
        accession = value.get('accession')
        if not isinstance(accession, str) or not re.fullmatch(r'(?:GSE\d+|PXD[0-9]{5,9})', accession) or not isinstance(item, dict) or _spec(item, accession) != item:
            raise DownloadError('Invalid planned GEO source.')
        cap = value.get('max_bytes')
        if type(cap) is not int or not 0 < cap <= self.limits.max_file_bytes or (item['bytes'] is not None and item['bytes'] > cap):
            raise DownloadError('Invalid planned size or budget.')

    def _folder(self, key):
        if not isinstance(key, str) or not ID.fullmatch(key):
            raise DownloadError('Invalid matrix download job ID.')
        folder = _directory(self.root / key)
        if os.name != 'nt' and folder.stat().st_mode & 0o077:
            raise DownloadError('Matrix job directory must be private.')
        return folder

    def _persist(self, key):
        self._jobs[key]['updated_at'] = _now()
        _write_json(self._folder(key) / 'job.json', self._jobs[key])

    def _update(self, key, **changes):
        with self._lock:
            self._jobs[key].update(changes); self._persist(key)

    def _available(self):
        if any(thread.is_alive() for thread in self._threads.values()):
            raise DownloadError('A matrix download is already active; wait or cancel it first.')
        return _Lease(_directory(self.root))

    def start(self, plan, confirmed=False, plan_sha256=None):
        with self._lock:
            self._check_plan(plan, confirmed, plan_sha256, registered=True)
            if plan_sha256 in self._plan_jobs:
                return self.get(self._plan_jobs[plan_sha256])
            lease = self._available()
            try:
                self._space(plan['bytes'] if plan['bytes'] is not None else plan['max_bytes'])
                key = str(uuid.uuid4()); (self.root / key).mkdir(mode=0o700)
                value = {'kind': 'matrix_download_job', 'schema_version': 1, 'job_id': key,
                         'plan_id': plan['plan_id'], 'plan_sha256': plan_sha256, 'plan': deepcopy(plan),
                         'status': 'queued', 'created_at': _now(), 'updated_at': _now(),
                         'source_name': plan['source_name'], 'source_url': plan['source_url'],
                         'total_bytes': plan['bytes'], 'max_bytes': plan['max_bytes'],
                         'bytes_downloaded': 0, 'partial_sha256': hashlib.sha256(b'').hexdigest(),
                         'validator': None, 'resume_supported': False, 'error': None,
                         'receipt': None, 'attempts': 1, 'cancel_requested': False,
                         'archive_extracted': False, 'analysis_executed': False}
                self._jobs[key] = value
                self._plan_jobs[plan_sha256] = key
                self._persist(key)
                self._launch(key, lease, resume=False)
                return deepcopy(value)
            except BaseException:
                lease.close(); raise

    def get(self, job_id):
        with self._lock:
            folder = self._folder(job_id)
            if job_id not in self._jobs or job_id not in self._threads:
                value = _read_json(folder / 'job.json')
                if value.get('kind') != 'matrix_download_job' or value.get('job_id') != job_id:
                    raise DownloadError('Invalid matrix download job record.')
                self._check_plan(value.get('plan'), True, value.get('plan_sha256'))
                if value.get('status') not in TERMINAL:
                    try:
                        lease = _Lease(self.root)
                    except DownloadError:
                        pass  # Another process owns the worker; never overwrite its progress.
                    else:
                        try:
                            message = ('Service stopped; partial bytes retained.' if _full_partial(value)
                                       else 'Service stopped; explicit resume confirmation is required.')
                            supported, message = _resume_state(value, message)
                            value.update(status='interrupted', error=message, resume_supported=supported)
                            _write_json(folder / 'job.json', value)
                        finally:
                            lease.close()
                self._jobs[job_id] = value
                self._plan_jobs[value['plan_sha256']] = job_id
            value = self._jobs[job_id]
            # Normalize older persisted terminal records too, without touching a
            # partial file or another process's active job.
            if value['status'] in TERMINAL - {'completed'} and _full_partial(value):
                value['resume_supported'], value['error'] = _resume_state(value, value.get('error'))
            return deepcopy(value)

    def history(self):
        """Read bounded retained records without resuming, cancelling or deleting."""
        rows = []
        for folder in self.root.iterdir():
            if not ID.fullmatch(folder.name) or folder.is_symlink() or not folder.is_dir(): continue
            try:
                value = _read_json(folder / 'job.json')
                if value.get('kind') != 'matrix_download_job' or value.get('job_id') != folder.name: continue
                rows.append({key: value.get(key) for key in ('job_id','source_name','source_url','status','bytes_downloaded','total_bytes','created_at')})
            except (DownloadError, OSError): continue
        return sorted(rows, key=lambda row: row.get('created_at') or '', reverse=True)[:50]

    def cancel(self, job_id):
        with self._lock:
            value = self.get(job_id)
            if value['status'] in TERMINAL:
                return value
            _write_json(self._folder(job_id) / 'cancel.request', {'cancel': True})
            if job_id in self._events:
                self._events[job_id].set()
            if job_id in self._threads:
                self._jobs[job_id]['cancel_requested'] = True
                self._persist(job_id)
            value['cancel_requested'] = True
            return value

    def resume(self, job_id, confirmed=False, plan_sha256=None):
        with self._lock:
            value = self.get(job_id)
            self._check_plan(value['plan'], confirmed, plan_sha256)
            if value['status'] == 'completed':
                return value
            if value['status'] not in TERMINAL:
                raise DownloadError('Matrix download is already active.')
            if _full_partial(value):
                raise DownloadError(FULL_PARTIAL_RECOVERY)
            if not value.get('validator') or not value.get('bytes_downloaded'):
                raise DownloadError('Resume requires retained bytes and an original strong ETag or Last-Modified validator; no automatic restart.')
            lease = self._available()
            try:
                folder = self._folder(job_id); partial = folder / (job_id + '.part')
                if not _regular(partial) or partial.stat().st_size != value['bytes_downloaded']:
                    raise DownloadError('Retained partial differs from its durable checkpoint; it will not be appended or discarded.')
                total = value['total_bytes'] if value['total_bytes'] is not None else value['max_bytes']
                self._space(max(0, total - value['bytes_downloaded']))
                marker = folder / 'cancel.request'
                if _regular(marker):
                    marker.unlink()
                self._jobs[job_id].update(status='queued', error=None, cancel_requested=False,
                                         resume_supported=False, attempts=value['attempts'] + 1)
                self._persist(job_id)
                self._launch(job_id, lease, resume=True)
                return deepcopy(self._jobs[job_id])
            except BaseException:
                lease.close(); raise

    def wait(self, job_id, timeout=None):
        """Local/test convenience. HTTP callers should poll get instead."""
        self.get(job_id)
        thread = self._threads.get(job_id)
        if thread:
            thread.join(timeout)
        return self.get(job_id)

    def _launch(self, key, lease, resume):
        event = threading.Event(); self._events[key] = event
        thread = threading.Thread(target=self._run, args=(key, event, lease, resume), name='emp-matrix-' + key[:8], daemon=True)
        self._threads[key] = thread; thread.start()

    def _stop(self, key, event, started):
        if event.is_set() or _regular(self._folder(key) / 'cancel.request'):
            raise _Cancelled('Download cancelled; partial bytes retained.')
        if time.monotonic() - started > self.limits.max_job_seconds:
            raise DownloadError('Maximum download attempt duration exceeded; partial bytes retained.')

    def _run(self, key, event, lease, resume):
        started = time.monotonic()
        try:
            self._update(key, status='running')
            self._download(key, event, started, resume)
        except Exception as exc:
            status = 'cancelled' if isinstance(exc, _Cancelled) else 'failed'
            message = str(exc) if isinstance(exc, DownloadError) else 'Matrix transfer failed (' + type(exc).__name__ + '); partial bytes retained.'
            with self._lock:
                value = self._jobs[key]
                supported, message = _resume_state(value, message)
                self._update(key, status=status, error=message, resume_supported=supported)
        finally:
            lease.close()

    def _download(self, key, event, started, resume):
        value = self._jobs[key]; plan = value['plan']; item = plan['file']
        folder = self._folder(key); partial = folder / (key + '.part'); final = folder / (key + '.data')
        sha = hashlib.sha256(); publisher = item['checksum']
        publisher_hash = hashlib.new(publisher['algorithm'], usedforsecurity=False) if publisher else None
        actual = 0
        if resume:
            with _open(partial, os.O_RDONLY) as source:
                while True:
                    self._stop(key, event, started)
                    block = source.read(self.limits.chunk_bytes)
                    if not block:
                        break
                    actual += len(block)
                    if actual > value['max_bytes']:
                        raise DownloadError('Retained partial exceeds its confirmed budget.')
                    sha.update(block)
                    if publisher_hash: publisher_hash.update(block)
            if actual != value['bytes_downloaded'] or not hmac.compare_digest(sha.hexdigest(), value['partial_sha256']):
                raise DownloadError('Retained partial checksum changed; refusing to append.')
        headers = {'User-Agent': 'EasyMultiProfiler-MatrixDownload/1.0', 'Accept-Encoding': 'identity'}
        if resume:
            headers.update({'Range': 'bytes=' + str(actual) + '-', 'If-Range': value['validator']['value']})
        self._stop(key, event, started)
        with self._opener.open(Request(item['url'], headers=headers), timeout=self.limits.timeout_seconds) as response:
            self._stop(key, event, started)
            if response.geturl() != item['url'] or response.headers.get('Content-Encoding', 'identity').lower() != 'identity':
                raise DownloadError('Unexpected download origin or content encoding.')
            length = _length(response.headers)
            if resume:
                if response.status != 206:
                    raise DownloadError('Resume requires HTTP 206; a full response is never appended or automatically restarted.')
                match = re.fullmatch(r'bytes ([0-9]{1,20})-([0-9]{1,20})/([0-9]{1,20})', response.headers.get('Content-Range', ''))
                if not match:
                    raise DownloadError('Resume requires an exact bounded Content-Range.')
                start, end, total = map(int, match.groups())
                if start != actual or end != total - 1 or not start <= end or total > value['max_bytes']:
                    raise DownloadError('Resume Content-Range does not match the retained file or budget.')
                previous_total = value['total_bytes']
                if previous_total is not None and total != previous_total:
                    raise DownloadError('Source size changed; retained bytes will not be appended.')
                validator = value['validator']
                if response.headers.get(validator['header']) != validator['value']:
                    raise DownloadError('Source validator changed or disappeared; retained bytes will not be appended.')
                if length is not None and length != total - actual:
                    raise DownloadError('Resume Content-Length does not match Content-Range.')
            else:
                if response.status != 200 or response.headers.get('Content-Range') is not None:
                    raise DownloadError('Initial download requires a complete HTTP 200 response.')
                total = item['bytes'] if item['bytes'] is not None else length
                if length is not None and total is not None and length != total:
                    raise DownloadError('Source size differs from the confirmed metadata.')
                validator = _validator(response.headers)
            if total is not None and (total <= 0 or total > value['max_bytes']):
                raise DownloadError('Source size exceeds the confirmed budget or is empty.')
            self._space((total if total is not None else value['max_bytes']) - actual)
            self._update(key, total_bytes=total, validator=validator)
            flags = os.O_WRONLY | (os.O_APPEND if resume else os.O_CREAT | os.O_EXCL)
            with _open(partial, flags, 'ab' if resume else 'wb') as output:
                maximum = total if total is not None else value['max_bytes']
                while True:
                    self._stop(key, event, started)
                    # read1 returns after one underlying socket read instead of waiting
                    # to fill a large buffer, keeping cancellation/deadline checks prompt.
                    read = getattr(response, 'read1', response.read)
                    block = read(min(self.limits.chunk_bytes, maximum - actual + 1))
                    self._stop(key, event, started)
                    if not block:
                        break
                    if actual + len(block) > maximum:
                        raise DownloadError('Download exceeds its declared size or confirmed byte budget.')
                    self._space(len(block))
                    output.write(block); output.flush(); os.fsync(output.fileno())
                    actual += len(block); sha.update(block)
                    if publisher_hash: publisher_hash.update(block)
                    self._update(key, bytes_downloaded=actual, partial_sha256=sha.hexdigest())
            if total is not None and actual != total:
                raise DownloadError('Download ended before its declared size; partial bytes retained.')
            if actual == 0:
                raise DownloadError('The downloaded source is empty.')
        self._stop(key, event, started)
        if publisher_hash and not hmac.compare_digest(publisher_hash.hexdigest(), publisher['value']):
            raise DownloadError('Publisher checksum mismatch; retained bytes are not a completed download.')
        _regular(partial)
        if _regular(final):
            raise DownloadError('A completed artifact already exists; refusing to overwrite it.')
        receipt = {'kind': 'matrix_download_receipt', 'job_id': key, 'completed_at': _now(),
                   'plan_sha256': plan['plan_sha256'], 'source_name': item['name'],
                   'source_url': item['url'], 'filename': key + '.data', 'bytes': actual,
                   'sha256': sha.hexdigest(), 'publisher_checksum': publisher,
                   'publisher_checksum_verified': publisher_hash is not None,
                   'archive_extracted': False, 'analysis_executed': False}
        os.replace(partial, final)
        with _open(final, os.O_RDONLY) as completed:
            receipt['artifact_identity'] = _fingerprint(os.fstat(completed.fileno()))
        _write_json(folder / 'receipt.json', receipt)
        self._update(key, status='completed', total_bytes=actual, bytes_downloaded=actual,
                     filename=receipt['filename'], sha256=receipt['sha256'],
                     publisher_checksum_verified=receipt['publisher_checksum_verified'],
                     receipt=receipt, resume_supported=False, error=None)

    def open_completed(self, job_id):
        """Return (binary_handle, receipt); caller closes handle after streaming."""
        with self._lock:
            value = self.get(job_id)
            if value['status'] != 'completed' or not isinstance(value.get('receipt'), dict):
                raise DownloadError('Only completed matrix downloads may be retrieved.')
            receipt = _read_json(self._folder(job_id) / 'receipt.json')
            if receipt != value['receipt'] or receipt.get('filename') != job_id + '.data':
                raise DownloadError('Completed download receipt does not match its job.')
            handle = _open(self._folder(job_id) / (job_id + '.data'), os.O_RDONLY)
        # Hashing a large completed file must not block status/cancel operations.
        try:
            before = _fingerprint(os.fstat(handle.fileno()))
            expected = receipt.get('artifact_identity')
            if (not isinstance(expected, dict) or set(expected) != set(before)
                    or before['size'] != receipt['bytes']
                    or any(before[field] != expected[field] for field in before if field != 'ctime_ns')):
                raise DownloadError('Completed file changed since verification; retrieval refused.')
            if before != expected:
                # macOS metadata changes can update ctime without changing the
                # payload. Never ignore it: verify this same opened descriptor,
                # with bounded reads and stable identity before/after hashing.
                digest = hashlib.sha256(); actual = 0; started = time.monotonic()
                while True:
                    if time.monotonic() - started > self.limits.max_job_seconds:
                        raise DownloadError('Completed-file verification deadline exceeded.')
                    block = handle.read(min(self.limits.chunk_bytes, receipt['bytes'] - actual + 1))
                    if not block:
                        break
                    actual += len(block)
                    if actual > receipt['bytes']:
                        raise DownloadError('Completed file changed during verification; retrieval refused.')
                    digest.update(block)
                after = _fingerprint(os.fstat(handle.fileno()))
                if (after != before or actual != receipt['bytes']
                        or not hmac.compare_digest(digest.hexdigest(), receipt['sha256'])):
                    raise DownloadError('Completed file changed during verification or its checksum no longer matches; retrieval refused.')
                handle.seek(0)
            return handle, deepcopy(receipt)
        except BaseException:
            handle.close()
            raise
