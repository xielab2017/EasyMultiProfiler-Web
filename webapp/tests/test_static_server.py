"""HTTP regression checks for the frontend media server (stdlib only)."""
import functools
import http.client
import importlib.util
from pathlib import Path
import tempfile
import threading
import unittest

spec = importlib.util.spec_from_file_location('static_server', Path(__file__).parents[1] / 'scripts/static_server.py')
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


class RangeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        Path(cls.tmp.name, 'data.bin').write_bytes(b'0123456789')
        Path(cls.tmp.name, 'empty.bin').write_bytes(b'')
        cls.httpd = server.EMPThreadingHTTPServer(('127.0.0.1', 0), functools.partial(server.RangeHandler, directory=cls.tmp.name))
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()
        cls.thread.join()
        cls.tmp.cleanup()

    def request(self, value=None, method='GET', path='/data.bin'):
        conn = http.client.HTTPConnection(*self.httpd.server_address, timeout=3)
        conn.request(method, path, headers={} if value is None else {'Range': value})
        response = conn.getresponse()
        result = response.status, dict(response.getheaders()), response.read()
        conn.close()
        return result

    def test_full(self):
        self.assertEqual(self.request()[2], b'0123456789')

    def test_ranges(self):
        for value, expected in [('bytes=2-4', b'234'), ('bytes=7-', b'789'), ('bytes=-3', b'789'), ('bytes=8-99', b'89')]:
            with self.subTest(value=value):
                status, headers, data = self.request(value)
                self.assertEqual(status, 206)
                self.assertEqual(data, expected)
                self.assertEqual(int(headers['Content-Length']), len(expected))

    def test_invalid_ignored(self):
        for value in ['bytes=-', 'bytes=0-1junk', 'bytes=0-1,3-4', 'bytes=abc-def', 'items=0-1']:
            with self.subTest(value=value):
                status, _, data = self.request(value)
                self.assertEqual(status, 200)
                self.assertEqual(data, b'0123456789')

    def test_unsatisfiable(self):
        for value in ['bytes=20-', 'bytes=5-2', 'bytes=-0']:
            self.assertEqual(self.request(value)[0], 416)
        self.assertEqual(self.request('bytes=0-', path='/empty.bin')[0], 416)

    def test_head_ignores_range(self):
        status, headers, data = self.request('bytes=2-4', method='HEAD')
        self.assertEqual(status, 200)
        self.assertEqual(int(headers['Content-Length']), 10)
        self.assertEqual(data, b'')


if __name__ == '__main__':
    unittest.main()
