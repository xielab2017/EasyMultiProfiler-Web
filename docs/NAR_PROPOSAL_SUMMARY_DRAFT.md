# Proposal Summary — NAR Web Server Issue (DRAFT)

**Status:** internal draft for the one-page proposal summary, prepared
2026-10-26. Submission route decided by the owner on 2026-10-26:
**Web Server route** (public demo first). Statements are limited to implemented, tested functionality.
Items the owner must supply are marked `{{TODO: ...}}`; nothing is
submitted anywhere until the owner approves the route and the text.

**Proposed title:** EasyMultiProfiler Web: a local-first, multilingual
web platform for downstream multi-omics analysis

**Authors:** {{TODO: author list and affiliations — owner to supply}}

**Corresponding author:** {{TODO: name / email — owner to supply}}

---

## Summary

EasyMultiProfiler Web is a browser-based platform for downstream
multi-omics analysis, built on the EasyMultiProfiler R package. A
Plumber REST API and a dependency-light static front end bring the
complete analysis workflow — data import and inspection, quality
control, preprocessing, differential and diversity analysis,
enrichment, visualization, and export — into a point-and-click
interface. Dedicated tracks cover transcriptomics (RNA-seq),
microbiome (16S), metagenomics, metabolomics, ChIP-seq / CUT&RUN
(including downstream peak analysis), and clinical / phenotype data,
and cross-omics joint analyses link the tracks (for example ChIP–RNA
peak–gene association and cross-omics correlation networks with FDR
control). Every workflow step is also exposed in a Code Lab as plain,
editable R code, so no-code users and programmers share one auditable
pipeline, and each run produces a reproducible report (manifest plus
report file) capturing versions, platform, parameters, and session
information.

Three properties distinguish the resource. First, it is **local-first**:
it installs with one click on Windows, macOS, or Linux and runs on the
user's own machine, so data never leave that machine unless the user
explicitly synchronizes results to a GitHub repository — a privacy
model that also makes it directly usable in teaching, where students
sign in by student ID and sync weekly coursework to their own
repositories in an append-only run history. Second, it is
**rigor-reporting**: an automated quality-control report flags
missingness, zero- and near-zero-variance features, batch–group
confounding, and principal-component association with batch or group,
and reports them without ever silently dropping or imputing data;
long analyses run as disk-persistent background jobs with progress,
cancellation, step-level caching, and resume. Third, it is
**multilingual**: version 9.1.0 auto-detects the interface language
from the visitor's IP country (with browser-language fallback and
manual override) across 11 locales — Simplified and Traditional
Chinese, English, Japanese, Korean, Arabic (with full right-to-left
layout), Spanish, French, German, Portuguese, and Russian — including
locale-aware fonts for exported figures.

**Validation.** The platform ships with bundled demo datasets and
one-click loading per track; the manuscript will walk through
transcriptomics and 16S use cases end-to-end on those datasets and
cross-check one result against the equivalent command-line
EasyMultiProfiler calls. The v9.1.0 code base passes its automated
test suites (R helper tests for the quality-control, multi-omics,
caching, and localization modules; front-end localization tests) on
R 4.3.3. {{TODO: insert measured use-case timings after the benchmark
runs — no numbers are claimed before they are recorded}}

**Availability.** Source code (Artistic License 2.0), per-OS release
packages, and documentation: https://github.com/xielab2017/EasyMultiProfiler-Web
A public demo instance with the bundled demo data is available
without login at {{TODO: demo URL — deployment in progress, see
docs/DEMO_DEPLOYMENT_PLAN.md}} (HTTPS) and will be maintained for at
least five years. The exact submitted release is archived at
{{TODO: Zenodo DOI}}. For local installation, per-OS one-click
installers are provided on the same repository.

**Funding:** {{TODO: funding sources and grant numbers — owner to
supply; never invent}}

**Conflict of interest:** {{TODO: standard statement — owner to
confirm}}
