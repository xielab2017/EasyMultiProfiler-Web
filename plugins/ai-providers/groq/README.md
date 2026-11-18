# Groq 模型接口

[English](README.en.md)

把 Groq 接入 EMP 的模型选择器，用自己的 API Key 测试连接。

![Groq 模型配置与连接操作示意。](https://xielab2017.github.io/EasyMultiProfiler-Web-Plugins/assets/previews/groq-zh.svg)

[在 EMP 中安装](http://127.0.0.1:8080/#plugins/groq) · [插件页面](https://xielab2017.github.io/EasyMultiProfiler-Web-Plugins/ai-providers/groq/)

EMP 9.4.0+ · v1.0.0

在线安装需要 EMP 10.4 或更高版本。安装按钮打开本机 8080 端口。使用其他地址时，直接从该实例的「插件」页安装。

1. 在 EMP 10.4 或更高版本，打开「插件」，点击 Groq 的「安装」。已预装时可直接点「设置」。
2. 刷新「模型与 API」，选择 Groq · Plugin，填写自己的 Groq API Key。
3. 检测模型列表，选择账号可用的模型，保存并加载后进行连接测试。

需要可访问 Groq 的网络与有效凭据。旧版可将 plugin.json 放入 plugins/ai-providers/groq/ 后刷新页面。

调用模型会向 api.groq.com 发送本次提交的内容。下载包只包含服务清单。
