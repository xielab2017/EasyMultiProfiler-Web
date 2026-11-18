# Sample quality summary

[中文](README.md)

Calculate observed and missing values, mean, standard deviation and coefficient of variation for each sample.

![Example quality table for synthetic samples.](https://xielab2017.github.io/EasyMultiProfiler-Web-Plugins/assets/previews/sample-quality-en.svg)

[Install in EMP](http://127.0.0.1:8080/#plugins/sample-quality) · [Plugin page](https://xielab2017.github.io/EasyMultiProfiler-Web-Plugins/en/examples/sample-quality/)

EMP 10.0.0+ · v1.0.0

Online installation requires EMP 10.4 or later. The install button opens port 8080 on this computer. For another address, open Plugins in that EMP instance.

1. In EMP 10.4 or later, open Plugins and select Install and enable.
2. Import a numeric matrix. In Plugins, choose the experiment, primary assay and Sample quality summary.
3. Select Run analysis. In EMP 10.2 or later, choose the metrics to compute in Settings.

Use features as rows and samples as columns. The coefficient of variation is the sample standard deviation divided by its mean. A zero mean gives a missing result.

assay.read reads the selected matrix. job.result.write saves the new analysis result.
