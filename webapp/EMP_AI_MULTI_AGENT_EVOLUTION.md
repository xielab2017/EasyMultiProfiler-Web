# EMP AI 多 Agent 体系与自我进化架构

**版本**：v5.1 · 2026-06-20  
**依据**：[EMP_AI_Interpret_Module_Upgrade_Guide.md](/Users/liweixie/Downloads/EMP_AI_Interpret_Module_Upgrade_Guide.md)

---

## 1. 目标

将 EMP 页面版 AI 从「通用图形解释器」升级为：

> **结果写作助手 + 图形审稿人 + 下游分析导航器 + 代码优化入口**

并通过 **四角色多 Agent 工作流** + **自我进化层**，在真实使用中持续收集信号、分析偏好、个性化升级。

---

## 2. 四角色 Agent 体系

| Agent | 视角 | 职责 | 交付物 |
|-------|------|------|--------|
| **用户（User）** | 零基础学生 / 一线科研 | 跑 Course + demo；反馈卡点；验证 AI 卡片是否「能写进论文」 | 每轮 5–10 条可复现问题 + 截图 |
| **AI 工程师** | Prompt / 结构化输出 / 多模态 | 五模块解读、强制 `output_language`、heatmap 补充、JSON schema、`prompt_buttons` | `ai_copilot.R` + 回归用例 |
| **系统代码工程师** | 后端 / 前端 / API / 存储 | 卡片 UI、Code Lab 闭环、evolution API、smoke 测试 | R + JS + plumber 端点 |
| **市场销售** | 产品定位 / 竞品 / 论文场景 | 卖点文案、组图逻辑、下游实验链、INSTALL/Guide 叙事 | Guide 文案 + 演示脚本 |

### 2.1 协作循环

```
用户验证 ──► 市场销售（场景/卖点）──► AI 工程师（prompt/schema）
      ▲                                      │
      │                                      ▼
自我进化层 ◄── 系统代码工程师（API/UI/存储）◄── 测试回归
```

### 2.2 评审清单（每轮）

**用户 Agent**

- [ ] 中文界面下 AI 输出是否全中文（不受基因名影响）
- [ ] 五张卡片是否比旧版 markdown 更易扫读
- [ ] prompt 按钮是否一键填入 Code Lab

**AI 工程师 Agent**

- [ ] 热图是否给出 ECM/通路方向（非「红高蓝低」套话）
- [ ] 局限模块是否明确「探索性 vs 正式 DEG」
- [ ] LLM 失败时 offline 五模块是否仍完整

**系统代码工程师 Agent**

- [ ] `/api/evolution/event` 是否写入 profile
- [ ] `ai_interpret` 返回 `sections` + `prompt_buttons`
- [ ] smoke / diff 回归仍绿

**市场销售 Agent**

- [ ] 对外话术：闭环 6 步（看懂→可靠→优化→代码→下游→组图）
- [ ] 与竞品差异：多组学 + Code Lab + 教学 Course 一体

---

## 3. AI Interpret v2 输出结构

| 模块 | 字段 | UI 卡片 |
|------|------|---------|
| 论文式结果解读 | `sections.interpretation` | 结果解读 |
| 统计与图形局限 | `sections.limitations` | 图形与统计局限 |
| 出图优化 | `sections.figure_optimization` | 出图优化建议 |
| 下游与实验 | `sections.downstream_guidance` | 下游分析与机制验证 |
| 文章组图 | `sections.manuscript_panel` | 文章组图建议 |
| Code Lab 入口 | `prompt_buttons[]` | 出图优化卡片内按钮 |

**语言控制**：`output_language` = `zh-CN` | `en-US`，由 `getLocale()` 传入，禁止模型从基因名推断语言。

---

## 4. 自我进化层（Self-Evolution）

### 4.1 采集事件

| event_type | 说明 |
|------------|------|
| `page_view` | 页面 / workflow 切换 |
| `analysis_run` | 分析类型、组学、实验 |
| `ai_interpret` | 解读来源 llm/offline、分析类型 |
| `prompt_button_click` | 按钮 label + workflow |
| `code_lab_optimize` | LLM 优化触发 |
| `analysis_error` | 错误摘要（截断） |

存储路径：`/tmp/emp_evolution/users/<user_id>/`

- `events.jsonl` — 原始事件流
- `profile.json` — 聚合画像（omics/analysis 计数、locale、copilot 次数、personalization）

### 4.2 API

```
POST /api/evolution/event
GET  /api/evolution/profile?user_id=<id>
```

前端 `user_id`：`localStorage.emp_evolution_user_id`（匿名 UUID，非 PII）。

### 4.3 个性化回灌（R1 已实现基础）

- `profile.personalization.experience_level`：`beginner` | `advanced`
- `profile.personalization.top_omics` / `top_analysis`
- 后续轮次：注入 `ai_interpret` user_prompt 作为「用户习惯」上下文

### 4.4 隐私原则

- 不存原始表达矩阵、患者 ID、上传文件名
- 仅统计型 payload（omics、analysis_type、locale、错误摘要）
- 用户可清除：`localStorage.removeItem('emp_evolution_user_id')`

---

## 5. 实现映射

| 组件 | 路径 |
|------|------|
| AI 五模块 + prompt_buttons | `webapp/backend/helpers/ai_copilot.R` |
| 进化存储 | `webapp/backend/helpers/user_evolution.R` |
| 前端 telemetry | `webapp/frontend/js/evolution.js` |
| 卡片 UI | `webapp/frontend/js/app.js` + `css/style.css` |
| 三方测试流（安装/ smoke） | `webapp/V5_AGENT_WORKFLOW.md` |

---

## 6. 路线图

| 轮次 | 主题 | 负责 Agent |
|------|------|------------|
| R1 | 五模块 + 卡片 + evolution API + 四角色文档 | 全员 ✅ |
| R2 | LLM 强制 JSON 解析 + vision 热图 ECM 模块 | AI 工程师 |
| R3 | profile 注入 interpret prompt + 推荐默认阈值 | 系统 + AI |
| R4 | 销售演示包：RNA-seq 热图 → 论文 Figure 2 叙事 | 市场销售 |
| R5 | 跨用户聚合（opt-in）→ 全局 prompt 微调 | AI + 系统 |

---

*与 V5 安装/测试 Agent 流程并行：见 `V5_AGENT_WORKFLOW.md`。*
