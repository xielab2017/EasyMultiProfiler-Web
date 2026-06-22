# EasyMultiProfiler Web v5.0.2 — Release Notes

**Branch:** `v5.0.2`  
**Repository:** https://github.com/xielab2017/EasyMultiProfiler-Web  
**Date:** 2026-06-22

## Highlights

- **ChIP-seq 完整流程**：Treatment / Control 分栏上传；多 BAM/SAM → MACS2/3（assay 预设 + 高级 optimize 参数）→ ChIPseeker 注释 → RNA-seq 联合分析（热图、火山图、GO/KEGG bubble）
- **Code Lab LLM**：NVIDIA NIM、Base URL 标准/自定义、模型选择与独立 Save；优化速度与多 provider 修复
- **PCA 双圈点**样式恢复；publication 主题增强
- **v5.0.1 全部能力保留**：GSEA/GO 富集、AI copilot、分平台安装、Guide、i18n、Run All

## Test data

统一目录 `tests/`（16S、RNA-seq、Clinical 官方示例）。

## Install (from this branch)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/v5.0.2/webapp/scripts/install_from_github.sh)"
```

```powershell
irm https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/v5.0.2/webapp/scripts/install_from_github.ps1 | iex
```

## Upgrade from v5.0.1

1. 拉取分支 `v5.0.2` 或运行上方一键安装（默认克隆 `v5.0.2`）
2. 重启 API + 前端：`bash webapp/scripts/start_local.sh`
3. 浏览器硬刷新（清除旧 JS 缓存）
