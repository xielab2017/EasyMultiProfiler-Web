# EMP Course 微课 · 专业动画制作规格书

> **用途**：交给动画/视频制作团队（CNS 科普、Nature Reviews 风格），替换当前简易 Canvas 视频。  
> **目标时长**：每节 **5:00 ± 0:30**  
> **画幅**：1920×1080（交付可 downscale 至 1280×720）  
> **配音**：中文普通话，纪录片男声（参考 Yunxi / 央视科教），语速约 180–200 字/分钟  
> **字幕**：简体中文硬字幕 + SRT 外挂  

## 文件索引

| 文件 | 内容 |
|------|------|
| [00_制作总则.md](./00_制作总则.md) | 视觉风格、镜头语言、数据可视化规范、EMP 界面规范 |
| [01_16S微生物组.md](./01_16S微生物组.md) | m16s_import ~ m16s_interpret（5 节） |
| [02_转录组RNAseq.md](./02_转录组RNAseq.md) | rnaseq_import ~ rnaseq_interpret（5 节） |
| [03_代谢组.md](./03_代谢组.md) | metab_import ~ metab_interpret（5 节） |
| [04_宏基因组.md](./04_宏基因组.md) | mgx_import ~ mgx_interpret（5 节） |
| [NARRATION_录音稿.md](./NARRATION_录音稿.md) | **20 节完整旁白**（可直接送录音棚） |
| [anime_prompts/](./anime_prompts/README.md) | **20 节动漫视频 LLM Prompt**（一键复制给 Kling/可灵等） |

## 单节结构说明

每一「场景」包含：

1. **时间码**（入点–出点）
2. **旁白全文**（可直接录音）
3. **画面演示需求**（分：主镜头 / 动画细节 / 数据与标注 / 镜头运动 / 音效）
4. **EMP 衔接**（若需录屏或 UI 示意）

## 与现有数据对应

| 模块 ID | 视频文件 | 测验 ID |
|---------|----------|---------|
| `m16s_import` | `videos/m16s_import.mp4` | `quiz_m16s_import` |
| … | … | … |

源教案：`webapp/data/teaching_videos.json`
