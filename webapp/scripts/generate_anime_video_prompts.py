#!/usr/bin/env python3
"""Generate anime-style video LLM prompts from teaching_videos.json."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "webapp" / "data" / "teaching_videos.json"
OUT = ROOT / "webapp" / "docs" / "video_specs" / "anime_prompts"

ORDER = [
    "m16s_import", "m16s_prepare", "m16s_analysis", "m16s_viz", "m16s_interpret",
    "rnaseq_import", "rnaseq_prepare", "rnaseq_analysis", "rnaseq_viz", "rnaseq_interpret",
    "metab_import", "metab_prepare", "metab_analysis", "metab_viz", "metab_interpret",
    "mgx_import", "mgx_prepare", "mgx_analysis", "mgx_viz", "mgx_interpret",
]

TRACK_LABEL = {
    "microbiome_16s": "16S 微生物组",
    "transcriptomics": "转录组 RNA-seq",
    "metabolomics": "代谢组",
    "metagenomics": "宏基因组",
}

STEP_LABEL = {
    "import": "数据导入",
    "prepare": "质控与预处理",
    "analysis": "核心分析",
    "visualization": "可视化",
    "interpretation": "结果解读",
}

GLOBAL_STYLE = """## 全局动漫视觉设定（所有课程视频统一）

- **风格**：日系科普动漫（类似《工作细胞》科普感 + 3Blue1Brown 抽象图解），2D 赛璐璐，线条干净，非 Q 版
- **画幅**：16:9，1920×1080，24fps
- **时长**：约 4–5 分钟（240–300 秒）
- **背景**：深蓝渐变宇宙感（#060b18 → #0f1f3d），关键生物学结构用高饱和荧光色
- **固定角色**：
  - **小研**（女研究生，白大褂+马尾，负责提问与操作 EMP）
  - **博导酱**（温和男导师形象，负责讲解概念，旁白主声可对应此角色）
  - **菌菌 / 基因君 / 代谢小精灵**（拟人化分子或微生物，按章节替换）
- **镜头语言**：远景（组织/群落）→ 中景（细胞）→ 近景（数据矩阵/UI）；每 8–12 秒有一次视觉变化
- **数据可视化**：矩阵/热图/火山图从生物学实体「汇聚溶解」出现，禁止白底 PPT 翻页
- **字幕**：简体中文硬字幕，关键词高亮（黄色描边）
- **配音**：中文普通话，纪录片科普语速（180–200 字/分钟），先声后画（旁白提前 0.2s）
- **EMP 衔接**：右下角画中画（≤25%）展示 EasyMultiProfiler 界面操作，圆角 8px
- **禁止**：静态 bullet 列表、无实体的纯几何图标、与旁白无关的素材拼接、夸张表情包"""

MASTER_PROMPT_TEMPLATE = """请为「EasyMultiProfiler 生信课程微课」制作一段 **{duration}** 的 **日系科普动漫** 教学视频。

### 课程信息
- **模块 ID**：{module_id}
- **标题**：{title}
- **组学赛道**：{omics_label}
- **教学环节**：{step_label}
- **学习目标**：{objective}
- **输出文件名**：{local_video}

### 内容梗概（本集要讲什么）
{description}

### 视觉与角色（必须遵守）
{global_style_short}

### 分镜要求（共 {scene_count} 幕，按时间顺序制作）
{storyboard_block}

### 旁白全文（请严格覆盖，可微调口语化，不可删减科学要点）
{narration}

### 结尾 3 要点字幕卡（各停留 3 秒）
{takeaways_block}

### 质量检查清单
- [ ] 是否用动漫角色讲解，而非 PPT？
- [ ] 是否每 8–12 秒有镜头运动或新元素？
- [ ] 数据概念是否从生物学画面「过渡」到图表？
- [ ] 是否包含 1 段 EMP 软件画中画操作？
- [ ] 结尾是否显示 3 条 takeaway？

请按分镜输出：场景编号、时长、画面描述、角色动作、台词/旁白、字幕、转场方式。"""


def scene_block(storyboard: list[dict]) -> str:
    lines = []
    for i, s in enumerate(storyboard, 1):
        t = s.get("t", "")
        scene = s.get("scene", "").strip()
        lines.append(f"**第 {i} 幕 {t}**\n{scene}")
    return "\n\n".join(lines) if lines else "（按旁白自然切 4–5 幕，每幕约 45–60 秒）"


def takeaways_block(takeaways: list[str]) -> str:
    return "\n".join(f"{i}. {t}" for i, t in enumerate(takeaways, 1))


def per_file_content(module_id: str, m: dict) -> str:
    omics = TRACK_LABEL.get(m.get("omics", ""), m.get("omics", ""))
    step = STEP_LABEL.get(m.get("step", ""), m.get("step", ""))
    storyboard = m.get("storyboard") or []
    takeaways = m.get("takeaways") or []
    local_video = m.get("local_video", f"videos/{module_id}.mp4")

    master = MASTER_PROMPT_TEMPLATE.format(
        duration=m.get("duration", "约 4 分钟"),
        module_id=module_id,
        title=m.get("title", ""),
        omics_label=omics,
        step_label=step,
        objective=m.get("objective", ""),
        local_video=local_video,
        description=m.get("description", ""),
        global_style_short="风格：日系科普动漫，角色「小研+博导酱」，深蓝科幻背景，数据图从生物画面过渡出现。",
        scene_count=len(storyboard),
        storyboard_block=scene_block(storyboard),
        narration=m.get("script", "").strip(),
        takeaways_block=takeaways_block(takeaways),
    )

    scenes_detail = []
    for i, s in enumerate(storyboard, 1):
        scenes_detail.append(
            f"### 场景 {i} · {s.get('t', '')}\n\n"
            f"**画面任务**：{s.get('scene', '')}\n\n"
            f"**动漫化建议**：用角色互动呈现该场景；数据/图表从细胞或分子画面中变形出现；保持科普严谨。\n"
        )

    return f"""# 动漫微课 Prompt · {module_id}

> **标题**：{m.get('title', '')}
> **赛道**：{omics} · {step}
> **时长**：{m.get('duration', '约 4 分钟')}
> **交付 MP4**：`webapp/frontend/{local_video}`
> **源数据**：`webapp/data/teaching_videos.json` → `{module_id}`

---

## 一、一键复制给视频 LLM 的主 Prompt

```
{master}
```

---

## 二、本集内容大纲（给你快速审阅）

| 项目 | 内容 |
|------|------|
| 学习目标 | {m.get('objective', '')} |
| 核心概念 | {m.get('description', '')} |
| 分镜数 | {len(storyboard)} |
| 要点 | {'；'.join(takeaways)} |

---

## 三、全局动漫风格（详见 `00_GLOBAL_ANIME_STYLE.md`）

{GLOBAL_STYLE}

---

## 四、分镜细化（供分场景生成或迭代）

{chr(10).join(scenes_detail) if scenes_detail else '_（见 teaching_videos.json storyboard）_'}

---

## 五、旁白全文（配音稿）

{m.get('script', '').strip()}

---

## 六、生成后自检

1. 科学事实是否与旁白一致？
2. 是否避免「相对丰度=绝对增多」等常见误读（如本集涉及）？
3. 字幕是否包含 takeaway 三要点？
4. 导出 1080p H.264，文件名 `{module_id}.mp4` 放入 `webapp/frontend/videos/`
"""


def readme_index(modules: dict) -> str:
    rows = []
    for mid in ORDER:
        m = modules[mid]
        omics = TRACK_LABEL.get(m.get("omics", ""), "")
        rows.append(f"| [{mid}](./{mid}.md) | {omics} | {m.get('title', '')} | {m.get('duration', '')} |")
    table = "\n".join(rows)
    return f"""# EMP 课程微课 · 动漫视频 LLM Prompt 库

> 共 **20** 节微课，每节一个独立 Prompt 文件，可直接复制到 Kling / Runway / Pika / 可灵 / 即梦 等视频 LLM，或交给脚本分镜工具。

## 使用方式

1. 先读 [00_GLOBAL_ANIME_STYLE.md](./00_GLOBAL_ANIME_STYLE.md) 统一视觉
2. 打开对应模块的 `{{module_id}}.md`
3. 复制 **「一、一键复制给视频 LLM 的主 Prompt」** 代码块到视频 LLM
4. 生成后重命名为 `{{module_id}}.mp4`，放入 `webapp/frontend/videos/`
5. 旁白可参考 [NARRATION_录音稿.md](../NARRATION_录音稿.md) 单独配音后合成

## 重新生成本目录

```bash
python3 webapp/scripts/generate_anime_video_prompts.py
```

## 课程目录

| 文件 | 赛道 | 标题 | 时长 |
|------|------|------|------|
{table}

## 源数据

- `webapp/data/teaching_videos.json`（script / storyboard / takeaways）
- `webapp/docs/video_specs/NARRATION_录音稿.md`（完整旁白）
- `webapp/docs/video_specs/00_制作总则.md`（CNS 科普制作规范）
"""


def global_style_file() -> str:
    return f"""# 00 · 动漫微课全局视觉设定

{GLOBAL_STYLE}

## 角色设定卡（供一致性参考）

### 小研（学生视角）
- 外观：东亚女性研究生，25 岁，深棕马尾，圆框眼镜，白大褂内搭浅蓝衬衫
- 性格：好奇、爱追问「所以这意味着什么？」
- 用途：在 EMP 界面操作、提出常见误区、总结 takeaway

### 博导酱（讲解视角）
- 外观：温和中年男性导师，短发，无眼镜，深蓝西装+敞开领口
- 性格：沉稳、善用比喻
- 用途：主旁白声音、概念拆解、指向图表

### 拟人化助手（按章节切换）
| 赛道 | 助手形象 | 设定 |
|------|----------|------|
| 16S / 宏基因组 | 菌菌 | 半透明蓝绿细菌精灵，头顶分类标签 |
| RNA-seq | 基因君 | 双螺旋发带的基因小人，持 count 数字牌 |
| 代谢组 | 代谢小精灵 | 六边形小分子，颜色随通路变化 |

## 镜头模板（每幕可选用）

1. **开场**：星空推进 → 实验室全景 → 角色入画
2. **概念**：博导酱白板手势 → 画面变成动漫化机制动画
3. **数据**：生物结构溶解为矩阵/热图/火山图（粒子过渡）
4. **实操**：小研在 EMP 画中画操作，主画面保留概念图
5. **收尾**：三要点字幕卡 + 「下一节见」

## 与 CNS 科普规范的关系

本动漫风格是 `00_制作总则.md` 的**教学友好版**：保留「生物→数据」三层画面与数据可视化规范，但用动漫角色降低门槛。交付前仍须核对科学准确性。
"""


def main() -> None:
    data = json.loads(DATA.read_text(encoding="utf-8"))
    modules = data["modules"]
    OUT.mkdir(parents=True, exist_ok=True)

    (OUT / "00_GLOBAL_ANIME_STYLE.md").write_text(global_style_file(), encoding="utf-8")
    (OUT / "README.md").write_text(readme_index(modules), encoding="utf-8")

    for mid in ORDER:
        (OUT / f"{mid}.md").write_text(per_file_content(mid, modules[mid]), encoding="utf-8")

    master_lines = ["# 20 节微课 · 动漫 Prompt 合集\n", "> 每节完整 Prompt 见单独文件；此处仅列标题与一键索引。\n"]
    for mid in ORDER:
        m = modules[mid]
        master_lines.append(f"\n## {mid}\n\n**{m.get('title', '')}**\n\n→ 详见 [{mid}.md](./{mid}.md)\n")
    (OUT / "MASTER_INDEX.md").write_text("".join(master_lines), encoding="utf-8")

    print(f"Wrote {len(ORDER)} prompts + README to {OUT}")


if __name__ == "__main__":
    main()
