#!/usr/bin/env python3
"""Deterministic policy tests; no keychain, network, app state, or build needed."""
import importlib.util
from pathlib import Path
import stat
import subprocess
import sys
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("release_tools", ROOT / "scripts/release-tools.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


def entries():
    result = [zipfile.ZipInfo(name) for name in sorted(release.EXPECTED_FILES)]
    for entry in result:
        entry.external_attr = (stat.S_IFREG | (0o755 if entry.filename.endswith("/MacOS/DeepWork") else 0o644)) << 16
    return result


class ReleasePolicyTests(unittest.TestCase):
    def test_preview_tag_maps_to_bundle_version(self):
        for tag, version in [("v0.1.0-preview.1", "0.1.0"), ("v12.34.56-preview.28", "12.34.56")]:
            with self.subTest(tag=tag):
                self.assertEqual(release.version_for_tag(tag), version)

    def test_stable_empty_malformed_and_unsafe_tags_are_rejected(self):
        for tag in ["", "v0.1.0", "0.1.0-preview.1", "v01.1.0-preview.1", "v0.1.0-preview.0",
                    "v0.1.0-preview.01", "v0.1.0-beta.1", "v0.1.0-preview.1/x", "../v0.1.0-preview.1",
                    "v0.1.0-preview.1\n", "v0.1.0-preview.1+build", "v0.1.0-preview.$(id)"]:
            with self.subTest(tag=tag), self.assertRaises(release.ReleaseError):
                release.version_for_tag(tag)

    def test_build_number_boundaries(self):
        for value in ["1", "42", "9999"]:
            self.assertEqual(release.validate_build_number(value), value)
        for value in ["", "0", "01", "10000", "-1", "1.2", "1\n", "$(id)"]:
            with self.subTest(value=value), self.assertRaises(release.ReleaseError):
                release.validate_build_number(value)

    def test_archive_allowlist_accepts_complete_app_and_optional_directories(self):
        release.validate_entries(entries())
        release.validate_entries(entries() + [zipfile.ZipInfo(name) for name in release.EXPECTED_DIRECTORIES])

    def test_archive_missing_required_file(self):
        with self.assertRaisesRegex(release.ReleaseError, "missing a required"):
            release.validate_entries(entries()[1:])

    def test_archive_rejects_private_data_and_path_traversal(self):
        for name in ["Deep Work.app/Contents/Resources/DeepWork.sqlite", "../Info.plist", "/tmp/secret",
                     "__MACOSX/._Deep Work.app", "Deep Work.app/.DS_Store"]:
            with self.subTest(name=name), self.assertRaisesRegex(release.ReleaseError, "unexpected files"):
                release.validate_entries(entries() + [zipfile.ZipInfo(name)])

    def test_archive_rejects_duplicate_paths(self):
        with self.assertRaisesRegex(release.ReleaseError, "duplicate"):
            release.validate_entries(entries() + [entries()[0]])

    def test_archive_rejects_symlinks(self):
        candidates = entries()
        candidates[0].external_attr = (stat.S_IFLNK | 0o777) << 16
        with self.assertRaisesRegex(release.ReleaseError, "symbolic links"):
            release.validate_entries(candidates)

    def test_archive_rejects_encryption(self):
        candidates = entries()
        candidates[0].flag_bits = 1
        with self.assertRaisesRegex(release.ReleaseError, "encrypted"):
            release.validate_entries(candidates)

    def test_archive_requires_regular_file_metadata(self):
        candidates = entries()
        candidates[0].external_attr = 0o644 << 16
        with self.assertRaisesRegex(release.ReleaseError, "must be regular files"):
            release.validate_entries(candidates)

    def test_archive_requires_executable_permissions(self):
        for permissions in [0o644, 0o641]:
            candidates = entries()
            for entry in candidates:
                entry.external_attr = (stat.S_IFREG | permissions) << 16
            with self.subTest(permissions=permissions), self.assertRaisesRegex(release.ReleaseError, "executable permissions"):
                release.validate_entries(candidates)

    def test_archive_rejects_unbounded_expansion(self):
        candidates = entries()
        candidates[0].file_size = 250 * 1024 * 1024
        with self.assertRaisesRegex(release.ReleaseError, "size limit"):
            release.validate_entries(candidates)

    def test_source_version_must_match_tag(self):
        with patch.object(release, "source_plist", return_value={"CFBundleShortVersionString": "0.2.0"}), \
             patch.object(release, "run") as commands, \
             self.assertRaisesRegex(release.ReleaseError, "Tag version must match"):
            release.inspect_source("v0.1.0-preview.1", "1")
        commands.assert_not_called()

    def test_source_missing_version_is_rejected(self):
        with patch.object(release, "source_plist", return_value={}), \
             self.assertRaisesRegex(release.ReleaseError, "Tag version must match"):
            release.inspect_source("v0.1.0-preview.1", "1")

    def test_dirty_source_is_rejected(self):
        with patch.object(release, "source_plist", return_value={"CFBundleShortVersionString": "0.1.0"}), \
             patch.object(release, "run", return_value=" M DeepWork/App/AppModel.swift"), \
             self.assertRaisesRegex(release.ReleaseError, "clean, committed"):
            release.inspect_source("v0.1.0-preview.1", "1")

    def test_new_tag_can_be_packaged_before_publication(self):
        commit = "a" * 40
        with patch.object(release, "source_plist", return_value={"CFBundleShortVersionString": "0.1.0"}), \
             patch.object(release, "run", side_effect=["", commit]), \
             patch.object(release.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "")):
            self.assertEqual(release.inspect_source("v0.1.0-preview.1", "1"), commit)

    def test_existing_tag_must_match_head(self):
        commit = "a" * 40
        for tag_commit, valid in [(commit, True), ("b" * 40, False)]:
            with self.subTest(valid=valid), \
                 patch.object(release, "source_plist", return_value={"CFBundleShortVersionString": "0.1.0"}), \
                 patch.object(release, "run", side_effect=["", commit]), \
                 patch.object(release.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, tag_commit)):
                if valid:
                    self.assertEqual(release.inspect_source("v0.1.0-preview.1", "1"), commit)
                else:
                    with self.assertRaisesRegex(release.ReleaseError, "must point to HEAD"):
                        release.inspect_source("v0.1.0-preview.1", "1")

    def test_invalid_input_fails_before_git_or_build_work(self):
        with patch.object(release, "source_plist") as plist, \
             self.assertRaises(release.ReleaseError):
            release.inspect_source("../../invalid", "1")
        plist.assert_not_called()

    def test_packaging_cli_rejects_stable_tag(self):
        result = subprocess.run([str(ROOT / "scripts/package-release.sh"), "v0.1.0", "1"],
                                cwd=ROOT, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("only publishes ad-hoc", result.stderr)

    def test_packaging_cli_requires_tag(self):
        result = subprocess.run([str(ROOT / "scripts/package-release.sh")], cwd=ROOT,
                                text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Usage:", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
