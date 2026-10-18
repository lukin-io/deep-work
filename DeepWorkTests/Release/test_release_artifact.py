#!/usr/bin/env python3
"""Native acceptance/regressions against a real packaged application archive."""
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("release_tools", ROOT / "scripts/release-tools.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
SOURCE = Path(sys.argv.pop(1)).resolve()
TAG = sys.argv.pop(1)


class ReleaseArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="deep-work-release-tests-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name) / "assets"
        shutil.copytree(SOURCE, self.directory)
        self.archive = self.directory / f"Deep-Work-{TAG}-macOS-arm64.zip"
        self.metadata_file = self.directory / "release-metadata.json"
        self.metadata = json.loads(self.metadata_file.read_text())

    def refresh_checksums(self):
        self.metadata["sha256"] = release.digest(self.archive)
        self.metadata_file.write_text(json.dumps(self.metadata, indent=2) + "\n")
        (self.directory / "SHA256SUMS").write_text("".join(
            f"{release.digest(path)}  {path.name}\n" for path in [self.archive, self.metadata_file]))

    def rewrite_archive(self, transform):
        with zipfile.ZipFile(self.archive) as source:
            contents = [(entry, source.read(entry.filename)) for entry in source.infolist()]
        replacement = self.archive.with_suffix(".replacement.zip")
        with zipfile.ZipFile(replacement, "w", compression=zipfile.ZIP_DEFLATED) as destination:
            for entry, content in contents:
                changed = transform(entry, content)
                if changed is not None:
                    destination.writestr(*changed)
        replacement.replace(self.archive)
        self.refresh_checksums()

    def test_real_apple_silicon_release_is_valid(self):
        release.verify(self.directory, TAG, self.metadata["commit"])

    def test_wrong_source_commit_is_rejected(self):
        with self.assertRaisesRegex(release.ReleaseError, "commit does not match"):
            release.verify(self.directory, TAG, "0" * 40)

    def test_checksum_tampering_is_rejected(self):
        self.archive.write_bytes(self.archive.read_bytes() + b"corrupt")
        with self.assertRaisesRegex(release.ReleaseError, "checksums do not match"):
            release.verify(self.directory, TAG)

    def test_missing_metadata_asset_is_rejected(self):
        self.metadata_file.unlink()
        with self.assertRaisesRegex(release.ReleaseError, "exactly the archive"):
            release.verify(self.directory, TAG)

    def test_false_notarization_claim_is_rejected(self):
        self.metadata["signing"]["notarized"] = True
        self.refresh_checksums()
        with self.assertRaisesRegex(release.ReleaseError, "invalid signing"):
            release.verify(self.directory, TAG)

    def test_packaged_version_must_match_tag(self):
        def change(entry, content):
            if entry.filename.endswith("/Info.plist"):
                plist = plistlib.loads(content)
                plist["CFBundleShortVersionString"] = "999.0.0"
                content = plistlib.dumps(plist)
            return entry, content
        self.rewrite_archive(change)
        with self.assertRaisesRegex(release.ReleaseError, "invalid CFBundleShortVersionString"):
            release.verify(self.directory, TAG)

    def test_missing_application_binary_is_rejected(self):
        self.rewrite_archive(lambda entry, content: None if entry.filename.endswith("/MacOS/DeepWork") else (entry, content))
        with self.assertRaisesRegex(release.ReleaseError, "missing a required"):
            release.verify(self.directory, TAG)

    def test_private_sqlite_file_cannot_be_distributed(self):
        with zipfile.ZipFile(self.archive, "a") as archive:
            archive.writestr("Deep Work.app/Contents/Resources/DeepWork.sqlite", b"private fixture")
        self.refresh_checksums()
        with self.assertRaisesRegex(release.ReleaseError, "unexpected files"):
            release.verify(self.directory, TAG)

    def test_symlink_cannot_escape_app_bundle(self):
        def change(entry, content):
            if entry.filename.endswith("/Resources/LICENSE"):
                entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                content = b"/tmp/elsewhere"
            return entry, content
        self.rewrite_archive(change)
        with self.assertRaisesRegex(release.ReleaseError, "symbolic links"):
            release.verify(self.directory, TAG)

    def test_stripped_file_type_is_rejected(self):
        def change(entry, content):
            if entry.filename.endswith("/MacOS/DeepWork"):
                entry.external_attr = 0o755 << 16
            return entry, content
        self.rewrite_archive(change)
        with self.assertRaisesRegex(release.ReleaseError, "must be regular files"):
            release.verify(self.directory, TAG)

    def test_non_executable_app_is_rejected(self):
        def change(entry, content):
            if entry.filename.endswith("/MacOS/DeepWork"):
                entry.external_attr = (stat.S_IFREG | 0o644) << 16
            return entry, content
        self.rewrite_archive(change)
        with self.assertRaisesRegex(release.ReleaseError, "executable permissions"):
            release.verify(self.directory, TAG)

    def intel_fixture(self):
        # A tiny incompatible Mach-O tests the rejection boundary without
        # building or distributing an Intel version of the application.
        executable = Path(self.temporary.name) / "intel-fixture"
        subprocess.run(["xcrun", "clang", "-target", "x86_64-apple-macosx15.0", "-x", "c",
                        "-o", str(executable), "-"], input="int main(void) { return 0; }\n",
                       text=True, check=True, capture_output=True)
        return executable

    def test_intel_only_executable_is_rejected(self):
        intel = self.intel_fixture().read_bytes()
        self.rewrite_archive(lambda entry, content: (entry, intel)
                             if entry.filename.endswith("/MacOS/DeepWork") else (entry, content))
        with self.assertRaisesRegex(release.ReleaseError, "must contain only arm64"):
            release.verify(self.directory, TAG)

    def test_universal_executable_is_rejected(self):
        intel = self.intel_fixture()
        def change(entry, content):
            if entry.filename.endswith("/MacOS/DeepWork"):
                arm64 = Path(self.temporary.name) / "arm64-fixture"
                universal = Path(self.temporary.name) / "universal-fixture"
                arm64.write_bytes(content)
                subprocess.run(["xcrun", "lipo", "-create", str(arm64), str(intel), "-output", str(universal)], check=True)
                content = universal.read_bytes()
            return entry, content
        self.rewrite_archive(change)
        with self.assertRaisesRegex(release.ReleaseError, "must contain only arm64"):
            release.verify(self.directory, TAG)

    def test_unsupported_deployment_targets_are_rejected(self):
        original_archive = self.archive.read_bytes()
        for target in ["14.0", "16.0"]:
            with self.subTest(target=target):
                self.archive.write_bytes(original_archive)
                def change(entry, content):
                    if entry.filename.endswith("/MacOS/DeepWork"):
                        original = Path(self.temporary.name) / "original"
                        changed = Path(self.temporary.name) / "changed"
                        original.write_bytes(content)
                        subprocess.run(["xcrun", "vtool", "-arch", "arm64", "-set-build-version", "macos", target, "27.0",
                                        "-replace", "-output", str(changed), str(original)], check=True, capture_output=True)
                        content = changed.read_bytes()
                    return entry, content
                self.rewrite_archive(change)
                with self.assertRaisesRegex(release.ReleaseError, "target macOS 15.0"):
                    release.verify(self.directory, TAG)

    def test_intel_and_universal_metadata_are_rejected(self):
        for architectures in [["x86_64"], ["arm64", "x86_64"]]:
            with self.subTest(architectures=architectures):
                self.metadata["architectures"] = architectures
                self.refresh_checksums()
                with self.assertRaisesRegex(release.ReleaseError, "invalid architectures"):
                    release.verify(self.directory, TAG)

    def test_corrupt_signature_is_rejected(self):
        def change(entry, content):
            if entry.filename.endswith("/_CodeSignature/CodeResources"):
                content = b"invalid signature resource seal"
            return entry, content
        self.rewrite_archive(change)
        with self.assertRaisesRegex(release.ReleaseError, "codesign.*failed"):
            release.verify(self.directory, TAG)

    def test_debug_data_override_is_rejected(self):
        self.rewrite_archive(lambda entry, content: (entry, content + b"DEEP_WORK_DATA_DIR")
                             if entry.filename.endswith("/MacOS/DeepWork") else (entry, content))
        with self.assertRaisesRegex(release.ReleaseError, "Debug-only"):
            release.verify(self.directory, TAG)


if __name__ == "__main__":
    unittest.main(verbosity=2)
