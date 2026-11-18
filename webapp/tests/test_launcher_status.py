"""Check startup messages and exit status with no services, downloads, or browser."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class LauncherStatusTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="EMP launcher ")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.scripts = self.root / "webapp" / "scripts"
        self.scripts.mkdir(parents=True)
        for name in ("Run-EMP-Web-Mac.command", "Install-EMP-Web-Mac.command", "install.sh", "DESCRIPTION"):
            shutil.copy(ROOT / name, self.root)
        for name in ("launch_emp_web.sh", "bootstrap_and_start.sh", "check_runtime.R"):
            shutil.copy(ROOT / "webapp" / "scripts" / name, self.scripts)
        (self.scripts / "check_prerequisites.sh").write_text("exit 0\n")
        (self.scripts / "resolve_rscript.sh").write_text('echo "$EMPI_RSCRIPT"\n')
        fake_r = self.root / "fake Rscript"
        fake_r.write_text("#!/bin/sh\nexit 1\n")
        fake_r.chmod(0o755)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(("EMP_", "EMPI_"))}
        self.env["EMPI_RSCRIPT"] = str(fake_r)
        # Fail if a caller attempts installation or opens the browser.
        (self.scripts / "install").mkdir()
        for name in ("install_runtime.sh", "install/install_r.sh", "install/install_system_deps.sh"):
            (self.scripts / name).write_text('touch "$PWD/side-effect"; exit 19\n')
        opener = self.root / "open"
        opener.write_text('#!/bin/sh\ntouch "$PWD/side-effect"\n')
        opener.chmod(0o755)
        self.env["PATH"] = str(self.root) + os.pathsep + self.env["PATH"]

    def run_entry(self, name, *args):
        return subprocess.run(["bash", str(self.root / name), *args], env=self.env,
                              stdin=subprocess.DEVNULL, capture_output=True, text=True)

    def test_finder_entry_points_only_preflight_in_dry_run(self):
        (self.scripts / "start_local.sh").write_text(
            '[[ "$1" == "--dry-run" ]] || exit 29\necho "preflight completed"\n')
        for name in ("Run-EMP-Web-Mac.command", "Install-EMP-Web-Mac.command"):
            with self.subTest(name=name):
                result = self.run_entry(name, "--dry-run")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("preflight completed", result.stdout)
                self.assertNotIn("web is running", result.stdout.lower())
                self.assertNotIn("已在后台运行", result.stdout)
                self.assertFalse((self.root / "side-effect").exists())

    def test_skipped_install_preserves_start_failure(self):
        self.env["EMP_SKIP_INSTALL"] = "1"
        (self.scripts / "start_local.sh").write_text('echo "API failed"; exit 23\n')
        result = self.run_entry("Run-EMP-Web-Mac.command")
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertIn("skipping R package installation", result.stdout)
        self.assertIn("API failed", result.stdout)
        self.assertNotIn("install will run", result.stdout)
        self.assertNotIn("已在后台运行", result.stdout)
        self.assertFalse((self.root / "side-effect").exists())

    def test_matching_package_skips_install_and_old_package_triggers_install(self):
        resolver = ROOT / 'webapp/scripts/resolve_rscript.sh'
        result = subprocess.run(['bash', str(resolver)], capture_output=True, text=True)
        if result.returncode:
            self.skipTest('A supported R is required for installed-package version checks')
        rscript = result.stdout.strip()
        packages = ('EasyMultiProfiler', 'plumber', 'jsonlite', 'base64enc', 'callr', 'digest', 'ps')
        library = self.root / '.local_run/R_libs'
        library.mkdir(parents=True)
        for name in packages:
            package = self.root / name
            package.mkdir()
            (package / 'DESCRIPTION').write_text(
                f'Package: {name}\nVersion: 1.0.0\nTitle: Launcher Fixture\n'
                'Description: Test fixture.\nAuthor: Test\nMaintainer: Test <test@example.com>\nLicense: MIT\n')
            (package / 'NAMESPACE').touch()
        subprocess.run([
            rscript, '--vanilla', '-e',
            'args <- commandArgs(TRUE); install.packages(args[-1], lib=args[1], repos=NULL, type="source")',
            str(library), *packages,
        ], cwd=self.root, check=True, capture_output=True)
        self.env['EMPI_RSCRIPT'] = rscript
        (self.scripts / 'start_local.sh').write_text('echo "checked startup"\n')
        checkout = self.root / 'DESCRIPTION'
        checkout.write_text('Package: EasyMultiProfiler\nVersion: 1.0.0\n')
        result = self.run_entry('Run-EMP-Web-Mac.command')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('checked startup', result.stdout)
        self.assertFalse((self.root / 'side-effect').exists())
        checkout.write_text('Package: EasyMultiProfiler\nVersion: 1.1.0\n')
        result = self.run_entry('Run-EMP-Web-Mac.command')
        self.assertEqual(result.returncode, 19, result.stdout + result.stderr)
        self.assertIn('loaded 1.0.0, checkout requires 1.1.0', result.stdout)
        self.assertTrue((self.root / 'side-effect').exists())

    def test_standalone_installer_propagates_download_failure(self):
        (self.scripts / "bootstrap_and_start.sh").unlink()
        curl = self.root / "curl"
        curl.write_text("#!/bin/sh\nexit 22\n")
        curl.chmod(0o755)
        result = self.run_entry("Install-EMP-Web-Mac.command")
        self.assertEqual(result.returncode, 22)
        self.assertIn("Installation failed", result.stdout)
