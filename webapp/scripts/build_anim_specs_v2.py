#!/usr/bin/env python3
"""Generate teaching_anim_v2.json: ~5 min bio-animation specs from teaching_videos.json.

Each module -> 8 scenes with:
  - conversational narration (from script paragraphs + oral fillers)
  - bio canvas visual types (not PPT charts)
  - caption subtitles for lower-third
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VIDEOS = ROOT / "webapp" / "data" / "teaching_videos.json"
OUT = ROOT / "webapp" / "data" / "teaching_anim_v2.json"

# Bio scene mapping: (omics, step) -> list of 8 scene keys (title + 6 body + summary)
BIO_SCENES = {
    ("microbiome_16s", "import"): [
        "microbiome_ecosystem", "gene_16s", "pcr_sequencing", "pipeline_dada2",
        "abundance_matrix", "metadata_link", "abundance_matrix", "hypothesis_card",
    ],
    ("microbiome_16s", "prepare"): [
        "microbiome_ecosystem", "composition_shift", "composition_shift", "pipeline_dada2",
        "pipeline_dada2", "diversity_pcoa", "composition_shift", "hypothesis_card",
    ],
    ("microbiome_16s", "analysis"): [
        "microbiome_ecosystem", "diversity_pcoa", "diversity_pcoa", "diversity_pcoa",
        "diversity_pcoa", "diversity_pcoa", "volcano_plot", "hypothesis_card",
    ],
    ("microbiome_16s", "visualization"): [
        "diversity_pcoa", "diversity_pcoa", "composition_shift", "composition_shift",
        "diversity_pcoa", "diversity_pcoa", "diversity_pcoa", "hypothesis_card",
    ],
    ("microbiome_16s", "interpretation"): [
        "volcano_plot", "volcano_plot", "volcano_plot", "pathway_network",
        "hypothesis_card", "hypothesis_card", "pathway_network", "hypothesis_card",
    ],
    ("transcriptomics", "import"): [
        "rnaseq_cell", "rnaseq_cell", "pcr_sequencing", "abundance_matrix",
        "abundance_matrix", "metadata_link", "abundance_matrix", "hypothesis_card",
    ],
    ("transcriptomics", "prepare"): [
        "rnaseq_cell", "pipeline_dada2", "pipeline_dada2", "composition_shift",
        "pipeline_dada2", "pipeline_dada2", "composition_shift", "hypothesis_card",
    ],
    ("transcriptomics", "analysis"): [
        "rnaseq_cell", "volcano_plot", "volcano_plot", "volcano_plot",
        "volcano_plot", "volcano_plot", "volcano_plot", "hypothesis_card",
    ],
    ("transcriptomics", "visualization"): [
        "volcano_plot", "volcano_plot", "abundance_matrix", "abundance_matrix",
        "volcano_plot", "abundance_matrix", "volcano_plot", "hypothesis_card",
    ],
    ("transcriptomics", "interpretation"): [
        "pathway_network", "pathway_network", "pathway_network", "pathway_network",
        "hypothesis_card", "pathway_network", "hypothesis_card", "hypothesis_card",
    ],
    ("metabolomics", "import"): [
        "metabolite_ms", "metabolite_ms", "pipeline_dada2", "abundance_matrix",
        "abundance_matrix", "metadata_link", "metabolite_ms", "hypothesis_card",
    ],
    ("metabolomics", "prepare"): [
        "metabolite_ms", "pipeline_dada2", "pipeline_dada2", "composition_shift",
        "composition_shift", "pipeline_dada2", "metabolite_ms", "hypothesis_card",
    ],
    ("metabolomics", "analysis"): [
        "metabolite_ms", "diversity_pcoa", "diversity_pcoa", "volcano_plot",
        "diversity_pcoa", "volcano_plot", "metabolite_ms", "hypothesis_card",
    ],
    ("metabolomics", "visualization"): [
        "abundance_matrix", "volcano_plot", "diversity_pcoa", "diversity_pcoa",
        "abundance_matrix", "volcano_plot", "metabolite_ms", "hypothesis_card",
    ],
    ("metabolomics", "interpretation"): [
        "pathway_network", "pathway_network", "pathway_network", "hypothesis_card",
        "hypothesis_card", "pathway_network", "hypothesis_card", "hypothesis_card",
    ],
    ("metagenomics", "import"): [
        "shotgun_dna", "shotgun_dna", "pipeline_dada2", "abundance_matrix",
        "abundance_matrix", "metadata_link", "shotgun_dna", "hypothesis_card",
    ],
    ("metagenomics", "prepare"): [
        "shotgun_dna", "composition_shift", "pipeline_dada2", "composition_shift",
        "pipeline_dada2", "composition_shift", "shotgun_dna", "hypothesis_card",
    ],
    ("metagenomics", "analysis"): [
        "shotgun_dna", "diversity_pcoa", "diversity_pcoa", "volcano_plot",
        "pathway_network", "volcano_plot", "shotgun_dna", "hypothesis_card",
    ],
    ("metagenomics", "visualization"): [
        "abundance_matrix", "abundance_matrix", "composition_shift", "diversity_pcoa",
        "abundance_matrix", "diversity_pcoa", "shotgun_dna", "hypothesis_card",
    ],
    ("metagenomics", "interpretation"): [
        "pathway_network", "pathway_network", "hypothesis_card", "pathway_network",
        "hypothesis_card", "shotgun_dna", "hypothesis_card", "hypothesis_card",
    ],
}

STEP_LABELS = {
    "import": "数据导入", "prepare": "质控与预处理", "analysis": "核心分析",
    "visualization": "可视化", "interpretation": "结果解读与假设",
}
OMICS_SHORT = {
    "microbiome_16s": "16S", "transcriptomics": "RNA-seq",
    "metabolomics": "代谢组", "metagenomics": "宏基因组",
}


def oralize(text: str, idx: int = 0) -> str:
    """Expand paragraph into warm, documentary-style narration (~300+ chars target)."""
    text = text.strip()
    if not text:
        return text
    openers = [
        "你看，", "其实呢，", "这里我想特别强调，", "换句话说，",
        "打个比方，", "接下来这一步，", "很多人第一次做会在这里踩坑——",
    ]
    bridges = [
        "这在顶刊组学文章里是默认前提。",
        "理解了这一点，后面操作就不会懵。",
        "对照动画，把概念和数据对上号。",
    ]
    o = openers[idx % len(openers)]
    if not text.endswith("。"):
        text += "。"
    return f"{o}{text}"


def split_script_rich(script: str, n: int = 6) -> list[str]:
    """Split script into n chunks, preferring sentence boundaries."""
    paras = [p.strip() for p in script.split("\n\n") if p.strip()]
    chunks: list[str] = []
    for p in paras:
        sents = re.split(r"(?<=[。！？])", p)
        sents = [s.strip() for s in sents if s.strip()]
        if len(sents) <= 2:
            chunks.append(p)
        else:
            mid = len(sents) // 2
            chunks.append("".join(sents[:mid]))
            chunks.append("".join(sents[mid:]))
    # merge or split to hit n
    while len(chunks) > n:
        # merge shortest adjacent pair
        best = min(range(len(chunks) - 1), key=lambda i: len(chunks[i]) + len(chunks[i + 1]))
        chunks[best:best + 2] = [chunks[best] + chunks[best + 1]]
    while len(chunks) < n and chunks:
        longest = max(range(len(chunks)), key=lambda i: len(chunks[i]))
        s = chunks[longest]
        mid = len(s) // 2
        cut = s.rfind("。", 0, mid + 50)
        if cut < 30:
            cut = mid
        chunks[longest:longest + 1] = [s[: cut + 1], s[cut + 1:].strip()]
    return chunks[:n]


def title_narration(mod, omics_label, step_label) -> str:
    title = mod.get("title", "")
    objective = mod.get("objective", "")
    desc = mod.get("description", "")
    return (
        f"你好，欢迎回来。"
        f"这一节是{omics_label}的{step_label}。"
        f"接下来大约五分钟，我会用科普动画的方式，"
        f"把{title.split('·')[-1].strip() if '·' in title else '这个步骤'}讲清楚。"
        f"目标是：{objective}"
    )


def summary_narration(takeaways: list) -> str:
    parts = "好，我们快速回顾一下本节的关键要点。" + " ".join(
        f"第{i + 1}，{t}。" for i, t in enumerate(takeaways[:3])
    )
    parts += "把这些记牢，下一节分析就会顺很多。我们下节课见。"
    return parts


def body_headings(para: str, idx: int) -> tuple[str, str]:
    """Derive eyebrow + heading from paragraph start."""
    first = para.split("。")[0][:30]
    eyebrows = ["先看原理", "关键一步", "深入理解", "实战要点", "常见误区", "进阶提示"]
    return eyebrows[idx % len(eyebrows)], first + ("…" if len(first) >= 28 else "")


def caption_from_para(para: str) -> str:
    s = para.replace("\n", "")
    return s[:80] + ("…" if len(s) > 80 else "")


def build_module(mid: str, mod: dict) -> dict:
    omics = mod["omics"]
    step = mod["step"]
    omics_label = {"microbiome_16s": "16S 微生物组", "transcriptomics": "转录组 RNA-seq",
                   "metabolomics": "代谢组", "metagenomics": "宏基因组"}.get(omics, omics)
    step_label = f"{OMICS_SHORT.get(omics, omics)} · {STEP_LABELS.get(step, step)}"
    bio_keys = BIO_SCENES.get((omics, step), ["microbiome_ecosystem"] * 8)
    if len(bio_keys) < 8:
        bio_keys = bio_keys + ["hypothesis_card"] * (8 - len(bio_keys))

    paras = split_script_rich(mod.get("script", ""), 6)
    takeaways = mod.get("takeaways", [])

    scenes = []

    # Scene 0: title
    title_parts = mod.get("title", "").split("·")
    heading = title_parts[-1].strip() if title_parts else mod.get("title", "")
    scenes.append({
        "eyebrow": mod.get("title", "").split("·")[0].strip() if "·" in mod.get("title", "") else omics_label,
        "heading": heading,
        "caption": mod.get("description", ""),
        "narration": title_narration(mod, omics_label, STEP_LABELS.get(step, step)),
        "visual": {"type": "bio", "scene": bio_keys[0]},
    })

    for i, para in enumerate(paras):
        eyebrow, h = body_headings(para, i)
        scenes.append({
            "eyebrow": eyebrow,
            "heading": h,
            "caption": caption_from_para(para),
            "narration": oralize(para, i),
            "visual": {"type": "bio", "scene": bio_keys[i + 1]},
        })

    # Scene 7: summary
    scenes.append({
        "eyebrow": "本节小结",
        "heading": "三个要点带走",
        "caption": " · ".join(takeaways[:3]) if takeaways else "",
        "narration": summary_narration(takeaways),
        "visual": {"type": "bio", "scene": bio_keys[7]},
    })

    return {
        "omics": omics,
        "step_label": step_label,
        "title_first": True,
        "footnote": "原创科普动画 · 中文配音",
        "scenes": scenes,
    }


def main():
    data = json.loads(VIDEOS.read_text())
    out = {}
    for mid, mod in data["modules"].items():
        out[mid] = build_module(mid, mod)
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"wrote {len(out)} modules -> {OUT}")
    # estimate narration chars
    chars = sum(len(s["narration"]) for m in out.values() for s in m["scenes"])
    print(f"total narration chars: {chars}, ~{chars/4/60:.0f} min at 240 cpm")


if __name__ == "__main__":
    main()
