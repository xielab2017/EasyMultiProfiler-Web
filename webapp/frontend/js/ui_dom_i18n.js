/**
 * Maps static DOM nodes in index.html to i18n keys (bulk labeling without tagging every node).
 * attr: text | html | title | placeholder | aria | value
 */
import { t } from "./locale.js?v=2026-06-21-v5.0.2";
import { applyPagesI18n } from "./i18n_pages.js?v=2026-06-21-v5.0.2";

export const DOM_I18N = [
  { sel: "#gp-label", key: "common.working" },
  { sel: ".omics-switch-label", key: "omics.label" },
  { sel: "#omics-pipeline option[value='all']", key: "omics.all" },
  { sel: "#omics-pipeline option[value='transcriptomics']", key: "omics.transcriptomics" },
  { sel: "#omics-pipeline option[value='microbiome_16s']", key: "omics.microbiome_16s" },
  { sel: "#omics-pipeline option[value='metagenomics']", key: "omics.metagenomics" },
  { sel: "#omics-pipeline option[value='metabolomics']", key: "omics.metabolomics" },
  { sel: "#session-label", key: "common.sessionActive" },
  { sel: ".perf-title", key: "common.lastRun" },
  { sel: "label[for='global-experiment']", key: "topbar.experiment" },
  { sel: "#btn-topbar-clear", key: "topbar.clearAll" },
  { sel: "#btn-topbar-clear", key: "topbar.clearAllTitle", attr: "title" },
  { sel: "#step-timing", key: "topbar.timingTitle", attr: "title" },
  { sel: ".code-lab-console-title", key: "codelab.consoleTitle" },
  { sel: "#code-lab-console-clear", key: "codelab.consoleClear" },
  { sel: ".code-lab-exec-placeholder", key: "codelab.placeholder" },
  { sel: ".teaching-tab[data-teaching-tab='cases']", key: "course.tab.cases" },
  { sel: ".teaching-tab[data-teaching-tab='critique']", key: "course.tab.critique" },
  { sel: "#page-prompts .card h2", key: "prompts.title" },
  { sel: "#page-prompts .card .hint", key: "prompts.hint" },
  { sel: "#welcome-card h2", key: "welcome.title" },
  { sel: "#welcome-card > .hint", key: "welcome.body" },
  { sel: "#btn-welcome-guide", key: "welcome.btnGuide" },
  { sel: "#btn-welcome-course", key: "welcome.btnCourse" },
  { sel: "#btn-welcome-dismiss", key: "welcome.btnDismiss" },
  { sel: ".demo-datasets-card h2", key: "demo.title" },
  { sel: ".demo-datasets-card > .hint", key: "demo.hint" },
  { sel: "#page-import .card[data-clinical-script] > h2", key: "import.uploadTitle" },
  { sel: "#page-import .card[data-clinical-script] > .hint", key: "import.uploadHint" },
  { sel: "#import-data-label", key: "import.countMatrix" },
  { sel: "#drop-data .hint", key: "import.rowsCols" },
  { sel: "#import-meta-label", key: "import.metadata" },
  { sel: "#drop-meta .hint", key: "import.metaFirstCol" },
  { sel: "#drop-data label[for='import-data-file']", key: "common.chooseFile" },
  { sel: "#drop-meta label[for='import-meta-file']", key: "common.chooseFile" },
  { sel: "#btn-import", key: "import.btn", attr: "lastText" },
  { sel: "#workflow-blueprint h3", key: "import.blueprintTitle" },
  { sel: "#workflow-blueprint > .hint", key: "import.blueprintHint" },
  { sel: "#import-experiments h3", key: "import.loadedTitle" },
  { sel: "#btn-clear-session", key: "import.clearLoaded", attr: "lastText" },
  { sel: "#page-summary .section-head h2", key: "summary.title" },
  { sel: "#btn-summary-export-empt", key: "summary.exportEmpt", attr: "lastText" },
  { sel: "#page-summary .card:nth-child(2) h3", key: "summary.coldata" },
  { sel: "#page-summary .card:nth-child(3) h3", key: "summary.features" },
  { sel: "#page-inspector .teaching-hint-card .hint", key: "inspector.hint", attr: "html" },
  { sel: "#page-inspector .section-head h2", key: "inspector.title" },
  { sel: "#btn-inspector-refresh", key: "common.refresh", attr: "lastText" },
  { sel: ".tab[data-tab='inspector-assay']", key: "inspector.tab.assay" },
  { sel: ".tab[data-tab='inspector-coldata']", key: "inspector.tab.coldata" },
  { sel: ".tab[data-tab='inspector-rowdata']", key: "inspector.tab.rowdata" },
  { sel: ".tab[data-tab='inspector-results']", key: "inspector.tab.results" },
  { sel: "#btn-inspector-assay-prev", key: "common.prev" },
  { sel: "#btn-inspector-assay-next", key: "common.next" },
  { sel: "#btn-inspector-rowdata-prev", key: "common.prev" },
  { sel: "#btn-inspector-rowdata-next", key: "common.next" },
  { sel: "#inspector-results label", key: "inspector.resultTable" },
  { sel: "#btn-inspector-load-result", key: "inspector.loadResult", attr: "lastText" },
  { sel: "#page-preparation > .card:first-child > .hint", key: "prep.quickGuide", attr: "html" },
  { sel: "#btn-prep-recommended", key: "prep.recommended", attr: "lastText" },
  { sel: "#btn-prep-recommended", key: "prep.recommendedTitle", attr: "title" },
  { sel: "#btn-prep-recommended + .hint", key: "prep.recommendedHint" },
  { sel: "#btn-prep-refresh-snapshots", key: "common.refresh" },
  { sel: "#btn-prep-use-snapshot", key: "prep.useSelected" },
  { sel: "#page-preparation .card:nth-child(2) h3", key: "prep.previewTitle" },
  { sel: "#page-preparation .card:nth-child(2) > .hint", key: "prep.previewHint" },
  { sel: ".tab[data-tab='prep-filter']", key: "prep.tab.filter" },
  { sel: ".tab[data-tab='prep-normalize']", key: "prep.tab.normalize" },
  { sel: ".tab[data-tab='prep-impute']", key: "prep.tab.impute" },
  { sel: ".tab[data-tab='prep-rarefy']", key: "prep.tab.rarefy" },
  { sel: ".tab[data-tab='prep-collapse']", key: "prep.tab.collapse" },
  { sel: ".tab[data-tab='prep-m16s-taxonomy']", key: "prep.tab.m16sTax" },
  { sel: "#prep-mode", key: "prep.mode", attr: "formLabel" },
  { sel: "#prep-snapshot-select", key: "prep.snapshot", attr: "formLabel" },
  { sel: "#prep-filter h3", key: "prep.filterTitle" },
  { sel: "#btn-filter", key: "prep.applyFilter", attr: "lastText" },
  { sel: "#prep-normalize h3", key: "prep.normTitle" },
  { sel: "#btn-normalize", key: "prep.normBtn", attr: "lastText" },
  { sel: "#btn-normalize-export-assay", key: "prep.normExport", attr: "lastText" },
  { sel: "#prep-impute h3", key: "prep.imputeTitle" },
  { sel: "#btn-impute", key: "prep.imputeBtn", attr: "lastText" },
  { sel: "#page-export > .card:first-child h2", key: "export.title" },
  { sel: "#page-export > .card:first-child > .hint", key: "export.hint" },
  { sel: "#page-export .export-card:nth-child(1) h3", key: "export.assay" },
  { sel: "#page-export .export-card:nth-child(1) p", key: "export.assayDesc" },
  { sel: "#btn-export-assay", key: "common.downloadCsv" },
  { sel: "#page-export .export-card:nth-child(2) h3", key: "export.coldata" },
  { sel: "#page-export .export-card:nth-child(2) p", key: "export.coldataDesc" },
  { sel: "#btn-export-coldata", key: "common.downloadCsv" },
  { sel: "#page-export .export-card:nth-child(3) h3", key: "export.diff" },
  { sel: "#page-export .export-card:nth-child(3) p", key: "export.diffDesc" },
  { sel: "#btn-export-diff", key: "common.downloadCsv" },
  { sel: "#page-export .export-card:nth-child(4) h3", key: "export.mgxDiff" },
  { sel: "#page-export .export-card:nth-child(4) p", key: "export.mgxDiffDesc" },
  { sel: "#mgx-btn-export-diff", key: "common.downloadCsv" },
  { sel: "#page-export .export-card:nth-child(5) h3", key: "export.alpha" },
  { sel: "#page-export .export-card:nth-child(5) p", key: "export.alphaDesc" },
  { sel: "#btn-export-alpha", key: "common.downloadCsv" },
  { sel: "#page-export .export-card:nth-child(6) h3", key: "export.rds" },
  { sel: "#page-export .export-card:nth-child(6) p", key: "export.rdsDesc" },
  { sel: "#btn-export-rds", key: "common.downloadRds" },
  { sel: ".teaching-export-card h3", key: "export.teachingReport" },
  { sel: ".teaching-export-card p", key: "export.teachingReportDesc" },
  { sel: "#btn-teaching-report", key: "export.teachingReportBtn" },
  { sel: "#teaching-journal-card h2", key: "export.journalTitle" },
  { sel: "#teaching-journal-card > .hint", key: "export.journalHint" },
  { sel: "#btn-teaching-journal-save", key: "export.journalSave" },
  { sel: "#btn-run-all", key: "runall.runAll", attr: "lastText" },
  { sel: "#btn-run-all-smart", key: "runall.smartDefaults", attr: "lastText" },
  { sel: "#btn-run-all-smart", key: "runall.smartTitle", attr: "title" },
  { sel: "#btn-run-all-cancel", key: "runall.cancel", attr: "lastText" },
  { sel: "#ra-download", key: "runall.downloadBundle", attr: "lastText" },
  { sel: "#ra-progress-msg", key: "runall.queued" },
  { sel: "#page-runall #ra-bundles", key: "runall.prevBundles", attr: "prevHeading" },
  { sel: "#clin-btn-reorient", key: "clinical.btnReorient", attr: "lastText" },
  { sel: "#clin-btn-three-line", key: "clinical.btnThreeLine", attr: "lastText" },
  { sel: "#clin-btn-systematic", key: "clinical.btnSystematic", attr: "lastText" },
  { sel: "#clin-analysis-strategy", key: "clinical.strategy", attr: "formLabel" },
  { sel: "#clin-analysis-strategy + .hint", key: "clinical.strategyHint" },
];

function setLabelFor(id, text) {
  const lab = document.querySelector(`label[for="${id}"]`);
  if (lab) lab.textContent = text;
}

function setLastTextNode(el, text) {
  if (!el) return;
  const nodes = [...el.childNodes];
  const textNode = nodes.reverse().find((n) => n.nodeType === Node.TEXT_NODE && n.textContent.trim());
  if (textNode) textNode.textContent = text.startsWith(" ") ? ` ${text}` : ` ${text}`;
  else el.appendChild(document.createTextNode(` ${text}`));
}

function setFormGroupLabel(inputId, text) {
  const input = document.getElementById(inputId);
  const lab = input?.closest(".form-group")?.querySelector(":scope > label");
  if (lab && !lab.querySelector("input, select, textarea")) lab.textContent = text;
}

function setWrapLabelText(inputId, text) {
  const input = document.getElementById(inputId);
  const lab = input?.closest("label");
  if (!lab) return;
  for (const n of lab.childNodes) {
    if (n === input) break;
    if (n.nodeType === Node.TEXT_NODE && n.textContent.trim()) {
      n.textContent = text;
      return;
    }
  }
}

function applyBinding({ sel, key, attr = "text", labelFor }) {
  const el = document.querySelector(sel);
  if (!el) return;
  const val = t(key);
  if (attr === "label" && labelFor) {
    setLabelFor(labelFor, val);
    return;
  }
  if (attr === "formLabel") {
    setFormGroupLabel(sel.replace(/^#/, ""), val);
    return;
  }
  if (attr === "prevHeading") {
    const prev = document.querySelector(sel)?.previousElementSibling;
    if (prev?.tagName === "H3") prev.textContent = val;
    return;
  }
  if (attr === "html") el.innerHTML = val;
  else if (attr === "title") el.title = val;
  else if (attr === "placeholder") el.placeholder = val;
  else if (attr === "aria") el.setAttribute("aria-label", val);
  else if (attr === "lastText") setLastTextNode(el, val);
  else el.textContent = val;
}

export function applyDomI18n() {
  DOM_I18N.forEach(applyBinding);
  applyImportSelectOptions();
  applyPrepModeOptions();
  applyClinicalOptions();
  applyImportFormLabels();
  applyJournalLabels();
  setFormGroupLabel("prep-mode", t("prep.mode"));
  setFormGroupLabel("prep-snapshot-select", t("prep.snapshot"));
  applyPagesI18n();
}

function applyImportFormLabels() {
  setFormGroupLabel("import-data-type", t("import.dataType"));
  setFormGroupLabel("import-clinical-kind", t("import.clinicalKind"));
  setFormGroupLabel("import-exp-name", t("import.expName"));
  setFormGroupLabel("import-assay-name", t("import.assayName"));
  setFormGroupLabel("import-start-level", t("import.taxLevel"));
  setFormGroupLabel("import-tax-sep", t("import.taxSep"));
}

function applyJournalLabels() {
  setWrapLabelText("teaching-journal-interpretation", t("export.journalInterp"));
  setWrapLabelText("teaching-journal-hypothesis", t("export.journalHyp"));
  setWrapLabelText("teaching-journal-limitations", t("export.journalLimit"));
  setWrapLabelText("teaching-journal-ai", t("export.journalAi"));
  const ph = {
    "teaching-journal-interpretation": "export.journalInterpPh",
    "teaching-journal-hypothesis": "export.journalHypPh",
    "teaching-journal-ai": "export.journalAiPh",
  };
  Object.entries(ph).forEach(([id, key]) => {
    const el = document.getElementById(id);
    if (el) el.placeholder = t(key);
  });
}

function applyImportSelectOptions() {
  const dt = document.getElementById("import-data-type");
  if (dt) {
    const map = {
      normal: "import.dataType.normal",
      tax: "import.dataType.tax",
      clinical: "import.dataType.clinical",
    };
    [...dt.options].forEach((o) => {
      if (map[o.value]) o.textContent = t(map[o.value]);
    });
  }
  const ck = document.getElementById("import-clinical-kind");
  if (ck) {
    const map = { clinical_raw: "import.clinicalRaw", clinical_meta: "import.clinicalMeta" };
    [...ck.options].forEach((o) => {
      if (map[o.value]) o.textContent = t(map[o.value]);
    });
  }
}

function applyPrepModeOptions() {
  const sel = document.getElementById("prep-mode");
  if (!sel) return;
  const map = { stack: "prep.modeStack", single: "prep.modeSingle" };
  [...sel.options].forEach((o) => {
    if (map[o.value]) o.textContent = t(map[o.value]);
  });
}

function applyClinicalOptions() {
  const sel = document.getElementById("clin-analysis-strategy");
  if (!sel) return;
  const map = {
    three_line: "clinical.threeLine",
    systematic: "clinical.systematic",
    reorient: "clinical.reorient",
    overview: "clinical.overview",
  };
  [...sel.options].forEach((o) => {
    if (map[o.value]) o.textContent = t(map[o.value]);
  });
}
