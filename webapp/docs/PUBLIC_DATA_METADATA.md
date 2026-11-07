# Public sequencing metadata (experimental, v1)

This additive, Python-standard-library module runs without R. It fits the project's existing `webapp/scripts` helper layout and emits versioned JSON for a future Plumber/agent adapter. An optional Python sidecar now serves a Chinese metadata page and HTTP APIs; the main navigation links to the page. It is not wired into the R analysis API or AI tool registry. Existing analysis code is unchanged.

## Run

From the repository root:

```sh
python webapp/scripts/public_data.py search 'breast cancer RNA sequencing' --limit 5
python webapp/scripts/public_data.py resolve SRR390728 --select SRR390728
python webapp/scripts/public_data.py resolve GSE60424
python webapp/scripts/public_data.py parse-ena saved-report.tsv --select SRR390728
python -m unittest discover -s webapp/tests -p 'test_public_data.py' -v
```

`resolve` accepts exact GSE, SRA/ENA/DRA run/study/sample/experiment, and BioProject accession syntax. ENA coverage for any accession is not guaranteed. GEO is resolved through NCBI GDS ESearch/ESummary: only an exact accession match with an explicit SRA/BioProject relation is followed. Keyword search returns candidate GEO records, not guaranteed sequencing datasets. DOI/PMID-to-paper resolution is not implemented.

`parse-ena` requires the columns requested in `FIELDS` in the module; it performs offline parsing only. Unit-test data are explicitly synthetic. Results are sent to stdout; redirect to a file if needed. Errors go to stderr with a nonzero exit code and do not return a fake empty success.

## Manifest contract

- `schema_version`: `1.0`
- `status`: `metadata_only`
- `sources`: actual metadata request URLs, response SHA256, retrieval UTC time
- `runs`: run/study/sample/experiment IDs, organism, library strategy/layout, candidate FASTQ files with HTTPS URL, archive-reported MD5 and byte size
- `selected_runs`, `selected_bytes`: explicit selection and its size; nothing selected by default
- `download_enabled: false`, `analysis_executed: false`

Archive checksums are **not verified file checksums**: no FASTQ bytes have been downloaded. Missing links do not prove controlled access or absence of raw data. The module does not infer biological groups, mate ordering, patient identifiers, appropriate analysis settings or publication association beyond explicit accession links. Layout and metadata must be reviewed before raw-read processing.

## Boundaries and failure modes

Metadata GET requests are limited to fixed ENA and NCBI endpoints, with TLS verification, no redirects, 30-second request timeout, 8-MiB response cap, and NCBI request spacing. No arbitrary URL fetch, credentials, subprocess execution, package installation or sequencing download is performed. FASTQ URLs are manifest-only and restricted to the ENA FASTQ archive host/path. Invalid/mismatched checksum/size columns, duplicate runs and malformed rows fail closed.

Large studies can exceed the response or run limit; narrow the accession. Provider outages, rate limits, restricted network egress and missing archive coverage remain possible. No automatic retry or cross-provider fallback that could hide incomplete data is implemented.

Future integration should invoke the module without a shell, bound execution time/output, preserve the source hashes, and validate `schema_version`. Add authentication, job status, cancellation and resource policy before exposing it through an API. A download/execution feature needs separate explicit user review and independent tests, not merely a selected run in this manifest.

## Validation on this cloud

Live metadata-only checks succeeded:

- `SRR390728`: 1 run, 1 sample, 2 FASTQ links, 203,162,874 archive-reported bytes.
- `GSE60424`: exact GEO series “Next generation sequencing of human immune cell subsets across diseases”, explicitly linked to `SRP045500`; 134 runs/samples, 268 FASTQ links, 252,125,394,615 archive-reported bytes (about 252 GB).

These are metadata retrieval checks, not validation of scientific suitability or successful download/analysis. No raw sequencing files were downloaded. Snapshots supplied with the deliverable include request provenance. R remains unavailable, so Plumber integration and analysis execution are untested.

## Primary API references

- ENA file reports: https://github.com/enasequence/read_docs/blob/master/retrieval/programmatic-access/file-reports.rst
- NCBI GEO programmatic access: https://www.ncbi.nlm.nih.gov/geo/info/geo_paccess.html
- GEO/SRA raw-data relationship: https://www.ncbi.nlm.nih.gov/geo/info/faq.html

## Optional metadata UI and API

Run `python webapp/scripts/public_data_server.py` and open `http://127.0.0.1:8081/public_data.html` on that computer. The service binds loopback only. Its status is experimental metadata-only, not a production deployment.

For the existing gateway, start both the sidecar and gateway with `EMP_PUBLIC_DATA_PORT=8081`; the gateway routes only `/api/public-data/*`, `/public_data.html` and its JS to the sidecar. The setting is opt-in and does not change other API routes. Only loopback origins are supported; remote deployments require a separate security review. Restart the gateway when changing its environment.

Routes: GET health; POST search (`term`), resolve (`accession`), plan (`manifest_id`, `selected_runs`), all below `/api/public-data/`. A resolved manifest is stored in server memory for 30 minutes (maximum 20). A plan can only use a stored manifest, not arbitrary URLs supplied by the browser. It reports archive size, current free space and a 1-GiB download reserve; analysis/decompression/reference space is additional and unestimated. No download/execute route exists. A plan is review-only and is not execution authorization.

HTTP tests cover synthetic resolve→plan, bad origin/host, invalid inputs, expired manifests, insufficient disk, missing execution endpoints, and optional gateway routing. Browser JS passes syntax validation; full browser interaction has not been tested. The UI clears old plans after a new accession or changed selection, and rejects a response for a changed selection.

## Processed matrices, papers and workflow preflight (incremental slice)

The optional metadata page now includes:
- Local PDF upload/drop (≤15 MiB, isolated bounded parsing), literal accessions with page provenance, and an explicitly separate PubMed query. No PDF bytes/text are sent to external services; article/PDF contents are data, not instructions. No AI model is configured.
- GEO Series supplementary files discovered from the official SOFT endpoint; first 10 files receive bounded size probes. Candidate name/format is not a data-type assertion.
- Confirmed per-file download of known-size plain/gzip CSV/TSV/TXT candidates ≤32 MiB, to `.local_run/public_data`. No tar/zip extraction. TLS host/path restrictions, no redirects, available-space check, streamed size cap, partial-file cleanup and local SHA256 record. GEO often lacks a publisher checksum, so integrity against a publisher digest is explicitly unverified.
- Full bounded tabular inspection (≤64 MiB expanded): numeric/finite/nonnegative/integer checks, annotation-column exclusions, duplicate features, and sample-column labels. Integer nonnegative tables are only `count_like_unverified`, never automatically DESeq2-ready. TPM/FPKM cannot be distinguished from other fractional abundance values by numbers alone.
- Optional GEO series-matrix annotation retrieval (≤2 MiB compressed), with exact sample-description/ID matching; never positional joins. Multi-platform or larger annotation layouts may not resolve through this simple route.
- An editable bulk RNA-seq plan with operation ordering, parameters, datasets/sample JSON, contrast and batch checks. Validation is not execution. Other omics are explicitly unsupported placeholders; no working multiomics integration is claimed.

Additional API operations under `/api/public-data/`: POST `papers/pdf` (raw PDF body), `papers/search`, `processed/resolve`, `processed/download` (server manifest ID, file ID, confirmed=true), `processed/annotations`; GET `files/{download_id}` returns only an existing controlled download; GET `workflows/templates`; POST `workflows/validate`. Raw FASTQ download/execution remain unavailable.

### Verified processed-data example

GSE60450 discovery returned `GSE60450_Lactation-GenewiseCounts.txt.gz` (513,592 bytes). Controlled download and bounded inspection found 27,179 feature rows, 12 sample columns and a separately excluded `Length` column. All 12 columns matched exact GEO `Sample_description` values, despite different GEO and matrix orders. Author workflow describes these as featureCounts read counts: https://pmc.ncbi.nlm.nih.gov/articles/PMC4934518/ . This external evidence supports this dataset specifically; the generic classifier remains conservative.

Actual download source: https://ftp.ncbi.nlm.nih.gov/geo/series/GSE60nnn/GSE60450/suppl/GSE60450_Lactation-GenewiseCounts.txt.gz

No count-matrix analysis was executed. The page and endpoints have HTTP/logic tests; full browser interaction and an R integration run remain unverified. No public deployment is provided.
