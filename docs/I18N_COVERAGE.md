# I18N coverage (v9.0.4)

Locale modes: **自动 / Auto**, **中文**, **EN**.

## How it works

- `locale.js` stores mode (`auto|zh|en`) in `localStorage`.
- **Auto**: `navigator.language` seed, then IP country via `https://ipapi.co/json/` with HTTPS fallback `https://ipwho.is/`. CN / HK / MO / TW / SG → `zh`, else `en` when IP is known; otherwise browser language.
- On change: `applyDataI18nAttributes` → `applyDomI18n` (static + upload cards + chipds filters + ChIP deps chrome) → course banner → `emp:locale-change`.
- Listeners re-render dynamic panels: GitHub sync (`applyGithubSyncI18n`), ChIP recipe packs (`loadChipRecipePacks`), chipds catalog badges/filters, teaching case detail, Code Lab, Guide.

## Covered in this pass

| Surface | Mechanism |
|--------|-----------|
| Export / GitHub card | Labels, placeholders, track/assignment options, path preview, buttons via `t()` + locale-change |
| Import multi-omics upload cards | Titles, import modes (matrix vs DE), data/meta labels, Choose File, upload buttons |
| ChIP Step 1/2 chrome | Deps labels, empty peak / none options, recipe section titles, Run / combo, goto Step2 |
| ChIPseq Downstream filters | 全部/必做/推荐/高级/可选, BAM, status, search placeholder, summary badges |
| Course / Teaching | Quiz feedback, case chrome (科学问题/加载示例…), reload detail on locale-change |

Catalog: **~137 new keys** (zh+en pairs; catalog total **720** keys each side).

## Intentional English (left as-is)

- Tool / method names: DESeq2, edgeR, limma, ChIPseeker, HOMER, DiffBind, deepTools, MACS
- MACS / assay **preset option IDs and labels** (e.g. `cutrun_tf_p05`, “TF Cut&Run (p=0.05)”)
- Genome assembly codes (`mm`, `hs`, mm10/hg38)
- Recipe pack `requires` tokens (`peaks`, `rna_or_proteomics`, …) and technical log lines
- Catalog **stage names** from Excel (may be mixed CN/EN content)
- Course **case titles / quiz question bodies** from teaching JSON (content, not chrome)
- GitHub path segments (`Week_01`, `EMP2026`, repo URLs)
- Code Lab R snippets / template comments

## Gaps / follow-ups (not blocking)

- Some analysis/viz toast strings and long clinical option rows still mixed
- Chipds catalog item titles follow source spreadsheet language
- Welcome / demo cards already keyed; verify after hard refresh (`?v=i18n-locale-v1`)

## v9.0.5 addition

An audit of every CJK-bearing static element in `index.html` against all binding mechanisms
(`data-i18n`, `DOM_I18N`, and the programmatic binding functions in `ui_dom_i18n.js`,
`github_sync.js` and `app.js`) found **10 labels reached by none of them**, all on the ChIP-seq
downstream page: the four `<details>` panel headings (HOMER, DiffBind, Peak set operations,
deepTools), their four Run buttons, and three peak-management buttons. Catalogue keys and
`DOM_I18N` bindings were added for all ten.

Everything else in this document was verified correct: the catalogues are balanced (739 zh / 739 en
after the addition), no English value contains CJK characters, no `t()` call references a missing
key, no `DOM_I18N` selector is dead, and `<html lang>` is updated on switch. In particular the
Export / GitHub card is fully translated by `applyGithubSyncI18n()`, as described above.
