"""Synchronize current release labels from DESCRIPTION, preserving historical notes."""
import argparse
import json
import re
from pathlib import Path
from version_source import app_version

ROOT = Path(__file__).resolve().parents[2]
UI_FILES = (
 'webapp/frontend/index.html', 'webapp/frontend/js/guide.js',
 'webapp/frontend/js/locale.js', 'webapp/frontend/js/i18n_catalog.js',
 'webapp/frontend/js/feature_i18n.mjs', 'webapp/frontend/js/ui_language_catalog.mjs',
 'webapp/frontend/js/ui_language_aliases.mjs', 'webapp/frontend/js/ui_locales_full.mjs',
)

def sync_release(root=ROOT, check=False):
 root = Path(root)
 version = app_version(root/'DESCRIPTION')
 outputs = {'webapp/frontend/version.json': json.dumps({'version':version})+'\n'}
 for name in UI_FILES:
  path = root/name
  if path.exists():
   outputs[name] = re.sub(r'\bv9\.\d+\.\d+(?:[-+][\w.-]+)?\b', 'v'+version, path.read_text(), flags=re.I)
 for name in ('README.md', 'README_CN.md', 'README_EN.md'):
  path = root/name
  if not path.exists():
   continue
  text = path.read_text()
  text = re.sub(r'(EasyMultiProfiler Web [· ]*)v9\.\d+\.\d+', r'\g<1>v'+version, text)
  text = re.sub(r'(badge/version-)9\.\d+\.\d+', r'\g<1>'+version, text)
  text = re.sub(r'(\*\*(?:Version:|版本)\*\*[:：]?\s*`)[^`]+', r'\g<1>'+version, text)
  text = re.sub(r'(内部版本 )9\.\d+\.\d+', r'\g<1>'+version, text)
  # Only the leading current-release block changes; older release headings stay intact.
  text = re.sub(r'(?m)^## v9\.\d+\.\d+(?:[^\n]*)', '## v'+version, text, count=1)
  text = re.sub(r'docs/RELEASE_NOTES_v9\.\d+\.\d+\.md', 'docs/RELEASE_NOTES_v'+version+'.md', text, count=1)
  text = re.sub(r'(R package metadata \(version )9\.\d+\.\d+', r'\g<1>'+version, text)
  outputs[name] = text
 changed = [name for name,text in outputs.items() if not (root/name).exists() or (root/name).read_text()!=text]
 if not check:
  for name in changed:
   (root/name).write_text(outputs[name])
 return changed

if __name__ == '__main__':
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--check',action='store_true',help='Report stale release labels without changing files.')
 args=parser.parse_args()
 changed=sync_release(check=args.check)
 if args.check and changed:
  print('Stale release labels: '+', '.join(changed))
  raise SystemExit(1)
 print('Web release metadata synchronized: '+app_version())
