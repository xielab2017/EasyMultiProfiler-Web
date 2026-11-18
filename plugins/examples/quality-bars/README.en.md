# Sample quality bars

[中文](README.md)

Compare sample means from an existing result table in a bar chart.

![Bar chart of mean values from the same synthetic samples as the quality table.](https://xielab2017.github.io/EasyMultiProfiler-Web-Plugins/assets/previews/quality-bars-en.svg)

[Install in EMP](http://127.0.0.1:8080/#plugins/quality-bars) · [Plugin page](https://xielab2017.github.io/EasyMultiProfiler-Web-Plugins/en/examples/quality-bars/)

EMP 10.0.0+ · v1.0.0

Online installation requires EMP 10.4 or later. The install button opens port 8080 on this computer. For another address, open Plugins in that EMP instance.

1. In EMP 10.4 or later, open Plugins and select Install and enable.
2. Choose a completed plugin job containing a mean column, such as a Sample quality summary result.
3. Choose Sample quality bars and select Show result.

The default view displays the first 30 rows. From EMP 10.2, Settings lets you switch between bars and a table and adjust the row limit.

job.result.read reads the selected job’s result table.
