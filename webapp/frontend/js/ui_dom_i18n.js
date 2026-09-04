/**
 * Maps static DOM nodes in index.html to i18n keys (bulk labeling without tagging every node).
 * attr: text | html | title | placeholder | aria | value
 */
import { t } from "./locale.js?v=nav-active-fix-v1";

export const DOM_I18N = [
  // --- added 2026-09-03: 10 ChIP-seq downstream labels that never switched language
  { sel: "#chipds-btn-use-uploaded-peaks", key: "chipds.useUploadedPeaks" },
  { sel: "#chipds-btn-refresh-peaks", key: "chipds.refreshPeakList" },
  { sel: "#chipds-btn-refresh-tools", key: "chipds.reDetectTools" },
  { sel: "#chipds-panel-homer summary:nth-of-type(1)", key: "chipds.panelHomer" },
  { sel: "#chipds-btn-homer", key: "chipds.runHomer" },
  { sel: "#chipds-panel-diffbind summary:nth-of-type(1)", key: "chipds.panelDiffBind" },
  { sel: "#chipds-btn-diffbind", key: "chipds.runDiffBind" },
  { sel: "#chipds-panel-peaksops summary:nth-of-type(1)", key: "chipds.panelPeakOps" },
  { sel: "#chipds-panel-deeptools summary:nth-of-type(1)", key: "chipds.panelDeepTools" },
  { sel: "#chipds-btn-deeptools", key: "chipds.runDeepTools" },
  { sel: "#gp-label", key: "common.working" },
  { sel: ".omics-switch-label", key: "omics.label" },
  { sel: "#omics-pipeline option[value='all']", key: "omics.all" },
  { sel: "#omics-pipeline option[value='transcriptomics']", key: "omics.transcriptomics" },
  { sel: "#omics-pipeline option[value='chipseq']", key: "omics.chipseq" },
  { sel: "#omics-pipeline option[value='microbiome_16s']", key: "omics.microbiome_16s" },
  { sel: "#omics-pipeline option[value='metagenomics']", key: "omics.metagenomics" },
  { sel: "#omics-pipeline option[value='metabolomics']", key: "omics.metabolomics" },
  { sel: "#omics-pipeline option[value='clinical']", key: "omics.clinical" },
  { sel: "#omics-pipeline option[value='multiomics']", key: "omics.multiomics" },
  { sel: "#omics-pipeline option[value='customize']", key: "omics.customize" },
  { sel: '.nav-item[data-page="chipseq"] span', key: "nav.chipseq" },
  { sel: '.nav-item[data-page="chipseq_downstream"] span', key: "nav.chipseq_downstream" },
  { sel: "#chip-btn-browse-folder span", key: "chip.browseFolder" },
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
  { sel: "#clin-btn-cor-auto-config", key: "clinical.btnAutoConfig", attr: "lastText" },
  { sel: "#clin-btn-fit-auto-config", key: "clinical.btnAutoConfig", attr: "lastText" },
  { sel: "#clin-btn-wgcna-auto-config", key: "clinical.btnAutoConfig", attr: "lastText" },
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
  // Page-scoped bindings (clinical / analysis / …) are applied separately from
  // locale.applyDocumentLocale so a throw here cannot leave Clinical stuck in zh.
  DOM_I18N.forEach(applyBinding);
  applyImportSelectOptions();
  applyPrepModeOptions();
  applyClinicalOptions();
  applyImportFormLabels();
  applyJournalLabels();
  applyUploadCardsI18n();
  applyChipdsFilterI18n();
  applyChipDepsStaticI18n();
  setFormGroupLabel("prep-mode", t("prep.mode"));
  setFormGroupLabel("prep-snapshot-select", t("prep.snapshot"));
}

const UPLOAD_TYPE_KEYS = {
  transcriptomics: "tx",
  proteomics: "pro",
  microbiome_16s: "m16s",
  metagenomics: "mgx",
  metabolomics: "mbx",
  chipseq: "chip",
  clinical: "clinical",
};

function applyUploadCardsI18n() {
  const hint = document.querySelector("#page-import .card[data-clinical-script] > .hint");
  if (hint) hint.innerHTML = t("upload.pageHint");

  document.querySelectorAll(".upload-card[data-upload-type]").forEach((card) => {
    const type = card.dataset.uploadType;
    const short = UPLOAD_TYPE_KEYS[type];
    if (!short) return;
    const h3 = card.querySelector("header h3");
    if (h3) h3.textContent = t(`upload.card.${short}`);

    const cardHint = card.querySelector(":scope > .hint");
    if (cardHint && ["mgx", "chip", "clinical"].includes(short)) {
      cardHint.innerHTML = t(`upload.hint.${short}`);
    }

    card.querySelectorAll(".form-group > label").forEach((lab) => {
      const sel = lab.parentElement?.querySelector("select, input");
      if (!sel) return;
      if (sel.classList.contains("upload-import-mode")) lab.textContent = t("upload.importMode");
      else if (sel.classList.contains("upload-exp-name")) {
        lab.textContent = short === "clinical" ? t("upload.clinicalTableName") : t("upload.expName");
      } else if (sel.classList.contains("upload-assay-name")) lab.textContent = t("upload.assayName");
      else if (sel.classList.contains("upload-start-level")) lab.textContent = t("upload.taxLevel");
      else if (sel.classList.contains("upload-tax-sep")) lab.textContent = t("upload.taxSep");
      else if (sel.classList.contains("upload-genome")) lab.textContent = t("upload.genome");
      else if (sel.classList.contains("upload-preset")) lab.textContent = t("upload.assayMeta");
      else if (sel.classList.contains("upload-clinical-kind")) lab.textContent = t("upload.clinicalKind");
    });

    const modeSel = card.querySelector(".upload-import-mode");
    if (modeSel) {
      [...modeSel.options].forEach((o) => {
        if (o.value === "matrix") o.textContent = t(`upload.mode.matrix.${short}`);
        else if (o.value === "diff_raw") {
          if (short === "m16s") o.textContent = t("upload.mode.diff.marker");
          else if (short === "mgx") o.textContent = t("upload.mode.diff.func");
          else o.textContent = t("upload.mode.diff");
        }
      });
    }
    const clinKind = card.querySelector(".upload-clinical-kind");
    if (clinKind) {
      [...clinKind.options].forEach((o) => {
        if (o.value === "clinical_raw") o.textContent = t("import.clinicalRaw");
        if (o.value === "clinical_meta") o.textContent = t("import.clinicalMeta");
      });
    }

    const dataLabel = card.querySelector(".upload-data-label");
    if (dataLabel) {
      dataLabel.dataset.matrixLabelKey = `upload.dataLabel.${short}`;
      const isDiff = card.querySelector(".upload-import-mode")?.value === "diff_raw";
      dataLabel.textContent = isDiff ? t("upload.dataLabel.diff") : t(`upload.dataLabel.${short}`);
    }

    const rowsHint = card.querySelector(".upload-matrix-only.hint, .hint.upload-matrix-only");
    if (rowsHint && ["tx", "pro", "mgx", "mbx"].includes(short)) {
      rowsHint.textContent = t(`upload.rows.${short}`);
    }
    card.querySelectorAll(".upload-diff-only.hint, .hint.upload-diff-only").forEach((el) => {
      el.textContent = t("upload.diffHint");
    });

    card.querySelectorAll(".drop-meta p strong, .upload-zone.drop-meta p strong").forEach((el) => {
      if (short === "m16s") el.textContent = t("upload.metaSampleOptional");
      else if (short === "clinical") el.textContent = t("upload.metaCompanion");
      else el.textContent = t("upload.metaOptional");
    });

    card.querySelectorAll("label.btn[for^='upload-']").forEach((lab) => {
      lab.textContent = short === "chip" && lab.getAttribute("for")?.includes("chipseq")
        ? t("upload.choosePeak")
        : t("upload.chooseFile");
    });

    const btn = card.querySelector(".upload-btn");
    if (btn) {
      const icon = btn.querySelector("i")?.outerHTML || "";
      const isDiff = card.querySelector(".upload-import-mode")?.value === "diff_raw";
      const key = isDiff && short !== "chip" && short !== "clinical"
        ? `upload.btnDiff.${short}`
        : `upload.btn.${short}`;
      btn.dataset.labelMatrixKey = `upload.btn.${short}`;
      if (short !== "chip" && short !== "clinical") btn.dataset.labelDiffKey = `upload.btnDiff.${short}`;
      btn.innerHTML = `${icon} ${t(key)}`.trim();
    }
  });

  const goChip = document.getElementById("btn-go-chipseq");
  if (goChip) {
    const icon = goChip.querySelector("i")?.outerHTML || "";
    goChip.innerHTML = `${icon} ${t("upload.btn.openChip")}`.trim();
  }

  const chipPeakP = document.querySelector('.upload-card[data-upload-type="chipseq"] .drop-data p');
  if (chipPeakP && !chipPeakP.querySelector(".upload-data-label")) {
    chipPeakP.innerHTML = `<strong>${t("upload.dataLabel.chip")}</strong> ${t("upload.peakFileFmt")}`;
  } else if (chipPeakP?.querySelector(".upload-data-label")) {
    /* handled above */
  } else {
    const p = document.querySelector('.upload-card[data-upload-type="chipseq"] .upload-zone.drop-data > p');
    if (p) p.innerHTML = `<strong>${t("upload.dataLabel.chip")}</strong> ${t("upload.peakFileFmt")}`;
  }
}

function applyChipdsFilterI18n() {
  const maps = {
    "chipds-filter-priority": {
      "": "chipds.opt.all",
      must: "chipds.opt.must",
      recommend: "chipds.opt.recommend",
      advanced: "chipds.opt.advanced",
      optional: "chipds.opt.optional",
    },
    "chipds-filter-bam": {
      "": "chipds.opt.all",
      no: "chipds.opt.bamNo",
      yes: "chipds.opt.bamYes",
    },
    "chipds-filter-status": {
      "": "chipds.opt.all",
      available: "chipds.opt.available",
      planned: "chipds.opt.planned",
    },
  };
  Object.entries(maps).forEach(([id, map]) => {
    const sel = document.getElementById(id);
    if (!sel) return;
    [...sel.options].forEach((o) => {
      if (map[o.value] != null) o.textContent = t(map[o.value]);
    });
  });
  const stage = document.getElementById("chipds-filter-stage");
  if (stage?.options?.[0] && !stage.options[0].value) {
    stage.options[0].textContent = t("chipds.opt.allStages");
  }
  const search = document.getElementById("chipds-search");
  if (search) search.placeholder = t("chipds.searchPh");
}

function applyChipDepsStaticI18n() {
  const labelMap = [
    ["chip-deps-peak", "chip.deps.peak"],
    ["chip-deps-assay", "chip.deps.assay"],
    ["chip-deps-rna", "chip.label.rnaseq"],
    ["chip-deps-proteomics", "chip.label.proteomics"],
    ["chip-deps-m16s", "omics.microbiome_16s"],
    ["chip-deps-mgx", "omics.metagenomics"],
    ["chip-deps-mbx", "omics.metabolomics"],
    ["chip-deps-clinical", "omics.clinical"],
  ];
  labelMap.forEach(([id, key]) => {
    const lab = document.querySelector(`label[for="${id}"]`);
    if (lab) lab.textContent = t(key);
  });
  document.querySelectorAll("#chip-recipe-deps .form-group").forEach((fg) => {
    if (fg.querySelector("#chip-deps-bam")) {
      const lab = fg.querySelector("label");
      if (lab) lab.textContent = t("chip.deps.bam");
    }
  });
  const refresh = document.getElementById("chip-deps-refresh");
  if (refresh) refresh.textContent = t("chip.deps.refresh");
  const comboRun = document.getElementById("chip-recipe-combo-run");
  if (comboRun) {
    const icon = comboRun.querySelector("i")?.outerHTML || "";
    comboRun.innerHTML = `${icon} ${t("chip.recipe.comboRun")}`.trim();
  }
  const results = document.getElementById("chip-recipe-results");
  if (results && results.querySelector(":scope > .hint") && results.children.length === 1) {
    results.querySelector(".hint").textContent = t("chip.recipe.resultsHint");
  }
  document.querySelectorAll("#chip-btn-goto-step2, #chip-btn-goto-step2-b").forEach((btn) => {
    const icon = btn.querySelector("i")?.outerHTML || "";
    btn.innerHTML = `${icon} ${t("chip.btn.gotoStep2Short")}`.trim();
  });
  // empty peak / none options in static HTML
  ["chip-deps-peak", "chip-deps-rna", "chip-deps-proteomics", "chip-deps-m16s", "chip-deps-mgx", "chip-deps-mbx", "chip-deps-clinical"]
    .forEach((id) => {
      const sel = document.getElementById(id);
      if (!sel) return;
      [...sel.options].forEach((o) => {
        if (!o.value) {
          o.textContent = id === "chip-deps-peak" ? t("chip.opt.noPeaks") : t("chip.opt.none");
        } else if (o.value === "standalone") {
          o.textContent = t("chip.opt.standaloneClin");
        }
      });
    });
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
