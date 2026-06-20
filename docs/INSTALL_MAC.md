# EasyMultiProfiler Web — Mac 安装指南（傻瓜版）

> 适用：macOS 12+（Intel / Apple Silicon）。目标：装好 R + EMP + Web，浏览器打开 `http://127.0.0.1:8080`。  
> **Windows 用户请看 [INSTALL_WINDOWS.md](INSTALL_WINDOWS.md)**（命令与脚本完全不同）。  
> **网页内说明**：启动后左侧 **Guide** 页 · 完整手册 [USER_GUIDE_V5.md](USER_GUIDE_V5.md)

---

## ⚠️ 与 Windows 的区别（请勿混用）

| 项目 | macOS | Windows |
|------|-------|---------|
| 一键命令 | `bash` + `install_from_github.sh` | PowerShell + `install_from_github.ps1` |
| 双击启动 | `Run-EMP-Web.command` | `Start-EMP-Web.bat` |
| 首次修复 | `launch_emp_web.sh --repair` | `Repair-and-Start-EMP-Web.bat` |
| 先装 R | `brew install --cask r` | `winget install RProject.R` |

---

## 方式 A：一键安装（推荐，约 15–40 分钟）

### 第 1 步：打开「终端」

- 按 `Command + 空格`，输入 **Terminal**，回车。

### 第 2 步：粘贴下面**一整行**，回车

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/master/webapp/scripts/install_from_github.sh)"
```

脚本会自动：

1. 克隆 GitHub 仓库到当前目录下的 `EasyMultiProfiler-Web` 文件夹  
2. 检查 Git、Python、R（缺失时会提示如何安装）  
3. 安装 CRAN / Bioconductor / EasyMultiProfiler 依赖  
4. 启动后端（8000）和网页（8080）  
5. 尝试用 Safari 打开网页  

### 第 3 步：确认成功

浏览器地址栏应显示：

- 网页：**http://127.0.0.1:8080**（默认进入 **Course** 课程页）  
- 健康检查：**http://127.0.0.1:8000/api/health** → 看到 `"status":"ok"`

---

## 方式 B：没有 R？先装 R（只需做一次）

若一键脚本报 **`Rscript not found`**：

### 选项 B1 — Homebrew（推荐）

```bash
# 若未安装 Homebrew，先执行（官网：https://brew.sh）
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew install --cask r
brew install python@3.12 git
```

关闭终端再打开，然后重新执行 **方式 A** 的一键命令。

### 选项 B2 — 官方安装包

1. 打开 https://cran.r-project.org/bin/macosx/  
2. 下载 **R-4.x.x.pkg**（需 **≥ 4.3.3**）  
3. 双击安装，完成后重新执行 **方式 A**  

### 编译工具（若 EMP 安装报 Fortran / gfortran 错误）

```bash
xcode-select --install
# 若仍失败，见仓库 tutorial_related/Installation.md
```

---

## 方式 C：已下载 ZIP / 已有仓库文件夹

```bash
cd /你的路径/EasyMultiProfiler-Web
bash webapp/scripts/check_prerequisites.sh
bash webapp/scripts/bootstrap_and_start.sh
```

---

## 日常使用

| 操作 | 命令或文件 |
|------|------------|
| 启动 | 双击 `Run-EMP-Web.command`（日常：仅启动；首次或 `--repair`：自动装依赖） |
| 命令行启动 | `bash webapp/scripts/launch_emp_web.sh` |
| 强制修复依赖 | `bash webapp/scripts/launch_emp_web.sh --repair` |
| 仅启动（跳过安装检查） | `bash webapp/scripts/start_local.sh` |
| 停止 | `bash webapp/scripts/stop_local.sh` |
| 完整重装 | `bash webapp/scripts/bootstrap_and_start.sh` |

---

## 常见问题

| 现象 | 处理 |
|------|------|
| 8080 打不开 | 先 `bash webapp/scripts/stop_local.sh`，再 `start_local.sh` |
| 依赖安装很慢 | 设置镜像：`export EMP_CRAN_MIRROR=https://cloud.r-project.org` |
| 校园 LLM | 设置 `export EMP_CAMPUS_LLM_API_KEY=你的密钥` 后重启 API |
| 仅学课程、不上传数据 | Course 页 →「一键加载本课示例数据」 |

---

## 卸载

删除克隆的 `EasyMultiProfiler-Web` 文件夹；R 包可用 R 控制台：`remove.packages("EasyMultiProfiler")`。
