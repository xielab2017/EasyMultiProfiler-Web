# EasyMultiProfiler Web v7.0.0 — Release Notes

> **Headline:** From a fresh GitHub clone to a running web app in **one
> command line**. The installer auto-detects your OS, installs
> `git` / `python3` / `R ≥ 4.3.3` if missing, builds the EMP package
> and its 50+ CRAN / Bioconductor dependencies, then starts the API
> + web UI and opens the browser.

---

## 🚀 What's new in v7

### Zero-dependency one-line install

| Step | v6 | v7 |
|------|----|----|
| Install git | manual | auto (brew / apt / winget / direct download) |
| Install python3 | manual | auto (same as above) |
| Install R ≥ 4.3.3 | manual `brew install --cask r` / `winget install RProject.R` | auto — picks the right CRAN `.pkg` / `.exe` / apt source for your OS and arch |
| Install EMP | `remotes::install_github("...")` | auto — installs from the local checkout when present, falls back to GitHub |
| Start backend + frontend | `bash webapp/scripts/start_local.sh` | the same launcher now auto-bootstraps R if it was missing |

### One-line install (macOS / Linux terminal)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/v7.0.0/webapp/scripts/install_from_github.sh)"
```

### One-line install (Windows PowerShell)

```powershell
irm https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/v7.0.0/webapp/scripts/install_from_github.ps1 | iex
```

### Windows double-click (.cmd / Explorer)

`install.cmd` in the repo root now stays open after the bootstrap so
you can see the log instead of the CMD window flashing closed. Same
for `install.sh` from a Terminal.app double-click.

For users who already cloned:

```bash
bash install.sh                                       # macOS / Linux
powershell -File webapp\scripts\bootstrap_and_start.ps1   # Windows PowerShell
install.cmd                                           # Windows CMD / double-click
```

### New V7 scripts

`webapp/scripts/install/`
- `_platform.sh` — OS / arch detection, shared helpers (sourced)
- `install_system_deps.{sh,ps1}` — git / python3 install (brew / apt / dnf / winget)
- `install_r.{sh,ps1}` — R install (CRAN `.pkg` / `.exe` / apt repo, auto arch)

Cross-shell entry points (auto-detect host OS, forward .ps1 ↔ .sh
when invoked on a non-native PowerShell):
- `webapp/scripts/install_from_github.{sh,ps1}` — clone + bootstrap
- `webapp/scripts/bootstrap_and_start.{sh,ps1}` — full chain
- `webapp/scripts/launch_emp_web.{sh,ps1}` — daily launcher with auto-repair
- `webapp/scripts/repair_and_start_windows.ps1` — force re-install

### Auto-detect cross-shell forwarding (v7.0.1)

Every installer entry probes `$IsWindows` / `$IsLinux` / `$IsMacOS`
and falls back to a manual platform check on Windows PowerShell 5.x
where those automatic variables are absent. Parameter passing uses
environment variables (`$EMP_REPO_URL` / `$EMP_TARGET_DIR` /
`$EMP_BRANCH`) — positional arguments through `bash -s --` from
PowerShell have unreliable quoting across pwsh versions, env vars
survive cleanly.

### Environment variables (advanced / CI)

| Variable | Default | Meaning |
|----------|---------|---------|
| `EMP_AUTO_INSTALL` | `1` | `=0` makes the installer abort when anything is missing instead of installing it |
| `EMP_SKIP_DEPS` | `0` | `=1` skips git / python3 install |
| `EMP_SKIP_R_INSTALL` | `0` | `=1` skips R install |
| `EMP_R_VERSION` | `4.4.2` | pin R release |
| `EMP_R_MIRROR` | `https://cran.r-project.org` | CRAN mirror for the R installer |
| `EMP_CRAN_MIRROR` | `https://cloud.r-project.org` | CRAN mirror for `install_runtime.R` |
| `EMP_BIOC_MIRROR` | `https://bioconductor.org` | Bioconductor mirror |
| `EMP_BIOC_VERSION` | auto (from R) | pin Bioc release |
| `EMPI_RSCRIPT` | _unset_ | full path to `Rscript.exe` (used by `start_local_windows.ps1`) |
| `EMPI_PYTHON` | _unset_ | full path to `python.exe` (used by the static web server) |

### v7.0.2 reliability fixes (just before this release)

- `install_runtime.R` now reads `DESCRIPTION` and installs **all
  58 direct Imports** (the previous hard-coded list only covered 28
  CRAN + 19 Bioc, which left `metap` / `fracdiff` / `gdtools` /
  `fru` / `multtest` un-installed on first run and aborted the
  EMP install). Adds `--with-suggests` / `--no-emp` / `--fail-fast`
  flags.
- `bootstrap_and_start.ps1` re-reads the machine `PATH` after each
  installer step (winget / R installer register PATH for *future*
  sessions; the current PS session must refresh).
- `install.cmd` keeps the CMD window open after the bootstrap so
  Windows users actually see the result of double-clicking it.
- `docs/TECHNICAL_MODE_V6.svg` redrawn to reflect the V7 install
  chain and to group 16S / Metagenomics under a single "Microbiome
  family" badge.

---

## ✅ What v6 capabilities we kept (no regression)

- ChIP-seq: BAM → MACS2/3 peaks → ChIPseeker annotation → cross-omics
  with RNA-seq / proteomics
- RNA-seq GSEA + GO subtypes: GO BP / CC / MF, KEGG, Reactome rank-based GSEA
- AI interpretation v2.1: CNS-grade evidence-anchored writing templates
  and LLM prompts
- Code Lab LLM: multi-model auto-fallback + local rules-based repair
- Visualization improvements: heatmap size adjustable, PCA / PCoA
  publication theme that doesn't get clipped, vector PDF export
- Multi-omics import + Chinese UI + ChIP-seq can take pre-called peaks
  directly
- 16S / RNA-seq / Clinical / Metabolomics / Microbiome can be loaded
  with example data at the same time

---

## Upgrade from v6.x

1. `git pull` (or re-clone)
2. Run the one-line install for your shell, or `bash install.sh` /
   `install.cmd` from inside the repo.
3. Hard-refresh the browser tab to clear the old JS cache.

## Install from this tag

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/v7.0.0/webapp/scripts/install_from_github.sh)"
```

```powershell
irm https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/v7.0.0/webapp/scripts/install_from_github.ps1 | iex
```

## Compatibility

- macOS 11+ (Apple Silicon and Intel)
- Windows 10 / 11 (PowerShell 5.1+; PowerShell 7 supported for cross-shell forward)
- Ubuntu 20.04+ / Debian 11+ (apt auto-add CRAN source)
- Fedora 38+ / RHEL 9+ (dnf auto-add CRAN repo)
- WSL2 (Ubuntu)
- Git-Bash on Windows
