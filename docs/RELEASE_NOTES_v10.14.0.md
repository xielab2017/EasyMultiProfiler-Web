# EasyMultiProfiler Web 10.14.0

自定义富集图采用完整常规排版，修复名称缩略与右侧图例裁切。

- 所有所选通路名称完整换行，不再用省略号或间隔显示代替完整名称。类别行距按文本高度和气泡直径分配；Gene ratio、Count、−log10(p.adjust)、条目排序与统计保持不变。
- 色阶和 Count 图例默认在右侧纵向排列，标题、坐标和两种图例一起参与空间测量。手动设置仍可选择左、右、上、下或隐藏图例，并保留单独指定的字号。
- 画布不足时返回 `FIGURE_LAYOUT_NEEDS_SPACE` 与建议宽高。网页提供「采用推荐尺寸并重新生成」按钮；点击前不改变宽高、单位和字体，也不显示旧图冒充新结果。用户可自行修改参数。
- 富集图推荐起点更新为 180 × 180 mm。自定义尺寸照常保留；字号与实际物理页面尺寸不会被静默更改。
- 保留 MANIFEST 中手动请求的换行上限，并单独记录实际渲染宽度与完整显示标签数量。失败的整批导出文件会清理。
- PDF / SVG 保持矢量色阶；PNG 使用平滑的位图色阶，避免矢量色块在预览中出现细缝。导出设备格式在各次绘制后恢复，避免格式串用。

验收：172 项 Node 测试通过。R 对 60 / 76.2 / 120 / 180 mm 请求验证完整的 20 个名称、20 个数据点、图例边界及原值不变；较小画布的建议尺寸由测试明确接受后才应用。验证手动 4 pt / 换行 5、独立标题 / 坐标 / 图例字号、五种图例位置、结构化空间建议及失败文件清理。真实浏览器验证推荐尺寸按钮、原尺寸不被提前改变、手动参数恢复及完整 PDF / CSV 下载；PDF 验证 20 个完整名称可见，无省略号及栅格图片。既有热图位置、火山图、外观和后台任务回归通过。

## English

Custom enrichment figures now retain every selected term name in full. Wrapped labels receive adequate categorical row spacing; conventional right-side color and Count guides fit within the export. If the chosen size cannot contain the requested typography, an explicit suggested-size action is offered. User dimensions and fonts stay unchanged until that action is accepted. PDF and SVG remain editable vectors.
