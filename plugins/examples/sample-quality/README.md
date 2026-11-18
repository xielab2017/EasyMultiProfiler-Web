# 样本质量概览

[English](README.en.md)

按样本统计观测值、缺失值、均值、标准差和变异系数。

![合成样本的质量统计表示例。](https://xielab2017.github.io/EasyMultiProfiler-Web-Plugins/assets/previews/sample-quality-zh.svg)

[在 EMP 中安装](http://127.0.0.1:8080/#plugins/sample-quality) · [插件页面](https://xielab2017.github.io/EasyMultiProfiler-Web-Plugins/examples/sample-quality/)

EMP 10.0.0+ · v1.0.0

在线安装需要 EMP 10.4 或更高版本。安装按钮打开本机 8080 端口。使用其他地址时，直接从该实例的「插件」页安装。

1. 在 EMP 10.4 或更高版本，打开「插件」，点击此插件的「安装并启用」。
2. 导入实验矩阵，在插件面板选择实验、主 assay 和 Sample quality summary。
3. 点击「运行分析」查看指标。10.2 起可在插件设置中选择需要的指标。

适用于特征为行、样本为列的数值矩阵。变异系数使用标准差除以均值，均值为零时结果为空。

assay.read 读取选定矩阵，job.result.write 写入新任务结果。
