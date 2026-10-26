# Manuscript Plan — Nucleic Acids Research (Web Server Issue)

**Working title:** EasyMultiProfiler Web
**Target venue:** *Nucleic Acids Research*, Web Server issue
**Software version covered:** v9.1.0
**Status of this document:** internal preparation plan. Every statement that
still needs evidence is marked `{{TODO: ...}}`. No performance numbers,
access statistics, or bibliographic details are asserted anywhere in this
plan until they have actually been measured or confirmed.

---

## 1. Requirements checklist (NAR Web Server style)

The Web Server issue expects a freely accessible, functional web service
with a concise methods-style manuscript. Status below is honest as of the
v9.1.0 code state.

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 1 | Publicly accessible web server or demo instance | TODO | The app is local-first today. Deploy a public demo instance (bundled demo data only) and record its URL here: {{TODO: demo URL}} |
| 2 | Freely accessible without login for the demo | TODO | The demo instance must open the analysis UI without registration. Teaching/GitHub-sync features may stay behind the student login on local installs, but the demo path must not require it. |
| 3 | HTTPS on the public instance | TODO | Terminate TLS at the demo host / reverse proxy; verify `GET /api/health` over HTTPS. |
| 4 | Works in modern browsers | Partially done | The front end is a dependency-light static app (HTML/CSS/JS modules) tested in Chromium-based browsers during development; complete a browser matrix pass (Chrome, Edge, Firefox, Safari) on the demo instance: {{TODO: browser matrix results}} |
| 5 | No login wall, fees, or restricted access for reviewers | TODO | Provide the demo URL plus, if needed, a reviewer test account in the cover letter — credentials are shared with the editor only, never printed in the manuscript. |
| 6 | Software is available (source code) | Done | Public GitHub repository with Artistic-2.0 license; per-OS release packages are built by `webapp/scripts/package_release.sh`. |
| 7 | Input data are documented, example data provided | Done (local) | Bundled demo datasets with one-click loading in Course mode; mirror the same demo data on the public instance. |
| 8 | Results are downloadable | Done | CSV / PDF / RDS export in the UI; reproducible report (manifest + report file) per run. |
| 9 | Manuscript follows the Web Server format (summary, implementation, validation, availability) | Planned | See Section 2 outline. Word budgets to be confirmed against the current author instructions at submission time: {{TODO: confirm current NAR Web Server author instructions and limits}} |
| 10 | Long-term availability / archiving | TODO | Archive the v9.1.0 release on Zenodo and cite its DOI: {{TODO: Zenodo DOI}} |
| 11 | Claims are evidence-backed | Rule | No benchmark, user-count, or performance claim enters the manuscript without a recorded measurement (script + date + environment) in the lab notebook. |

---

## 2. Manuscript outline (NAR Web Server style)

### Title options (pick one at drafting time)

1. EasyMultiProfiler Web: a local-first, multilingual web platform for downstream multi-omics analysis
2. EasyMultiProfiler Web: no-code downstream multi-omics analysis in the browser with reproducible, teaching-ready workflows
3. EasyMultiProfiler Web: an 11-language web server for multi-omics downstream analysis, quality control and reproducible reporting

### Abstract / Summary skeleton (budget: ~200–250 words, confirm at submission)

- Sentence 1–2: problem — downstream multi-omics analysis is fragmented across command-line tools; non-programmers and teaching settings are underserved.
- Sentence 3–5: what the server does — browser UI over the EasyMultiProfiler R core; tracks for transcriptomics, 16S, metagenomics, metabolomics, ChIP-seq/CUT&RUN, clinical data, and cross-omics joint analysis; import → QC → preprocess → analyze → visualize → export.
- Sentence 6–7: distinguishing features — local-first privacy model with optional GitHub sync; Code Lab exposes every step as editable R; background jobs; rigor QC that reports (never silently alters) data issues; reproducible run reports.
- Sentence 8: v9.1.0 additions — IP-based UI language auto-detection with 11 locales incl. RTL Arabic; one-click installers for Windows/macOS/Linux.
- Final sentence: availability (GitHub + demo URL + license). {{TODO: insert demo URL and Zenodo DOI}}

### Introduction (~600–800 words)

- Downstream analysis as the bottleneck after quantification; heterogeneity of omics types.
- Existing point-and-click options and their limits (single-omics scope, server-side data upload/privacy, English-only UI, weak teaching support) — cite only tools actually reviewed: {{TODO: reference list}}.
- Design goals: no-code but auditable, local-first, multilingual, teaching-ready.

### Implementation (~800–1000 words)

- Architecture: static front end, Plumber REST API, EasyMultiProfiler R core, session-scoped local storage, disk-persistent background jobs (callr).
- Workflow engine: per-omics tracks, Run All, Code Lab (generated R, fusion with external scripts).
- Rigor layer: emp_qc_rigor (missingness, variance, batch–group confounding, PC association), step cache and resume, reproducible manifest/report.
- Internationalization: country→locale mapping, negotiation chain (manual > IP country > browser language > default), RTL layout, plot font strategy.
- Course mode and append-only GitHub homework sync.
- Platform support: installers and platform detection for Windows/macOS/Linux.

### Data and methods (~400–600 words)

- Input formats per track (count/abundance matrices + sample metadata; peak/BAM-derived inputs for ChIP), the EMPT inspector.
- Statistical methods are those of the underlying EasyMultiProfiler package and its declared dependencies (DESCRIPTION) — describe, do not re-claim novelty.
- Demo datasets bundled with the app, used in the validation section.

### Validation / use-case plan (uses the bundled demo data only)

- Use case 1: one transcriptomics demo from import to differential results, enrichment, figure export, and reproducible report.
- Use case 2: one 16S demo through diversity and differential abundance.
- Use case 3 (teaching): one Course week completed end-to-end, synced to a GitHub repository, showing the run-history layout.
- Each use case records: input size, steps, wall-clock time and peak memory on a stated machine — measured by the scripts in `docs/PERFORMANCE_AND_MEMORY.md` context: {{TODO: run and record the use cases}}
- Cross-check one result against the equivalent command-line EasyMultiProfiler calls and report concordance factually: {{TODO: concordance check}}

### Discussion (~300–400 words)

- Scope and limits: downstream analysis only; long-tail UI strings still fall back to English (state this honestly); local-first model trades hosted convenience for privacy, mitigated by the demo instance; R dependency weight.
- Future work: full long-tail translations, hosted multi-user deployment, additional tracks.

### Availability, funding, conflict of interest, supplementary

- **Availability:** GitHub repository URL, demo URL, Zenodo DOI, license (Artistic-2.0). {{TODO: fill in at submission}}
- **Funding:** {{TODO: funding sources and grant numbers — owner to supply; never invent}}
- **Conflict of interest:** {{TODO: standard statement — owner to confirm}}
- **Supplementary:** installation matrix per OS, full endpoint list, QC warning-code table, locale coverage table.

---

## 3. Figure and table plan

| Item | Content | Status |
|------|---------|--------|
| Figure 1 | Workflow / architecture diagram (reuse `docs/TECHNICAL_MODE_V9_EDUCATION.svg`, redraw at journal quality) | Asset exists, redraw TODO |
| Figure 2 | UI screenshots: analysis page in English, Japanese, and Arabic (RTL) showing the same view | TODO (capture on demo instance) |
| Figure 3 | Course → Export → GitHub sync flow with the run-history layout | Asset exists (`docs/images/emp-web-v8-github-sync.png`), refresh TODO |
| Figure 4 | Rigor QC dashboard example from a demo run (missingness, batch association panels) | TODO (generate with emp_plot_qc_dashboard) |
| Table 1 | Platform / installation matrix: OS × installer × start/stop entry × status of the 3-OS install test | Draft in release notes; test results TODO |
| Table 2 | Feature comparison with reviewed related tools (only tools actually reviewed, factual columns only) | TODO |
| Table 3 | Benchmark table: demo datasets × steps × time / peak memory | {{TODO: run benchmarks}} — no numbers until measured |

---

## 4. Pre-submission action checklist (ordered)

1. [ ] Deploy the public demo instance (demo data only), enable HTTPS, confirm the demo needs no login.
2. [ ] Run the R helper tests on a machine with R: `Rscript webapp/tests/test_v910_helpers.R` and `Rscript webapp/tests/test_v910_round2.R`; fix failures before anything else.
3. [ ] Three-OS install test using the actual release packages from `webapp/scripts/package_release.sh` (Windows, macOS Intel/Apple Silicon, Linux): record date, OS build, R version, success/failure per step in Table 1.
4. [ ] Browser matrix pass on the demo instance (Chrome, Edge, Firefox, Safari), including the Arabic RTL layout and the job tray.
5. [ ] Run the three validation use cases on the bundled demo data; record time/memory; run the command-line concordance check.
6. [ ] Fill Table 3 from the recorded benchmark outputs only.
7. [ ] Capture Figure 2 and Figure 4 on the demo instance at publication resolution.
8. [ ] Archive the exact submitted release on Zenodo; insert the DOI into README_EN.md, the manuscript Availability section, and the BibTeX block.
9. [ ] Replace every `{{TODO: ...}}` in README_EN.md and in the manuscript draft; a text search for `{{TODO` must return nothing in the submitted files.
10. [ ] Confirm the current NAR Web Server author instructions (format, word limits, figure rules) and adjust Section 2 budgets.
11. [ ] Owner review of Funding and Conflict-of-interest statements.
12. [ ] Submit with the demo URL (and reviewer access details, if any) in the cover letter.
