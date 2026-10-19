import AppKit
import Testing
import DeepWorkCore
@testable import DeepWorkApp

@MainActor
private final class RecordingAnnouncements: AccessibilityAnnouncing {
    struct Entry: Equatable {
        let message: String
        let priority: NSAccessibilityPriorityLevel
    }
    var entries: [Entry] = []
    func announce(_ message: String, priority: NSAccessibilityPriorityLevel) {
        entries.append(Entry(message: message, priority: priority))
    }
    var messages: [String] { entries.map(\.message) }
    func reset() { entries.removeAll() }
}

extension NativeApplicationTests {
@Suite(.serialized)
@MainActor
struct AccessibilityAnnouncementTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkAnnouncements-\(UUID())")
    }

    private func model(_ directory: URL, clock: TestTimerClock, recorder: RecordingAnnouncements) -> AppModel {
        AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                 clock: clock, automaticRefresh: false, reportingTimeZone: .gmt, announcements: recorder)
    }

    private func configure(_ model: AppModel, repeats: Bool = true) {
        model.focusSelection.wrappedValue = .custom
        model.breakSelection.wrappedValue = .custom
        model.customFocusText = "1"
        model.customBreakText = "1"
        model.repeats.wrappedValue = repeats
    }

    @Test func testG013NativeAnnouncementUsesApplicationElementAndRequiredKeysWithoutKeyWindow() {
        prepareNativeTestApplication()
        let application = NSApplication.shared
        var received: [(AnyObject, NSAccessibility.Notification, [NSAccessibility.NotificationUserInfoKey: Any])] = []
        let announcer = NativeAccessibilityAnnouncer(application: { application }) { element, notification, info in
            received.append((element, notification, info))
        }
        announcer.announce("Deep work paused.", priority: .medium)
        announcer.announce("Choose a valid value.", priority: .high)
        #expect(received.count == 2)
        #expect(received.allSatisfy { $0.0 === application && $0.1 == .announcementRequested })
        #expect(received[0].2[.announcement] as? String == "Deep work paused.")
        #expect(received[0].2[.priority] as? Int == NSAccessibilityPriorityLevel.medium.rawValue)
        #expect(received[1].2[.priority] as? Int == NSAccessibilityPriorityLevel.high.rawValue)
        #expect(received.allSatisfy { $0.2.count == 2 })
        // This verifies the native dispatch boundary, not VoiceOver reception.
    }

    @Test func testG013MissingApplicationAndEmptyMessagesDoNotPost() {
        prepareNativeTestApplication()
        var posts = 0
        let missing = NativeAccessibilityAnnouncer(application: { nil }) { _, _, _ in posts += 1 }
        missing.announce("Deep work started.", priority: .medium)
        let present = NativeAccessibilityAnnouncer(post: { _, _, _ in posts += 1 })
        present.announce("", priority: .medium)
        #expect(posts == 0)
    }

    @Test func testG013_F016_F017JournalAndSettingsReceiveActionsButCountdownAndNoOpsStaySilent() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let recorder = RecordingAnnouncements()
        let app = model(directory, clock: clock, recorder: recorder)
        #expect(recorder.entries.isEmpty)
        app.startFocus() // Missing choices cannot claim success.
        #expect(recorder.entries.isEmpty)
        configure(app)
        #expect(app.selectedTab == .journal)
        app.startFocus()
        #expect(recorder.messages == ["Deep work started."])
        app.startFocus()
        for _ in 0..<8 { clock.advance(0.25); app.refreshTimer() }
        #expect(recorder.messages == ["Deep work started."])
        app.selectedTab = .settings
        app.pauseTimer(); app.pauseTimer()
        clock.advance(600); app.refreshTimer()
        app.resumeTimer(); app.resumeTimer()
        app.repeats.wrappedValue = false
        app.repeats.wrappedValue = false
        app.endSession(); app.endSession()
        #expect(recorder.messages == [
            "Deep work started.", "Deep work paused.", "Deep work resumed.",
            "Repeat cycles off. Stops after your upcoming break.",
            "Session ended. Your duration choices are ready."
        ])
        #expect(recorder.entries.allSatisfy { $0.priority == .medium })
        await app.flushPersistence()
        #expect(JournalStore(directory: directory).load().value.records.first?.focusedSeconds == 2)
    }

    @Test func testG013_F023_F024DelayedBoundariesSpeakOneCurrentStateAndExactDeadlinePauseIsTruthful() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let recorder = RecordingAnnouncements()
        let app = model(directory, clock: clock, recorder: recorder)
        configure(app); app.startFocus(); recorder.reset()
        clock.advance(305); app.refreshTimer(); app.refreshTimer()
        #expect(recorder.messages == ["3 focus cycles completed. Break started."])
        #expect(app.journal.records.count == 3)
        clock.advance(55); app.refreshTimer()
        #expect(recorder.messages.last == "Deep work started.")
        recorder.reset()
        clock.advance(60); app.pauseTimer()
        #expect(recorder.messages == ["One focus cycle completed. Break paused."])
        #expect(app.timer.state == .break && app.timer.isPaused)
        app.resumeTimer()
        #expect(recorder.messages.last == "Break resumed.")
        await app.flushPersistence()
        #expect(JournalStore(directory: directory).load().value.records.count == 4)
    }

    @Test func testG013_F024SinglePairCompletionRepeatChoiceAndStartAgainAreDistinct() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let recorder = RecordingAnnouncements()
        let app = model(directory, clock: clock, recorder: recorder)
        configure(app, repeats: false); app.startFocus(); recorder.reset()
        clock.advance(120); app.refreshTimer()
        #expect(recorder.messages == ["One focus cycle completed. Cycle complete."])
        recorder.reset()
        app.repeats.wrappedValue = true
        #expect(recorder.messages == ["Repeat cycles on. Your next session will repeat."])
        #expect(app.timer.state == .complete)
        app.restartTimer()
        #expect(recorder.messages.last == "Deep work started.")
        await app.flushPersistence()
    }

    @Test func testG013_G006_G003NativeCloseAndStatusButtonAnnounceWithoutChangingRunningOrPausedCycle() async throws {
        prepareNativeTestApplication()
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let recorder = RecordingAnnouncements()
        let app = model(directory, clock: clock, recorder: recorder)
        let controller = WindowController(model: app)
        let window = try #require(controller.window); defer { window.orderOut(nil) }
        let menu = MenuBarController(model: app, windowController: controller, activateApplication: {})
        let button = try #require(menu.button)
        controller.showWindow(nil)
        #expect(recorder.entries.isEmpty)
        requestNativeWindowClose(window)
        #expect(recorder.messages == ["Window hidden. Use the menu-bar timer to reopen Deep Work."])
        controller.showWindow(nil)
        #expect(recorder.messages.last == "Deep Work window shown. Journal.")
        configure(app); app.startFocus(); app.selectedTab = .settings; recorder.reset()
        let recordID = app.timer.liveRecord?.id
        requestNativeWindowClose(window)
        #expect(recorder.messages == ["Window hidden. Your timer keeps running. Use the menu-bar timer to reopen Deep Work."])
        #expect(!window.isVisible && !app.timer.isPaused)
        clock.advance(17); app.refreshTimer()
        #expect(recorder.entries.count == 1)
        #expect(button.sendAction(button.action, to: button.target))
        #expect(recorder.messages.last == "Deep Work window shown. Focus. Deep work, 00:43 remaining.")
        #expect(app.timer.liveRecord?.id == recordID && !app.timer.isPaused)
        recorder.reset()
        controller.showWindow(nil) // Already-visible focus is not a reopen.
        #expect(recorder.entries.isEmpty)
        app.pauseTimer(); recorder.reset()
        requestNativeWindowClose(window)
        clock.advance(600); app.refreshTimer()
        #expect(button.sendAction(button.action, to: button.target))
        #expect(recorder.messages == [
            "Window hidden. Your timer stays paused. Use the menu-bar timer to reopen Deep Work.",
            "Deep Work window shown. Focus. Deep work paused, 00:43 remaining."
        ])
        #expect(app.timer.liveRecord?.id == recordID && app.timer.isPaused)
        await app.flushPersistence()
        withExtendedLifetime(menu) {}
    }

    @Test func testG013_F025RecoveredFirstPresentationAnnouncesOnceAndQuitCannotStartAnotherCycle() async throws {
        prepareNativeTestApplication()
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let originalClock = TestTimerClock(); let originalRecorder = RecordingAnnouncements()
        let original = model(directory, clock: originalClock, recorder: originalRecorder)
        configure(original); original.startFocus(); originalClock.advance(17)
        #expect(await original.prepareForTermination())
        let clock = TestTimerClock(); clock.date += 86_400
        let recorder = RecordingAnnouncements(); let app = model(directory, clock: clock, recorder: recorder)
        #expect(recorder.entries.isEmpty)
        let controller = WindowController(model: app)
        let window = try #require(controller.window); defer { window.orderOut(nil) }
        controller.showWindow(nil); controller.showWindow(nil)
        #expect(recorder.messages == ["Your unfinished session is paused at its last saved point. Resume when you’re ready."])
        clock.advance(600); app.refreshTimer()
        #expect(recorder.entries.count == 1 && app.timer.remainingSeconds == 43)
        app.resumeTimer()
        #expect(recorder.messages.last == "Deep work resumed.")
        #expect(await app.prepareForTermination())
        recorder.reset()
        app.startFocus(); app.resumeTimer(); app.restartTimer(); app.endSession(); app.repeats.wrappedValue = false
        #expect(recorder.entries.isEmpty)
    }

    @Test func testG013SharedErrorRoutePreservesHighPriority() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = RecordingAnnouncements()
        let app = model(directory, clock: TestTimerClock(), recorder: recorder)
        app.announce("Choose a valid reporting day.", priority: .high)
        #expect(recorder.entries == [.init(message: "Choose a valid reporting day.", priority: .high)])
        await app.flushPersistence()
    }
}
}
