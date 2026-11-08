# 数据驱动的 AI 对话与流程引导

上传矩阵后，工作台会保留原文件，并检查行列结构、候选样本列、整数/小数、缺失值、负值和数值范围。检查摘要会进入右侧统一对话，调用用户已加载的模型推荐适用流程。模型未加载时保留问题，刷新或加载“模型与 API”后可继续发送。

整数矩阵只代表数值上兼容计数，不能证明它是 RNA-seq 原始计数。蛋白标识列只能提供组学候选。分组、批次、配对和生物学重复必须有真实样本信息或来源证据。含负数、小数或缺失值的输入不会自动套入 DESeq2/edgeR。

Agent 模式记住用户选择。它可以读取三个页面的白名单字段和检查摘要，填写现有选项、查询来源、查找矩阵文件、打开下载计划、读取已下载矩阵、生成流程、检查整合输入。下载和分析继续经过原有接口的数据校验。分组确认和执行审核复选框不在模型可写范围。

新数据的自动引导是草案模式：适用的计数流程可填入工作台供编辑；不会因为刚上传文件就执行差异分析。其他组学仍需通过对应已接入页面执行，不把工作台的 bulk counts 执行器宣传成任意组学执行器。

## 对话显示与自动化记录

- 模型回答渲染为标题、段落、列表、表格、链接和代码块；模型生成的 HTML 不执行，不自动加载远程图片。
- 工具阶段来自服务端实际事件：请求模型、开始调用工具、工具返回、错误或结束。无提示词、密钥、模型推理原文和工具参数。
- 步骤草案单独显示为卡片，标明尚未执行。
- 页面动作可在最多三轮中读取更新后的状态继续；相同字段不重复写入，无变化时停止空转。
- 后台接收事件显示任务编号；进度与失败/完成状态只取后台任务列表，不以模型宣称作为完成证据。
- Enter 发送，Shift+Enter 换行；输入法组合输入时 Enter 不发送。

当前是工具阶段实时更新，最终回答在模型响应完成后显示；尚未实现逐字 token 流式显示。进度记录在元数据服务内存保留最多 30 分钟、100 个轮次、每轮 48 条事件。刷新浏览器后旧聊天不会恢复。

## GitHub 源码参考与应用映射

2026-11-08 直接读取 [yilewang/llm-for-zotero](https://github.com/yilewang/llm-for-zotero) 的 main 分支；另确认本机插件版本为 3.9.16。以下借鉴的是交互和状态设计，本项目重新实现对应功能，未复制其插件代码或账号登录组件。

| 上游代码 | 学到的设计 | 本项目对应实现 |
|---|---|---|
| [assistantRichText.ts](https://github.com/yilewang/llm-for-zotero/blob/main/src/modules/contextPanel/assistantRichText.ts) | 用户消息展示与内部运行状态分开 | `chat_presentation.mjs` 的安全富文本与独立记录 |
| [stageEvents.ts](https://github.com/yilewang/llm-for-zotero/blob/main/src/agent/stageEvents.ts) | 阶段事件只携带真实已知字段 | `agent_progress.py` 与轮询端点 |
| [toolPresentation.ts](https://github.com/yilewang/llm-for-zotero/blob/main/src/agent/toolPresentation.ts) | 工具应有可读名称 | 操作记录中的中文工具标签 |
| [taskProgress/planSteps.ts](https://github.com/yilewang/llm-for-zotero/blob/main/src/modules/contextPanel/taskProgress/planSteps.ts) | 步骤状态、未完成原因和折叠查看 | 草案卡片、工具记录、后台任务状态 |
| [loop/outcomes.ts](https://github.com/yilewang/llm-for-zotero/blob/main/src/agent/loop/outcomes.ts) | 只有宿主证据才能确认任务完成 | 后台接收回执与真实任务进度 |
| [loop/stopRules.ts](https://github.com/yilewang/llm-for-zotero/blob/main/src/agent/loop/stopRules.ts) | 无进展、失败和中断都应明确终止 | 有界页面续接、无变化不重复填写 |

## 本次验证

Node 测试覆盖可读表格/列表、安全链接、字段白名单、Agent 偏好、只解读不执行、后台状态与新增页面上下文。Python 测试覆盖矩阵数值识别、原始输入保留、工具校验、阶段事件和敏感字段不进入进度。

本地 HTTP 已验证整数计数候选和含缺失/负值的蛋白矩阵分别返回正确检查摘要。重启后服务端模型配置处于未加载状态；需浏览器恢复其已保存配置，真实 LLM 全链路尚未复验。浏览器自动化连接超时，不能将单元测试和 HTTP 检查视作真实点击验收。


## 对话输入区与附件（2026-11-08 更新）

- 右侧对话边界可左右拖动调宽，宽度保存在当前浏览器；分隔条支持左右方向键，双击还原。窄屏仍使用单列布局。
- 新消息、工具状态、后台进度和图片布局变化在用户位于底部时自动跟随；上滚阅读会暂停，点击“回到最新消息”恢复。
- 发送时立即清空文字输入，回复期间可编辑下一条草稿。迟到回复不清空新草稿；失败时仅在输入仍为空时恢复原问题。
- 底部模型选择列出已保存的服务/模型和已检测的模型目录，复用“模型与 API”的加载入口，不把密钥放入选项或聊天记录。
- 图片支持选择、拖入、剪贴板粘贴（PNG/JPEG/WebP，每张最多 5 MiB）。发送时通过标准图片内容块进入模型请求；Anthropic 协议转换为 base64 image source。模型是否支持视觉由所选模型实际能力决定，失败会显示原因。
- PDF 支持多选、拖入；共享应用文件大小上限，最多读取前 100 页，单篇发送最多 24,000 字符的带页码文本，全部 PDF 合计最多 48,000 字符。超出范围明确标为节选；不做 OCR，也不把提取文本说成看过页面图片。
- 每次最多保留 6 个附件。附件保留在输入区作为后续问答上下文，可逐项移除；清空对话会移除选中上下文。发送前上传仅在本机解析，发送消息后才提交给已选模型。
- 附件缓存在本机服务内存中最多 30 分钟；服务重启后失效，不改动原始文件。

继续直接读取的上游源码：
[chatScrollLifecycle.ts](https://github.com/yilewang/llm-for-zotero/blob/main/src/modules/contextPanel/chatScrollLifecycle.ts)、
[textareaSizing.ts](https://github.com/yilewang/llm-for-zotero/blob/main/src/modules/contextPanel/textareaSizing.ts)、
[chatFloatingComposer.ts](https://github.com/yilewang/llm-for-zotero/blob/main/src/modules/contextPanel/chatFloatingComposer.ts)、
[screenshot.ts](https://github.com/yilewang/llm-for-zotero/blob/main/src/modules/contextPanel/screenshot.ts)。

本次使用本地模拟模型服务验证了真实 HTTP 上传、PDF 工作进程、OpenAI-compatible 与 Anthropic 两种图片消息格式。模拟服务不是外部真实模型验收；外部模型测试单独记录在 `.local_run/verification/chat-attachments/`。

实际 MiniMax-M3.1-Flash 测试已返回：合成柱图 A=2、B=5；合成 PDF 为 6 个样本、GSE60450，并明确区分图片和 PDF 文本来源。请求未包含这些预期答案，也未执行分析。已通过原生 Chrome 查看新版界面、模型选择和上传后的 PDF 条目，观察到发送后输入框已清空；窗口拖动与滚动策略另有自动化交互测试覆盖。
