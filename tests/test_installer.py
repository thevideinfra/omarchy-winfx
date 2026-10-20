import os
from pathlib import Path
import subprocess
import unittest


class InstallerTests(unittest.TestCase):
    def run_backend(self, missing='', install_status='0'):
        script = (Path(__file__).parents[1] / 'install.sh').read_text()
        block = script.split('if (( backend )); then\n', 1)[1].split('\nif [[ $SRC', 1)[0]
        harness = '''
set -euo pipefail
backend=1
pacman() { [[ " $MISSING " != *" ${@: -1} "* ]]; }
sudo() { printf 'INSTALL sudo %s\\n' "$*"; return "$INSTALL_STATUS"; }
pkexec() { printf 'INSTALL pkexec %s\\n' "$*"; return "$INSTALL_STATUS"; }
hyprpm() { printf 'BACKEND %s\\n' "$*"; [[ $1 != list ]] || echo HyprWindowShade; }
if (( backend )); then
'''
        return subprocess.run(['bash', '-c', harness + block], text=True,
                              capture_output=True, env={**os.environ, 'MISSING': missing,
                                                        'INSTALL_STATUS': install_status})

    def test_installs_missing_packages_before_backend(self):
        result = self.run_backend('hyprpm cpio')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('INSTALL pkexec pacman -S --needed hyprpm cpio', result.stdout)
        self.assertLess(result.stdout.index('INSTALL'), result.stdout.index('BACKEND update'))

    def test_checks_build_dependencies_even_when_hyprpm_exists(self):
        result = self.run_backend('base-devel pkgconf')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('INSTALL pkexec pacman -S --needed base-devel pkgconf', result.stdout)

    def test_skips_install_when_dependencies_present(self):
        result = self.run_backend()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('INSTALL', result.stdout)
        self.assertIn('BACKEND update', result.stdout)

    def test_failed_package_install_stops_before_backend(self):
        result = self.run_backend('hyprpm', '1')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('BACKEND', result.stdout)
