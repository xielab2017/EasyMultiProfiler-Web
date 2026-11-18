# EMP Web 插件

[浏览独立插件商店](https://xielab2017.github.io/EasyMultiProfiler-Web-Plugins/) · [查看商店源码](https://github.com/xielab2017/EasyMultiProfiler-Web-Plugins)

EMP Web 工作台接受分析、结果展示和研究聊天三种 JSON 插件。方法插件描述在选定 assay 上计算的指标，展示插件选择结果中的指标及其显示方式。模型提供商继续使用独立的接口。[模型提供商开发文档](ai-providers/README.md)

## 安装与使用

1. 点击左侧或顶部导航中紧接「模型与 API」的「插件」。运行分析前，请先在导入页添加实验矩阵。
2. 在在线商店卡片点击「安装并启用」。模型提供商点「安装」，随后可进入设置。若离线，展开「从文件或内置示例安装」，选择示例并点「安装示例」，或从本地选择第三方开发者提供的 `plugin.json`。查看名称、版本及权限后点「启用」。
   安装后点插件名称旁的「设置」。分析插件可勾选要计算的指标，至少保留一项。展示插件可选择表格或条形图、设置每次展示的行数（1–200）。点击「保存」后，再次运行分析或展示结果时生效。可点击「恢复默认设置」。设置按用户、部署和插件版本指纹保存。
3. 选择实验及其主 assay，以及已启用的方法，点「运行分析」。任务完成后显示前 30 行，后台保留完整结果。API 亦可指定该实验的其他 assay。
4. 选择已完成的插件任务和展示插件，点「展示结果」。展示定义中指定的指标必须存在于该任务结果中。
5. 在线插件卡片可打开 GitHub 说明、设置或卸载。卸载撤销插件授权，已保存的任务结果和对话文字保留。「停用」撤回当前用户的授权。个人已安装的同一 ID 只可更新到同一 ABI 的更高版本，更新后需重新启用。每次运行记录实际授权的定义及 SHA-256。

管理员可将插件目录放入 `plugins/extensions/<id>/plugin.json`，用户刷新即可发现并自行启用。设置 `EMP_PLUGIN_ROOT` 可切换插件根目录，其下的 `extensions/` 和 `examples/` 分别提供预安装插件与可选示例。服务根据认证身份及部署端点分别保存网页安装的插件和授权。管理员预装目录具有同名优先权。无身份配置的本地模式使用同一个 local 身份。

## 研究对话插件

[Zotero 风格研究助手](examples/zotero-style-chat/README.md) 使用 emp.chat-ui.v1，权限为 chat.panel。renderer 取 research-chat，startup 可取 adaptive、expanded 或 collapsed。多个清单使用同一窗口时，按插件 ID 顺序采用第一个已启用配置。模型配置在「模型与 API」管理。

## 开发分析方法

从 [样本质量分析示例](examples/sample-quality/plugin.json) 复制一个目录，用新的小写 ID 命名目录及清单。清单严格检查字段。ID 和指标名均以小写英文字母开头，后续可用小写字母、数字、连字符及下划线，最多 48 字节。版本使用三个整数，例如 `1.0.0`。

| 字段 | 取值 |
| --- | --- |
| `abi` | `emp.analysis.v1` |
| `permissions` | `["assay.read", "job.result.write"]` |
| `definition.axis` | `sample` 按矩阵列汇总，`feature` 按矩阵行汇总 |
| `definition.metrics` | 1–8 个具有唯一 `key` 和 `expression` 的对象。名称 `item` 留给坐标标签 |
| 统计表达式 | `{"stat":"mean"}`。支持 `observed`、`missing`、`nonzero`、`sum`、`mean`、`median`、`sd`、`min`、`max` |
| 数值表达式 | `{"constant":2}`。常数须为有限数 |
| 算术表达式 | `{"op":"multiply","left":{"stat":"mean"},"right":{"constant":2}}`。支持 `add`、`subtract`、`multiply`、`divide`，最多四层运算 |

矩阵以特征为行、样本为列。观测计数、缺失计数和非零计数分别计数。其余统计量跳过缺失值，全缺失时返回 JSON null。样本标准差使用 n−1，自由度不足时返回 null。除零及非有限输出同样返回 null。每次接收最多 100 万个数值单元，输出轴最多 5000 个具有唯一标签的项目。运行环境负责存取矩阵及写入任务结果；插件只有清单中声明的运算可用。

## 开发展示方式

[条形图示例](examples/quality-bars/plugin.json) 使用 `emp.view.v1` 并声明 `["job.result.read"]`。定义字段如下。

```json
{"input":"emp.metric-table.v1","layout":"bars","label":"item","value":"mean","limit":30}
```

`layout` 可用 `table` 或 `bars`。标签始终为 `item`，`value` 选指定的结果指标，`limit` 为 1–200 行。网页将标签作为文本渲染。条形图以零为基线，显示正负值。不同作者发布的插件只需遵守同一结果契约并使用相同指标名即可组合。

## HTTP 接口

按部署设置提供 Bearer 身份认证。所有 POST 请求均使用 JSON。清单限 32 KiB，每个账号最多通过网页在当前部署安装到 128 项（含部署已安装项）。

| 方法及路径 | 请求或结果 |
| --- | --- |
| GET `/api/extensions` | 返回支持的 ABI、可安装示例、已安装清单摘要与定义、版本指纹、当前用户授权，以及无效目录诊断 |
| POST `/api/extensions/install` | `{"manifest":{...}}` 或 `{"example_id":"sample-quality"}` |
| POST `/api/extensions/uninstall` | 当前账号卸载指定的 `id` 与 `sha256` |
| POST `/api/extensions/enable` | `{"id":"sample-quality","sha256":"…","enabled":true}` |
| POST `/api/extensions/settings` | `id`、已安装清单的 `sha256`、`settings`。分析示例 `{"metrics":["mean","sd"]}`，展示示例 `{"layout":"table","limit":20}`。`settings: null` 恢复默认。GET 目录的已安装条目返回有效设置。 |
| POST `/api/extensions/run` | `id`、`sha256`、`session_id`、`experiment`、`assay`。返回后台 `job_id` |
| GET `/api/jobs/<id>`、`/api/jobs/<id>/result` | 任务状态及 `emp.metric-table.v1` 完整结构化结果，含 `columns`、`rows`、输入和方法指纹、方法定义及 R/Web 版本 |
| GET `/api/extensions/jobs/<session_id>` | 最近 30 个插件任务 |
| POST `/api/extensions/display` | `id`、`sha256`、`session_id`、`job_id`。返回布局、指标、预览行及总行数 |

在项目根目录运行以下命令核验单个插件或启动隔离的端到端回归。回归使用两个测试账号和本地合成矩阵。

```sh
Rscript --vanilla -e 'source("webapp/backend/helpers/platform_extensions.R"); print(.ext_read(commandArgs(TRUE)[1])$id)' plugins/examples/sample-quality/plugin.json
python3 webapp/tests/check_platform_extensions_http.py --rscript /path/to/Rscript
```

若已安装 Node、Playwright 及 Chromium，附加 `--browser` 即可通过真实网页完成上传、启用、运行和条形图数值验收。可用 `EMP_TEST_CHROME` 指定本机 Chromium 路径。
