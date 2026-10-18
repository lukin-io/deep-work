#!/bin/bash
# Native image/bundle acceptance regressions, independent of a running app.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/../.." && pwd)"
icon_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/deep-work-icon-tests.XXXXXX")"
trap 'rm -rf "$icon_test_dir"' EXIT
app_dir="$icon_test_dir/Deep Work.app"
resources="$app_dir/Contents/Resources"
catalog="$project_dir/DeepWork/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$resources"
cp "$project_dir/DeepWork/Resources/Info.plist" "$app_dir/Contents/Info.plist"
xcrun swiftc "$project_dir/scripts/verify-app-icon.swift" -o "$icon_test_dir/verify-app-icon"
builder="$project_dir/scripts/build-app-icon.sh"
cp -R "$catalog" "$icon_test_dir/Original.appiconset"
"$builder" "$resources/AppIcon.icns"
cp "$resources/AppIcon.icns" "$icon_test_dir/Original.icns"

expect_invalid_bundle() {
    local expected_message="$1"
    if "$icon_test_dir/verify-app-icon" "$app_dir" "$catalog" >"$icon_test_dir/result.log" 2>&1; then
        printf 'Expected icon validation to reject: %s\n' "$expected_message" >&2
        exit 1
    fi
    if ! /usr/bin/grep -Fq "$expected_message" "$icon_test_dir/result.log"; then
        cat "$icon_test_dir/result.log" >&2
        exit 1
    fi
}

expect_failed_build_preserves_output() {
    local input_catalog="$1"
    local expected_message="$2"
    cp "$icon_test_dir/Original.icns" "$resources/AppIcon.icns"
    if "$builder" "$resources/AppIcon.icns" "$input_catalog" >"$icon_test_dir/result.log" 2>&1; then
        printf 'Expected icon generation to reject: %s\n' "$input_catalog" >&2
        exit 1
    fi
    if [[ -n "$expected_message" ]] && ! /usr/bin/grep -Fq "$expected_message" "$icon_test_dir/result.log"; then
        cat "$icon_test_dir/result.log" >&2
        exit 1
    fi
    cmp "$icon_test_dir/Original.icns" "$resources/AppIcon.icns"
}

# 1. Native resource lookup, every size, and per-pixel parity with Xcode's assets.
"$icon_test_dir/verify-app-icon" "$app_dir" "$catalog"

# 2. Missing metadata must fail rather than accept a generic application icon.
/usr/libexec/PlistBuddy -c 'Delete :CFBundleIconFile' "$app_dir/Contents/Info.plist"
expect_invalid_bundle 'CFBundleIconFile must name AppIcon.icns.'
cp "$project_dir/DeepWork/Resources/Info.plist" "$app_dir/Contents/Info.plist"

# 3. A broken packaging path and 4. an undecodable resource must both fail.
rm "$resources/AppIcon.icns"
expect_invalid_bundle 'The bundle icon is missing or cannot be decoded by macOS.'
printf 'invalid icon data' >"$resources/AppIcon.icns"
expect_invalid_bundle 'The bundle icon is missing or cannot be decoded by macOS.'

# 5. A valid ICNS with only one resolution is insufficient for our shipped icon.
mkdir "$icon_test_dir/Incomplete.iconset"
cp "$catalog/icon_16x16.png" "$icon_test_dir/Incomplete.iconset/"
/usr/bin/iconutil --convert icns --output "$resources/AppIcon.icns" "$icon_test_dir/Incomplete.iconset"
expect_invalid_bundle 'The icon must include all ten 16–512pt standard and Retina representations.'

# 6. Packaging is deterministic and leaves the canonical source tree unchanged.
"$builder" "$resources/AppIcon.icns" "$catalog"
cmp "$icon_test_dir/Original.icns" "$resources/AppIcon.icns"
diff -r "$icon_test_dir/Original.appiconset" "$catalog"

# 7. An otherwise valid ten-size resource with changed artwork must fail.
cp "$icon_test_dir/Original.icns" "$resources/AppIcon.icns"
cp -R "$catalog" "$icon_test_dir/Changed.appiconset"
swift - "$icon_test_dir/Changed.appiconset/icon_16x16.png" <<'SWIFT'
import Foundation
import CoreGraphics
import ImageIO
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
let original = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8,
                        bytesPerRow: 64, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.draw(original, in: CGRect(x: 0, y: 0, width: 16, height: 16))
context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
SWIFT
catalog="$icon_test_dir/Changed.appiconset"
expect_invalid_bundle 'Packaged icon pixels differ from approved asset: icon_16x16.png.'

# 8. Missing required images preserve the previous valid output.
cp -R "$icon_test_dir/Original.appiconset" "$icon_test_dir/Missing.appiconset"
rm "$icon_test_dir/Missing.appiconset/icon_512x512@2x.png"
expect_failed_build_preserves_output "$icon_test_dir/Missing.appiconset" \
    'Required app icon image is missing: icon_512x512@2x.png'

# 9. Missing catalog/metadata cannot silently fall back to delivery archives.
expect_failed_build_preserves_output "$icon_test_dir/Absent.appiconset" \
    'App icon catalog or Contents.json is missing:'
rm "$icon_test_dir/Missing.appiconset/Contents.json"
expect_failed_build_preserves_output "$icon_test_dir/Missing.appiconset" \
    'App icon catalog or Contents.json is missing:'

# 10. Invalid source bytes must not publish a partial ICNS over a good one.
cp -R "$icon_test_dir/Original.appiconset" "$icon_test_dir/Corrupt.appiconset"
printf 'invalid image data' >"$icon_test_dir/Corrupt.appiconset/icon_16x16.png"
expect_failed_build_preserves_output "$icon_test_dir/Corrupt.appiconset" ''

# 11. Generated artifacts cannot be written into the source asset catalog.
catalog="$icon_test_dir/Original.appiconset"
if "$builder" "$catalog/AppIcon.icns" "$catalog" >"$icon_test_dir/result.log" 2>&1; then
    printf 'Expected source asset output path to be rejected.\n' >&2
    exit 1
fi
/usr/bin/grep -Fq 'App icon output must be outside the source asset catalog.' "$icon_test_dir/result.log"
diff -r "$project_dir/DeepWork/Resources/Assets.xcassets/AppIcon.appiconset" "$catalog"

# 12. Successful conversion still needs valid catalog metadata before publishing.
cp -R "$icon_test_dir/Original.appiconset" "$icon_test_dir/InvalidMetadata.appiconset"
printf '{}' >"$icon_test_dir/InvalidMetadata.appiconset/Contents.json"
expect_failed_build_preserves_output "$icon_test_dir/InvalidMetadata.appiconset" \
    'AppIcon asset catalog must contain ten image entries.'
shopt -s nullglob
temporary_outputs=("$resources"/.app-icon-build.*)
if [[ "${#temporary_outputs[@]}" -ne 0 ]]; then
    printf 'Icon generation left temporary output after a failure.\n' >&2
    exit 1
fi
printf 'App icon packaging: 12 acceptance/regression cases passed.\n'
