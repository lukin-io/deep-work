"""Fixture-tool regressions; native signing/launch is checked separately."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class UIAcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        (self.root / 'scripts').mkdir()
        self.script = self.root / 'scripts/prepare-ui-acceptance.sh'
        shutil.copy2(ROOT / 'scripts/prepare-ui-acceptance.sh', self.script)
        self.source = self.root / '.build/Deep Work.app'
        (self.source / 'Contents/MacOS').mkdir(parents=True)
        self.binary = self.source / 'Contents/MacOS/DeepWork'
        self.binary.write_text('debug fixture')
        self.binary.chmod(0o755)
        (self.source / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'app.deepwork.mac', 'CFBundleExecutable': 'DeepWork',
            'CFBundleDisplayName': 'Deep Work',
            'CFBundleURLTypes': [{'CFBundleURLSchemes': ['deepwork']}],
        }))
        self.outputs = self.root / 'temporary outputs'; self.outputs.mkdir()
        commands = self.root / 'commands'; commands.mkdir()
        for name, script in {
            'nm': '#!/bin/sh\nif grep -q "debug fixture" "$2"; then echo DebugAcceptanceOptions; fi\n',
            'ditto': '#!/bin/sh\ncp -R "$1" "$2"\n',
            'codesign': '#!/bin/sh\nexit 0\n',
        }.items():
            path = commands / name; path.write_text(script); path.chmod(0o755)
        self.environment = {**os.environ, 'TMPDIR': str(self.outputs), 'PATH': str(commands) + os.pathsep + os.environ['PATH']}

    def tearDown(self):
        self.temporary.cleanup()

    def run_script(self, *arguments):
        return subprocess.run([str(self.script), *arguments], env=self.environment, text=True, capture_output=True)

    def test_each_fixture_has_unique_identity_and_relaunch_safe_data(self):
        before = (self.source / 'Contents/Info.plist').read_bytes()
        identities = []
        for _ in range(2):
            result = self.run_script('dark', 'clipboard-failure', '320')
            self.assertEqual(result.returncode, 0, result.stderr)
            app = Path(result.stdout.strip())
            info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
            identities.append((info['CFBundleIdentifier'], info['CFBundleExecutable']))
            self.assertNotEqual(info['CFBundleIdentifier'], 'app.deepwork.mac')
            self.assertEqual(info['CFBundleDisplayName'], 'Deep Work Acceptance')
            self.assertTrue((app / 'Contents/MacOS' / info['CFBundleExecutable']).is_file())
            self.assertNotIn('CFBundleURLTypes', info)
            self.assertEqual(info['LSEnvironment'], {
                'DEEP_WORK_DATA_DIR': str(app.parent / 'data'), 'DEEP_WORK_APPEARANCE': 'dark',
                'DEEP_WORK_CLIPBOARD_FAILURE': '1', 'DEEP_WORK_WINDOW_WIDTH': '320',
            })
        self.assertNotEqual(identities[0], identities[1])
        self.assertEqual((self.source / 'Contents/Info.plist').read_bytes(), before)

    def test_release_or_stripped_binary_is_refused_before_creating_fixture(self):
        self.binary.write_text('release fixture')
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unstripped Debug', result.stderr)
        self.assertEqual(list(self.outputs.iterdir()), [])

    def test_invalid_options_fail_before_creating_fixture(self):
        for arguments in [('unknown',), ('light', 'unknown'), ('light', 'normal', '319'),
                          ('light', 'normal', '1601'), ('light', 'normal', '320.5'), ('light', 'normal', '18446744073709551936')]:
            with self.subTest(arguments=arguments):
                self.assertNotEqual(self.run_script(*arguments).returncode, 0)
        self.assertEqual(list(self.outputs.iterdir()), [])

    def test_missing_build_fails_with_actionable_command(self):
        self.binary.unlink()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('./scripts/build-app.sh', result.stderr)
        self.assertEqual(list(self.outputs.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
