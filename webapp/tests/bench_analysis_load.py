"""Run an isolated local EMP HTTP benchmark with synthetic count-workbench jobs."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from hashlib import sha256
from http.client import HTTPConnection
import json
from pathlib import Path
import os
import random
import secrets
import signal
import socket
import statistics
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "webapp/scripts"
sys.path.insert(0, str(SCRIPTS))
from launch_metadata import analysis_rscript


def fixture(features):
    rng = random.Random(1051)
    samples = [{"id": f"{group}{n}", "group": group} for group in ("A", "B") for n in range(1, 4)]
    rows = [["feature_id", *(s["id"] for s in samples)]]
    for n in range(features):
        base = rng.randint(50, 500)
        counts = [max(1, round(rng.gauss(base, base / 12))) for _ in samples]
        if n < features // 10:
            counts[3:] = [count * 4 for count in counts[3:]]
        rows.append([f"gene_{n}", *map(str, counts)])
    matrix = "\n".join(",".join(row) for row in rows) + "\n"
    plan = {
        "version": 1, "dataset_id": "fixture", "omics": "bulk_rnaseq", "data_type": "raw_counts",
        "samples": samples, "design": {"independent_samples": True, "reference": "A", "test": "B"},
        "contract": "emp-count-workbench-v1",
        "input_sha256": sha256(matrix.encode()).hexdigest(),
        "source_sha256": sha256(matrix.encode()).hexdigest(), "seed": 1051,
        "raw_counts_evidence": "Generated unnormalized counts for the EMP load benchmark.",
        "steps": [
            {"id": "qc", "operation": "qc", "parameters": {}},
            {"id": "norm", "operation": "normalize", "parameters": {}},
            {"id": "pca", "operation": "pca", "parameters": {"components": 2}},
            {"id": "diff", "operation": "deseq2", "parameters": {"alpha": 0.05, "min_count": 10, "min_samples": 2}},
            {"id": "heatmap", "operation": "heatmap", "parameters": {"top_n": 50}},
        ],
    }
    plan_json = json.dumps(plan, separators=(",", ":"))
    return {"plan_json": plan_json, "plan_sha256": sha256(plan_json.encode()).hexdigest(),
            "matrix_csv": matrix, "confirmed": True}


def request(port, endpoint, token=None, body=None, timeout=30):
    conn = HTTPConnection("127.0.0.1", port, timeout=timeout)
    try:
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
        began = time.monotonic()
        conn.request("POST" if body else "GET", endpoint, json.dumps(body) if body else None, headers)
        response = conn.getresponse()
        value = json.loads(response.read())
        elapsed = time.monotonic() - began
        if response.status != 200 or value.get("success") is False:
            raise RuntimeError(f"{endpoint}: {response.status} {value.get('error', '')}")
        return value, elapsed
    finally:
        conn.close()


def port_on_loopback():
    for _ in range(80):
        port = 18000 + secrets.randbelow(30000)
        with socket.socket() as check:
            try:
                check.bind(("127.0.0.1", port))
                return port
            except OSError:
                continue
    raise RuntimeError("Could not reserve a test port")


@contextmanager
def running_api(folder, tokens, worker_limit):
    port = port_on_loopback()
    env = {**os.environ, "API_HOST": "127.0.0.1", "API_PORT": str(port),
           "EMP_DATA_DIR": str(folder / "data"), "EMP_SESSION_DIR": str(folder / "data/sessions"),
           "EMP_JOB_DIR": str(folder / "data/jobs"), "EMP_PROJECT_DIR": str(folder / "data/projects"),
           "EMP_ENABLE_USER_R": "false", "EMP_API_TOKEN": "",
           "EMP_API_TOKEN_SHA256S": json.dumps({f"bench-{i}": sha256(token.encode()).hexdigest()
                                               for i, token in enumerate(tokens)}),
           "EMP_BACKEND_DIR": str(ROOT / "webapp/backend"), "BACKEND_DIR": str(ROOT / "webapp/backend"),
           "EMP_ANALYSIS_WORKERS": str(worker_limit), "VECLIB_MAXIMUM_THREADS": "1"}
    rscript = analysis_rscript(SCRIPTS)
    if not rscript:
        raise RuntimeError("No compatible Rscript was found")
    with (folder / "r-api.log").open("w") as log:
        proc = subprocess.Popen([rscript, str(ROOT / "webapp/backend/run_api.R")], cwd=ROOT,
                                env=env, start_new_session=True, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 90
            while time.monotonic() < deadline:
                if proc.poll() is not None:
                    raise RuntimeError(f"R exited; see {log.name}")
                try:
                    if request(port, "/api/workbench/capabilities", tokens[0], timeout=2)[0]["ready"]:
                        break
                except (OSError, RuntimeError):
                    pass
                time.sleep(0.25)
            else:
                raise RuntimeError(f"R startup timed out; see {log.name}")
            yield port, proc.pid
        finally:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
            except ProcessLookupError:
                proc.wait()


def rss_tree(root):
    fields = subprocess.check_output(["ps", "-axo", "pid=,ppid=,rss=,comm="], text=True)
    rows = {}
    for line in fields.splitlines():
        parts = line.strip().split(maxsplit=3)
        if len(parts) == 4:
            pid, ppid, rss = map(int, parts[:3])
            rows[pid] = (ppid, rss, parts[3])
    descendants = {root}
    while True:
        children = {pid for pid, (parent, _, _) in rows.items() if parent in descendants}
        if children <= descendants:
            break
        descendants.update(children)
    workers = sum(1 for pid in descendants - {root} if Path(rows[pid][2]).name == "R" and rows[pid][1] > 0)
    return sum(rows[pid][1] for pid in descendants if pid in rows) / 1024, workers


def run_job(port, token, payload, features):
    started = time.monotonic()
    job, submit = request(port, "/api/workbench/run", token, payload)
    prefix = "/api/jobs/" + job["job_id"]
    queue_delay = None
    while time.monotonic() - started < 120:
        state, _ = request(port, prefix, token)
        phase = state["job"]["status"]
        if phase == "running" and queue_delay is None:
            queue_delay = time.monotonic() - started
        if phase == "done":
            result, _ = request(port, prefix + "/result", token)
            assert result["plan_sha256"] == payload["plan_sha256"]
            assert len(result["artifacts"]["differential"]["rows"]) == features
            return {"status": "done", "seconds": time.monotonic() - started, "submit_seconds": submit,
                    "first_observed_running_seconds": queue_delay, "tested_features": features}
        if phase in {"error", "cancelled"}:
            raise RuntimeError(f"{phase}: {state['job'].get('error', state['job'].get('message'))}")
        time.sleep(0.25)
    raise RuntimeError("Job did not finish before the 120-second deadline")


def percentile(samples, p):
    if not samples:
        return None
    if len(samples) == 1:
        return samples[0]
    return statistics.quantiles(samples, n=100, method="inclusive")[p - 1]


def load(port, pid, tokens, payload, features):
    done = threading.Event()
    samples, probes = [], []
    def monitor():
        while not done.is_set():
            samples.append(rss_tree(pid))
            try:
                _, latency = request(port, "/api/health", tokens[0], timeout=4)
                probes.append({"status": "ok", "seconds": latency})
            except (OSError, RuntimeError) as error:
                probes.append({"status": "error", "error": str(error)})
            done.wait(0.20)
    baseline_rss, _ = rss_tree(pid)
    monitor_thread = threading.Thread(target=monitor)
    monitor_thread.start()
    began = time.monotonic()
    try:
        with ThreadPoolExecutor(max_workers=len(tokens)) as pool:
            futures = [pool.submit(run_job, port, token, payload, features) for token in tokens]
            jobs = []
            for future in futures:
                try:
                    jobs.append(future.result())
                except Exception as error:
                    jobs.append({"status": "error", "error": str(error)})
    finally:
        elapsed = time.monotonic() - began
        done.set()
        monitor_thread.join()
    healthy = [probe["seconds"] for probe in probes if probe["status"] == "ok"]
    successful = [row["seconds"] for row in jobs if row["status"] == "done"]
    return {"concurrent_clients": len(tokens), "jobs_ok": len(successful), "jobs_failed": len(tokens)-len(successful),
            "elapsed_seconds": elapsed, "jobs_per_second": len(successful)/elapsed,
            "job_seconds_p50": statistics.median(successful) if successful else None,
            "job_seconds_p95": percentile(successful, 95),
            "health_ok": len(healthy), "health_failed": len(probes)-len(healthy), "health_seconds_p95": percentile(healthy, 95),
            "baseline_rss_mib": baseline_rss, "peak_rss_mib": max((rss for rss, _ in samples), default=baseline_rss),
            "peak_r_workers": max((n for _, n in samples), default=0),
            "jobs": jobs}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--clients", type=int, nargs="+", default=[1, 4, 8])
    parser.add_argument("--features", type=int, default=400)
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()
    if not all(1 <= n <= 12 for n in args.clients) or not 100 <= args.features <= 5000:
        parser.error("Use 1–12 clients and 100–5000 synthetic features")
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    payload = fixture(args.features)
    results = []
    for i, n in enumerate(args.clients, start=1):
        tokens = [secrets.token_hex(24) for _ in range(n)]
        folder = args.output / f"run-{i:02}-{n}-clients"
        folder.mkdir()
        with running_api(folder, tokens, args.workers) as (port, pid):
            summary = load(port, pid, tokens, payload, args.features)
        results.append(summary)
        print(json.dumps(summary), flush=True)
        (args.output / "results.json").write_text(json.dumps({"features": args.features, "samples": 6,
            "configured_worker_limit": args.workers, "results": results}, indent=2) + "\n")
    return int(any(row["jobs_failed"] or row["health_failed"] for row in results))


if __name__ == "__main__":
    raise SystemExit(main())
