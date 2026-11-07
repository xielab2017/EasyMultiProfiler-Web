# v9.1.2 — Local installation and agent context

Independent development update; original v9.1.0 remains untouched. No merge, public deployment or live-provider verification is implied.

## Implemented

- Metadata-only cross-platform entry points, Python >=3.10 validation and offline --check. Optional pypdf for local PDF extraction; full R analysis remains separate.
- Safer full-service launch defaults, prerequisite/port checks, quoted paths, own-process cleanup and runtime frontend-port discovery.
- Fedora dispatch and Mac R-path fixes. Linux R setup stops safely with approved-source instructions instead of invalid CRAN key/repository mutations. Explicit plumber/jsonlite/base64enc installation and writable project R library. --no-emp smoke respects its option.
- Server-owned selected-context IDs, sanitized preview and digest binding, separate consent, get_selected_context read-only agent tool, redacted minimal tool audit. Context includes metadata/preflight/inspection summaries, not actual analysis results. Raw matrices, PDFs, paths and sample/group labels are excluded.

## Validation and limits

118 Python unittests and Node resolver/locale/syntax checks pass against this update. Launcher coverage includes mocked quoted paths/defaults/errors, shell syntax and static Windows checks. These are not native Windows or macOS installation tests; R/PowerShell are unavailable. R installer changes have static contract checks only. Metadata --check reports ready on this Linux environment while explicitly reporting missing R. Full browser interaction and actual NVIDIA/OpenAI model calls remain unverified. Context projection does not establish scientific correctness or confirm that selected snapshots belong to the same experiment.

Read docs/INSTALLATION_AUDIT_v9.1.2.md and webapp/docs/AGENT_ADAPTER.md for exact contracts. Existing explicit runtime configuration can override safer new defaults. No credential values, user PDFs or downloaded datasets are included in source control.
