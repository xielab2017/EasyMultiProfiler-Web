# Release Notes — v9.0.4

**Branch:** `v9.0.4`  
**Base:** `9.0.3-windows`  
**Internal version:** `9.0.4`  
**Status:** Windows-ready release.

## Summary

- Keeps the repaired Windows launcher that starts the R API and web frontend together.
- Keeps the session-ownership registration fix for local student workflows.
- Removes the hard-coded classroom homework repository URL from the UI and backend.
- Leaves the GitHub repository URL blank and editable, and binds the repository supplied by the user.
- Preserves optional deployment-level `EMP_CLASS_HOMEWORK_REPO` and `EMP_CLASS_GITHUB_TOKEN` auto-binding.
- Excludes local sessions, jobs, student profiles, tokens, logs, and other `.local_run` data from Git.

## Validation

- JavaScript syntax checks pass.
- R source parsing and the GitHub repository smoke test pass.
- Local API and frontend health checks return HTTP 200 on Windows.
