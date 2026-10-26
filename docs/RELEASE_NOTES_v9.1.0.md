# EasyMultiProfiler Web v9.1.0 发布说明

**版本**：9.1.0（上一版本 9.0.4）
**主题**：多地区语言全面本地化 + Windows / macOS / Linux 平台自动识别 + 分析能力 A–D 提升

---

## 1. 语言：按 IP 自动识别地区，整系统多语言

### 支持的界面语言（11 种）

简体中文（zh）、繁体中文（zh-TW）、English（en）、日本語（ja）、한국어（ko）、العربية（ar）、Español（es）、Français（fr）、Deutsch（de）、Português（pt）、Русский（ru）。

### 自动识别链（手动选择永远优先）

1. 用户在界面右上手动选择的语言（保存在浏览器本地，优先于一切自动判断）
2. **IP 归属地**：前端通过 IP 服务取得国家代码，后端 `/api/locale/negotiate` 也支持 `CF-IPCountry` / `X-Geo-Country` 请求头，按国家映射语言（例如 JP → 日本語，KR → 한국어，SA/AE 等 → العربية，TW/HK/MO → 繁体中文）
3. 浏览器语言（`navigator.language` / `Accept-Language`）
4. 产品默认：简体中文

### 全面转化范围

- 顶部语言切换改为「自动」按钮 + 全部语言下拉选择，不再只有中/英两档
- 导航、页面标题、ChIP 向导、字号与语言控件、常用操作、组学名称、页脚、AI 解读按钮等**核心文案**已提供全部 11 种语言
- 阿拉伯语自动切换整页 RTL（`dir="rtl"`）布局，`<html lang>` 写入正确的 BCP-47 代码
- 后端新增本地化消息目录（质控警告、报告标题等，含 zh/en/ja/ko/ar），并提供 R 出图字体规则（CJK 与阿拉伯文字形需显式字体族，否则图内文字会变方块，见 `docs/I18N_PLATFORM_v910.md`）
- 日期与数字的地区格式由浏览器 `Intl` 按所选语言处理

### 诚实的范围说明

- 本版完成的是**核心文案集**的全面转化。各语言的长尾文案（个别页面的低频提示、教学长文等）尚未逐条翻译，未翻译的键按 `当前语言 -> English -> 简体中文 -> 键名` 的顺序回退显示，不会出现空白或报错。后续版本将按语言逐批补齐长尾文案。
- **本地单机运行的注意事项**：在本机以 `127.0.0.1` 打开时，IP 识别取到的是这台机器的公网出口地区；通过局域网 / Tailscale 访问时，识别的是访问者一侧的地区。识别结果不符合预期时，手动切换即可覆盖，且会被保存。
- 部分较早的界面模块内部仍按「中文 / 非中文」二分处理细节（例如个别分隔符），不影响核心流程，后续统一。

---

## 2. 平台：自动识别 Windows / macOS / Linux

- 新增统一平台检测契约：`webapp/scripts/detect_platform.sh`（macOS / Linux / WSL）与 `webapp/scripts/detect_platform.ps1`（Windows）输出同一 JSON 结构：`{os, arch, distro, r_version, python_version, git_version}`
- 后端新增 `GET /api/system/info`：返回操作系统（windows / macos / linux）、架构（含是否为 ARM）、系统详情、R 版本与 EMP 版本，便于支持与排障
- 新增 Linux 根目录启动 / 停止入口：`Start-EMP-Web-Linux.sh`、`Stop-EMP-Web-Linux.sh`，与 Mac `.command`、Windows `.bat` 对等
- 安装与启动脚本中仍写着旧版本号（v7）的用户可见横幅已统一为 v9.1.0

### 平台矩阵（本版验证范围）

| 平台 | 安装入口 | 启动 | 停止 | 平台检测 |
|------|----------|------|------|----------|
| Windows 10/11 x64 | `install.cmd` / PowerShell 一行安装 | `Run-EMP-Web-Windows.bat` | `Stop-EMP-Web-Windows.bat` | `detect_platform.ps1` |
| macOS（Intel / Apple Silicon） | `install.sh` / bash 一行安装 | `Run-EMP-Web-Mac.command` | `Stop-EMP-Web-Mac.command` | `detect_platform.sh` |
| Linux（Ubuntu 等） | `install.sh` / bash 一行安装 | `Start-EMP-Web-Linux.sh` | `Stop-EMP-Web-Linux.sh` | `detect_platform.sh` |
| WSL | `install.sh` | 同 Linux | 同 Linux | 识别为 windows / WSL |

---

## 3. 分析功能提升（A–D，均为后端新增助手，不改变既有分析行为）

- **A 严谨性质控** `helpers/qc_rigor.R`：`emp_qc_rigor()` 对特征 x 样本矩阵做缺失（整体与逐样本/逐特征）、零方差与近零方差特征、批次 x 分组混杂（卡方 + Cramer's V）、主成分与批次/分组关联（lm R²）检查，返回稳定警告码（如 `HIGH_MISSINGNESS`、`BATCH_GROUP_CONFOUNDING`、`BATCH_PC_ASSOCIATION`）。**只报告，不删数据、不插补**，符合本项目的严谨规范。
- **B 性能与可恢复** `helpers/run_pipeline_cache.R`：确定性步骤缓存键（md5）、RDS 步骤缓存（命中时不重复计算）、跨平台并行 `lapply`（Unix 用 fork，Windows 用 PSOCK 集群，由 `EMP_PARALLEL_WORKERS` 控制）、断点续跑计划（按 manifest 跳过已完成步骤）。与既有 `jobs.R` 的异步任务与进度配合使用。
- **C 多组学整合与 ChIP-RNA** `helpers/multiomics_joint.R`：跨组学 Spearman 相关网络（BH 校正）、多组学联合因子分解（SVD）、ChIP peak 到基因的链接表（含到 TSS 距离与可选的样本级信号-表达相关）。样本均按列名匹配，未匹配样本不静默混入。
- **D 可复现报告** `helpers/repro_report.R`：每次运行可生成复现清单（EMP 版本、平台、R 版本、关键包版本、会话信息、界面语言），并写出 `manifest.json` 与按界面语言标题的 `REPORT.md`。未安装的包如实记录为未安装，不编造版本。

后端同时新增 `GET /api/locale/negotiate`（语言协商）与 `GET /api/system/info`（平台信息）两个只读端点。

---

## 4. 版本统一

- `DESCRIPTION`、后端各助手的版本默认值、前端标题/徽章/指南文案、安装脚本与中英文 README 中的版本号已统一由 9.0.4 升至 **9.1.0**
- 历史文档（CHANGELOG_V5 / V7、RELEASE_NOTES_v9.0.4）保持原文，不做改写

## 升级方法

与以往相同：重新运行一行安装命令（会自动拉取最新代码并复检依赖），或在已 clone 的仓库执行 `git pull` 后重启服务。旧的界面语言设置（auto / zh / en）会被新版自动识别；新增语言直接在右上语言下拉中选择。

## 已知限制

- 长尾 UI 文案的多语言覆盖分批推进中，未覆盖部分按上述回退链显示英文或中文
- `detect_platform.ps1` 未在真实 Windows 上实测（开发环境为 Linux），脚本保持保守写法，欢迎在 Windows 上反馈检测结果
- 新增 R 助手为基础 R 实现（仅 `repro_report` 用到已在用的 jsonlite），未新增包依赖
