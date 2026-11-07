"""Offline mocked tests only. No actual provider or metadata requests."""
import json
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import agent_adapter as agent


def call(name='validate_plan', args=None, ident='call_1'):
    return {'role': 'assistant', 'content': None, 'tool_calls': [
        {'id': ident, 'type': 'function', 'function': {'name': name,
         'arguments': json.dumps({'plan': {}} if args is None else args)}}]}


class AgentTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {'OPENAI_API_KEY': 'test-secret-only',
            'EMP_AGENT_ALLOW_MODEL_REQUEST': '1', 'EMP_AGENT_MODEL': 'gpt-4.1-mini'}, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_status_no_secret(self):
        self.assertEqual(agent.status()['status'], 'ready')
        self.assertNotIn('test-secret-only', json.dumps(agent.status()))

    @patch.object(agent, '_request')
    def test_gates(self, req):
        for consent in (False, 'true', 1):
            self.assertEqual(agent.respond('hello', consent)['status'], 'consent_required')
        os.environ['EMP_AGENT_ALLOW_MODEL_REQUEST'] = 'true'
        self.assertEqual(agent.respond('hello', True)['status'], 'unconfigured')
        os.environ['EMP_AGENT_ALLOW_MODEL_REQUEST'] = '1'
        del os.environ['OPENAI_API_KEY']
        self.assertEqual(agent.respond('hello', True)['status'], 'unconfigured')
        req.assert_not_called()

    @patch.object(agent, '_request')
    def test_invalid_questions(self, req):
        for value in ('', 'a' * 4001, {}, 'test-secret-only'):
            self.assertEqual(agent.respond(value, True)['status'], 'invalid_request')
        req.assert_not_called()

    @patch.object(agent, '_request')
    def test_plan_tool_and_untrusted_wrapper(self, req):
        req.side_effect = [call(), {'role': 'assistant', 'content': 'Plan is not valid.'}]
        result = agent.respond('Validate this plan', True)
        self.assertEqual(result['status'], 'ok')
        self.assertFalse(result['tool_results'][0]['result']['valid'])
        self.assertFalse(result['execution_supported'])
        self.assertIn('untrusted_data', req.call_args.args[0][-1]['content'])
        self.assertIn('UNTRUSTED DATA', req.call_args.args[0][0]['content'])

    @patch.object(agent, '_run')
    @patch.object(agent, '_request')
    def test_reject_unknown_and_bad_schema(self, req, run):
        for value in (call('run_code', {'code': 'bad'}), call('search_metadata', {'term': 'x', 'limit': True}),
                      call('resolve_accession', {'accession': 'https://evil.test'}),
                      call('validate_plan', {'plan': {}, 'code': 'bad'})):
            req.return_value = value
            self.assertEqual(agent.respond('hello', True)['status'], 'error')
        run.assert_not_called()

    @patch.object(agent, '_run', return_value={'metadata': 'ok'})
    @patch.object(agent, '_request')
    def test_round_bound(self, req, run):
        req.side_effect = [call(ident='call_' + str(i)) for i in range(4)]
        self.assertEqual(agent.respond('hello', True)['status'], 'round_limit')
        self.assertEqual(run.call_count, 3)
        self.assertEqual(req.call_count, 4)
        self.assertTrue(req.call_args.kwargs['final_only'])

    @patch.object(agent, '_request', side_effect=RuntimeError('test-secret-only provider body'))
    def test_error_redacted(self, req):
        self.assertNotIn('test-secret-only', json.dumps(agent.respond('hello', True)))

    def test_bounded_result(self):
        self.assertTrue(agent._bounded({'x': 'a' * 13000}, '')['truncated'])
        self.assertEqual(agent._bounded({'x': 'test-secret-only'}, 'test-secret-only')['x'], '[REDACTED]')

    @patch.object(agent.public_data, 'geo_search', return_value=[])
    def test_search_dispatch(self, search):
        self.assertEqual(agent._run('search_metadata', {'term': 'public study', 'limit': 2}), [])
        self.assertEqual(search.call_args.args[1:], ('public study', 2))

    @patch.object(agent.public_data, 'resolve', return_value={'runs': []})
    def test_resolve_dispatch(self, resolve):
        self.assertEqual(agent._run('resolve_accession', {'accession': 'SRR123'}), {'runs': []})
        self.assertEqual(resolve.call_args.args[1], 'SRR123')

    @patch.object(agent, 'build_opener')
    def test_fixed_endpoint_transport(self, opener):
        response = opener.return_value.open.return_value.__enter__.return_value
        response.read.return_value = json.dumps({'choices': [{'finish_reason': 'stop',
            'message': {'role': 'assistant', 'content': 'ok'}}]}).encode()
        result = agent.respond('hello', True)
        self.assertEqual(result['status'], 'ok')
        request = opener.return_value.open.call_args.args[0]
        self.assertEqual(request.full_url, 'https://api.openai.com/v1/chat/completions')
        self.assertEqual(request.get_method(), 'POST')
        self.assertEqual(json.loads(request.data)['max_tokens'], 1200)

    @patch.object(agent.paper_sources, 'search_pubmed', return_value={'articles': []})
    @patch.object(agent.paper_sources, 'fetch_pubmed_abstract', return_value={'accessions': []})
    @patch.object(agent.processed_data, 'discover', return_value={'files': []})
    def test_paper_processed_dispatch(self, discover, abstract, search):
        self.assertEqual(agent._run('search_papers', {'term': 'public study', 'limit': 2}), {'articles': []})
        search.assert_called_once_with('public study', 2)
        self.assertEqual(agent._run('fetch_paper_abstract', {'pmid': '123'}), {'accessions': []})
        abstract.assert_called_once_with('123')
        self.assertEqual(agent._run('discover_processed', {'accession': 'GSE123'}), {'files': []})
        discover.assert_called_once_with('GSE123')

    @patch.object(agent, '_run')
    @patch.object(agent, '_request')
    def test_paper_processed_schema(self, req, run):
        invalid = [('search_papers', {'term': 'x', 'limit': 11}),
                   ('search_papers', {'term': 'x', 'limit': True}),
                   ('search_papers', {'term': 'x\\n', 'limit': 1}),
                   ('search_papers', {'term': 'x', 'limit': 1, 'url': 'bad'}),
                   ('fetch_paper_abstract', {'pmid': 123}),
                   ('fetch_paper_abstract', {'pmid': '0'}),
                   ('fetch_paper_abstract', {'pmid': '1234567890123'}),
                   ('fetch_paper_abstract', {'pmid': 'https://evil.test'}),
                   ('discover_processed', {'accession': 'SRR123'}),
                   ('discover_processed', {'accession': 'GSE123', 'download': True}),
                   ('discover_processed', {'accession': 'GSE1/../../x'})]
        # Explicit control character; reject before any metadata dispatch.
        invalid[2] = ('search_papers', {'term': 'x' + chr(10), 'limit': 1})
        for name, args in invalid:
            req.return_value = call(name, args)
            self.assertEqual(agent.respond('hello', True)['status'], 'error', (name, args))
        run.assert_not_called()

    @patch.object(agent.processed_data, 'download')
    @patch.object(agent.paper_sources, 'extract_pdf')
    @patch.object(agent.processed_data, 'discover', return_value={'files': [{'name': 'matrix.tsv'}]})
    @patch.object(agent.paper_sources, 'fetch_pubmed_abstract', return_value={'accessions': [{'accession': 'GSE123', 'verified': False}]})
    @patch.object(agent.paper_sources, 'search_pubmed', return_value={'articles': [{'pmid': '123'}]})
    @patch.object(agent, '_request')
    def test_mocked_article_to_matrix_loop(self, req, search, abstract, discover, pdf, download):
        req.side_effect = [call('search_papers', {'term': 'public study', 'limit': 1}, 'call_1'),
                           call('fetch_paper_abstract', {'pmid': '123'}, 'call_2'),
                           call('discover_processed', {'accession': 'GSE123'}, 'call_3'),
                           {'role': 'assistant', 'content': 'Matrix metadata found; contents unverified.'}]
        result = agent.respond('Find public study matrix metadata', True)
        self.assertEqual(result['status'], 'ok')
        self.assertEqual(len(result['tool_results']), 3)
        search.assert_called_once_with('public study', 1)
        abstract.assert_called_once_with('123')
        discover.assert_called_once_with('GSE123')
        pdf.assert_not_called()
        download.assert_not_called()
        self.assertTrue(req.call_args.kwargs['final_only'])

    @patch.object(agent.repository_files, 'pride_files', return_value={'files': [{'name': 'table.csv'}], 'downloaded': False, 'matrix_verified': False})
    @patch.object(agent, '_request')
    def test_pride_metadata_tool_roundtrip(self, req, pride):
        req.side_effect = [call('discover_pride_files', {'accession': 'PXD006933'}, 'call_1'),
                           {'role': 'assistant', 'content': 'Candidate table requires review.'}]
        result = agent.respond('Find PRIDE tables', True)
        self.assertEqual(result['status'], 'ok')
        pride.assert_called_once_with('PXD006933')
        self.assertEqual(len(result['tool_results']), 1)

    @patch.object(agent.repository_files, 'pride_files')
    @patch.object(agent, '_request')
    def test_pride_tool_rejects_invalid_accession(self, req, pride):
        req.return_value = call('discover_pride_files', {'accession': 'PXD006933/../../x'})
        self.assertEqual(agent.respond('Find files', True)['status'], 'error')
        pride.assert_not_called()

    @patch.object(agent, 'build_opener')
    def test_nvidia_fixed_endpoint_and_no_cross_provider_key(self, opener):
        os.environ['EMP_AGENT_PROVIDER'] = 'nvidia'
        os.environ['NVIDIA_API_KEY'] = 'mock-nvidia-secret'
        del os.environ['EMP_AGENT_MODEL']
        response = opener.return_value.open.return_value.__enter__.return_value
        response.read.return_value = json.dumps({'choices': [{'finish_reason': 'stop',
            'message': {'role': 'assistant', 'content': 'ok'}}]}).encode()
        self.assertEqual(agent.status()['model'], agent.NVIDIA_MODEL)
        self.assertEqual(agent.status()['provider'], 'nvidia')
        self.assertFalse(agent.status()['live_verified'])
        self.assertIn('NVIDIA', agent.respond('hello')['answer'])
        opener.assert_not_called()
        self.assertEqual(agent.respond('hello', True)['status'], 'ok')
        request = opener.return_value.open.call_args.args[0]
        self.assertEqual(request.full_url, 'https://integrate.api.nvidia.com/v1/chat/completions')
        self.assertEqual(request.get_header('Authorization'), 'Bearer mock-nvidia-secret')
        self.assertNotIn('test-secret-only', str(request.headers))
        payload = json.loads(request.data)
        self.assertEqual(payload['model'], agent.NVIDIA_MODEL)
        self.assertEqual(payload['chat_template_kwargs'], {'enable_thinking': False})
        self.assertEqual(payload['tool_choice'], 'auto')
        self.assertEqual(payload['tools'], agent.TOOLS)
        self.assertNotIn('parallel_tool_calls', payload)

    @patch.object(agent, '_request')
    def test_provider_selection_fails_closed(self, req):
        for provider in ('custom', 'NVIDIA', 'https://evil.test', ''):
            os.environ['EMP_AGENT_PROVIDER'] = provider
            self.assertEqual(agent.respond('hello', True)['status'], 'unconfigured')
            self.assertEqual(agent.status()['provider'], 'unsupported')
        os.environ['EMP_AGENT_PROVIDER'] = 'nvidia'
        del os.environ['EMP_AGENT_MODEL']
        # OpenAI credential must not be used for NVIDIA.
        self.assertEqual(agent.respond('hello', True)['status'], 'unconfigured')
        os.environ['NVIDIA_API_KEY'] = 'mock-nvidia-secret'
        os.environ['EMP_AGENT_MODEL'] = 'unapproved/model'
        self.assertEqual(agent.respond('hello', True)['status'], 'unconfigured')
        del os.environ['EMP_AGENT_MODEL']
        del os.environ['EMP_AGENT_ALLOW_MODEL_REQUEST']
        self.assertFalse(agent.status()['allow_model_request'])
        self.assertEqual(agent.respond('hello', True)['status'], 'unconfigured')
        req.assert_not_called()

    @patch.object(agent, '_request')
    def test_nvidia_mocked_tool_roundtrip(self, req):
        os.environ['EMP_AGENT_PROVIDER'] = 'nvidia'
        os.environ['NVIDIA_API_KEY'] = 'mock-nvidia-secret'
        del os.environ['EMP_AGENT_MODEL']
        req.side_effect = [call(), {'role': 'assistant', 'content': 'Plan needs metadata.'}]
        result = agent.respond('Validate an empty plan', True)
        self.assertEqual(result['status'], 'ok')
        self.assertEqual(req.call_args.kwargs['provider'], 'nvidia')
        self.assertFalse(result['tool_results'][0]['result']['valid'])
        self.assertNotIn('mock-nvidia-secret', json.dumps(result))

    @patch.object(agent, '_request')
    def test_context_consent_gate(self, req):
        for permission in (False, 'true', 1):
            result = agent.respond('Review', True, context={'plan': {}}, context_consent=permission)
            self.assertEqual(result['status'], 'context_consent_required')
            self.assertEqual(result['audit'], [])
        self.assertEqual(agent.respond('Review', True, context={'path': '/tmp/x'},
                                      context_consent=True)['status'], 'invalid_request')
        req.assert_not_called()

    @patch.object(agent, '_run')
    @patch.object(agent, '_request')
    def test_selected_context_roundtrip(self, req, run):
        from test_agent_context import snapshot
        req.side_effect = [call('get_selected_context', {}), {'role': 'assistant', 'content': 'Inspection only.'}]
        result = agent.respond('Review selected data', True, context=snapshot(), context_consent=True)
        self.assertEqual(result['status'], 'ok')
        self.assertEqual(result['audit'][0]['tool'], 'get_selected_context')
        self.assertEqual(result['audit'][0]['status'], 'ok')
        self.assertGreaterEqual(result['audit'][0]['duration_ms'], 0)
        self.assertNotIn('SECRET', json.dumps(req.call_args.args[0]))
        self.assertNotIn('/private', json.dumps(result))
        run.assert_not_called()

    @patch.object(agent, '_request')
    def test_no_selected_context(self, req):
        req.side_effect = [call('get_selected_context', {}), {'role': 'assistant', 'content': 'No selection.'}]
        result = agent.respond('What is selected?', True)
        self.assertEqual(result['tool_results'][0]['result']['selected_sections'], [])
        self.assertEqual(result['status'], 'ok')

    @patch.object(agent, '_run')
    @patch.object(agent, '_request')
    def test_context_arbitrary_arguments_and_audit(self, req, run):
        for name, args in [('get_selected_context', {'id': 'other-record'}),
                           ('get_selected_context', {'path': '/private/secret'}),
                           ('/private/SECRET', {})]:
            req.return_value = call(name, args)
            result = agent.respond('Review', True)
            self.assertEqual(result['status'], 'error')
            self.assertEqual(result['audit'][0]['status'], 'rejected')
            self.assertNotIn('SECRET', json.dumps(result['audit']))
            self.assertNotIn('other-record', json.dumps(result['audit']))
        run.assert_not_called()

    @patch.object(agent, '_run', side_effect=RuntimeError('secret raw content'))
    @patch.object(agent, '_request', return_value=call())
    def test_tool_failure_audit(self, req, run):
        result = agent.respond('Review', True)
        self.assertEqual(result['audit'][0]['status'], 'error')
        self.assertEqual(set(result['audit'][0]), {'tool', 'status', 'duration_ms'})
        self.assertNotIn('secret raw content', json.dumps(result))

    def test_redirect_refused(self):
        with self.assertRaises(agent.AdapterError):
            agent._NoRedirect().redirect_request(None)


if __name__ == '__main__':
    unittest.main()
