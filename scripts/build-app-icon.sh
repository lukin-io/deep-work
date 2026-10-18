#!/bin/bash
# Package the canonical Xcode assets without resizing or editing their artwork.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
    printf 'Usage: %s OUTPUT.icns [AppIcon.appiconset]\nThe output directory must already exist.\n' "$0" >&2
    exit 1
fi
output="$1"
catalog="${2:-$project_dir/DeepWork/Resources/Assets.xcassets/AppIcon.appiconset}"
if [[ ! -d "$catalog" || ! -f "$catalog/Contents.json" ]]; then
    printf 'App icon catalog or Contents.json is missing: %s\n' "$catalog" >&2
    exit 1
fi
catalog="$(cd "$catalog" && pwd -P)"
if [[ ! -d "$(dirname "$output")" || -d "$output" || "$output" != *.icns ]]; then
    printf 'App icon output must be an .icns file in an existing directory.\n' >&2
    exit 1
fi
output_dir="$(cd "$(dirname "$output")" && pwd -P)"
case "$output_dir/" in
    "$catalog/"*)
        printf 'App icon output must be outside the source asset catalog.\n' >&2
        exit 1
        ;;
esac
filenames=(
    icon_16x16.png icon_16x16@2x.png
    icon_32x32.png icon_32x32@2x.png
    icon_128x128.png icon_128x128@2x.png
    icon_256x256.png icon_256x256@2x.png
    icon_512x512.png icon_512x512@2x.png
)
for filename in "${filenames[@]}"; do
    if [[ ! -f "$catalog/$filename" ]]; then
        printf 'Required app icon image is missing: %s\n' "$filename" >&2
        exit 1
    fi
done

# Stage next to the destination so a successful final rename is atomic. Failed
# conversion or validation never replaces the last known-good output.
staging_dir="$(mktemp -d "$output_dir/.app-icon-build.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
iconset="$staging_dir/AppIcon.iconset"
validation_app="$staging_dir/Deep Work.app"
mkdir -p "$iconset" "$validation_app/Contents/Resources"
for filename in "${filenames[@]}"; do
    cp "$catalog/$filename" "$iconset/$filename"
done
cp "$project_dir/DeepWork/Resources/Info.plist" "$validation_app/Contents/Info.plist"
generated_icon="$validation_app/Contents/Resources/AppIcon.icns"
/usr/bin/iconutil --convert icns --output "$generated_icon" "$iconset"
swift "$project_dir/scripts/verify-app-icon.swift" "$validation_app" "$catalog"
mv -f "$generated_icon" "$output"
printf 'Built app icon from canonical asset catalog: %s\n' "$output"
