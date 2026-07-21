# EasyMultiProfiler Webapp — V8.0.0_Education (preview)

Browser UI + Plumber API for EasyMultiProfiler. This preview branch adds course weekly sync to GitHub.

## Run locally

### One-line install (Education preview)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/V8.0.0_Education/webapp/scripts/install_from_github.sh)"
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/V8.0.0_Education/webapp/scripts/install_from_github.ps1 | iex
```

Open:

- Frontend: http://127.0.0.1:8080
- API health: http://127.0.0.1:8000/api/health

Stop:

```bash
webapp/scripts/stop_local.sh
```

## Education features

- Course cases with weekly assignment slots (`data/course_assignments.json`)
- Student ID + password login
- Bind personal GitHub repo + PAT
- Sync weekly / final project runs from the **Export** page

See the root [README.md](../README.md) and [docs/RELEASE_NOTES_v8.0.0_Education.md](../docs/RELEASE_NOTES_v8.0.0_Education.md).
