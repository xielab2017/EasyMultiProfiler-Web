import gzip
import hashlib
import http.client
import io
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
import uuid
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).parents[1]/'scripts'))
import matrix_api
import matrix_downloads
import metadata_proxy
import processed_data

URL='https://ftp.ncbi.nlm.nih.gov/geo/series/GSE60nnn/GSE60450/suppl/counts.tsv.gz'
BODY=gzip.compress(b'gene\tLength\ta\tb\nf1\t100\t1\t2\n',mtime=0)
class Response(io.BytesIO):
    status=200
    def __init__(self,data=BODY):super().__init__(data);self.headers={'Content-Length':str(len(data)),'ETag':'"fixture"'}
    def geturl(self):return URL
class Opener:
    def open(self,request,timeout):return Response()
class Store:
    def __init__(self):self.items={}
    def put(self,x):key=str(uuid.uuid4());self.items[key]=x;return key
    def get(self,k):return self.items[k]
class MatrixAPI(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();root=Path(self.tmp.name)
        class Handler(BaseHTTPRequestHandler):
            def valid_origin(self):return self.headers.get('Host')==f'127.0.0.1:{self.server.server_port}'
            def reply(self,status,value):
                raw=json.dumps(value).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
            def do_POST(self):return self.reply(404,{'legacy':True})
            def do_GET(self):return self.reply(404,{'legacy':True})
            def log_message(self,*a):pass
        matrix_api.install(Handler,root)
        self.server=ThreadingHTTPServer(('127.0.0.1',0),Handler);self.server.store=Store()
        self.server.matrix_download_manager=matrix_downloads.MatrixDownloadManager(root/'downloads',opener=Opener())
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
        self.manifest=self.server.store.put({'accession':'GSE60450','status':'processed_candidates','maximum_download_bytes':32*1024**2,'files':[{'id':'0','name':'counts.tsv.gz','url':URL,'bytes':len(BODY),'checksum':None}]})
    def tearDown(self):self.server.shutdown();self.thread.join();self.server.server_close();self.tmp.cleanup()
    def call(self,op,data):
        c=http.client.HTTPConnection('127.0.0.1',self.server.server_port,timeout=5);c.request('POST','/api/public-data/'+op,json.dumps(data),{'Content-Type':'application/json'});r=c.getresponse();raw=r.read();c.close();return r.status,json.loads(raw)
    def completed(self):
        code,p=self.call('matrix/plan',{'manifest_id':self.manifest,'file_id':'0','max_bytes':1024**3});self.assertEqual(code,200)
        code,job=self.call('matrix/start',{'plan_id':p['plan_id'],'plan_sha256':p['plan_sha256'],'confirmed':True});self.assertEqual(code,200)
        self.server.matrix_download_manager.wait(job['job_id'],timeout=5)
        return job['job_id']
    def test_complete_matrix_contract_preview_range_and_head(self):
        key=self.completed();code,job=self.call('matrix/status',{'job_id':key});self.assertEqual(job['status'],'completed');self.assertEqual(job['receipt']['sha256'],hashlib.sha256(BODY).hexdigest())
        code,preview=self.call('matrix/preview',{'job_id':key});self.assertEqual(code,200);self.assertEqual(preview['inspection']['column_labels'],['a','b']);self.assertFalse(preview['inspection']['raw_count_provenance_verified'])
        for method,headers,status,length in [('GET',{},200,len(BODY)),('GET',{'Range':'bytes=0-9'},206,10),('HEAD',{},200,0)]:
            c=http.client.HTTPConnection('127.0.0.1',self.server.server_port);c.request(method,'/api/public-data/matrix/files/'+key,headers=headers);r=c.getresponse();self.assertEqual(r.status,status);self.assertEqual(len(r.read()),length);c.close()
    def test_reject_arbitrary_url_and_missing_consent(self):
        code,_=self.call('matrix/plan',{'manifest_id':self.manifest,'file_id':'0','url':'https://evil.test'});self.assertEqual(code,400)
        _,p=self.call('matrix/plan',{'manifest_id':self.manifest,'file_id':'0','max_bytes':1024**3});code,_=self.call('matrix/start',{'plan_id':p['plan_id'],'plan_sha256':p['plan_sha256'],'confirmed':False});self.assertEqual(code,400)
    def test_history_retains_completed_download_and_has_no_resumption_side_effect(self):
        key=self.completed();manager=self.server.matrix_download_manager
        before=(manager.root/key/'job.json').read_bytes()
        code,data=self.call('matrix/history',{});self.assertEqual(code,200);self.assertEqual(data['jobs'][0]['job_id'],key)
        self.assertEqual(data['jobs'][0]['status'],'completed');self.assertNotIn('plan',data['jobs'][0])
        self.assertEqual((manager.root/key/'job.json').read_bytes(),before)
        c=http.client.HTTPConnection('127.0.0.1',self.server.server_port)
        c.request('POST','/api/public-data/matrix/history','{}',{'Content-Type':'application/json','X-Forwarded-Host':'public.example'})
        r=c.getresponse();r.read();self.assertEqual(r.status,403);c.close()
    def test_old_routes_untouched_and_annotation_labels_forwarded(self):
        code,_=self.call('old-feature',{});self.assertEqual(code,404)
        with patch.object(processed_data,'fetch_annotations',return_value={'records':[{'accession':'GSM1','descriptions':['s1']}],'source_url':'official','sha256':'a'*64}) as fetch:
            code,value=self.call('processed/annotations',{'accession':'GSE60450','columns':['s1']});self.assertEqual(code,200);fetch.assert_called_once_with('GSE60450',labels=['s1']);self.assertEqual(value['matches'][0]['status'],'exact')
    def test_provenance_attachment_is_bounded_snapshot_and_head(self):
        source={'records':[{'accession':'GSM1','descriptions':['s1']}],'source_url':'official','sha256':'a'*64}
        with patch.object(processed_data,'fetch_annotations',return_value=source):
            code,value=self.call('processed/annotations',{'accession':'GSE60450','columns':['s1']})
        self.assertEqual(code,200);path=value['provenance_download_url']
        for method in ('GET','HEAD'):
            c=http.client.HTTPConnection('127.0.0.1',self.server.server_port);c.request(method,path);r=c.getresponse();data=r.read()
            self.assertEqual(r.status,200);self.assertIn('attachment;',r.getheader('Content-Disposition'));self.assertIn('GSE60450_sample_provenance.json',r.getheader('Content-Disposition'));self.assertGreater(int(r.getheader('Content-Length')),0)
            if method=='GET':self.assertEqual(json.loads(data)['matches'][0]['status'],'exact')
            else:self.assertEqual(data,b'')
            c.close()
        for invalid in ['/api/public-data/matrix/exports/../../data','/api/public-data/matrix/exports/'+self.manifest]:
            c=http.client.HTTPConnection('127.0.0.1',self.server.server_port);c.request('GET',invalid);r=c.getresponse();r.read();self.assertEqual(r.status,404);c.close()

    def test_provenance_through_same_origin_proxy(self):
        with patch.object(processed_data,'fetch_annotations',return_value={'records':[],'source_url':'official','sha256':'a'*64}):
            _,value=self.call('processed/annotations',{'accession':'GSE60450','columns':[]})
        class ProxyHandler(BaseHTTPRequestHandler):
            def do_GET(self):metadata_proxy.proxy(self)
            def do_HEAD(self):metadata_proxy.proxy(self)
            def log_message(self,*a):pass
        proxy=ThreadingHTTPServer(('127.0.0.1',0),ProxyHandler);proxy.metadata_port=self.server.server_port
        thread=threading.Thread(target=proxy.serve_forever,daemon=True);thread.start()
        try:
            for method in ('GET','HEAD'):
                c=http.client.HTTPConnection('127.0.0.1',proxy.server_port);c.request(method,value['provenance_download_url']);r=c.getresponse();raw=r.read()
                self.assertEqual(r.status,200);self.assertIn('attachment',r.getheader('Content-Disposition'));self.assertGreater(int(r.getheader('Content-Length')),0)
                if method=='GET':self.assertEqual(json.loads(raw)['source_url'],'official')
                else:self.assertEqual(raw,b'')
                c.close()
        finally:proxy.shutdown();thread.join();proxy.server_close()

    def test_preview_is_bounded_and_unsupported_format_preserved(self):
        value=matrix_api.preview(io.BytesIO(b'gene\tx\na\t1\n'+b'a\t1\n'*100000),'large.tsv');self.assertLessEqual(value['preview_rows'],100);self.assertLessEqual(value['preview_bytes'],256*1024);self.assertFalse(value['complete_file_inspected'])
        value=matrix_api.preview(io.BytesIO(b'archive'),'matrix.tar');self.assertEqual(value['inspection'],'original_file_only_format_not_previewed')

class ProxyStream(unittest.TestCase):
    def test_streams_over_old_34mib_cap_without_large_reads(self):
        size=40*1024*1024
        class Result:
            status=200
            def __init__(self):self.left=size
            def getheader(self,key):return str(size) if key=='Content-Length' else 'application/octet-stream' if key=='Content-Type' else None
            def read(self,n):
                self.assertBound(n);n=min(n,self.left);self.left-=n;return b'x'*n
            def assertBound(self,n):assert n<=65536
        class Conn:
            def __init__(self,*a,**k):pass
            def request(self,*a,**k):pass
            def getresponse(self):return Result()
            def close(self):pass
        class Sink:
            count=0
            def write(self,b):self.count+=len(b)
        class Handler:
            path='/api/public-data/matrix/files/12345678-1234-4234-8234-123456789abc';command='GET';headers={'Host':'127.0.0.1:8080'};server=type('S',(),{'metadata_port':8081,'server_address':('127.0.0.1',8080)})();connection=type('C',(),{'settimeout':lambda *a:None})();rfile=io.BytesIO();wfile=Sink()
            def send_response(self,status):self.status=status
            def send_header(self,*a):pass
            def end_headers(self):pass
        handler=Handler()
        with patch('metadata_proxy.http.client.HTTPConnection',Conn):self.assertTrue(metadata_proxy.proxy(handler))
        self.assertEqual(handler.status,200);self.assertEqual(handler.wfile.count,size)

if __name__=='__main__':unittest.main()
