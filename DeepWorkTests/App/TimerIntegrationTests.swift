import AppKit
import Foundation
import Testing
import DeepWorkCore
@testable import DeepWorkApp

@MainActor
final class TestTimerClock: TimerClock {
    var elapsed: TimeInterval = 0
    var date = Date(timeIntervalSince1970: 1_700_000_000)
    func now() -> TimerInstant { TimerInstant(elapsed: elapsed, wallDate: date) }
    func advance(_ seconds: TimeInterval) { elapsed += seconds; date += seconds }
}

extension NativeApplicationTests {
@Suite(.serialized)
@MainActor
struct TimerIntegrationTests {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func model(_ directory: URL, clock: TestTimerClock) -> AppModel {
        AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                 clock: clock, automaticRefresh: false)
    }
    private func configure(_ model: AppModel, focus: String = "1", rest: String = "1", repeats: Bool = true) {
        model.focusSelection.wrappedValue = .custom; model.breakSelection.wrappedValue = .custom
        model.customFocusText = focus; model.customBreakText = rest; model.repeats.wrappedValue = repeats
    }

    @Test func testF001_F009_AC02ExactValidationHandlerAndStoredChoices() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let app = model(directory, clock: clock)
        #expect(!app.canStart)
        #expect(app.configurationError == nil)
        #expect(app.customFocusText == "75" && app.customBreakText == "15")
        #expect(app.durationSummary == "Choose both durations to begin.")
        for invalid in ["", "1.5", "0", "481", "-1", "abc", "１２"] {
            configure(app, focus: invalid)
            #expect(!app.canStart)
            #expect(app.focusDurationError == "Choose a whole number from 1 to 480.")
            app.startFocus(); #expect(app.timer.state == .setup)
            configure(app, rest: invalid)
            #expect(!app.canStart)
            #expect(app.breakDurationError == "Choose a whole number from 1 to 480.")
            app.startFocus(); #expect(app.timer.state == .setup)
        }
        configure(app, focus: "480", rest: "1")
        #expect(app.canStart)
        #expect(app.durationSummary == "480 min deep → 1 min break")
        app.startFocus(); let id = app.timer.liveRecord?.id
        app.startFocus(); #expect(app.timer.liveRecord?.id == id)
        #expect(app.timer.countdownText == "480:00")
        app.endSession(); #expect(app.journal.records.isEmpty)
        app.focusSelection.wrappedValue = .preset(90); app.breakSelection.wrappedValue = .preset(20)
        #expect(app.configurationError == nil)
        #expect(app.durationSummary == "90 min deep → 20 min break")
        await app.flushPersistence()
        let restored = model(directory, clock: TestTimerClock())
        #expect(restored.journal.configuration.resolvedFocusMinutes == 90)
        #expect(restored.journal.configuration.resolvedBreakMinutes == 20)
        #expect(restored.customFocusText == "480" && restored.customBreakText == "1")
        restored.focusSelection.wrappedValue = .custom
        #expect(restored.journal.configuration.resolvedFocusMinutes == 480)
        await restored.flushPersistence()
    }

    @Test func testF016_F025_AC06_AC12SQLiteQuitRecoveryKeepsIDAndExcludesDowntime() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let app = model(directory, clock: clock)
        configure(app, repeats: false); app.startFocus()
        let id = try #require(app.timer.liveRecord?.id)
        clock.advance(17); await app.prepareForTermination()
        #expect(app.timer.isPaused)
        let persisted = JournalStore(directory: directory).load()
        #expect(persisted.failure == nil)
        #expect(persisted.value.activeCheckpoint?.remainingSeconds == 43)
        let newClock = TestTimerClock(); newClock.date += 86_400
        let restored = model(directory, clock: newClock)
        #expect(restored.selectedTab == .journal)
        #expect(restored.timer.isRecovered && restored.timer.isPaused)
        #expect(restored.timer.liveRecord?.id == id)
        #expect(restored.timer.liveRecord?.focusedSeconds == 17)
        newClock.advance(600); restored.refreshTimer()
        #expect(restored.timer.remainingSeconds == 43)
        restored.resumeTimer(); #expect(!restored.timer.isRecovered)
        newClock.advance(43); restored.refreshTimer()
        let record = try #require(restored.journal.records.first)
        #expect(record.id == id && record.outcome == .complete && record.focusedSeconds == 60)
        #expect(record.segments.count == 2)
        #expect(record.segments[1].startedAt.timeIntervalSince(record.segments[0].endedAt) >= 86_400)
        #expect(restored.timer.state == .break)
        await restored.flushPersistence()
        let saved = JournalStore(directory: directory).load().value
        #expect(saved.records.count == 1 && saved.activeCheckpoint?.phase == .break)
        try saved.validate()
    }

    @Test func testF025CrashUsesLastFiveSecondCheckpointWithoutClosedTime() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let app = model(directory, clock: clock)
        configure(app); app.startFocus(); await app.flushPersistence()
        clock.advance(4); app.refreshTimer(); await app.flushPersistence()
        #expect(JournalStore(directory: directory).load().value.activeCheckpoint?.remainingSeconds == 60)
        clock.advance(1); app.refreshTimer(); await app.flushPersistence()
        #expect(JournalStore(directory: directory).load().value.activeCheckpoint?.remainingSeconds == 55)
        clock.advance(4); app.refreshTimer() // Crash before the next scheduled checkpoint: no Quit flush.
        let restartedClock = TestTimerClock(); restartedClock.date += 100_000
        let restarted = model(directory, clock: restartedClock)
        #expect(restarted.timer.isPaused && restarted.timer.remainingSeconds == 55)
        #expect(restarted.timer.liveRecord?.focusedSeconds == 5)
        #expect(restarted.journal.records.isEmpty)
        await restarted.flushPersistence()
    }

    @Test func testF023_F024RecordsAndCheckpointCommitTogetherExactlyOnce() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let app = model(directory, clock: clock)
        configure(app); app.startFocus()
        clock.advance(305); app.refreshTimer(); app.refreshTimer()
        #expect(app.journal.records.count == 3)
        #expect(app.journal.records.allSatisfy { $0.focusedSeconds == 60 && $0.outcome == .complete })
        #expect(app.timer.state == .break && app.timer.remainingSeconds == 55)
        await app.flushPersistence()
        let saved = JournalStore(directory: directory).load().value
        #expect(Set(saved.records.map(\.id)).count == 3)
        #expect(saved.activeCheckpoint?.phase == .break)
        #expect(saved.activeCheckpoint?.remainingSeconds == 55)
        try saved.validate()
        let restored = model(directory, clock: TestTimerClock())
        #expect(restored.timer.isPaused && restored.timer.state == .break)
        #expect(restored.journal.records == saved.records)
        await restored.flushPersistence()
    }

    @Test func testF019_F022_AC07_AC08_AC13PartialAndZeroSQLiteRows() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let app = model(directory, clock: clock)
        configure(app); app.startFocus(); app.endSession()
        #expect(app.journal.records.isEmpty)
        app.startFocus(); clock.advance(17); app.pauseTimer(); clock.advance(600)
        app.advanceTimer(expectedPhaseID: try #require(app.timer.phaseID))
        #expect(app.timer.state == .break && !app.timer.isPaused)
        #expect(app.journal.records.first?.focusedSeconds == 17)
        #expect(app.journal.records.first?.outcome == .partial)
        app.pauseTimer(); app.advanceTimer(expectedPhaseID: try #require(app.timer.phaseID))
        #expect(app.timer.state == .focus && !app.timer.isPaused)
        app.endSession(); #expect(app.journal.records.count == 1)
        await app.flushPersistence()
        let saved = JournalStore(directory: directory).load().value
        #expect(saved.records.count == 1 && saved.activeCheckpoint == nil)
        try saved.validate()
    }

    @Test func testF010_F018_AC04_AC05CompletionDoesNotRestartAndCaptionWaitsForCommit() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let app = model(directory, clock: clock)
        configure(app, repeats: false); app.startFocus(); clock.advance(120); app.pauseTimer()
        #expect(app.timer.state == .complete)
        #expect(app.timerCaption == "Saving to your journal…")
        app.repeats.wrappedValue = true
        #expect(app.timer.state == .complete)
        #expect(app.repeatExplanation == "Your next session will repeat.")
        await app.flushPersistence(); #expect(app.timerCaption == "Saved to your journal.")
        app.restartTimer()
        #expect(app.timer.state == .focus && app.timer.remainingSeconds == 60)
        #expect(app.timer.liveRecord?.id != app.journal.records.first?.id)
        #expect(app.journal.records.count == 1)
        await app.flushPersistence()
    }

    @Test func testF024_J052FailedStorageKeepsTimerUsableAndNeverClaimsSaved() async throws {
        let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        try Data("blocked".utf8).write(to: path)
        let clock = TestTimerClock(); let app = model(path, clock: clock)
        configure(app, repeats: false); app.startFocus(); clock.advance(120); app.refreshTimer()
        await app.flushPersistence()
        #expect(app.timer.state == .complete && app.journal.records.count == 1)
        #expect(app.journalFailure != nil)
        #expect(app.timerCaption == "Your session is in memory. It could not be saved.")
        #expect(app.journalStorageMessage.contains("Saving unavailable"))
        #expect(try String(contentsOf: path) == "blocked")
        app.restartTimer(); #expect(app.timer.state == .focus)
        await app.flushPersistence()
    }

    @Test func testG003_G006_F024_AC11HiddenNativeWindowKeepsTimerAndFocusReopen() async throws {
        prepareNativeTestApplication()
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let app = model(directory, clock: clock)
        let controller = WindowController(model: app)
        let window = try #require(controller.window); defer { window.orderOut(nil) }
        configure(app); app.startFocus(); app.selectedTab = .settings
        controller.showWindow(nil); #expect(!controller.windowShouldClose(window))
        #expect(!window.isVisible)
        clock.advance(130); app.refreshTimer()
        #expect(app.journal.records.count == 1 && app.timer.state == .focus && app.timer.remainingSeconds == 50)
        let id = app.timer.liveRecord?.id
        app.showFocus(); controller.showWindow(nil)
        #expect(window.isVisible && app.selectedTab == .focus)
        #expect(app.timer.liveRecord?.id == id)
        app.pauseTimer(); #expect(!controller.windowShouldClose(window))
        clock.advance(600); app.showFocus(); controller.showWindow(nil)
        #expect(app.timer.isPaused && app.timer.remainingSeconds == 50)
        #expect(app.timer.liveRecord?.id == id)
        await app.flushPersistence()
    }
    @Test func testG009TabSwitchReconcilesDeadlineBeforeJournalIsShown() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let app = model(directory, clock: clock)
        configure(app); app.selectedTab = .focus; app.startFocus()
        clock.advance(60); app.selectedTab = .journal
        #expect(app.timer.state == .break && app.journal.records.count == 1)
        await app.flushPersistence()
        #expect(JournalStore(directory: directory).load().value.records.count == 1)
    }

    @Test func testF025QuitDrainRejectsTimerAndPreferenceMutations() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let app = model(directory, clock: clock)
        configure(app); app.startFocus(); clock.advance(17)
        let quitting = Task { await app.prepareForTermination() }
        while !app.isTerminating { await Task.yield() }
        app.resumeTimer(); app.endSession(); app.repeats.wrappedValue = false
        app.focusSelection.wrappedValue = .preset(90)
        clock.advance(600); app.refreshTimer()
        await quitting.value
        #expect(app.timer.isPaused && app.timer.state == .focus)
        #expect(app.timer.remainingSeconds == 43)
        #expect(app.journal.configuration.repeats)
        #expect(app.journal.configuration.focusSelection == .custom)
        let saved = JournalStore(directory: directory).load().value
        #expect(saved.activeCheckpoint?.remainingSeconds == 43)
        #expect(saved.activeCheckpoint?.focusRecord?.focusedSeconds == 17)
    }

}

}
