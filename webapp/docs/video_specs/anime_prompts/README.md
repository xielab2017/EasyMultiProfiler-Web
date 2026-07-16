# EMP 课程微课 · 动漫视频 LLM Prompt 库

> 共 **20** 节微课，每节一个独立 Prompt 文件，可直接复制到 Kling / Runway / Pika / 可灵 / 即梦 等视频 LLM，或交给脚本分镜工具。

## 使用方式

1. 先读 [00_GLOBAL_ANIME_STYLE.md](./00_GLOBAL_ANIME_STYLE.md) 统一视觉
2. 打开对应模块的 `{module_id}.md`
3. 复制 **「一、一键复制给视频 LLM 的主 Prompt」** 代码块到视频 LLM
4. 生成后重命名为 `{module_id}.mp4`，放入 `webapp/frontend/videos/`
5. 旁白可参考 [NARRATION_录音稿.md](../NARRATION_录音稿.md) 单独配音后合成

## 重新生成本目录

```bash
python3 webapp/scripts/generate_anime_video_prompts.py
```

## 课程目录

| 文件 | 赛道 | 标题 | 时长 |
|------|------|------|------|
| [m16s_import](./m16s_import.md) | 16S 微生物组 | 16S 微生物组 · 第1步：数据从哪来、导入什么 | 约 4 分钟 |
| [m16s_prepare](./m16s_prepare.md) | 16S 微生物组 | 16S 微生物组 · 第2步：为什么菌群数据要特殊预处理 | 约 4 分钟 |
| [m16s_analysis](./m16s_analysis.md) | 16S 微生物组 | 16S 微生物组 · 第3步：多样性分析到底在量什么 | 约 4 分钟 |
| [m16s_viz](./m16s_viz.md) | 16S 微生物组 | 16S 微生物组 · 第4步：排序图与组成图怎么读 | 约 4 分钟 |
| [m16s_interpret](./m16s_interpret.md) | 16S 微生物组 | 16S 微生物组 · 第5步：差异菌属与可验证假设 | 约 4 分钟 |
| [rnaseq_import](./rnaseq_import.md) | 转录组 RNA-seq | 转录组 RNA-seq · 第1步：count 矩阵是什么、导入什么 | 约 4 分钟 |
| [rnaseq_prepare](./rnaseq_prepare.md) | 转录组 RNA-seq | 转录组 RNA-seq · 第2步：归一化与低表达过滤为何重要 | 约 4 分钟 |
| [rnaseq_analysis](./rnaseq_analysis.md) | 转录组 RNA-seq | 转录组 RNA-seq · 第3步：差异表达分析在算什么 | 约 4 分钟 |
| [rnaseq_viz](./rnaseq_viz.md) | 转录组 RNA-seq | 转录组 RNA-seq · 第4步：火山图与热图怎么读 | 约 4 分钟 |
| [rnaseq_interpret](./rnaseq_interpret.md) | 转录组 RNA-seq | 转录组 RNA-seq · 第5步：功能富集与科学解读 | 约 4 分钟 |
| [metab_import](./metab_import.md) | 代谢组 | 代谢组 · 第1步：代谢组数据是什么、导入什么 | 约 4 分钟 |
| [metab_prepare](./metab_prepare.md) | 代谢组 | 代谢组 · 第2步：缺失值、归一化与标度化 | 约 4 分钟 |
| [metab_analysis](./metab_analysis.md) | 代谢组 | 代谢组 · 第3步：多元分析与差异代谢物 | 约 4 分钟 |
| [metab_viz](./metab_viz.md) | 代谢组 | 代谢组 · 第4步：热图、火山图与得分图怎么读 | 约 4 分钟 |
| [metab_interpret](./metab_interpret.md) | 代谢组 | 代谢组 · 第5步：通路、关联与因果的边界 | 约 4 分钟 |
| [mgx_import](./mgx_import.md) | 宏基因组 | 宏基因组 · 第1步：鸟枪法数据与谱表导入 | 约 4 分钟 |
| [mgx_prepare](./mgx_prepare.md) | 宏基因组 | 宏基因组 · 第2步：谱表的过滤与归一化 | 约 4 分钟 |
| [mgx_analysis](./mgx_analysis.md) | 宏基因组 | 宏基因组 · 第3步：群落结构与差异特征分析 | 约 4 分钟 |
| [mgx_viz](./mgx_viz.md) | 宏基因组 | 宏基因组 · 第4步：功能热图与组成图怎么读 | 约 4 分钟 |
| [mgx_interpret](./mgx_interpret.md) | 宏基因组 | 宏基因组 · 第5步：功能富集、因果谬误与假设 | 约 4 分钟 |

## 源数据

- `webapp/data/teaching_videos.json`（script / storyboard / takeaways）
- `webapp/docs/video_specs/NARRATION_录音稿.md`（完整旁白）
- `webapp/docs/video_specs/00_制作总则.md`（CNS 科普制作规范）
