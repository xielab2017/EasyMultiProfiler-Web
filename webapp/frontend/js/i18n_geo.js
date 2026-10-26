/**
 * i18n_geo.js — pure locale/geography helpers for EMP Web v9.1.0.
 *
 * No DOM access and no imports, so this module can be unit-tested in Node
 * (webapp/tests/test_v910_i18n_geo.mjs) and reused by locale.js.
 *
 * Resolution contract (see docs/I18N_PLATFORM_v910.md):
 *   manual user choice > IP country > browser language > product default.
 */

export const SUPPORTED_LOCALES = [
  "zh", "zh-TW", "en", "ja", "ko", "ar", "es", "fr", "de", "pt", "ru",
];

export const RTL_LOCALES = ["ar"];

/** ISO 3166-1 alpha-2 country code -> supported locale. */
export const COUNTRY_TO_LOCALE = {
  CN: "zh",
  TW: "zh-TW", HK: "zh-TW", MO: "zh-TW",
  SG: "zh",
  JP: "ja",
  KR: "ko",
  AE: "ar", SA: "ar", EG: "ar", QA: "ar", KW: "ar", OM: "ar", BH: "ar",
  JO: "ar", LB: "ar", IQ: "ar", MA: "ar", DZ: "ar", TN: "ar", LY: "ar",
  SD: "ar", YE: "ar", PS: "ar",
  ES: "es", MX: "es", AR: "es", CO: "es", CL: "es", PE: "es", VE: "es",
  FR: "fr", BE: "fr",
  DE: "de", AT: "de", CH: "de",
  PT: "pt", BR: "pt",
  RU: "ru", BY: "ru", KZ: "ru", UA: "ru",
  US: "en", GB: "en", CA: "en", AU: "en", NZ: "en", IE: "en",
};

/** Map an ISO country code to a supported locale, or null when unmapped. */
export function localeForCountry(cc) {
  if (!cc || typeof cc !== "string") return null;
  return COUNTRY_TO_LOCALE[cc.trim().toUpperCase()] || null;
}

/** Map a BCP-47 browser language tag to a supported locale, or null. */
export function localeForBrowserLang(lang) {
  if (!lang || typeof lang !== "string") return null;
  const tag = lang.trim().toLowerCase().replace(/_/g, "-");
  if (!tag) return null;
  if (tag === "zh-tw" || tag === "zh-hk" || tag === "zh-mo" ||
      tag.startsWith("zh-hant")) {
    return "zh-TW";
  }
  const prefix = tag.split("-")[0];
  if (prefix === "zh") return "zh";
  if (["ja", "ko", "ar", "es", "fr", "de", "pt", "ru", "en"].includes(prefix)) {
    return prefix;
  }
  return null;
}

/** True when the locale uses a right-to-left script layout. */
export function isRtl(locale) {
  return RTL_LOCALES.includes(locale);
}

/** Proper BCP-47 tag for the html lang attribute. */
export function bcp47(locale) {
  if (locale === "zh") return "zh-CN";
  return locale || "zh-CN";
}

/**
 * Human-readable display name for a locale, in that locale itself
 * (for example "日本語", "한국어", "العربية"). Falls back to the code.
 */
export function localeDisplayName(locale) {
  try {
    const names = new Intl.DisplayNames([locale], { type: "language" });
    return names.of(locale) || locale;
  } catch {
    return locale;
  }
}
