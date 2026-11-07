"""Bounded PRIDE project-file metadata, never an arbitrary URL downloader."""
import json,re
from urllib.parse import urlsplit,unquote
from urllib.request import Request,build_opener,HTTPRedirectHandler

class RepositoryError(ValueError):pass
class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):raise RepositoryError('Repository redirect refused')

def pride_files(accession):
    if not isinstance(accession,str) or not re.fullmatch(r'PXD[0-9]{5,9}',accession):raise RepositoryError('Valid PRIDE PXD accession required')
    url=f'https://www.ebi.ac.uk/pride/ws/archive/v2/projects/{accession}/files?pageSize=100&page=0'
    try:
        with build_opener(_NoRedirect()).open(Request(url,headers={'Accept':'application/json','User-Agent':'EasyMultiProfiler/1.0'}),timeout=15) as response:raw=response.read(2*1024*1024+1)
        if len(raw)>2*1024*1024:raise RepositoryError('PRIDE response exceeded the metadata limit')
        records=json.loads(raw)
    except (OSError,ValueError) as error:raise RepositoryError('Unable to read PRIDE project files; open the official project page to continue.') from error
    if not isinstance(records,list):raise RepositoryError('Unexpected PRIDE file response')
    files=[]
    for row in records[:100]:
        if not isinstance(row,dict):continue
        name=row.get('fileName','')
        if not isinstance(name,str) or len(name)>255 or not re.search(r'\.(?:csv|tsv|txt|xlsx|xls|mztab)(?:\.gz)?$',name,re.I):continue
        if re.search(r'\.(?:fastq|fq|sra|bam|cram)(?:\.gz)?$',name,re.I):continue
        for location in row.get('publicFileLocations') or []:
            if not isinstance(location,dict):continue
            value=location.get('value','')
            if not isinstance(value,str):continue
            parsed=urlsplit(value);decoded=unquote(parsed.path)
            if parsed.scheme not in {'ftp','https'} or parsed.hostname!='ftp.pride.ebi.ac.uk' or parsed.query or parsed.fragment or parsed.username or parsed.password:continue
            if not decoded.startswith('/pride/data/archive/') or f'/{accession}/' not in decoded or any(part in {'.','..'} for part in decoded.split('/')) or decoded.rsplit('/',1)[-1]!=name:continue
            size=row.get('fileSizeBytes');size=size if type(size) is int and size>=0 else None
            category = row.get('fileCategory')
            files.append({'name':name,'size_bytes':size,'category':category.get('value','') if isinstance(category,dict) else '', 'url':'https://ftp.pride.ebi.ac.uk'+parsed.path})
            break
    return {'accession':accession,'repository':'PRIDE','source_url':url,'files':files[:30],'records_inspected':len(records[:100]),'may_have_more':len(records)>=100 or len(files)>30,'downloaded':False,'matrix_verified':False}
