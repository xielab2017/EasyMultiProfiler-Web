# Release Notes — V8.0.0_Education（预览）

**Branch:** `V8.0.0_Education`  
**Repo:** https://github.com/xielab2017/EasyMultiProfiler-Web  
**Status:** Education preview（课堂试用），不替换 `v7.0.0` / `main` 默认发布线。

## 摘要

在 V7 一键安装与多组学 Web 分析能力之上，增加面向课程的：

- 按周作业槽位（对接 Course case / task）
- 学号 + 自设口令
- 学生绑定个人 GitHub 仓库与 PAT
- 一键同步分析与教学产物（每次新建 run，保留历史）

## 学生流程

1. Course：完成周次微课 / 测验 / 实操  
2. Export：注册登录 → 绑定仓库 → 选择周次或期末项目 → 同步  
3. 在 GitHub 查看 `EMP2026/assignments/<track>/<week>/runs/...`

## 关键文件

- `webapp/backend/helpers/github_sync.R`
- `webapp/data/course_assignments.json`
- `webapp/frontend/js/github_sync.js`
- Export 页 GitHub 面板（`index.html` / `teaching.css` / i18n）
- `docs/TECHNICAL_MODE_V8_EDUCATION.svg`
- `docs/images/emp-web-v8-*.png`

## 环境变量（建议）

| 变量 | 作用 |
|------|------|
| `EMP_GITHUB_SECRET_KEY` | 加密学生 GitHub PAT（生产必设） |
| `EMP_STUDENTS_DIR` | 学生档案存储目录（可选） |
| `EMP_COURSE_CODE` | 课程代号，默认 `EMP2026` |

## 已知限制（预览）

- 学生身份与 Teaching Learning Trace 仍主要挂在分析 `session_id`；后续可将 Trace 正式挂到学号  
- 默认同步不含完整 RDS；大文件建议 Git LFS 或仅本地下载  
- 安装脚本若未改默认分支，请显式 `git clone -b V8.0.0_Education`

## 升级自 V7

可直接切换分支试用；分析与安装路径与 V7 兼容。教育功能为增量，不影响既有 Import → Analyze → Export 流程。
