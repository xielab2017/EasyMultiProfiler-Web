import io,json,sys,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import repository_files as repositories

class Response(io.BytesIO):
    def __enter__(self):return self
    def __exit__(self,*args):self.close()

class RepositoryTests(unittest.TestCase):
    @patch.object(repositories,'build_opener')
    def test_only_original_pride_project_tables_are_exposed(self,opener):
        base='ftp://ftp.pride.ebi.ac.uk/pride/data/archive/2022/03/PXD006933/'
        def row(name,url):return {'fileName':name,'fileSizeBytes':123,'fileCategory':{'value':'RESULT'},'publicFileLocations':[{'value':url}]}
        records=[row('counts.tsv',base+'counts.tsv'),row('reads.fastq.gz',base+'reads.fastq.gz'),row('evil.csv','https://evil.example/evil.csv'),row('other.csv',base+'../PXD006933/other.csv')]
        opener.return_value.open.return_value=Response(json.dumps(records).encode())
        result=repositories.pride_files('PXD006933')
        self.assertEqual([f['name'] for f in result['files']],['counts.tsv'])
        self.assertEqual(result['files'][0]['url'],'https://ftp.pride.ebi.ac.uk/pride/data/archive/2022/03/PXD006933/counts.tsv')
        self.assertFalse(result['matrix_verified']);self.assertFalse(result['downloaded'])
        with self.assertRaises(repositories.RepositoryError):repositories.pride_files('PXD006933/../../')

if __name__=='__main__':unittest.main()
