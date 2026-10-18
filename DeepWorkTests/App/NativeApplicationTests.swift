import AppKit
import Testing

/// AppKit owns process-global focus, windows and status items. Serialize these
/// suites together, not only cases inside each individual suite.
@Suite(.serialized)
struct NativeApplicationTests {}

@MainActor
func prepareNativeTestApplication() {
    _ = NSApplication.shared
}
