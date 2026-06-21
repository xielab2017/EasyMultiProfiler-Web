#!/usr/bin/env python3
"""Generate original narrated micro-lesson videos from teaching_videos.json.

For each lesson module we synthesize a fully original short video (no YouTube):
  - Chinese voiceover via macOS `say` (Tingting)
  - Custom slides rendered with PIL (title / objective / per-paragraph talking
    points / key takeaways)
  - Assembled into an MP4 with ffmpeg, perfectly synced per segment.

Usage:
  python3 build_lesson_videos.py m16s_import          # one module
  python3 build_lesson_videos.py all                  # every module
"""
import json
import os
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "webapp" / "data" / "teaching_videos.json"
OUT_DIR = ROOT / "webapp" / "frontend" / "videos"
TMP_ROOT = Path(tempfile.gettempdir()) / "emp_vid"

VOICE = "Tingting"
RATE = 132  # speaking rate (measured, clear pace -> ~3 min lessons)
TAIL_PAD = 0.6  # seconds of silence appended after each segment's narration
W, H = 1280, 720

FONT_BOLD = "/System/Library/Fonts/Hiragino Sans GB.ttc"
FONT_REG = "/System/Library/Fonts/Hiragino Sans GB.ttc"

OMICS_COLORS = {
    "microbiome_16s": (37, 99, 235),
    "transcriptomics": (5, 150, 105),
    "metabolomics": (217, 70, 239),
    "metagenomics": (234, 88, 12),
}

from PIL import Image, ImageDraw, ImageFont  # noqa: E402


def font(size, bold=False):
    return ImageFont.truetype(FONT_BOLD if bold else FONT_REG, size)


def wrap_cjk(text, draw, fnt, max_w):
    lines = []
    cur = ""
    for ch in text:
        if ch == "\n":
            lines.append(cur)
            cur = ""
            continue
        test = cur + ch
        if draw.textlength(test, font=fnt) <= max_w:
            cur = test
        else:
            lines.append(cur)
            cur = ch
    if cur:
        lines.append(cur)
    return lines


def draw_base(omics, step_label, title):
    img = Image.new("RGB", (W, H), (248, 250, 252))
    d = ImageDraw.Draw(img)
    accent = OMICS_COLORS.get(omics, (37, 99, 235))
    # top band
    d.rectangle([0, 0, W, 86], fill=accent)
    d.text((48, 24), f"{step_label}", font=font(34, True), fill=(255, 255, 255))
    tw = d.textlength("EasyMultiProfiler · 背景微课", font=font(22))
    d.text((W - tw - 48, 32), "EasyMultiProfiler · 背景微课", font=font(22), fill=(255, 255, 255))
    # title
    d.text((48, 108), title, font=font(30, True), fill=(15, 23, 42))
    d.line([48, 158, W - 48, 158], fill=accent, width=3)
    return img, d, accent


def slide_title(path, omics, step_label, title, objective):
    img, d, accent = draw_base(omics, step_label, title)
    d.text((48, 200), "学习目标", font=font(28, True), fill=accent)
    lines = wrap_cjk(objective, d, font(34), W - 120)
    y = 252
    for ln in lines:
        d.text((60, y), ln, font=font(34), fill=(30, 41, 59))
        y += 52
    d.text((48, H - 70), "本节为原创讲解短视频（中文配音）", font=font(22), fill=(100, 116, 139))
    img.save(path)


def slide_body(path, omics, step_label, title, idx, total, paragraph):
    img, d, accent = draw_base(omics, step_label, title)
    # progress dots
    for i in range(total):
        cx = 60 + i * 30
        col = accent if i <= idx else (203, 213, 225)
        d.ellipse([cx, 176, cx + 16, 192], fill=col)
    lines = wrap_cjk(paragraph, d, font(36), W - 120)
    # vertical center the text block
    line_h = 58
    block_h = len(lines) * line_h
    y = max(220, (H - block_h) // 2 + 20)
    for ln in lines:
        d.text((60, y), ln, font=font(36), fill=(30, 41, 59))
        y += line_h
    d.text((W - 130, H - 56), f"{idx + 1} / {total}", font=font(24), fill=(100, 116, 139))
    img.save(path)


def slide_takeaways(path, omics, step_label, title, takeaways):
    img, d, accent = draw_base(omics, step_label, title)
    d.text((48, 200), "关键要点", font=font(30, True), fill=accent)
    y = 268
    for i, t in enumerate(takeaways):
        d.ellipse([60, y + 10, 84, y + 34], fill=accent)
        d.text((66, y + 8), str(i + 1), font=font(22, True), fill=(255, 255, 255))
        lines = wrap_cjk(t, d, font(32), W - 180)
        for j, ln in enumerate(lines):
            d.text((108, y), ln, font=font(32), fill=(30, 41, 59))
            y += 48
        y += 18
    img.save(path)


def tts(text, out_aiff):
    subprocess.run(["say", "-v", VOICE, "-r", str(RATE), "-o", str(out_aiff), text], check=True)


def duration(path):
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "csv=p=0", str(path)],
        capture_output=True, text=True, check=True,
    )
    return float(r.stdout.strip() or 0.0)


def make_segment(png, aiff, out_mp4):
    dur = duration(aiff) + TAIL_PAD
    subprocess.run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-loop", "1", "-i", str(png),
        "-i", str(aiff),
        "-c:v", "libx264", "-tune", "stillimage", "-pix_fmt", "yuv420p",
        "-r", "25", "-c:a", "aac", "-b:a", "128k",
        "-af", f"apad=pad_dur={TAIL_PAD}",
        "-t", f"{dur:.2f}", str(out_mp4),
    ], check=True)


def build_module(mid, mod):
    omics = mod.get("omics", "")
    step_label = mod.get("step_label") or mod.get("aspect", "")
    # step_label may be a code if not resolved; map common ones
    STEP = {"import": "数据导入", "prepare": "质控与预处理", "analysis": "核心分析",
            "visualization": "可视化", "interpretation": "结果解读与假设"}
    step_label = STEP.get(mod.get("step", ""), step_label)
    title = mod.get("title", mid)
    objective = mod.get("objective", "")
    script = mod.get("script", "")
    takeaways = mod.get("takeaways", []) or []

    tmp = TMP_ROOT / mid
    tmp.mkdir(parents=True, exist_ok=True)
    segs = []

    # 1) title/objective slide
    paras = [p.strip() for p in script.split("\n\n") if p.strip()]
    total = len(paras)

    def add(idx_name, png, narration):
        aiff = tmp / f"{idx_name}.aiff"
        tts(narration, aiff)
        mp4 = tmp / f"{idx_name}.mp4"
        make_segment(png, aiff, mp4)
        segs.append(mp4)

    p0 = tmp / "s_title.png"
    slide_title(p0, omics, step_label, title, objective)
    add("00_title", p0, f"{title}。本节学习目标：{objective}")

    # 2) body slides (one per paragraph)
    for i, para in enumerate(paras):
        png = tmp / f"s_body_{i}.png"
        slide_body(png, omics, step_label, title, i, total, para)
        add(f"{i+1:02d}_body", png, para)

    # 3) takeaways slide
    if takeaways:
        pz = tmp / "s_take.png"
        slide_takeaways(pz, omics, step_label, title, takeaways)
        add("99_take", pz, "本节关键要点回顾：" + "；".join(takeaways) + "。")

    # concat
    listfile = tmp / "list.txt"
    listfile.write_text("".join(f"file '{m}'\n" for m in segs))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"{mid}.mp4"
    subprocess.run([
        "ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0",
        "-i", str(listfile), "-c", "copy", str(out),
    ], check=True)
    dur = duration(out)
    print(f"  {mid}.mp4  ({dur:.0f}s, {total} segments)")
    return dur


def main():
    data = json.loads(DATA.read_text())
    mods = data["modules"]
    target = sys.argv[1] if len(sys.argv) > 1 else "all"
    ids = list(mods) if target == "all" else [target]
    for mid in ids:
        if mid not in mods:
            print(f"skip unknown module {mid}")
            continue
        print(f"building {mid} ...")
        build_module(mid, mods[mid])


if __name__ == "__main__":
    main()
