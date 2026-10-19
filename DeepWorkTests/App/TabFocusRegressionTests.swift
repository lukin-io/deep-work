import AppKit
import Testing
import DeepWorkCore
@testable import DeepWorkApp

/// Exercise actual first-responder routing after SwiftUI inserts Focus. Testing
/// the segmented control alone cannot detect a view stealing keyboard focus.
extension NativeApplicationTests {
@Suite(.serialized)
@MainActor
struct TabFocusRegressionTests {
    enum FocusScenario: CaseIterable, Sendable { case setup, running, paused }

    @Test(arguments: FocusScenario.allCases)
    func testG012_J047ExplicitFocusActionMovesResponderAfterPanelInsertion(_ scenario: FocusScenario) async throws {
        prepareNativeTestApplication()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkExplicitFocus-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                             clock: TestTimerClock(), automaticRefresh: false)
        if scenario != .setup {
            model.focusSelection.wrappedValue = .preset(60)
            model.breakSelection.wrappedValue = .preset(10)
            model.startFocus()
            if scenario == .paused { model.pauseTimer() }
        }
        model.selectedTab = .journal
        let controller = WindowController(model: model)
        let window = try #require(controller.window)
        defer { window.orderOut(nil) }
        controller.showWindow(nil)
        try await Task.sleep(for: .milliseconds(100))
        let content = try #require(window.contentView)
        let tabs = try #require(findTabs(in: content))
        try #require(window.makeFirstResponder(tabs))

        // The empty Journal action and menu-bar action both call showFocus.
        // This crosses the real RootView insertion and NSWindow responder boundary.
        model.showFocus()
        try await Task.sleep(for: .milliseconds(100))
        content.layoutSubtreeIfNeeded()
        #expect(model.selectedTab == .focus)
        #expect(!model.consumeFocusControlRequest(), "The inserted panel must consume the explicit request once")
        if NSApplication.shared.isFullKeyboardAccessEnabled {
            #expect(window.firstResponder != nil && window.firstResponder !== tabs,
                    "An explicit Focus action must move focus into the inserted panel")
        } else {
            print("G-012/J-047: macOS Keyboard navigation is disabled; Focus picker/button first-responder acceptance requires the compiled-app check with it enabled.")
        }
        #expect(model.timer.isPaused == (scenario == .paused))
        await model.flushPersistence()
    }

    @Test func testG012AbandonedExplicitFocusRequestDoesNotStealSettingsOrLaterTabFocus() async throws {
        prepareNativeTestApplication()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkAbandonedFocus-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                             clock: TestTimerClock(), automaticRefresh: false)
        model.selectedTab = .settings
        model.feedbackMessage = "Preserve unsaved feedback while navigating"
        let controller = WindowController(model: model)
        let window = try #require(controller.window)
        defer { window.orderOut(nil) }
        controller.showWindow(nil)
        try await Task.sleep(for: .milliseconds(100))
        let content = try #require(window.contentView)
        let tabs = try #require(findTabs(in: content))
        try #require(window.makeFirstResponder(tabs))
        #expect(!model.consumeFocusControlRequest())

        // Supersede the request before SwiftUI can insert Focus. A view-only
        // cancellation hook cannot clear a request for a view that never mounts.
        model.showFocus()
        model.selectedTab = .settings
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.selectedTab == .settings && window.firstResponder === tabs)
        try press(115, in: window) // Home -> Focus is ordinary tab navigation.
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.selectedTab == .focus && window.firstResponder === tabs)

        // Also supersede a new request while the Focus panel already exists.
        model.showFocus()
        model.selectedTab = .settings
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.selectedTab == .settings && window.firstResponder === tabs)
        #expect(!model.consumeFocusControlRequest())
        #expect(model.feedbackMessage == "Preserve unsaved feedback while navigating")
        await model.flushPersistence()
    }

    @Test(arguments: FocusScenario.allCases)
    func testG012FocusAppearancePreservesTabFirstResponder(_ scenario: FocusScenario) async throws {
        prepareNativeTestApplication()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkTabFocus-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock()
        let model = AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                             clock: clock, automaticRefresh: false)
        model.feedbackMessage = "Unsaved keyboard-navigation draft"
        if scenario != .setup {
            model.focusSelection.wrappedValue = .preset(60)
            model.breakSelection.wrappedValue = .preset(10)
            model.startFocus()
            clock.advance(17)
            model.refreshTimer()
            if scenario == .paused { model.pauseTimer() }
        }
        let recordID = model.timer.liveRecord?.id
        let remaining = model.timer.remainingSeconds
        model.selectedTab = .settings
        let controller = WindowController(model: model)
        let window = try #require(controller.window)
        defer { window.orderOut(nil) }
        controller.showWindow(nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        let content = try #require(window.contentView)
        let tabs = try #require(findTabs(in: content))
        try #require(window.makeFirstResponder(tabs))

        // Right wraps Settings -> Focus. Wait for Focus.onAppear and deferred
        // window layout before checking which responder will receive Left.
        try press(124, in: window)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(model.selectedTab == .focus)
        try #require(window.firstResponder === tabs)
        try press(123, in: window)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(model.selectedTab == .settings)
        #expect(window.firstResponder === tabs)

        try press(115, in: window) // Home -> Focus
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(model.selectedTab == .focus)
        try #require(window.firstResponder === tabs)
        try press(119, in: window) // End -> Settings
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(model.selectedTab == .settings)
        #expect(window.firstResponder === tabs)
        #expect(model.timer.liveRecord?.id == recordID)
        #expect(model.timer.remainingSeconds == remaining)
        #expect(model.timer.isPaused == (scenario == .paused))
        #expect(model.feedbackMessage == "Unsaved keyboard-navigation draft")
        await model.flushPersistence()
    }

    private func findTabs(in view: NSView) -> TabSegmentedControl? {
        if let tabs = view as? TabSegmentedControl { return tabs }
        for child in view.subviews {
            if let tabs = findTabs(in: child) { return tabs }
        }
        return nil
    }

    private func press(_ code: UInt16, in window: NSWindow) throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                windowNumber: window.windowNumber, context: nil, characters: "",
                                                charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
        let responder = try #require(window.firstResponder)
        responder.keyDown(with: event)
    }
}

}
