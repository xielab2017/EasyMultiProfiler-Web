"""Serve only bundled tutorial assets, with bounded single-range streaming."""
import re

ASSETS = {
    '/tutorial.html': ('tutorial.html', 'text/html; charset=utf-8'),
    '/js/tutorial.js': ('js/tutorial.js', 'text/javascript; charset=utf-8'),
    '/videos/emp_metadata_walkthrough.mp4': ('videos/emp_metadata_walkthrough.mp4', 'video/mp4'),
    '/videos/emp_metadata_walkthrough.en.vtt': ('videos/emp_metadata_walkthrough.en.vtt', 'text/vtt; charset=utf-8'),
    '/videos/emp_metadata_walkthrough.zh.vtt': ('videos/emp_metadata_walkthrough.zh.vtt', 'text/vtt; charset=utf-8'),
}

def serve(handler, path, frontend):
    if path not in ASSETS:
        return False
    relative, mime = ASSETS[path]
    file = frontend / relative
    if not file.is_file():
        handler.send_error(404, 'Tutorial asset not installed')
        return True
    size = file.stat().st_size
    start, end, status = 0, size - 1, 200
    requested = handler.headers.get('Range') if handler.command == 'GET' else None
    match = re.fullmatch(r'bytes=(\d{0,20})-(\d{0,20})', requested or '')
    if match and any(match.groups()):
        first, last = match.groups()
        start = int(first) if first else max(0, size - int(last))
        end = min(int(last), size - 1) if first and last else size - 1
        if start > end or start >= size:
            handler.send_response(416)
            handler.send_header('Content-Range', f'bytes */{size}')
            handler.send_header('Content-Length', '0')
            handler.end_headers()
            return True
        status = 206
    handler.send_response(status)
    handler.send_header('Content-Type', mime)
    handler.send_header('Content-Length', str(max(0, end - start + 1)))
    handler.send_header('Accept-Ranges', 'bytes')
    handler.send_header('X-Content-Type-Options', 'nosniff')
    handler.send_header('Cache-Control', 'no-cache')
    if status == 206:
        handler.send_header('Content-Range', f'bytes {start}-{end}/{size}')
    handler.end_headers()
    if handler.command != 'HEAD':
        with file.open('rb') as stream:
            stream.seek(start)
            remaining = end - start + 1
            while remaining > 0:
                chunk = stream.read(min(65536, remaining))
                if not chunk:
                    break
                handler.wfile.write(chunk)
                remaining -= len(chunk)
    return True
