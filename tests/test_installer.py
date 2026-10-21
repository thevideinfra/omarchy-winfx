import os
from pathlib import Path
import re
import subprocess
import unittest

SCRIPT = (Path(__file__).parents[1] / 'install.sh').read_text()


class InstallerTests(unittest.TestCase):
    def run_backend(self, missing='', install_status='0'):
        block = SCRIPT.split('if (( backend )); then\n', 1)[1].split('\nif [[ $SRC', 1)[0]
        harness = '''
set -euo pipefail
backend=1
pacman() { [[ " $MISSING " != *" ${@: -1} "* ]]; }
sudo() { printf 'INSTALL sudo %s\\n' "$*"; return "$INSTALL_STATUS"; }
pkexec() { printf 'INSTALL pkexec %s\\n' "$*"; return "$INSTALL_STATUS"; }
if (( backend )); then
'''
        return subprocess.run(['bash', '-c', harness + block], text=True,
                              capture_output=True, env={**os.environ, 'MISSING': missing,
                                                        'INSTALL_STATUS': install_status})

    def test_installs_only_the_missing_build_tools(self):
        result = self.run_backend('git pkgconf')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('INSTALL pkexec pacman -S --needed pkgconf git', result.stdout)
        self.assertNotIn('base-devel', result.stdout)

    def test_skips_install_when_the_tools_are_present(self):
        result = self.run_backend()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('INSTALL', result.stdout)

    def test_a_failed_install_stops_and_points_at_a_stale_package_database(self):
        result = self.run_backend('git', '1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('pacman -Syu', result.stderr)

    def test_the_installer_needs_neither_hyprpm_nor_a_hyprland_clone(self):
        # One sudo prompt at most: the backend builds against the headers the hyprland
        # package already installed, so hyprpm, cmake and cpio are not needed.
        self.assertIsNone(re.search(r'^\s*hyprpm\b', SCRIPT, re.M))
        for package in ('hyprpm', 'cmake', 'cpio'):
            self.assertNotIn(package, SCRIPT.split('for package in', 1)[1].split(';', 1)[0])


if __name__ == '__main__':
    unittest.main()
