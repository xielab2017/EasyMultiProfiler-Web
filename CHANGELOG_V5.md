# EasyMultiProfiler Web v5.0.1 — Release Notes

**Branch:** `v5.0.1`  
**Repository:** https://github.com/xielab2017/EasyMultiProfiler-Web  
**Date:** 2026-06-21

## Highlights

- **ChIP-seq 工作流**：BAM → MACS2/3 peak calling → ChIPseeker 注释 → 与 RNA-seq / 蛋白组交叉整合
- **RNA-seq GSEA**：基于 rank 的 GSEA（GO BP/CC/MF、KEGG、Reactome）
- **GO 富集细分**：enrichment 支持 GO_BP / GO_CC / GO_MF 独立选择
- **AI 结果解读升级**：CNS 级证据锚定 prompt + 离线模板（主模式 → 统计证据 → 生物学指向 → 结论边界）
- **Code Lab LLM 优化**：多 provider 自动回退、本地规则 polish、友好错误提示
- **可视化**：热图宽高可调；PCA/PCoA 防出框与 publication 主题
- **API 韧性**：前端自动尝试 `127.0.0.1` / `localhost` 双 base URL
- **v5.0.0 全部能力保留**：分平台安装、Guide 页、i18n、AI copilot、自我进化、Run All、smoke_v5

## Test data

统一目录 `tests/`（16S、RNA-seq、Clinical 官方示例）。

## Install (from this branch)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/v5.0.1/webapp/scripts/install_from_github.sh)"
```

```powershell
irm https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/v5.0.1/webapp/scripts/install_from_github.ps1 | iex
```

## Upgrade from v5.0.0

1. 拉取分支 `v5.0.1` 或运行上方一键安装（默认克隆 `v5.0.1`）
2. 重启 API + 前端：`bash webapp/scripts/start_local.sh`
3. 浏览器硬刷新（清除旧 JS 缓存）
