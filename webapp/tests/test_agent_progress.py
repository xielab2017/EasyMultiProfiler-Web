import sys
from pathlib import Path
import unittest
sys.path.insert(0,str(Path(__file__).parents[1]/'scripts'))
import agent_progress as progress
import agent_adapter
from unittest.mock import patch

class ProgressTests(unittest.TestCase):
    def test_events_are_bounded_inert_and_do_not_store_reasoning_or_payloads(self):
        import uuid
        run_id=uuid.uuid4().hex
        progress.start(run_id)
        for _ in range(60):progress.emit(run_id,'tool_finished',tool='fill_page_fields',status='ok',question='PRIVATE',reasoning='HIDDEN',arguments={'key':'SECRET'})
        row=progress.get(run_id)
        self.assertEqual(len(row['events']),48)
        self.assertEqual(set(row['events'][0]),{'stage','tool','status'})
        self.assertNotIn('PRIVATE',str(row));self.assertIsNone(progress.get('../x'))
        with self.assertRaises(ValueError):progress.start(run_id)
        with self.assertRaises(ValueError):progress.start('unsafe')

    def test_adapter_emits_real_tool_stages_and_keeps_reasoning_out_of_progress(self):
        import uuid,json
        run_id=uuid.uuid4().hex
        call={'role':'assistant','content':None,'tool_calls':[{'id':'call_fixture','type':'function','function':{'name':'fill_page_fields','arguments':json.dumps({'fields':{'matrix-accession':'GSE60450'}})}}]}
        with patch.object(agent_adapter,'_settings',return_value=('fixture-key','fixture-model',True,'openai')),patch.object(agent_adapter,'_request',side_effect=[call,{'role':'assistant','content':'<think>PRIVATE REASONING</think>已准备页面参数，等待本地页面校验。'}]):
            response=agent_adapter.respond('Prepare a page field',True,_runtime_override={},run_id=run_id)
        self.assertEqual(response['status'],'ok')
        events=progress.get(run_id)['events']
        self.assertEqual([e['stage'] for e in events],['provider_request','tool_started','tool_finished','completed'])
        self.assertNotIn('PRIVATE',str(events)+response['answer'])
        self.assertFalse(response['tool_results'][0]['result']['execution_performed'])
