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
        self.archive = self.directory / f"Deep-Work-{TAG}-macOS-universal.zip"
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

    def test_real_universal_release_is_valid(self):
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

    def test_missing_intel_slice_is_rejected(self):
        def change(entry, content):
            if entry.filename.endswith("/MacOS/DeepWork"):
                fat = Path(self.temporary.name) / "fat"
                thin = Path(self.temporary.name) / "thin"
                fat.write_bytes(content)
                subprocess.run(["xcrun", "lipo", str(fat), "-thin", "arm64", "-output", str(thin)], check=True)
                content = thin.read_bytes()
            return entry, content
        self.rewrite_archive(change)
        with self.assertRaisesRegex(release.ReleaseError, "arm64 and x86_64"):
            release.verify(self.directory, TAG)

    def test_higher_deployment_target_in_one_slice_is_rejected(self):
        def change(entry, content):
            if entry.filename.endswith("/MacOS/DeepWork"):
                original = Path(self.temporary.name) / "original"
                changed = Path(self.temporary.name) / "changed"
                original.write_bytes(content)
                subprocess.run(["xcrun", "vtool", "-arch", "x86_64", "-set-build-version", "macos", "14.0", "27.0",
                                "-replace", "-output", str(changed), str(original)], check=True, capture_output=True)
                content = changed.read_bytes()
            return entry, content
        self.rewrite_archive(change)
        with self.assertRaisesRegex(release.ReleaseError, "target macOS 13.0 on both"):
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
