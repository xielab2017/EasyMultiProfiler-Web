"""Exercise the actual EMP HTTP handler and model transport on private fixture ports."""
import concurrent.futures
import http.client
import json
from pathlib import Path
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import agent_adapter
import model_settings
import public_data_server


class Provider(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        self.server.received.append(payload)
        content = next(m['content'] for m in payload['messages'] if m['role'] == 'user')
        question = content[0]['text'] if isinstance(content, list) else content
        if question == 'delayed action':
            self.server.entered.set()
            self.server.release.wait(8)
        message = {'role': 'assistant', 'content': 'Fixture reply'}
        if question in ('page action', 'delayed action'):
            message['tool_calls'] = [{'id': 'action1', 'type': 'function', 'function': {
                'name': 'request_page_action', 'arguments': '{"action":"refresh_tasks"}'}}]
        body = json.dumps({'choices': [{'message': message, 'finish_reason': 'tool_calls' if 'tool_calls' in message else 'stop'}]}).encode()
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class ChatContractHTTP(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.model = ThreadingHTTPServer(('127.0.0.1', 0), Provider)
        cls.emp = public_data_server.make_server(0)
        for service in (cls.model, cls.emp):
            worker = threading.Thread(target=service.serve_forever, daemon=True)
            worker.start()
            cls.addClassCleanup(worker.join)
            cls.addClassCleanup(service.server_close)
            cls.addClassCleanup(service.shutdown)

    def setUp(self):
        self.model.received = []
        self.model.entered = threading.Event()
        self.model.release = threading.Event()
        self.addCleanup(model_settings.clear)
        self.config = {'provider': 'custom', 'model': 'fixture', 'enabled': True,
                       'base_url': f'http://127.0.0.1:{self.model.server_port}/v1'}
        self.revision = self.api('config', self.config)['config_revision']

    def api(self, operation, data=None, mime='application/json'):
        conn = http.client.HTTPConnection('127.0.0.1', self.emp.server_port, timeout=12)
        try:
            body = json.dumps(data).encode() if data is not None and mime == 'application/json' else data
            conn.request('POST' if body is not None else 'GET', '/api/public-data/agent/' + operation,
                         body, headers={'Content-Type': mime})
            response = conn.getresponse()
            self.assertEqual(response.status, 200)
            return json.load(response)
        finally:
            conn.close()

    def question(self, question, **kwargs):
        return self.api('respond', dict(question=question, consent=True, expected_provider='custom',
                                        expected_config_revision=self.revision, **kwargs))

    def test_each_mode_and_format_with_attached_evidence(self):
        attachment = self.api('attachments', b'# Synthetic Markdown evidence', 'text/markdown')
        status = self.api('status')
        self.assertEqual(status['chat_contract_version'], 2)
        for mode in ('chat', 'agent'):
            for output in ('answer', 'comparison', 'summary', 'note'):
                with self.subTest(mode=mode, output=output):
                    answer = self.question('Describe.', chat_mode=mode, output_type=output, attachment_ids=[attachment['id']])
                    self.assertEqual(answer['status'], 'ok')
                    payload = self.model.received[-1]
                    self.assertEqual(bool(payload.get('tools')), mode == 'agent')
                    self.assertIn(agent_adapter.OUTPUT_TYPES[output], payload['messages'][0]['content'])
                    self.assertIn('Synthetic Markdown evidence', json.dumps(payload['messages']))
        self.assertEqual(self.question('page action', chat_mode='chat')['status'], 'error')
        self.assertEqual(self.question('page action')['status'], 'ok')  # legacy requester
        self.assertTrue(self.api('status')['live_tools_verified'])
        self.assertEqual(self.question('Ordinary follow-up.', chat_mode='chat')['status'], 'ok')
        self.assertTrue(self.api('status')['live_tools_verified'])

    def test_inflight_success_cannot_verify_reloaded_identical_profile(self):
        with concurrent.futures.ThreadPoolExecutor(1) as pool:
            first = pool.submit(self.question, 'delayed action', chat_mode='agent')
            try:
                self.assertTrue(self.model.entered.wait(6))
                new_status = self.api('config', self.config)
                self.assertGreater(new_status['config_revision'], self.revision)
            finally:
                self.model.release.set()
            self.assertEqual(first.result(10)['status'], 'ok')
        self.assertFalse(self.api('status')['live_verified'])
        self.assertEqual(self.question('Old approval.', chat_mode='agent')['status'], 'configuration_changed')
        self.assertEqual(len(self.model.received), 1)

    def test_attachment_receipt_matches_each_submitted_excerpt(self):
        items = [self.api('attachments', b'x' * 22000, 'text/plain') for _ in range(3)]
        ids = [item['id'] for item in items]
        combined = self.question('Three documents.', chat_mode='chat', attachment_ids=ids)
        self.assertEqual(combined['status'], 'ok')
        self.assertEqual([(m['chars_sent'], m['truncated']) for m in combined['attachments']], [(16000, True)] * 3)
        content = self.model.received[-1]['messages'][1]['content']
        for block in content[1:]:
            self.assertEqual(len(block['text'].splitlines()[-1]), 16000)
        solo = self.question('One document.', chat_mode='chat', attachment_ids=ids[:1])
        self.assertEqual(solo['attachments'][0]['chars_sent'], 22000)
        self.assertFalse(solo['attachments'][0]['truncated'])
