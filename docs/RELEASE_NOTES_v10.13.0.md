# EasyMultiProfiler Web 10.13.0

热图色阶 / 分组图例可独立定位，并修复富集气泡图的小画布自动排版。

- 普通热图和 DEG 热图新增「色阶位置（Scale）」及「分组图例位置」。可选自动、上、下、左、右；关闭自动参数配置后分别固定位置，重新生成即可。按图型保存，中英文同步。
- 根据两个图例实际占用重新分配矩阵区域；色阶刻度增加外侧留白，避免端点数字裁切。不改变矩阵、聚类、颜色范围或统计。
- 富集图自动模式按导出设备实际测量文本宽度及可用高度，动态换行、缩略长名称或间隔显示条目标签。全部气泡和统计保留，DATA 下载保留完整名称；MANIFEST 记录采用的换行宽度和显示标签数。
- 气泡最大直径按画布和条目数适配，继续使用面积映射 Count；色阶最多显示三个刻度，计数图例使用三个参考值，避免小画布刻度重叠。
- 自动模式忽略此前保存的手动换行、最大气泡及颜色覆盖，并显示实际采用值；取消勾选恢复此前手动参数。Top N、条目筛选和统计阈值仍由用户控制。
- 手动换行字符数可为 1–10000 的整数，留空使用 45；取消过时的至少 10 字符校验。修复空字段被转换为 0。富集图宽高和字号遵守本图独立配置，允许小于原有 3 inch / 6 pt 限制的有效正数。
- 富集图色阶在 PDF 中使用矢量色块，不嵌入栅格图片；保留设定的物理页面尺寸，便于 Illustrator 按 100% 放置。
- 测试的隔离 R 实例加互斥锁，避免并发启动时误用另一实例的健康响应。

验收：171 项 Node 测试通过；R 验证所有 16 种热图图例位置组合，聚类保持一致。60 / 76.2 / 120 / 180 mm 富集图的可见标签不重叠，全部 20 个来源条目、数据点及完整名称保留。真实浏览器 / R API 验证自动参数、手动恢复、换行值 5、字号 4 pt、空换行默认、热图位置保存、中英文和窄屏。实际 76.2 mm PDF 为矢量输出，CSV 保留完整名称。既有自动 / 手动布局、外观、后台任务、富集图与导出回归通过。

## English

Heatmap color scales and annotation legends now have separate position controls. Automatic ORA layouts measure the final page to fit long term labels, bubble diameters and continuous/count legends; all points and full source descriptions remain available. Manual wrap values below ten and blank defaults are supported. PDF color bars use vector rectangles. Controls and saved settings remain independent for each figure type.
