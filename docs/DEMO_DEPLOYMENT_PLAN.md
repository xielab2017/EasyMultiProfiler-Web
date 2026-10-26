# Public Demo Deployment Plan (NAR Web Server Route)

**Decision:** the owner chose the **Web Server route** on 2026-10-26.
The journal requires a publicly accessible demo on HTTPS (port 443),
usable **without login**, backed by a sample-data mechanism, and
maintained for **at least 5 years**.

## Chosen host and URL

- **Host:** the lab's Mac Studio (`liweimac-studio`), which already
  runs this app for LAN / phone access (see
  `webapp/docs/LAN_TAILSCALE_ACCESS.md`).
- **Public entry:** Tailscale Funnel on port 443 —
  `https://liweimac-studio.tail577190.ts.net/` → gateway `:8090` →
  UI `:8080` + API `:8000`. Funnel provides the public HTTPS endpoint
  the journal requires; no router port-forwarding is needed.
- **Why this host:** the publishing mechanism is already built into
  the project (`EMP_ENABLE_FUNNEL` in `webapp/scripts/start_local.sh`,
  helper `webapp/scripts/enable_emp_funnel.sh`) and the URL is stable
  as long as the tailnet and the machine name persist.
- **Checked 2026-10-26:** the Funnel name resolves and accepts
  connections, but the app itself was not running at check time
  (empty reply), so the demo is **not live yet** — step 1 below is
  the actual go-live.

## Go-live steps (on the Mac Studio)

```bash
# 1. Get the release code (v9.1.0 branch until it is merged to main)
git clone -b v9.1.0 https://github.com/xielab2017/EasyMultiProfiler-Web.git
cd EasyMultiProfiler-Web        # or git pull inside an existing clone

# 2. One-time runtime config + start (Funnel publishes automatically)
bash webapp/scripts/init_runtime_config.sh
bash webapp/scripts/start_local.sh
```

The start script prints the Funnel HTTPS URL when publishing succeeds.

## Verification checklist (from a non-tailnet network, e.g. phone on 4G)

- [ ] `https://liweimac-studio.tail577190.ts.net/` loads the UI with
      no login wall.
- [ ] `GET /api/health` over the same HTTPS origin returns OK.
- [ ] A bundled demo dataset loads in one click (Course / Guide) and
      one demo analysis runs end-to-end as a background job.
- [ ] The job tray shows progress and completion; results export.
- [ ] Language auto-detection works (and Arabic renders RTL).
- [ ] Record the verified date + URL in
      `docs/NAR_MANUSCRIPT_PLAN.md` and in the proposal summary
      (replace the demo-URL `{{TODO}}`).

## Public-demo hardening (before announcing the URL)

- Demo data only on the public instance; no real research data.
- `EMP_ENABLE_USER_R` stays `false` (the default) — no arbitrary R
  execution for anonymous visitors.
- Do **not** configure the deployment-wide GitHub token or a class
  repository on the demo instance; homework sync stays a local-install
  feature.
- Keep student-login features available but never required for the
  analysis path (journal rule: no login for the demo).
- Periodically clear accumulated anonymous sessions/jobs on the demo
  host (the app stores them under its local storage directories).

## Keeping it alive for 5 years (journal commitment)

- The Mac Studio must stay powered and online; set macOS to never
  sleep (Energy settings) and add the app start to the login items or
  a launchd agent so it recovers after reboots and updates.
- Keep the Tailscale Funnel mapping on 443 pointed at the gateway
  (do not `funnel reset`; other services use 8443 on the same host).
- Before the URL is printed in the manuscript, make the final call:
  keep Mac Studio + Funnel (zero hosting cost, workstation uptime) or
  migrate the same stack to a small always-on server (the URL would
  change, so decide **before** submission, not after acceptance).

## Fallback

If the public demo proves impractical, the stand-alone route remains
available: `container/Dockerfile` is drafted (build verification
pending) and the guidelines allow stand-alone applications without a
public demo, provided the container version runs without further
installs.
