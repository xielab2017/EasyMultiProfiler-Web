# Open the development features / 启动开发版新功能

The v9.1.3 development branch is `codex/v9.1.0-public-data-metadata`. It is not the default/main branch, and the old GitHub release packages do not contain these changes. An earlier development-slice ZIP was an overlay, not a complete installer.

1. Obtain this branch's complete source archive and extract into a **new sibling folder**. Do not overwrite an existing installation or reuse its running services.
2. Install Python 3.10+ from an approved official source if it is absent.
3. Run `Start-EMP-Metadata.cmd` on Windows, `Start-EMP-Metadata.command` on macOS, or `bash Start-EMP-Metadata.sh` on Linux. Alternatively run `python webapp/scripts/launch_metadata.py` from the extracted folder.
4. Open the exact URL printed in the terminal. Default: `http://127.0.0.1:8081/public_data.html`. This address refers to the same computer that runs the launcher. A changed port requires the printed URL.
5. Confirm the page says **v9.1.3**. This page exposes papers/PDFs, public metadata, confirmed processed-matrix downloads, workflow preflight and the restricted agent adapter.

The original R application on port8080 is separate. Its new sidebar/startup link gives these instructions rather than implying the sidecar is running. Full R dependencies are not bundled or verified in the current environment. Local PDF extraction additionally requires `pypdf`. No credentials are provided or collected in the page, and a live AI model is not configured by installing the package.

中文：下载独立开发分支完整源码，不是旧Release或源码增量包。解压到新目录，启动 `Start-EMP-Metadata` 对应平台脚本，打开终端输出的网址，并检查v9.1.3版本文字。旧首页8080与新元数据页8081是不同服务；如果端口占用，先确认已有服务来源，不要误停其他程序。完整源码不代表已安装R/Python依赖，也不代表真实AI已配置。

Tutorial: `tutorial.html` is an illustrated English-narrated guide with bilingual subtitles, not a live screen recording. Twenty legacy full lesson videos remain absent; readable fallbacks explain this instead of displaying an unexplained failed player.
