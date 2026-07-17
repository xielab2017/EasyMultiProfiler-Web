# EasyMultiProfiler Web — Windows 一键安装（V7）

> **V7 重大升级：从 GitHub clone → 启动网页只需 1 行命令，R / Python / git / EMP 全部自动识别并按系统自动安装。**

---

## 1. 一行命令启动（强烈推荐）

以普通用户（**不需要管理员**）打开 **PowerShell**，粘贴：

```powershell
irm https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/v7.0.0/webapp/scripts/install_from_github.ps1 | iex
```

首次运行时脚本会**自动弹 UAC 提权窗口**（仅在缺失 R / python3 / git 时），装好后：

- 后端 API : `http://127.0.0.1:8000/api/health`
- 前端界面 : `http://127.0.0.1:8080`

---

## 2. 已经被 `git clone` 下来的用户

```powershell
cd EasyMultiProfiler-Web
powershell -ExecutionPolicy Bypass -File webapp\scripts\bootstrap_and_start.ps1
```

---

## 3. 日常启动（已装好之后）

**双击** `Start-EMP-Web.bat`（推荐）：

- 自动检测 R / python3 是否还在，缺了再补
- 缺 EMP 包则自动 `remotes::install_local()`

**命令行：**

```powershell
powershell -ExecutionPolicy Bypass -File webapp\scripts\launch_emp_web.ps1           # 智能启动
powershell -ExecutionPolicy Bypass -File webapp\scripts\launch_emp_web.ps1 -Repair   # 重装 R 包
```

---

## 4. 自动安装逻辑

`install_system_deps.ps1` 与 `install_r.ps1` 都是幂等的，按以下顺序探测：

| 探测 | 命中即跳过 | 缺失则执行 |
|------|-----------|-----------|
| `git` | `git.exe` 已在 PATH 且不在 WindowsApps 别名 | `winget install Git.Git`（无 winget 时下载 `Git-2.46.0-64-bit.exe` 静默安装） |
| `python3 ≥ 3.8` | 已在 PATH | `winget install Python.Python.3.12` 或 `python.org/ftp/python/3.12.7` 静默安装 |
| `R ≥ 4.3.3` | `Rscript.exe` 已找到 | 下载 `R-4.4.2-win.exe`（自动选 x64 / arm64），`/SILENT /ALLUSERS` 安装并写机器 PATH |

所有 `R-*` 版本号均可由 `-Version` / `EMP_R_VERSION` 覆盖。

---

## 5. 环境变量开关（高级）

```powershell
$env:EMP_AUTO_INSTALL = "0"     # 缺东西不装，只报错（CI / 受限环境）
$env:EMP_SKIP_DEPS    = "1"     # 跳过 python3 / git 安装
$env:EMP_SKIP_R_INSTALL = "1"   # 跳过 R 安装
$env:EMP_R_VERSION    = "4.4.2" # 指定 R 版本
$env:EMP_R_MIRROR     = "https://mirrors.tuna.tsinghua.edu.cn/CRAN"
$env:EMPI_PYTHON      = "C:\custom\python.exe"  # 指定 python
$env:EMPI_RSCRIPT     = "D:\custom\R\R-4.4.2\bin\Rscript.exe"
```

---

## 6. 启动失败排查

```powershell
# 单步日志
Get-Content .local_run\api.log -Tail 50
Get-Content .local_run\web.log -Tail 50
```

最常见的两个原因：

1. **Microsoft Store 别名 python** —— 在「应用执行别名」里关掉 `python.exe` / `python3.exe`，让脚本用真实安装。
2. **杀毒软件拦截 .exe 下载** —— 把 EasyMultiProfiler-Web 文件夹加白名单。

---

## 7. 与 V6 的差异

| 项目 | V6 | V7 |
|------|----|----|
| 安装 R | 用户手动 `winget install RProject.R` | 自动下载 CRAN `.exe` 静默安装 |
| 安装 git/python | 用户手动 | 自动 winget / 静默下载 |
| 启动 .bat | 检查依赖，缺则报错 | 缺则自动装，再启 |
| 默认 R 版本 | 用户已装 | 4.4.2（同时支持 x64 + arm64） |
| `EMP_AUTO_INSTALL=0` | 不存在 | 受限环境立即报错 |

---

## 8. 卸载 / 重置

- 卸载 R : `winget uninstall RProject.R` 或「控制面板 → 程序」
- 卸载 EMP : 启动一次 PowerShell，`Rscript -e "remove.packages('EasyMultiProfiler')"`
- 清理会话缓存 : 删除 `%TEMP%\emp_sessions`