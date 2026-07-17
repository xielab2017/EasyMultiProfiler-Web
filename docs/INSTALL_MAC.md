# EasyMultiProfiler Web — macOS / Linux 一键安装（V7）

> **V7 重大升级：从 GitHub clone → 启动网页只需 1 行命令，R / Python / git / EMP 全部自动识别并按系统自动安装。**

---

## 1. 一行命令启动（强烈推荐）

打开 **Terminal.app**（`⌘ + 空格`，输入 Terminal，回车），粘贴下面整行命令：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/v7.0.0/webapp/scripts/install_from_github.sh)"
```

> **复制错行了？** V7 入口脚本会**自动检测**当前操作系统（macOS / Linux / Windows），
> 即使你在 PowerShell 7 (`pwsh`) 里跑 `.ps1` 入口，也会自动转发到 `.sh`。
> 反过来 bash 入口也会自动转发。复制任意一行都不会装错系统。
>
> 想要 Windows CMD / 双击？下载 **`install.cmd`** 双击即可。

脚本会自动完成：

| 步骤 | 说明 |
|------|------|
| ① 检查 / 安装 **git** | 缺失时通过 Homebrew 或 apt 自动装 |
| ② **克隆仓库** 到当前目录的 `EasyMultiProfiler-Web` |
| ③ 检查 / 安装 **python3 ≥ 3.8** | 同上 |
| ④ 检查 / 安装 **R ≥ 4.3.3** | macOS 直接下载 CRAN `.pkg`；Linux 添加 CRAN apt/yum 源后 `apt-get install r-base` |
| ⑤ 安装 **CRAN + Bioconductor + EasyMultiProfiler** R 包 | `remotes::install_local()`，离线优先用本仓库的 EMP 源码 |
| ⑥ 启动 **后端 API :8000** + **网页 :8080** | 并尝试 `open` Safari 打开 |

首次安装大约 **15–40 分钟**（取决于网络，主要花在 Bioconductor）。

---

## 2. 已经被 `git clone` 下来的用户

```bash
cd EasyMultiProfiler-Web
bash webapp/scripts/bootstrap_and_start.sh
```

同样会自动判断并安装缺失组件。

---

## 3. 日常启动（已装好之后）

```bash
bash webapp/scripts/launch_emp_web.sh        # 智能启动：缺包才装
bash webapp/scripts/launch_emp_web.sh --repair   # 强制重装所有 R 包
```

或直接**双击** `Run-EMP-Web-Mac.command`。

---

## 4. 环境变量开关（高级）

```bash
EMP_AUTO_INSTALL=0  bash webapp/scripts/bootstrap_and_start.sh   # 缺东西不装，只报错
EMP_SKIP_DEPS=1     bash webapp/scripts/bootstrap_and_start.sh   # 跳过 git/python3 安装
EMP_SKIP_R_INSTALL=1 bash webapp/scripts/bootstrap_and_start.sh # 跳过 R 安装（必须已有 R ≥ 4.3.3）
EMP_R_VERSION=4.4.2 bash webapp/scripts/bootstrap_and_start.sh  # 指定要装的 R 版本（默认 4.4.2）
EMP_R_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/CRAN \
                   bash webapp/scripts/bootstrap_and_start.sh    # 改 CRAN 镜像
```

---

## 5. 启动失败排查

```bash
bash webapp/scripts/check_prerequisites.sh   # 单独检查 git/python/R
cat .local_run/api.log                       # 后端日志
cat .local_run/web.log                       # 前端日志
```

修复后再次 `bash webapp/scripts/launch_emp_web.sh --repair`。

---

## 6. 与 V6 的差异

| 项目 | V6 | V7 |
|------|----|----|
| 安装 R | 用户手动 `brew install --cask r` | 自动下载 CRAN `.pkg`，按需 sudo |
| 安装 git/python | 用户手动 | 自动 brew/apt |
| 一键脚本 | 2 个（mac / win） | 仍 2 个，但**默认行为变化**：缺啥装啥 |
| `EMP_AUTO_INSTALL=0` | 不存在 | 用于 CI / 受限环境，缺东西时立即报错而非尝试安装 |
| R 默认版本 | 用户已装 | 4.4.2（Apple Silicon 原生） |

---

## 7. 常见问题

**Q: 自动装 R 时弹出管理员密码？**  
A: 是的。`.pkg` 必须用 `sudo installer` 写入 `/Library/Frameworks/`。如果你不想输密码，可以用 `brew install --cask r` 预先装好。

**Q: 想用清华 CRAN 镜像怎么办？**  
A: `EMP_R_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/CRAN bash ...`

**Q: 在 ARM Mac 上没找到 R？**  
A: V7 默认装 `R-4.4.2-arm64.pkg`（macOS 11+ Big Sur 起）。低于 11 的系统请先升级 macOS。

**Q: Linux 没有 sudo？**  
A: 直接用 root 跑脚本，或设置 `EMP_AUTO_INSTALL=0` 提前手动装好 git/python/R。