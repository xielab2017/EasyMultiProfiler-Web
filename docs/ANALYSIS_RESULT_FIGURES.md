# 分析页集成出图 / Integrated analysis figures

从「分析」进入降维、相关、聚类或标志物页，选择方法并运行。完成后自动保存本次结果并出图；同一方法重复运行也保留不同结果，可在「已保存分析」中选择。刷新来源不会重跑分析。修改「本图独立设置」后点击生成，只读取所选结果。

| 分析 | 方法 | 图形与语义 |
| --- | --- | --- |
| 降维 | PCA、PCoA、UMAP、t-SNE、MDS | 使用本次保存的坐标画散点图，可选坐标轴、保存的分组和样本标签；MDS 当前采用 PCoA |
| 相关 | Spearman、Pearson、Kendall | 相关系数热图；可切换阈值网络图，选择变量和显示数量 |
| 聚类 | Hierarchical、K-means、PAM | 保存的聚类树（仅层次法）、聚类输入的描述性 PCA 投影、样本归属图或各簇数量图 |
| 标志物 | Random Forest、LEfSe / ANCOM 的 RF 备用、LASSO、XGBoost | 按实际保存的分数绘制 Top N 横向条形图；LASSO 保留系数正负与对比方向，XGBoost 可选 Gain |

每类分析分别保存尺寸、cm / mm / inch / point 单位、字号、线宽及导出设置；可选自动参数配置或手动调整。初始完整画布分别为 120 × 100、180 × 160、180 × 140、180 × 160 mm。PNG 用于预览，PDF / SVG 用于矢量编辑；在 Illustrator 中按 100% 放置。下载还包括本图数据 CSV 与 MANIFEST。

MANIFEST 记录源结果 ID、源文件校验值、原始分析参数、可用的算法参数、保存时的软件版本及本次绘图参数。完整分析表保留在独立结果快照中；绘图 CSV 只包含实际展示部分。相关热图默认最多显示 24 个变量，可改为 2–80 个或指定变量；未保存的系数保持 NA，不凭空补成 0 或 1。网络圆形位置只是布局，不代表生物学距离。

t-SNE 使用 Rtsne，UMAP 使用 umap 的 R 实现，缺依赖会明确报错，不再用 UMAP 冒充 t-SNE。它们是可选 R 依赖，可通过 `install.packages(c("Rtsne", "umap"))` 安装。计算前要求至少四个样本、输入有限；参数和随机种子记录在结果中。既有 t-SNE 任务若实际保存了 UMAP 坐标，会明确标作历史 UMAP 备用结果。

LEfSe / ANCOM 目前仍是 Random Forest 备用实现，图中注明实际方法，不能当作 LEfSe LDA 或 ANCOM W。标志物分数图不生成未保存的 ROC 或验证性能。原生 PCA / PCoA 只有可信的解释率元数据才展示百分比，不把未知轴权重解释为方差比例。

旧后台任务也可选择出图。若旧聚类只保存归属，没有树或投影，就提供归属图和数量图；不会为了画图隐式重跑聚类。若需要新树或投影，用户需明确重新运行分析。旧结果没有保留的软件版本、分组或算法信息不会用当前实验信息替代。

## API

- `GET /api/visualize/analysis-result/sources/<session_id>?experiment=...`：当前会话和实验的结果目录。
- `POST /api/visualize/analysis-result/describe`：结果列、分组及可用视图。
- `POST /api/visualize/analysis-result`：指定 `session_id`、`experiment`、`kind`、`source_id`，以及所选视图参数；响应 `analysis_recomputed: false`。
- `GET /api/visualize/analysis-result/file/<session_id>/<filename>`：经所有权检查的图形、CSV 和清单下载。

来源 ID 分为 `snapshot:<id>` 与兼容旧任务的 `job:<id>`；所有入口检查会话、任务所有权及实验归属。前端只接受本 API 路径的下载链接。并行刷新、切换实验或结果时丢弃过时响应。

降维图还支持分组均值置信 / 数据椭圆、边际箱线与轴向 P / BH q，下载 STATS 查看统计审计。[用法、样本门槛与检验假定](ORDINATION_GROUP_FIGURES.md)。
