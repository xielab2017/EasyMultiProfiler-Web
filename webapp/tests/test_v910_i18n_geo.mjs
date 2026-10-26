/**
 * test_v910_i18n_geo.mjs — Node tests for the v9.1.0 i18n modules.
 * Run: node webapp/tests/test_v910_i18n_geo.mjs
 */
import assert from "node:assert/strict";
import {
  SUPPORTED_LOCALES,
  RTL_LOCALES,
  localeForCountry,
  localeForBrowserLang,
  isRtl,
  bcp47,
  localeDisplayName,
} from "../frontend/js/i18n_geo.js";
import { EXTRA_LOCALES } from "../frontend/js/i18n_extra_locales.js";

// --- Country mapping ---------------------------------------------------
assert.equal(localeForCountry("JP"), "ja");
assert.equal(localeForCountry("SA"), "ar");
assert.equal(localeForCountry("KR"), "ko");
assert.equal(localeForCountry("TW"), "zh-TW");
assert.equal(localeForCountry("CN"), "zh");
assert.equal(localeForCountry("HK"), "zh-TW");
assert.equal(localeForCountry("SG"), "zh");
assert.equal(localeForCountry("BR"), "pt");
assert.equal(localeForCountry("DE"), "de");
assert.equal(localeForCountry("US"), "en");
assert.equal(localeForCountry("XX"), null);
assert.equal(localeForCountry(""), null);
assert.equal(localeForCountry(null), null);
assert.equal(localeForCountry("jp"), "ja", "country codes are case-insensitive");

// --- Browser language mapping ------------------------------------------
assert.equal(localeForBrowserLang("ja-JP"), "ja");
assert.equal(localeForBrowserLang("ko-KR"), "ko");
assert.equal(localeForBrowserLang("zh-TW"), "zh-TW");
assert.equal(localeForBrowserLang("zh-Hant-HK"), "zh-TW");
assert.equal(localeForBrowserLang("zh-CN"), "zh");
assert.equal(localeForBrowserLang("ar-EG"), "ar");
assert.equal(localeForBrowserLang("pt-BR"), "pt");
assert.equal(localeForBrowserLang("en-US"), "en");
assert.equal(localeForBrowserLang("xx-YY"), null);
assert.equal(localeForBrowserLang(""), null);

// --- RTL ---------------------------------------------------------------
assert.equal(isRtl("ar"), true);
for (const loc of SUPPORTED_LOCALES) {
  if (loc !== "ar") assert.equal(isRtl(loc), false, `${loc} must not be RTL`);
}
assert.deepEqual(RTL_LOCALES, ["ar"]);

// --- BCP-47 + display names ---------------------------------------------
assert.equal(bcp47("zh"), "zh-CN");
assert.equal(bcp47("zh-TW"), "zh-TW");
assert.equal(bcp47("ja"), "ja");
assert.equal(typeof localeDisplayName("ja"), "string");
assert.ok(localeDisplayName("ja").length > 0);
assert.ok(localeDisplayName("ar").length > 0);

// --- Extra locales coverage ----------------------------------------------
const NAV_KEYS = [
  "nav.guide", "nav.course", "nav.prompts", "nav.data", "nav.summary",
  "nav.inspector", "nav.prepare", "nav.analyze", "nav.chipseq",
  "nav.chipseq_downstream", "nav.clinical", "nav.runall", "nav.visualize",
  "nav.export",
];
// The full core key list used by i18n_extra_locales.js (95 keys).
const CORE_KEYS = [
  ...NAV_KEYS,
  "wf.guide", "wf.course", "wf.prompts", "wf.import", "wf.summary",
  "wf.inspector", "wf.preparation", "wf.analysis", "wf.clinical",
  "wf.runall", "wf.visualization", "wf.export",
  "page.guide", "page.course", "page.prompts", "page.import", "page.summary",
  "page.inspector", "page.preparation", "page.analysis", "page.chipseq",
  "page.chipseq_downstream", "page.clinical", "page.runall",
  "page.visualization", "page.export",
  "chip.wizard.step1", "chip.wizard.step2", "chip.wizard.advanced",
  "locale.label", "locale.auto", "locale.hint.auto", "locale.hint.browser",
  "locale.hint.manual",
  "fontScale.label", "fontScale.smaller", "fontScale.larger", "fontScale.reset",
  "common.working", "common.loading", "common.clear", "common.refresh",
  "common.apply", "common.cancel", "common.run", "common.downloadCsv",
  "common.downloadRds", "common.downloadPdf", "common.chooseFile",
  "common.prev", "common.next", "common.experiment", "common.sessionActive",
  "common.lastRun", "common.method", "common.feature", "common.yes",
  "common.no", "common.yesFast",
  "omics.label", "omics.all", "omics.transcriptomics", "omics.chipseq",
  "omics.microbiome_16s", "omics.metagenomics", "omics.metabolomics",
  "omics.clinical", "omics.multiomics", "omics.customize", "omics.label.m16s",
  "omics.label.transcriptomics", "omics.label.metagenomics",
  "omics.label.metabolomics", "omics.label.chipseq", "omics.label.clinical",
  "omics.label.multiomics", "omics.label.customize",
  "footer.guide", "footer.course", "footer.docs",
  "copilot.btn",
];

const EXPECTED_EXTRA = ["zh-TW", "ja", "ko", "ar", "es", "fr", "de", "pt", "ru"];
assert.deepEqual(Object.keys(EXTRA_LOCALES).sort(), [...EXPECTED_EXTRA].sort());

for (const [loc, dict] of Object.entries(EXTRA_LOCALES)) {
  for (const key of NAV_KEYS) {
    assert.ok(dict[key] && dict[key].trim().length > 0,
      `${loc} is missing nav key ${key}`);
  }
}
// ja / ko / ar must cover the FULL core key list.
for (const loc of ["ja", "ko", "ar"]) {
  for (const key of CORE_KEYS) {
    assert.ok(EXTRA_LOCALES[loc][key] && EXTRA_LOCALES[loc][key].trim().length > 0,
      `${loc} is missing core key ${key}`);
  }
}
// Every extra locale covers the full core list too (by construction).
for (const [loc, dict] of Object.entries(EXTRA_LOCALES)) {
  for (const key of CORE_KEYS) {
    assert.ok(dict[key] && dict[key].trim().length > 0,
      `${loc} is missing core key ${key}`);
  }
}
// Supported locales = zh + en (built in) + extra locales.
for (const loc of SUPPORTED_LOCALES) {
  assert.ok(loc === "zh" || loc === "en" || EXTRA_LOCALES[loc],
    `supported locale ${loc} has no dictionary`);
}

console.log("test_v910_i18n_geo.mjs: all assertions passed");
console.log(`  locales: ${SUPPORTED_LOCALES.join(", ")}`);
console.log(`  core keys per extra locale: ${CORE_KEYS.length}`);
