/**
 * Recommended filter / normalize / analysis defaults per omics pipeline.
 */
import { t } from "./locale.js?v=2026-07-16-multi-demo";

export function omicsLabel(key) {
  const map = {
    microbiome_16s: "omics.label.m16s",
    transcriptomics: "omics.label.transcriptomics",
    metagenomics: "omics.label.metagenomics",
    metabolomics: "omics.label.metabolomics",
    chipseq: "omics.label.chipseq",
    clinical: "omics.label.clinical",
  };
  return t(map[key] || "") || key;
}

/** @type {Record<string, Record<string, string>>} */
export const OMICS_RECOMMENDED = {
  microbiome_16s: {
    "filter-min-prevalence": "0.1",
    "filter-min-detect-rate": "0.05",
    "filter-max-detect-rate": "1",
    "norm-method": "rclr",
    "collapse-level": "Genus",
    "m16s-min-total-abundance": "0",
    "m16s-keep-topn": "40",
    "m16s-drop-unassigned": "true",
    "m16s-normalize-method": "rclr",
    "m16s-tax-level": "Genus",
    "ra-tax-level": "Genus",
    "ra-alpha": "shannon",
    "ra-ord": "PCoA",
    "diff-method": "wilcox",
    "diff-filter-low": "true",
    "diff-subset": "true",
    "deg-fc": "1",
    "deg-p": "0.05",
    "deg-use-padj": "true",
    "deg-min-rowsum": "0",
    "vol-fc": "1",
    "vol-p": "0.05",
    "vol-use-padj": "true",
  },
  transcriptomics: {
    "filter-min-count": "10",
    "filter-max-na": "0.2",
    "norm-method": "log",
    "diff-method": "DESeq2",
    "diff-filter-low": "true",
    "diff-subset": "true",
    "tx-diff-method": "DESeq2",
    "tx-gsea-org": "mmu",
    "deg-fc": "1",
    "deg-p": "0.05",
    "deg-use-padj": "true",
    "deg-min-rowsum": "10",
    "vol-fc": "1",
    "vol-p": "0.05",
    "vol-use-padj": "true",
    "ra-fc": "1",
    "ra-p": "0.05",
    "ra-use-padj": "true",
    "ra-min-rowsum": "10",
    "ra-enrich": "true",
    "enrich-use-padj": "true",
  },
  metagenomics: {
    "filter-min-prevalence": "0.1",
    "filter-min-detect-rate": "0.05",
    "norm-method": "rclr",
    "mgx-normalize-method": "rclr",
    "collapse-level": "Genus",
    "diff-filter-low": "true",
    "deg-use-padj": "true",
    "vol-use-padj": "true",
  },
  metabolomics: {
    "filter-max-na": "0.2",
    "impute-method": "knn",
    "norm-method": "rclr",
    "mbx-normalize-method": "rclr",
    "diff-filter-low": "true",
    "deg-use-padj": "true",
    "vol-use-padj": "true",
  },
  chipseq: {
    "chip-genome": "hs",
    "chip-prefer-macs": "auto",
    "chip-macs-preset": "chipseq_tf",
    "chip-format": "BAM",
    "chip-cutoff-type": "q",
    "chip-qvalue": "0.01",
    "chip-keep-dup": "auto",
    "chip-score-cutoff": "5",
    "chip-co-score-cutoff": "10",
    "chip-min-counts": "100",
  },
  clinical: {
    "clin-cor-padj": "BH",
    "clin-cor-method": "spearman",
  },
};

function setField(id, value) {
  const el = document.getElementById(id);
  if (!el || value == null) return false;
  if (el.tagName === "SELECT" || el.tagName === "INPUT" || el.tagName === "TEXTAREA") {
    el.value = String(value);
    el.dispatchEvent(new Event("change", { bubbles: true }));
    return true;
  }
  return false;
}

/**
 * Apply recommended UI defaults for the given omics pipeline key.
 * @param {string} omics - e.g. microbiome_16s, transcriptomics
 * @param {{ silent?: boolean }} opts
 * @returns {{ omics: string, applied: number, label: string }}
 */
export function applyOmicsDefaults(omics, opts = {}) {
  const key = omics || document.getElementById("omics-pipeline")?.value || "transcriptomics";
  const map = OMICS_RECOMMENDED[key] || OMICS_RECOMMENDED.transcriptomics;
  let applied = 0;
  for (const [id, val] of Object.entries(map)) {
    if (setField(id, val)) applied++;
  }
  const label = omicsLabel(key);
  if (!opts.silent) {
    window.dispatchEvent(new CustomEvent("emp:toast", {
      detail: { msg: t("defaults.appliedFull", null, { label, n: applied }), type: "success" },
    }));
  }
  return { omics: key, applied, label };
}

/** Short human-readable summary for teaching cards. */
export function omicsDefaultsHint(omics) {
  const key = omics || "transcriptomics";
  switch (key) {
    case "microbiome_16s":
      return t("defaults.hint.m16s");
    case "transcriptomics":
      return t("defaults.hint.transcriptomics");
    case "metabolomics":
      return t("defaults.hint.metabolomics");
    case "chipseq":
      return t("defaults.hint.chipseq");
    default:
      return t("defaults.hint.generic");
  }
}
