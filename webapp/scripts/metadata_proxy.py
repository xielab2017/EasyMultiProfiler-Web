"""Bounded same-origin proxy to the local metadata service; never arbitrary targets."""
import http.client
import os
import re
from urllib.parse import urlsplit
from pdf_limits import MAX_PDF_BYTES

MAX_PDF = MAX_PDF_BYTES
MAX_JSON = 16384
MAX_RESPONSE = 34 * 1024 * 1024

def proxy(handler):
    path = urlsplit(handler.path).path
    if not path.startswith('/api/public-data/'):
        return False
    port = getattr(handler.server, 'metadata_port', 0)
    if not port:
        handler.send_error(503, 'Metadata service routing is not enabled')
        return True
    own_port = handler.server.server_address[1]
    hosts = {f'127.0.0.1:{own_port}', f'localhost:{own_port}'}
    host = handler.headers.get('Host', '')
    origin = handler.headers.get('Origin')
    def fail(status, message):
        data = ('{"error": "'+message+'"}').encode()
        handler.send_response(status); handler.send_header('Content-Type', 'application/json')
        handler.send_header('Content-Length', str(len(data))); handler.end_headers()
        if handler.command != 'HEAD': handler.wfile.write(data)
    if host not in hosts or origin not in (None, 'http://'+host):
        fail(403, 'Local origin required'); return True
    if handler.headers.get('Transfer-Encoding'):
        fail(400, 'Transfer encoding is not supported'); return True
    try:
        length = int(handler.headers.get('Content-Length', '0'))
    except ValueError:
        fail(400, 'Invalid body length'); return True
    limit = MAX_PDF if path.endswith('/papers/pdf') else MAX_JSON
    if path in {'/api/public-data/advanced/analysis/prepare','/api/public-data/advanced/r/prepare'}:
        limit = 512 * 1024
    if path == '/api/public-data/processed/annotations': limit = 512 * 1024
    if path == '/api/public-data/advanced/qc/upload': limit = 12 * 1024 * 1024
    if path == '/api/public-data/workbench/upload': limit = 12 * 1024 * 1024
    elif path.startswith('/api/public-data/workbench/'): limit = 512 * 1024
    if path == '/api/public-data/agent/attachments':limit = MAX_PDF if handler.headers.get('Content-Type','').split(';')[0]=='application/pdf' else 5*1024**2
    if length < 0 or length > limit:
        fail(413, 'Request too large'); return True
    headers = {}
    for key in ('Content-Type', 'Range', 'X-Matrix-Name', 'X-Attachment-Name'):
        if handler.headers.get(key): headers[key] = handler.headers[key]
    # Host and origin are validated above. Do not forward cookies/auth/private headers.
    handler.connection.settimeout(30)
    body = handler.rfile.read(length) if length else None
    connection = http.client.HTTPConnection('127.0.0.1', port, timeout=120)
    try:
        connection.request(handler.command, handler.path, body, headers)
        response = connection.getresponse()
        declared = response.getheader('Content-Length')
        streaming_matrix = re.fullmatch(r'/api/public-data/matrix/files/[a-f0-9-]{36}', path)
        streaming_export = re.fullmatch(r'/api/public-data/matrix/exports/[a-f0-9-]{36}', path)
        if (streaming_matrix or streaming_export) and response.status in (200,206):
            if declared is None or not declared.isdigit() or not 0 <= int(declared) <= (2*1024**2 if streaming_export else 100*1024**3):
                raise ValueError('Invalid matrix file length')
            handler.send_response(response.status)
            for key in ('Content-Type','Content-Disposition','Content-Range','Accept-Ranges','ETag'):
                if response.getheader(key):handler.send_header(key,response.getheader(key))
            handler.send_header('Content-Length',declared);handler.send_header('Cache-Control','no-store');handler.send_header('X-Content-Type-Options','nosniff');handler.end_headers()
            remaining=int(declared) if handler.command!='HEAD' else 0
            try:
                while remaining:
                    chunk=response.read(min(65536,remaining))
                    if not chunk:handler.close_connection=True;break
                    handler.wfile.write(chunk);remaining-=len(chunk)
            except (OSError,http.client.HTTPException):handler.close_connection=True
            return True
        if declared and int(declared) > MAX_RESPONSE:
            raise ValueError('Oversized response')
        data = response.read(MAX_RESPONSE + 1)
        if len(data) > MAX_RESPONSE:
            raise ValueError('Oversized response')
        handler.send_response(response.status)
        for key in ('Content-Type', 'Content-Disposition', 'Content-Range', 'Accept-Ranges'):
            if response.getheader(key): handler.send_header(key, response.getheader(key))
        handler.send_header('Content-Length', str(len(data)))
        handler.send_header('Cache-Control', 'no-store')
        handler.send_header('X-Content-Type-Options', 'nosniff'); handler.end_headers()
        if handler.command != 'HEAD': handler.wfile.write(data)
    except (OSError, ValueError, http.client.HTTPException):
        fail(502, 'Metadata service unavailable; start Start-EMP-Metadata')
    finally:
        connection.close()
    return True
