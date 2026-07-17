# EasyMultiProfiler Web v7.0.0 — Release Notes

**Branch:** `v7.0.0`
**Repository:** https://github.com/xielab2017/EasyMultiProfiler-Web
**Date:** 2026-07-17

---

## 🎉 主题：**零依赖 1 行安装**

V7 的最大变化是**安装体验**——R / Python / git / EMP 不再是用户的负担。

### 改了什么

| 步骤 | V6 | V7 |
|------|----|----|
| 1. 装 git | 用户手动 | 脚本自动 brew / apt / winget / 直接下载 exe |
| 2. 装 python3 | 用户手动 | 同上 |
| 3. 装 R ≥ 4.3.3 | 用户 `brew install --cask r` 或 `winget install RProject.R` | 脚本按 OS 自动选 CRAN .pkg / .exe / apt 源 |
| 4. 装 EMP | 用户 `remotes::install_github()` | 脚本优先 `install_local()`（仓库自带的 `R/`），回退到 GitHub 安装 |
| 5. 启后端+前端 | 用户 `bash webapp/scripts/start_local.sh` | 启动器同上（仍可单独调用） |

### 一行命令

```bash
# macOS / Linux
bash -c "$(curl -fsSL https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/v7.0.0/webapp/scripts/install_from_github.sh)"

# Windows (PowerShell)
irm https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/v7.0.0/webapp/scripts/install_from_github.ps1 | iex
```

### 新增脚本

`webapp/scripts/install/`
- `_platform.sh` —— OS / 架构检测 / 共享 helpers（sourced）
- `install_system_deps.sh` —— macOS brew / Debian apt / Fedora dnf
- `install_r.sh` —— 按 `uname -s / -m` 选 CRAN `.pkg` 或 Linux 仓库
- `install_system_deps.ps1` —— winget + 手动 fallback
- `install_r.ps1` —— CRAN `.exe` 静默安装，自动写机器 PATH

### 新增 / 重写脚本

- `webapp/scripts/bootstrap_and_start.sh` / `.ps1` —— 全新 V7 入口，先装系统依赖、再装 R、再装 EMP 包、再启动
- `webapp/scripts/install_from_github.sh` / `.ps1` —— 默认分支切到 `v7.0.0`，clone 后直接走 bootstrap
- `webapp/scripts/launch_emp_web.sh` / `.ps1` —— 日常启动也会自动补缺失的 R / python3
- `webapp/scripts/repair_and_start_windows.ps1` —— repair 时也会补 R

### 环境变量开关（高级 / CI）

| 变量 | 默认 | 含义 |
|------|------|------|
| `EMP_AUTO_INSTALL` | `1` | `=0` 时缺东西立即报错不安装 |
| `EMP_SKIP_DEPS`    | `0` | `=1` 跳过 git/python3 安装 |
| `EMP_SKIP_R_INSTALL` | `0` | `=1` 跳过 R 安装 |
| `EMP_R_VERSION`    | `4.4.2` | 指定要装的 R 版本 |
| `EMP_R_MIRROR`     | `https://cran.r-project.org` | CRAN 镜像 |
| `EMP_CRAN_MIRROR`  | `https://cloud.r-project.org` | install_runtime.R 用的 CRAN |

### 兼容 / 退路

- **保留旧脚本**：`Start-EMP-Web.bat` / `Repair-and-Start-EMP-Web.bat` / `Run-EMP-Web-Mac.command` / `Run-EMP-Web-Windows.bat` 行为已升级：缺 R 不再立刻报错，自动装。
- **Windows**：脚本用 PowerShell，依赖 .NET WebClient，无需额外模块。
- **macOS Apple Silicon**：默认装 `R-4.4.2-arm64.pkg`（macOS 11+）。
- **Windows arm64**：脚本自动选 `R-4.4.2-win-arm64.exe`（如 CRAN 提供）。
- **Linux**：Ubuntu/Debian 自动加 CRAN `jammy/focal` apt 源；RHEL/Fedora 用 CRAN 的 rpm 仓库。

### 文档

- `README.md` —— 顶部改写为 V7 流程
- `docs/INSTALL_MAC.md` / `INSTALL_WINDOWS.md` —— 全部重写
- 本文件 `CHANGELOG_V7.md`

---

## V6 全部能力保留（不缩水）

- ChIP-seq：BAM → MACS2/3 peaks → ChIPseeker 注释 → 与 RNA-seq / 蛋白组交叉分析
- RNA-seq GSEA + GO 细分：GO BP/CC/MF、KEGG、Reactome rank-based GSEA
- AI 结果解读 v2.1：CNS 级证据锚定写作模板与 LLM prompt
- Code Lab LLM：多模型自动回退 + 本地规则优化兜底
- 可视化增强：热图尺寸可调、PCA/PCoA 防出框 publication 主题
- 多组学导入 + Vector PDF + 中文 UI + ChIP-seq 直接传 pre-called peaks
- 16S / RNA-seq / Clinical / Metabolomics / Microbiome 同时加载示例数据

---

## Upgrade from v6.x

1. 拉取分支 `v7.0.0` 或重新运行上面的一行命令
2. 首次会自动装 R + EMP；后续 `bash webapp/scripts/launch_emp_web.sh` 即可
3. 浏览器硬刷新（清除旧 JS 缓存）

## Install from this branch

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/v7.0.0/webapp/scripts/install_from_github.sh)"
```

```powershell
irm https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/v7.0.0/webapp/scripts/install_from_github.ps1 | iex
```