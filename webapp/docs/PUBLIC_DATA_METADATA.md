# Public sequencing metadata (experimental, v1)

This additive, Python-standard-library module runs without R. It fits the project's existing `webapp/scripts` helper layout and emits versioned JSON for a future Plumber/agent adapter. It is **not yet wired into the web UI, Plumber API or AI tool registry**. Existing analysis code is unchanged.

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
