"""Exercise the Unix start/stop scripts with isolated HTTP fixture processes."""
from contextlib import ExitStack, closing
from http.client import HTTPConnection
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
SERVICES = (
    ("api", "backend/run_api.R", "API_PORT", "/api/health"),
    ("web", "scripts/static_server.py", "WEB_PORT", "/"),
    ("metadata", "scripts/public_data_server.py", "EMP_PUBLIC_DATA_PORT", "/api/public-data/health"),
)

# Fixture responses identify the process that actually owns the listener.
SERVER = """import os, signal
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(str(os.getpid()).encode())

signal.alarm(60)
HTTPServer(("127.0.0.1", int(os.environ[{port_key!r}])), Handler).serve_forever()
"""


@unittest.skipUnless(os.name == "posix", "Unix launcher")
class DetachedServiceTests(unittest.TestCase):
    def test_services_outlive_launcher_and_stop_by_recorded_pid(self):
        with tempfile.TemporaryDirectory(prefix="EMP daemon ") as folder:
            root = Path(folder)
            scripts = root / "webapp/scripts"
            scripts.mkdir(parents=True)
            for name in ("start_local.sh", "process_identity.sh", "stop_local.sh"):
                shutil.copy(SCRIPTS / name, scripts)
            for name in ("resolve_python.sh", "resolve_rscript.sh"):
                (scripts / name).write_text('echo "$TEST_PYTHON"\n')
            env = dict(PATH=os.environ["PATH"], HOME=folder, TEST_PYTHON=sys.executable)
            (root / "webapp/backend").mkdir()
            # Reserve distinct ephemeral ports together; release them just before launch.
            with ExitStack() as reserved:
                for _, script, port_key, _ in SERVICES:
                    (root / "webapp" / script).write_text(SERVER.format(port_key=port_key))
                    sock = reserved.enter_context(socket.socket())
                    sock.bind(("127.0.0.1", 0))
                    env[port_key] = str(sock.getsockname()[1])

            run = root / ".local_run"
            try:
                launched = subprocess.run(["bash", str(scripts / "start_local.sh")], env=env,
                                          capture_output=True, text=True, timeout=20, start_new_session=True)
                self.assertEqual(launched.returncode, 0, launched.stdout + launched.stderr)
                for name, _, port_key, endpoint in SERVICES:
                    pid = int((run / f"{name}.pid").read_text())
                    self.assertEqual(os.getsid(pid), pid)
                    self.assertEqual(os.getpgid(pid), pid)
                    with closing(HTTPConnection("127.0.0.1", int(env[port_key]), timeout=2)) as conn:
                        conn.request("GET", endpoint)
                        response = conn.getresponse()
                        self.assertEqual((response.status, response.read()), (200, str(pid).encode()))
            finally:
                subprocess.run(["bash", str(scripts / "stop_local.sh")], env=env, check=True,
                               capture_output=True, timeout=15)
            for name, _, port_key, _ in SERVICES:
                self.assertFalse((run / f"{name}.pid").exists())
                with socket.socket() as sock:
                    self.assertNotEqual(sock.connect_ex(("127.0.0.1", int(env[port_key]))), 0)
