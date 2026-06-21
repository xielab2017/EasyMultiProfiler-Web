# EasyMultiProfiler Web v5.0.1

**多组学下游分析与可视化 — 浏览器版（R 后端 + 静态前端）**

![](https://img.shields.io/badge/version-5.0.1-blue)
![](https://img.shields.io/badge/R%20%3E%3D-4.3.3-brightgreen)
![](https://img.shields.io/badge/macOS%20%7C%20Windows-Web%20install-brightgreen)

面向学生与零基础用户：**无需事先安装 EMP R 包**，按平台运行一键脚本即可（会自动安装 R 依赖并启动网页）。

---

## 三种使用方式（选一条即可）

| 方式 | 适合谁 | 安装入口 | 详细文档 |
|------|--------|----------|----------|
| **macOS Web** | Mac 用户、课程上机 | 终端一行命令 或 双击 `Run-EMP-Web-Mac.command` | [docs/INSTALL_MAC.md](docs/INSTALL_MAC.md) |
| **Windows Web** | Windows 10/11 用户 | PowerShell 一行命令 或 `.bat` 双击 | [docs/INSTALL_WINDOWS.md](docs/INSTALL_WINDOWS.md) |
| **仅 R 包** | 已有 RStudio 的研究者 | R 控制台 `pak::pak(...)` | 下方「R 包 only」 |

> **Mac 与 Windows 使用不同的脚本与命令，请勿混用。**  
> 打开网页后，左侧 **Guide** 页有完整分平台说明（v5.0.1 内置指南）。

---

## 快速安装

### macOS（推荐）

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/v5.0.1/webapp/scripts/install_from_github.sh)"
```

或克隆/解压仓库后双击 **`Run-EMP-Web-Mac.command`**。

### Windows（推荐）

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
irm https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/v5.0.1/webapp/scripts/install_from_github.ps1 | iex
```

或解压后：**首次**双击 `Repair-and-Start-EMP-Web.bat`，**日常**双击 `Start-EMP-Web.bat`。

### 成功标志

- 网页：**http://127.0.0.1:8080**（默认 **Course** 页）  
- API：**http://127.0.0.1:8000/api/health** → `"status":"ok"`

---

## v5.0.1 亮点

- **ChIP-seq**：BAM → MACS2/3 peaks → ChIPseeker 注释 → 与 RNA-seq / 蛋白组交叉分析  
- **RNA-seq GSEA + GO 细分**：GO BP/CC/MF、KEGG、Reactome rank-based GSEA  
- **AI 结果解读 v2.1**：CNS 级证据锚定写作模板与 LLM prompt  
- **Code Lab LLM**：多模型自动回退 + 本地规则优化兜底  
- **可视化增强**：热图尺寸可调、PCA/PCoA 防出框 publication 主题  
- **分平台安装 + Guide 页 + i18n + Run All + Course 教学**（继承 v5.0.0 全部能力）  

完整用户指南：[docs/USER_GUIDE_V5.md](docs/USER_GUIDE_V5.md)

---

## 网页内推荐流程

```
Course → Data（或 demo）→ Prepare（推荐参数）→ Analyze → Run All → Visualize → Export
```

没有自己的数据？Course 或 Data 页 **一键加载示例数据** 即可。

---

## 仅 R 包（不使用 Web UI）

```r
if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak")
pak::pak("liubingdong/EasyMultiProfiler")
library(EasyMultiProfiler)
```

教程：https://liubingdong.github.io/EasyMultiProfiler_tutorial/

---

## 架构

| 组件 | 路径 |
|------|------|
| R API（Plumber） | `webapp/backend` |
| 前端 UI | `webapp/frontend` |
| 安装脚本 | `webapp/scripts` |
| 测试数据 | `tests/` |

---

## 开发与回归

```bash
bash webapp/scripts/check_prerequisites.sh
bash webapp/scripts/launch_emp_web.sh          # 日常
bash webapp/scripts/launch_emp_web.sh --repair # 强制重装依赖
Rscript webapp/scripts/smoke_v5_pipeline.R     # 16S + RNA-seq + Clinical
```

工作流文档：[webapp/V5_AGENT_WORKFLOW.md](webapp/V5_AGENT_WORKFLOW.md)

---

## 关于 EasyMultiProfiler R 包

EasyMultiProfiler 提供微生物组、转录组、代谢组等多组学下游分析（过滤、差异、富集、WGCNA、可视化等）。  
本仓库 **Web 版** 在 R 包之上提供零基础安装、Course 教学与 AI 增强体验。

原 R 包说明与示例图见 `tutorial_related/` 及 [官网教程](http://easymultiprofiler.xielab.net)。
