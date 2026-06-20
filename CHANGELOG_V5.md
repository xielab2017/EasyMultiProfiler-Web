# EasyMultiProfiler Web v5.0.0 — Release Notes

**Branch:** `v5.0.0`  
**Repository:** https://github.com/xielab2017/EasyMultiProfiler-Web  
**Date:** 2026-06-20

## Highlights

- **分平台一键安装**：Mac (`install_from_github.sh` / `.command`) 与 Windows (`install_from_github.ps1` / `.bat`)
- **内置 Guide 页**：安装、分析流程、FAQ（`docs/INSTALL_MAC.md`, `docs/INSTALL_WINDOWS.md`, `docs/USER_GUIDE_V5.md`）
- **i18n**：中/英界面与 workflow 步骤条
- **AI Interpret v2**：五模块卡片（结果解读 / 局限 / 出图优化 / 下游 / 组图）+ Code Lab prompt 按钮
- **自我进化层**：`/api/evolution/event` 匿名用户画像与事件采集
- **四角色 Agent 工作流**：见 `webapp/EMP_AI_MULTI_AGENT_EVOLUTION.md`
- **Code Lab**：LLM 脚本优化、vision 读图、失败修复回环
- **Run All + smoke_v5**：RNA-seq / 16S / Clinical 端到端回归
- **多组差异分析修复**：DESeq2/edgeR 多组比较、multi_lrt 全 pairwise + LRT 列

## Test data

统一目录 `tests/`（16S、RNA-seq、Clinical 官方示例）。

## Install (from this branch)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/v5.0.0/webapp/scripts/install_from_github.sh)"
```

```powershell
irm https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/v5.0.0/webapp/scripts/install_from_github.ps1 | iex
```

## Upgrade from v4.x

1. 拉取分支 `v5.0.0` 或运行上方一键安装（默认克隆 `v5.0.0`）
2. 重启 API + 前端：`bash webapp/scripts/start_local.sh`
3. 浏览器硬刷新（清除旧 JS 缓存）
