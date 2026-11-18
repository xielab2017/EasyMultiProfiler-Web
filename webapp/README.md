# EasyMultiProfiler Webapp

Browser UI + Plumber API for EasyMultiProfiler. Includes course weekly sync to GitHub.

## Run locally

For EasyMultiProfiler Web on `main`, use the launcher in its root directory, such as `Run-EMP-Web-Mac.command` on macOS. See the [current version and release notes](../README.md).

### One-line install from the upstream main branch

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

The original Windows education release is documented in the [v9.0.4 release notes](../docs/RELEASE_NOTES_v9.0.4.md).
