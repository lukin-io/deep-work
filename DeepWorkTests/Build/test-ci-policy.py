#!/usr/bin/env python3
"""CI gate regressions and isolated toolchain fixtures; not hosted-run evidence.

Ruby's bundled Psych parses the real workflow without a third-party Python
dependency. GitHub's macOS images include Ruby. No fixture changes Xcode selection.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/release.yml"
VERIFY = ROOT / "scripts/verify-ci-environment.sh"
MOCK_TOOL = r'''#!/usr/bin/env python3
import os, pathlib, sys
tool = pathlib.Path(sys.argv[0]).name
if os.environ.get("TEST_FAIL_TOOL") == tool:
    raise SystemExit("Fixture tool failed")
if tool == "uname":
    print(os.environ.get("TEST_SYSTEM", "Darwin") if sys.argv[1] == "-s" else os.environ.get("TEST_ARCH", "arm64"))
elif tool == "sw_vers":
    print(os.environ.get("TEST_MACOS", "15.7.9"))
elif tool == "xcodebuild":
    print("Xcode " + os.environ.get("TEST_XCODE", "16.4") + "\nBuild version fixture")
elif tool == "swift":
    print(os.environ.get("TEST_PATH_SWIFT", "Apple Swift version fixture\nTarget: arm64-apple-macosx15.0"))
elif tool == "xcrun":
    if sys.argv[1:] == ["--find", "swiftc"]:
        print(os.environ.get("TEST_SWIFTC", os.environ["DEVELOPER_DIR"] + "/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"))
    elif sys.argv[1:] == ["--sdk", "macosx", "--show-sdk-version"]:
        print(os.environ.get("TEST_SDK", "15.5"))
    elif sys.argv[1:] == ["swift", "--version"]:
        print("Apple Swift version fixture\nTarget: arm64-apple-macosx15.0")
    else:
        raise SystemExit("Unexpected fixture xcrun arguments")
else:
    raise SystemExit("Unexpected fixture tool")
'''


class CIEnvironmentTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="deep-work-ci-environment-")
        self.addCleanup(self.temporary.cleanup)
        self.fixture = Path(self.temporary.name)
        self.commands = self.fixture / "commands"
        self.commands.mkdir()
        for tool in ["uname", "sw_vers", "xcodebuild", "xcrun", "swift"]:
            executable = self.commands / tool
            executable.write_text(MOCK_TOOL)
            executable.chmod(0o755)
        self.developer = self.fixture / "Xcode_16.4.app/Contents/Developer"
        self.developer.mkdir(parents=True)
        self.environment = {key: value for key, value in os.environ.items() if not key.startswith("TEST_")}
        self.environment.update(PATH=str(self.commands) + os.pathsep + os.environ["PATH"],
                                DEVELOPER_DIR=str(self.developer))

    def check(self, message=None, arguments=("15", "16.4", "15.5"), **environment):
        result = subprocess.run(["bash", str(VERIFY), *arguments], cwd=ROOT,
                                env=dict(self.environment, **environment), text=True, capture_output=True)
        if message is None:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Verified CI:", result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn(message, result.stderr)
            self.assertNotIn("Verified CI:", result.stdout)

    def test_explicit_minimum_and_current_toolchains_are_accepted(self):
        self.check()
        developer = self.fixture / "Xcode_26.6.app/Contents/Developer"
        developer.mkdir(parents=True)
        self.check(arguments=("26", "26.6", "26.5"), DEVELOPER_DIR=str(developer),
                   TEST_MACOS="26.6.2", TEST_XCODE="26.6", TEST_SDK="26.5")

    def test_missing_arguments_fail(self):
        self.check("usage:", arguments=())

    def test_invalid_versions_fail(self):
        for arguments in [("", "16.4", "15.5"), ("15", "latest", "15.5"),
                          ("15", "16.4\n", "15.5"), ("15", "16.4", "$(id)")]:
            with self.subTest(arguments=arguments):
                self.check("explicit numeric versions", arguments=arguments)

    def test_non_macos_fails(self):
        self.check("macOS runner is required", TEST_SYSTEM="Linux")

    def test_intel_runner_fails(self):
        self.check("Apple Silicon runner is required", TEST_ARCH="x86_64")

    def test_wrong_macos_version_fails(self):
        self.check("expected macOS 15, found 26.6.2", TEST_MACOS="26.6.2")

    def test_missing_or_noninstalled_developer_directory_fails(self):
        for directory in ["", str(self.fixture / "missing/Xcode_16.4.app/Contents/Developer")]:
            with self.subTest(directory=directory):
                self.check("DEVELOPER_DIR must select", DEVELOPER_DIR=directory)

    def test_unversioned_developer_directory_fails(self):
        self.check("DEVELOPER_DIR must select", DEVELOPER_DIR=str(self.fixture))

    def test_different_selected_xcode_fails(self):
        self.check("selected Xcode does not match", TEST_XCODE="26.6")

    def test_swift_compiler_outside_selected_xcode_fails(self):
        self.check("Swift compiler is outside", TEST_SWIFTC="/Library/Developer/CommandLineTools/usr/bin/swiftc")

    def test_wrong_sdk_fails(self):
        self.check("expected SDK 15.5, found 26.5", TEST_SDK="26.5")

    def test_path_swift_must_match_xcode(self):
        self.check("PATH Swift differs", TEST_PATH_SWIFT="Other Swift toolchain")

    def test_failed_tool_does_not_report_success(self):
        for tool in ["uname", "sw_vers", "xcodebuild", "xcrun", "swift"]:
            with self.subTest(tool=tool):
                self.check("Fixture tool failed", TEST_FAIL_TOOL=tool)


class WorkflowPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # 'on' is quoted in YAML so YAML 1.1 parsers retain its string key.
        result = subprocess.run(["ruby", "-rjson", "-ryaml", "-e",
                                 "puts JSON.generate(YAML.safe_load(File.read(ARGV[0]), aliases: false))",
                                 str(WORKFLOW)], check=True, text=True, capture_output=True)
        cls.workflow = json.loads(result.stdout)
        cls.jobs = cls.workflow["jobs"]

    def test_only_main_pr_main_push_and_version_tags_trigger_workflow(self):
        self.assertEqual(self.workflow["on"], {"pull_request": {"branches": ["main"]},
                                             "push": {"branches": ["main"], "tags": ["v*"]}})

    def test_only_superseded_pull_requests_are_cancelled(self):
        self.assertEqual(self.workflow["concurrency"], {
            "group": "release-${{ github.ref }}",
            "cancel-in-progress": "${{ github.event_name == 'pull_request' }}"})

    def test_minimum_and_current_ga_macos_run_all_native_and_xcode_checks(self):
        tests = self.jobs["native-tests"]
        self.assertIs(tests["strategy"]["fail-fast"], False)
        self.assertEqual(tests["runs-on"], "${{ matrix.runner }}")
        self.assertEqual(tests["strategy"]["matrix"]["include"], [
            {"runner": "macos-15", "macos": "15", "xcode": "16.4", "sdk": "15.5"},
            {"runner": "macos-26", "macos": "26", "xcode": "26.6", "sdk": "26.5"}])
        commands = "\n".join(step.get("run", "") for step in tests["steps"])
        for required in ["./scripts/test.sh", "test-ci-policy.py", "test-publish-release.py",
                         "-strict-concurrency=complete", "-warnings-as-errors", "plutil -lint",
                         "xcodebuild", "-configuration Release", "platform=macOS,arch=arm64"]:
            self.assertIn(required, commands)
        self.assertNotIn("continue-on-error", tests)
        self.assertFalse(any(step.get("continue-on-error", False) for step in tests["steps"]))

    def test_every_job_checks_explicit_toolchain_before_build_or_publication(self):
        for name, job in self.jobs.items():
            with self.subTest(job=name):
                self.assertIn("DEVELOPER_DIR", job["env"])
                self.assertEqual(job["steps"][1]["run"].split()[0], "./scripts/verify-ci-environment.sh")
        for name in ["package", "publish"]:
            self.assertEqual(self.jobs[name]["runs-on"], "macos-15")
            self.assertEqual(self.jobs[name]["env"]["DEVELOPER_DIR"],
                             "/Applications/Xcode_16.4.app/Contents/Developer")

    def test_publication_waits_for_package_and_both_matrix_results(self):
        self.assertEqual(self.jobs["package"]["needs"], "native-tests")
        self.assertEqual(self.jobs["publish"]["needs"], "package")
        self.assertNotIn("if", self.jobs["package"])
        self.assertEqual(self.jobs["publish"]["if"],
                         "github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v') && github.repository == 'lukin-io/deep-work'")

    def test_only_publication_receives_write_permission(self):
        self.assertEqual(self.workflow["permissions"], {"contents": "read"})
        for name, job in self.jobs.items():
            self.assertEqual(job.get("permissions", self.workflow["permissions"]),
                             {"contents": "write" if name == "publish" else "read"})

    def test_actions_are_immutable_and_checkouts_do_not_persist_credentials(self):
        for job in self.jobs.values():
            for step in job["steps"]:
                if "uses" in step:
                    self.assertRegex(step["uses"], r"^actions/[a-z-]+@[0-9a-f]{40}$")
                if step.get("uses", "").startswith("actions/checkout@"):
                    self.assertIs(step["with"]["persist-credentials"], False)

    def test_publisher_only_downloads_artifact_from_its_current_run(self):
        steps = self.jobs["publish"]["steps"]
        download = next(step for step in steps if step.get("uses", "").startswith("actions/download-artifact@"))
        self.assertEqual(download["with"], {"name": "macOS-release",
                                          "path": ".build/releases/${{ needs.package.outputs.tag }}"})
        self.assertEqual(steps[-1]["env"]["GH_TOKEN"], "${{ github.token }}")
        self.assertEqual(steps[-1]["run"], './scripts/publish-release.sh "$RELEASE_TAG"')

    def test_workflow_runs_do_not_interpolate_untrusted_expressions(self):
        for job in self.jobs.values():
            for step in job["steps"]:
                self.assertNotIn("${{", step.get("run", ""))


if __name__ == "__main__":
    unittest.main(verbosity=2)
