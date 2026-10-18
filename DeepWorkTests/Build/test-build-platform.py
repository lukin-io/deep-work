#!/usr/bin/env python3
"""Native build-platform contract checks with isolated unsupported-host fixtures."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class BuildPlatformTests(unittest.TestCase):
    def test_swift_package_requires_macos_15(self):
        result = subprocess.run(["swift", "package", "dump-package"], cwd=ROOT,
                                check=True, text=True, capture_output=True)
        platforms = json.loads(result.stdout)["platforms"]
        self.assertEqual([(item["platformName"], item["version"]) for item in platforms],
                         [("macos", "15.0")])

    def test_application_declares_macos_15(self):
        with (ROOT / "DeepWork/Resources/Info.plist").open("rb") as stream:
            self.assertEqual(plistlib.load(stream)["LSMinimumSystemVersion"], "15.0")

    def test_xcode_debug_and_release_target_only_apple_silicon(self):
        result = subprocess.run(["plutil", "-convert", "json", "-o", "-",
                                 str(ROOT / "DeepWork.xcodeproj/project.pbxproj")],
                                check=True, text=True, capture_output=True)
        project = json.loads(result.stdout)
        objects = project["objects"]
        configuration_list = objects[objects[project["rootObject"]]["buildConfigurationList"]]
        configurations = [objects[item] for item in configuration_list["buildConfigurations"]]
        self.assertEqual({item["name"] for item in configurations}, {"Debug", "Release"})
        for configuration in configurations:
            with self.subTest(configuration=configuration["name"]):
                settings = configuration["buildSettings"]
                self.assertEqual(settings["MACOSX_DEPLOYMENT_TARGET"], "15.0")
                self.assertEqual(settings["ARCHS"], "arm64")
                self.assertEqual(settings["EXCLUDED_ARCHS"], "x86_64")

    def test_unsupported_host_fails_before_compilation_or_bundle_changes(self):
        with tempfile.TemporaryDirectory(prefix="deep-work-platform-") as temporary:
            fixture = Path(temporary)
            scripts = fixture / "scripts"
            scripts.mkdir()
            build_script = scripts / "build-app.sh"
            build_script.write_bytes((ROOT / "scripts/build-app.sh").read_bytes())
            commands = fixture / "commands"
            commands.mkdir()
            swift_called = fixture / "swift-was-called"
            swift = commands / "swift"
            swift.write_text('#!/bin/bash\ntouch "$TEST_SWIFT_CALLED"\nexit 91\n')
            swift.chmod(0o755)
            uname = commands / "uname"
            for architecture in ["x86_64", "i386", "unknown"]:
                with self.subTest(architecture=architecture):
                    uname.write_text(f"#!/bin/bash\nprintf '%s\\n' '{architecture}'\n")
                    uname.chmod(0o755)
                    environment = dict(os.environ, PATH=str(commands) + os.pathsep + os.environ["PATH"],
                                       TEST_SWIFT_CALLED=str(swift_called))
                    result = subprocess.run(["bash", str(build_script)], cwd=fixture,
                                            env=environment, text=True, capture_output=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("requires Apple Silicon", result.stderr)
                    self.assertFalse(swift_called.exists())
                    self.assertFalse((fixture / ".build").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
