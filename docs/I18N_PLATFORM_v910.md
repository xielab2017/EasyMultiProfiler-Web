# v9.1.0 开发者文档：本地化架构与平台检测契约

面向后续维护者：如何新增一种语言、RTL 与 R 出图字体的规则、三平台检测的统一契约、以及分析助手 A–D 的 API。

---

## 1. Locale 架构（前端）

### 文件分工

| 文件 | 职责 |
|------|------|
| `webapp/frontend/js/i18n_geo.js` | 纯函数模块，无 DOM 依赖，可在 Node 中单测。`SUPPORTED_LOCALES`、`RTL_LOCALES`、`COUNTRY_TO_LOCALE`、`localeForCountry()`、`localeForBrowserLang()`、`isRtl()`、`bcp47()`、`localeDisplayName()` |
| `webapp/frontend/js/i18n_extra_locales.js` | `EXTRA_LOCALES`：zh-TW / ja / ko / ar / es / fr / de / pt / ru 的**核心键集**翻译 |
| `webapp/frontend/js/locale.js` | 运行时：合并 `I18N_CORE`（zh/en）+ `I18N_CATALOG`（zh/en）+ `EXTRA_LOCALES`，负责解析、持久化与 DOM 应用 |
| `webapp/frontend/js/i18n_catalog.js` | zh/en 长尾目录 |
| `webapp/frontend/js/ui_dom_i18n.js`、`i18n_pages.js` | 通过 `t()` 把目录应用到静态 DOM 与各页面 |

### 解析与回退

- 模式（localStorage `emp_ui_locale_mode`）：`auto` 或任一受支持语言代码；解析结果存 `emp_ui_locale_resolved`。
- `auto` 解析链：IP 国家（`fetchIpCountry()`，ipapi.co 失败时回退 ipwho.is）-> `localeForCountry()` -> 浏览器语言 `localeForBrowserLang()` -> 默认 `zh`。
- `getLocale()` 返回**真实解析代码**（如 `ja`、`zh-TW`），不再是 zh/en 二值。
- `t(key)` 回退链：**当前语言 -> en -> zh -> 键名**。新增语言只翻核心键、长尾靠回退，是既定策略，不是缺陷。
- `applyDocumentLocale()`：设置 `<html lang>`（`bcp47()`：zh -> `zh-CN`）、`<html dir>`（阿拉伯语 `rtl`，其余 `ltr`）、`data-emp-locale`，并同步语言下拉的选中值。
- 已知兼容点：`app.js`、`guide.js`、`teaching.js` 中仍有按 `getLocale() === "zh"` 的二分判断（中文取中文标签、其余取英文标签）与个别 `=== "en"` 的分隔符判断。新增语言在这些细节处走英文分支，属于已知行为，逐模块改造时再处理，不要为了统一而大面积改动这些文件。

### 如何新增一种语言（例如意大利语 it）

1. 在 `i18n_geo.js` 的 `SUPPORTED_LOCALES` 加入 `"it"`；在 `COUNTRY_TO_LOCALE` 加入 `IT: "it"` 等国家映射；`localeForBrowserLang()` 的前缀列表加入 `"it"`。
2. 在 `i18n_extra_locales.js` 的 `EXTRA_LOCALES` 加入 `it` 字典，键集与现有语言完全一致（核心键集见该文件头注释；用 `webapp/tests/test_v910_i18n_geo.mjs` 的核心键清单校验完整性）。
3. 在 `webapp/frontend/index.html` 的 `#locale-select` 加入 `<option value="it">Italiano</option>`（显示名用该语言的自称）。
4. 若为 RTL 语言：把代码加入 `RTL_LOCALES`，并检查布局在 `dir="rtl"` 下的表现。
5. 后端同步：在 `webapp/backend/helpers/i18n_locale.R` 的 `.EMP_SUPPORTED_LOCALES` 与 `.EMP_COUNTRY_LOCALE` 加入同样映射；后端消息目录 `.EMP_MSG` 可只补该语言的高频键，缺失自动回退英文。
6. 跑测试：`node webapp/tests/test_v910_i18n_geo.mjs`。

### RTL 规则

- 只有阿拉伯语（`ar`）在 `RTL_LOCALES` 中。`applyDocumentLocale()` 据此设置整页 `dir`。
- 新增 RTL 语言前，先在真实页面检查：侧边导航、表格、图表容器在镜像布局下不应溢出或遮挡；逻辑属性（margin-inline 等）优先于物理方向属性。

### R 出图字体规则

- 规则实现：`helpers/i18n_locale.R` 的 `emp_plot_font_family()`。
- ja -> `Noto Sans CJK JP`；ko -> `Noto Sans CJK KR`；zh -> `Noto Sans CJK SC`；zh-TW -> `Noto Sans CJK TC`；ar -> `Noto Sans Arabic`；其余 -> 通用 `sans`。
- 原因：多数图形设备对 CJK 与阿拉伯文字形没有默认字体回退，不指定字体族图内文字会渲染为方块。服务器缺失对应字体时，应安装 Noto CJK / Noto Sans Arabic，或接受设备回退并在报告中注明。

---

## 2. 平台检测契约

三端必须输出同一结构，前端、脚本与后端 `/api/system/info` 共用这套字段语义：

```json
{"os": "windows|macos|linux|unknown", "arch": "x86_64",
 "distro": "Ubuntu 24.04.5 LTS", "r_version": "4.4.0",
 "python_version": "3.12.3", "git_version": "2.43.0"}
```

| 实现 | 平台 | 说明 |
|------|------|------|
| `webapp/scripts/detect_platform.sh` | macOS / Linux / WSL / Git-Bash | `uname` + `/etc/os-release` + `/proc/version`（WSL 识别为 `windows` / distro `WSL`） |
| `webapp/scripts/detect_platform.ps1` | Windows | CIM 取系统说明，命令探测 Rscript / python / git，`ConvertTo-Json -Compress` 输出 |
| `helpers/platform_info.R` | 后端运行时 | `emp_detect_os()`：`.Platform$OS.type` 为 windows，其余按 `Sys.info()` 的 Darwin 区分 macos / linux；`emp_platform_info()` 另返回 `os_detail`、`is_arm` |

- 找不到的工具（R / Python / Git）一律输出空字符串，不报错中断。
- 根目录启动入口三平台对等：Windows `.bat`、macOS `.command`、Linux `Start-EMP-Web-Linux.sh` / `Stop-EMP-Web-Linux.sh`（内部委托 `webapp/scripts/start_local.sh` / `stop_local.sh`）。

---

## 3. 分析助手 API（后端，基础 R；仅 repro 用 jsonlite）

### A. 严谨性质控 `helpers/qc_rigor.R`

```r
emp_qc_rigor(mat, meta = NULL, group_col = NULL, batch_col = NULL)
# -> list(checks, warnings, summary)
```

- `mat`：特征 x 样本数值矩阵。检查缺失（整体/逐样本/逐特征）、零方差与近零方差特征；给出 `meta` 且列存在时做批次 x 分组卡方 + Cramer's V 混杂检查，以及 PC1–PC3 与批次/分组的 lm R² 关联（PCA 只用完整、无缺失、非常量特征，并在结果中注明）。
- 警告码：`HIGH_MISSINGNESS`（整体缺失 > 20%）、`BATCH_GROUP_CONFOUNDING`（V > 0.3 且 p < 0.05）、`BATCH_PC_ASSOCIATION`（PC1/PC2 的批次 R² > 0.3）。
- **只报告，绝不删数据或插补**；所有可选步骤均有 `tryCatch` 保护。

### B. 缓存 / 并行 / 续跑 `helpers/run_pipeline_cache.R`

```r
emp_step_key(step_name, key_parts)                       # 确定性 md5 键
emp_run_cached_step(name, key_parts, fn, cache_dir)      # -> list(value, cached, key, file)
emp_lapply_parallel(X, FUN)                              # EMP_PARALLEL_WORKERS 控制并行度
emp_resume_plan(steps, manifest)                         # -> 未完成步骤（保持原顺序）
```

- Windows 并行走 PSOCK 集群并保证退出时关闭；Unix 走 `mclapply`；工人數 <= 1 时退化为普通 `lapply`。
- 与 `helpers/jobs.R` 的关系：jobs 管异步任务与进度，本文件管单步缓存与续跑计划，两者正交。

### C. 多组学联合 `helpers/multiomics_joint.R`

```r
emp_cross_omics_network(mat_a, mat_b, fdr = 0.05, cor_min = 0.5)
# -> data.frame(from, to, cor, p_adj)，Spearman + BH，p 用 t 近似（已在函数文档注明）
emp_joint_factor(blocks, n_factors = 2)
# -> list(scores, loadings, variance_explained, samples)，块内行标准化后 SVD
emp_chip_rna_links(peaks, gene_expr = NULL, max_dist = 50000)
# -> data.frame(peak_id, chr, gene, distance_to_tss, within_max_dist, expr_cor, note)
```

- 样本一律按列名交集匹配；交集小于阈值时返回空结果或报错，不猜测对应关系。
- `emp_chip_rna_links()`：缺 `gene_tss` 列时距离为 NA 并写明原因，不编造坐标。

### D. 可复现报告 `helpers/repro_report.R`

```r
emp_repro_manifest(extra = list(), locale = "en")  # 版本/平台/R/包版本/会话信息清单
emp_write_repro_report(dir, manifest, locale)     # 写 manifest.json + REPORT.md
```

- 包版本只查固定集合（ggplot2、DESeq2、limma），未安装记 NA，不编造。
- `REPORT.md` 标题走 `emp_msg(locale, "report.title")` 本地化；正文结构固定为 Version / Platform / R / Packages / Notes。

### 新增端点（`webapp/backend/plumber.R`）

| 端点 | 说明 |
|------|------|
| `GET /api/system/info` | `emp_platform_info()` + `emp_version = "9.1.0"` |
| `GET /api/locale/negotiate` | 读 `CF-IPCountry` / `X-Geo-Country` 头与 `Accept-Language`，返回 `{locale, dir}`，协商规则见 `emp_negotiate_locale()`（国家 > 语言 > 默认 zh） |
