# EasyMultiProfiler Web v9.3.0

Date: 2026-11-08. Source release on `main`.

## 中文

本版整合 v9.2.0 之后的 Agent、数据下载、后台任务、结果快照、分析与可视化改进，并统一版本和界面。

- **Agent 对话**：单一跨页面对话窗口读取注册页面上下文；支持模型选择、图片上传/粘贴、PDF 附件、输入发送后清空、自动跟随新消息和面板宽度调整。Agent 模式记忆选择，Plan 可选；需要样本关系或设计确认时显示交互项，再继续已授权任务。
- **模型配置**：独立“模型与 API”页面；服务/模型配置按浏览器保存，支持 MiniMax 中国/国际站及兼容协议。思考深度按模型能力开放并保存，服务端校验实际参数。移除不可用的网页账号连接入口。
- **数据发现与下载**：论文/PDF、数据库编号和关键词统一发现入口；改进多论文项目、GEO 与 PRIDE 处理矩阵下载、来源证据、样本精确匹配及工作台交接。其他数据库链接不代表已实现托管下载，不会强制只接受 GSE。
- **工作台与后台任务**：导入、类型与样本审查、可组合步骤、异步执行、进度和结果记录；不适用的输入不能静默按原始计数处理。任务面板可拖动、清理已结束记录；清理记录不等于删除原始输入。
- **分析与出图**：增加 GSEA、GO/KEGG 富集气泡图与运行富集曲线、按组学筛选的结果来源、保存分析快照和扩展图型。PCA 的协方差椭圆是组内离散范围，不冒充组均值置信区间；不足三个非共线点不伪造椭圆。模型解读可附带实际结果图。
- **界面统一**：移除“课程”“AI 提示词”导航入口；顶部与左侧共用名称、顺序和组学可见范围。11 种语言统一目录；保留原始数据和历史对话原文。工作台/整合页统一表单，导出卡片按钮等高并底部对齐。
- **版本统一**：DESCRIPTION 为版本源；Web 元数据、可见版本文案、中英文 README、启动器和打包名称同步。运行 `python3 webapp/scripts/sync_app_version.py`，用 `--check` 检查遗漏。

## English

This source release combines page-aware Agent chat, optional planning and review, attachments and model-specific thinking depth, public matrix discovery/download handoffs, multi-study projects, asynchronous tasks and analysis snapshots. It adds enrichment/GSEA plotting and omics-specific visualization sources, synchronizes navigation and 11 UI locales, and standardizes forms and export cards. DESCRIPTION is the release-version source; synchronize generated labels before committing.

## Validation / 验证

- Node: 132 tests passed.
- Python: 274 tests completed, 1 skipped, no failures.
- R: ordination ellipse boundaries, GSEA full-rank/input contracts, one-click RNA-seq/16S stage fixtures, enrichment scientific contracts, real PNG/PDF/SVG exports, and the figure-method bridge checks passed. No new external GO/KEGG/GSEA network inference was claimed by these fixture tests. The bridge test uses a portable fixture by default; an explicitly configured methods library can be tested through `EMP_FIGURE_METHODS_ROOT`.
- Release-label consistency check, Bash syntax, backend R parsing and staged whitespace checks passed.
- Prior local browser checks: 11 locales × 16 navigation entries; matched sidebar/top ordering; aligned 48 px export buttons; 42 px workbench controls; MiniMax-M3.1 effort forwarding and persistence. See [UI acceptance](NAVIGATION_I18N_AND_THINKING_20261108.md) and [Agent-flow acceptance](AGENT_FLOW_ACCEPTANCE_20261108.md) for tested scope and evidence.

## Limits / 边界

This is a source update, not a new binary installer bundle or a public deployment. Native Windows/Linux installation, all provider accounts, every repository download route and every possible scientific workflow have not been exhaustively tested. Language catalogs have automated coverage/placeholder checks but still benefit from native-language review. Real-provider checks cover configured MiniMax calls; provider parameter contracts do not prove other services connect successfully.

The count-workbench execution adapter requires verified raw counts and an independent-sample design; it does not silently fit paired, repeated-measure or batch-adjusted models. Multi-omics integration requires appropriate inputs, preprocessing and sample correspondence; arbitrary cross-study matrices are not concatenated automatically. Existing installed R package versions are reported separately from the Web release version.

Reproduce the release checks:

```bash
python3 webapp/scripts/sync_app_version.py --check
node --test webapp/tests/*.mjs
PYTHONPATH=webapp/tests:webapp/scripts python3 -m unittest discover -s webapp/tests -p 'test_*.py'
Rscript --vanilla webapp/tests/test_ordination_ellipse.R
Rscript --vanilla webapp/tests/test_gsea_analysis.R
Rscript --vanilla webapp/tests/test_figure_method_rules.R
```

No local API credentials, runtime configuration, downloaded matrices, caches or duplicate working-copy files are part of this release.
