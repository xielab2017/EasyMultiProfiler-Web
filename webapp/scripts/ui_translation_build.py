"""Explicit local maintenance build: translate registered public UI literals only."""
import json,os,re,threading
from pathlib import Path
import model_settings
ROOT=Path(__file__).resolve().parents[2]
SOURCES=ROOT/'.local_run/ui_translation_sources.json'
LOCALES={'en':'English','zh-TW':'Traditional Chinese','ja':'Japanese','ko':'Korean','ar':'Arabic','es':'Spanish','fr':'French','de':'German','pt':'Portuguese','ru':'Russian'}
SLOTS=threading.BoundedSemaphore(6)
def translate(value):
 if os.environ.get('EMP_UI_TRANSLATION_BUILD')!='1':raise ValueError('UI build is disabled')
 if not isinstance(value,dict) or set(value)!={'locale','ids'} or value['locale'] not in LOCALES:raise ValueError('Invalid UI build')
 ids=value['ids']
 if not isinstance(ids,list) or not 0<len(ids)<=180 or any(not isinstance(k,str) for k in ids):raise ValueError('Invalid UI batch')
 source=json.loads(SOURCES.read_text());rows={k:source[k] for k in ids}
 runtime=model_settings.active()
 if not runtime:raise ValueError('Load a model first')
 import agent_adapter
 messages=[{'role':'system','content':'Translate public scientific software UI labels. Return ONLY a JSON object with the exact input IDs and translated values. Preserve all {placeholders}, HTML tags, URLs, code snippets, CLI flags, package names, model names, scientific abbreviations and numeric thresholds. Do not add explanations. Translate every human-readable label and sentence naturally; retain named software and scientific abbreviations.'},{'role':'user','content':'UI scope: interpretation; registered step: ui-translation.\nTranslate these registered UI strings (English or Chinese source) into '+LOCALES[value['locale']]+'.\n'+json.dumps(rows,ensure_ascii=False)}]
 with SLOTS:
  result=agent_adapter._request(messages,runtime['key'],runtime['model'],final_only=True,provider=runtime['provider'],endpoint=runtime['endpoint'],protocol=runtime['protocol'],reasoning_effort='low' if runtime['provider'] in {'minimax','nvidia','openai','claude','gemini'} else 'auto',max_output_tokens=16384)
 text=result.get('content','').strip();text=re.sub(r'^```(?:json)?\s*|\s*```$','',text)
 out=json.loads(text,strict=False)
 if not isinstance(out,dict) or set(out)!=set(rows):raise ValueError('Translation IDs differ')
 for key,original in rows.items():
  new=out[key]
  if not isinstance(new,str) or not new.strip():raise ValueError('Empty translation')
  if value['locale'] in {'en','ko','ar','es','fr','de','pt','ru'} and re.search('[\u4e00-\u9fff]',new):raise ValueError('Untranslated Chinese characters: '+key)
  if sorted(re.findall(r'\{[^{}]+\}',original))!=sorted(re.findall(r'\{[^{}]+\}',new)):raise ValueError('Placeholders changed: '+key)
  if sorted(re.findall(r'</?[^>]+>',original))!=sorted(re.findall(r'</?[^>]+>',new)):raise ValueError('HTML changed: '+key)
 return {'locale':value['locale'],'strings':out,'model':runtime['model']}
