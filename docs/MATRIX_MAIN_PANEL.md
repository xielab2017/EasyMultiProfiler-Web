# Matrix download in the main application

This is a minimal local source increment, not a GitHub release. Apply to the backed-up, reviewed legacy installation. It does not require the advanced, QC or agent overlays. Do not change R, credentials, user datasets or previous analysis state.

## User flow

1. Open the existing main page on port8080 and select **矩阵下载 / Matrix** in its sidebar. The panel is part of the main DOM, not an iframe or link-only page on another port.
2. Search public GEO keywords or enter a GSE. The example button only fills GSE60450; it does not query or download automatically.
3. Select an original supplementary file. Review source URL, known/unknown size, format uncertainty and the exact plan. Choose the per-file budget (default5GiB, maximum100GiB; actual disk must also leave1GiB free). Explicitly confirm before starting.
4. Refresh progress while the background job runs. Cancel retains partial data. Resume requires a separate confirmation and only works with verified source validators and exact HTTP206 ranges. No automatic full restart, extraction, analysis or raw-read download occurs.
5. Save the completed original file directly through port8080. The full attachment is streamed in64KiB chunks; it is not buffered as one object and is not subject to the older34MiB JSON-proxy ceiling. Range and HEAD are supported.
6. Read sample information. A bounded header preview supplies candidate column names for exact GSM/description matching. Export the sample TSV and source JSON. No biological groups are inferred. Original files are unchanged.

Known-size and unknown-size files can be selected. HDF5/MTX and compressed archives are downloaded unchanged; unsupported formats are not falsely reported as parsed matrices. ObviousFASTQ/FQ/SRA/BAM/CRAM files are blocked in this matrix-only route. Archive contents remain unknown, so verify the author description before choosing one. The word RAW in a GEO archive name does not establish its contents.

## Installation by the local owner

Back up the listed source files and preserve `.git`, configuration and `.local_run`. Copy only manifest-listed files from this matrix bundle. It intentionally does not replace `public_data_server.py` or `launch_metadata.py` with advanced versions.

Run `python webapp/scripts/install_matrix_panel.py PROJECT_ROOT --check`, then run the same command without `--check`. The installer accepts only the previously inspected legacy server hash, creates a recoverable source backup, adds the matrix-only wrapper, and appends this feature to README. It neither starts/stops processes nor changes R.

After confirming no unsaved webpage work or active matrix task would be interrupted, restart only the identified metadata/static processes with the existing project Python/environment:

- Metadata: `EMP_PUBLIC_DATA_PORT=8081 .local_run/metadata_venv/bin/python webapp/scripts/public_data_server.py`
- Main static/proxy: `EMP_PUBLIC_DATA_PORT=8081 .local_run/metadata_venv/bin/python webapp/scripts/static_server.py 8080 webapp/frontend 127.0.0.1`

Use the actual verified project path and executable. Never kill unrelated port occupants or rerun a full launcher that mutates auth/network settings. Keep the R8000 process unchanged.

## Validation and limits

Offline tests cover explicit confirmation, stream limits, unknown sizes, cancellation/resumption validators, exact file hashes, unsafe URL/path rejection, attachment streaming and bounded preview. Frontend tests cover main navigation, large/unknown-size candidates, stale responses and independent consent. These are not claims of a100GiB live transfer.

The live Mac acceptance target is only GSE60450_Lactation-GenewiseCounts.txt.gz:513592bytes, SHA256 `906b6ec4c33e95ca0ba454a3e0d07ad74e9cb7528ee38b89a9b122f5674a5f0d`. Its content has27179features, Length annotation and12sample columns. The official series matrix provides12exact description mappings. Record actual browser/native results separately; do not substitute fixtures for a failed live request.

The older compatibility `processed/download` route retains its historical32MiB cap; the embedded main panel uses the new `matrix/*` route and is not governed by that cap. Previews remain bounded to256KiB/100rows, with at most5000column labels; they do not certify raw counts, inspect entire large files or perform analysis. Plain/gzip previews only; other formats still save unchanged. No automatic data cleanup is performed. Owner-led archival may be needed to recover disk space.

### Local acceptance fixes

On macOS, archive restoration can retain old frontend modification times. After copying the panel, update the copied frontend files' modification times and reload the main page with a fresh query string so an older browser cache is not mistaken for the new deployment. Do not clear unrelated browser data.

Cross-job artifacts are scoped to the current completed job. Loading another job or editing its ID clears prior download links, receipts, previews and sample exports; annotation matching must never reuse another job's columns.

On macOS, unit tests must use a real project-local temporary directory rather than the system `/var` symlink path: create an isolated directory under `.local_run/verification`, resolve it to its physical path, and set `TMPDIR` for the test command only. Do not relax the downloader's symlink checks or change global system settings. Record platform skips separately from executed tests.

### Sample provenance attachment

The sample TSV remains a separate explicit download. The provenance JSON now uses a real same-origin attachment link rather than a programmatically clicked Blob. Reading annotations creates a bounded (at most 2 MiB) temporary snapshot of those exact records and matches; the link retrieves that snapshot without refetching GEO or downloading the matrix again. Exports expire with the local metadata store or service restart. Reread sample information to regenerate an expired link. Links are disabled and cleared when the current job or accession changes. No automatic-download browser permission is requested.

The previous Blob action reported generation without confirming delivery. On the tested Chrome instance the JSON did not reach Downloads, even after separating the actions. This establishes a delivery failure, not a proven browser-policy root cause. Actual disk delivery through the new attachment link must be verified separately.
