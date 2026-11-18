# Start EasyMultiProfiler Web

Download the source ZIP from the [main README](../README.md), extract it, and run the installer for your operating system. Once installed, use `Run-EMP-Web-Mac.command`, `Run-EMP-Web-Windows.bat` or `Start-EMP-Web-Linux.sh` to start the full application. The terminal prints the local URL, normally http://127.0.0.1:8080. Open **Plugins** to browse the plugin catalog or **Course** for the tutorial.

The full application also starts the metadata sidecar. To run only metadata discovery, public matrix downloads and PDF inspection, use `Start-EMP-Metadata.sh`, `.command` or `.cmd` and open the URL printed by the launcher, normally http://127.0.0.1:8081. PDF extraction requires `pypdf`. Configure a provider in **Models and API** before using an external AI model.

从[中文版 README](../README_CN.md)下载源码并解压，按系统运行安装器。安装后使用对应启动器打开完整应用，默认地址为 http://127.0.0.1:8080。插件商店在「插件」页，教程在「课程」页。只需查找文献、查看 PDF 或下载公开矩阵时，运行对应系统的 `Start-EMP-Metadata` 启动器并打开终端给出的网址，默认端口为 8081。
