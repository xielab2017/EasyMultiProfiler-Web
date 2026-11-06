# v9.1.1 — Public-data and agent development slice

Based on v9.1.0 commit b36909d917ec19a8b5f5add05890219d32c670b6. Published only to the independent codex/v9.1.0-public-data-metadata branch. No merge, public deployment or version tag is implied.

- Optional Python sidecar and Chinese UI linked from the existing sidebar; opt-in gateway routes.
- GEO/SRA/ENA metadata, bounded processed-matrix downloads with explicit confirmation, local SHA256 and conservative type checks.
- Local bounded PDF parsing, PubMed metadata and abstract extraction; no PDF upload to providers.
- Editable bulk RNA-seq preflight with sample identity, provenance, parameters, contrast, replication and batch-confounding checks; no execution engine.
- Fixed-endpoint OpenAI/NVIDIA adapters, server credentials only, default disabled, explicit consent, bounded read-only tool calls; no live model test.
- HTTP Range robustness fixes and regression coverage.

## Verification

92 Python tests passed: metadata/HTTP/processed data 36, papers 19, workflow plans 14, adapters 18, static server 5. JavaScript syntax checks passed. Live metadata and one small GSE60450 matrix download/sample mapping were verified. Publisher checksum is unavailable; reported SHA256 is a local digest.

R/Bioconductor is unavailable in this cloud. Full browser interaction, original R analysis, multiomics execution, large/MTX/H5AD matrix support, actual provider inference and production readiness remain unverified. NVIDIA model catalog support does not prove account entitlement or live service compatibility.

## Start

`python webapp/scripts/public_data_server.py`

Open localhost port 8081 on the same computer. For PDF functionality install the optional reputable `pypdf` dependency according to your environment's dependency policy. Do not enable network exposure without a security review. Do not paste secrets into chat, code, command arguments or source control.

See webapp/docs/PUBLIC_DATA_METADATA.md, PAPER_SOURCES.md, WORKFLOW_PLANS.md and AGENT_ADAPTER.md for contracts and limitations. Future independently published changes will increment the version and update README at the user's request.
