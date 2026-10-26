# i18n_locale.R - EMP Web v9.1.0 backend locale helpers (base R only).
#
# Mirrors webapp/frontend/js/i18n_geo.js: the same country -> locale map,
# the same negotiation priority (explicit country header > Accept-Language
# > product default "zh"), and the same fallback for user-facing messages
# (locale -> en -> zh -> key). See docs/I18N_PLATFORM_v910.md.

.EMP_SUPPORTED_LOCALES <- c("zh", "zh-TW", "en", "ja", "ko", "ar",
                            "es", "fr", "de", "pt", "ru")

.EMP_COUNTRY_LOCALE <- c(
  CN = "zh",
  TW = "zh-TW", HK = "zh-TW", MO = "zh-TW",
  SG = "zh",
  JP = "ja",
  KR = "ko",
  AE = "ar", SA = "ar", EG = "ar", QA = "ar", KW = "ar", OM = "ar",
  BH = "ar", JO = "ar", LB = "ar", IQ = "ar", MA = "ar", DZ = "ar",
  TN = "ar", LY = "ar", SD = "ar", YE = "ar", PS = "ar",
  ES = "es", MX = "es", AR = "es", CO = "es", CL = "es", PE = "es",
  VE = "es",
  FR = "fr", BE = "fr",
  DE = "de", AT = "de", CH = "de",
  PT = "pt", BR = "pt",
  RU = "ru", BY = "ru", KZ = "ru", UA = "ru",
  US = "en", GB = "en", CA = "en", AU = "en", NZ = "en", IE = "en"
)

#' Map an ISO 3166-1 alpha-2 country code to a supported locale (or NA).
emp_country_to_locale <- function(cc) {
  if (is.null(cc) || length(cc) == 0) return(NA_character_)
  cc <- toupper(trimws(as.character(cc[[1]])))
  if (!nzchar(cc)) return(NA_character_)
  loc <- unname(.EMP_COUNTRY_LOCALE[cc])
  if (length(loc) == 0 || is.na(loc)) NA_character_ else loc
}

#' Map a BCP-47 language tag to a supported locale (or NA).
emp_language_to_locale <- function(lang) {
  if (is.null(lang) || length(lang) == 0) return(NA_character_)
  tag <- tolower(trimws(as.character(lang[[1]])))
  tag <- gsub("_", "-", tag)
  if (!nzchar(tag)) return(NA_character_)
  if (tag %in% c("zh-tw", "zh-hk", "zh-mo") || startsWith(tag, "zh-hant")) {
    return("zh-TW")
  }
  prefix <- strsplit(tag, "-", fixed = TRUE)[[1]][[1]]
  if (prefix %in% .EMP_SUPPORTED_LOCALES) prefix else NA_character_
}

#' Negotiate the UI locale for a request.
#' Priority: geo country header > Accept-Language (first entries, in
#' order) > product default "zh".
emp_negotiate_locale <- function(country_header = NULL,
                                 accept_language = NULL) {
  by_country <- emp_country_to_locale(country_header)
  if (!is.na(by_country)) return(by_country)
  if (!is.null(accept_language) && length(accept_language) > 0) {
    raw <- as.character(accept_language[[1]])
    if (nzchar(raw)) {
      tags <- strsplit(raw, ",", fixed = TRUE)[[1]]
      for (tag in tags) {
        tag <- sub(";.*$", "", trimws(tag))
        loc <- emp_language_to_locale(tag)
        if (!is.na(loc)) return(loc)
      }
    }
  }
  "zh"
}

#' Text direction for a locale: "rtl" for Arabic, "ltr" otherwise.
emp_locale_dir <- function(locale) {
  if (!is.null(locale) && length(locale) > 0 &&
      identical(as.character(locale[[1]]), "ar")) "rtl" else "ltr"
}

#' Font family to prefer for plot text in a locale. CJK and Arabic glyphs
#' need explicit families on most graphics devices, otherwise plot labels
#' render as boxes. Falls back to the generic "sans".
emp_plot_font_family <- function(locale) {
  if (is.null(locale) || length(locale) == 0) return("sans")
  switch(as.character(locale[[1]]),
    "ja" = "Noto Sans CJK JP",
    "ko" = "Noto Sans CJK KR",
    "zh" = "Noto Sans CJK SC",
    "zh-TW" = "Noto Sans CJK TC",
    "ar" = "Noto Sans Arabic",
    "sans"
  )
}

# Backend message catalog. Only the keys needed by API/report code live
# here; full UI strings live in the frontend catalog. Locales beyond
# zh/en/ja/ko/ar fall back to English (see emp_msg).
.EMP_MSG <- list(
  "qc.missing_warning" = list(
    zh = "数据缺失比例偏高，请在分析报告中如实报告缺失情况，不要静默插补。",
    en = "Missingness is high. Report it honestly in the analysis report; do not silently impute.",
    ja = "欠測の割合が高めです。黙って補完せず、解析レポートで正直に報告してください。",
    ko = "결측 비율이 높습니다. 조용히 대치하지 말고 분석 보고서에 솔직히 보고하세요.",
    ar = "نسبة البيانات المفقودة مرتفعة. أبلغ عنها بصراحة في تقرير التحليل ولا تستبدلها بصمت."
  ),
  "qc.batch_warning" = list(
    zh = "检测到批次与分组可能混杂，差异结果可能受批次效应影响，请结合批次校正与敏感性分析解读。",
    en = "Batch and group may be confounded. Interpret differential results together with batch correction and sensitivity analyses.",
    ja = "バッチと群が交絡している可能性があります。バッチ補正と感度解析とあわせて結果を解釈してください。",
    ko = "배치와 그룹이 혼재되어 있을 수 있습니다. 배치 보정 및 민감도 분석과 함께 결과를 해석하세요.",
    ar = "قد يكون الدفعة والمجموعة مختلطين. فسر النتائج التفاضلية مع تصحيح الدفعة وتحليلات الحساسية."
  ),
  "qc.multitest_note" = list(
    zh = "涉及多重检验时必须报告校正方法（如 BH/FDR），论断强度不得超过证据强度。",
    en = "When multiple tests are performed, report the correction method (for example BH/FDR); claims must not exceed the evidence.",
    ja = "多重検定を行う場合は補正方法（BH/FDRなど）を報告し、主張は証拠の強さを超えないようにしてください。",
    ko = "다중 검정을 수행할 때는 보정 방법(예: BH/FDR)을 보고하고, 주장은 증거의 강도를 초과하지 않아야 합니다.",
    ar = "عند إجراء اختبارات متعددة، أبلغ عن طريقة التصحيح (مثل BH/FDR) ويجب ألا تتجاوز الادعاءات قوة الأدلة."
  ),
  "report.title" = list(
    zh = "可复现分析报告",
    en = "Reproducible Analysis Report",
    ja = "再現可能な解析レポート",
    ko = "재현 가능한 분석 보고서",
    ar = "تقرير تحليل قابل لإعادة الإنتاج"
  ),
  "report.generated_with" = list(
    zh = "由 EasyMultiProfiler Web 生成",
    en = "Generated with EasyMultiProfiler Web",
    ja = "EasyMultiProfiler Web で生成",
    ko = "EasyMultiProfiler Web으로 생성됨",
    ar = "تم إنشاؤه باستخدام EasyMultiProfiler Web"
  )
)

#' Look up a backend message: locale -> en -> zh -> key itself.
emp_msg <- function(locale, key) {
  entry <- .EMP_MSG[[key]]
  if (is.null(entry)) return(key)
  loc <- if (is.null(locale) || length(locale) == 0) "en" else as.character(locale[[1]])
  value <- entry[[loc]]
  if (is.null(value)) value <- entry[["en"]]
  if (is.null(value)) value <- entry[["zh"]]
  if (is.null(value)) return(key)
  value
}
