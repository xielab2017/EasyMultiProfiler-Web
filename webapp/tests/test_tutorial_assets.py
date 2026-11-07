"""Tutorial routes: real HTTP, synthetic media, no external services."""
import http.client
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
import public_data_server as s

class TutorialTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        videos = self.root / 'webapp/frontend/videos'; videos.mkdir(parents=True)
        (videos / 'emp_metadata_walkthrough.mp4').write_bytes(b'0123456789')
        (videos / 'emp_metadata_walkthrough.en.vtt').write_text('WEBVTT\n')
        self.patch = patch.object(s, 'ROOT', self.root); self.patch.start()
        self.server = s.make_server(0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True); self.thread.start()
    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join()
        self.patch.stop(); self.temp.cleanup()
    def call(self, path='/videos/emp_metadata_walkthrough.mp4', method='GET', **headers):
        c = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=2)
        c.request(method, path, headers=headers); r = c.getresponse()
        result = r.status, dict(r.getheaders()), r.read(); c.close(); return result
    def test_full_and_head(self):
        status, headers, body = self.call()
        self.assertEqual((status, body), (200, b'0123456789'))
        self.assertEqual(headers['Content-Type'], 'video/mp4')
        self.assertEqual(self.call(method='HEAD')[2], b'')
    def test_seek_and_suffix(self):
        status, headers, body = self.call(Range='bytes=2-4')
        self.assertEqual((status, body), (206, b'234'))
        self.assertEqual(headers['Content-Range'], 'bytes 2-4/10')
        self.assertEqual(self.call(Range='bytes=-2')[2], b'89')
        self.assertEqual(self.call(Range='bytes=10-')[0], 416)
    def test_bad_ranges_and_origin(self):
        for value in ('bytes=-', 'bytes=0-1,4-5', 'bytes='+'9'*100+'-'):
            self.assertEqual(self.call(Range=value)[0], 200)
        self.assertEqual(self.call(Origin='https://evil.test')[0], 403)
    def test_allowlist_and_missing(self):
        self.assertEqual(self.call('/videos/../public_data.html')[0], 404)
        self.assertEqual(self.call('/videos/arbitrary.mp4')[0], 404)
        self.assertEqual(self.call('/videos/emp_metadata_walkthrough.zh.vtt')[0], 404)
        self.assertEqual(self.call('/videos/emp_metadata_walkthrough.en.vtt')[1]['Content-Type'], 'text/vtt; charset=utf-8')

if __name__ == '__main__': unittest.main()
