"""Build checked-in UI translations using the explicitly enabled local maintenance route."""
import concurrent.futures,json,os,re,time,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'.local_run/ui_translation_sources.json'
CACHE=ROOT/'.local_run/ui-locales'
LOCALES=['zh-TW','ja','ko','ar','es','fr','de','pt','ru']
def call(locale,ids):
 body=json.dumps({'locale':locale,'ids':ids}).encode()
 req=urllib.request.Request('http://127.0.0.1:8082/api/public-data/agent/ui-localize',data=body,headers={'Content-Type':'application/json'})
 try:
  with urllib.request.urlopen(req,timeout=180) as r:return json.load(r)['strings']
 except urllib.error.HTTPError as exc:raise RuntimeError(exc.read().decode()[:240]) from exc
if __name__=='__main__':
 CACHE.mkdir(exist_ok=True);source=json.loads(SOURCE.read_text());cache={}
 for locale in LOCALES:
  p=CACHE/(locale+'.json');cache[locale]=json.loads(p.read_text()) if p.exists() else {}
  for k,v in source.items():
   if re.fullmatch(r'[A-Z0-9_./+()±−– -]{2,18}',v) or v.startswith('--'):cache[locale].setdefault(k,v)
 jobs=[]
 for locale in LOCALES:
  pending=[k for k in source if k not in cache[locale]]
  batch=[];chars=0
  for k in pending:
   if batch and (len(batch)>=110 or chars+len(source[k])>5500):jobs.append((locale,batch));batch=[];chars=0
   batch.append(k);chars+=len(source[k])
  if batch:jobs.append((locale,batch))
 print('Batches',len(jobs),'strings',sum(len(v) for _,v in jobs),flush=True)
 def translate(job):
  locale,ids=job
  for attempt in range(3):
   try:return locale,call(locale,ids)
   except Exception as exc:
    if attempt==2:
     if len(ids)>1:
      middle=len(ids)//2;_,left=translate((locale,ids[:middle]));_,right=translate((locale,ids[middle:]));return locale,left|right
     raise
    print('Retry',locale,len(ids),str(exc)[:130],flush=True);time.sleep(1)
 with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
  futures={pool.submit(translate,job):job for job in jobs}
  errors=[]
  for n,future in enumerate(concurrent.futures.as_completed(futures),1):
   try:
    locale,rows=future.result();cache[locale].update(rows);p=CACHE/(locale+'.json');p.write_text(json.dumps(cache[locale],ensure_ascii=False));print('Done',n,'/',len(jobs),locale,len(cache[locale]),flush=True)
   except Exception as exc:errors.append((futures[future],str(exc)));print('FAILED',str(exc)[:180],flush=True)
 if errors:raise RuntimeError(str(errors)[:500])
 full={text:{locale:cache[locale][k] for locale in LOCALES} for k,text in source.items()}
 import subprocess,sys
 subprocess.run([sys.executable,str(ROOT/'webapp/scripts/compile_ui_locales.py')],check=True)
 print('COMPLETE',len(full),'strings x',len(LOCALES),'locales',flush=True)
