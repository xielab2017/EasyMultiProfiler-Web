# Release Notes — V9.0.1_Education

**Branch:** `V9.0.1_Education`  
**Repo:** https://github.com/xielab2017/EasyMultiProfiler-Web  
**Status:** Education patch on V9.0.0_Education.

## Summary

- **Required display name（姓名必填）** on student register; backend rejects empty names.
- **Classroom homework repo** can be configured with `EMP_CLASS_HOMEWORK_REPO`; no repository is hard-coded.
- Optional **`EMP_CLASS_GITHUB_TOKEN`**: server auto-binds students to the class repo (token encrypted like a normal PAT bind).
- Login/register responses include `class_homework_repo`, `github_bound`, `auto_bound`, `need_pat`; also `POST /api/github/ensure_class_repo`.
- On successful bind/auto-bind, pushes a lightweight `EMP2026/students/{id}/connection.json` when GitHub write works.
- UI leaves `#gh-repo-url` blank and editable unless a deployment provides a repository.

## Env

| Variable | Purpose |
|---|---|
| `EMP_CLASS_HOMEWORK_REPO` | Optional class repo URL |
| `EMP_CLASS_GITHUB_TOKEN` | Optional shared PAT with push to class repo |
| `EMP_GITHUB_SECRET_KEY` | Encrypts stored PATs (unchanged) |

Without a configured class repository, students enter their target repository URL and PAT.

## Live GitHub push

If no class/student PAT is configured in the test environment, auto-bind and connection commit are **SKIP**ped; register/login + `need_pat` still work.
