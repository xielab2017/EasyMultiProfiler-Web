"""Shell resolver regressions for ambiguous PATH and user-specified Python."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
RESOLVER = ROOT / 'webapp/scripts/resolve_python.sh'


class PythonDiscoveryTests(unittest.TestCase):
    def test_finds_compatible_second_python_on_path(self):
        with tempfile.TemporaryDirectory(prefix="EMP project's python ") as tmp:
            root = Path(tmp)
            scripts = root / 'webapp/scripts'
            scripts.mkdir(parents=True)
            resolver = scripts / RESOLVER.name
            shutil.copyfile(RESOLVER, resolver)
            old = root / 'first/python3'
            old.parent.mkdir()
            old.write_text('#!/bin/sh\nexit 1\n')
            old.chmod(0o755)
            good = root / 'second/python3'
            good.parent.mkdir()
            good.symlink_to(sys.executable)
            env = dict(os.environ, HOME=tmp,
                       PATH=os.pathsep.join([str(old.parent), str(good.parent), os.environ['PATH']]))
            for key in ('EMPI_PYTHON', 'CONDA_PREFIX', 'VIRTUAL_ENV'):
                env.pop(key, None)

            def resolve():
                return subprocess.run(['bash', str(resolver)], env=env, capture_output=True, text=True)

            result = resolve()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), str(good))
            local = root / '.local_run/metadata_venv/bin/python'
            local.parent.mkdir(parents=True)
            local.symlink_to(sys.executable)
            self.assertEqual(resolve().stdout.strip(), str(local))
            env['EMPI_PYTHON'] = str(old)
            result = resolve()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(str(old), result.stderr)


if __name__ == '__main__':
    unittest.main()
