"""Loopback HTTP integration tests with synthetic upstream metadata."""
import http.client
import json
from pathlib import Path
import sys
import threading
import unittest
sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
import public_data_server as s
from test_public_data import FakeClient, report

class ServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = s.make_server(0)
        cls.server.client_factory = lambda: FakeClient([report()])
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True); cls.thread.start()
    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.thread.join()
    def call(self, path, data=None, headers=None):
        conn = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=3)
        h = {'Content-Type': 'application/json'}; h.update(headers or {})
        conn.request('GET' if data is None else 'POST', path, body=None if data is None else json.dumps(data), headers=h)
        r=conn.getresponse(); result=(r.status,r.read());conn.close();return result
    def test_page_and_script(self):
        self.assertIn(b'EasyMultiProfiler', self.call('/public_data.html')[1])
        self.assertEqual(self.call('/js/public_data_ui.js')[0],200)
    def test_health(self):
        status,body=self.call('/api/public-data/health');self.assertEqual(status,200)
        self.assertFalse(json.loads(body)['download_enabled'])
    def test_resolve_to_plan(self):
        status,body=self.call('/api/public-data/resolve',{'accession':'SRR123'})
        self.assertEqual(status,200); value=json.loads(body)
        status,body=self.call('/api/public-data/plan',{'manifest_id':value['manifest_id'],'selected_runs':['SRR123']})
        self.assertEqual(status,200);plan=json.loads(body);self.assertEqual(plan['archive_bytes'],30)
        self.assertFalse(plan['checksums_verified']);self.assertFalse(plan['analysis_enabled'])
    def test_origin_and_host(self):
        self.assertEqual(self.call('/api/public-data/health',headers={'Origin':'https://evil.test'})[0],403)
        self.assertEqual(self.call('/api/public-data/health',headers={'Host':'evil.test'})[0],403)
    def test_invalid_requests(self):
        self.assertEqual(self.call('/api/public-data/resolve',{'accession':'SRR1'}, {'Content-Type':'text/plain'})[0],415)
        self.assertEqual(self.call('/api/public-data/resolve',{'accession':None})[0],400)
        self.assertEqual(self.call('/api/public-data/plan',{'manifest_id':'unknown','selected_runs':['SRR1']})[0],400)
    def test_no_download_endpoint(self):
        self.assertEqual(self.call('/api/public-data/download',{})[0],404)
        self.assertEqual(self.call('/api/public-data/execute',{})[0],404)
    def test_space_checks(self):
        value=s.metadata.manifest(s.metadata.parse_ena(report()),'SRR123')
        plan=s.download_plan(value,['SRR123'],0)
        self.assertTrue(plan['blockers']);self.assertFalse(plan['download_enabled'])
        with self.assertRaises(s.metadata.MetadataError):s.download_plan(value,[],10**12)
    def test_manifest_expiry(self):
        store=s.Store();key=store.put({});store.items[key]=(0,{})
        with self.assertRaises(s.metadata.MetadataError):store.get(key)
    def test_workflow_templates_and_invalid_plan(self):
        status,body=self.call('/api/public-data/workflows/templates')
        self.assertEqual(status,200);self.assertFalse(json.loads(body)['execution_supported'])
        status,body=self.call('/api/public-data/workflows/validate',{'plan':{}})
        self.assertEqual(status,200);self.assertFalse(json.loads(body)['valid'])
    def test_pdf_content_type(self):
        self.assertEqual(self.call('/api/public-data/papers/pdf',{})[0],415)
    def test_processed_download_requires_confirmation(self):
        from test_processed_data import SOFT
        value=s.processed_data.parse_soft(SOFT,'GSE60450');key=self.server.store.put(value)
        status,body=self.call('/api/public-data/processed/download',{'manifest_id':key,'file_id':'0'})
        self.assertEqual(status,400);self.assertIn(b'confirmation',body)

    def test_agent_disabled_and_no_consent(self):
        from unittest.mock import patch
        with patch.dict(s.agent_adapter.os.environ, {}, clear=True):
            status,body=self.call('/api/public-data/agent/status')
            self.assertEqual(status,200);self.assertFalse(json.loads(body)['configured'])
            status,body=self.call('/api/public-data/agent/respond',{'question':'public RNA-seq'})
            self.assertEqual(status,200);self.assertIn(json.loads(body)['status'],['unconfigured','consent_required'])

    def test_context_preview_redacts_and_binds_digest(self):
        from unittest.mock import patch
        value=s.metadata.manifest(s.metadata.parse_ena(report()),'SRR123',selected=['SRR123'])
        value['private_note']='SensitivePatient';key=self.server.store.put(value)
        status,body=self.call('/api/public-data/agent/context-preview',{'context_ids':{'manifest_id':key}})
        self.assertEqual(status,200);preview=json.loads(body)
        self.assertNotIn(b'SensitivePatient',body);self.assertEqual(preview['manifest']['selected_run_count'],1)
        request={'question':'Public context question','consent':True,'expected_provider':'openai',
                 'context_ids':{'manifest_id':key},'context_sha256':'stale','context_consent':True}
        with patch.object(s.agent_adapter,'status',return_value={'provider':'openai'}),patch.object(s.agent_adapter,'respond',return_value={'status':'ok'}) as respond:
            self.assertEqual(self.call('/api/public-data/agent/respond',request)[0],409);respond.assert_not_called()
            request['context_sha256']=preview['snapshot_sha256']
            self.assertEqual(self.call('/api/public-data/agent/respond',request)[0],200)
            self.assertEqual(respond.call_args.kwargs['context']['manifest']['request'],'SRR123')
            self.assertTrue(respond.call_args.kwargs['context_consent'])
    def test_context_rejects_payloads_and_paths(self):
        for payload in [{'context':{'anything':'arbitrary'}}, {'context_ids':{'download_id':'../../secret'}},
                        {'context_ids':{'unexpected':'value'}}]:
            self.assertEqual(self.call('/api/public-data/agent/context-preview',payload)[0],400)
        self.assertEqual(self.call('/api/public-data/agent/respond',{'context':{'raw':'no'}})[0],400)
    def test_workflow_record_is_selectable(self):
        status,body=self.call('/api/public-data/workflows/validate',{'plan':{'version':1}})
        value=json.loads(body);self.assertIn('plan_id',value)
        status,body=self.call('/api/public-data/agent/context-preview',{'context_ids':{'plan_id':value['plan_id']}})
        self.assertEqual(status,200);self.assertFalse(json.loads(body)['plan']['valid'])
    def test_run_plan_preserves_selection_for_context(self):
        _,body=self.call('/api/public-data/resolve',{'accession':'SRR123'});key=json.loads(body)['manifest_id']
        _,body=self.call('/api/public-data/plan',{'manifest_id':key,'selected_runs':['SRR123']})
        selected_key=json.loads(body)['context_manifest_id']
        self.assertEqual(self.server.store.get(selected_key)['selected_runs'],['SRR123'])
        self.assertEqual(self.server.store.get(key)['selected_runs'],[])

    def test_optional_gateway_route(self):
        import emp_gateway as gateway
        old=gateway.PUBLIC_DATA_PORT
        try:
            gateway.PUBLIC_DATA_PORT=8081
            handler=object.__new__(gateway.GatewayHandler);handler.path='/api/public-data/resolve'
            self.assertEqual(handler._target(),('127.0.0.1',8081))
            handler.path='/api/health';self.assertEqual(handler._target(),('127.0.0.1',gateway.API_PORT))
            gateway.PUBLIC_DATA_PORT=0;handler.path='/api/public-data/resolve'
            self.assertEqual(handler._target(),('127.0.0.1',gateway.API_PORT))
        finally:gateway.PUBLIC_DATA_PORT=old

if __name__=='__main__':unittest.main()
