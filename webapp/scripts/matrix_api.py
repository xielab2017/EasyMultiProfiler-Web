"""Minimal matrix-only routes installed around the existing metadata Handler."""
import csv
import gzip
import io
import json
import re
import threading
import time
from urllib.parse import urlsplit
import processed_data
import matrix_downloads

PREFIX='/api/public-data/'
LOCK=threading.Lock()
MAX_EXPORT_BYTES=2*1024*1024

def manager(handler,root):
    with LOCK:
        if not hasattr(handler.server,'matrix_download_manager'):
            handler.server.matrix_download_manager=matrix_downloads.MatrixDownloadManager(root/'.local_run/matrix_downloads')
        return handler.server.matrix_download_manager

def fields(value,names):
    if not isinstance(value,dict) or set(value)-set(names):raise ValueError('Unsupported matrix request fields')

class PreviewInput:
    def __init__(self,handle):self.handle=handle;self.used=0;self.started=time.monotonic()
    def read(self,n=-1):
        if time.monotonic()-self.started>5:raise ValueError('Preview time limit')
        left=2*1024*1024-self.used
        data=self.handle.read(left+1 if n<0 else min(n,left+1));self.used+=len(data)
        if self.used>2*1024*1024:raise ValueError('Preview compressed-byte limit')
        return data
    def tell(self):return self.used

def preview(handle,name):
    result={'data_type':'unknown','raw_count_provenance_verified':False,'analysis_executed':False,'column_labels':[],
            'warning':'Bounded preview only; filenames and numeric values do not establish raw counts or sample groups.'}
    if not name.lower().endswith(('.txt','.tsv','.csv','.txt.gz','.tsv.gz','.csv.gz')):
        return dict(result,inspection='original_file_only_format_not_previewed')
    try:
        magic=handle.read(2);handle.seek(0)
        reader=gzip.GzipFile(fileobj=PreviewInput(handle)) if magic==b'\x1f\x8b' else handle
        raw=reader.read(256*1024+1)
        if reader is not handle:reader.close()
        truncated=len(raw)>256*1024;raw=raw[:256*1024]
        if truncated:raw=raw.rsplit(b'\n',1)[0]
        text=raw.decode('utf-8-sig');first=next((x for x in text.splitlines() if x and not x.startswith('#')),'')
        if not first:return dict(result,inspection='no_header_in_preview')
        rows=csv.reader(io.StringIO(text),delimiter='\t' if '\t' in first else ',')
        header=next((row for row in rows if row and not row[0].startswith('#')),[])
        if not 2<=len(header)<=5001 or any(len(x)>256 for x in header):return dict(result,inspection='header_exceeds_preview_bounds')
        annotations=[i for i,x in enumerate(header) if i>0 and x.lower() in {'length','gene_length','gene_name','symbol','description'}]
        labels=[x for i,x in enumerate(header) if i>0 and i not in annotations]
        count=0
        for row in rows:
            if count>=100:break
            if row and not row[0].startswith('#'):count+=1
        return dict(result,inspection='bounded_header_preview',column_labels=labels,excluded_annotation_columns=[header[i] for i in annotations],
                    preview_rows=count,preview_bytes=len(raw),complete_file_inspected=False,preview_read_entire_file=not truncated,warning=result['warning']+' Named annotation columns are excluded only from this header preview, never from the downloaded file.')
    except (UnicodeError,OSError,EOFError,csv.Error,ValueError):return dict(result,inspection='unsupported_or_unreadable_preview')

def install(Handler,root):
    if getattr(Handler,'_matrix_routes_installed',False):return
    old_post,old_get=Handler.do_POST,Handler.do_GET
    old_head=getattr(Handler,'do_HEAD',None)
    def post(self):
        path=urlsplit(self.path).path
        annotations=path==PREFIX+'processed/annotations'
        if not path.startswith(PREFIX+'matrix/') and not annotations:return old_post(self)
        if not self.valid_origin():return self.reply(403,{'error':'Origin or host not allowed'})
        if self.headers.get('Transfer-Encoding'):return self.reply(400,{'error':'Transfer encoding unsupported'})
        if self.headers.get('Content-Type','').split(';')[0]!='application/json':return self.reply(415,{'error':'JSON required'})
        try:
            size=int(self.headers.get('Content-Length','0'));limit=512*1024 if annotations else 16384
            if not 0<size<=limit:return self.reply(413,{'error':'Invalid request size'})
            self.connection.settimeout(30);req=json.loads(self.rfile.read(size))
            if path == PREFIX+'matrix/history':
                from workbench_api import local_owner
                fields(req,set())
                if not local_owner(self):return self.reply(403,{'error':'Local owner history required'})
                return self.reply(200,{'jobs':manager(self,root).history()})
            if annotations:
                fields(req,{'accession','columns'});columns=req.get('columns',[])
                if not isinstance(columns,list) or len(columns)>5000 or any(not isinstance(x,str) or len(x)>256 for x in columns):raise ValueError('Bounded column labels required')
                result=processed_data.fetch_annotations(req.get('accession',''),labels=columns)
                result['matches']=processed_data.match_samples(columns,result['records'])
                name=req.get('accession','').upper()+'_sample_provenance.json'
                if not re.fullmatch(r'GSE[0-9]+_sample_provenance\.json',name):raise ValueError('Valid GEO accession required')
                raw=json.dumps(result,ensure_ascii=False,indent=2).encode('utf-8')
                if len(raw)<=MAX_EXPORT_BYTES:
                    key=self.server.store.put({'kind':'matrix_sample_provenance','filename':name,'json_text':raw.decode('utf-8')})
                    result['provenance_download_url']=PREFIX+'matrix/exports/'+key
                    result['provenance_download_note']='Temporary local snapshot; reread annotations if expired or service restarted.'
                else:result['provenance_download_note']='Provenance exceeds the 2 MiB export limit; no attachment created.'
                return self.reply(200,result)
            op=path.removeprefix(PREFIX+'matrix/');m=manager(self,root)
            if op=='resolve':
                fields(req,{'accession'});accession=req.get('accession','')
                if re.fullmatch(r'GSE[0-9]{1,9}',accession):manifest=processed_data.discover(accession)
                elif re.fullmatch(r'PXD[0-9]{5,9}',accession):
                    import repository_files
                    found=repository_files.pride_files(accession)
                    manifest={'accession':accession,'repository':'PRIDE','status':'processed_candidates','sample_accessions':[],'title':accession,'files':[{'id':str(i),'name':r['name'],'url':r['url'],'bytes':r['size_bytes'],'format_hint':'tabular_candidate','checksum':None} for i,r in enumerate(found['files'])]}
                else:raise ValueError('Automatic managed downloads currently accept public GEO GSE or PRIDE PXD accessions; no arbitrary URLs')
                return self.reply(200,{'manifest':manifest,'manifest_id':self.server.store.put(manifest)})
            if op=='plan':
                fields(req,{'manifest_id','file_id','max_bytes'});key=req.get('manifest_id')
                if not isinstance(key,str):raise ValueError('Stored matrix manifest required')
                manifest=self.server.store.get(key)
                plan=m.plan(manifest,req.get('file_id'),max_bytes=req.get('max_bytes'))
                key=self.server.store.put({'kind':'matrix_download_plan','plan':plan})
                return self.reply(200,{'plan_id':key,'plan_sha256':plan['plan_sha256'],'plan':plan})
            if op=='start':
                fields(req,{'plan_id','confirmed','plan_sha256'});item=self.server.store.get(req.get('plan_id'))
                if item.get('kind')!='matrix_download_plan':raise ValueError('Stored matrix plan required')
                return self.reply(200,m.start(item['plan'],confirmed=req.get('confirmed') is True,plan_sha256=req.get('plan_sha256')))
            if op in {'status','cancel','resume','preview'}:
                fields(req,{'job_id','confirmed','plan_sha256'} if op=='resume' else {'job_id'})
                key=req.get('job_id')
                if op=='status':return self.reply(200,m.get(key))
                if op=='cancel':return self.reply(200,m.cancel(key))
                if op=='resume':return self.reply(200,m.resume(key,confirmed=req.get('confirmed') is True,plan_sha256=req.get('plan_sha256')))
                handle,receipt=m.open_completed(key)
                try: result=preview(handle,receipt['source_name'])
                finally:handle.close()
                return self.reply(200,{'job_id':key,'source_sha256':receipt['sha256'],'inspection':result})
            return self.reply(404,{'error':'Unknown matrix operation'})
        except (ValueError,TypeError,KeyError,OSError) as exc:return self.reply(400,{'error':str(exc)})
    def get(self):
        path=urlsplit(self.path).path
        if not path.startswith((PREFIX+'matrix/files/',PREFIX+'matrix/exports/')):return old_get(self)
        if not self.valid_origin():return self.reply(403,{'error':'Origin or host not allowed'})
        if path.startswith(PREFIX+'matrix/exports/'):
            try:
                key=path.removeprefix(PREFIX+'matrix/exports/')
                if not re.fullmatch(r'[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}',key):raise ValueError('Invalid export ID')
                item=self.server.store.get(key)
                if item.get('kind')!='matrix_sample_provenance' or not re.fullmatch(r'GSE[0-9]+_sample_provenance\.json',item.get('filename','')):raise ValueError('Unavailable provenance export')
                raw=item['json_text'].encode('utf-8')
                if len(raw)>MAX_EXPORT_BYTES:raise ValueError('Export exceeds bounded size')
                self.send_response(200);self.send_header('Content-Type','application/json; charset=utf-8');self.send_header('Content-Disposition',f'attachment; filename="{item["filename"]}"');self.send_header('Content-Length',str(len(raw)));self.send_header('Cache-Control','no-store');self.send_header('X-Content-Type-Options','nosniff');self.end_headers()
                if self.command!='HEAD':self.wfile.write(raw)
                return
            except (ValueError,TypeError,KeyError,OSError):return self.reply(404,{'error':'Provenance snapshot expired or unavailable; reread sample information.'})
        handle=None;headers_sent=False
        try:
            key=path.removeprefix(PREFIX+'matrix/files/');handle,receipt=manager(self,root).open_completed(key)
            size=receipt['bytes'];start,end=0,size-1;status=200
            header=self.headers.get('Range')
            if header:
                match=re.fullmatch(r'bytes=([0-9]*)-([0-9]*)',header)
                if not match or not any(match.groups()):raise ValueError('Invalid byte range')
                left,right=match.groups()
                if left:start=int(left);end=min(int(right),end) if right else end
                else:start=max(0,size-int(right))
                if not 0<=start<=end<size:
                    self.send_response(416);self.send_header('Content-Range',f'bytes */{size}');self.send_header('Content-Length','0');self.end_headers();return
                status=206
            name=re.sub(r'[^A-Za-z0-9._-]','_',receipt['source_name'])[:200] or 'matrix.data'
            self.send_response(status);self.send_header('Content-Type','application/octet-stream');self.send_header('Content-Disposition',f'attachment; filename="{name}"');self.send_header('Content-Length',str(end-start+1));self.send_header('Accept-Ranges','bytes');self.send_header('ETag','"'+receipt['sha256']+'"');self.send_header('X-Content-Type-Options','nosniff')
            if status==206:self.send_header('Content-Range',f'bytes {start}-{end}/{size}')
            self.end_headers();headers_sent=True
            if self.command=='HEAD':return
            handle.seek(start);remaining=end-start+1
            while remaining:
                chunk=handle.read(min(65536,remaining))
                if not chunk:break
                self.wfile.write(chunk);remaining-=len(chunk)
        except (ValueError,TypeError,KeyError,OSError) as exc:
            if not headers_sent:return self.reply(400,{'error':str(exc)})
            self.close_connection=True
        finally:
            if handle is not None:handle.close()
    def head(self):
        if urlsplit(self.path).path.startswith((PREFIX+'matrix/files/',PREFIX+'matrix/exports/')):return get(self)
        if old_head:return old_head(self)
        return self.send_error(405)
    Handler.do_POST=post;Handler.do_GET=get;Handler.do_HEAD=head;Handler._matrix_routes_installed=True
