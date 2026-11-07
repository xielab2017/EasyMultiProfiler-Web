# Matrix sample annotations

This component retrieves public GEO sample metadata for a selected expression
matrix. It does not download raw reads, choose groups or contrasts, or run an
analysis. Matrix discovery and confirmed supplementary-file downloads keep their
existing behavior and bounds.

## Retrieval and provenance

`processed_data.fetch_annotations(accession, labels=None)` first requests only:

- `https://ftp.ncbi.nlm.nih.gov/geo/series/<group>/<GSE>/matrix/<GSE>_series_matrix.txt.gz`

It accepts a series matrix only when its `Series_geo_accession` is the requested
GSE, its sample identifiers are unique GSM accessions, and sample metadata rows
have the expected number of columns. If the default matrix is absent, malformed,
for another series, reports multiple platforms, or does not uniquely match all
supplied column labels, it tries only:

- `https://ftp.ncbi.nlm.nih.gov/geo/series/<group>/<GSE>/soft/<GSE>_family.soft.gz`

The SOFT parser requires the requested series and complete, unique membership of
its declared samples. Platform and expression tables are not used for matching.
There is no directory enumeration, platform-matrix fan-out, supplementary-file
fallback, or raw-data download. Every request disables redirects and has a
20-second socket timeout. HTTP access denials and throttling stop rather than
trying another endpoint. A transient read error can try the independent official
family metadata endpoint.

Both compressed sources have the same 2 MiB limit and 64 MiB expanded limit.
Exceeding either stops, with no less-restricted retry. At most two metadata files
are requested. Valid metadata can therefore be unavailable for large studies;
that limitation is reported rather than silently relaxing bounds.

The result retains `records`, `source_url` and `sha256` for compatibility, and adds
`source_format`, compressed/expanded byte counts, `sources` and `warnings`.
SHA-256 is computed from the downloaded compressed bytes. It records local byte
identity, not a verified publisher checksum. `sources` includes each successfully
read and decoded source, including a matrix later rejected in favor of SOFT;
the top-level URL/hash always belongs to the returned records. Warnings explain
fallback or unresolved columns. A missing fallback may preserve same-series
matrix metadata with an explicit warning and unmatched columns. Invalid SOFT
identity/membership and size-limit failures fail closed.

Callers should pass the actual selected matrix sample columns through `labels`
when available, then use `match_samples(labels, result['records'])`. The legacy
one-argument call remains supported but cannot detect matrix-column mismatches.

## Exact mapping and metadata

Matching uses only exact, case-sensitive equality with `Sample_geo_accession` or
one complete `Sample_description` value. The response gives `matched_fields` for
each accepted match. It does not trim labels, use substring/title similarity,
match by column position, or derive mappings from filenames. Shared descriptions,
duplicate column labels, and two aliases assigning two columns to one GSM remain
`unmatched_or_ambiguous`, with no sample attached.

Titles, descriptions, reported characteristics, source names, and platform IDs
are retained as source metadata. No group, condition, contrast, pairing, or batch
interpretation is inferred. A successful identifier match does not establish
analysis suitability or statistical validity.

## GSE60450 verification (2026-11-07 UTC)

The official default series matrix was available with HTTP 200:

- URL: https://ftp.ncbi.nlm.nih.gov/geo/series/GSE60nnn/GSE60450/matrix/GSE60450_series_matrix.txt.gz
- Compressed bytes: 2,633
- SHA-256: `8b3b727e7c8a7794c2bda57d62109c4cecdb9dc6eaac579a8cfa7e8921638267`

It contains all 12 full matrix column identifiers in `Sample_description`.
Consequently this dataset works through the primary endpoint; the fallback is
for other endpoint/metadata cases, not a claim that GSE60450 has no series matrix.
The previously verified official family SOFT fixture is 2,905 compressed bytes,
with SHA-256 `4ed19bb55731ec6a8c534de63505896ad5b1731b891960a813ff3e95a703338b`:

https://ftp.ncbi.nlm.nih.gov/geo/series/GSE60nnn/GSE60450/soft/GSE60450_family.soft.gz

Both metadata sources match the 12 matrix sample columns exactly. Matrix order
is basal GSM1480297–GSM1480302 followed by luminal GSM1480291–GSM1480296; it differs
from metadata record order. `EntrezGeneID` and `Length` are not sample columns.
No grouping or analysis was executed in this annotation check.

## Tests

Run offline annotation and existing download regression tests:

```bash
PYTHONDONTWRITEBYTECODE=1 python -m unittest discover -s webapp/tests -p 'test_matrix_annotations.py' -v
PYTHONDONTWRITEBYTECODE=1 python -m unittest discover -s webapp/tests -p 'test_processed_data.py' -v
```

Synthetic fixtures preserve the real series-matrix and family-SOFT formats. Tests
cover source identity, exact reordered mapping, aliases and duplicates,
multiple platforms, missing/malformed sources, provenance, access denials,
redirect refusal, and compressed/expanded limits. One optional test uses the
already-downloaded public fixture at `../public_validation_inputs`; it never
fetches fixtures or reads the count table beyond its header.
