# ── EasyMultiProfiler – R Plumber Backend ────────────────────────────────────
# Base: rocker/r-ver gives us a clean R installation without RStudio
FROM rocker/r-ver:4.3.3

# ── System dependencies ───────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libglpk-dev \
    libgsl-dev \
    libhdf5-dev \
    libfftw3-dev \
    libboost-all-dev \
    libbz2-dev \
    libzstd-dev \
    zlib1g-dev \
    liblzma-dev \
    libpng-dev \
    libjpeg-dev \
    libgfortran5 \
    liblapack-dev \
    libblas-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    pandoc \
    git \
    && rm -rf /var/lib/apt/lists/*

# ── Configure CRAN mirror ─────────────────────────────────────────────────────
RUN echo 'options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/bookworm/latest"))' \
    >> /usr/local/lib/R/etc/Rprofile.site

# ── Install BiocManager ───────────────────────────────────────────────────────
RUN R -e "install.packages('BiocManager', ask = FALSE)" && \
    R -e "BiocManager::install(version = '3.18', ask = FALSE, update = FALSE)"

# ── Install CRAN packages ─────────────────────────────────────────────────────
RUN R -e "install.packages(c( \
    'plumber', 'jsonlite', 'base64enc', \
    'aplot', 'bigstatsr', 'Boruta', 'bootnet', 'data.table', \
    'dynamicTreeCut', 'fastcluster', 'forcats', 'ggiraph', 'ggplot2', \
    'ggsignif', 'ggpubr', 'ggrepel', 'ggbreak', 'glue', 'gson', \
    'infotheo', 'magrittr', 'Matrix', 'memoise', 'missRanger', \
    'networkD3', 'patchwork', 'purrr', 'pillar', 'psych', 'qgraph', \
    'randomForest', 'rlang', 'rstatix', 'Rcpp', 'RcppParallel', \
    'snowfall', 'spsUtil', 'stringr', 'tibble', 'tidyr', 'vegan', \
    'WGCNA', 'withr', 'xgboost', 'yulab.utils' \
  ), ask = FALSE)"

# ── Install Bioconductor packages ─────────────────────────────────────────────
RUN R -e "BiocManager::install(c( \
    'biomformat', 'clusterProfiler', 'DESeq2', 'DOSE', 'edgeR', \
    'enrichplot', 'ggtree', 'impute', 'limma', 'MultiAssayExperiment', \
    'qvalue', 'S4Vectors', 'SummarizedExperiment', 'tidybulk' \
  ), ask = FALSE, update = FALSE)"

# ── Copy the EasyMultiProfiler package source and install ─────────────────────
WORKDIR /install
COPY ../../ /install/EasyMultiProfiler
RUN R -e "install.packages('/install/EasyMultiProfiler', repos = NULL, type = 'source')"

# ── Copy backend application ──────────────────────────────────────────────────
WORKDIR /app
COPY . /app

# ── Persistent runtime storage ────────────────────────────────────────────────
RUN mkdir -p /data/sessions /data/jobs && chmod -R 777 /data

# ── Expose port ───────────────────────────────────────────────────────────────
EXPOSE 8000

ENV BACKEND_DIR=/app \
    API_HOST=0.0.0.0 \
    EMP_SESSION_DIR=/data/sessions \
    EMP_JOB_DIR=/data/jobs \
    EMP_PROJECT_DIR=/data/projects

# ── Start API ─────────────────────────────────────────────────────────────────
CMD ["Rscript", "/app/run_api.R"]
