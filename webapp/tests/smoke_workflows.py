#!/usr/bin/env python3
"""HTTP smoke test for the Agent Hub-facing EMP 16S workflow."""

from __future__ import annotations

import base64
import hashlib
import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path


API_BASE = os.environ.get("EMP_API_BASE", "http://127.0.0.1:8000").rstrip("/")
ROOT = Path(__file__).resolve().parents[2]
DATA_ROOT = Path(os.environ.get("EMP_TEST_DATA_ROOT", ROOT / "tests")).resolve()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def request_json(method: str, path: str, payload: dict | None = None) -> dict:
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{API_BASE}{path}",
        data=body,
        method=method,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        data = json.loads(response.read().decode("utf-8"))
    if not data.get("success", False):
        raise AssertionError(f"{path} failed: {data}")
    return data


def request_bytes(path: str) -> tuple[bytes, str]:
    with urllib.request.urlopen(f"{API_BASE}{path}", timeout=120) as response:
        return response.read(), response.headers.get_content_type()


def main() -> None:
    data_path = DATA_ROOT / "16S_level-7.csv"
    metadata_path = DATA_ROOT / "16S_mapping.csv"
    before = {data_path: sha256(data_path), metadata_path: sha256(metadata_path)}

    capabilities = request_json("GET", "/api/capabilities")
    assert capabilities["api_version"] == "1.0"
    assert capabilities["features"]["path_import"] is True
    assert capabilities["features"]["arbitrary_r"] is False
    assert "microbiome_16s" in capabilities["workflows"]

    manifest = request_json(
        "POST",
        "/api/import/path/preview",
        {
            "data_path": str(data_path),
            "metadata_path": str(metadata_path),
            "data_type": "tax",
        },
    )
    assert manifest["data"]["orientation"] == "features_in_rows"
    assert manifest["sample_overlap"]["matched"] > 0
    assert not manifest["sample_overlap"]["metadata_only"]

    experiment = f"agent_smoke_{int(time.time())}"
    imported = request_json(
        "POST",
        "/api/import/path",
        {
            "data_path": str(data_path),
            "metadata_path": str(metadata_path),
            "experiment_name": experiment,
            "data_type": "tax",
            "assay_name": "counts",
            "start_level": "Species",
        },
    )
    session_id = imported["session_id"]
    assert imported["omics"] == "microbiome_16s"

    common = {"session_id": session_id, "experiment": experiment}
    validation = request_json(
        "POST", "/api/workflows/microbiome_16s/validate", {**common, "tax_sep": ";"}
    )
    assert all(validation["validation"]["checks"].values())

    taxonomy = request_json(
        "POST",
        "/api/workflows/microbiome_16s/prepare/taxonomy",
        {
            **common,
            "collapse_level": "Genus",
            "drop_unassigned": False,
            "keep_top_n": 40,
            "tax_sep": ";",
        },
    )
    assert taxonomy["n_features_after"] > 0

    alpha = request_json(
        "POST", "/api/analyze/alpha", {**common, "method": "shannon", "source": "current"}
    )
    assert alpha["n_rows"] > 0 and "shannon" in alpha["columns"]

    plot = request_json(
        "POST",
        "/api/visualize/alpha",
        {**common, "metric": "shannon", "source": "current", "width": 8, "height": 6},
    )
    png = base64.b64decode(plot["plot"])
    assert png.startswith(b"\x89PNG\r\n\x1a\n")
    assert plot["pdf_available"] is True and plot["pdf_name"].endswith(".pdf")

    pdf, mime = request_bytes(
        f"/api/download/plot/{session_id}/{experiment}/{plot['pdf_name']}"
    )
    assert mime == "application/pdf" and pdf.startswith(b"%PDF")

    after = {data_path: sha256(data_path), metadata_path: sha256(metadata_path)}
    assert before == after, "EMP smoke modified an input fixture"
    print(
        json.dumps(
            {
                "ok": True,
                "session_id": session_id,
                "experiment": experiment,
                "samples": imported["samples"],
                "features": imported["features"],
                "alpha_rows": alpha["n_rows"],
                "pdf_bytes": len(pdf),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
