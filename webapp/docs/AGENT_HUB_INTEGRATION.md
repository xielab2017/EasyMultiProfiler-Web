# Agent Hub Integration

EasyMultiProfiler exposes a constrained API surface for Agent Hub. The first
integration release supports local capability discovery, protected path
preview/import, persistent sessions and asynchronous jobs.

The Phase 2 server foundation adds bearer authentication, endpoint-scoped
project/session ownership, persistent session manifests and supported job
cancellation. It does not provide public TLS termination by itself; place the
API behind an HTTPS reverse proxy before connecting a remote Agent Hub.

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
| `EMP_PROJECT_DIR` | `<EMP_DATA_DIR>/projects` | Projects and ownership records |
| `EMP_API_TOKEN` | empty | Bearer token; mandatory for non-loopback binds |
| `EMP_API_OWNER_ID` | `token-owner` | Stable owner attached to the configured token |
| `EMP_ENDPOINT_ID` | `local-default` | Stable deployment identity stored with ownership |
| `EMP_CORS_ORIGIN` | `*` locally | Explicit trusted origin required for non-loopback binds |

Docker explicitly sets `API_HOST=0.0.0.0` because the API must accept traffic
from outside its container. Compose retains the existing `emp_sessions` named
volume at `/tmp/emp_sessions`; jobs use its `.jobs` directory, so an upgrade does
not hide sessions created by earlier Compose releases. Docker also disables the
arbitrary User R endpoint and restricts CORS to `http://localhost` by default.
Before starting Compose, configure a strong bearer token or a token-hash map.
Non-loopback startup fails closed without one of them. Agent Hub stores only
the token's environment/secret reference and sends it as a bearer credential.

For multi-user deployments, set `EMP_API_TOKEN_SHA256S` to a JSON object mapping
stable owner IDs to SHA-256 token hashes, for example `{"alice":"<64 hex>"}`.
The server resolves each bearer token to its owner without storing raw tokens;
project, session and job records are then checked against that owner.

Because Docker exposes a non-loopback listener, the API refuses to start until
`EMP_API_TOKEN` or `EMP_API_TOKEN_SHA256S` is set:

```bash
EMP_API_TOKEN='replace-with-a-long-random-secret' docker compose -f webapp/docker-compose.yml up
```

Send the token only as a request header:

```http
Authorization: Bearer replace-with-a-long-random-secret
```

`GET /api/health` remains unauthenticated for health checks. Every other API
route requires the token whenever a token is configured or the listener is not
loopback. Tokens are never written to project, session or job records.

## Persistent projects and ownership

The Phase 2 server routes are:

- `POST /api/projects` creates an owned project.
- `GET /api/projects/<project_id>` returns that project to its owner.
- `POST /api/projects/<project_id>/sessions` creates and binds a session.
- `GET /api/session/<session_id>/manifest` returns imports, experiments, jobs and versions.
- `POST /api/jobs/<job_id>/cancel` cancels a worker started by the current API process.

Ownership records bind endpoint ID, owner ID and session/project. Changing
`EMP_ENDPOINT_ID` intentionally makes old records inaccessible until the
deployment is restored to its original identity. Existing unowned sessions can
be claimed automatically only by an unauthenticated loopback deployment;
remote deployments never auto-claim them.

Cancellation deliberately uses the live `callr` process handle rather than a
persisted PID. After an API restart a previously running job may still be
inspectable, but cancellation returns `not_cancellable`; this avoids killing an
unrelated process if the operating system has reused the old PID.

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
