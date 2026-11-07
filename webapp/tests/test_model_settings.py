"""Local configuration tests; no live provider calls or real credentials."""
import http.client
import json
import sys
import threading
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import model_settings as settings
import agent_adapter as agent
import public_data_server

class ModelSettingsTests(unittest.TestCase):
    def setUp(self):
        settings.clear(); self.addCleanup(settings.clear)

    def test_key_never_returned_and_loading_makes_no_model_request(self):
        with patch.object(agent, '_request') as request:
            value=settings.configure({'provider':'openai','model':'gpt-4.1-mini','api_key':'synthetic-secret','enabled':True})
            self.assertNotIn('synthetic-secret',json.dumps(value))
            self.assertEqual(agent.status()['status'],'ready');request.assert_not_called()

    def test_config_revision_binds_consent_and_endpoint_snapshot(self):
        value=settings.configure({'provider':'custom','base_url':'http://127.0.0.1:11434/v1','model':'qwen2.5:7b','enabled':True})
        with patch.object(agent,'_request',return_value={'role':'assistant','content':'Test reply'}) as request:
            self.assertEqual(agent.respond('hello',True)['status'],'configuration_changed');request.assert_not_called()
            reply=agent.respond('hello',True,expected_config_revision=value['config_revision'])
            self.assertEqual(reply['answer'],'Test reply')
            self.assertEqual(request.call_args.kwargs['endpoint'],'http://127.0.0.1:11434/v1/chat/completions')

    def test_unsupported_settings_do_not_change_configuration(self):
        base={'provider':'openai','model':'gpt-4.1-mini','api_key':'synthetic-secret','enabled':True}
        for changed in [dict(base,enabled='true'),dict(base,model='fusion'),dict(base,base_url='https://other.example/v1'),dict(base,provider='auto')]:
            with self.assertRaises(ValueError):settings.configure(changed)
        self.assertIsNone(settings.active())
        for url in ['file:///tmp/key','http://169.254.169.254','https://key:secret@api.example/v1','https://api.example/?key=secret','http://public.example/v1']:
            with self.assertRaises(ValueError):settings.endpoint(url)

    def test_config_route_is_owner_only_and_never_echoes_a_key(self):
        server=public_data_server.make_server(0);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        self.addCleanup(lambda:(server.shutdown(),server.server_close(),thread.join()))
        def call(body,origin=None):
            conn=http.client.HTTPConnection('127.0.0.1',server.server_port,timeout=5)
            headers={'Content-Type':'application/json'}
            if origin:headers['Origin']=origin
            conn.request('POST','/api/public-data/agent/config',json.dumps(body),headers)
            response=conn.getresponse();value=response.status,response.read();conn.close();return value
        body={'provider':'openai','model':'gpt-4.1-mini','api_key':'synthetic-secret','enabled':True}
        self.assertEqual(call(body,'https://unrelated.example')[0],403)
        status,raw=call(body);self.assertEqual(status,200);self.assertNotIn(b'synthetic-secret',raw)
        self.assertEqual(call({'reset_runtime':True})[0],200)

if __name__=='__main__':unittest.main()
