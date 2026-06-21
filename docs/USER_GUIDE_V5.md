# EasyMultiProfiler Web v5.0.1 — 用户使用指南

> **三种使用方式，请只选一种**  
> ① **macOS Web 版** · ② **Windows Web 版** · ③ **仅 R / RStudio 包**（不用浏览器）

启动 Web 版后，浏览器默认地址：**http://127.0.0.1:8080**（左侧 **Guide** 页有完整说明副本）。

---

## 1. 安装路径（Mac / Windows / R 各不相同）

### 🍎 macOS — Web 版

| 场景 | 操作 |
|------|------|
| **零基础一键** | 终端粘贴：`bash -c "$(curl -fsSL https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/master/webapp/scripts/install_from_github.sh)"` |
| **已有仓库** | 双击 `Run-EMP-Web.command` |
| **日常启动** | 同上（智能跳过已安装的包） |
| **修复依赖** | `bash webapp/scripts/launch_emp_web.sh --repair` |
| **先装 R** | `brew install --cask r python@3.12 git` |

详细文档：[INSTALL_MAC.md](INSTALL_MAC.md)

### 🪟 Windows — Web 版

| 场景 | 操作 |
|------|------|
| **零基础一键** | PowerShell：`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force` 后执行 `irm .../install_from_github.ps1 \| iex` |
| **首次（本地文件夹）** | 双击 **`Repair-and-Start-EMP-Web.bat`** |
| **日常启动** | 双击 **`Start-EMP-Web.bat`** |
| **更新 / 缺包** | 再运行 **`Repair-and-Start-EMP-Web.bat`** |
| **先装 R** | `winget install --id RProject.R -e` + Python + Git |

**请勿在 Windows 上运行 Mac 的 `.sh` / `.command` 文件。**  
详细文档：[INSTALL_WINDOWS.md](INSTALL_WINDOWS.md)

### 📊 仅 R / RStudio（不用 Web）

```r
if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak")
pak::pak("liubingdong/EasyMultiProfiler")
library(EasyMultiProfiler)
```

Web 专有的 **Course、AI 解读、Run All、Code Lab** 仅在浏览器版提供。

---

## 2. 确认安装成功

- 网页 UI：`http://127.0.0.1:8080` → 默认 **Course** 页  
- API 健康：`http://127.0.0.1:8000/api/health` → `"status":"ok"`  
- 侧边栏底部显示 **v5.0.1**

---

## 3. 网页内推荐流程（零基础）

```
Course（学 + 示例数据）→ Data → Prepare（推荐参数）→ Analyze → Run All → Visualize → Export
```

### 3.1 不想上传真实数据？

- **Course** 页：每课「一键加载本课示例数据」  
- **Data** 页：16S / RNA-seq / Clinical 官方 tests 数据集  

导入后会**自动套用**该组学的推荐过滤/归一化/阈值参数。

### 3.2 Prepare — 推荐参数

| 组学 | 推荐要点 |
|------|----------|
| 16S | prevalence ≥ 10%、Genus、rclr、keep top 40 |
| RNA-seq | DESeq2、padj ≤ 0.05、\|log2FC\| ≥ 1、min rowSum = 10 |
| 代谢组 | max NA ≤ 20%、KNN 填补、rclr |

Prepare 页点击 **「推荐参数（当前组学）」** 可手动重新套用。

### 3.3 Analyze + AI

- 差异、Alpha、富集等模块按 Omics 切换器过滤标签  
- 结果表格/图下方：**AI 解读结果**  
  - 无 API Key → 本地规则解读  
  - 有 LLM Key → 模型解读；图表可 **vision 读图** + 发表级 checklist  

### 3.4 Run All

- **RNA-seq**：DESeq2 → 火山 → 热图 → 富集 → 单 zip  
- **16S**：分类 → Alpha → Beta → 组成 → zip  
- 点击 **Smart defaults** 自动填充分组与阈值  

### 3.5 Code Lab（右侧栏）

- 查看/编辑 R 脚本，LLM 优化  
- 运行失败 → **AI 自动修复并重跑**  
- Copilot 建议 → **一键填入 Code Lab**

---

## 4. 页面导航速查

| 页面 | 作用 |
|------|------|
| **Course** | 视频任务卡、测验、示例数据、AI 纠错 Lab |
| **Guide** | 安装 + 本指南网页版 |
| **Data** | 上传 / demo 导入 |
| **Prepare** | 过滤、归一化、16S taxonomy |
| **Analyze** | 核心统计与机器学习模块 |
| **Run All** | 一键打包分析 |
| **Visualize** | 出版级出图 |
| **Clinical** | 临床表型 |
| **Export** | CSV / RDS / 课程 Markdown 报告 |

---

## 5. v5.0.1 新特性摘要

- 分平台傻瓜安装（Mac bash / Windows PowerShell+bat）  
- 一键示例数据 + 组学推荐参数  
- AI 解读（含图表 vision）+ 可执行 Code Lab actions  
- Run All 智能默认值  
- Course 教学闭环 + 期末报告导出  
- `emp_pub_theme` 统一出图 + AI 视觉 checklist  

---

## 6. 常见问题

**Q：Mac 和 Windows 安装命令能混用吗？**  
A：不能。Mac 用 `.sh` / `.command`；Windows 用 `.ps1` / `.bat`。

**Q：必须会 R 吗？**  
A：使用 Web 版不需要写 R，但本机须安装 R（≥ 4.3.3）作为后端；脚本会自动装 EMP 及依赖包。

**Q：8080 打不开？**  
A：Mac：`bash webapp/scripts/stop_local.sh` 后重启。Windows：`Restart-EMP-Web.bat`。

**Q：如何配置 AI？**  
A：Code Lab 或系统环境变量配置 LLM Key（如 `EMP_CAMPUS_LLM_API_KEY`），重启 API。

---

## 7. 更多资源

- GitHub Issues：https://github.com/xielab2017/EasyMultiProfiler-Web/issues  
- R 包教程：https://liubingdong.github.io/EasyMultiProfiler_tutorial/  
- 开发工作流：`webapp/V5_AGENT_WORKFLOW.md`
