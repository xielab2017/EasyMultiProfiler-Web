# Verified local R analysis bridge

`webapp/scripts/r_analysis_bridge.py` is a standard-library-only bridge to the
**existing API at `http://127.0.0.1:8000` on the same computer**. It never launches
R, evaluates code, installs packages, changes credentials, restarts a service or
calls the transcriptomics wrapper that can fall back to limma.

## Status and supported analysis

The Python implementation and mocked HTTP tests are implemented. These tests do
**not** prove that DESeq2 ran on a Mac. A live execution is disabled by default,
and requires both a trusted local runtime profile/probe and explicit confirmation
of an exact prepared plan. Existing service health, an installed package version
of 9.0.3, or current source files alone do not satisfy that requirement.

Initially supported:

- One server-managed bulk RNA-seq matrix declared as **raw, unnormalized counts**.
- Finite, nonnegative **exact integers** no greater than 2,147,483,647. No tolerance,
  rounding, numeric-string conversion, missing-value filling or negative clipping.
- Exactly two groups, at least two explicitly independent biological replicates
  per group, at most 256 samples, 50,000 features and 1,000,000 cells.
- Exact sample-ID matching, no automatic exclusion of unmatched samples.
- An unadjusted `~group` DESeq2 model and explicit test/reference direction.
- One worker/core request and the R backend's existing DESeq2 defaults.

TPM, FPKM, normalized abundances, other omics, batch adjustments, repeated-subject
or paired models, covariates, multi-group models, user formulas and custom R are
blocked. Any batch field blocks this implementation, even if constant. Repeated
subject IDs block it; unique subject IDs still require the independent-samples
assertion. At least one feature must be positive in every sample for the supported
default size-factor estimator. Validation is necessary, not a guarantee of model
fit or scientific suitability.

### Scientific provenance and native output semantics

The internal matrix registry requires a nonempty provenance source and the
original input's SHA-256. `prepare.raw_counts_evidence` must contain the user's
reviewed statement or actual dataset documentation establishing that the file is
raw counts. Do not manufacture this statement from a filename, integer values or
a model's guess. For synthetic tests, explicitly identify synthetic data.

This evidence and the independent-replicate assertion are included in the exact
confirmation digest. They are **recorded evidence, not independently proven
biological provenance**; `raw_count_provenance_verified` remains false.

The existing R code has material behavior that the plan discloses:

1. Import removes all-zero features. The bridge predicts this count and checks
   the actual imported dimensions.
2. `filter_low=true` makes `run_diff` retain features positive in at least
   `max(3, ceiling(0.1 * n_samples))` samples, but only when at least 50 pass.
3. The separate **native result cache always applies that positive-sample filter**,
   even if `filter_low=false` or fewer than 50 features pass. Its eligible-feature
   count is included in `native_result_filter`.
4. The native cache removes rows with missing `pvalue`. `padj` can still be null
   because of DESeq2 independent filtering. The bridge does not invent p-values.
5. The compact result has legacy contrast-label conventions. The bridge returns
   only the native cache with verified method/group/reference/test metadata and
   full standard DESeq2 statistics. Positive `log2FoldChange` means **test over
   reference**. Missing native statistics or a renamed compact fallback are not
   accepted as success.
6. The native cache is a second DESeq2 fit after the compact fit. The existing R
   implementation can therefore do more work than a single DESeq2 call. If cache
   generation fails, the job can be done while the bridge reports
   `result_unverified`, not an invented successful differential result.

## Exact existing R HTTP contract

All requests use the server's existing bearer token, if one is needed. The token
is passed only to `LocalRClient(token=...)`, never to a browser, public request,
plan, returned record, log or URL. The client has no proxy or redirect support and
cannot change host/port. Credential setup or rotation is outside this module.

| Endpoint | Bridge use |
| --- | --- |
| `GET /api/health` | Require `status=ok`, exact attested `version`. |
| `GET /api/capabilities` | Require API `1.0`, exact attested `package_version`, `path_import`, `async_jobs`, `job_cancel`, `transcriptomics` workflow and `emp.analyze.differential` tool. |
| `POST /api/import/path/preview` | Body: server-generated `data_path`, `metadata_path`, `data_type=normal`. Require exact full SHA-256/path, features-in-rows orientation, metadata ID column and complete sample overlap with no warnings. Does not create a session. |
| `POST /api/import/path` | Same paths, `data_type=normal`, `assay_name=counts`, generated `experiment_name`. Do not send an existing session ID. Verify new session ID, experiment, assay and predicted dimensions. |
| `POST /api/analyze/differential/async` | Body: new session, generated experiment, `method=DESeq2`, `group_var=emp_group`, `ref_group=reference`, `test_group=test`, `comparison_mode=pairwise`, `subset_two_groups=true`, `filter_low`, `cores=1`. This endpoint submits `run_diff` directly. |
| `GET /api/jobs/{job_id}` | Require matching job ID, session and `kind=differential`. Handle queued/running/done/error/cancel_requested/cancelled. Never return arbitrary R log/error text. |
| `GET /api/analyze/diff_raw/{session_id}/{experiment}` | After done, verify DESeq2 method/contrast, actual standard result columns, feature aliases and numeric bounds. Return the original feature IDs. |
| `POST /api/jobs/{job_id}/cancel` | Only an execution created by this instance. Distinguish cancel_requested, cancelled and already_finished. A timeout is not a successful cancellation. |

`GET /api/jobs/{job_id}/result` is allowed by the restricted transport but is not
used for the final table because it returns the compact result. General job-list,
workflow wrappers, arbitrary R, downloads and user-selected endpoints are not
exposed by this bridge.

### Server-owned files and identifiers

The hosting application passes already-ingested matrix and metadata records to
internal registration methods. These methods must **not** be HTTP endpoints
accepting local paths. They snapshot data and independently validate it.

After runtime verification succeeds, preparation writes canonical CSVs inside a
dedicated, server-owned managed root. A runtime-blocked plan writes no CSVs or
plan directory and returns `inputs_staged=false` with `input_sha256={}`.
The root must be within the R service's existing `EMP_ALLOWED_ROOTS`. Canonical
feature/sample/group aliases avoid R's numeric-index guessing, name sanitizing,
metadata heuristics and factor-label problems. Original labels are preserved in
the plan/mapping and restored in the returned table. Input values are unchanged.

Each successfully staged plan has private files and SHA-256 values; these are
checked before preview and immediately before import. Symlinks and changed bytes fail closed. The files
must remain protected from concurrent external writers: the existing R API
cannot provide a cross-process atomic file lock between HTTP calls. No staged
input or credential is uploaded to another computer.

## Host integration API

Use one bridge instance per authenticated server/owner. The host must continue to
enforce authentication, ownership, origin/CSRF protections, request-size limits,
resource limits and explicit human confirmation. Never let an agent/model set
`confirmed=true` merely because it proposed a plan.

```python
from r_analysis_bridge import RAnalysisBridge, LocalRClient, BridgeError

bridge = RAnalysisBridge(
    trusted_managed_root,                    # Internal configuration, not a request.
    client=LocalRClient(existing_server_token),
    runtime_profile=trusted_profile,         # None keeps execution blocked.
    runtime_probe=trusted_local_probe,        # None keeps execution blocked.
)

# Internal calls after the host resolves/authorizes its own record IDs:
bridge.register_matrix(data_id, {
    "id": "rna", "omics": "bulk_rnaseq", "data_type": "raw_counts",
    "sample_ids": sample_ids, "feature_ids": feature_ids, "values": values,
    "provenance": {"source": documented_source, "sha256": original_file_sha256},
})
bridge.register_metadata(metadata_id, samples)  # [{"id": ..., "group": ...}, ...]

# Public JSON commands can map directly to these strict methods:
plan = bridge.prepare({
    "data_id": data_id, "metadata_id": metadata_id,
    "ref_group": "control", "test_group": "treated",
    "design": {"group": "group", "independent_samples": True},
    "filter_low": True,
    "raw_counts_evidence": user_reviewed_count_source_evidence,
})
# Show the entire material plan, evidence, direction, sample counts, native
# filtering rules, runtime and blockers. Only enable Confirm if executable.
execution = bridge.execute({
    "plan_id": plan["plan_id"], "plan_sha256": plan["plan_sha256"],
    "confirmed": True,  # Only following explicit user confirmation of THIS plan.
})
state = bridge.poll({"execution_id": execution["execution_id"]})
state = bridge.cancel({"execution_id": execution["execution_id"]})
```

Final prepare fields also include `confirmation_required`, `execution_performed`,
`executable`, `blockers`, `warnings`, `provenance`, `raw_counts_evidence`, runtime
fingerprints, exact sample order, predicted imported dimensions and SHA-256.
Preparation never imports or submits analysis. A blocked plan must be prepared
again after its blocker is resolved. A changed plan needs a new confirmation.

Execution records contain an opaque `execution_id`, plan ID/digest, status,
`session_created`, `execution_performed`, `retry_allowed=false` and
`needs_reconciliation`. On a submit timeout, `execution_performed=null` means
**unknown**, not false. Repeating the same confirmed plan returns the existing
record and never submits again. Concurrent duplicate submissions are guarded.

The in-memory registry is intentionally not a durable job scheduler. A host
restart loses access to these IDs, while an R worker may continue. Do not create
a replacement job automatically. The local owner must reconcile existing R jobs
before rerunning. Do not expose an unscoped bridge instance to multiple users.
The bridge enforces these process-local registry limits:

- 8 immutable matrix records, at most 2,000,000 cells and 100,000 feature IDs
  across those records.
- 32 immutable sample-metadata records. Hosts that allocate new metadata on
  every prepare must handle `registry_limit` rather than silently evict records.
- 16 plans, including blocked plans, and therefore at most 16 execution records.
  An overflow raises `plan_limit` before runtime/network or file work.
- Only one preparation at a time. A concurrent call returns `prepare_busy`;
  it cannot race past plan capacity or allocate another large CSV buffer.

Staging is limited to 16 MiB per plan and 128 MiB across the dedicated root,
including retained files from earlier server instances. Directory scans are
bounded to 1,024 entries and never follow symlinks. Every staging operation must
leave at least **512 MiB free disk space**; the reserve is checked again before
import. These are local safety bounds, not an estimate of all R fitting/session
storage requirements. The host must still limit concurrent R work and monitor
actual resources.

A capacity/disk failure returns a specific blocked-plan error (`staging_limit`,
`disk_reserve` or `staging_unavailable`). A runtime-blocked plan does not even
serialize CSVs. Staging I/O failures report `staging_failed`; partial bridge
files may remain and count toward the next check. No input, plan, metadata,
execution or user file is automatically evicted/deleted to make room. Owner-led
archival or starting a fresh instance must first reconcile active/uncertain R
jobs. Starting a fresh instance does not bypass the retained-file disk quota.
Use one dedicated root per instance; external writers or multiple independent
instances sharing the same root are outside the cross-process locking contract.

## Trusted runtime verification: existing Mac owner procedure

**Do not infer loaded code from a hash of files currently on disk.** Plumber
loads functions into memory. An old running API may still execute pre-overlay
functions, while asynchronous callr workers source current helpers from disk.
An HTTP health check reports neither those loaded functions nor DESeq2's actual
loaded library. This is why simply enabling the bridge against the existing old
process is unsafe.

The smallest bounded verification path, when a restart is separately authorized:

1. Record the API listener identity without printing arguments or environment:
   `lsof -nP -iTCP:8000 -sTCP:LISTEN -Fp` and then
   `ps -p <verified-pid> -o pid= -o lstart= -o comm=`. Require exactly one listener.
   Check existing job state with the current authenticated API/UI. **If any job
   is active or uncertain, do not stop it to obtain an attestation.**
2. Review the exact backend source and installed EasyMultiProfiler DESeq2 path.
   Confirm that the asynchronous endpoint calls `run_diff`, DESeq2 belongs to
   `no_fallback`, and `tx_run_differential` is never used. Confirm the native-cache
   contract described above. Hash the source before starting the new process.
3. Verify required packages using the **same Rscript executable, startup options,
   library paths and existing launch environment as API8000**. In a read-only
   probe, check `requireNamespace` and capture `packageVersion` and `find.package`
   for at least EasyMultiProfiler, DESeq2, tidybulk and callr; also capture
   SummarizedExperiment, MultiAssayExperiment, S4Vectors, jsonlite and digest.
   The launcher's `.local_run/R_libs` prepend must be reproduced when used.
   An unrelated `Rscript --vanilla` probe with different `.libPaths()` is not
   evidence about the running service. Record paths/versions in a local private
   administrative record, not in browser requests. Never print `Sys.getenv()`,
   tokens, process arguments or authentication headers.
4. If the old loaded source cannot be independently established, have the local
   owner perform a controlled **API8000-only** stop/start from the reviewed
   backend with existing auth and environment unchanged. This briefly interrupts
   R service availability and can kill active work; that is why job checks and
   restart authorization are required. Do not unnecessarily restart frontend8080
   or metadata8081. The bridge does not perform this action.
5. After readiness, capture the new listener PID/start-time/executable and compare
   post-start source/package fingerprints to the pre-start record. Establish
   that the process was actually launched from those reviewed files and library
   settings. Merely having a later process start time is not proof by itself.
   Require authenticated capabilities to match `package_version`, API 1.0 and
   required features. If any step is unverified, keep execution blocked.
6. Only now create a trusted profile, valid for at most one hour, and a local
   callable probe. The profile is a server configuration object, never supplied
   by the browser. It contains no token or key.

Required profile shape:

```python
trusted_profile = {
    "api_version": "1.0",
    "package_version": verified_versions["EasyMultiProfiler"],
    "package_versions": verified_versions,
    "source_contract": "emp-direct-deseq2-v1",
    "source_sha256": verified_source_digest,
    "runtime_id": verified_process_digest,
    "running_code_verified": True,  # Only after the procedure above, never guessed.
    "verified_at": now_epoch_seconds,
    "expires_at": now_epoch_seconds + 3600,
}
```

The zero-argument local probe must re-observe and return **exactly**:

```python
{
    "runtime_id": current_process_digest,
    "source_sha256": current_source_digest,
    "package_versions": current_package_versions,
}
```

Fingerprint recipe for the server integration:

- `runtime_id`: SHA-256 of canonical JSON containing the single current API8000
  listener PID, OS process start time and executable identity. Re-query the OS
  using fixed commands/OS APIs, not caller-selected processes or shell strings.
  Preserve PID start time to detect PID reuse.
- `source_sha256`: SHA-256 of a canonical, sorted map from stable labels to file
  SHA-256 values. Include `run_api.R`, `plumber.R`, all sourced `helpers/*.R`, and
  the actual installed package DESCRIPTION/NAMESPACE/R loader and lazy-load
  database files for the verified packages. Include native libraries where the
  runtime depends on them. Use the installation directories observed in the
  matching R probe, not guessed checkout package sources. Recheck current bytes
  so changing disk helpers or installed code invalidates the attestation too.
- `package_versions`: Re-read the selected installation DESCRIPTION versions and
  verify the installation paths have not changed. The map must exactly equal
  the one stored in the profile. The service and callr child library resolution
  must be part of the observed launch provenance.

A probe returning a saved constant object is **not a live verification probe**.
The existing HTTP API cannot implement this trust check by itself. If the host
cannot inspect listener/process/source evidence, leave profile/probe unset and
show the specific `runtime_unverified` blocker. No new authentication mechanism,
secret, persistent credential, source patch or R execution endpoint is required.

Before a new execution, the profile must still be fresh and the probe, versions,
capabilities, staged input bytes and preview must all match the prepared plan.
Existing jobs can be polled/cancelled after the one-hour new-execution window,
but only when the same process/source/packages are still verified. A restarted
API or changed code blocks those operations until the owner reconciles the job;
never send a stale job's cancellation to a different/unverified process.

## Precise local live acceptance recipe (not run in cloud)

After the runtime procedure and host wiring are complete:

1. Run the Python mock tests on the Mac with the hosting Python interpreter:
   `python3 -m unittest discover -s webapp/tests -p test_r_analysis_bridge.py -v`.
2. Use a dedicated managed directory already inside the R service's allowed
   roots. Do not broaden allowed roots or replace existing credentials for the
   smoke test. Instantiate the bridge using the real `LocalRClient` and the
   trusted current profile/probe. Do not use `FakeAPI` or the test profile.
3. Create a **synthetic, non-human fixture**: 200 features and six samples
   (`control1..3`, `treated1..3`), three independent synthetic replicates per
   group. Generate bounded positive integer counts with deterministic NumPy
   negative-binomial sampling (seed 20261106), varying feature means and sample
   depth; multiply means for the first 25 treated features by four. Add one
   all-zero feature. Suggested recipe:

   ```python
   import hashlib, json, numpy as np
   rng = np.random.default_rng(20261106)
   means = rng.uniform(40, 800, size=(200, 1)) * np.array([0.9, 1.0, 1.1, 1.0, 1.1, 0.9])
   means[:25, 3:] *= 4
   values = np.maximum(1, rng.negative_binomial(12, 12 / (12 + means))).tolist()
   values.append([0] * 6)
   fixture_bytes = json.dumps(values, separators=(",", ":")).encode()
   source_sha256 = hashlib.sha256(fixture_bytes).hexdigest()
   ```

   This is a smoke-test fixture, not genuine biological data, inferred sample
   metadata or a scientific benchmark. Store its original fixture bytes locally
   for provenance. Use documented source `Synthetic negative-binomial fixture,
   seed 20261106` and evidence `Synthetic unnormalized integer counts generated
   specifically for this local acceptance test; not human biological samples`.
4. Internally register the fixture and actual synthetic sample metadata under
   fresh server-owned IDs. Prepare the plan with reference `control`, test
   `treated`, `independent_samples=true`, and the exact synthetic evidence.
5. Inspect the plan: `execution_performed=false`, executable only after verified
   preflight, 201 input features, 200 after all-zero removal, six matched samples,
   two groups of three, native-filter eligibility 200, exact expected runtime,
   checksums and test/reference direction. At this point no session or R job
   should have been created.
6. Show the plan to the owner and obtain explicit exact-plan confirmation for
   **this synthetic DESeq2 run**. Then call `execute` with that plan ID/digest.
   Record only safe execution status, not token-bearing HTTP objects.
7. Poll every 2–5 seconds, not in a busy loop. Expect queued/running then
   `completed`, a nonempty native DESeq2 table with standard statistics,
   original feature IDs, confirmed test/reference direction and runtime/input
   provenance. Inspect the intended positive effect in the first 25 features
   as a sanity check, not an exact guarantee that each gene must be significant.
   Compare a selected result to the existing R native result/export. A
   completed R job with an unavailable/malformed native cache is a failed
   acceptance (`result_unverified`), not a passing DESeq2 bridge test.
8. Repeat the same confirmed execute call: it must return the same execution,
   not a second session/job. Prepare a different plan but do not confirm it:
   no job must be created. Fractional input, negative input, normalized input,
   a mismatched sample ID, repeated subject or batch design must be rejected
   before import. Change the staged test file and ensure its original plan
   fails before import (use a dedicated test plan, never a live user's input).
9. For a separate, explicitly confirmed synthetic job, test cancellation while
   it is still running. Accept `cancel_requested` as pending only; poll until
   `cancelled` or a truthful completion. A short job may win the race and return
   `already_finished`; do not call that a successful cancellation test.
10. Capture passed/failed/not-run checks and actual package/runtime evidence.
    Do not claim statistical execution verified unless step 7 succeeded. Retain
    any uncertain submissions for owner reconciliation and do not retry them.

## Local automated verification

```sh
python3 -m py_compile webapp/scripts/r_analysis_bridge.py
python3 -m unittest discover -s webapp/tests -p test_r_analysis_bridge.py -v
```

Tests cover preview-only preparation, scientific/shape/integer validation,
immutable registries, unsupported designs, explicit digest confirmation,
duplicate/concurrent submissions, changed files/symlinks, loopback-only HTTP,
redirect/proxy and endpoint blocking, secret-safe errors, response bounds,
version/capability/process/source/package gates, provenance requirements,
registry/plan/cell/staging limits, disk reserves, no-write blocked plans,
single-flight preparation, uncertain submissions, actual native-result validation
and truthful cancellation.
All HTTP responses are mocked. No R computation, service restart, credential
configuration or GitHub push is performed by these tests.
