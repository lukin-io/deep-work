#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./DeepWorkTests/Icon/test-app-icon.sh
# Some standalone Command Line Tools releases ship Testing but omit its macro
# search path. Full Xcode toolchains discover the plugin automatically.
swift_bin="$(xcrun --find swiftc)"
testing_plugin="$(dirname "$swift_bin")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
test_log="$(mktemp "${TMPDIR:-/tmp}/deep-work-tests.XXXXXX")"
trap 'rm -f "$test_log"' EXIT
if [[ -f "$testing_plugin" ]]; then
    swift test --disable-xctest -Xswiftc -load-plugin-library -Xswiftc "$testing_plugin" "$@" 2>&1 | tee "$test_log"
else
    swift test --disable-xctest "$@" 2>&1 | tee "$test_log"
fi

awk -f scripts/check-test-completion.awk "$test_log"
