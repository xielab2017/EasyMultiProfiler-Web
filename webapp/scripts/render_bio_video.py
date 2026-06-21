#!/usr/bin/env python3
"""Render CNS-style bio-animation micro-lesson videos (~5 min each).

Uses teaching_anim_v2.json + anim_template_bio.html + edge-tts SSML (Yunxi).
"""
import asyncio
import json
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ANIM = ROOT / "webapp" / "data" / "teaching_anim_v2.json"
TEMPLATE = ROOT / "webapp" / "scripts" / "anim_template_bio.html"
OUT_DIR = ROOT / "webapp" / "frontend" / "videos"
TMP_ROOT = Path(tempfile.gettempdir()) / "emp_anim_bio"

VOICE = "zh-CN-YunxiNeural"   # warm documentary narrator
RATE = "-6%"                     # natural but not too slow
PITCH = "+0Hz"
TAIL = 0.65                      # pause between scenes

import edge_tts  # noqa: E402
from playwright.sync_api import sync_playwright  # noqa: E402


def probe(path):
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                        "-of", "csv=p=0", str(path)], capture_output=True, text=True)
    return float(r.stdout.strip() or 0)


def to_ssml(text: str) -> str:
    """Light SSML: prosody only, no per-comma breaks (keeps ~5 min target)."""
    text = text.strip()
    text = text.replace("因此", "所以").replace("此外", "另外").replace("然而", "不过")
    # one short pause mid-text if long
    if len(text) > 120:
        mid = text.find("。", len(text) // 3)
        if mid > 0:
            text = text[: mid + 1] + '<break time="350ms"/>' + text[mid + 1 :]
    return (
        f'<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="zh-CN">'
        f'<voice name="{VOICE}"><prosody rate="{RATE}" pitch="{PITCH}">{text}</prosody></voice></speak>'
    )


async def _synth(text, out):
    ssml = to_ssml(text)
    await edge_tts.Communicate(ssml, VOICE).save(str(out))


def synth(text, out):
    asyncio.run(_synth(text, out))


def scene_audio(mp3, wav, tail=TAIL):
    dur = probe(mp3) + tail
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(mp3),
                    "-af", f"apad=pad_dur={tail}", "-t", f"{dur:.3f}",
                    "-ar", "44100", "-ac", "2", str(wav)], check=True)
    return dur


def silence(wav, seconds):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi",
                    "-i", "anullsrc=r=44100:cl=stereo", "-t", f"{max(0.05, seconds):.3f}",
                    str(wav)], check=True)


def concat_audio(wavs, out):
    lst = out.with_suffix(".txt")
    lst.write_text("".join(f"file '{w}'\n" for w in wavs))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0",
                    "-i", str(lst), "-c", "copy", str(out)], check=True)


def record(html_path, total, out_webm):
    vdir = out_webm.parent
    with sync_playwright() as p:
        browser = p.chromium.launch(args=["--force-color-profile=srgb"])
        ctx = browser.new_context(
            viewport={"width": 1280, "height": 720},
            device_scale_factor=1,
            record_video_dir=str(vdir),
            record_video_size={"width": 1280, "height": 720},
        )
        page = ctx.new_page()
        t0 = time.monotonic()
        page.goto(html_path)
        page.wait_for_function("window.__ready === true", timeout=20000)
        page.evaluate("window.START()")
        lead = time.monotonic() - t0
        page.wait_for_function("window.__done === true", timeout=int((total + 30) * 1000))
        time.sleep(0.4)
        vid_path = page.video.path()
        ctx.close()
        browser.close()
    Path(vid_path).replace(out_webm)
    return lead


def build_module(mid, spec):
    tmp = TMP_ROOT / mid
    tmp.mkdir(parents=True, exist_ok=True)
    scenes = spec["scenes"]

    durations, wavs = [], []
    for i, sc in enumerate(scenes):
        mp3 = tmp / f"s{i}.mp3"
        synth(sc["narration"], mp3)
        wav = tmp / f"s{i}.wav"
        durations.append(scene_audio(mp3, wav))
        wavs.append(wav)

    data = {
        "omics": spec.get("omics", ""),
        "step_label": spec.get("step_label", ""),
        "footnote": spec.get("footnote", "原创科普动画 · 中文配音"),
        "title_first": spec.get("title_first", True),
        "scenes": [{k: sc.get(k) for k in ("eyebrow", "heading", "caption", "subtitle", "points", "visual")} for sc in scenes],
        "durations": durations,
    }
    html = TEMPLATE.read_text(encoding="utf-8").replace("/*__DATA__*/", json.dumps(data, ensure_ascii=False))
    html_file = tmp / "scene.html"
    html_file.write_text(html, encoding="utf-8")

    total = sum(durations)
    webm = tmp / "raw.webm"
    lead = record(html_file.as_uri(), total, webm)

    sil = tmp / "lead.wav"
    silence(sil, lead)
    voice = tmp / "voice.wav"
    concat_audio([sil] + wavs, voice)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"{mid}.mp4"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(webm), "-i", str(voice),
                    "-c:v", "libx264", "-preset", "medium", "-pix_fmt", "yuv420p", "-r", "30",
                    "-vf", "scale=1280:720", "-c:a", "aac", "-b:a", "192k",
                    "-shortest", str(out)], check=True)
    print(f"  {mid}.mp4  ({probe(out):.0f}s, {len(scenes)} scenes, lead {lead:.2f}s)")


def main():
    specs = json.loads(ANIM.read_text(encoding="utf-8"))
    target = sys.argv[1] if len(sys.argv) > 1 else "all"
    ids = list(specs) if target == "all" else [target]
    for mid in ids:
        if mid not in specs:
            print(f"skip unknown module {mid}")
            continue
        print(f"rendering {mid} ...")
        build_module(mid, specs[mid])


if __name__ == "__main__":
    main()
