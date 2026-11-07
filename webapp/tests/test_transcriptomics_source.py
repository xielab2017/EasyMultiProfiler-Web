"""Static guard only. The corresponding base-R contract requires Rscript."""
from pathlib import Path
import unittest

class TranscriptomicsSourceTests(unittest.TestCase):
    def test_no_silent_method_fallback(self):
        text=(Path(__file__).parents[1]/'backend/helpers/workflow_transcriptomics.R').read_text()
        body=text.split('tx_run_differential <-',1)[1].split('tx_run_gsea <-',1)[0]
        self.assertEqual(body.count('run_diff('),1)
        self.assertIn('method_use, group_var',body)
        self.assertNotIn('"limma"',body)

if __name__=='__main__':unittest.main()
