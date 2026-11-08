# Agent 流程实测记录 — 2026-11-08

本记录对应当前本地工作区。浏览器真实调用模型为 MiniMax-M3（中国站、Anthropic 兼容协议），不代表其他供应商已通过实测。页面服务为 127.0.0.1:8080，R API 为 8003，矩阵与 Agent 服务为 8082。没有推送或发布这些工作区改动。

## 实际执行结果

| 链路 | 实测结果 | 可核对凭据 |
|---|---|---|
| Agent 下载公开 GEO → 工作台 | 通过；复用已完成的 GSE305056 计数文件，自动导入 21,652 特征、30 样本 | 下载任务 `1e706972-10e1-419d-a26f-a9b8fdc4b50e` |
| GEO 样本信息匹配 | 通过；按 Library name 精确匹配 30/30，未按字母猜分组 | 本地 `GSE305056-annotations.json` |
| 真实数据的设计确认 | 弹出关系/分组/来源核对；发现 batch 字段含时间条件且缺失 10 项，明确警告 | 未确认真实数据独立性、未运行该研究差异分析 |
| PRIDE 公开蛋白矩阵下载 | 通过；实际下载 PXD067973 的 report.pg_matrix.tsv，2,486,063 bytes | 任务 `3d3d8b03-7da9-4ca0-9b48-1a4d3984e082`；SHA256 `943e543bcd3693fadfb6d7bc44c2080e87f0d1587e02af61ba7b2dab97e5e716` |
| 计数工作台分析 | 通过；6 个独立合成样本、200 特征，DESeq2/edgeR 各 200 行结果、PCA 和热图 | `20261108130855.993-dtsbi681` |
| 主数据页上传 → Agent 导入 | 通过；实际浏览器上传矩阵和 metadata，创建 SYNTHETIC_UI_20261108 | 6 样本、200 特征；Group 和 SubjectID 正确识别 |
| Agent → 主分析页 DESeq2 | 通过；实际完成异步任务 | `20261108133742.175-p3bx87gv` |
| Agent → 降维 PCA | 通过；核实任务类型及 method=PCA，6 行坐标 | `20261108141219.217-pvavm7kh` |
| 保存 PCA 坐标 → 散点图 | 通过；scat-ordination=emp，Group 着色，PC1/PC2；实际下载 PDF | scatter_main_SYNTHETIC_UI_20261108.pdf |
| Agent → 火山图 | 通过；从已保存差异结果生成，无重新拟合 | volcano_SYNTHETIC_UI_20261108.pdf |
| Agent → 热图 | 通过；Group、Top20、8×6 英寸均核对页面值及实际图片 | agent-heatmap.jpg |
| AI 图像解读 | 通过；当前结果图作为 PNG 附件进入真实模型请求，对话显示缩略图，模型识别散点/解释率/椭圆 | vision-response.txt；不是页面截图或原始矩阵 |
| 可选 Plan | 通过；先弹出计划卡片，确认前不执行，点击确认后继续填写及出图 | plan-confirmation.jpg |
| 中英文切换 | 图型目录、图型按钮、样式选项实际切换并切回中文 | 方法 ID 与分析数据不改变 |

测试输入是 seed=20261108 生成的合成数据，名称 SyntheticGene 不代表真实基因。未将合成数据做 GO/KEGG 生物学解释。证据与输入位于 `.local_run/verification/agent-ui/`，该目录是本机验证产物。

## 修复的问题

- 修复标签切换后旧面板残留 active 类的问题；隐藏面板即使残留 active 类也不暴露给 Agent。Agent 只可读取/填写当前步骤的允许字段，不能把其他标签的“运行”当作当前请求。
- PCA 请求与差异分析按钮不匹配时拒绝提交；要求保存坐标时拒绝改为 assay_pca。
- 后台任务完成后可继续原请求；有新用户输入、实验变化、失败或取消时不擅自重跑。
- 页面操作工具交接后立即由 UI 执行，不空转消耗模型工具轮数；已完成动作与任务回执去重。
- “AI 解读结果”附带当前结果图、绘图参数、图旁统计文字；普通可视化对话中请求解读当前图也会附图。图像限制 1800 像素长边、5 MiB，仅捕获结果图，不捕获整页。
- 只解读时不向模型提供执行工具，也不触发 Plan 确认。
- PCA 内置协方差椭圆恢复为至少 3 个非共线点；少于 3 个或奇异协方差不伪造椭圆。标注 95% 离散椭圆不是组均值置信区间，小样本估计不稳定。
- 保留差异统计的完整小数精度，不把很小的非零 FDR 四舍五入为 0。

## 自动检查与边界

```sh
node --test webapp/tests/test_*.mjs
PYTHONPATH=webapp/tests:webapp/scripts .local_run/metadata_venv/bin/python -m unittest test_agent_adapter test_agent_attachments test_matrix_downloads test_matrix_api test_matrix_annotations test_omics_workbench
Rscript webapp/tests/test_ordination_ellipse.R
```

当前通过 125 个 Node 测试；Python 106 个测试，1 个可选依赖测试跳过；R 椭圆三样本/两样本/共线边界检查通过。

计数工作台仍只执行独立设计，不支持配对、重复测量或批次调整模型。确认窗口能记录这些设计并提示后续处理，不会将其假装成独立样本。多组学联合分析、全部数据库、全部模型和所有出图类型没有在本轮穷举验证。
