import AppKit
import Foundation
import Testing
import DeepWorkCore
@testable import DeepWorkApp

extension NativeApplicationTests {
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct SlackIntegrationTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkSlackIntegration-\(UUID())")
    }

    private func model(_ directory: URL, clock: TestTimerClock, client: RecordingSlackClient,
                       exporter: (any CSVFileExporting)? = nil) -> AppModel {
        let slack = SlackStatusController(client: client, store: SlackStore(directory: directory), now: { clock.date })
        return AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                        clock: clock, automaticRefresh: false, csvFileExporter: exporter, slack: slack)
    }

    private func configure(_ app: AppModel, repeats: Bool = true) {
        app.focusSelection.wrappedValue = .custom; app.breakSelection.wrappedValue = .custom
        app.customFocusText = "1"; app.customBreakText = "1"; app.repeats.wrappedValue = repeats
    }

    private func flush(_ app: AppModel) async {
        await app.flushPersistence()
        await app.slack?.flush()
    }

    @Test func testF027_F028_AC28SetupStartPauseResumeAndTicksUseOneOwnedStatusPerCycle() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let client = RecordingSlackClient(); let previous = client.remote
        let app = model(directory, clock: clock, client: client)
        configure(app); await flush(app)
        #expect(client.writes.isEmpty && client.reads == 0)
        app.startFocus(); await flush(app)
        let cycle = try #require(app.timer.phaseID)
        let receipt = try #require(try await SlackStore(directory: directory).load().ownership)
        #expect(receipt.cycleID == cycle && receipt.previous == previous)
        #expect(client.writes == [.focus] && client.reads == 1)
        clock.advance(17); app.pauseTimer(); await flush(app)
        clock.advance(600); app.refreshTimer(); await flush(app)
        #expect(app.timer.isPaused && app.timer.remainingSeconds == 43)
        #expect(client.remote == .focus && client.writes == [.focus])
        app.resumeTimer()
        for _ in 0..<10 { app.refreshTimer() }
        await flush(app)
        #expect(app.timer.phaseID == cycle && !app.timer.isPaused)
        #expect(client.writes == [.focus] && client.reads == 1)
        app.endSession(); await flush(app)
        #expect(client.writes == [.focus, previous] && client.remote == previous)
        #expect(try await SlackStore(directory: directory).load().ownership == nil)
        #expect(JournalStore(directory: directory).load().value.records.first?.focusedSeconds == 17)
    }

    @Test func testG006_F028_AC11NativeWindowCloseKeepsSlackAndTimerRunning() async throws {
        prepareNativeTestApplication()
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let client = RecordingSlackClient()
        let app = model(directory, clock: clock, client: client)
        let controller = WindowController(model: app)
        let window = try #require(controller.window); defer { window.orderOut(nil) }
        controller.showWindow(nil)
        configure(app); app.startFocus(); await flush(app)
        let cycle = app.timer.phaseID
        requestNativeWindowClose(window)
        clock.advance(9); app.refreshTimer(); await flush(app)
        #expect(!window.isVisible && !app.timer.isPaused)
        #expect(app.timer.phaseID == cycle && app.timer.remainingSeconds == 51)
        #expect(client.remote == .focus && client.writes == [.focus])
        #expect(try await SlackStore(directory: directory).load().ownership?.cycleID == cycle)
        #expect(JournalStore(directory: directory).load().value.activeCheckpoint?.remainingSeconds == 51)
        app.endSession(); await flush(app)
    }

    @Test func testF023_F028_AC28NaturalBreakRestoresAndNextFocusOwnsNewCycle() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let client = RecordingSlackClient(); let previous = client.remote
        let app = model(directory, clock: clock, client: client)
        configure(app); app.startFocus(); await flush(app)
        let firstCycle = app.timer.phaseID
        clock.advance(60); app.refreshTimer(); await flush(app)
        #expect(app.timer.state == .break && client.remote == previous)
        #expect(client.writes == [.focus, previous])
        #expect(try await SlackStore(directory: directory).load().ownership == nil)
        app.pauseTimer(); app.resumeTimer(); await flush(app)
        #expect(client.writes == [.focus, previous])
        clock.advance(60); app.refreshTimer(); await flush(app)
        #expect(app.timer.state == .focus && app.timer.phaseID != firstCycle)
        #expect(client.writes == [.focus, previous, .focus])
        #expect(try await SlackStore(directory: directory).load().ownership?.cycleID == app.timer.phaseID)
        #expect(JournalStore(directory: directory).load().value.records.first?.focusedSeconds == 60)
        app.endSession(); await flush(app)
    }

    @Test func testF024_F028_AC28SinglePairCompletionDoesNotReapplyAndEndWhilePausedRestores() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let client = RecordingSlackClient(); let previous = client.remote
        let app = model(directory, clock: clock, client: client)
        configure(app, repeats: false); app.startFocus(); await flush(app)
        clock.advance(60); app.refreshTimer(); await flush(app)
        clock.advance(60); app.refreshTimer(); await flush(app)
        #expect(app.timer.state == .complete && client.writes == [.focus, previous])
        app.repeats.wrappedValue = true; await flush(app)
        #expect(client.writes == [.focus, previous])
        app.restartTimer(); await flush(app)
        clock.advance(3); app.pauseTimer(); await flush(app)
        app.endSession(); await flush(app)
        #expect(client.writes == [.focus, previous, .focus, previous])
        #expect(try await SlackStore(directory: directory).load().ownership == nil)
    }

    @Test func testF028_AC28MissingAccountAndFailedCredentialsNeverBlockLocalTimerOrSQLite() async throws {
        for credentialFailure in [false, true] {
            let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
            let clock = TestTimerClock(); let client = RecordingSlackClient()
            client.account = nil; client.loadFailure = credentialFailure
            let app = model(directory, clock: clock, client: client)
            configure(app, repeats: false); app.startFocus(); await flush(app)
            clock.advance(60); app.refreshTimer(); await flush(app)
            #expect(app.timer.state == .break && app.journal.records.count == 1)
            #expect(client.writes.isEmpty && client.reads == 0)
            #expect(JournalStore(directory: directory).load().value.records.first?.focusedSeconds == 60)
            #expect((app.slack?.failureMessage != nil) == credentialFailure)
            #expect(try await SlackStore(directory: directory).load().ownership == nil)
            // No owned status means locked credentials do not obstruct Quit.
            #expect(await app.prepareForTermination())
        }
    }

    @Test func testF028_AC28RejectedRemoteSetKeepsRecoverableReceiptAndTimerAccounting() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let client = RecordingSlackClient(); let previous = client.remote
        client.setFailure = true
        let app = model(directory, clock: clock, client: client)
        configure(app); app.startFocus(); await flush(app)
        #expect(client.remote == previous && app.slack?.failureMessage != nil)
        #expect(try await SlackStore(directory: directory).load().ownership != nil)
        clock.advance(11); app.refreshTimer(); await app.flushPersistence()
        #expect(!app.timer.isPaused && app.timer.remainingSeconds == 49)
        #expect(JournalStore(directory: directory).load().value.activeCheckpoint?.remainingSeconds == 49)
        client.setFailure = false; await app.slack?.retry()
        #expect(client.remote == .focus && app.slack?.failureMessage == nil)
        app.endSession(); await flush(app)
        #expect(client.remote == previous && app.journal.records.first?.focusedSeconds == 11)
    }

    @Test func testF025_F028_AC28QuitFailureRetainsPausedCheckpointAndReceiptThenRetriesRestore() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let client = RecordingSlackClient(); let previous = client.remote
        let app = model(directory, clock: clock, client: client)
        configure(app); app.startFocus(); await flush(app)
        let cycle = app.timer.phaseID
        clock.advance(17); client.profileFailure = true
        #expect(!(await app.prepareForTermination()))
        #expect(app.timer.isPaused && !app.isTerminating && client.remote == .focus)
        #expect(app.lifecycleFailureMessage?.contains("Slack changes could not be saved or restored") == true)
        #expect(app.lifecycleFailureMessage?.contains("recovery receipt stays on this Mac") == true)
        #expect(try await SlackStore(directory: directory).load().ownership?.cycleID == cycle)
        #expect(JournalStore(directory: directory).load().value.activeCheckpoint?.remainingSeconds == 43)
        client.profileFailure = false
        #expect(await app.prepareForTermination())
        #expect(client.remote == previous && app.lifecycleFailureMessage == nil)
        #expect(try await SlackStore(directory: directory).load().ownership == nil)
    }

    @Test func testF025_F028_AC28RelaunchRestoresPendingStatusButRecoveredFocusWaitsForResume() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let firstClock = TestTimerClock(); let client = RecordingSlackClient(); let previous = client.remote
        let first = model(directory, clock: firstClock, client: client)
        configure(first); first.startFocus(); await flush(first)
        firstClock.advance(17); first.refreshTimer(); await flush(first)
        let savedRecordID = first.timer.liveRecord?.id
        // Simulate process death using its last committed checkpoint and
        // receipt. No Quit restoration runs on the first model.
        let clock = TestTimerClock(); clock.date += 86_400
        let restored = model(directory, clock: clock, client: client)
        await flush(restored)
        let recoveredCycle = restored.timer.phaseID
        #expect(restored.timer.isRecovered && restored.timer.isPaused)
        #expect(restored.timer.liveRecord?.id == savedRecordID && restored.timer.remainingSeconds == 43)
        #expect(client.remote == previous && client.writes == [.focus, previous])
        #expect(try await SlackStore(directory: directory).load().ownership == nil)
        clock.advance(600); restored.refreshTimer(); restored.pauseTimer(); await flush(restored)
        #expect(client.writes == [.focus, previous] && restored.timer.remainingSeconds == 43)
        restored.resumeTimer(); await flush(restored)
        #expect(!restored.timer.isRecovered && !restored.timer.isPaused)
        #expect(client.writes == [.focus, previous, .focus])
        #expect(try await SlackStore(directory: directory).load().ownership?.cycleID == recoveredCycle)
        restored.endSession(); await flush(restored)
    }

    @Test func testF028_AC28SlowRemoteWriteDoesNotDelayTimerOrLocalSQLiteAndQuitDrainsAcceptedWrite() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let client = RecordingSlackClient(); let previous = client.remote
        let app = model(directory, clock: clock, client: client)
        configure(app); await flush(app)
        client.holdWrite = true; app.startFocus()
        try await waitUntil { client.gate != nil }
        #expect(try await SlackStore(directory: directory).load().ownership != nil)
        clock.advance(17); app.refreshTimer(); await app.flushPersistence()
        #expect(!app.timer.isPaused && app.timer.remainingSeconds == 43)
        #expect(JournalStore(directory: directory).load().value.activeCheckpoint?.remainingSeconds == 43)
        var finishedQuit = false
        let quit = Task { @MainActor in let saved = await app.prepareForTermination(); finishedQuit = true; return saved }
        try await waitUntil { app.isTerminating }
        await app.flushPersistence()
        #expect(app.timer.isPaused && !finishedQuit)
        #expect(JournalStore(directory: directory).load().value.activeCheckpoint?.remainingSeconds == 43)
        client.release()
        #expect(await quit.value)
        #expect(client.writes == [.focus, previous] && client.remote == previous)
        #expect(try await SlackStore(directory: directory).load().ownership == nil)
    }

    @Test func testF028_AC28DetectedManualSlackEditSurvivesAppEndAndSQLiteReceiptClears() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let client = RecordingSlackClient()
        let app = model(directory, clock: clock, client: client)
        configure(app); app.startFocus(); await flush(app)
        let manual = SlackProfile(text: "Meeting", emoji: ":calendar:", expiration: 0)
        client.remote = manual
        clock.advance(5); app.endSession(); await flush(app)
        #expect(client.remote == manual && client.writes == [.focus])
        #expect(app.slack?.statusText == "Your changed Slack status was kept.")
        #expect(try await SlackStore(directory: directory).load().ownership == nil)
        #expect(app.journal.records.first?.focusedSeconds == 5)
    }

    @Test func testF028_AC28CancelledQuitOnlyReappliesPausedFocusAfterExplicitKeepOpen() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let client = RecordingSlackClient(); let previous = client.remote
        let app = model(directory, clock: clock, client: client, exporter: SlackTestQuitFailureExporter())
        configure(app); app.startFocus(); await flush(app)
        clock.advance(17)
        #expect(!(await app.prepareForTermination()))
        #expect(app.timer.isPaused && client.remote == previous)
        #expect(client.writes == [.focus, previous])
        // Calendar/activation updates may arrive while the Quit failure alert
        // is awaiting a choice. They must not reapply before Quit Without Saving.
        app.refreshTimer(); app.selectedTab = .settings; await flush(app)
        #expect(client.remote == previous && client.writes == [.focus, previous])
        app.keepOpenAfterCancelledQuit(); await flush(app)
        #expect(app.timer.isPaused && app.timer.remainingSeconds == 43)
        #expect(client.writes == [.focus, previous, .focus] && client.remote == .focus)
        #expect(try await SlackStore(directory: directory).load().ownership?.cycleID == app.timer.phaseID)
        app.endSession(); await flush(app)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1000 {
            if condition() { return }
            // The write-ahead SQLite commit runs on another executor. Yield
            // counts are not a wall-clock deadline and can expire before I/O.
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(condition())
    }
}
}

@MainActor
private struct SlackTestQuitFailureExporter: CSVFileExporting {
    func save(data: Data, suggestedFilename: String) async -> CSVFileExportResult { .cancelled }
    func prepareForTermination() async -> CSVFileExportResult? { .failed("Test CSV write failed.") }
}
