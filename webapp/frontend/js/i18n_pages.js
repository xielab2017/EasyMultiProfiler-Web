/**
 * Page-scoped i18n bindings for Analysis, Clinical, Visualize, Run All, Prepare extras.
 */
import { t } from "./locale.js?v=2026-07-16-multi-demo";

function $(sel, root = document) {
  return root.querySelector(sel);
}
function $$(sel, root = document) {
  return [...root.querySelectorAll(sel)];
}

function setText(el, key, vars) {
  if (!el || !key) return;
  el.textContent = t(key, null, vars);
}

function setHtml(el, key) {
  if (!el || !key) return;
  el.innerHTML = t(key);
}

function setLabelFor(id, key) {
  const input = document.getElementById(id);
  const lab = input?.closest(".form-group")?.querySelector(":scope > label");
  if (!lab) return;
  const cb = lab.querySelector('input[type="checkbox"]');
  if (cb) {
    for (const n of lab.childNodes) {
      if (n.nodeType === Node.TEXT_NODE && n.textContent.trim()) {
        n.textContent = ` ${t(key)}`;
        return;
      }
    }
    lab.appendChild(document.createTextNode(` ${t(key)}`));
  } else if (!lab.querySelector("input, select, textarea")) {
    lab.textContent = t(key);
  }
}

function setWrapLabel(inputId, key) {
  const input = document.getElementById(inputId);
  const lab = input?.closest("label");
  if (!lab) return;
  for (const n of lab.childNodes) {
    if (n === input) break;
    if (n.nodeType === Node.TEXT_NODE && n.textContent.trim()) {
      n.textContent = t(key);
      return;
    }
  }
}

function setLastText(el, key) {
  if (!el) return;
  const nodes = [...el.childNodes];
  const tn = nodes.reverse().find((n) => n.nodeType === Node.TEXT_NODE && n.textContent.trim());
  if (tn) tn.textContent = ` ${t(key)}`;
  else el.appendChild(document.createTextNode(` ${t(key)}`));
}

function applySelectOptions(id, map) {
  const sel = document.getElementById(id);
  if (!sel) return;
  const cur = sel.value;
  [...sel.options].forEach((o) => {
    if (map[o.value]) o.textContent = t(map[o.value]);
  });
  if (cur) sel.value = cur;
}

function applyTableHead(tableId, keys) {
  const ths = $$(`#${tableId} thead th`);
  keys.forEach((key, i) => {
    if (ths[i] && key) ths[i].textContent = t(key);
  });
}

function applyClinicalPage() {
  const root = $("#page-clinical");
  if (!root) return;

  setText($("#page-clinical > .card:first-of-type > h2"), "clinical.pageTitle");
  setHtml($("#page-clinical > .card:first-of-type > p.hint"), "clinical.pageHint");

  setLabelFor("clin-analysis-strategy", "clinical.strategy");
  setHtml($("#clin-analysis-strategy")?.closest(".form-group")?.querySelector("small.hint"), "clinical.strategyHint");
  setLabelFor("clin-data-source", "clinical.dataSource");
  setLabelFor("clin-three-group", "clinical.threeGroup");
  setLabelFor("clin-three-max-levels", "clinical.maxLevels");
  setLabelFor("clin-three-engine", "clinical.threeEngine");
  setLabelFor("clin-systematic-cohort", "clinical.cohortFilter");
  setLabelFor("clin-three-skip-high-card", "clinical.skipHighCard");
  setHtml($("#clin-three-skip-high-card")?.closest(".form-group")?.querySelector("small.hint"), "clinical.skipHighCardHint");

  applySelectOptions("clin-analysis-strategy", {
    three_line: "clinical.threeLine",
    systematic: "clinical.systematic",
    reorient: "clinical.reorient",
    overview: "clinical.overview",
    cor: "clinical.optCor",
    fitline: "clinical.optFitline",
    wgcna: "clinical.optWgcna",
    marker_model: "clinical.optMarker",
  });
  applySelectOptions("clin-data-source", {
    auto: "clinical.srcAuto",
    experiment: "clinical.srcExperiment",
    standalone: "clinical.srcStandalone",
  });
  applySelectOptions("clin-three-engine", {
    gtsummary: "clinical.engineGtsummary",
    emp_custom: "clinical.engineEmp",
  });
  applySelectOptions("clin-systematic-cohort", {
    "": "clinical.cohortAll",
    IBS: "clinical.cohortIbs",
    UC: "clinical.cohortUc",
  });
  applySelectOptions("clin-reorient-mode", {
    auto: "clinical.reorientAuto",
    transpose: "clinical.reorientForce",
  });

  setLastText($("#clin-btn-refresh-vars"), "clinical.detectVars");
  setLastText($("#clin-btn-reorient"), "clinical.btnReorient");
  setLastText($("#clin-btn-three-line"), "clinical.btnThreeLine");
  setLastText($("#clin-btn-systematic"), "clinical.btnSystematic");

  applyTableHead("clin-vars-table", [
    "clinical.colName", "clinical.colType", "clinical.colN",
    "clinical.colUnique", "clinical.colMin", "clinical.colMax", "clinical.colMean",
  ]);

  // Section 1: correlation
  const corCard = $('[data-clinical-script="cor"]', root);
  if (corCard) {
    setText($("h2", corCard), "clinical.corTitle");
    setHtml($("p.hint", corCard), "clinical.corHint");
    setLabelFor("clin-cor-traits", "clinical.corTraits");
    setHtml($("#clin-cor-traits")?.closest(".form-group")?.querySelector("small.hint"), "clinical.multiSelectHint");
    setLabelFor("clin-cor-method", "common.method");
    setLabelFor("clin-cor-topn", "clinical.corTopN");
    setLabelFor("clin-cor-padj", "clinical.pAdj");
    applySelectOptions("clin-cor-method", {
      spearman: "clinical.methodSpearman",
      pearson: "clinical.methodPearson",
      kendall: "clinical.methodKendall",
    });
    applySelectOptions("clin-cor-padj", {
      BH: "clinical.padjBH",
      holm: "clinical.padjHolm",
      bonferroni: "clinical.padjBonf",
      none: "clinical.padjNone",
    });
    setLastText($("#clin-btn-cor"), "clinical.runCor");
    setLastText($("#clin-cor-pdf"), "common.downloadPdf");
    setText($("#clin-cor-table-wrap h3"), "clinical.topAssociations");
    applyTableHead("clin-cor-table", ["common.feature", "clinical.trait", "clinical.colR", "clinical.colP", "clinical.colPadj"]);
  }

  // Section 2: fitline
  const fitCard = $('[data-clinical-script="fitline"]', root);
  if (fitCard) {
    setText($("h2", fitCard), "clinical.fitTitle");
    setHtml($("p.hint", fitCard), "clinical.fitHint");
    setLabelFor("clin-fit-feature", "clinical.fitFeature");
    setHtml($("#clin-fit-feature")?.closest(".form-group")?.querySelector("small.hint"), "clinical.fitFeatureHint");
    setLabelFor("clin-fit-trait", "clinical.fitTrait");
    setLabelFor("clin-fit-group", "clinical.fitGroup");
    setLabelFor("clin-fit-method", "clinical.regression");
    setLabelFor("clin-fit-logy", "clinical.log1pY");
    applySelectOptions("clin-fit-method", { lm: "clinical.regLm", loess: "clinical.regLoess" });
    applySelectOptions("clin-fit-logy", { false: "common.no", true: "clinical.log1pYes" });
    const grp = $("#clin-fit-group");
    if (grp?.options[0]) grp.options[0].textContent = t("clinical.noGrouping");
    setLastText($("#clin-btn-fit"), "clinical.drawScatter");
    setLastText($("#clin-fit-pdf"), "common.downloadPdf");
  }

  // Section 3: WGCNA
  const wgcnaCard = $('[data-clinical-script="wgcna"]', root);
  if (wgcnaCard) {
    setText($("h2", wgcnaCard), "clinical.wgcnaTitle");
    setHtml($("p.hint", wgcnaCard), "clinical.wgcnaHint");
    setLabelFor("clin-wgcna-traits", "clinical.wgcnaTraits");
    setLabelFor("clin-wgcna-minmod", "clinical.minModuleSize");
    setLastText($("#clin-btn-wgcna"), "clinical.runWgcna");
    setLastText($("#clin-wgcna-pdf"), "common.downloadPdf");
    setText($("#clin-wgcna-table-wrap h3"), "clinical.wgcnaTop");
    applyTableHead("clin-wgcna-table", ["clinical.trait", "clinical.module", "clinical.colR", "clinical.colP", "clinical.colPadj"]);
  }

  // Section 4: marker model
  const mmCard = $('[data-clinical-script="marker_model"]', root);
  if (mmCard) {
    setText($("h2", mmCard), "clinical.markerTitle");
    setHtml($("p.hint", mmCard), "clinical.markerHint");
    setLabelFor("clin-marker-experiments", "clinical.markerExperiments");
    setHtml($("#clin-marker-experiments")?.closest(".form-group")?.querySelector("small.hint"), "clinical.markerExpHint");
    setLabelFor("clin-marker-outcome", "clinical.markerOutcome");
    setLabelFor("clin-marker-positive", "clinical.markerPositive");
    setLabelFor("clin-marker-methods", "clinical.markerModels");
    setLabelFor("clin-marker-max-features", "clinical.markerMaxFeat");
    setLabelFor("clin-marker-validation", "clinical.markerValidation");
    setHtml($("#clin-marker-validation")?.closest(".form-group")?.querySelector("small.hint"), "clinical.markerValHint");
    setLabelFor("clin-marker-include-clinical", "clinical.markerIncludeClinical");
    setLastText($("#clin-btn-marker-model"), "clinical.runMarker");
  }
}

function applyAnalysisPage() {
  const root = $("#page-analysis");
  if (!root) return;

  setLabelFor("ana-snapshot-select", "ana.snapshotTarget");
  setHtml($("#ana-snapshot-select")?.closest(".form-group")?.querySelector("small.hint"), "ana.snapshotHint");
  setHtml($("#page-analysis .card:nth-of-type(2) > p.hint"), "ana.coreSplit");

  const tabKeys = {
    "ana-alpha": "ana.tab.alpha",
    "ana-diff": "ana.tab.diff",
    "ana-dim": "ana.tab.dim",
    "ana-cor": "ana.tab.cor",
    "ana-cluster": "ana.tab.cluster",
    "ana-marker": "ana.tab.marker",
    "ana-enrich": "ana.tab.enrich",
    "ana-network": "ana.tab.network",
    "ana-tx": "ana.tab.tx",
    "ana-mgx": "ana.tab.mgx",
    "ana-mbx": "ana.tab.mbx",
    "ana-chipseq": "ana.tab.chipseq",
    "ana-cross": "ana.tab.cross",
  };
  $$(".tab-bar .tab", root).forEach((tab) => {
    const key = tabKeys[tab.dataset.tab];
    if (key) tab.textContent = t(key);
  });

  setText($("#ana-alpha h3"), "ana.alphaTitle");
  setLabelFor("alpha-method", "common.method");
  setLabelFor("alpha-source", "ana.dataSource");
  applySelectOptions("alpha-source", {
    current: "ana.srcCurrent",
    raw: "ana.srcRaw",
    relative: "ana.srcRelative",
  });
  setLastText($("#btn-alpha"), "common.run");

  setText($("#ana-diff h3"), "ana.diffTitle");
  setHtml($("#ana-diff > p.hint"), "ana.diffHint");
  setLabelFor("diff-method", "common.method");
  setLabelFor("diff-group", "ana.groupVar");
  setLabelFor("diff-comparison-mode", "ana.comparisonMode");
  setLabelFor("diff-ref", "ana.refGroup");
  setLabelFor("diff-test", "ana.testGroup");
  setLabelFor("diff-mode", "ana.runMode");
  setLabelFor("diff-filter-low", "ana.prefilterLow");
  setLabelFor("diff-subset", "ana.subset2");
  setLabelFor("diff-cores", "ana.cores");
  applySelectOptions("diff-comparison-mode", {
    pairwise: "ana.compPairwise",
    all_pairwise: "ana.compAllPairwise",
    multi_lrt: "ana.compMultiLrt",
  });
  applySelectOptions("diff-mode", { async: "ana.modeAsync", sync: "ana.modeSync" });
  applySelectOptions("diff-filter-low", { true: "common.yesFast", false: "common.no" });
  applySelectOptions("diff-subset", { true: "common.yesFast", false: "common.no" });
  setLastText($("#btn-diff"), "common.run");

  setText($("#ana-dim h3"), "ana.dimTitle");
  setHtml($("#ana-dim > p.hint"), "ana.dimHint");
  setLabelFor("dim-method", "common.method");
  setLastText($("#btn-dim"), "common.run");

  setText($("#ana-cor h3"), "ana.corTitle");
  setLabelFor("cor-method", "common.method");
  setLastText($("#btn-cor"), "common.run");

  setText($("#ana-cluster h3"), "ana.clusterTitle");
  setLabelFor("cluster-method", "common.method");
  setLabelFor("cluster-k", "ana.clusterK");
  setLastText($("#btn-cluster"), "common.run");

  setText($("#ana-marker h3"), "ana.markerTitle");
  setLastText($("#btn-marker"), "common.run");
  setText($("#ana-enrich h3"), "ana.enrichTitle");
  setLastText($("#btn-enrich"), "common.run");
  setText($("#ana-network h3"), "ana.networkTitle");
  setLastText($("#btn-network"), "common.run");
  setText($("#ana-tx h3"), "ana.txTitle");
  setLastText($("#tx-btn-profile"), "ana.profile");
  setLastText($("#tx-btn-diff"), "ana.tab.diff");
  setLastText($("#tx-btn-gsea"), "ana.gsea");
  setLastText($("#tx-btn-wgcna"), "ana.tab.network");
  setText($("#ana-mgx h3"), "ana.mgxTitle");
  setLastText($("#mgx-btn-profile"), "ana.profileMatrix");
  setLastText($("#mgx-btn-preprocess"), "ana.preprocess");
  setLastText($("#mgx-btn-diff"), "ana.runDiff");
  setLastText($("#mgx-btn-enrich"), "ana.runEnrich");
  setText($("#ana-mbx h3"), "ana.mbxTitle");
  setLastText($("#mbx-btn-profile"), "ana.profileDefaults");
  setLastText($("#mbx-btn-preprocess"), "ana.runPreprocess");
  setLastText($("#mbx-btn-diff"), "ana.runDiff");
  setLastText($("#mbx-btn-volcano"), "viz.volcanoGen");
  setText($("#ana-cross h3"), "ana.crossTitle");
  setLastText($("#btn-cross-omics-cor"), "ana.crossCor");
  setLastText($("#btn-cross-omics-clin"), "ana.crossClin");
}

function applyVisualizationPage() {
  const root = $("#page-visualization");
  if (!root) return;

  setLabelFor("viz-snapshot-select", "viz.snapshotTarget");
  setHtml($("#viz-snapshot-select")?.closest(".form-group")?.querySelector("small.hint"), "viz.snapshotHint");

  const tabKeys = {
    "viz-barplot": "viz.tab.barplot",
    "viz-boxplot": "viz.tab.boxplot",
    "viz-heatmap": "viz.tab.heatmap",
    "viz-volcano": "viz.tab.volcano",
    "viz-scatter": "viz.tab.scatter",
    "viz-structure": "viz.tab.structure",
    "viz-alpha": "viz.tab.alpha",
    "viz-tx": "viz.tab.tx",
    "viz-m16s-sankey": "viz.tab.sankey",
    "viz-m16s-network": "viz.tab.network",
    "viz-mgx": "viz.tab.mgx",
  };
  $$(".tab-bar .tab", root).forEach((tab) => {
    const key = tabKeys[tab.dataset.tab];
    if (key) tab.textContent = t(key);
  });

  setLabelFor("viz-color-panel", "viz.colorPanel");
  setLabelFor("viz-use-custom-colors", "viz.customColors");
  setHtml($("#viz-use-custom-colors")?.closest(".form-group")?.querySelector("small.hint"), "viz.colorHint");
  setLabelFor("viz-figure-scale", "viz.figureScale");
  setHtml($("#viz-figure-scale")?.closest(".form-group")?.querySelector("small.hint"), "viz.figureScaleHint");
  setLabelFor("viz-lock-aspect", "viz.lockAspect");
  setLabelFor("viz-axis-text-x", "viz.axisTextX");
  setLabelFor("viz-axis-text-y", "viz.axisTextY");
  setLabelFor("viz-axis-title-x", "viz.axisTitleX");
  setLabelFor("viz-axis-title-y", "viz.axisTitleY");

  setText($("#viz-barplot h3"), "viz.barplotTitle");
  setLabelFor("bar-mode", "viz.mode");
  setLabelFor("bar-group", "ana.groupVar");
  setLabelFor("bar-topn", "viz.topN");
  setLabelFor("bar-feature", "common.feature");
  applySelectOptions("bar-mode", { top20: "viz.modeTopN", single: "viz.modeSingle" });
  setLastText($("#btn-barplot"), "viz.generate");

  setText($("#viz-boxplot h3"), "viz.boxplotTitle");
  setLabelFor("box-group", "ana.groupVar");
  setLabelFor("box-feature", "common.feature");
  setLastText($("#btn-boxplot"), "viz.generate");

  setText($("#viz-heatmap h3"), "viz.heatmapTitle");
  setHtml($("#viz-heatmap > p.hint"), "viz.heatmapHint");
  setLabelFor("heat-group", "ana.groupVar");
  setLabelFor("heat-topn", "viz.topNVariance");
  setLabelFor("heat-cluster-rows", "viz.clusterRows");
  setLabelFor("heat-cluster-cols", "viz.clusterCols");
  setLabelFor("heat-show-rn", "viz.showNames");
  setLabelFor("heat-font-size", "viz.fontSize");
  applySelectOptions("heat-cluster-rows", { true: "common.yes", false: "common.no" });
  applySelectOptions("heat-cluster-cols", { true: "common.yes", false: "common.no" });
  applySelectOptions("heat-show-rn", { true: "common.yes", false: "common.no" });
  setWrapLabel("heat-custom", "viz.customList");
  setLastText($("#btn-heatmap"), "viz.topVarHeatmap");
  setLastText($("#btn-heatmap-custom"), "viz.customHeatmap");
  setLastText($("#heat-custom-clear"), "viz.clearList");
  setText($("#viz-heatmap h4"), "viz.degHeatmap");

  setText($("#viz-volcano h3"), "viz.volcanoTitle");
  setLastText($("#btn-volcano"), "viz.generate");
  setLastText($("#vol-pdf-link"), "common.downloadPdf");
  setText($("#viz-scatter h3"), "viz.scatterTitle");
  setLastText($("#btn-scatter"), "viz.generate");
  setText($("#viz-structure h3"), "viz.structureTitle");
  setLastText($("#btn-structure"), "viz.generate");
  setText($("#viz-alpha h3"), "viz.alphaPlotTitle");
  setLastText($("#btn-alpha-plot"), "viz.generate");
  setText($("#viz-tx h3"), "viz.txVizTitle");
  setLastText($("#tx-btn-heatmap"), "viz.tab.heatmap");
  setLastText($("#tx-btn-volcano"), "viz.tab.volcano");
  setText($("#viz-m16s-sankey h3"), "viz.sankeyTitle");
  setLastText($("#m16s-btn-sankey"), "viz.sankeyGen");
  setText($("#viz-m16s-network h3"), "viz.m16sNetTitle");
  setLastText($("#m16s-btn-network"), "viz.m16sNetGen");
  setText($("#viz-mgx h3"), "viz.mgxVizTitle");
  setLastText($("#mgx-btn-heatmap"), "viz.funcHeatmap");
  setLastText($("#mgx-btn-volcano"), "viz.funcVolcano");
  setLastText($("#btn-deg-heatmap"), "viz.degHeatmapBtn");
}

function applyRunAllPage() {
  const root = $("#page-runall");
  if (!root) return;

  setText($("#page-runall > .card > h2"), "runall.pageTitle");
  setHtml($("#page-runall > .card > p.hint"), "runall.pageHint");

  setLabelFor("ra-pipeline", "runall.pipeline");
  setLabelFor("ra-group", "runall.groupVar");
  setLabelFor("ra-ref", "runall.refGroup");
  setLabelFor("ra-test", "runall.testGroup");
  setLabelFor("ra-organism", "runall.organism");
  setLabelFor("ra-fc", "runall.fcCutoff");
  setLabelFor("ra-p", "runall.pCutoff");
  setLabelFor("ra-use-padj", "runall.threshold");
  setLabelFor("ra-min-rowsum", "runall.minRowSum");
  setLabelFor("ra-enrich", "runall.enrichment");
  setLabelFor("ra-tax-level", "runall.taxLevel");
  setLabelFor("ra-alpha", "runall.primaryAlpha");
  setLabelFor("ra-ord", "runall.primaryOrd");

  applySelectOptions("ra-pipeline", {
    rnaseq: "runall.pipeRnaseq",
    m16s: "runall.pipeM16s",
  });
  applySelectOptions("ra-use-padj", { true: "runall.padjAuto", false: "runall.pvalue" });
  applySelectOptions("ra-enrich", { true: "runall.enrichInclude", false: "runall.enrichSkip" });

  setHtml($("#ra-alpha")?.closest(".form-group")?.querySelector("small.hint"), "runall.alphaHint");
  setHtml($("#ra-ord")?.closest(".form-group")?.querySelector("small.hint"), "runall.ordHint");

  const prev = $("#ra-bundles")?.previousElementSibling;
  if (prev?.tagName === "H3") prev.textContent = t("runall.prevBundles");
}

function applyPrepareExtras() {
  setText($("#prep-rarefy h3"), "prep.rarefyTitle");
  setHtml($("#prep-rarefy > p.hint"), "prep.rarefyHint");
  setLabelFor("rarefy-size", "prep.sampleSize");
  setLastText($("#btn-rarefy"), "prep.rarefyBtn");

  setText($("#prep-collapse h3"), "prep.collapseTitle");
  setHtml($("#prep-collapse > p.hint"), "prep.collapseHint");
  setLabelFor("collapse-level", "prep.targetLevel");
  setLastText($("#btn-collapse"), "prep.collapseBtn");

  setText($("#prep-m16s-taxonomy h3"), "prep.m16sTaxTitle");
}

export function applyPagesI18n() {
  applyClinicalPage();
  applyAnalysisPage();
  applyVisualizationPage();
  applyRunAllPage();
  applyPrepareExtras();
}
