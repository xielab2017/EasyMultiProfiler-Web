#!/usr/bin/env python3
"""EMP public gateway: one origin for Funnel / Tailscale Serve.

  /api/*  -> http://127.0.0.1:API_PORT
  /*      -> http://127.0.0.1:WEB_PORT

Funnel HTTPS (port 443) has empty window.location.port, so the frontend
already uses same-origin `/api` — this gateway makes that work.
"""
from __future__ import annotations

import os
import sys
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


API_PORT = int(os.environ.get("API_PORT", "8000"))
WEB_PORT = int(os.environ.get("WEB_PORT", "8080"))
GATEWAY_HOST = os.environ.get("GATEWAY_HOST", "127.0.0.1")
GATEWAY_PORT = int(os.environ.get("GATEWAY_PORT", "8090"))
HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "host",
    "content-length",
}


class GatewayHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _target(self):
        path = urlsplit(self.path).path or "/"
        if path == "/api" or path.startswith("/api/"):
            return ("127.0.0.1", API_PORT)
        return ("127.0.0.1", WEB_PORT)

    def _proxy(self):
        host, port = self._target()
        length = int(self.headers.get("Content-Length", "0") or 0)
        body = self.rfile.read(length) if length > 0 else None
        headers = {
            k: v
            for k, v in self.headers.items()
            if k.lower() not in HOP_BY_HOP
        }
        # Preserve client identity for logs; backend still sees gateway.
        headers["X-Forwarded-Host"] = self.headers.get("Host", "")
        headers["X-Forwarded-Proto"] = self.headers.get("X-Forwarded-Proto", "https")
        try:
            conn = HTTPConnection(host, port, timeout=300)
            conn.request(self.command, self.path, body=body, headers=headers)
            resp = conn.getresponse()
            payload = resp.read()
        except Exception as exc:  # noqa: BLE001
            msg = f"gateway upstream error: {exc}".encode("utf-8")
            self.send_response(502)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)
            return

        self.send_response(resp.status, resp.reason)
        for k, v in resp.getheaders():
            if k.lower() in HOP_BY_HOP:
                continue
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(payload)
        try:
            conn.close()
        except Exception:
            pass

    def do_GET(self):
        self._proxy()

    def do_POST(self):
        self._proxy()

    def do_PUT(self):
        self._proxy()

    def do_DELETE(self):
        self._proxy()

    def do_OPTIONS(self):
        self._proxy()

    def do_HEAD(self):
        self._proxy()

    def do_PATCH(self):
        self._proxy()


def main():
    httpd = ThreadingHTTPServer((GATEWAY_HOST, GATEWAY_PORT), GatewayHandler)
    print(
        f"EMP gateway on http://{GATEWAY_HOST}:{GATEWAY_PORT} "
        f"(web:{WEB_PORT} api:{API_PORT})",
        flush=True,
    )
    httpd.serve_forever()


if __name__ == "__main__":
    main()
