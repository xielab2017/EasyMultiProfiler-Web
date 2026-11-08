import sys,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from version_source import app_version
from sync_app_version import sync_release
class VersionTests(unittest.TestCase):
 def test_version_changes_from_description_without_rewriting_ui_sources(self):
  with tempfile.TemporaryDirectory() as folder:
   p=Path(folder)/'DESCRIPTION';p.write_text('Package: fixture\nVersion: 9.2.0\n');self.assertEqual(app_version(p),'9.2.0')
   p.write_text('Package: fixture\nVersion: 9.3.1\n');self.assertEqual(app_version(p),'9.3.1')
   p.write_text('Package: fixture\n');self.assertRaises(ValueError,app_version,p)
 def test_sync_updates_ui_metadata_and_current_readme_without_rewriting_history(self):
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder);(root/'DESCRIPTION').write_text('Version: 9.3.0\n')
   (root/'webapp/frontend/js').mkdir(parents=True)
   (root/'webapp/frontend/index.html').write_text('<title>EMP v9.2.0</title>')
   (root/'webapp/frontend/js/guide.js').write_text('"Welcome v9.1.0"')
   (root/'README.md').write_text('# EasyMultiProfiler Web · v9.2.0\n> **Version:** `9.2.0`\n## v9.2.0\n[notes](docs/RELEASE_NOTES_v9.2.0.md)\n## v9.1.3 — historical\n')
   self.assertTrue(sync_release(root,check=True));self.assertFalse((root/'webapp/frontend/version.json').exists())
   sync_release(root);self.assertFalse(sync_release(root,check=True))
   self.assertIn('9.3.0',(root/'webapp/frontend/version.json').read_text())
   self.assertEqual((root/'webapp/frontend/js/guide.js').read_text(),'"Welcome v9.3.0"')
   readme=(root/'README.md').read_text();self.assertIn('**Version:** `9.3.0`',readme);self.assertIn('RELEASE_NOTES_v9.3.0.md',readme);self.assertIn('## v9.1.3 — historical',readme)
