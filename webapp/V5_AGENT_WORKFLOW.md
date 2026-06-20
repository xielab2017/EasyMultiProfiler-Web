# EMP-Web v5.0.0 — 多 Agent 工作流（10+ 轮优化）

> **目标**：零基础用户（无 R/RStudio）在 Mac / Windows 上一键完成 R + EMP + EMP-Web 安装；用 tests/ 数据多轮优化分析/出图/Run All；AI 解读与脚本优化达到「可执行建议 + 一键复制到 Code Lab」。
>
> **AI 四角色 + 自我进化**：见 [`EMP_AI_MULTI_AGENT_EVOLUTION.md`](EMP_AI_MULTI_AGENT_EVOLUTION.md)

## 角色

| 角色 | 职责 | 交付 |
|------|------|------|
| **用户（Gen-Z 学生）** | 按 INSTALL 文档首次安装；跑 Course + 三种 demo；反馈卡点 | 每轮 5–10 条可复现问题 |
| **AI 工程师** | 五模块 AI Interpret、prompt_buttons、locale 强制、heatmap 补充 | `ai_copilot.R` + 用例 |
| **系统代码工程师** | 安装脚本、evolution API、卡片 UI、smoke 测试 | R + JS + plumber |
| **市场销售** | 论文场景叙事、组图逻辑、Guide/演示脚本 | 文案 + demo 流程 |
| **数据工程师** | 依赖、跨平台、tests 数据管道、Run All 稳定性 | 脚本 + smoke 报告 |
| **测试员** | Mac/Windows 实机、无 R 环境、断网/慢网、AI 功能 | PASS/FAIL 清单 |

## 优化循环

```
用户验证 → 测试员回归 → 数据工程师修复 → AI/分析专项轮 → 下一轮
```

---

## 10 轮路线图

| 轮次 | 主题 | 状态 |
|------|------|------|
| R1 | 安装：Mac/Windows 文档 + prerequisites 脚本 + PS1 一键克隆 | ✅ 本轮 |
| R2 | install_runtime.R：本地 EMP 源码安装、patchwork 锁定、Python 检测 | ✅ 本轮 |
| R3 | AI 解读：结构化 actions + 出图美观度 + 一键 Code Lab | ✅ 本轮 |
| R4 | LLM 优化：主题/参数上下文、发表级美化 preset、错误修复轮 | ✅ 本轮 |
| R5 | smoke_v5：16S + RNA-seq + Clinical 端到端 | ✅ 本轮 |
| R6 | Run All 多层级：智能默认值（分组/对比组/物种自动识别 + tests 推荐阈值）| ✅ 本轮 |
| R7 | 过滤/归一化：各组学推荐默认值写入 UI + 教学联动 | ✅ 本轮 |
| R8 | 出图：emp_pub_theme 全 workflow 统一 + AI 视觉 checklist | ✅ 本轮 |
| R9 | Windows 实机：Python 解析器（py -3 / 跳过 Store stub）+ Repair bat 全流程 | ✅ 本轮 |
| R10 | Mac 实机：launch_emp_web.sh + .command 双击（智能安装/日常启动） | ✅ 本轮 |
| R11+ | AI vision 读图（多模态送图）、失败自动修复回环 | ✅ 本轮 |

**v5.0.0 发布条件**：R1–R10 测试员签字 + smoke_v5 全绿 + GitHub INSTALL / USER_GUIDE 文档评审通过 + 网页 **Guide** 页与分平台安装说明一致。

---

## 测试数据（统一路径 `tests/`）

| 数据集 | 文件 |
|--------|------|
| 16S | `tests/level-7.csv`, `tests/meta.csv` |
| RNA-seq | `tests/RNAseq_output.csv`, `tests/RNAseq_mapping.txt` |
| Clinical | `tests/Clinical-test.csv`, `tests/meta-test.csv` |

运行回归：

```bash
# 需先启动 API
bash webapp/scripts/start_local.sh
Rscript webapp/scripts/smoke_v5_pipeline.R
```

---

## AI 优化专项（多轮）

1. **解读**：结果 + 统计陷阱 + **出图美观度** + 编号建议  
2. **actions[]**：`{ label, workflow, tab, instruction, auto_optimize }`  
3. **前端**：「应用到 Code Lab」→ 填 instruction + 打开面板 + 可选自动 optimize  
4. **LLM 优化**：注入 `ui_context`（分组、阈值、配色）；`emp_pub_theme` / `emp_pub_palette` 约束  
5. **失败修复**：`user_r/run` stderr → 二次 optimize（R6+）

---

*文档版本：v5 Round 1 · 2026-06-20*
