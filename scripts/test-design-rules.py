#!/usr/bin/env python3
"""Check that policy violations fail CI without touching the real source tree."""
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class DesignPolicyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for relative in ['Sources/DonyClean', 'AGENTS.md', '.agents/skills/donyhome-design',
                         'docs/design-system.md', 'scripts/install-design-skill.sh']:
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            if (ROOT / relative).is_dir():
                shutil.copytree(ROOT / relative, destination)
            else:
                shutil.copy2(ROOT / relative, destination)

    def check_policy(self):
        return subprocess.run(['python3', str(ROOT / 'scripts/check-design-rules.py'),
                               '--root', str(self.root)], capture_output=True, text=True)

    def test_current_controls_pass(self):
        result = self.check_policy()
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_new_screen_cannot_add_text_dropdown(self):
        (self.root / 'Sources/DonyClean/NewScreen.swift').write_text(
            'let filter = DonyMenuButton(title: "filter") {}\n')
        result = self.check_policy()
        self.assertEqual(result.returncode, 1)
        self.assertIn('text dropdowns are forbidden', result.stdout)

    def test_native_picker_cannot_bypass_resource_controls(self):
        path = self.root / 'Sources/DonyClean/PerformanceView.swift'
        with path.open('a') as output:
            output.write('\nlet native = Picker("scope", selection: $scope) {}\n')
        result = self.check_policy()
        self.assertEqual(result.returncode, 1)
        self.assertIn('native dropdowns are forbidden', result.stdout)

    def test_portable_skill_cannot_drift(self):
        (self.root / '.agents/skills/donyhome-design/references/design-system.md').write_text('stale')
        result = self.check_policy()
        self.assertEqual(result.returncode, 1)
        self.assertIn('portable reference differs', result.stdout)

    def test_native_reference_image_must_ship_with_skill(self):
        (self.root / '.agents/skills/donyhome-design/assets/development-reference.png').unlink()
        result = self.check_policy()
        self.assertEqual(result.returncode, 1)
        self.assertIn('broken portable reference', result.stdout)


if __name__ == '__main__':
    unittest.main()
