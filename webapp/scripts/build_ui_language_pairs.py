"""Collect explicit bilingual UI literals. No API calls or user data are read."""
import ast,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]/'frontend/js'
CJK=re.compile('[\u4e00-\u9fff]')
LITERAL=r'''(?:'(?:\\.|[^'\\\n])*'|"(?:\\.|[^"\\\n])*")'''
def load():
 text=(ROOT/'ui_language_catalog.mjs').read_text();return json.loads(text.split('=',1)[1].strip().rstrip(';'))
def collect(pairs):
 for p in [*ROOT.glob('*.js'),*ROOT.glob('*.mjs')]:
  if ' 2.' in p.name or p.name=='ui_language_catalog.mjs':continue
  source=p.read_text()
  for match in re.finditer(r'('+LITERAL+r')\s*,\s*('+LITERAL+r')',source):
   try:a,b=(ast.literal_eval(x) for x in match.groups())
   except (ValueError,SyntaxError):continue
   if CJK.search(a) and not CJK.search(b) and len(b)>2 and '{' not in a and '<' not in a and '<' not in b:pairs.setdefault(b,a)
  for match in re.finditer(LITERAL,source):
   try:value=ast.literal_eval(match.group())
   except (ValueError,SyntaxError):continue
   if not isinstance(value,str) or ' / ' not in value or '<' in value or '{' in value:continue
   left,right=value.rsplit(' / ',1)
   if CJK.search(left) and not CJK.search(right) and re.search('[A-Za-z]{3}',right):
    pairs.setdefault(right,left);pairs.setdefault(value,left)
 return pairs
if __name__=='__main__':
 pairs=collect(load());(ROOT/'ui_language_catalog.mjs').write_text('export const UI_LANGUAGE_PAIRS = '+json.dumps(pairs,ensure_ascii=False,indent=2)+';\n');print(f'{len(pairs)} explicit UI translation pairs')
