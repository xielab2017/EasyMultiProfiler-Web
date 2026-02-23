# EasyMultiProfiler Web

> EasyMultiProfiler Python网页版 - 零门槛多组学分析平台

[![GitHub Stars](https://img.shields.io/github/stars/xielab2017/EasyMultiProfiler-Web)](https://github.com/xielab2017/EasyMultiProfiler-Web)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## 🎯 简介

EasyMultiProfiler Web 是 **EasyMultiProfiler** 的Python网页版，旨在为零门槛用户提供便捷的多组学数据分析体验。

### 特点

- 🌐 **无需R环境** - 纯Python，零门槛
- 💻 **网页界面** - 浏览器直接使用
- 🔒 **数据安全** - 本地处理，不上传
- 🚀 **功能强大** - 继承R版核心功能

---

## 🆚 版本对比

| 特性 | R版 | Web版 |
|------|-----|-------|
| 安装 | 复杂 | 简单 |
| 环境 | R 4.3+ | Python 3.8+ |
| 界面 | RStudio | 网页 |
| 数据 | 服务器 | 本地 |

---

## 🚀 快速开始

### 安装

```bash
# 克隆
git clone https://github.com/xielab2017/EasyMultiProfiler-Web.git
cd EasyMultiProfiler-Web

# 安装依赖
pip install -r requirements.txt

# 启动
python web/app.py

# 浏览器访问
http://localhost:5000
```

---

## 📦 核心功能

### 已支持

| 模块 | 功能 |
|------|------|
| 🧬 **ChIP-seq** | Peak calling, Motif分析, 注释 |
| 🔬 **单细胞** | 降维, 聚类, 标记基因 |
| 🧪 **多组学整合** | RNA-seq + 微生物组联合分析 |
| 📊 **可视化** | 热图, 火山图, PCA, UMAP |

### 规划中

- CUT&Tag/CUT&RUN 分析
- 临床数据关联
- 报告生成

---

## 📁 项目结构

```
EasyMultiProfiler-Web/
├── processors/           # 分析模块
│   ├── chipseq.py      # ChIP-seq分析
│   ├── singlecell.py   # 单细胞分析
│   └── multiomics.py  # 多组学整合
├── web/                # 网页界面
│   └── app.py         # Flask应用
├── data/               # 示例数据
├── docs/               # 文档
└── requirements.txt    # 依赖
```

---

## 📖 文档

- [快速开始](docs/QUICK_START.md)
- [功能说明](docs/FEATURES.md)

---

## 🤝 贡献

欢迎提交 Issue 和 PR！

---

## 📄 License

MIT License

---

## 📮 联系

- GitHub: https://github.com/xielab2017/EasyMultiProfiler-Web

---

*让多组学分析更简单* 🧬
