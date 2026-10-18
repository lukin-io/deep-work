import AppKit
import Testing
@testable import DeepWorkApp

/// AppKit owns process-global focus, windows and status items. Serialize these
/// suites together, not only cases inside each individual suite.
@Suite(.serialized)
struct NativeApplicationTests {}

@MainActor
func prepareNativeTestApplication() {
    _ = NSApplication.shared
}

/// Dispatch the native traffic-light button's action without performClose's
/// synthetic click tracking, which exits the hostless SwiftPM main loop.
/// Real mouse clicks and Command-W are verified through the compiled app.
@MainActor
func requestNativeWindowClose(_ window: NSWindow) {
    guard let button = window.standardWindowButton(.closeButton) else {
        Issue.record("Expected a native close button")
        return
    }
    #expect(button.sendAction(button.action, to: button.target))
}
