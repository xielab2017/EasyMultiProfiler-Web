# 导航、语言、表单与思考深度验收

日期：2026-11-08。Web 发布版本：9.2.0。

## 修改

- 删除左侧和顶部的“课程”“AI 提示词”导航入口；旧入口回到指南。顶部直接从左侧生成，同步名称、顺序、当前页和组学可见范围。侧栏排序仍保存在当前浏览器。
- 为 11 种界面语言建立统一文本目录，覆盖静态文案、动态按钮、选项、占位符、标题和提示。目录包含 3116 条源文案。动态本地化保留原始文本，避免重复翻译造成空白累积、文案串改和页面阻塞。结果表、代码、样本与分组值、模型名称、用户和 AI 对话原文不做界面翻译。
- AI 输入区增加“思考深度”。按模型能力开放选项，按服务与模型分别保存。未知或无已公布参数的模型使用默认值；服务端校验后才传递参数。Plan 仍是可选项。
- 多研究整合和工作台统一输入框、选择框、按钮、间距和响应式布局。普通输入框与选择框高度 42 px。
- 导出卡片使用相同布局；所有下载按钮宽度随卡片、固定高度 48 px、统一描边样式并在底部对齐，支持长语言换行。
- Web 版本从仓库 DESCRIPTION 读取；页面欢迎信息、指南、版本徽标、健康接口和启动器使用同一来源。静态部署文件由同步脚本生成。

## 实际验证

| 检查 | 结果 |
| --- | --- |
| Chrome 中 11 种语言 × 16 个导航入口 | 176 次顶部/侧栏名称与顺序一致 |
| 左侧移动“模型与 API”再移回 | 顶部立即同步；原顺序已恢复 |
| 简体中文和俄语导出页 | 七张卡片同高，七个按钮均为 48 px，同一行底边一致 |
| 工作台和多研究整合表单 | 可见普通输入框、选择框均为 42 px；隐藏文件选择器除外 |
| MiniMax-M3.1-Flash，中国站、Anthropic 协议 | 实际发送 low；返回“思考深度连接正常” |
| 模型请求审计 | requested=low，applied=true，parameter=output_config.effort；无分析执行 |
| 刷新后思考深度 | low 恢复成功；之后已恢复测试前的 max |
| 俄语欢迎信息、指南和全局徽标 | 均显示 v9.2.0 |
| Node 前端测试 | 132 项通过，0 失败 |
| Python 模型、附件、适配器和版本测试 | 41 项通过 |
| 其他检查 | git diff --check、Mac 启动器 Bash 语法、R 后端解析、Python 编译通过 |

Web 与元数据服务保持运行，地址 http://127.0.0.1:8080/。健康接口 http://127.0.0.1:8003/api/health 返回 Web 9.2.0；已安装 R 包版本仍是 9.0.3，未伪装为升级。维护用翻译构建接口已关闭。

## 复现

```bash
node --test webapp/tests/*.mjs
PYTHONPATH=webapp/tests:webapp/scripts .local_run/metadata_venv/bin/python -m unittest webapp/tests/test_model_reasoning.py webapp/tests/test_agent_adapter.py webapp/tests/test_agent_attachments.py webapp/tests/test_version_source.py
```

升级时只修改 DESCRIPTION 的 Version，再运行：

```bash
python3 webapp/scripts/sync_app_version.py
```

本次验收证据位于 `.local_run/verification/nav-language/`，包括导航逐页记录、真实请求审计和中俄文界面截图。完整测试输出为 `.local_run/verification/nav-language-tests.txt` 和 `.local_run/verification/reasoning-tests.txt`。

## 验证边界

导航逐页检查没有重新执行所有科学分析。语言目录通过完整性、占位符和混入中文字符检查，尚未逐句完成各语种的人工语义校对。历史对话和原始研究数据保留原文。真实模型调用验证覆盖 MiniMax-M3.1；其他提供商本次仅验证参数规则，不能据此宣称全部联网通过。Windows 启动器未在 Windows 上运行。没有提交或推送 Git。

参数依据：[MiniMax 文档](https://platform.minimax.cn/docs/guides/text-generation)、[OpenAI reasoning](https://developers.openai.com/api/docs/guides/reasoning)、[Claude effort](https://platform.claude.com/docs/en/build-with-claude/effort)、[Gemini OpenAI compatibility](https://ai.google.dev/gemini-api/docs/openai)、[NVIDIA thinking budget](https://docs.nvidia.com/nim/large-language-models/1.15.0/thinking-budget-control.html)。
