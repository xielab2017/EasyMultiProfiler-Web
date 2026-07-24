# Lab MACS2/3 参数约定（TF / 组蛋白 Cut&Run / ATAC）

对齐本地脚本：

| 实验 | 本地依据 | EMP 预设 | 核心命令 |
|------|----------|----------|----------|
| TF Cut&Run | `Nr4a1.../macs2.sh` | `cutrun_tf_p05` ★ | `-f BAMPE -g 1.87e9 -p 0.05 -B` |
| Histone Cut&Run | `His163.../macs2.sh` | `cutrun_histone_p05` ★ | **同上**（不用 `--broad`） |
| ATAC | 同 lab 风格 | `atac_bampe_p05` ★ | 同上；可选 `-c IgG` |
| 更严 | macs2.sh `-p 0.01` | `*_p01` | `-p 0.01` |
| 宽峰域（可选） | — | `histone_broad` | BAMPE + `--broad` |

## 推荐工作流

1. 本地跑 `webapp/scripts/macs_lab_callpeak.sh`
2. 上传：`*_peaks.narrowPeak`、`*_summits.bed`、`*_peaks.xls`（+ `*.run_info.txt`）
3. BAM 仅在 deepTools / DiffBind / IGV / 网页 callpeak 时注册

## 本地一键示例

```bash
# TF Cut&Run（多样本合并，对齐 47091 风格）
./webapp/scripts/macs_lab_callpeak.sh tf_p05 ./macs_out \
  HA1.bam HA2.bam HA3.bam HA4.bam HA5.bam -- \
  IgG1.bam IgG2.bam IgG3.bam IgG4.bam

# Histone Cut&Run
./webapp/scripts/macs_lab_callpeak.sh histone_p05 ./macs_out \
  His.bam -- IgG.bam

# ATAC
./webapp/scripts/macs_lab_callpeak.sh atac_p05 ./macs_out \
  ATAC1.bam ATAC2.bam --
```

**注意**：`gsize=1.87e9`（MACS2 经典 mm）。MACS3 短码 `mm`≈2.65e9，勿混用。
