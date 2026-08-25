# EasyMultiProfiler Webapp — v9.0.3 (main)

Browser UI + Plumber API for EasyMultiProfiler. Includes course weekly sync to GitHub.

## Run locally

### One-line install (main)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/main/webapp/scripts/install_from_github.sh)"
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/main/webapp/scripts/install_from_github.ps1 | iex
```

Open:

- Frontend: http://127.0.0.1:8080
- API health: http://127.0.0.1:8000/api/health

Stop (same ports/PIDs as start):

| Platform | Double-click / command |
|----------|------------------------|
| **macOS** | `Stop-EMP-Web-Mac.command` (repo root), or `bash webapp/scripts/stop_local.sh` |
| **Windows** | `Stop-EMP-Web-Windows.bat` (repo root), or `webapp/scripts/stop_local_windows.ps1` |

## Education features

- Course cases with weekly assignment slots (`data/course_assignments.json`)
- Student ID + password login
- Bind personal GitHub repo + PAT
- Sync weekly / final project runs from the **Export** page

See the root [README.md](../README.md) and [docs/RELEASE_NOTES_v9.0.3.md](../docs/RELEASE_NOTES_v9.0.3.md).
