#!/usr/bin/env python3
"""Check tutorial media, caption coverage and evidence without browser automation."""
from pathlib import Path
import hashlib,json,subprocess
BASE=Path(__file__).resolve().parent
p=BASE/'emp_metadata_walkthrough.mp4'
info=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(p)]))
v=next(x for x in info['streams'] if x['codec_type']=='video')
a=next(x for x in info['streams'] if x['codec_type']=='audio')
assert (v['width'],v['height'])==(1280,720)
assert v['codec_name']=='h264' and a['codec_name']=='aac'
subprocess.run(['ffmpeg','-v','error','-i',str(p),'-f','null','-'],check=True)
t=json.loads((BASE/'timeline.json').read_text())
for i,c in enumerate(t):
 assert c['end']>c['start']
 if i: assert abs(c['start']-t[i-1]['end'])<0.002
assert abs(float(info['format']['duration'])-t[-1]['end'])<0.25
for lang in ['en','zh']:
 txt=(BASE/f'emp_metadata_walkthrough.{lang}.vtt').read_text()
 assert txt.startswith('WEBVTT') and txt.count(' --> ')==len(t)
 for c in t: assert c[lang] in txt
z=json.loads((BASE/'assets/evidence/GSE60450.download-check.json').read_text())
assert z['inspection']['feature_rows']==27179
assert len(z['inspection']['column_labels'])==12
assert z['inspection']['data_type']=='count_like_unverified'
assert z['inspection']['deseq2_ready'] is False
x=json.loads((BASE/'assets/evidence/synthetic-plan-validation.json').read_text())
assert x['valid'] is True and x['executable'] is False
x=json.loads((BASE/'assets/evidence/agent-status.json').read_text())
assert x['status']=='unconfigured' and x['enabled'] is False
raw=p.read_bytes()
assert raw.find(b'moov')>0 and raw.find(b'moov')<raw.find(b'mdat')
report={'file':p.name,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'duration_seconds':float(info['format']['duration']),'video':{'codec':v['codec_name'],'width':v['width'],'height':v['height'],'fps':v['r_frame_rate']},'audio':{'codec':a['codec_name'],'sample_rate':a['sample_rate'],'channels':a['channels']},'cue_count':len(t),'chapter_count':len(set(c['scene'] for c in t)),'full_decode':'passed','caption_timings_and_content':'passed','evidence_assertions':'passed','fast_start':'passed','presentation':'original illustrated slides, not screen recording','browser_playback':'not verified; local service unavailable to cloud browser','http_range':'integration-owned check'}
(BASE/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
(BASE/'ffprobe.json').write_text(json.dumps(info,indent=2)+'\n')
print(json.dumps(report,indent=2))
