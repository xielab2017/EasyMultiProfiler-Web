#!/usr/bin/env python3
"""Offline illustrated walkthrough. Requires Pillow, ffmpeg with flite, and CJK fonts.
Does not launch or automate a browser, retrieve data, run R, or call any model.
Reproduces narrated MP4, burned bilingual captions, and separate WebVTT/SRT tracks.
"""
from pathlib import Path
import argparse, json, subprocess, textwrap, hashlib
from PIL import Image, ImageDraw, ImageFont
BASE=Path(__file__).resolve().parent
W,H=1280,720
BG='#0B1322'; CARD='#152238'; INK='#F2F5FA'; MUTED='#B7C8DB'; ACC='#50D7C7'; WARN='#FFCD72'
FREG='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
FBOLD='/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'
MONO='/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'
def font(n,bold=False,mono=False): return ImageFont.truetype(MONO if mono else (FBOLD if bold else FREG),n)
def wrap(s,f,width,draw):
    # Word-aware English; character-aware CJK, preserving explicit newlines.
    out=[]
    for p in s.split('\n'):
        toks=list(p) if any('\u4e00'<=c<='\u9fff' for c in p) else p.split(' ')
        sep='' if toks==list(p) else ' '
        line=''
        for t in toks:
            new=(line+sep+t) if line else t
            if draw.textlength(new,font=f)>width and line: out.append(line); line=t
            else: line=new
        if line: out.append(line)
    return out
def drawtext(d,xy,s,f,width,fill=INK,gap=6):
    x,y=xy
    for line in wrap(s,f,width,d):
        d.text((x,y),line,font=f,fill=fill); y+=f.size+gap
    return y
def panel(d,rect,title,items,accent=False,command=False):
    x,y,x2,y2=rect; d.rounded_rectangle(rect,radius=20,fill=CARD)
    d.rectangle((x,y+22,x+4,y+57),fill=ACC if not accent else WARN)
    drawtext(d,(x+24,y+20),title,font(23,True),x2-x-44,ACC if not accent else WARN)
    yy=y+75
    for item in items:
        fs=20 if command else (21 if accent else 24)
        f=font(fs,mono=command and item.startswith('python'))
        d.ellipse((x+25,yy+12,x+32,yy+19),fill=ACC if not accent else WARN)
        yy=drawtext(d,(x+47,yy),item,f,x2-x-70,MUTED,gap=6)+(14 if accent else 20)
    if yy>y2+4: raise ValueError('Panel overflow: '+title+str(yy))
def frame(scene,cue,idx,total,path):
    im=Image.new('RGB',(W,H),BG); d=ImageDraw.Draw(im)
    d.text((38,18),'EasyMultiProfiler-Web  v9.1.2',font=font(19,True),fill=MUTED)
    d.text((906,20),scene['tag'],font=font(16,True),fill=ACC)
    d.text((38,61),scene['title'],font=font(34,True),fill=INK)
    d.text((39,109),scene['zh_title'],font=font(22),fill=ACC)
    panel(d,(38,159,727,444),scene['left_title'],scene['items'],command=scene['tag'].startswith('02'))
    panel(d,(747,159,1242,444),scene['right_title'],scene['right_items'],True)
    drawtext(d,(40,463),scene['footnote'],font(15),1200,MUTED,5)
    d.text((40,511),'ILLUSTRATED GUIDE  /  图解教程  ·  Not a live screen recording',font=font(15),fill='#93A6BE')
    # Stable caption strip, never covering the teaching cards.
    d.rectangle((0,553,W,H),fill='#030811')
    for j in range(total):
        x=38+j*(1204/total); d.rectangle((x,544,x+1204/total-4,548),fill=ACC if j<=idx else '#2A3B52')
    en=wrap(cue['en'],font(21),1196,d); zh=wrap(cue['zh'],font(24),1196,d)
    if len(en)>3 or len(zh)>2: raise ValueError('Subtitle overflow '+str(idx))
    yy=568
    for ln in en:
        tw=d.textlength(ln,font=font(21)); d.text(((W-tw)/2,yy),ln,font=font(21),fill=INK); yy+=29
    yy=max(yy+5,638)
    for ln in zh:
        tw=d.textlength(ln,font=font(24)); d.text(((W-tw)/2,yy),ln,font=font(24),fill=ACC); yy+=32
    if yy>717: raise ValueError('Subtitle baseline overflow '+str(idx))
    im.save(path)
def run(args): subprocess.run(args,check=True)
def probe(p):
    return float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',str(p)],text=True).strip())
def stamp(sec,sep='.'):
    ms=round(sec*1000); h,ms=divmod(ms,3600000); m,ms=divmod(ms,60000); s,ms=divmod(ms,1000)
    return f'{h:02}:{m:02}:{s:02}{sep}{ms:03}'
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--voice',default='slt'); ap.add_argument('--frames-only',action='store_true'); args=ap.parse_args()
    spec=json.loads((BASE/'storyboard.json').read_text()); out=BASE/'rendered'; out.mkdir(exist_ok=True)
    cues=[(s,c) for s in spec['scenes'] for c in s['cues']]; timeline=[]; cur=0
    for i,(sc,c) in enumerate(cues):
        png=out/f'frame_{i:02}.png'; frame(sc,c,i,len(cues),png)
        if args.frames_only: continue
        txt=out/f'voice_{i:02}.txt'; txt.write_text(c['en']); raw=out/f'raw_{i:02}.wav'; wav=out/f'voice_{i:02}.wav'; mp4=out/f'clip_{i:02}.mp4'
        run(['ffmpeg','-y','-loglevel','error','-f','lavfi','-i',f'flite=textfile={txt}:voice={args.voice}','-af','atempo=0.97','-ar','48000','-ac','1',str(raw)])
        dur=probe(raw)+0.65
        run(['ffmpeg','-y','-loglevel','error','-i',str(raw),'-af','apad=pad_dur=0.65','-t',f'{dur:.6f}','-ar','48000','-ac','1',str(wav)])
        # 12 fps is sufficient for still teaching diagrams. Fixed frame durations avoid drift.
        frames=round(dur*12); dur=frames/12
        run(['ffmpeg','-y','-loglevel','error','-loop','1','-framerate','12','-i',str(png),'-i',str(wav),'-t',f'{dur:.6f}','-c:v','libx264','-preset','medium','-tune','stillimage','-crf','25','-pix_fmt','yuv420p','-r','12','-c:a','aac','-b:a','64k','-movflags','+faststart',str(mp4)])
        timeline.append(dict(index=i,scene=sc['title'],start=round(cur,6),end=round(cur+dur,6),**c)); cur+=dur
        print(f'{i+1}/{len(cues)} {dur:.2f}s {sc["title"]}',flush=True)
    if args.frames_only: return
    lst=out/'concat.txt'; lst.write_text(''.join(f"file '{out/f'clip_{i:02}.mp4'}'\n" for i in range(len(cues))))
    output=BASE/'emp_metadata_walkthrough.mp4'
    run(['ffmpeg','-y','-loglevel','error','-f','concat','-safe','0','-i',str(lst),'-c','copy','-movflags','+faststart',str(output)])
    for lang in ['en','zh']:
        vtt='WEBVTT\n\n'; srt=''
        for i,c in enumerate(timeline):
            vtt+=f'{i+1}\n{stamp(c["start"])} --> {stamp(c["end"])}\n{c[lang]}\n\n'
            srt+=f'{i+1}\n{stamp(c["start"],",")} --> {stamp(c["end"],",")}\n{c[lang]}\n\n'
        (BASE/f'emp_metadata_walkthrough.{lang}.vtt').write_text(vtt)
        (BASE/f'emp_metadata_walkthrough.{lang}.srt').write_text(srt)
    (BASE/'timeline.json').write_text(json.dumps(timeline,ensure_ascii=False,indent=2))
    (BASE/'narration_en.txt').write_text('\n\n'.join(f'{i+1}. {c["en"]}' for i,c in enumerate(timeline)))
    run(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(output)])
    print('OUTPUT',output,'duration',probe(output),'bytes',output.stat().st_size)
if __name__=='__main__': main()
