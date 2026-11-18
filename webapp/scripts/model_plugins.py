"""Discover declarative model providers installed by the local EMP operator."""
import json
import logging
import os
import tempfile
import threading
import re
from pathlib import Path
from urllib.parse import urlsplit

PLUGIN_ROOT = Path(__file__).resolve().parents[2] / "plugins" / "ai-providers"
_registry_lock = threading.RLock()
FIELDS = {"api_version", "id", "version", "name", "protocol", "base_url", "default_model"}
MODEL_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}")


def read_manifest(path):
    if path.stat().st_size > 16 * 1024:
        raise ValueError("manifest exceeds 16 KiB")
    data = json.loads(path.read_text(encoding="utf-8"))
    return validate_manifest(data, path.parent.name)


def validate_manifest(data, directory_id):
    if not isinstance(data, dict) or set(data) != FIELDS:
        raise ValueError("unexpected or missing manifest fields")
    if type(data["api_version"]) is not int or data["api_version"] != 1:
        raise ValueError("unsupported plugin API version")
    if any(not isinstance(data[k], str) for k in FIELDS - {"api_version"}):
        raise ValueError("manifest fields must be strings")
    if data["id"] != directory_id or not re.fullmatch(r"[a-z][a-z0-9-]{0,47}", data["id"]):
        raise ValueError("id must match its directory name")
    if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", data["version"]):
        raise ValueError("version must be major.minor.patch")
    if not 1 <= len(data["name"].strip()) <= 80 or not data["name"].isprintable():
        raise ValueError("invalid display name")
    if data["protocol"] != "openai-chat-completions":
        raise ValueError("unsupported model protocol")
    if not MODEL_ID.fullmatch(data["default_model"]) or data["default_model"] in {"auto", "fusion", "mixed"}:
        raise ValueError("invalid default chat model")
    base = data["base_url"]
    if not base.isascii() or any(ord(c) <= 32 or ord(c) == 127 for c in base) or any(c in base for c in "\\?#"):
        raise ValueError("invalid base URL")
    url = urlsplit(base)
    if (url.scheme != "https" or not url.hostname or url.username is not None or url.password is not None
            or url.port == 0 or url.path.rstrip("/").endswith(("/chat/completions", "/models"))):
        raise ValueError("provide an HTTPS API base without credentials or an operation suffix")
    return {**data, "provider": "plugin-" + data["id"], "base_url": base.rstrip("/")}


def install_manifest(data):
    """Install a validated provider without replacing an administrator's configuration."""
    plugin_id = data.get("id") if isinstance(data, dict) else None
    parsed = validate_manifest(data, plugin_id)
    with _registry_lock:
        bundled = PLUGIN_ROOT / plugin_id / "plugin.json"
        destination = PLUGIN_ROOT / ".installed" / plugin_id / "plugin.json"
        existing = bundled if bundled.exists() else destination
        if existing.exists() and read_manifest(existing) != parsed:
            raise ValueError("A different provider already uses this ID")
        if not existing.exists():
            destination.parent.mkdir(exist_ok=True, parents=True)
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=destination.parent, delete=False) as temp:
                staging = Path(temp.name)
                json.dump(data,temp,ensure_ascii=False,indent=2)
            try:
                os.replace(staging,destination)
            finally:
                staging.unlink(missing_ok=True)
        (PLUGIN_ROOT / ".removed" / plugin_id).unlink(missing_ok=True)
        return {"installed": True, "provider": parsed["provider"]}


def uninstall_manifest(data):
    if set(data) != {"id","version"} or not isinstance(data["id"],str) or not re.fullmatch(r"[a-z][a-z0-9-]{0,47}", data["id"]):
        raise ValueError("Invalid provider ID")
    plugin_id = data["id"]
    with _registry_lock:
        current = providers().get("plugin-" + plugin_id)
        if current:
            if current["version"] != data["version"]:
                raise ValueError("Provider changed; refresh before removing")
            if (PLUGIN_ROOT / plugin_id / "plugin.json").is_file():
                marker = PLUGIN_ROOT / ".removed" / plugin_id
                marker.parent.mkdir(exist_ok=True)
                marker.touch()
            (PLUGIN_ROOT / ".installed" / plugin_id / "plugin.json").unlink(missing_ok=True)
    return {"uninstalled": True, "provider":"plugin-" + plugin_id}


def providers():
    catalog = {}
    paths = sorted((PLUGIN_ROOT / ".installed").glob("*/plugin.json")) + sorted(PLUGIN_ROOT.glob("*/plugin.json"))
    for path in paths:
        if (PLUGIN_ROOT / ".removed" / path.parent.name).exists():
            continue
        try:
            plugin = read_manifest(path)
        except (OSError, ValueError) as exc:
            logging.getLogger(__name__).warning("Skipping model plugin %s (%s)", path.parent.name, type(exc).__name__)
            continue
        catalog[plugin["provider"]] = plugin
    return catalog


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Validate one EMP model plugin manifest")
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(read_manifest(args.manifest), ensure_ascii=False, indent=2))
    except (OSError, ValueError) as error:
        parser.exit(1, f"Invalid model plugin: {error}\n")
