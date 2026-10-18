#!/usr/bin/env python3
"""Fail-closed checks for Deep Work's explicitly unnotarized preview artifacts."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
APP_NAME = "Deep Work.app"
EXPECTED_FILES = {
    f"{APP_NAME}/Contents/Info.plist",
    f"{APP_NAME}/Contents/MacOS/DeepWork",
    f"{APP_NAME}/Contents/Resources/AppIcon.icns",
    f"{APP_NAME}/Contents/Resources/LICENSE",
    f"{APP_NAME}/Contents/_CodeSignature/CodeResources",
}
EXPECTED_DIRECTORIES = {
    f"{APP_NAME}/", f"{APP_NAME}/Contents/", f"{APP_NAME}/Contents/MacOS/",
    f"{APP_NAME}/Contents/Resources/", f"{APP_NAME}/Contents/_CodeSignature/",
}


class ReleaseError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ReleaseError(message)


def version_for_tag(tag):
    # Stable releases need a separate Developer ID + notarization pipeline.
    match = re.fullmatch(r"v((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))-preview\.([1-9][0-9]*)", tag)
    require(match is not None, "Tag must be vMAJOR.MINOR.PATCH-preview.N; this pipeline only publishes ad-hoc, unnotarized previews.")
    return match.group(1)


def validate_build_number(value):
    require(re.fullmatch(r"[1-9][0-9]{0,3}", value) is not None,
            "Build number must be a positive integer from 1 through 9999.")
    return value


def run(arguments):
    result = subprocess.run(arguments, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    require(result.returncode == 0, f"{' '.join(map(str, arguments))} failed: {result.stderr.strip() or result.stdout.strip()}")
    return result.stdout.strip()


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def source_plist():
    with (ROOT / "DeepWork/Resources/Info.plist").open("rb") as stream:
        return plistlib.load(stream)


def inspect_source(tag, build_number):
    version = version_for_tag(tag)
    validate_build_number(build_number)
    require(source_plist().get("CFBundleShortVersionString") == version,
            "Tag version must match the committed Info.plist CFBundleShortVersionString.")
    require(run(["git", "status", "--porcelain", "--untracked-files=normal"]) == "",
            "Release packaging requires a clean, committed working tree.")
    commit = run(["git", "rev-parse", "HEAD"])
    tag_ref = subprocess.run(["git", "rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}"],
                             cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    require(tag_ref.returncode != 0 or tag_ref.stdout.strip() == commit,
            "Existing release tag must point to HEAD.")
    return commit


def write_metadata(directory, tag, build_number, commit):
    artifact = directory / f"Deep-Work-{tag}-macOS-universal.zip"
    metadata = {
        "schemaVersion": 1, "appName": "Deep Work", "bundleIdentifier": "app.deepwork.mac",
        "tag": tag, "version": version_for_tag(tag), "buildNumber": validate_build_number(build_number),
        "commit": commit, "sourceTreeClean": True, "configuration": "Release",
        "architectures": ["arm64", "x86_64"], "minimumMacOS": "13.0",
        "signing": {"identity": "ad-hoc", "notarized": False},
        "artifact": artifact.name, "sha256": digest(artifact),
        "createdAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "swiftVersion": run(["swift", "--version"]),
        "macOSSDKVersion": run(["xcrun", "--sdk", "macosx", "--show-sdk-version"]),
    }
    metadata_file = directory / "release-metadata.json"
    metadata_file.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
    (directory / "SHA256SUMS").write_text("".join(
        f"{digest(path)}  {path.name}\n" for path in [artifact, metadata_file]))


def validate_entries(entries):
    names = [entry.filename for entry in entries]
    require(len(names) == len(set(names)), "Archive contains duplicate entries.")
    require(set(names) <= EXPECTED_FILES | EXPECTED_DIRECTORIES,
            "Archive contains unexpected files or paths; only the application may be distributed.")
    require(EXPECTED_FILES <= set(names), "Archive is missing a required application file.")
    require(sum(entry.file_size for entry in entries) < 250 * 1024 * 1024,
            "Archive exceeds the preview application size limit.")
    for entry in entries:
        mode = entry.external_attr >> 16
        require(not stat.S_ISLNK(mode), "Archive must not contain symbolic links.")
        require(not entry.flag_bits & 1, "Archive must not contain encrypted entries.")
        if entry.filename in EXPECTED_FILES:
            require(stat.S_ISREG(mode), "Archived application files must be regular files.")
        if entry.filename == f"{APP_NAME}/Contents/MacOS/DeepWork":
            require(mode & 0o100 != 0, "Archived application binary must retain executable permissions.")


def verify(directory, tag, expected_commit=None):
    version = version_for_tag(tag)
    artifact_name = f"Deep-Work-{tag}-macOS-universal.zip"
    require(directory.is_dir(), "Release directory does not exist.")
    require({path.name for path in directory.iterdir()} == {artifact_name, "SHA256SUMS", "release-metadata.json"},
            "Release directory must contain exactly the archive, SHA256SUMS, and release-metadata.json.")
    for path in directory.iterdir():
        require(path.is_file() and not path.is_symlink(), "Release assets must be regular files.")
    artifact = directory / artifact_name
    metadata_file = directory / "release-metadata.json"
    expected_sums = "".join(f"{digest(path)}  {path.name}\n" for path in [artifact, metadata_file])
    require((directory / "SHA256SUMS").read_text() == expected_sums, "Release checksums do not match the assets.")
    metadata = json.loads(metadata_file.read_text())
    require(isinstance(metadata, dict), "Release metadata must be an object.")
    expected = {"schemaVersion": 1, "appName": "Deep Work", "bundleIdentifier": "app.deepwork.mac",
                "tag": tag, "version": version, "configuration": "Release", "sourceTreeClean": True,
                "architectures": ["arm64", "x86_64"], "minimumMacOS": "13.0",
                "signing": {"identity": "ad-hoc", "notarized": False},
                "artifact": artifact_name, "sha256": digest(artifact)}
    for key, value in expected.items():
        require(metadata.get(key) == value, f"Release metadata has an invalid {key}.")
    build_number = validate_build_number(str(metadata.get("buildNumber", "")))
    commit = metadata.get("commit", "")
    require(isinstance(commit, str) and re.fullmatch(r"[0-9a-f]{40}", commit) is not None,
            "Release metadata must identify a full Git commit.")
    if expected_commit is not None:
        require(commit == expected_commit, "Release metadata commit does not match the expected source.")
    for key in ["createdAtUTC", "swiftVersion", "macOSSDKVersion"]:
        require(isinstance(metadata.get(key), str) and metadata[key], f"Release metadata is missing {key}.")

    # Inspect the complete allowlist before extraction. No archive path can escape
    # the temporary directory, and no user database or test fixture can slip in.
    with tempfile.TemporaryDirectory(prefix="deep-work-release-verify-") as temporary:
        unpacked = Path(temporary)
        with zipfile.ZipFile(artifact) as archive:
            validate_entries(archive.infolist())
            archive.extractall(unpacked)
            executable = unpacked / APP_NAME / "Contents/MacOS/DeepWork"
            os.chmod(executable, 0o755)
        app = unpacked / APP_NAME
        with (app / "Contents/Info.plist").open("rb") as stream:
            plist = plistlib.load(stream)
        for key, value in {"CFBundleIdentifier": "app.deepwork.mac", "CFBundleExecutable": "DeepWork",
                           "CFBundleShortVersionString": version, "CFBundleVersion": build_number,
                           "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "13.0",
                           "CFBundleIconFile": "AppIcon.icns"}.items():
            require(plist.get(key) == value, f"Packaged Info.plist has an invalid {key}.")
        require(set(run(["xcrun", "lipo", "-archs", str(executable)]).split()) == {"arm64", "x86_64"},
                "Application executable must contain arm64 and x86_64 slices.")
        for architecture in ["arm64", "x86_64"]:
            build_commands = run(["xcrun", "vtool", "-arch", architecture, "-show-build", str(executable)])
            require(re.search(r"^\s*minos 13\.0(?:\.0)?$", build_commands, re.MULTILINE) is not None,
                    "Application executable must target macOS 13.0 on both architectures.")
        require(b"DEEP_WORK_DATA_DIR" not in executable.read_bytes(),
                "Application contains the Debug-only data-directory override.")
        run(["codesign", "--verify", "--strict", "--all-architectures", str(app)])
        details = subprocess.run(["codesign", "--display", "--verbose=4", str(app)], text=True,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        require(details.returncode == 0 and "Signature=adhoc" in details.stderr,
                "Preview application must have an explicit ad-hoc signature.")
        require((app / "Contents/Resources/LICENSE").read_bytes() == (ROOT / "LICENSE").read_bytes(),
                "Application must contain the repository license unchanged.")
        run(["swift", str(ROOT / "scripts/verify-app-icon.swift"), str(app),
             str(ROOT / "DeepWork/Resources/Assets.xcassets/AppIcon.appiconset")])
    print(f"Verified {tag}: universal Release app, icon, license, ad-hoc signature, metadata, checksums; not notarized.")


def main(arguments):
    require(len(arguments) > 0, "Expected validate-input, inspect-source, write-metadata, or verify command.")
    command, *args = arguments
    if command == "validate-input" and len(args) == 2:
        version_for_tag(args[0])
        validate_build_number(args[1])
    elif command == "inspect-source" and len(args) == 2:
        print(inspect_source(*args))
    elif command == "write-metadata" and len(args) == 4:
        write_metadata(Path(args[0]), *args[1:])
    elif command == "verify" and len(args) in [2, 3]:
        verify(Path(args[0]), *args[1:])
    else:
        raise ReleaseError("Invalid release tool arguments.")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (ReleaseError, OSError, ValueError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        print(f"Release validation failed: {error}", file=sys.stderr)
        sys.exit(1)
