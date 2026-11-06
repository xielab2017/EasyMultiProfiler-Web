# Paper sources: local PDF and public literature entry points

`webapp/scripts/paper_sources.py` is an additive discovery module. It does not import data, download matrices, execute paper instructions, run LLMs, or claim study relevance.

## Callable API

- `extract_pdf(data: bytes, filename='paper.pdf') -> dict`: parses PDF bytes locally. `filename` is not used as a filesystem path. No PDF bytes or extracted text are transmitted to external services.
- `extract_text(text: str) -> dict`: extracts literal identifiers from locally provided text. It makes no network or subprocess calls.
- `search_pubmed(query: str, limit=10) -> dict`: sends the explicit keyword query to NCBI PubMed ESearch and retrieves matching ESummary metadata. Limit must be an integer between 1 and 20; query is limited to 300 characters. Do not automatically feed uploaded paper text into this function. The UI should disclose that the search query goes to public NCBI services and advise against private information.
- `PaperSourceError(ValueError)`: controlled validation, parser, and service failures with user-displayable messages. HTTP handlers should catch this separately from unexpected errors.

Extraction result fields:

- `source`: `pdf` or `text`.
- `accessions`: objects with `accession`, `kind` (`GEO`, `SRA`, `BioProject`), `pages` (one-based), canonical repository `url`, and `verified: false`.
- `dois`: objects with `doi` and one-based `pages`.
- `warnings`: nonempty list, including that identifiers are unverified mentions.

Text input is treated as one synthetic page. Only explicit GSE, SRP, PRJNA, PRJEB, PRJDB identifiers and DOI-like strings are recognized. Identifiers are deduplicated and retain all inspected page numbers. The module does not inspect nearby wording to infer relevance; an accession mentioned in references or even malicious instructions remains an unverified literal candidate. DOI recognition is heuristic, including punctuation trimming, and may miss line-wrapped identifiers or include trailing punctuation.

Search result fields: `source: 'pubmed'`, `query`, `articles`, `warnings`. Article objects include `pmid`, `title`, `journal`, `date`, `dois`, canonical PubMed `url`, and unverified `accessions` extracted only from the title. Title `pages` are synthetic, not paper page provenance. Abstracts, full text, supplementary files, GEO links absent from metadata, and count matrices are not fetched. Empty accession lists are normal. Follow a paper's data availability section or upload its PDF, then verify candidates using the separate repository discovery interface.

## Local parser requirements and limits

Requires optional `pypdf` in the same Python interpreter as the service; it was already installed in this development environment. No package is installed automatically. Without it the function returns a clear error and suggests pasting the data-availability text. Encrypted, malformed, and unsupported PDFs are rejected. Image-only PDFs require OCR, which is not implemented.

PDF parsing runs in a separate local process with a 20-second wall timeout. Unix workers also apply 512 MiB virtual-memory and 15-second CPU limits. These resource limits are not a security sandbox, and Windows lacks Unix memory/CPU enforcement. Keep the parser current and restrict this service to its intended trusted local deployment. The worker does not intentionally make network requests, render JavaScript, follow links, launch document actions, or execute extracted instructions.

Limits: 15 MiB PDF input, first 100 pages, 1,000,000 extracted characters, at most 100 unique accessions and 100 DOI candidates. Extraction reports truncation. The hosting HTTP service must also enforce a request-body limit before buffering uploads and bounded request concurrency. A compact PDF can expand significantly during parsing; worker resource limits mitigate this on Unix but do not replace platform isolation.

PubMed access uses fixed HTTPS ESearch/ESummary endpoints, rejects redirects, bounds each response to 2 MiB, uses a 12-second per-request timeout, and paces requests below three per second per service process. Multiple service processes need shared throttling. Failed service requests do not fall back to arbitrary URLs. Remote strings are untrusted: render titles/journals/DOIs using text content, never raw HTML. No live public query was required for the unit suite; remote behavior is fixture-tested.

## Verification

Run:

```
python -m unittest discover -s webapp/tests -p test_paper_sources.py -v
```

Tests include a real generated PDF through the worker, page provenance, explicit identifier boundaries, missing parser, malformed input, PDF timeout, malicious instruction text remaining inert, bounded/deduplicated candidates, PubMed keyword-only fixtures, invalid queries, empty results, endpoint restrictions, and redirect rejection.

## Selected-article abstract extraction

`fetch_pubmed_abstract(pmid: str) -> dict` fetches exactly one public PubMed article via fixed NCBI EFetch. Only a numeric PMID (1–12 digits, nonzero leading digit) is transmitted. It returns:

- `source: 'pubmed_abstract'`, `pmid`, `title`, `abstract`, `has_abstract`, canonical PubMed `url`.
- `accessions` and `dois` in the extraction shape above, with `pages: []` because no PDF pages were inspected. Each candidate adds `pmid` and `sections` (`title`, `abstract`, or DOI-only `article_metadata`) for provenance. All accessions remain unverified literal mentions.
- `links`: `{kind, url}` objects for PubMed and, only when reported with a valid identifier, PMC. Links are not fetched. No publisher link or free full-text access is inferred.
- `warnings`: source/relevance limits and explicit missing-abstract or missing-PMC-link notices where applicable. No accession in an abstract does not mean no public data exists.

Search remains metadata-only; this separate selected-article operation fetches the abstract but not full text or supplementary files. Structured abstract paragraphs are joined with blank lines; inline XML formatting is converted to plain text. Treat returned title and abstract as untrusted content and render as text, not HTML or model instructions.

The EFetch response shares the 2 MiB network-response cap and timeout/pacing rules. XML preflight limits depth to 64, elements to 20,000, and text to 200,000 characters. Entity declarations and external entity resolution are rejected, including in UTF-16 input. PubMed's ordinary external DOCTYPE is accepted but never downloaded. Parsing uses only Python standard-library Expat/ElementTree, requiring no extra XML dependency.

Additional tests cover selected-PMID matching, abstract/title provenance, missing abstracts and full-text links, malformed XML, invalid PMIDs, internal/external entity attacks including UTF-16, structural/text/size limits, and malicious instructions remaining inert. The suite now contains 19 passing tests; selected-article network behavior is fixture-tested, not live-verified by this module's worker.
