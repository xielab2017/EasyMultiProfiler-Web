# Container version (draft)

This directory holds the container packaging for EasyMultiProfiler Web,
prepared for the stand-alone application route of the NAR Web Server
issue, which requires a container version (Docker or Podman) that runs
without installing further software.

- `Dockerfile` — builds on `rocker/r-ver:4.3.3`, installs the full
  dependency set declared in the repo `DESCRIPTION` via
  `webapp/scripts/install_runtime.R`, and starts the web app with
  `webapp/scripts/start_local.sh` (ports 8000 API / 8080 web /
  8090 gateway).

**Status (2026-10-26): draft, not yet build-verified.** The dependency
install is heavy (many Bioconductor packages compile from source or
install as binaries); the first verification build should run on a
machine with ample disk and CPU, followed by a boot check of
`GET /api/health` and the web UI. Do not cite the container as
available until that verification is recorded here with its date and
environment.
