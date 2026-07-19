# Agent Hub Integration

EasyMultiProfiler exposes a constrained API surface for Agent Hub. The first
integration release supports local capability discovery, protected path
preview/import, persistent sessions and asynchronous jobs.

## Local startup

The API listens on loopback by default:

```bash
EMP_ALLOWED_ROOTS=/absolute/project/root \
Rscript webapp/backend/run_api.R
```

Use the platform path separator to configure multiple allowed roots (`:` on
macOS/Linux and `;` on Windows). A path is accepted only when its normalized
target remains inside one of these roots. Symlink escapes and directories are
rejected.

Relevant environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `API_HOST` | `127.0.0.1` | Plumber bind host |
| `API_PORT` | `8000` | Plumber port |
| `EMP_ALLOWED_ROOTS` | empty | Roots available to path import |
| `EMP_DATA_DIR` | platform user data directory | Parent runtime directory |
| `EMP_SESSION_DIR` | `<EMP_DATA_DIR>/sessions` | Persistent sessions |
| `EMP_JOB_DIR` | `<EMP_DATA_DIR>/jobs` | Persistent asynchronous jobs |

Docker explicitly sets `API_HOST=0.0.0.0` because the API must accept traffic
from outside its container. Compose retains the existing `emp_sessions` named
volume at `/tmp/emp_sessions`; jobs use its `.jobs` directory, so an upgrade does
not hide sessions created by earlier Compose releases. Docker also disables the
arbitrary User R endpoint and restricts CORS to `http://localhost` by default.

## Capability negotiation

Agent Hub should call `GET /api/capabilities` before enabling path import or
asynchronous controls. The response advertises API/EMP versions, workflows,
limits and supported features. Clients must not infer API support from the Web
UI version.

## Protected path import

Preview does not create a session:

```http
POST /api/import/path/preview
Content-Type: application/json

{
  "data_path": "/allowed/project/abundance.csv",
  "metadata_path": "/allowed/project/meta.csv",
  "data_type": "tax"
}
```

Import reuses the same internal builders as multipart import:

```http
POST /api/import/path
Content-Type: application/json

{
  "data_path": "/allowed/project/abundance.csv",
  "metadata_path": "/allowed/project/meta.csv",
  "experiment_name": "study_16s",
  "data_type": "tax",
  "assay_name": "counts",
  "start_level": "Species",
  "tax_sep": ";"
}
```

Agent integrations must not expose the arbitrary R execution endpoints as
tools. Remote deployment additionally requires authentication, ownership
checks, restricted CORS and TLS; those controls are outside the local Phase 1
contract.
