# Groq model provider

[中文](README.md)

Add Groq to the EMP model selector and test the connection with your own API key.

![Example Groq provider configuration and connection controls.](https://xielab2017.github.io/EasyMultiProfiler-Web-Plugins/assets/previews/groq-en.svg)

[Install in EMP](http://127.0.0.1:8080/#plugins/groq) · [Plugin page](https://xielab2017.github.io/EasyMultiProfiler-Web-Plugins/en/ai-providers/groq/)

EMP 9.4.0+ · v1.0.0

Online installation requires EMP 10.4 or later. The install button opens port 8080 on this computer. For another address, open Plugins in that EMP instance.

1. In EMP 10.4 or later, open Plugins and select Install on the Groq card. Choose Settings if it is already installed.
2. Under Models and API, select Groq · Plugin and enter your own Groq API key.
3. Fetch the model list, select a model available to your account, then save, load and test the connection.

Requires access to Groq and valid credentials. In older versions, place plugin.json in plugins/ai-providers/groq/ and refresh the page.

Model requests send the submitted content to api.groq.com. The download contains only the provider manifest.
