#!/bin/bash
# Produce an immutable, Apple Silicon macOS preview without copying local app data.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
    printf 'Usage: %s vMAJOR.MINOR.PATCH-preview.N [BUILD_NUMBER]\n' "$0" >&2
    exit 1
fi
tag="$1"
build_number="${2:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' DeepWork/Resources/Info.plist)}"
python3 scripts/release-tools.py validate-input "$tag" "$build_number"
commit="$(python3 scripts/release-tools.py inspect-source "$tag" "$build_number")"
output_dir="$project_dir/.build/releases/$tag"
if [[ -e "$output_dir" ]]; then
    printf 'Release output already exists; refusing to overwrite: %s\n' "$output_dir" >&2
    exit 1
fi
mkdir -p "$project_dir/.build/releases"
staging_dir="$(mktemp -d "$project_dir/.build/releases/.release-staging.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
app_dir="$staging_dir/bundle/Deep Work.app"
assets_dir="$staging_dir/assets"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$assets_dir"
scratch="$project_dir/.build/release-arm64"
swift build -c release --product DeepWork --triple arm64-apple-macosx15.0 \
    --scratch-path "$scratch" -Xswiftc -strict-concurrency=complete
binary_dir="$(swift build -c release --triple arm64-apple-macosx15.0 \
    --scratch-path "$scratch" --show-bin-path)"
cp "$binary_dir/DeepWork" "$app_dir/Contents/MacOS/DeepWork"
cp DeepWork/Resources/Info.plist "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app_dir/Contents/Info.plist"
cp LICENSE "$app_dir/Contents/Resources/LICENSE"
./scripts/build-app-icon.sh "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_dir"
codesign --verify --strict --all-architectures "$app_dir"
# Omit Finder/resource-fork metadata and preserve only the explicit app bundle.
/usr/bin/ditto -c -k --keepParent --norsrc --noextattr "$app_dir" \
    "$assets_dir/Deep-Work-$tag-macOS-arm64.zip"
python3 scripts/release-tools.py write-metadata "$assets_dir" "$tag" "$build_number" "$commit"
./scripts/verify-release.sh "$assets_dir" "$tag" "$commit"
# Fail if a concurrent edit changed the source during compilation.
final_commit="$(python3 scripts/release-tools.py inspect-source "$tag" "$build_number")"
if [[ "$final_commit" != "$commit" ]]; then
    printf 'HEAD changed during packaging; no release output was published.\n' >&2
    exit 1
fi
python3 - "$assets_dir" "$output_dir" <<'PYTHON'
import os
import sys
os.rename(sys.argv[1], sys.argv[2])
PYTHON
printf 'Packaged unnotarized preview: %s\n' "$output_dir"
