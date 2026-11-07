import hashlib
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).parents[1]/'scripts'))
import processed_data
import install_matrix_panel

URL='https://ftp.ncbi.nlm.nih.gov/geo/series/GSE60nnn/GSE60450/suppl/counts.h5ad'
SOFT=('!Series_title = example\n!Series_supplementary_file = '+URL+'\n').encode()
class Response(io.BytesIO):
    def __init__(self,data=b'',status=200,headers=None,permit_read=False):super().__init__(data);self.status=status;self.headers=headers or {};self.permit_read=permit_read
    def read(self,*a):
        if not self.permit_read:raise AssertionError('Probe must not read the file body')
        return super().read(*a)
class ProbeTests(unittest.TestCase):
    def test_longer_head_budget_and_large_file_size(self):
        calls=[]
        class Opener:
            def open(self,req,timeout):
                calls.append((req.get_method(),timeout))
                return Response(SOFT,permit_read=True) if len(calls)==1 else Response(headers={'Content-Length':str(64*1024**2)})
        with patch('processed_data.build_opener',return_value=Opener()):value=processed_data.discover('GSE60450')
        self.assertEqual(value['files'][0]['bytes'],64*1024**2);self.assertEqual(calls[1][0],'HEAD');self.assertGreater(calls[1][1],5)
    def test_unknown_head_falls_back_to_range_headers_only(self):
        calls=[]
        class Opener:
            def open(self,req,timeout):
                calls.append(req)
                if len(calls)==1:return Response(SOFT,permit_read=True)
                if len(calls)==2:return Response()
                return Response(status=206,headers={'Content-Range':'bytes 0-0/513592','Content-Length':'1'})
        with patch('processed_data.build_opener',return_value=Opener()):value=processed_data.discover('GSE60450')
        self.assertEqual(value['files'][0]['bytes'],513592);self.assertEqual(calls[-1].get_header('Range'),'bytes=0-0')
    def test_failed_probe_keeps_size_unknown_never_guesses(self):
        class Opener:
            n=0
            def open(self,req,timeout):
                self.n+=1
                if self.n==1:return Response(SOFT,permit_read=True)
                raise OSError('unavailable')
        with patch('processed_data.build_opener',return_value=Opener()):value=processed_data.discover('GSE60450')
        self.assertIsNone(value['files'][0]['bytes'])
class InstallTests(unittest.TestCase):
    def test_unknown_server_refused_without_mutation(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            for name in ['matrix_api.py','matrix_downloads.py','metadata_proxy.py','public_data_server.py']:
                p=root/'webapp/scripts'/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('unknown')
            p=root/'webapp/frontend/js/matrix_panel.js';p.parent.mkdir(parents=True);p.write_text('source')
            with self.assertRaises(ValueError):install_matrix_panel.apply(root)
            self.assertEqual((root/'webapp/scripts/public_data_server.py').read_text(),'unknown')
    def test_exact_source_hook_backup_and_idempotency(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);original='class Handler: pass\n\ndef make_server(port=8081): pass\n'
            for name in ['matrix_api.py','matrix_downloads.py','metadata_proxy.py','public_data_server.py']:
                p=root/'webapp/scripts'/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(original if name=='public_data_server.py' else 'source')
            p=root/'webapp/frontend/js/matrix_panel.js';p.parent.mkdir(parents=True);p.write_text('source')
            with patch.object(install_matrix_panel,'EXPECTED',hashlib.sha256(original.encode()).hexdigest()):
                self.assertTrue(install_matrix_panel.apply(root,check=True)['ready']);self.assertFalse((root/'.local_run').exists())
                install_matrix_panel.apply(root);self.assertTrue(install_matrix_panel.apply(root)['already_installed'])
            self.assertEqual(len(list((root/'.local_run/verification').glob('*/public_data_server.py'))),1)
            self.assertEqual((root/'README.md').read_text().count('## Local matrix download panel'),1)
if __name__=='__main__':unittest.main()
