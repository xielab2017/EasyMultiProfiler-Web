import gzip
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).parents[1]/'scripts'))
import processed_data as p

URL='https://ftp.ncbi.nlm.nih.gov/geo/series/GSE60nnn/GSE60450/suppl/counts.tsv'
SOFT='!Series_title = Synthetic fixture\n!Series_sample_id = GSM1\n!Series_supplementary_file = '+URL+'\n'

class ProcessedTests(unittest.TestCase):
    def test_soft(self):
        result=p.parse_soft(SOFT,'GSE60450');self.assertEqual(result['files'][0]['data_type'],'unknown')
        self.assertEqual(result['sample_accessions'],['GSM1'])
    def test_bad_url(self):
        for url in [URL.replace('ftp.ncbi.nlm.nih.gov','evil.test'),URL.replace('GSE60450/suppl','GSE60451/suppl'),URL+'?x=1',URL.replace('counts.tsv','../counts.tsv')]:
            with self.assertRaises(p.m.MetadataError):p.safe_url(url,'GSE60450')
    def inspect(self,data,name='x.tsv'):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'file';path.write_bytes(data);return p.inspect_table(path,name)
    def test_count_like_not_confirmed(self):
        out=self.inspect(b'gene\tLength\ts1\ts2\na\t100\t1\t2\nb\t200\t3\t4\n')
        self.assertEqual(out['data_type'],'count_like_unverified');self.assertFalse(out['deseq2_ready'])
        self.assertEqual(out['column_labels'],['s1','s2']);self.assertEqual(out['excluded_annotation_columns'],['Length'])
    def test_normalized(self):
        self.assertEqual(self.inspect(b'gene,s1,s2\na,1.5,3.2\n')['data_type'],'noninteger_or_transformed_not_raw_count_input')
    def test_bad_and_nonfinite(self):
        for data in [b'gene\ts1\na\tNaN\n',b'gene\ts1\na\tfoo\n']:
            self.assertEqual(self.inspect(data)['data_type'],'unknown')
        self.assertEqual(self.inspect(b'not gzip','x.tsv.gz')['inspection'],'unreadable_or_invalid_compression')
    def test_gzip(self):
        out=self.inspect(gzip.compress(b'gene\ts1\na\t2\n'),'x.tsv.gz')
        self.assertEqual(out['feature_rows'],1)
    def test_no_archive_extraction(self):
        self.assertEqual(self.inspect(b'anything','matrix.tar.gz')['inspection'],'unsupported_format_not_extracted')
    def test_sample_mapping_not_positional(self):
        text='!Sample_geo_accession\tGSM2\tGSM1\n!Sample_description\ts2\ts1\n!Sample_title\tsecond\tfirst\n'
        records=p.parse_sample_annotations(text)
        out=p.match_samples(['s1','s2','missing'],records)
        self.assertEqual(out[0]['sample']['accession'],'GSM1')
        self.assertEqual(out[2]['status'],'unmatched_or_ambiguous')
    def test_confirmation_and_size(self):
        value=p.parse_soft(SOFT,'GSE60450')
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(p.m.MetadataError):p.download(value,'0',d)
            with self.assertRaises(p.m.MetadataError):p.download(value,'0',d,True)
    def test_download_and_hash(self):
        data=b'gene\ts1\na\t1\n';value=p.parse_soft(SOFT,'GSE60450');value['files'][0]['bytes']=len(data)
        class Opener:
            def open(self,*args,**kwargs):return io.BytesIO(data)
        with tempfile.TemporaryDirectory() as d,patch.object(p,'build_opener',return_value=Opener()):
            result=p.download(value,'0',d,True)
            self.assertEqual(result['sha256'],p.hashlib.sha256(data).hexdigest())
            self.assertFalse(result['publisher_checksum_verified'])
            self.assertEqual(result['inspection']['data_type'],'count_like_unverified')
    def test_short_download_cleans_partial(self):
        value=p.parse_soft(SOFT,'GSE60450');value['files'][0]['bytes']=100
        class Opener:
            def open(self,*args,**kwargs):return io.BytesIO(b'too short')
        with tempfile.TemporaryDirectory() as d,patch.object(p,'build_opener',return_value=Opener()):
            with self.assertRaises(p.m.MetadataError):p.download(value,'0',d,True)
            self.assertEqual(list(Path(d).iterdir()),[])

if __name__=='__main__':unittest.main()
