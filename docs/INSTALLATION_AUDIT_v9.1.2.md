# Installation audit v9.1.2

## Scope and tested environment

Audit and isolated tests ran on Linux with Python 3.12 and Bash. No system packages were installed, no package repositories or security settings changed, and no Funnel/public binding was executed. R and PowerShell are unavailable in this managed environment. Native macOS and Windows execution, R package installation, and full R backend readiness remain unverified. Shell syntax and mock execution do not establish native platform support.

## Ready without R: metadata UI

- macOS: `bash Start-EMP-Metadata.command`
- Linux: `bash Start-EMP-Metadata.sh`
- Windows: `Start-EMP-Metadata.cmd`
- Direct: `python webapp/scripts/launch_metadata.py`
- Read-only dependency report: append `--check`.

Requires Python 3.10 or newer; optional `pypdf` enables PDF extraction. The launcher checks the Python version before importing sidecar modules. It binds only to 127.0.0.1, defaults to port 8081, and accepts `--port`. `EMPI_PYTHON` may specify an executable path containing spaces. Run in a terminal; Ctrl+C stops it. This starts metadata features, not the full R analysis backend. The JSON check does not contact providers, install dependencies, or start a server; its optional dependency and R availability fields reflect the current machine.

## Changes

- Unix full-service defaults are now loopback with Funnel disabled. Config initialization fills missing hosts with loopback, preserving existing explicit settings. Existing runtime.env values can still opt into remote binding; inspect them before launching.
- Unix start checks Python >=3.10, R >=4.3.3, curl, valid distinct ports before starting anything. `EMP_DRY_RUN=1` validates and prints configuration without creating service files. Python and R executable overrides are quoted.
- Unix prerequisite checking now rejects Python 2/old Python instead of accepting any executable, and daily launch no longer ignores failed prerequisites. No-browser environment option works on Unix.
- Startup no longer kills arbitrary port owners. Unix and Windows PID-file stopping requires a recognized absolute script path in the current normalized checkout, with argument boundaries, to reduce stale/reused PID risks. Legacy relative-path processes are left running and must be stopped manually; new Unix launches use absolute paths. Port conflicts fail with guidance. Windows stop no longer performs broad listener cleanup. Unix readiness failure and Windows partial startup failure clean up started services.
- Windows cross-OS handoff passes arguments directly to Bash rather than constructing a shell string. Bootstrap uses terminating PowerShell errors. Runtime configuration path for token persistence is defined.
- Both full launchers generate nonsecret runtime_ports.local.js from validated numeric API and web ports for frontend discovery.
- System dependency installer fixes the Fedora function name and honors EMP_AUTO_INSTALL=0 before any package-manager operations. Python baseline is 3.10.
- Mac R installation looks under Resources/bin and no longer passes installer `-allowUntrusted`.
- Removed broken Linux CRAN repository/key import and fixed Fedora38 RPM assumptions. Missing/old Linux R now stops with official distribution-specific setup guidance. Administrators must install R >=4.3.3 using approved repositories. The script does not change apt signing keys or sources.
- R package installer explicitly includes plumber, jsonlite and base64enc and creates a writable project-local .local_run/R_libs library. Launchers discover that library.
- Funnel entry points no longer opportunistically publish an unrelated Agent Hub.

## Validation

`python -m unittest discover -s webapp/tests -p test_launchers.py -v`

Tests cover Bash syntax for shell/command files; metadata JSON dependency check; .command → shell wrapper; quoted project and R executable paths; local-only defaults; dry-run no-side-effects; invalid port/missing R failure; static Windows handoff checks, and pure command-identity fixtures rejecting other checkouts, prefixed paths, relative paths and script-name suffixes without sending process signals. These tests are isolated and do not run installers.

## Remaining native validation

1. macOS Bash 3.2 on Intel and Apple Silicon: fresh Python/R installation, Homebrew PATH discovery across child shells, and daily restart.
2. Windows PowerShell 5.1/7: Python launcher/Store alias handling, non-ASCII paths, UAC installation, process cleanup, and R package installation.
3. Linux administrator-provisioned R: real package installation, backend health, and complete workflow smoke tests. Managed apt denials are not bypassed.
4. Legacy runtime.env uses shell syntax on Unix and key/value parsing on Windows; avoid complex shell expressions in shared configs. Existing explicit remote settings are not automatically migrated.

Older installation guides describing fully automatic Linux R repository setup no longer apply to that step; use the approved-source instructions above.
