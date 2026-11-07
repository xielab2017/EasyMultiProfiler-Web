# Main-page matrix/original-file downloads

The standalone `webapp/scripts/matrix_downloads.py` supports an explicitly
selected original GEO supplementary file. It does not depend on the optional
advanced/raw-download module. The main page/backend must own the manifest and
plan; HTTP clients supply only IDs, a byte budget, and explicit confirmation.

## Scope and limits

- TXT, TSV, CSV, MatrixMarket/MTX, H5AD, HDF5, Loom, RDS, gzip, ZIP, TAR and
  other original supplementary formats are downloadable. There is no 32 MiB
  or tabular-only limit. The old discovery manifest's
  `maximum_download_bytes` does not constrain this manager.
- Direct files named FASTQ/FQ/SRA/BAM/CRAM, including compressed or wrapped
  versions, are rejected because this feature is only for matrix downloads.
- Archives are never opened or extracted. `GSE*_RAW.tar` is not automatically
  classified as sequencing reads: GEO uses this name for varied author
  submissions, including matrix collections. It remains an explicit user choice
  with an unknown-contents warning. No file is automatically selected.
- Default per-file budget: **5 GiB**. User-selected maximum: **100 GiB**.
  A known size must fit the chosen budget. An unknown size requires an explicit
  budget in the plan, even if the chosen value is the usual 5 GiB.
- One worker across all manager instances/processes sharing a download root.
  Streams use a 1 MiB buffer by default (maximum 8 MiB), a 30-second socket
  timeout (maximum 120 seconds), and a 24-hour attempt deadline checked between
  reads and hashing blocks. Production responses use `read1` when available
  so slow sources do not need to fill the buffer before stop checks.
- A **1 GiB** free-space reserve is required at planning/start/resume and before
  every write. Unknown-size planning reserves the full selected budget.
- Downloaded data stays local. No shell, executable, parser, decompressor,
  converter, analysis engine or model is invoked.

## Integration contract

```python
from matrix_downloads import MatrixDownloadManager, DownloadError

manager = MatrixDownloadManager(service_owned_private_directory)
plan = manager.plan(server_owned_manifest, file_id, max_bytes=None)
# Display plan source_name/source_url/bytes/max_bytes/warnings/blockers.
# Keep this plan in server-owned state; never accept a client-supplied plan.
job = manager.start(plan, confirmed=True, plan_sha256=plan['plan_sha256'])
job = manager.get(job['job_id'])
manager.cancel(job['job_id'])
manager.resume(job['job_id'], confirmed=True, plan_sha256=plan['plan_sha256'])
handle, receipt = manager.open_completed(job['job_id'])
with handle:
    # Stream bounded chunks to the same user's response; do not read all at once.
    ...
```

`plan(manifest, file_id, max_bytes=None)` performs no network access. Plans are
registered in memory for 30 minutes, up to 128 plans. A plan with blockers has
`status="blocked"`; otherwise `status="ready_for_confirmation"` and
`download_enabled=true`. Exact consent binds the selected source, byte cap,
service destination and limits. Duplicate starts for the same registered plan
reuse its existing job rather than downloading twice. Start never resumes or
restarts a failed job automatically.

Plan keys include `plan_id`, `plan_sha256`, `source_name`, `source_url`, `bytes`
(nullable), `total_bytes` (nullable), `max_bytes`, `file` (file_id/name/url/bytes/
checksum), `warnings`, `blockers`, `status`, `download_enabled`, `limits`, and
`destination_id`.

`start` and `resume` return promptly with a snapshot; handlers should poll `get`
instead of waiting for transfer completion. `wait(job_id, timeout)` exists only
for local/test callers. Job keys include `job_id`, `plan_id`, `plan_sha256`,
`plan`, `status`, `source_name`, `source_url`, `total_bytes`, `max_bytes`,
`bytes_downloaded`, `resume_supported`, `error`, `receipt`, `attempts`, and
`cancel_requested`. Status is queued/running/completed/cancelled/interrupted/
failed. Cancellation is cooperative; a pending network read can take up to its
socket timeout. Stop checks also observe a persisted cancellation marker, so
another server process can request cancellation safely.

`open_completed(job_id)` returns **(binary file handle, receipt dictionary)**.
The caller must close the handle and stream bounded chunks. It accepts no path.
Use an escaped/encoded Content-Disposition source filename, application/octet-
stream and nosniff. Never interpolate the source filename into a filesystem path
or an unescaped HTTP header. Receipts contain `job_id`, `source_name`,
`source_url`, `filename`, `bytes`, `sha256`, `publisher_checksum`,
`publisher_checksum_verified`, `archive_extracted=false`, and
`analysis_executed=false`. A completion-time device/inode/size/mtime/ctime
fingerprint is checked against the opened file before retrieval. Device, inode,
size, or mtime changes are rejected immediately. If only ctime changed (for
example, macOS file metadata updates), the same opened descriptor is rehashed
with bounded reads. Its SHA-256 must match the receipt and all fingerprint
fields must remain stable across verification; only then is it rewound and
returned. The rehash runs outside the manager lock so status/cancel calls remain
responsive. This requires no redownload and never blindly ignores ctime.
Unchanged fingerprints avoid rereading the entire large payload.

The ctime-only fallback deliberately does not cache or rewrite the recorded
identity. Every later retrieval with that drift (including HEAD/preview) hashes
the original payload again before returning its handle. On multi-GiB files,
verification can exceed a proxy's upstream response timeout (120 seconds in the
current proxy); retries would repeat verification. This is a known operational
limitation, not permission to skip verification or automatically redownload.

All failures are `DownloadError` for synchronous validation or a sanitized job
`error` for background transfers. Caller-visible exceptions do not include
credential-bearing URLs, raw exception details, or local artifact paths.

## Safety, persistence and resuming

Only the strict `processed_data.safe_url` official GEO HTTPS whitelist is used.
An FTP metadata link is normalized by that existing validator to its HTTPS
counterpart. Credentials, query strings, fragments, unexpected origins,
traversal and redirect responses are refused. Responses must have the exact
planned URL and identity content encoding; Content-Length and streamed bytes
must fit the confirmed plan.

The service configures a private download root (0700 on POSIX). Job directories
are random UUIDs, and payloads use opaque `<job_id>.part`/`<job_id>.data` names.
All files are 0600, all path components are checked against symlinks, and
symlink/hardlink/nonregular artifacts are rejected. `O_NOFOLLOW` is additionally
used where available. The root is service-owned and must not be writable by
untrusted OS users. POSIX flock or Windows msvcrt locks prevent concurrent
workers and release automatically on process exit. Native Windows operation
has not been tested by this test suite.

Each committed stream chunk is fsynced and checkpointed with its byte count
and local SHA-256. Atomic private JSON files hold progress and final receipts.
Cancellation/failure keeps partials; nothing automatically deletes or replaces
them. On restart, unfinished jobs are marked interrupted only after checking
that no process holds the worker lock. Recovery never auto-starts a transfer.

An explicitly confirmed resume requires the same plan digest, a retained
partial matching its durable size and hash, and an original **strong ETag** or
valid **Last-Modified** response validator. A weak ETag alone is insufficient.
The request uses `Range: bytes=<retained-size>-` and `If-Range`. Before appending,
the server must return HTTP **206**, the exact starting byte, a bounded total
consistent with the original size, a complete remaining Content-Range,
consistent Content-Length if present, and the unchanged validator. HTTP 200,
changed/missing validators, unsupported range, different totals, and malformed
ranges fail closed without append, deletion, or automatic restart. An unknown
original total can become known from a valid resumed Content-Range, still
within the consented cap.

A crash between writing bytes and committing their checkpoint can leave a
partial whose size/hash does not match the durable record. Such a partial is
preserved and refused for resume. A fully written but unfinalized partial is
also not silently accepted or restarted. When retained bytes reach the known
total size, `resume_supported` is false after cancellation, failure, or restart.
Explicit resume is rejected before any HTTP request or retained-file change,
and the error instructs the user to create a new explicitly confirmed download
plan. Existing partial bytes remain untouched; cleanup and redownload are never
automatic.

A local SHA-256 is a receipt for the downloaded bytes, **not publisher
verification or evidence that the file is an expression matrix**. If official
manifest metadata supplies an explicit checksum object
`{"algorithm": "sha256" | "md5", "value": "hex digest"}`, it is checked before
completion. Otherwise `publisher_checksum_verified` remains false. A checksum
mismatch is not a completed/downloadable artifact. Scientific suitability and
any later analysis require separate validation and consent.

## Offline verification

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s webapp/tests -p 'test_matrix_downloads.py' -v
```

The tests use a real loopback HTTP server, not external GEO file downloads.
The trusted fixture transport maps an already validated official GEO URL to
localhost. Coverage includes multi-format/large-file planning, unknown sizes,
cap and disk boundaries, exact consent, private files, source/path/link checks,
process locking, cancellation, persisted restart, streamed receipts, optional
publisher checksums, truncation, valid ETag/Last-Modified range resume, and
rejection of full/changed/malformed resumed responses, and full-size retained
checkpoints after cancellation/restart. Large real downloads,
Windows behavior, and main-page/macOS end-to-end integration are separate
acceptance stages.
