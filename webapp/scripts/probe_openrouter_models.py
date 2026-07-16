#!/usr/bin/env python3
"""Probe OpenRouter models via local EMP API or direct OpenRouter calls."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONFIG_DIR = ROOT / "webapp" / "config"
CANDIDATES = [
    "deepseek/deepseek-v4-pro",
    "deepseek/deepseek-v4-flash",
    "moonshotai/kimi-k2.7-code",
    "qwen/qwen3.7-max",
    "z-ai/glm-5.2",
    "z-ai/glm-5",
    "openai/gpt-5.6-sol",
    "openai/gpt-5.6-terra",
    "openai/gpt-5.6-luna",
    "openai/gpt-5.5",
    "openai/gpt-5.5-pro",
    "anthropic/claude-fable-5",
    "anthropic/claude-sonnet-5",
    "anthropic/claude-opus-4.8",
    "google/gemini-3.1-pro-preview",
    "google/gemini-3.5-flash",
    "openai/gpt-4o-mini",
    "deepseek/deepseek-chat",
    "meta-llama/llama-3.3-70b-instruct",
]


def load_openrouter_cfg() -> dict:
    cfg_path = CONFIG_DIR / "openrouter_llm.json"
    if cfg_path.exists():
        with cfg_path.open("r", encoding="utf-8") as fh:
            return json.load(fh)
    return {
        "base_url": os.environ.get("EMP_OPENROUTER_LLM_URL", "https://openrouter.ai/api/v1"),
        "api_key": os.environ.get("EMP_OPENROUTER_LLM_API_KEY", ""),
        "timeout": 90,
        "fusion_model": "deepseek/deepseek-v4-flash",
    }


def probe_via_api(api_base: str, config: dict, models: list[str]) -> dict:
    payload = {
        "config": config,
        "models": models,
        "write_manifest": True,
    }
    req = urllib.request.Request(
        f"{api_base.rstrip('/')}/api/llm/probe_openrouter",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=max(120, len(models) * 90)) as resp:
        return json.loads(resp.read().decode("utf-8", "replace"))


def probe_direct(config: dict, models: list[str]) -> dict:
    base_url = (config.get("base_url") or "https://openrouter.ai/api/v1").rstrip("/")
    api_key = (config.get("api_key") or "").strip()
    if not api_key:
        raise SystemExit(
            "OpenRouter API key missing. Create webapp/config/openrouter_llm.json "
            "or set EMP_OPENROUTER_LLM_API_KEY."
        )
    timeout = float(config.get("timeout") or 60)
    working = []
    failed = []
    for model in models:
        body = {
            "model": model,
            "messages": [{"role": "user", "content": "Reply with exactly: OK"}],
            "max_tokens": 24,
            "provider": {"allow_fallbacks": False},
        }
        if not model.lower().startswith("openai/gpt-5"):
            body["temperature"] = 0.2
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
            "HTTP-Referer": os.environ.get("EMP_OPENROUTER_HTTP_REFERER", "http://127.0.0.1:8080"),
            "X-Title": os.environ.get("EMP_OPENROUTER_X_TITLE", "EasyMultiProfiler"),
        }
        req = urllib.request.Request(
            f"{base_url}/chat/completions",
            data=json.dumps(body).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        started = datetime.now(timezone.utc)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = json.loads(resp.read().decode("utf-8", "replace"))
            elapsed = (datetime.now(timezone.utc) - started).total_seconds()
            sample = ""
            choices = raw.get("choices") or []
            if choices:
                sample = str((choices[0].get("message") or {}).get("content") or "")[:120]
            working.append(
                {
                    "ok": True,
                    "model": model,
                    "latency_s": round(elapsed, 2),
                    "sample": sample,
                }
            )
            print(f"OK   {model} ({elapsed:.1f}s)")
        except urllib.error.HTTPError as exc:
            elapsed = (datetime.now(timezone.utc) - started).total_seconds()
            detail = exc.read().decode("utf-8", "replace")[:300]
            failed.append(
                {
                    "ok": False,
                    "model": model,
                    "latency_s": round(elapsed, 2),
                    "error": f"HTTP {exc.code}: {detail}",
                }
            )
            print(f"FAIL {model} HTTP {exc.code}")
        except Exception as exc:  # noqa: BLE001
            elapsed = (datetime.now(timezone.utc) - started).total_seconds()
            failed.append(
                {
                    "ok": False,
                    "model": model,
                    "latency_s": round(elapsed, 2),
                    "error": str(exc),
                }
            )
            print(f"FAIL {model} {exc}")

    working_ids = [row["model"] for row in working]
    fusion_defaults = working_ids[:5]
    if not fusion_defaults:
        fusion_defaults = config.get("models") or CANDIDATES[:5]
    payload = {
        "probed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "fusion_defaults": fusion_defaults,
        "fusion_model": working_ids[0] if working_ids else config.get("fusion_model", fusion_defaults[0]),
        "working": working,
        "failed": failed,
    }
    out_path = CONFIG_DIR / "openrouter_verified_models.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return {
        "success": True,
        "probed": len(models),
        "working_count": len(working),
        "failed_count": len(failed),
        "fusion_defaults": fusion_defaults,
        "fusion_model": payload["fusion_model"],
        "working": working,
        "failed": failed,
        "manifest_path": str(out_path),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe OpenRouter models for EMP Code Lab.")
    parser.add_argument("--api", default=os.environ.get("EMP_API_BASE", "http://127.0.0.1:8000"))
    parser.add_argument("--direct", action="store_true", help="Call OpenRouter directly instead of EMP API.")
    parser.add_argument("--models", default="", help="Comma-separated model list override.")
    args = parser.parse_args()

    models = CANDIDATES
    if args.models.strip():
        models = [m.strip() for m in args.models.split(",") if m.strip()]

    cfg = load_openrouter_cfg()
    if args.direct:
        result = probe_direct(cfg, models)
    else:
        try:
            result = probe_via_api(args.api, cfg, models)
        except Exception as exc:  # noqa: BLE001
            print(f"EMP API probe failed ({exc}); falling back to direct OpenRouter calls.")
            result = probe_direct(cfg, models)

    print("\n=== Summary ===")
    print(f"Working: {result.get('working_count', 0)} / {result.get('probed', len(models))}")
    print(f"Fusion defaults: {', '.join(result.get('fusion_defaults') or [])}")
    print(f"Manifest: {result.get('manifest_path', CONFIG_DIR / 'openrouter_verified_models.json')}")
    return 0 if result.get("working_count", 0) else 1


if __name__ == "__main__":
    raise SystemExit(main())
