import Testing
import AppKit
import SQLite3
@testable import DeepWorkApp
import DeepWorkCore

struct AppModelTests {
    @Test @MainActor func testG009_G012_J001NavigationKeepsOneOwnerAndEdits() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory))
        #expect(model.selectedTab == .journal)
        #expect(model.reportPeriod == .week)
        #expect(model.repeatExplanation == "Deep work, then break. Repeat until unchecked.")
        model.repeats.wrappedValue = false
        #expect(model.repeatExplanation == "One deep work cycle and one break, then stop.")
        model.focusSelection.wrappedValue = .preset(60)
        model.feedbackMessage = "Unsaved form edits"
        model.reportPeriod = .range
        model.scheduleDraft = WorkSchedule(mode: .anyDay)
        for tab in AppTab.allCases { model.selectedTab = tab }
        #expect(!(model.journal.configuration.repeats))
        #expect(model.journal.configuration.resolvedFocusMinutes == 60)
        #expect(model.feedbackMessage == "Unsaved form edits")
        #expect(model.reportPeriod == .range)
        #expect(model.scheduleDraft?.mode == .anyDay)
        #expect(model.journal.records.isEmpty)
        #expect(AppTab.settings.moving(1) == .focus)
        #expect(AppTab.focus.moving(-1) == .settings)
        await model.flushPersistence()
    }

    @Test @MainActor func testS021ExplicitDraftOnlySurvivesRelaunchAndPreservesConfiguration() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory))
        #expect(model.journalFailure == nil)
        #expect(model.settingsFailure == nil)
        model.feedbackType = .idea
        model.feedbackEmail = "person@example.com"
        model.feedbackMessage = "  Saved draft A  "
        #expect(model.saveFeedbackDraft() == nil)
        model.feedbackMessage = "Unsaved draft B"
        model.repeats.wrappedValue = false
        model.selectedTab = .focus
        model.persistCommittedState()
        await model.flushPersistence()
        let restored = AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory))
        #expect(restored.selectedTab == .journal)
        #expect(restored.feedbackMessage == "Saved draft A")
        #expect(restored.feedbackType == .idea)
        #expect(restored.feedbackEmail == "person@example.com")
        #expect(!(restored.journal.configuration.repeats))
        await restored.flushPersistence()
    }

    @Test @MainActor func testJ052_S021FailedWritesRetainMemoryAndExposeIndependentWarnings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not a directory".utf8).write(to: directory)
        let model = AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory))
        #expect(model.journalFailure != nil)
        #expect(model.settingsFailure != nil)
        #expect(model.journalStorageMessage.contains("Saving unavailable"))
        #expect(model.settingsStorageMessage.contains("could not be saved"))
        model.repeats.wrappedValue = false
        model.feedbackMessage = "Keep these edits"
        #expect(model.saveFeedbackDraft() == nil)
        #expect(!(model.journal.configuration.repeats))
        #expect(model.settings.feedbackDraft.message == "Keep these edits")
        await model.flushPersistence()
        #expect(model.feedbackStatus!.contains("could not be saved"))
    }

    @Test @MainActor func testS021CorruptSettingsArePreservedWhileJournalStillSaves() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Corrupt only the settings row; the independent journal remains usable.
        let initial = AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory))
        await initial.flushPersistence()
        #expect(initial.settingsFailure == nil)
        let file = directory.appendingPathComponent(SettingsStore.filename)
        var database: OpaquePointer?
        try #require(sqlite3_open(file.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        try #require(sqlite3_exec(database, "UPDATE settings SET payload=x'ff' WHERE id=1", nil, nil, nil) == SQLITE_OK)
        let model = AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory))
        #expect(model.journalFailure == nil)
        #expect(model.settingsFailure != nil)
        model.repeats.wrappedValue = false
        model.feedbackMessage = "A valid new draft"
        _ = model.saveFeedbackDraft()
        await model.flushPersistence()
        var statement: OpaquePointer?
        try #require(sqlite3_prepare_v2(database, "SELECT hex(payload) FROM settings WHERE id=1", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        try #require(sqlite3_step(statement) == SQLITE_ROW)
        let payload = try #require(sqlite3_column_text(statement, 0))
        #expect(String(cString: payload) == "FF")
        #expect(!(JournalStore(directory: directory).load().value.configuration.repeats))
    }

    @Test @MainActor func testG012NativeKeyHandlerWrapsAndHomeEndSelect() async {
        let control = TabSegmentedControl()
        control.segmentCount = 3
        @MainActor func press(_ code: UInt16) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                        windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                        isARepeat: false, keyCode: code)!
            control.keyDown(with: event)
        }
        control.selectedSegment = AppTab.settings.rawValue
        press(124); #expect(control.selectedSegment == AppTab.focus.rawValue)
        press(123); #expect(control.selectedSegment == AppTab.settings.rawValue)
        press(115); #expect(control.selectedSegment == AppTab.focus.rawValue)
        press(119); #expect(control.selectedSegment == AppTab.settings.rawValue)
    }
}

/// Native AppKit integration, using actual NSWindow state on the main actor.
/// Timer-dependent close behavior remains a Stage 2 acceptance obligation.
extension NativeApplicationTests {
@Suite(.serialized)
struct WindowIntegrationTests {
    @Test @MainActor func testG001_G006_G007_G008_G011NativeLifecycleAndG009PanelResizeRegression() async throws {
        prepareNativeTestApplication()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory))
        let controller = WindowController(model: model)
        let window = try #require(controller.window)
        defer { window.orderOut(nil) }
        controller.showWindow(nil)
        #expect(window.title == "Deep Work")
        #expect(window.standardWindowButton(.closeButton)?.accessibilityLabel() == "Close window and keep timer running")
        #expect(window.isVisible)
        #expect(window.styleMask.contains(.miniaturizable))
        #expect(window.styleMask.contains(.resizable))
        #expect(window.collectionBehavior.contains(.fullScreenPrimary))
        #expect(window.contentMinSize.width == 320)
        model.feedbackMessage = "An unsaved lifecycle draft"
        model.repeats.wrappedValue = false
        #expect(controller.windowShouldClose(window) == false)
        #expect(!window.isVisible)
        controller.showWindow(nil)
        #expect(window.isVisible)
        #expect(model.feedbackMessage == "An unsaved lifecycle draft")
        #expect(!model.journal.configuration.repeats)
        window.miniaturize(nil)
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(window.isMiniaturized)
        controller.showWindow(nil)
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(!window.isMiniaturized)
        let original = window.frame
        window.zoom(nil)
        #expect(window.frame != original)
        window.zoom(nil)
        #expect(window.frame == original)
        model.selectedTab = .settings
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(model.selectedTab == .settings)
        #expect(abs(window.contentLayoutRect.width - 560) < 1)
        model.selectedTab = .focus
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(abs(window.contentLayoutRect.width - 390) < 1)
        #expect(model.feedbackMessage == "An unsaved lifecycle draft")
        window.setContentSize(NSSize(width: 320, height: 420))
        window.contentView?.layoutSubtreeIfNeeded()
        func findTabs(_ view: NSView) -> TabSegmentedControl? {
            if let tabs = view as? TabSegmentedControl { return tabs }
            return view.subviews.lazy.compactMap { findTabs($0) }.first
        }
        let content = try #require(window.contentView)
        let tabs = try #require(findTabs(content))
        let tabBounds = tabs.convert(tabs.bounds, to: content)
        #expect(tabBounds.minX >= 0 && tabBounds.maxX <= content.bounds.width)
        #expect(tabs.segmentCount == 3 && tabs.isEnabled)
        for index in 0..<3 { #expect(tabs.isEnabled(forSegment: index)) }
        await model.flushPersistence()
    }
}

}
