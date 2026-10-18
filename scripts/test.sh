#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Some standalone Command Line Tools releases ship Testing but omit its macro
# search path. Full Xcode toolchains discover the plugin automatically.
swift_bin="$(xcrun --find swiftc)"
testing_plugin="$(dirname "$swift_bin")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$testing_plugin" ]]; then
    swift test --disable-xctest -Xswiftc -load-plugin-library -Xswiftc "$testing_plugin" "$@"
else
    swift test --disable-xctest "$@"
fi
