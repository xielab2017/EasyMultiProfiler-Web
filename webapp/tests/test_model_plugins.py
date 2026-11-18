"""Exercise the provider extension through EMP's local HTTP and agent interfaces."""
import http.client
import io
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import agent_adapter
import model_catalog
import model_plugins
import model_settings
import public_data_server


class ProviderPlugins(unittest.TestCase):
    def setUp(self):
        model_settings.clear()
        self.addCleanup(model_settings.clear)
        server = public_data_server.make_server(0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.port = server.server_port
        self.addCleanup(thread.join)
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)

    def call(self, route, body=None, headers=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        try:
            conn.request("GET" if body is None else "POST", "/api/public-data/agent/" + route,
                         None if body is None else json.dumps(body),
                         {"Content-Type": "application/json", **(headers or {})})
            response = conn.getresponse()
            return response.status, json.load(response)
        finally:
            conn.close()

    def test_another_provider_is_discovered_from_its_folder(self):
        example = model_plugins.PLUGIN_ROOT / "groq/plugin.json"
        manifest = json.loads(example.read_text())
        with tempfile.TemporaryDirectory() as tmp, patch.object(model_plugins, "PLUGIN_ROOT", Path(tmp)):
            path = Path(tmp) / "example/plugin.json"
            path.parent.mkdir()
            path.write_text(json.dumps(dict(manifest, id="example", name="Example", base_url="https://example.org/v1")))
            self.assertEqual(self.call("plugins", headers={"Origin": "https://example.org"})[0], 403)
            status, body = self.call("plugins")
            self.assertEqual(status, 200)
            self.assertEqual([item["provider"] for item in body["plugins"]], ["plugin-example"])
            config = dict(provider="plugin-example", base_url="https://example.org/v1", model="sample", api_key="sample-key", enabled=True)
            self.assertEqual(self.call("config", config)[0], 200)
            for invalid in [dict(base_url="https://other.example/v1"), dict(api_key=""), dict(protocol="anthropic")]:
                self.assertEqual(self.call("config", {**config, **invalid})[0], 400)
            for invalid in [dict(api_version=2), dict(api_key="unexpected"), dict(base_url="http://example.org"), dict(id="other")]:
                path.write_text(json.dumps({**manifest, "id": "example", **invalid}))
                with self.assertRaises(ValueError):
                    model_plugins.read_manifest(path)
            path.unlink()
            self.assertEqual(self.call("plugins")[1]["plugins"], [])
            self.assertEqual(self.call("config", config)[0], 400)

    def test_store_installs_provider_and_preserves_existing_definition(self):
        original = json.loads((model_plugins.PLUGIN_ROOT / "groq/plugin.json").read_text())
        with tempfile.TemporaryDirectory() as tmp, patch.object(model_plugins, "PLUGIN_ROOT", Path(tmp)):
            self.assertEqual(self.call("plugins/install", original, {"Origin":"https://example.org"})[0], 403)
            self.assertEqual(self.call("plugins/install", original)[0], 200)
            self.assertEqual(self.call("plugins/install", original)[0], 200)
            self.assertEqual(self.call("plugins/install", dict(original,base_url="https://example.org/v1"))[0], 400)
            self.assertEqual(self.call("plugins/install", dict(original,id="../outside"))[0], 400)
            self.assertEqual(self.call("plugins")[1]["plugins"][0]["base_url"], original["base_url"])
            remove = {"id":original["id"],"version":original["version"]}
            self.assertEqual(self.call("plugins/uninstall",dict(remove,version="2.0.0"))[0],400)
            self.assertEqual(self.call("plugins/uninstall",remove)[0],200)
            self.assertEqual(self.call("plugins")[1]["plugins"],[])
            bundled = Path(tmp) / original["id"] / "plugin.json"
            bundled.parent.mkdir()
            bundled.write_text(json.dumps(original))
            self.assertEqual(self.call("plugins/uninstall",remove)[0],200)
            self.assertTrue(bundled.is_file())
            self.assertEqual(self.call("plugins")[1]["plugins"],[])
            self.assertEqual(self.call("plugins/install",original)[0],200)
            self.assertEqual(len(self.call("plugins")[1]["plugins"]),1)

    def test_groq_config_discovery_chat_and_tool_result(self):
        catalog = self.call("plugins")[1]["plugins"]
        plugin = next(item for item in catalog if item["provider"] == "plugin-groq")
        config = dict(provider=plugin["provider"], base_url=plugin["base_url"], model=plugin["default_model"],
                      api_key="synthetic-plugin-secret", enabled=True)
        with patch.object(model_catalog, "build_opener") as opener:
            opener.return_value.open.return_value = io.BytesIO(json.dumps({"data": [{"id": config["model"]}]}).encode())
            self.assertEqual(self.call("models", config)[1]["models"][0]["id"], config["model"])
            self.assertEqual(opener.return_value.open.call_args.args[0].full_url, plugin["base_url"] + "/models")
        with patch.object(agent_adapter, "build_opener") as opener:
            status, loaded = self.call("config", config)
            self.assertEqual(status, 200)
            self.assertNotIn(config["api_key"], json.dumps(loaded))
            request = dict(question="Draft a PCA workflow", expected_provider=config["provider"],
                           expected_config_revision=loaded["config_revision"])
            self.assertEqual(self.call("respond", request)[1]["status"], "consent_required")
            opener.assert_not_called()
            tool = {"id": "call_1", "type": "function", "function": {
                "name": "propose_count_workflow", "arguments": json.dumps({"question": "PCA"})}}
            responses = [("tool_calls", {"content": None, "tool_calls": [tool]}), ("stop", {"content": "Draft ready."})]
            opener.return_value.open.side_effect = [
                io.BytesIO(json.dumps({"choices": [{"finish_reason": reason, "message": {"role": "assistant", **message}}]}).encode())
                for reason, message in responses
            ]
            status, answer = self.call("respond", dict(request, consent=True))
            self.assertEqual((status, answer["answer"]), (200, "Draft ready."))
            self.assertEqual(answer["audit"][0]["status"], "ok")
            last = opener.return_value.open.call_args.args[0]
            self.assertEqual(last.full_url, plugin["base_url"] + "/chat/completions")
            self.assertEqual(last.get_header("Authorization"), "Bearer " + config["api_key"])
            self.assertEqual(json.loads(last.data)["messages"][-1]["role"], "tool")
            self.assertNotIn(config["api_key"], json.dumps(answer))
