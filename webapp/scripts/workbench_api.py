"""Local-owner workbench routes around the existing metadata service."""
import json
import threading
from urllib.parse import unquote, urlsplit
import matrix_api
import omics_workbench as wb

PREFIX = '/api/public-data/workbench/'
LOCK = threading.Lock()


def local_owner(handler):
    # Public gateway requests cannot expose prepared payloads containing counts.
    # Direct local requests and the existing loopback-only static proxy are kept.
    forwarded = handler.headers.get('X-Forwarded-Host')
    if forwarded:
        try:
            if urlsplit('http://' + forwarded).hostname not in {'localhost', '127.0.0.1', '::1'}: return False
        except ValueError: return False
    return handler.valid_origin()


def for_server(server, root):
    with LOCK:
        if not hasattr(server, 'omics_workbench'):
            server.omics_workbench = wb.Workbench(root / '.local_run/workbench')
        return server.omics_workbench


def instance(handler, root):
    return for_server(handler.server, root)


def install(Handler, root):
    if getattr(Handler, '_workbench_routes_installed', False): return
    old_post, old_get = Handler.do_POST, Handler.do_GET

    def post(self):
        path = urlsplit(self.path).path
        if not path.startswith(PREFIX): return old_post(self)
        if not local_owner(self): return self.reply(403, {'error': 'Local owner origin required'})
        if self.headers.get('Transfer-Encoding'): return self.reply(400, {'error': 'Transfer encoding unsupported'})
        op = path.removeprefix(PREFIX)
        try:
            size = int(self.headers.get('Content-Length', '0'))
            limit = wb.MAX_BYTES if op == 'upload' else 512 * 1024
            if not 0 < size <= limit: return self.reply(413, {'error': 'Workbench request exceeds bounded size'})
            self.connection.settimeout(30)
            service = instance(self, root)
            if op == 'upload':
                if self.headers.get('Content-Type') != 'application/octet-stream': return self.reply(415, {'error': 'Raw file body required'})
                name = unquote(self.headers.get('X-Matrix-Name', 'counts.tsv'))
                if len(name) > 256 or '/' in name or '\\' in name: raise ValueError('A filename without paths is required')
                return self.reply(200, service.ingest(self.rfile.read(size), name, 'Explicit local matrix upload: ' + name))
            if self.headers.get('Content-Type', '').split(';')[0] != 'application/json': return self.reply(415, {'error': 'JSON required'})
            req = json.loads(self.rfile.read(size))
            if op == 'ingest':
                wb.fields(req, {'job_id'})
                downloads = matrix_api.manager(self, root)
                job = downloads.get(req.get('job_id'))
                if job.get('status') != 'completed': raise ValueError('Wait for a completed matrix download before importing')
                if job['receipt']['bytes'] > wb.MAX_BYTES: raise ValueError('Download preserved; this in-memory analysis adapter accepts files <=12 MiB')
                handle, receipt = downloads.open_completed(req.get('job_id'))
                try:
                    if receipt['bytes'] > wb.MAX_BYTES: raise ValueError('Download preserved; this in-memory analysis adapter accepts files <=12 MiB')
                    raw = handle.read(wb.MAX_BYTES + 1)
                finally: handle.close()
                return self.reply(200, service.ingest(raw, receipt['source_name'], receipt['source_url']))
            if op == 'select':
                wb.fields(req, {'input_id', 'sample_columns'})
                return self.reply(200, service.select(req.get('input_id'), req.get('sample_columns')))
            if op == 'prepare':
                wb.fields(req, {'plan'})
                return self.reply(200, service.prepare(req.get('plan')))
            if op == 'propose':
                wb.fields(req, {'question'})
                return self.reply(200, wb.propose(req.get('question')))
            return self.reply(404, {'error': 'Unknown workbench operation'})
        except (ValueError, TypeError, KeyError, OSError, EOFError) as exc:
            return self.reply(400, {'error': str(exc)})

    def get(self):
        path = urlsplit(self.path).path
        if not path.startswith(PREFIX): return old_get(self)
        if not local_owner(self): return self.reply(403, {'error': 'Local owner origin required'})
        if path == PREFIX + 'catalog': return self.reply(200, wb.catalog())
        if path.startswith(PREFIX + 'prepared/'):
            try: return self.reply(200, instance(self, root).payload(path.removeprefix(PREFIX + 'prepared/')))
            except (ValueError, TypeError): return self.reply(404, {'error': 'Prepared record unavailable'})
        return self.reply(404, {'error': 'Unknown workbench resource'})

    Handler.do_POST, Handler.do_GET = post, get
    Handler._workbench_routes_installed = True
