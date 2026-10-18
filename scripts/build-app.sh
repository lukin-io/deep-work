#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c debug
binary_dir="$(swift build -c debug --show-bin-path)"
app_dir="$PWD/.build/Deep Work.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/DeepWork" "$app_dir/Contents/MacOS/DeepWork"
cp DeepWork/Resources/Info.plist "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
printf 'Built %s\n' "$app_dir"
