#!/usr/bin/env python3
"""Add only the reviewed matrix hook to a known legacy metadata server; no processes/network."""
import argparse
from datetime import datetime,timezone
import hashlib
import json
from pathlib import Path
import shutil

EXPECTED='33f2cad4f0278bab4de389f03ba6d9374cd2541761ec4ffa17b93630b72228e9'
HOOK='\nimport matrix_api\nmatrix_api.install(Handler, ROOT)\n'
NOTE='''\n\n## Local matrix download panel (unreleased)\n\nThe main application now contains a Matrix download navigation page. It searches GEO, selects a supplementary original file, shows the exact source and a user-selected byte budget, downloads in the background, streams the saved file through the same-origin main page, and retrieves source-preserving sample annotations. No raw-read processing, AI request or R analysis is triggered. Default per-file budget is 5 GiB, adjustable up to 100 GiB subject to available disk and a 1 GiB reserve. Formats may be downloaded unchanged; archives are not automatically extracted. Preview/annotation limits are independent from file download limits. See docs/MATRIX_MAIN_PANEL.md for operation, safety and validation limits. This local increment has not been pushed to GitHub.\n'''

def apply(root,check=False):
    root=Path(root).resolve();target=root/'webapp/scripts/public_data_server.py'
    if target.is_symlink() or not target.is_file():raise ValueError('Expected a regular metadata server source file')
    for relative in ['webapp/scripts/matrix_api.py','webapp/scripts/matrix_downloads.py','webapp/scripts/metadata_proxy.py','webapp/frontend/js/matrix_panel.js']:
        if not (root/relative).is_file():raise ValueError('Copy and verify all matrix package source files first')
    original=target.read_bytes();text=original.decode();already=HOOK.strip() in text
    if not already and hashlib.sha256(original).hexdigest()!=EXPECTED:raise ValueError('Metadata server source changed; inspect manually before applying this exact hook')
    marker='\ndef make_server('
    if not already and text.count(marker)!=1:raise ValueError('Expected one make_server definition')
    if check:return {'ready':True,'already_installed':already,'source_sha256':hashlib.sha256(original).hexdigest(),'processes_changed':False}
    if not already:
        base=root/'.local_run'
        if base.is_symlink():raise ValueError('Refusing a symlinked backup directory')
        backup=base/'verification'/('matrix_hook_backup_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
        backup.mkdir(parents=True);shutil.copy2(target,backup/target.name)
        target.write_text(text.replace(marker,HOOK+marker,1))
    readme=root/'README.md'
    if readme.is_symlink():raise ValueError('Refusing a symlinked README')
    content=readme.read_text() if readme.exists() else ''
    if '## Local matrix download panel (unreleased)' not in content:readme.write_text(content+NOTE)
    return {'installed':True,'already_installed':already,'source_sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'processes_changed':False,'r_changed':False}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('project_root');parser.add_argument('--check',action='store_true');args=parser.parse_args()
    print(json.dumps(apply(args.project_root,args.check),indent=2))
