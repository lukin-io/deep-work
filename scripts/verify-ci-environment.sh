#!/bin/bash
# Fail before building if a hosted image or selected toolchain drifts.
set -euo pipefail
fail() { printf 'CI environment rejected: %s\n' "$*" >&2; exit 1; }
[[ $# -eq 3 ]] || fail 'usage: verify-ci-environment.sh <macOS-major> <Xcode-version> <SDK-version>'
expected_macos="$1"
expected_xcode="$2"
expected_sdk="$3"
[[ "$expected_macos" =~ ^[1-9][0-9]*$ && "$expected_xcode" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ && "$expected_sdk" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] ||
  fail 'expected versions must be explicit numeric versions'
[[ "$(uname -s)" == Darwin ]] || fail 'a macOS runner is required'
[[ "$(uname -m)" == arm64 ]] || fail 'an Apple Silicon runner is required'
macos_version="$(sw_vers -productVersion)"
[[ "${macos_version%%.*}" == "$expected_macos" ]] || fail "expected macOS $expected_macos, found $macos_version"
[[ "${DEVELOPER_DIR:-}" == */Xcode_"$expected_xcode".app/Contents/Developer && -d "${DEVELOPER_DIR:-}" ]] ||
  fail "DEVELOPER_DIR must select the installed Xcode $expected_xcode explicitly"
xcode_version="$(xcodebuild -version)"
[[ "${xcode_version%%$'\n'*}" == "Xcode $expected_xcode" ]] || fail "selected Xcode does not match $expected_xcode"
swiftc_path="$(xcrun --find swiftc)"
[[ "$swiftc_path" == "$DEVELOPER_DIR/"* ]] || fail 'Swift compiler is outside the selected Xcode'
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
[[ "$sdk_version" == "$expected_sdk" ]] || fail "expected SDK $expected_sdk, found $sdk_version"
swift_version="$(swift --version)"
[[ "$swift_version" == "$(xcrun swift --version)" ]] || fail 'PATH Swift differs from the selected Xcode toolchain'
printf 'Verified CI: macOS %s, arm64, %s, SDK %s\n%s\n' "$macos_version" "$xcode_version" "$sdk_version" "$swift_version"
