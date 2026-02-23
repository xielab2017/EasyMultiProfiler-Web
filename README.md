# 🧬 EasyMultiProfiler

> 多组学数据分析平台

[![GitHub Stars](https://img.shields.io/github/stars/xielab2017/EasyMultiProfiler)](https://github.com/xielab2017/EasyMultiProfiler)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## 🎯 选择版本

| 版本 | 语言 | 界面 | 适合用户 |
|------|------|------|----------|
| **[网页版 (推荐)](https://github.com/xielab2017/EasyMultiProfiler-Web)** | Python | 网页 | 零门槛用户 |
| **[R版](https://github.com/liubingdong/EasyMultiProfiler)** | R | RStudio | 专业用户 |

---

## 🆚 网页版 vs R版

| 功能 | 网页版 | R版 |
|------|--------|------|
| 安装 | 简单 (pip) | 复杂 (R 4.3+) |
| 界面 | 网页浏览器 | RStudio |
| ChIP-seq | ✅ | ✅ |
| 单细胞 | ✅ | ✅ |
| 多组学整合 | ✅ | ✅ |
| 可视化 | ✅ | ✅ |
| 数据安全 | 本地处理 | 本地处理 |

---

## 🚀 网页版 (推荐)

**零门槛，无需R环境，浏览器直接使用！**

### 安装

```bash
# 克隆
git clone https://github.com/xielab2017/EasyMultiProfiler-Web.git
cd EasyMultiProfiler-Web

# 安装
pip install -r requirements.txt

# 启动
python web/app.py

# 浏览器访问 http://localhost:5000
```

### 功能

| 模块 | 功能 |
|------|------|
| 🧬 **ChIP-seq** | QC, Peak calling, Motif, 注释, GO/KEGG富集, 可视化 |
| 🧬 **ATAC-seq** | 开放染色质分析, Footprinting |
| 🧬 **CUT&Tag** | 高灵敏度分析 |
| 🧬 **CUT&RUN** | 极低背景分析 |
| 🦠 **单细胞** | 降维(UMAP/tSNE), 聚类, 标记基因, 轨迹分析 |
| 🧪 **多组学** | RNA-seq + 微生物组 + 临床数据联合分析 |

---

## 📦 R版

完整功能，适合高级用户。

### 安装

```r
# 安装
if (!requireNamespace("pak", quietly=TRUE)) install.packages("pak")
pak::pak("liubingdong/EasyMultiProfiler")
library(EasyMultiProfiler)
```

### 文档

- 官网: https://easymultiprofiler.xielab.net
- 论文: [Science China Life Sciences](https://doi.org/10.1007/s11427-025-3035-0)

---

## 📁 项目结构

```
EasyMultiProfiler/
├── EasyMultiProfiler/          # R版 (原仓库)
│   ├── R/                     # R代码
│   ├── man/                   # 文档
│   └── ...
│
└── EasyMultiProfiler-Web/    # 网页版 (新仓库)
    ├── processors/           # 分析模块
    │   ├── chipseeq.py       # ChIP-seq分析
    │   ├── singlecell.py     # 单细胞分析
    │   └── multiomics.py    # 多组学整合
    ├── web/                   # 网页界面
    │   └── app.py           # Flask应用
    └── requirements.txt       # 依赖
```

---

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

---

## 📄 License

MIT License

---

## 📮 联系

- GitHub: https://github.com/xielab2017
- 官网: https://easymultiprofiler.xielab.net

---

*让多组学分析更简单* 🧬
