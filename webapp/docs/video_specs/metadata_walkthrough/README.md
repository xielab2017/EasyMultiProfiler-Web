# EasyMultiProfiler-Web metadata tutorial

**An illustrated tutorial about v9.1.2, not a live screen recording.** It may be packaged with v9.1.3. English offline synthetic narration and burned-in Chinese/English subtitles are included. Optional VTT/SRT tracks contain the same captions; leave external tracks off during ordinary playback to avoid duplication.

## Deliverables

- `emp_metadata_walkthrough.mp4`: 1280 × 720, H.264/AAC, 12 fps; nine illustrated chapters.
- `emp_metadata_walkthrough.en.vtt` / `.zh.vtt`: separate captions.
- Matching SRT files, `narration_en.txt`, and `timeline.json`.
- `storyboard.json`: all slide text, English narration, and Chinese translations.
- `render_walkthrough.py`: fully local renderer. No downloads, credentials, model calls, paid services, or browser automation.
- `assets/evidence/`: actual local checks and saved public-data examples supporting the stated facts.
- `emp_metadata_walkthrough_poster.png`: representative frame.
- `verify_walkthrough.py` and `verification.json`: reproducible media and evidence checks.

## Rebuild

On Linux with Python, Pillow, ffmpeg/ffprobe, the ffmpeg `flite` filter and Noto Sans CJK fonts available:

```sh
python render_walkthrough.py
python verify_walkthrough.py
```

The renderer uses the installed Flite `slt` English synthetic voice. It is an intelligible basic offline voice, not a human recording or neural voice. Font paths are declared at the top of the script. `--voice awb` selects another installed Flite voice. `--frames-only` renders only PNGs for layout review. The video can be rebuilt offline from the included assets; running it does not retrieve or analyze scientific data.

## Evidence and limits

- Dependency check: the repository metadata launcher reported ready, Python 3.12.14, optional pypdf available, and R unavailable. Python 3.10+ is the requirement, not necessarily the viewer's installed version.
- `SRR390728.metadata.json` is a previously saved ENA metadata response: one paired-end RNA-Seq run, two FASTQ links, 203,162,874 archive-reported bytes. The recording did not retrieve or download those reads.
- The GSE60450 files are previously saved discovery/download-inspection records. They report a 513,592-byte processed file, 27,179 feature rows, 12 sample columns and an excluded Length column. Numerical classification remains `count_like_unverified`, with `deseq2_ready=false` and publisher checksum unverified.
- `synthetic-plan.json` is a conspicuously labeled teaching fixture with fake provenance and four synthetic sample identifiers. The actual validator accepts its structure but reports `executable=false`. It is not evidence about biological data.
- The agent status check reported `unconfigured`, disabled, and execution unsupported. No provider inference was made to produce the tutorial.
- Page control names and limits were checked against `webapp/frontend/public_data.html`, `webapp/scripts/launch_metadata.py`, `workflow_plans.py`, and `agent_adapter.py`, plus the repository metadata guide. No click-by-click browser validation is claimed.
- Browser capture and interactive playback could not be verified because the cloud browser could not reach the isolated local service. File-URL navigation was unsupported and not used. Verification instead includes full ffmpeg decoding, ffprobe stream checks, caption timing and visual inspection of rendered frames. HTTP delivery/Range should be verified by the integrating application.
- This is an original illustrated explanation, not UI footage or a fabricated demonstration. The entire video is labeled accordingly. No stock footage, music or external copyrighted media are used.

## 中文说明

本片是基于 v9.1.2 源码与真实检查记录制作的原创图解教程，不是实机连续录屏，也不声称逐个按钮已通过浏览器测试。使用离线英文合成配音，中文字幕与英文字幕已烧录进视频。另附的 VTT/SRT 是相同内容，日常播放可关闭外部字幕以避免重复。

公开数据示例是此前保存的元数据与矩阵检查记录；人工流程示例明确标为教学用。视频不会执行 R、调用 AI，也不会下载原始 FASTQ。流程校验通过不等于执行分析。复现所需脚本、文案、字幕、时间轴和依据均已包含。

## Repository integration

Generated MP4 and VTT files are installed in `webapp/frontend/videos/`. The production source stays here. Rebuilding writes outputs beside this README; copy the generated MP4 and two VTTs into the frontend videos directory after verification. No automatic upload or deployment is performed.
