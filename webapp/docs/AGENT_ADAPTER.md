# Restricted provider-to-tool adapter

`webapp/scripts/agent_adapter.py` is an independent, standard-library Python adapter with OpenAI-compatible OpenAI and NVIDIA Chat Completions transports and a narrow tool dispatcher. It does not modify or reuse the browser API-key settings, R copilot, R execution, or download endpoints. The existing `backend/helpers/llm.R` accepts browser/provider configuration; `ai_copilot.R` produces narrative interpretation. This adapter intentionally remains separate from those paths.

## API and opt-in

- `status() -> dict`: no network call; reports `status`, `configured`, `enabled`, `allow_model_request`, provider/model, `live_verified: false`, available tool names, and `execution_supported: false`. Credential values are never returned.
- `respond(question: str, consent: bool = False) -> dict`: returns `status`, `answer`, `tool_results`, and `execution_supported: false`. Status is one of `ok`, `unconfigured`, `consent_required`, `invalid_request`, `round_limit`, or `error`.
- Server process environment only: `EMP_AGENT_PROVIDER` accepts exactly `openai` (default) or `nvidia`. OpenAI uses only `OPENAI_API_KEY`, with optional `EMP_AGENT_MODEL` defaulting to `gpt-4.1-mini`. NVIDIA uses only `NVIDIA_API_KEY` and defaults to the pinned `nvidia/nemotron-3-ultra-550b-a55b`; any different model is rejected. Both require `EMP_AGENT_ALLOW_MODEL_REQUEST=1`, which is absent/disabled by default. Unknown providers fail closed and keys never fall back across providers. No credentials were supplied, saved, or requested for this implementation. Never place keys in source, page forms, browser storage, logs, or returned status.
- Both server `allow_model_request` opt-in and literal boolean `consent=True` are mandatory before any model or metadata request. Missing configuration is explicit and makes no network call. There is no silent offline answer pretending to be a model response.
- Consent wording for an integrating UI: “Send this question and bounded tool results to [selected provider: OpenAI or NVIDIA]. Public metadata search terms and accessions generated from it may be sent to NCBI/ENA. Do not include secrets, personal health information, or other sensitive personal data.” Obtain consent for each invocation; do not infer it from text strings such as `"true"`.
- Only the submitted question string is accepted; there is no file, PDF, upload, path, or document reader. If a user manually pastes document text into the question, that text is question content and would be transmitted after consent. The adapter cannot detect all sensitive information; the host should restrict use to public research questions.

## Fixed capabilities and limits

Provider selection fixes the endpoint to `https://api.openai.com/v1/chat/completions` (OpenAI) or `https://integrate.api.nvidia.com/v1/chat/completions` (NVIDIA). Neither endpoint can be supplied or overridden by browser/client/environment URL configuration. Redirects are refused; environment-configured proxies and managed network routing are respected. Provider timeout is 30 seconds per request. OpenAI model names are constrained to simple identifiers; NVIDIA is pinned to the exact requested model; base URLs and browser credentials are not accepted.

The entire read-only registry is:

1. `search_metadata(term, limit)`: `public_data.geo_search`, bounded to 1–10 public GEO results.
2. `resolve_accession(accession)`: `public_data.resolve`, using existing validated accession and allowlisted metadata endpoints. Returned download URLs are metadata only; nothing is downloaded.
3. `validate_plan(plan)`: local `workflow_plans.validate_plan`, which validates declared typed metadata only and always marks plans non-executable. It cannot verify actual matrices, hashes, biological independence or analysis runtime. The returned original-plan record is omitted.
4. `search_papers(term, limit)`: `paper_sources.search_pubmed`, bounded to 1–10 public PubMed article metadata records.
5. `fetch_paper_abstract(pmid)`: `paper_sources.fetch_pubmed_abstract`, accepting a positive numeric PMID string of at most 12 digits. Retrieves public title/abstract and literal, unverified accession mentions; never PDF/full text.
6. `discover_processed(accession)`: `processed_data.discover`, accepting only uppercase GSE accessions with 1–9 digits. Reads GEO metadata and may perform bounded HEAD requests for listed file sizes; it never downloads matrix contents. Filenames and listings do not establish raw-count suitability.

A three-round request can search papers, inspect one selected abstract, and list processed-file metadata for an accession found there. If no accession is present in the abstract, the model must report that limitation. More investigation requires another explicitly consented request. There is no automatic full-text/PDF fallback.

Unknown tools, extra outer arguments, wrong argument types, nonfinite JSON, invalid accessions, duplicate tool-call IDs, and multiple calls per round fail closed. Tool failures return a generic error without exposing exception text or provider bodies. There are at most three tool calls/rounds, followed by one final model request with tool choice disabled. A provider attempting a fourth tool call receives `round_limit` without dispatch. Questions are limited to 4,000 characters, final text to 8,000, provider replies to 128 KiB, tool arguments/results to 12,000 bytes, and model output to 1,200 tokens per response. Oversized tool results become an explicit truncation notice rather than partial malformed JSON. Existing metadata module network/time and response bounds also apply.

Retrieved tool content is wrapped as untrusted data and the system instruction warns against following embedded instructions. This is defense in depth, not a claim of complete prompt-injection protection. Capability enforcement is in Python, not dependent on the model obeying the prompt. There is no shell, code execution, download, filesystem-write, upload, analysis, or arbitrary HTTP tool. Tool arguments may only cause the documented read-only public metadata requests or local validation.

## Integration obligations

This file adds no route/UI and does not assert the existing page now uses it. A host must validate JSON input types, never accept client credentials or client-selected endpoints, enforce access control and per-user request/rate limits, surface consent and unconfigured/error states, and render answer text safely (not executable HTML). Do not use the narrative answer as evidence that an analysis ran. Metadata calls can take multiple requests; execution is synchronous and should not block an event-loop server. Avoid logging questions, credentials, request headers, or raw provider failures. No conversation state or keys are persisted by the adapter.

## Verification

Run `python -m unittest discover -s webapp/tests -p test_agent_adapter.py -v` from the repository root. Tests mock all provider/metadata networking, exercise both opt-in gates, fixed endpoint, schema rejection, bounded tool execution, typed validation, and sanitized errors. The article → abstract → matrix-metadata loop is also tested with mocked tool responses, including assertions that PDF extraction and matrix downloads are never called. **No live model call or real provider compatibility was verified.** A configured deployment still requires a separately authorized live smoke test; no credentials are needed to run these offline tests.


## NVIDIA documentation verification (2026-11-06)

Official sources consulted without authentication or API inference calls:

- [NVIDIA hosted model catalog](https://build.nvidia.com/nvidia/nemotron-3-ultra-550b-a55b) lists the exact model ID, a hosted endpoint example using `https://integrate.api.nvidia.com/v1`, and tool-calling capability. Its availability section advertises the endpoint as available.
- [NVIDIA model reference](https://docs.api.nvidia.com/nim/reference/nvidia-nemotron-3-ultra-550b-a55b) describes tool use and configurable `enable_thinking=True/False`. The adapter sends `chat_template_kwargs: {enable_thinking: false}` to avoid spending its small output budget on reasoning. The reference also includes deployment-specific parsing guidance; this is not evidence that this hosted transport has been tested.
- [NVIDIA NIM function-calling documentation](https://docs.nvidia.com/nim/large-language-models/1.8.0/function-calling.html) documents the OpenAI-compatible `tools` and `tool_choice` structure. This older version's model list is not evidence of current Ultra availability. [NIM 1.10 release notes](https://docs.nvidia.com/nim/large-language-models/1.10.0/release-notes.html) document changing/deprecated `parallel_tool_calls` support. The NVIDIA payload therefore omits that optional parameter; Python still rejects multiple calls in any response and enforces the same three-round maximum.

The official listing verifies that the named model and hosted URL are advertised, **not** this account's entitlement, remaining quota, service health, or successful hosted tool-calling behavior. `live_verified` remains false. The NVIDIA transport and tool roundtrip were tested with mocks only; no live provider request was made and no exposed credential was read, copied, saved, or used.

The host UI must display the actual configured provider from `status()` in the consent prompt, not hard-code OpenAI. Do not enable model requests until the deployment operator has securely provisioned a valid server-side credential and reviewed applicable provider terms. Credentials previously exposed in chat should be revoked and replaced; do not paste them into code, logs, command lines, or browser settings. No setup in this change provisions or enables credentials.
