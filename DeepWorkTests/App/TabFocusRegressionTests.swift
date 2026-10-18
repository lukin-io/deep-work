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
