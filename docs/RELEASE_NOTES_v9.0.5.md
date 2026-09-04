# Release Notes — v9.0.5

**Branch:** `v9.0.5`
**Base:** `v9.0.4`
**Internal version:** `9.0.5`
**Status:** correctness, security and cross-platform hardening. No new features.

## Summary

Twenty-six files changed. Every claim below was verified by executing the code, not by reading it;
the evidence is in `runtime_verification.md` and `router_test_report.csv`.

### Defects that made a documented workflow fail

- **Differential analysis failed on any host where the OS hides CPU topology.**
  `.diff_detect_cores()` guarded the `NA` from the first `parallel::detectCores()` call but not from
  its own fallback, so `core = NA` reached the package and every method died with
  `missing value where TRUE/FALSE needed`. Both calls are now guarded.
- **Taxonomy Collapse could not succeed.** The endpoint passed `taxa_level =`, which
  `EMP_collapse()` does not declare, and the package then hit an interactive `menu()` inside a
  non-interactive worker. Fixed, with an explicit `tax_annotation` parameter so callers can state
  the choice; `Kingdom` is accepted as an alias for the package's `Kindom`.
- **Correlation analysis silently produced coefficients without p-values.** `EMP_cor_analysis()`
  dispatches on class `EMP`, which the backend never constructed, so every request fell through to a
  `stats::cor()` fallback. `as.EMP()` is now exported and the endpoint returns the kernel's own
  table, p-values included.
- **Unlabelled samples entered the statistical tests** (2 of 132 in the bundled 16S demo).

### Failures that were being reported as plausible results

Selecting t-SNE ran UMAP; selecting LEfSe or ANCOM ran random forest; an unsupported clustering
method ran hierarchical clustering; an ordination that produced no coordinates returned sample
metadata for the frontend to plot as axes; three of the four imputation methods were not implemented
while the response echoed the user's choice. Each now either does what was asked or refuses and names
the alternatives, and the differential endpoint reports `requested_method` and `executed_method`
separately whenever its documented fallback fires.

### Security

- **Caller-supplied R execution was on by default.** Three sites read `EMP_ENABLE_USER_R` with
  `unset = "true"`, so `/api/user_r/run` evaluated arbitrary R in the API process unless the operator
  opted out. The bundled launchers set it to `false`, so official paths were safe; any other start-up
  was not. One shared parser, default **off**, now serves all four sites including the start-up guard.
- **`run_api.R` bound every interface while telling the deployment guard it was on loopback** — the
  guard and the bind read the same variable with different defaults, so the token requirement was
  waived on a server that was in fact reachable. Loopback is now the default and reaching beyond it
  is an explicit opt-in that requires a token.
- Request bodies above the 1 MiB parse cap bypassed session-ownership checks; two ChIP-seq endpoints
  accepted server paths outside `EMP_ALLOWED_ROOTS`; session, project and job identifiers came from
  R's seedable global RNG; provider API keys were passed to `curl` on the command line.

### Cross-platform

- `EVOLUTION_DIR` was hardcoded to `/tmp/emp_evolution` with no override and `TEACHING_DIR`
  defaulted to `/tmp/emp_teaching`. Windows has no `/tmp`, and on a shared POSIX host it is
  world-writable. Both now use the per-user application data root already used by sessions and jobs.
- Ten labels on the ChIP-seq downstream page never switched to English; catalogue entries and
  bindings added.

### Performance

- The clinical cross-omics screen replaced a per-pair `cor.test` loop with a vectorised
  implementation: 9–13× faster, coefficients identical, p-values differing only in the small-sample
  regime where `cor.test` switches to an exact distribution.
- Measured and **not** fixed: `/api/analyze/correlation` has no feature cap and runs synchronously —
  203 s for 83,521 genus-level pairs, blocking the single-process API throughout.

### Packaging

- 28 packages called at runtime by the web layer but installed by neither the installer nor the
  container are now declared; the ChIP-seq annotation stack is behind `EMP_INSTALL_CHIPSEQ`.
- **`LICENSE` added** (Artistic-2.0, verbatim from R's own `share/licenses`). GitHub currently
  reports no licence for this repository.

## Validation

- All 20 changed R sources parse; both changed JavaScript modules parse.
- Three test tiers, all green: 22 isolation assertions; 21 handler-level checks against the bundled
  16S demo with the real engine; **22 checks through the plumber router** — the real filter chain,
  handlers and serializers — covering import, prepare, analyse, the refusal paths, and the security
  and error contracts. `test_emp_web_router.R` reproduces the third tier anywhere R runs.
- Latency through the router: median 50 ms, 90th percentile 0.50 s, slowest 0.55 s.

## Known limitations carried into this release

- Code Lab snippets are sliced from stale handler code and must be regenerated before the feature is
  described as reproducing what each panel ran.
- Only 6 of 173 endpoints use the background job runner; long routes block the single-process API.
- The result cache has no eviction policy.
- `start_local.sh` defaults `API_HOST` to `0.0.0.0` while `start_local_windows.ps1` defaults to
  `127.0.0.1` — deliberate for classroom LAN use, but inconsistent across platforms.
- Windows validation runs in CI on this branch (`.github/workflows/windows-validation.yml`, a real
  `windows-latest` runner): `test_emp_web_platform.R` for the portability contract and
  `test_emp_web_router.R` for all 173 endpoints. Results are attached to the workflow run.

## Housekeeping worth doing on this branch

`webapp/backend/Rplots.pdf` (2.9 MB, an accidental headless-R artifact) and `webapp/test_outputs/`
(~19 MB of committed run outputs, including an 8.5 MB `manifest.json` and two 4.2 MB bundles) are
tracked. Removing them from the working tree and adding them to `.gitignore` will not shrink the
existing history — the repository is 319 MB on GitHub — but it keeps the branch clean for reviewers.

## Reproducing the validation

```bash
Rscript test_emp_web_platform.R --out platform_report.csv   # ~10 s, needs only jsonlite
Rscript test_emp_web_router.R   --out router_report.csv     # full engine, no socket or browser
```

Both run unchanged on Windows, macOS and Linux, and exit non-zero on any failure. macOS results for
this release: 11 of 11 executed portability checks pass (one skipped where the home directory is not
writable), and 22 of 22 functional checks pass.
