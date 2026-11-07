"""Static R-installer contract checks; these are not R execution tests."""
from pathlib import Path
import re
import unittest

class RuntimeContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source=(Path(__file__).parents[1]/'scripts/install_runtime.R').read_text()
    def test_web_dependencies_explicit(self):
        block=re.search(r'cran_always <- c\(([^\n]+)\)',self.source).group(1)
        for package in ['plumber','jsonlite','base64enc']:
            self.assertIn('"'+package+'"',block)
    def test_one_project_library_setup(self):
        self.assertEqual(self.source.count('.libPaths(c('),1)
        self.assertIn('file.path(emp_root, ".local_run", "R_libs")',self.source)
        self.assertIn('file.access(runtime_lib, 2L)',self.source)
    def test_no_emp_smoke_contract(self):
        self.assertIn('needed <- c(if (!no_emp) "EasyMultiProfiler"',self.source)

if __name__=='__main__':unittest.main()
