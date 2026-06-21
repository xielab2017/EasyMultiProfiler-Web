# EasyMultiProfiler Web — Windows 安装指南（傻瓜版）

> 适用：Windows 10 / 11（64 位）。目标：装好 R + EMP + Web，浏览器打开 `http://127.0.0.1:8080`。  
> **Mac 用户请看 [INSTALL_MAC.md](INSTALL_MAC.md)**（命令与脚本完全不同）。  
> **网页内说明**：启动后左侧 **Guide** 页 · 完整手册 [USER_GUIDE_V5.md](USER_GUIDE_V5.md)

---

## ⚠️ 与 macOS 的区别（请勿混用）

| 项目 | Windows | macOS |
|------|---------|-------|
| 一键命令 | PowerShell + `install_from_github.ps1` | `bash` + `install_from_github.sh` |
| 首次启动 | `Repair-and-Start-EMP-Web.bat` | `Run-EMP-Web.command` 或 bootstrap |
| 日常启动 | `Start-EMP-Web.bat` | `Run-EMP-Web.command` |
| 先装 R | `winget install RProject.R` | `brew install --cask r` |

---

## 方式 A：一键安装（推荐）

### 第 1 步：安装 R（若尚未安装）

**选项 A1 — winget（Windows 11 / 已装 App Installer）**

以**管理员**打开 **PowerShell**，粘贴：

```powershell
winget install --id RProject.R -e --accept-source-agreements --accept-package-agreements
winget install Python.Python.3.12 Git.Git -e --accept-source-agreements --accept-package-agreements
```

安装完成后**关闭并重新打开** PowerShell。

**选项 A2 — 手动**

1. 打开 https://cran.r-project.org/bin/windows/base/  
2. 下载并安装 **R ≥ 4.3.3**（安装时勾选 **Add to PATH**）  
3. 安装 Python 3：https://www.python.org/downloads/（勾选 **Add python.exe to PATH**）  
4. 安装 Git：https://git-scm.com/download/win  

### 第 2 步：一键克隆 + 安装 + 启动

在 **PowerShell** 中粘贴（可整段复制）：

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
irm https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/master/webapp/scripts/install_from_github.ps1 | iex
```

或：下载仓库 ZIP 解压后，进入文件夹，**双击**：

`Repair-and-Start-EMP-Web.bat`

（首次必须用 **Repair**，会安装所有 R 包；之后日常用 `Start-EMP-Web.bat`。）

### 第 3 步：确认成功

- 网页：**http://127.0.0.1:8080**  
- API：**http://127.0.0.1:8000/api/health**  

---

## 方式 B：PowerShell 分步（适合 IT / 实验室）

```powershell
git clone https://github.com/xielab2017/EasyMultiProfiler-Web.git
cd EasyMultiProfiler-Web
powershell -ExecutionPolicy Bypass -File webapp\scripts\check_prerequisites.ps1
powershell -ExecutionPolicy Bypass -File webapp\scripts\repair_and_start_windows.ps1
```

---

## 日常使用

| 场景 | 操作 |
|------|------|
| 每天打开网页 | 双击 `Start-EMP-Web.bat` |
| 更新代码后 / 缺包报错 | 双击 `Repair-and-Start-EMP-Web.bat` |
| 重启服务 | 双击 `Restart-EMP-Web.bat` |
| 停止 | `powershell -File webapp\scripts\stop_local_windows.ps1` |

---

## R 找不到时

在 PowerShell 中设置（路径按本机修改）：

```powershell
$env:EMPI_RSCRIPT = "C:\Program Files\R\R-4.4.2\bin\Rscript.exe"
```

或设置 `$env:R_HOME` 为 R 安装目录。

---

## Rtools（编译报错时）

若 `install_runtime.R` 报 C/Fortran 编译错误：

1. 安装 https://cran.r-project.org/bin/windows/Rtools/  
2. 安装时勾选 **Add rtools to PATH**  
3. 重新运行 `Repair-and-Start-EMP-Web.bat`  

---

## 常见问题

| 现象 | 处理 |
|------|------|
| 脚本无法运行 | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| 8080 被占用 | 运行 `stop_local_windows.ps1` 后重试 |
| 防火墙弹窗 | 允许 **专用网络** 访问 Python / R |
| 首次不要用 Start | 必须先 **Repair-and-Start** 安装依赖 |

---

## 卸载

删除 `EasyMultiProfiler-Web` 文件夹；R 中 `remove.packages("EasyMultiProfiler")` 可选。
