"""Real local HTTP and PDF extraction; a fixture provider, never an external LLM."""
import base64
import http.client
import io
import json
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).parents[1]/'scripts'))
import agent_attachments as attachments
import agent_adapter as agent
import model_settings
import public_data_server

PNG=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aY9sAAAAASUVORK5CYII=')
def pdf_fixture():
    from pypdf import PdfWriter
    from pypdf.generic import DecodedStreamObject,DictionaryObject,NameObject
    writer=PdfWriter();page=writer.add_blank_page(width=612,height=792)
    font=DictionaryObject({NameObject('/Type'):NameObject('/Font'),NameObject('/Subtype'):NameObject('/Type1'),NameObject('/BaseFont'):NameObject('/Helvetica')})
    page[NameObject('/Resources')]=DictionaryObject({NameObject('/Font'):DictionaryObject({NameObject('/F1'):font})})
    stream=DecodedStreamObject();stream.set_data(b'BT /F1 12 Tf 40 700 Td (Synthetic paper: six samples; GSE60450.) Tj ET');page[NameObject('/Contents')]=writer._add_object(stream)
    out=io.BytesIO();writer.write(out);return out.getvalue()

class AttachmentTests(unittest.TestCase):
    def test_validation_expiry_and_payload_bounds(self):
        with self.assertRaises(ValueError):attachments.put(b'<svg/>','image/png','unsafe.png')
        for value in [['bad'],[{}],[True],['a'*32]*2]:
            with self.assertRaises(ValueError):attachments.prepare(value)
        row=attachments.put(PNG,'image/png','plot.png');blocks,summary=attachments.prepare([row['id']])
        self.assertTrue(blocks[0]['image_url']['url'].startswith('data:image/png;base64,'));self.assertNotIn('body',summary[0])
        with patch.object(attachments.time,'monotonic',return_value=attachments.time.monotonic()+1900):
            with self.assertRaises(ValueError):attachments.prepare([row['id']])

    def test_pdf_extracted_text_and_truncation_are_explicit(self):
        row=attachments.put(pdf_fixture(),'application/pdf','paper.pdf');self.assertEqual(row['pages_inspected'],1)
        blocks,_=attachments.prepare([row['id']]);self.assertIn('[Page 1]',blocks[0]['text']);self.assertIn('GSE60450',blocks[0]['text']);self.assertNotIn('chat_text',row)

    def test_real_http_upload_to_multimodal_provider_transport(self):
        requests=[]
        class Provider(BaseHTTPRequestHandler):
            def log_message(self,*args):pass
            def do_POST(self):
                body=json.loads(self.rfile.read(int(self.headers['Content-Length'])));requests.append(body)
                if self.path=='/messages':result={'stop_reason':'end_turn','content':[{'type':'text','text':'Fixture Anthropic response'}]}
                else:result={'choices':[{'finish_reason':'stop','message':{'role':'assistant','content':'Fixture provider received attachments; no analysis executed.'}}]}
                raw=json.dumps(result).encode();self.send_response(200);self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
        provider=ThreadingHTTPServer(('127.0.0.1',0),Provider);threading.Thread(target=provider.serve_forever,daemon=True).start()
        service=public_data_server.make_server(0);threading.Thread(target=service.serve_forever,daemon=True).start()
        try:
            def call(path,raw,headers):
                conn=http.client.HTTPConnection('127.0.0.1',service.server_port);conn.request('POST','/api/public-data/'+path,body=raw,headers=headers);response=conn.getresponse();data=json.loads(response.read());conn.close();self.assertEqual(response.status,200,data);return data
            image=call('agent/attachments',PNG,{'Content-Type':'image/png','X-Attachment-Name':'figure.png'})
            pdf=call('agent/attachments',pdf_fixture(),{'Content-Type':'application/pdf','X-Attachment-Name':'paper.pdf'})
            cfg=model_settings.configure({'provider':'custom','model':'fixture-vision','api_key':'','base_url':f'http://127.0.0.1:{provider.server_port}/v1','enabled':True})
            answer=call('agent/respond',json.dumps({'question':'Read the attached figure and paper.','consent':True,'expected_provider':'custom','expected_config_revision':cfg['config_revision'],'attachment_ids':[image['id'],pdf['id']]}).encode(),{'Content-Type':'application/json'})
            self.assertEqual(answer['status'],'ok');content=requests[-1]['messages'][1]['content'];self.assertTrue(any(x['type']=='image_url' for x in content));self.assertTrue(any('Synthetic paper' in x.get('text','') for x in content));self.assertEqual(len(answer['attachments']),2)
            agent._request([{'role':'user','content':content}],'fixture-key','fixture-model',provider='claude',protocol='anthropic',endpoint=f'http://127.0.0.1:{provider.server_port}/messages')
            image_block=next(x for x in requests[-1]['messages'][0]['content'] if x['type']=='image');self.assertEqual(image_block['source']['media_type'],'image/png')
        finally:model_settings.clear();service.shutdown();service.server_close();provider.shutdown();provider.server_close()
