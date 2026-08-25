#!/usr/bin/env python3
"""Static file server with HTTP Range support (needed for <video> seeking/Safari).

Usage: python3 static_server.py [port] [directory] [host]
Defaults: port 8080, directory webapp/frontend, host 127.0.0.1

Env overrides:
  WEB_PORT, WEB_DIR, WEB_HOST
"""
import os
import re
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

RANGE_RE = re.compile(r"bytes=(\d*)-(\d*)")


class RangeHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def send_head(self):
        rng = self.headers.get("Range")
        if not rng:
            return super().send_head()
        path = self.translate_path(self.path)
        if not os.path.isfile(path):
            return super().send_head()
        m = RANGE_RE.match(rng.strip())
        if not m:
            return super().send_head()
        size = os.path.getsize(path)
        start_s, end_s = m.group(1), m.group(2)
        if start_s == "":
            length = int(end_s)
            start = max(0, size - length)
            end = size - 1
        else:
            start = int(start_s)
            end = int(end_s) if end_s else size - 1
        end = min(end, size - 1)
        if start > end or start >= size:
            self.send_response(416)
            self.send_header("Content-Range", f"bytes */{size}")
            self.end_headers()
            return None
        f = open(path, "rb")
        f.seek(start)
        self.send_response(206)
        ctype = self.guess_type(path)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Content-Length", str(end - start + 1))
        self.end_headers()
        self._range = (start, end)
        return f

    def copyfile(self, source, outputfile):
        rng = getattr(self, "_range", None)
        if not rng:
            return super().copyfile(source, outputfile)
        start, end = rng
        remaining = end - start + 1
        chunk = 64 * 1024
        while remaining > 0:
            data = source.read(min(chunk, remaining))
            if not data:
                break
            outputfile.write(data)
            remaining -= len(data)
        self._range = None


class EMPThreadingHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    port = int(sys.argv[1] if len(sys.argv) > 1 else os.environ.get("WEB_PORT", "8080"))
    directory = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("WEB_DIR", "webapp/frontend")
    host = sys.argv[3] if len(sys.argv) > 3 else os.environ.get("WEB_HOST", "127.0.0.1")
    if not str(host).strip():
        host = "127.0.0.1"
    directory = os.path.abspath(directory)
    if not os.path.isdir(directory):
        raise SystemExit(f"Frontend directory not found: {directory}")
    handler = partial(RangeHandler, directory=directory)
    httpd = EMPThreadingHTTPServer((host, port), handler)
    print(f"Serving {directory} on {host}:{port} (Range enabled)", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
