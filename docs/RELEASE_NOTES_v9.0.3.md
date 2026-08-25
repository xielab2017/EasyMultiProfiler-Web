# Release Notes — v9.0.3

**Branch:** `main`  
**Repo:** https://github.com/xielab2017/EasyMultiProfiler-Web  
**Internal version:** `9.0.3`  
**Status:** Official GitHub `main` release line (supersedes V9 Education preview branches for default install).

## Summary

- Promotes the Education / V9 web stack to **GitHub `main`** with internal version **9.0.3**.
- One-line installers default to branch `main` (macOS/Linux `.sh`, Windows `.ps1`).
- UI / API / GitHub sync report `9.0.3` via `EMP_WEB_VERSION` (default `9.0.3`).
- Continues classroom homework sync to `xielab2017/Bioinformatics_homework_XieLiwei` when configured.
- Includes ChIP-seq peak ops / recipe packs, RNA–ChIP co-analysis bridges, and i18n locale switching from the V9 line.

## Install

| Shell | Command |
|------|------|
| macOS / Linux | `bash -c "$(curl -fsSL https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/main/webapp/scripts/install_from_github.sh)"` |
| Windows PowerShell | `irm https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/main/webapp/scripts/install_from_github.ps1 \| iex` |

```bash
git clone -b main https://github.com/xielab2017/EasyMultiProfiler-Web.git
cd EasyMultiProfiler-Web
bash install.sh
```

## Env (classroom)

| Variable | Purpose |
|---|---|
| `EMP_WEB_VERSION` | Override displayed / synced version (default `9.0.3`) |
| `EMP_CLASS_HOMEWORK_REPO` | Class repo URL |
| `EMP_CLASS_GITHUB_TOKEN` | Optional shared PAT with push to class repo |
| `EMP_GITHUB_SECRET_KEY` | Encrypts stored PATs |

## Prior preview branches

Historical education preview tags/branches (`V9.0.0_Education`, `V9.0.1_Education`) remain on the remote for reference; new installs should use **`main` @ 9.0.3**.
