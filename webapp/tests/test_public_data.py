"""Offline synthetic fixtures. Passing tests do not imply live-service access."""
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('public_data', Path(__file__).parents[1] / 'scripts/public_data.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)


def report(**changes):
    row = dict(zip(m.FIELDS, ['SRR123', 'PRJNA123', 'SAMN123', 'SRX123', 'Homo sapiens', 'RNA-Seq', 'PAIRED',
        'ftp.sra.ebi.ac.uk/vol1/fastq/SRR123/SRR123_1.fastq.gz;ftp.sra.ebi.ac.uk/vol1/fastq/SRR123/SRR123_2.fastq.gz',
        'a'*32+';'+'b'*32, '10;20']))
    row.update(changes)
    return '\t'.join(m.FIELDS)+'\n'+'\t'.join(row[k] for k in m.FIELDS)+'\n'


class FakeClient:
    def __init__(self, responses):
        self.responses = iter(responses); self.sources = []; self.calls = []
    def get(self, base, params):
        self.calls.append((base, params))
        return next(self.responses)


class PublicDataTests(unittest.TestCase):
    def test_accessions(self):
        for value in ['GSE123', 'SRR123', 'ERR123', 'DRR123', 'SRP123', 'PRJNA123', 'PRJEB123']:
            self.assertEqual(m.accession(value.lower()), value)
        for value in ['https://evil.test', 'SRR1&x=2', '10.1000/doi', '../SRR1']:
            with self.assertRaises(m.MetadataError): m.accession(value)

    def test_parse_and_selection(self):
        runs = m.parse_ena(report())
        self.assertEqual(len(runs[0]['files']), 2)
        self.assertTrue(runs[0]['files'][0]['url'].startswith('https://'))
        self.assertEqual(m.manifest(runs, 'SRR123')['selected_bytes'], 0)
        self.assertEqual(m.manifest(runs, 'SRR123', selected=['SRR123'])['selected_bytes'], 30)
        with self.assertRaises(m.MetadataError): m.manifest(runs, '', selected=['SRR999'])

    def test_missing_links_not_claimed_restricted(self):
        runs = m.parse_ena(report(fastq_ftp='', fastq_md5='', fastq_bytes=''))
        self.assertEqual(runs[0]['availability'], 'no_public_fastq_links')
        self.assertTrue(runs[0]['warnings'])

    def test_invalid_reports(self):
        for text in ['<html>error</html>', report(fastq_md5='a'*32), report(fastq_bytes='-1;20'),
                     report(fastq_md5='x'*32+';'+'b'*32), report(run_accession='arbitrary'),
                     report()+report().split('\n')[1]+'\n']:
            with self.subTest(text=text):
                with self.assertRaises(m.MetadataError): m.parse_ena(text)

    def test_download_url_allowlist(self):
        for value in ['https://evil.test/a.fastq.gz', 'https://ftp.sra.ebi.ac.uk.evil.test/vol1/fastq/a.fastq.gz',
                      'https://user@ftp.sra.ebi.ac.uk/vol1/fastq/a.fastq.gz', 'http://ftp.sra.ebi.ac.uk/vol1/fastq/a.fastq.gz',
                      'https://ftp.sra.ebi.ac.uk/vol1/fastq/../a.fastq.gz', 'https://ftp.sra.ebi.ac.uk/vol1/fastq/a.fastq.gz?token=x']:
            with self.assertRaises(m.MetadataError): m.safe_fastq_url(value)

    def test_exact_geo_mapping(self):
        records = [{'accession': 'GSE123', 'relations': [{'relationtype': 'SRA', 'targetobject': 'SRP123'},
                    {'relationtype': 'SRA', 'targetobject': 'https://evil.test'}]}]
        self.assertEqual(m.geo_targets(records, 'GSE123'), ['SRP123'])
        with self.assertRaises(m.MetadataError): m.geo_targets(records, 'GSE999')

    def test_resolve_run(self):
        client = FakeClient([report()])
        out = m.resolve(client, 'SRR123', ['SRR123'])
        self.assertEqual(out['selected_bytes'], 30)
        self.assertFalse(out['download_enabled'])
        self.assertEqual(client.calls[0][0], m.ENA)

    def test_geo_to_ena(self):
        client = FakeClient([json.dumps({'esearchresult': {'idlist': ['123']}}),
            json.dumps({'result': {'123': {'accession': 'GSE123', 'title': 'Synthetic test fixture',
               'extrelations': [{'relationtype': 'SRA', 'targetobject': 'SRP123'}]}}}), report()])
        out = m.resolve(client, 'GSE123')
        self.assertEqual(out['runs'][0]['run_accession'], 'SRR123')
        self.assertEqual(client.calls[2][1]['accession'], 'SRP123')

    def test_empty_search(self):
        self.assertEqual(m.geo_search(FakeClient(['{"esearchresult":{"idlist":[]}}']), 'test'), [])
        with self.assertRaises(m.MetadataError): m.geo_search(FakeClient([]), 'test', 999)

    def test_malformed_upstream(self):
        for payload in [{}, {'esearchresult': None}, {'esearchresult': {'ERROR': 'bad query'}},
                        {'esearchresult': {'idlist': [], 'errorlist': {'phrasesnotfound': ['x']}}}]:
            with self.assertRaises(m.MetadataError):
                m.geo_search(FakeClient([json.dumps(payload)]), 'test')
        for summary in [{'result': None}, {'result': {'1': {'accession': None}}},
                        {'result': {'1': {'accession': 'GSE1', 'extrelations': None}}}]:
            with self.assertRaises(m.MetadataError):
                m.geo_search(FakeClient(['{"esearchresult":{"idlist":["1"]}}', json.dumps(summary)]), 'test')
        for url in ['https://ftp.sra.ebi.ac.uk:bad/vol1/fastq/a.fastq.gz',
                    'https://ftp.sra.ebi.ac.uk/vol1/fastq/%2e%2e/a.fastq.gz']:
            with self.assertRaises(m.MetadataError): m.safe_fastq_url(url)

    def test_geo_alias_dedup_and_conflict(self):
        responses = [json.dumps({'esearchresult': {'idlist': ['123']}}),
            json.dumps({'result': {'123': {'accession': 'GSE123', 'extrelations': [
                {'relationtype': 'SRA', 'targetobject': 'SRP123'},
                {'relationtype': 'BioProject', 'targetobject': 'PRJNA123'}]}}})]
        self.assertEqual(len(m.resolve(FakeClient(responses + [report(), report()]), 'GSE123')['runs']), 1)
        with self.assertRaises(m.MetadataError):
            m.resolve(FakeClient(responses + [report(), report(scientific_name='Mus musculus')]), 'GSE123')

    def test_metadata_errors(self):
        for text in ['oops', '[]', '{"error":"rate limited"}']:
            with self.assertRaises(m.MetadataError): m.metadata_json(text)
        with self.assertRaises(m.MetadataError): m.Client().get('http://127.0.0.1/', {})
        with self.assertRaises(m.MetadataError): m.NoRedirect().redirect_request()


if __name__ == '__main__': unittest.main()
