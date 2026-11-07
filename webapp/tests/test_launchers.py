"""Isolated launcher checks; no installation or public-network execution."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class LauncherTests(unittest.TestCase):
    def test_bash_syntax(self):
        for script in list(ROOT.rglob('*.sh')) + list(ROOT.glob('*.command')):
            if '.git' in script.parts or '.local_run' in script.parts:
                continue
            with self.subTest(script=str(script)):
                subprocess.run(['bash', '-n', str(script)], check=True, capture_output=True)

    def test_metadata_check(self):
        result = subprocess.run([sys.executable, str(ROOT / 'webapp/scripts/launch_metadata.py'), '--check'], capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        self.assertTrue(data['ready'])
        self.assertFalse(data['r']['required_for_metadata'])
        self.assertEqual(data['host'], '127.0.0.1')
        self.assertIn('pypdf', data['optional'])

    def test_quoted_path_and_default_dry_run(self):
        with tempfile.TemporaryDirectory(prefix="EMP project's ") as folder:
            root = Path(folder)
            scripts = root / 'webapp/scripts'
            scripts.mkdir(parents=True)
            shutil.copy(ROOT / 'webapp/scripts/start_local.sh', scripts)
            shutil.copy(ROOT / 'webapp/scripts/process_identity.sh', scripts)
            fake_r = root / 'fake Rscript'
            fake_r.write_text('#!/bin/sh\nexit 0\n')
            fake_r.chmod(0o755)
            env = {k: v for k, v in os.environ.items() if not k.startswith(('EMP_', 'EMPI_', 'API_', 'WEB_', 'GATEWAY_'))}
            env.update(EMP_DRY_RUN='1', EMPI_PYTHON=sys.executable, EMPI_RSCRIPT=str(fake_r))
            result = subprocess.run(['bash', str(scripts / 'start_local.sh')], env=env, capture_output=True, text=True, check=True)
            self.assertIn('API 127.0.0.1:8000; Web 127.0.0.1:8080; Funnel false', result.stdout)
            self.assertFalse((root / '.local_run').exists())
            env['API_PORT'] = 'garbage'
            result = subprocess.run(['bash', str(scripts / 'start_local.sh')], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Invalid port', result.stderr)
            env['API_PORT'] = '8000'
            env['EMPI_RSCRIPT'] = str(root / 'missing Rscript')
            result = subprocess.run(['bash', str(scripts / 'start_local.sh')], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Rscript not found', result.stderr)

    def test_metadata_shell_wrapper(self):
        result = subprocess.run(['bash', str(ROOT / 'Start-EMP-Metadata.command'), '--check'], env=dict(os.environ, EMPI_PYTHON=sys.executable), capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(result.stdout)['mode'], 'metadata-only')

    def test_pid_identity_is_checkout_specific_without_killing(self):
        helper = ROOT / 'webapp/scripts/process_identity.sh'
        root = "/tmp/EMP project's copy"
        cases = [
            (f"Rscript {root}/webapp/backend/run_api.R", True),
            (f'python "{root}/webapp/scripts/static_server.py" 8080', True),
            ("Rscript /tmp/another/webapp/backend/run_api.R", False),
            (f"Rscript /prefix{root}/webapp/backend/run_api.R", False),
            (f"Rscript {root}/webapp/backend/run_api.R.backup", False),
            ("Rscript webapp/backend/run_api.R", False),
            ("", False),
        ]
        for command, expected in cases:
            with self.subTest(command=command):
                result = subprocess.run(['bash', '-c', 'source "$1"; emp_command_belongs_to_repo "$2" "$3"', '_', str(helper), command, root])
                self.assertEqual(result.returncode == 0, expected)
        for name in ('start_local_windows.ps1', 'stop_local_windows.ps1'):
            source = (ROOT / 'webapp/scripts' / name).read_text(encoding='utf-8-sig')
            self.assertIn('Test-EMPProcessOwnership -CommandLine $identity.CommandLine -Root $Root', source)

    def test_installer_regressions(self):
        source = (ROOT / 'webapp/scripts/install/install_system_deps.sh').read_text()
        self.assertIn('install_with_dnf()', source)
        self.assertLess(source.index('if ! emp_should_auto_install; then'), source.index('os="$(emp_detect_os)"'))
        r_source = (ROOT / 'webapp/scripts/install/install_r.sh').read_text()
        self.assertIn('/Resources/bin"', r_source)
        self.assertNotIn('-allowUntrusted', r_source)
        self.assertNotIn('Release.gpg', r_source)
        self.assertNotIn('fc38.x86_64.rpm', r_source)

    def test_windows_handoff_is_not_shell_interpolation(self):
        for name in ('bootstrap_and_start.ps1', 'launch_emp_web.ps1'):
            source = (ROOT / 'webapp/scripts' / name).read_text(encoding='utf-8-sig')
            self.assertNotIn('& bash -c', source)
        source = (ROOT / 'webapp/scripts/start_local_windows.ps1').read_text(encoding='utf-8-sig')
        self.assertNotIn('Stop-EMPListenersOnPorts -Ports', source)

if __name__ == '__main__':
    unittest.main()
