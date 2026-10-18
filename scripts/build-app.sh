#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c debug
binary_dir="$(swift build -c debug --show-bin-path)"
app_dir="$PWD/.build/Deep Work.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/DeepWork" "$app_dir/Contents/MacOS/DeepWork"
cp DeepWork/Resources/Info.plist "$app_dir/Contents/Info.plist"
# Remove the obsolete generated icon name from earlier local development builds.
rm -f "$app_dir/Contents/Resources/DeepWork.icns"
./scripts/build-app-icon.sh "$app_dir/Contents/Resources/AppIcon.icns"
swift scripts/verify-app-icon.swift "$app_dir" DeepWork/Resources/Assets.xcassets/AppIcon.appiconset
codesign --force --sign - "$app_dir"
# Nested copies do not update the bundle directory. Match Xcode's final Touch
# step so LaunchServices invalidates a previously cached application icon.
touch "$app_dir"
printf 'Built %s\n' "$app_dir"
