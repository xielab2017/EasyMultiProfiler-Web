# EMP 外部 AI 模型插件

在网页「模型与 API」的服务下拉框选择 **Groq · Plugin**，填写自己的 Groq API Key，选择模型，点击「保存并加载到 AI 分析助手」。模型设置页提供模型列表检测和真实对话与工具调用测试。加载配置只访问本机服务，点击检测、连接测试或授权发送问题时才调用模型服务。浏览器沿用 EMP 的按服务保存设置机制，适合个人本机使用。

## 发布自己的服务插件

每个服务占用一个目录，包含一个 UTF-8 编码的 `plugin.json`。[Groq 的完整示例](groq/plugin.json) 可以直接复制。v1 支持 HTTPS、Bearer Key 和 OpenAI Chat Completions 协议。提供方应实现 `GET /models`、`POST /chat/completions`，工作台 Agent 使用支持 function calling 的聊天模型。

| 字段 | 约定 |
| --- | --- |
| `api_version` | 整数 1，表示 EMP 模型插件清单的接口版本 |
| `id` | 与文件夹同名，小写字母开头，可包含数字和连字符，最多 48 字符 |
| `version` | 插件发布版本，如 `1.0.0` |
| `name` | 网页服务选择器的显示名称 |
| `protocol` | `openai-chat-completions` |
| `base_url` | 服务的 HTTPS API 根地址，例如以 `/v1` 结尾。EMP 自动追加操作路径 |
| `default_model` | 服务接受的具体聊天模型 ID。用户也可检测模型列表或手动输入 |

把目录放入本文件夹，刷新网页，即可选择新服务。网页和后端从同一份清单读取固定地址，各服务使用独立配置。发布包仅包含以上公开字段，API Key 由用户在网页中填写。插件目录由本机管理员维护，发现过程仅读取 JSON。

服务发现接口为 `GET /api/public-data/agent/plugins`。返回 `api_version` 和 `plugins` 数组，每项包含清单字段以及运行时标识 `provider`（`plugin-<id>`）。模型设置、模型列表与聊天继续使用 EMP 现有接口。配置提交需携带该插件公布的 `base_url`。删除目录后刷新页面，已加载的内存连接可在设置页点击「停用本次加载与自动恢复」关闭。

开发时可在项目根目录运行以下命令校验单个清单，任何校验错误都会产生非零退出码。

```sh
python3 webapp/scripts/model_plugins.py plugins/ai-providers/groq/plugin.json
```

Groq 的接口地址和协议见 [Groq 兼容性文档](https://console.groq.com/docs/openai)，模型能力见 [Groq 工具调用文档](https://console.groq.com/docs/tool-use/overview)。
