#!/usr/bin/env python3
"""Render animated, neural-narrated micro-lesson videos.

Pipeline per module (from webapp/data/teaching_anim.json):
  1. edge-tts neural voice -> one mp3 per scene; measure durations
  2. inject scenes + per-scene durations into anim_template.html
  3. Playwright records the animated HTML page (1280x720) -> webm
  4. ffmpeg muxes the concatenated neural voiceover (lead-padded for sync) -> mp4

Usage:
  python3 render_anim_video.py m16s_import      # one module
  python3 render_anim_video.py all              # every module in teaching_anim.json
"""
import asyncio
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ANIM = ROOT / "webapp" / "data" / "teaching_anim.json"
TEMPLATE = ROOT / "webapp" / "scripts" / "anim_template.html"
OUT_DIR = ROOT / "webapp" / "frontend" / "videos"
TMP_ROOT = Path(tempfile.gettempdir()) / "emp_anim"

VOICE = "zh-CN-YunxiaNeural"     # lively youthful Mandarin (science-vlogger tone)
RATE = "-4%"                      # slightly slower = clearer
TAIL = 0.45                       # seconds of silence after each scene

import edge_tts  # noqa: E402
from playwright.sync_api import sync_playwright  # noqa: E402


def probe(path):
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                        "-of", "csv=p=0", str(path)], capture_output=True, text=True)
    return float(r.stdout.strip() or 0)


async def _synth(text, out, voice):
    await edge_tts.Communicate(text, voice, rate=RATE).save(str(out))


def synth(text, out):
    asyncio.run(_synth(text, out, VOICE))


def scene_audio(mp3, wav, tail=TAIL):
    """mp3 -> wav padded with `tail` seconds of trailing silence."""
    dur = probe(mp3) + tail
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(mp3),
                    "-af", f"apad=pad_dur={tail}", "-t", f"{dur:.3f}",
                    "-ar", "44100", "-ac", "2", str(wav)], check=True)
    return dur


def silence(wav, seconds):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi",
                    "-i", "anullsrc=r=44100:cl=stereo", "-t", f"{max(0.05,seconds):.3f}",
                    str(wav)], check=True)


def concat_audio(wavs, out):
    lst = out.with_suffix(".txt")
    lst.write_text("".join(f"file '{w}'\n" for w in wavs))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0",
                    "-i", str(lst), "-c", "copy", str(out)], check=True)


def record(html_path, total, out_webm):
    """Play the animation and screen-record it. Returns lead seconds before START."""
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
        page.wait_for_function("window.__ready === true", timeout=15000)
        page.evaluate("window.START()")
        lead = time.monotonic() - t0
        page.wait_for_function("window.__done === true", timeout=int((total + 15) * 1000))
        time.sleep(0.3)
        vid_path = page.video.path()
        ctx.close()
        browser.close()
    Path(vid_path).replace(out_webm)
    return lead


def build_module(mid, spec):
    tmp = TMP_ROOT / mid
    tmp.mkdir(parents=True, exist_ok=True)
    scenes = spec["scenes"]

    # 1) synth audio + durations
    durations, wavs = [], []
    for i, sc in enumerate(scenes):
        mp3 = tmp / f"s{i}.mp3"
        synth(sc["narration"], mp3)
        wav = tmp / f"s{i}.wav"
        durations.append(scene_audio(mp3, wav))
        wavs.append(wav)

    # 2) inject into template
    data = {
        "omics": spec.get("omics", ""),
        "step_label": spec.get("step_label", ""),
        "footnote": spec.get("footnote", "原创动画讲解 · 中文配音"),
        "title_first": spec.get("title_first", True),
        "scenes": [{k: sc.get(k) for k in ("eyebrow", "heading", "subtitle", "points", "visual")} for sc in scenes],
        "durations": durations,
    }
    html = TEMPLATE.read_text().replace("/*__DATA__*/", json.dumps(data, ensure_ascii=False))
    html_file = tmp / "scene.html"
    html_file.write_text(html)

    # 3) record animation
    total = sum(durations)
    webm = tmp / "raw.webm"
    lead = record(html_file.as_uri(), total, webm)

    # 4) voiceover with lead pad, then mux
    sil = tmp / "lead.wav"
    silence(sil, lead)
    voice = tmp / "voice.wav"
    concat_audio([sil] + wavs, voice)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"{mid}.mp4"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(webm), "-i", str(voice),
                    "-c:v", "libx264", "-preset", "medium", "-pix_fmt", "yuv420p", "-r", "30",
                    "-vf", "scale=1280:720", "-c:a", "aac", "-b:a", "160k",
                    "-shortest", str(out)], check=True)
    print(f"  {mid}.mp4  ({probe(out):.0f}s, {len(scenes)} scenes, lead {lead:.2f}s)")


def main():
    specs = json.loads(ANIM.read_text())
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
