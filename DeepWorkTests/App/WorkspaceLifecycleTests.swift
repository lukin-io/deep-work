import AppKit
import Foundation
import Testing
import DeepWorkCore
@testable import DeepWorkApp

extension NativeApplicationTests {
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct WorkspaceLifecycleTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkWorkspace-\(UUID())")
    }

    private func model(_ directory: URL, clock: TestTimerClock) -> AppModel {
        AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                 clock: clock, automaticRefresh: false, reportingTimeZone: .gmt)
    }

    private func configure(_ model: AppModel, repeats: Bool = true) {
        model.focusSelection.wrappedValue = .custom
        model.breakSelection.wrappedValue = .custom
        model.customFocusText = "1"
        model.customBreakText = "1"
        model.repeats.wrappedValue = repeats
    }

    @Test func testF024_AC10WorkspaceSleepSealsBeforePeriodicCheckpointWithoutPausingOrSavingDraft() async throws {
        prepareNativeTestApplication()
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let app = model(directory, clock: clock)
        let observer = WorkspaceLifecycleController(model: app)
        defer { withExtendedLifetime(observer) {} }
        configure(app)
        app.feedbackMessage = "An explicitly saved draft."
        #expect(app.saveFeedbackDraft() == nil)
        await app.flushPersistence()
        app.feedbackMessage = "An unsaved edit must remain unsaved."
        app.startFocus(); await app.flushPersistence()
        clock.advance(3)

        // This is the actual production center, not the default app center.
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification,
                                                   object: NSWorkspace.shared)
        #expect(!app.timer.isPaused && app.timer.remainingSeconds == 57)
        await app.flushPersistence()
        let saved = JournalStore(directory: directory).load()
        #expect(saved.failure == nil && saved.value.records.isEmpty)
        #expect(saved.value.activeCheckpoint?.remainingSeconds == 57)
        #expect(saved.value.activeCheckpoint?.focusRecord?.focusedSeconds == 3)
        #expect(SettingsStore(directory: directory).load().value.feedbackDraft.message == "An explicitly saved draft.")
        #expect(app.feedbackMessage == "An unsaved edit must remain unsaved.")
    }

    @Test func testF024_AC10WakeReconcilesEveryBoundaryOnceDespiteCivilClockChange() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let start = clock.date; let app = model(directory, clock: clock)
        let center = NotificationCenter()
        let observer = WorkspaceLifecycleController(model: app, notificationCenter: center)
        defer { withExtendedLifetime(observer) {} }
        configure(app); app.startFocus()
        clock.advance(17)
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        await app.flushPersistence()
        clock.advance(433)
        clock.date -= 86_400
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(app.timer.state == .break && !app.timer.isPaused && app.timer.remainingSeconds == 30)
        #expect(app.journal.records.count == 4)
        #expect(Set(app.journal.records.map(\.id)).count == 4)
        #expect(app.journal.records.map(\.focusedSeconds) == [60, 60, 60, 60])
        #expect(app.journal.records.map(\.endedAt) == [60.0, 180, 300, 420].map { start.addingTimeInterval($0) })
        await app.flushPersistence()
        let saved = JournalStore(directory: directory).load()
        #expect(saved.failure == nil && saved.value.records == app.journal.records)
        #expect(saved.value.activeCheckpoint?.phase == .break)
        #expect(saved.value.activeCheckpoint?.remainingSeconds == 30)
        try saved.value.validate()
    }

    @Test(arguments: [false, true])
    func testF016_F024_AC06PausedFocusAndBreakStayPausedAcrossWorkspaceEvents(inBreak: Bool) async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let app = model(directory, clock: clock)
        let center = NotificationCenter()
        let observer = WorkspaceLifecycleController(model: app, notificationCenter: center)
        defer { withExtendedLifetime(observer) {} }
        configure(app); app.startFocus()
        clock.advance(inBreak ? 77 : 17)
        app.pauseTimer()
        let phaseID = app.timer.phaseID
        let records = app.journal.records
        let focusedSeconds = app.timer.liveRecord?.focusedSeconds
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        clock.advance(600)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(app.timer.isPaused && app.timer.remainingSeconds == 43)
        #expect(app.timer.phaseID == phaseID && app.journal.records == records)
        #expect(app.timer.liveRecord?.focusedSeconds == focusedSeconds)
        await app.flushPersistence()
        #expect(JournalStore(directory: directory).load().value.activeCheckpoint?.remainingSeconds == 43)
    }

    @Test func testF025_AC12RecoveryUsesCommittedSleepCheckpointWithoutProcessDowntime() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let app = model(directory, clock: clock)
        let center = NotificationCenter()
        let observer = WorkspaceLifecycleController(model: app, notificationCenter: center)
        defer { withExtendedLifetime(observer) {} }
        configure(app); app.startFocus()
        let recordID = try #require(app.timer.liveRecord?.id)
        clock.advance(3)
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        await app.flushPersistence()

        let nextClock = TestTimerClock(); nextClock.date += 86_400
        let recovered = model(directory, clock: nextClock)
        let nextCenter = NotificationCenter()
        let nextObserver = WorkspaceLifecycleController(model: recovered, notificationCenter: nextCenter)
        defer { withExtendedLifetime(nextObserver) {} }
        nextClock.advance(600)
        nextCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(recovered.timer.isRecovered && recovered.timer.isPaused)
        #expect(recovered.timer.remainingSeconds == 57 && recovered.journal.records.isEmpty)
        #expect(recovered.timer.liveRecord?.id == recordID && recovered.timer.liveRecord?.focusedSeconds == 3)
        recovered.resumeTimer(); nextClock.advance(57)
        nextCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await recovered.flushPersistence()
        let saved = JournalStore(directory: directory).load().value
        #expect(saved.records.count == 1 && saved.records.first?.id == recordID)
        #expect(saved.records.first?.focusedSeconds == 60)
        #expect(saved.records.first?.segments.count == 2)
        try saved.validate()
    }

    @Test func testF024_J052_AC27WorkspaceEventsKeepTimingUsableWhenStorageFails() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        try Data("preserve this file".utf8).write(to: directory)
        let clock = TestTimerClock(); let app = model(directory, clock: clock)
        let center = NotificationCenter()
        let observer = WorkspaceLifecycleController(model: app, notificationCenter: center)
        defer { withExtendedLifetime(observer) {} }
        configure(app); app.startFocus(); clock.advance(17)
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        clock.advance(133)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await app.flushPersistence()
        #expect(app.timer.state == .focus && !app.timer.isPaused && app.timer.remainingSeconds == 30)
        #expect(app.journal.records.count == 1 && app.journal.records.first?.focusedSeconds == 60)
        #expect(app.journalFailure != nil && app.settingsFailure != nil)
        #expect(app.journalStorageMessage.contains("Saving unavailable"))
        #expect(try String(contentsOf: directory, encoding: .utf8) == "preserve this file")
        app.pauseTimer(); #expect(app.timer.isPaused)
        await app.flushPersistence()
    }

    @Test func testF024_AC10BackgroundDeliveryHopsToMainActorAndReleasedObserversStop() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let app = model(directory, clock: clock)
        let center = NotificationCenter()
        var observer: WorkspaceLifecycleController? = WorkspaceLifecycleController(model: app, notificationCenter: center)
        #expect(observer != nil)
        configure(app); app.startFocus(); clock.advance(17)
        await Task.detached {
            center.post(name: NSWorkspace.willSleepNotification, object: nil)
        }.value
        try await waitUntil { app.timer.remainingSeconds == 43 }
        await app.flushPersistence()
        #expect(JournalStore(directory: directory).load().value.activeCheckpoint?.remainingSeconds == 43)
        clock.advance(60)
        await Task.detached {
            center.post(name: NSWorkspace.didWakeNotification, object: nil)
        }.value
        try await waitUntil { app.timer.state == .break }
        #expect(app.journal.records.count == 1)
        await app.flushPersistence()
        observer = nil
        clock.advance(60)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(app.timer.state == .break && app.timer.remainingSeconds == 43)
        #expect(app.journal.records.count == 1)
    }

    @Test func testF024_AC10UnrelatedEventsAndIdleStatesDoNotCreateWork() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let app = model(directory, clock: clock)
        let center = NotificationCenter()
        let observer = WorkspaceLifecycleController(model: app, notificationCenter: center)
        defer { withExtendedLifetime(observer) {} }
        clock.advance(600)
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(app.timer.state == .setup && app.journal.records.isEmpty)
        configure(app, repeats: false); app.startFocus(); clock.advance(17)
        center.post(name: Notification.Name("UnrelatedWorkspaceEvent"), object: nil)
        #expect(app.timer.remainingSeconds == 60)
        clock.advance(103)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(app.timer.state == .complete && app.journal.records.count == 1)
        clock.advance(600)
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(app.timer.state == .complete && app.journal.records.count == 1)
        await app.flushPersistence()
        let saved = JournalStore(directory: directory).load().value
        #expect(saved.activeCheckpoint == nil && saved.records.count == 1)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(condition())
    }
}
}
