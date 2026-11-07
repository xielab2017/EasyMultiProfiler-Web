"""Protocol/region/catalog contracts with synthetic credentials; no live calls."""
import io,json,sys,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import model_settings as settings
import model_catalog
import agent_adapter as agent

class Response(io.BytesIO):
    def __enter__(self):return self
    def __exit__(self,*args):self.close()

class Connections(unittest.TestCase):
    def tearDown(self):settings.clear()
    def config(self,**extra):return dict(provider='minimax',model='MiniMax-M3',api_key='synthetic-secret',enabled=True,**extra)
    def test_region_protocol_endpoints_and_no_cross_region_fallback(self):
        for region,host in [('china','api.minimax.cn'),('international','api.minimax.io')]:
            for protocol,path in [('openai','/v1/chat/completions'),('anthropic','/anthropic/v1/messages')]:
                public=settings.configure(self.config(region=region,protocol=protocol));self.assertEqual(settings.active()['endpoint'],'https://'+host+path);self.assertNotIn('synthetic-secret',json.dumps(public))
        with self.assertRaises(ValueError):settings.configure(self.config(region='china',base_url='https://api.minimax.io/v1'))
    @patch.object(model_catalog,'build_opener')
    def test_catalog_is_bounded_safe_and_does_not_load_settings(self,opener):
        opener.return_value.open.return_value=Response(json.dumps({'data':[{'id':'latest-chat','created':200},{'id':'older','created':100},{'id':'undated'}]}).encode())
        result=model_catalog.discover(self.config(region='international',protocol='anthropic'))
        self.assertEqual(result['models'][0]['id'],'latest-chat');self.assertIsNone(settings.active());self.assertEqual(opener.return_value.open.call_args.args[0].full_url,'https://api.minimax.io/v1/models');self.assertNotIn('synthetic-secret',json.dumps(result))
    @patch.object(agent,'build_opener')
    def test_anthropic_roundtrip_preserves_thinking_and_tool_results(self,opener):
        content=[{'type':'thinking','thinking':'synthetic reasoning','signature':'test'},{'type':'tool_use','id':'call_1','name':'propose_count_workflow','input':{'question':'PCA DESeq2 edgeR heatmap'}}]
        opener.return_value.open.side_effect=[Response(json.dumps({'content':content,'stop_reason':'tool_use'}).encode()),Response(json.dumps({'content':[{'type':'text','text':'Draft only.'}],'stop_reason':'end_turn'}).encode())]
        cfg=settings.configure(self.config(protocol='anthropic',region='china'))
        result=agent.respond('Generate a PCA DESeq2 edgeR heatmap draft.',True,expected_config_revision=cfg['config_revision'])
        self.assertEqual(result['status'],'ok');self.assertEqual(result['audit'][0]['tool'],'propose_count_workflow')
        requests=opener.return_value.open.call_args_list;payload=json.loads(requests[1].args[0].data)
        self.assertEqual(payload['messages'][1]['content'],content);self.assertEqual(payload['messages'][2]['content'][0]['type'],'tool_result');self.assertNotIn('synthetic-secret',json.dumps(result))
    def test_claude_gemini_and_monica_have_separate_verified_endpoints(self):
        expected={'claude':'https://api.anthropic.com/v1/messages','gemini':'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions','monica':'https://openapi.monica.im/v1/chat/completions'}
        for provider,target in expected.items():
            settings.configure({'provider':provider,'model':'explicit-chat-model','api_key':'synthetic-secret','enabled':True});self.assertEqual(settings.active()['endpoint'],target)

if __name__=='__main__':unittest.main()
