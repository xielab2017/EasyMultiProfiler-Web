# EasyMultiProfiler Web - container image (DRAFT, not yet build-verified)
#
# Purpose: the stand-alone application route of the NAR Web Server issue
# requires "a container version (Docker or Podman) that runs without
# installing further software". This Dockerfile packages the full web
# app (Plumber API + static front end + gateway) on the rocker R base
# image; all R dependencies are installed at build time from the repo's
# own DESCRIPTION via webapp/scripts/install_runtime.R.
#
# STATUS 2026-10-26: drafted, NOT yet built end-to-end. The dependency
# install compiles many Bioconductor packages and needs a machine with
# ample disk/CPU; verify the build and a full boot before relying on
# this file for a submission. Known follow-ups for the verification
# pass: pin the Bioconductor release that matches R 4.3.3, confirm the
# gateway/static server ports, and add a healthcheck once the boot
# sequence is confirmed.
#
# Build (from the repository root):
#   docker build -f container/Dockerfile -t emp-web:9.1.0 .
# Run:
#   docker run --rm -p 8080:8080 -p 8000:8000 -p 8090:8090 emp-web:9.1.0
# Then open http://127.0.0.1:8080 (UI) and
# http://127.0.0.1:8000/api/health (API health check).

FROM rocker/r-ver:4.3.3

# System libraries commonly required by the DESCRIPTION dependency tree
# (XML, curl, ssl, font/rendering stack for publication graphics).
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 git curl \
      libxml2-dev libcurl4-openssl-dev libssl-dev \
      libfontconfig1-dev libfreetype6-dev libpng-dev libjpeg-dev \
      libtiff5-dev libcairo2-dev libharfbuzz-dev libfribidi-dev \
      pandoc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/emp
COPY . /opt/emp

# Install every CRAN/Bioconductor dependency declared in DESCRIPTION
# plus the EMP package itself, using the project's own installer so the
# container and the desktop installers resolve the same package set.
RUN Rscript webapp/scripts/install_runtime.R --fail-fast

# The desktop start script can auto-publish via Tailscale Funnel; that
# is meaningless (and unavailable) inside a container, so disable it.
ENV EMP_ENABLE_FUNNEL=false \
    API_PORT=8000 \
    WEB_PORT=8080 \
    GATEWAY_PORT=8090

EXPOSE 8000 8080 8090

CMD ["bash", "webapp/scripts/start_local.sh"]
