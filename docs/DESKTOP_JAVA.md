# EasyMultiProfiler-Web `v8.0.0_Java` — Desktop contract

This branch is the **EMP Web** stack consumed by the JavaFX desktop shell together with
Agent Hub branch [`v5.0.8_Java`](https://github.com/xielab2017/Agent-Hub/tree/v5.0.8_Java).

## Role split

| Layer | Owns |
|-------|------|
| **Agent-Hub `v5.0.8_Java`** | Agent UI + Python gateway :8765 |
| **This repo / branch** | R Plumber API :8000 + EMP static Web :8080 |
| **Java Desktop** | One-click install, starts both, Hub + EMP tabs |

## Desktop environment

```bash
EMP_DESKTOP=1
BROWSER=none
API_HOST=127.0.0.1
WEB_HOST=127.0.0.1
API_PORT=8000
WEB_PORT=8080
EMP_ENABLE_FUNNEL=false
# optional
EMP_CAMPUS_LLM_API_KEY=...
```

Launch (packages already installed):

```bash
bash webapp/scripts/start_local.sh
# or
bash webapp/scripts/launch_emp_web.sh   # respects EMP_DESKTOP=1 (no external browser)
```

## Health

- `GET http://127.0.0.1:8000/api/health` → `{"status":"ok",...}`
- UI: `http://127.0.0.1:8080/`

## Version

- Base: **V8.0.0_Education** (`a5c6b2b`)
- Branch purpose: Java Desktop packaging line → **v8.0.0_Java**
