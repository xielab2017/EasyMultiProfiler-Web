"""Compile validated translation batches; this command performs no network requests."""
import hashlib,json,re
from pathlib import Path
from opencc import OpenCC
ROOT=Path(__file__).resolve().parents[2]
LOCALES=['zh-TW','ja','ko','ar','es','fr','de','pt','ru']
if __name__=='__main__':
 source=json.loads((ROOT/'.local_run/ui_translation_sources.json').read_text());known=json.loads((ROOT/'.local_run/ui_zh_known.json').read_text())
 cache={locale:json.loads((ROOT/'.local_run/ui-locales'/f'{locale}.json').read_text()) for locale in LOCALES};cc=OpenCC('t2s')
 full={}
 for key,text in source.items():
  row={locale:cache[locale][key] for locale in LOCALES};row['zh']=known.get(text,cc.convert(row['zh-TW']))
  if sorted(re.findall(r'\{[^{}]+\}',text))!=sorted(re.findall(r'\{[^{}]+\}',row['zh'])):row['zh']=cc.convert(row['zh-TW'])
  full[text]=row
  for locale,value in row.items():
   if sorted(re.findall(r'\{[^{}]+\}',text))!=sorted(re.findall(r'\{[^{}]+\}',value)):raise ValueError(f'Placeholder mismatch {key} {locale}')
 target=ROOT/'webapp/frontend/js/ui_locales_full.mjs';target.write_text('export const UI_LOCALES_FULL = '+json.dumps(full,ensure_ascii=False,separators=(',',':'))+';\n')
 manifest={'source_strings':len(full),'locales':['en','zh',*LOCALES],'source_sha256':hashlib.sha256(json.dumps(source,sort_keys=True).encode()).hexdigest(),'method':'LLM translation with placeholder/tag validation; existing Chinese text retained; OpenCC used for additional Simplified Chinese strings.'}
 (ROOT/'.local_run/verification/ui-locales-manifest.json').write_text(json.dumps(manifest,indent=2));print('Compiled',len(full),'strings, 11 locales')
