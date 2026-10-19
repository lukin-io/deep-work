import AppKit
import Foundation
import Testing
import DeepWorkCore
@testable import DeepWorkApp

extension NativeApplicationTests {
@Suite(.serialized)
@MainActor
struct ClosePersistenceTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkCloseTests-\(UUID())")
    }

    private func makeModel(_ directory: URL, clock: TestTimerClock) -> AppModel {
        AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                 clock: clock, automaticRefresh: false)
    }

    private func configure(_ model: AppModel) {
        model.focusSelection.wrappedValue = .custom
        model.breakSelection.wrappedValue = .custom
        model.customFocusText = "1"
        model.customBreakText = "1"
    }

    @Test func testG006_F025CloseQueuesCommittedDataAndOnlyQuitPausesRecovery() async throws {
        prepareNativeTestApplication()
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock()
        let recordStart = clock.date - 3600
        let historicalRecord = SessionRecord(startedAt: recordStart, endedAt: recordStart + 60,
                                            plannedFocusMinutes: 1, outcome: .complete,
                                            segments: [ActiveSegment(startedAt: recordStart, endedAt: recordStart + 60)])
        let schedule = WorkSchedule(mode: .rotatingShifts, workDays: 3, restDays: 2,
                                    firstWorkDay: CivilDate(year: 2026, month: 10, day: 18),
                                    weekStartsOn: .sunday, reportingDayStartMinutes: 240)
        let committedSettings = SettingsDocument(launchAtLogin: true,
            feedbackDraft: FeedbackDraft(type: .idea, email: "", message: "Explicitly saved feedback"))
        #expect(JournalStore(directory: directory).save(JournalDocument(records: [historicalRecord], schedule: schedule)) == nil)
        #expect(SettingsStore(directory: directory).save(committedSettings) == nil)
        let model = makeModel(directory, clock: clock)
        let controller = WindowController(model: model)
        let window = try #require(controller.window); defer { window.orderOut(nil) }
        configure(model); model.repeats.wrappedValue = false
        model.feedbackMessage = "Unsaved feedback remains in the retained window"
        model.openSchedule()
        model.updateScheduleDraft { $0.mode = .anyDay }
        model.startFocus()
        let liveID = try #require(model.timer.liveRecord?.id)
        clock.advance(17)
        controller.showWindow(nil); requestNativeWindowClose(window)
        // Hide is synchronous and independent of the asynchronous SQLite writes.
        #expect(!window.isVisible && !model.isTerminating && model.lifecycleFailureMessage == nil)
        #expect(!model.timer.isPaused && model.timer.remainingSeconds == 43)
        await model.flushPersistence()
        let savedJournal = JournalStore(directory: directory).load()
        let savedSettings = SettingsStore(directory: directory).load()
        #expect(savedJournal.failure == nil && savedSettings.failure == nil)
        #expect(savedJournal.value.records == [historicalRecord])
        #expect(savedJournal.value.schedule == schedule)
        #expect(savedJournal.value.configuration == model.journal.configuration)
        #expect(savedJournal.value.activeCheckpoint?.focusRecord?.id == liveID)
        #expect(savedJournal.value.activeCheckpoint?.focusRecord?.focusedSeconds == 17)
        #expect(savedJournal.value.activeCheckpoint?.remainingSeconds == 43)
        #expect(savedSettings.value == committedSettings)
        clock.advance(10); model.showFocus(); controller.showWindow(nil)
        #expect(controller.window === window && window.isVisible)
        #expect(!model.timer.isPaused && model.timer.remainingSeconds == 33)
        #expect(model.timer.liveRecord?.id == liveID)
        #expect(model.feedbackMessage == "Unsaved feedback remains in the retained window")
        #expect(model.scheduleDraft?.mode == .anyDay)
        #expect(await model.prepareForTermination())
        clock.advance(86_400)
        let restored = makeModel(directory, clock: clock)
        #expect(restored.timer.isRecovered && restored.timer.isPaused)
        #expect(restored.timer.liveRecord?.id == liveID && restored.timer.remainingSeconds == 33)
        #expect(restored.timer.liveRecord?.focusedSeconds == 27)
        #expect(restored.feedbackMessage == committedSettings.feedbackDraft.message)
        #expect(restored.settings == committedSettings)
        #expect(restored.journal.records == [historicalRecord] && restored.journal.schedule == schedule)
        await restored.flushPersistence()
    }

    @Test(arguments: [60.0, 75.0, 130.0, 305.0])
    func testG006_F023_F024HiddenWindowCrossesBoundariesAndSavesRecordsExactlyOnce(elapsed: Double) async throws {
        prepareNativeTestApplication()
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let model = makeModel(directory, clock: clock)
        let controller = WindowController(model: model)
        let window = try #require(controller.window); defer { window.orderOut(nil) }
        configure(model); model.startFocus(); controller.showWindow(nil)
        requestNativeWindowClose(window)
        #expect(!window.isVisible && !model.timer.isPaused)
        clock.advance(elapsed); model.refreshTimer(); model.refreshTimer()
        requestNativeWindowClose(window) // Repeated close must not pause or duplicate boundary records.
        let expectedCount = Int((elapsed + 60) / 120)
        let expectedRemainder = 60 - elapsed.truncatingRemainder(dividingBy: 60)
        #expect(!model.timer.isPaused && model.timer.remainingSeconds == expectedRemainder)
        #expect(model.journal.records.count == expectedCount)
        await model.flushPersistence()
        let saved = JournalStore(directory: directory).load().value
        #expect(Set(saved.records.map(\.id)).count == expectedCount)
        #expect(saved.records.allSatisfy { $0.outcome == .complete && $0.focusedSeconds == 60 })
        #expect(saved.activeCheckpoint?.remainingSeconds == expectedRemainder)
        try saved.validate()
        clock.advance(1); model.showFocus(); controller.showWindow(nil)
        #expect(!model.timer.isPaused && model.timer.remainingSeconds == expectedRemainder - 1)
        #expect(model.journal.records == saved.records)
        await model.flushPersistence()
    }

    @Test(arguments: [false, true])
    func testG006CloseInSetupOrAlreadyPausedPreservesStateAndCreatesNoHistory(alreadyPaused: Bool) async throws {
        prepareNativeTestApplication()
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let model = makeModel(directory, clock: clock)
        let controller = WindowController(model: model)
        let window = try #require(controller.window); defer { window.orderOut(nil) }
        configure(model)
        if alreadyPaused { model.startFocus(); clock.advance(17); model.pauseTimer(); clock.advance(600) }
        let before = model.timer.activeCheckpoint
        controller.showWindow(nil); requestNativeWindowClose(window)
        #expect(!window.isVisible && model.journal.records.isEmpty)
        clock.advance(600); model.showFocus(); controller.showWindow(nil)
        #expect(model.timer.activeCheckpoint?.remainingSeconds == before?.remainingSeconds)
        #expect(model.timer.liveRecord?.id == before?.focusRecord?.id)
        #expect(model.timer.liveRecord?.segments == before?.focusRecord?.segments)
        #expect(model.timer.state == (alreadyPaused ? .focus : .setup))
        #expect(model.timer.isPaused == alreadyPaused)
        await model.flushPersistence()
        #expect(JournalStore(directory: directory).load().value.activeCheckpoint == model.timer.activeCheckpoint)
    }

    @Test(arguments: [false, true])
    func testG006_J052_S021FailedStorageStillHidesAndKeepsRunningEditsAndWarnings(journalFails: Bool) async throws {
        prepareNativeTestApplication()
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let blocked = directory.appendingPathComponent("blocked")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("preserve unreadable source".utf8).write(to: blocked)
        let clock = TestTimerClock()
        let model = AppModel(journalStore: JournalStore(directory: journalFails ? blocked : directory),
                             settingsStore: SettingsStore(directory: journalFails ? directory : blocked),
                             clock: clock, automaticRefresh: false)
        let controller = WindowController(model: model)
        let window = try #require(controller.window); defer { window.orderOut(nil) }
        configure(model); model.feedbackMessage = "Keep these unsaved edits"
        model.startFocus(); clock.advance(17)
        controller.showWindow(nil); requestNativeWindowClose(window)
        #expect(!window.isVisible && !model.timer.isPaused && model.timer.remainingSeconds == 43)
        await model.flushPersistence()
        #expect(model.lifecycleFailureMessage == nil)
        #expect(model.feedbackMessage == "Keep these unsaved edits")
        #expect((model.journalFailure != nil) == journalFails)
        #expect((model.settingsFailure != nil) == !journalFails)
        #expect(!model.isTerminating)
        clock.advance(1); model.showFocus(); controller.showWindow(nil)
        #expect(window.isVisible && !model.timer.isPaused && model.timer.remainingSeconds == 42)
        #expect(model.feedbackMessage == "Keep these unsaved edits")
        #expect(journalFails ? model.journalStorageMessage.contains("Saving unavailable") : model.settingsStorageMessage.contains("could not be saved"))
        #expect(try String(contentsOf: blocked) == "preserve unreadable source")
        await model.flushPersistence()
    }

    @Test func testG003_G006SlowCloseCheckpointNeverDelaysHideOrFreezesReopenedControls() async throws {
        prepareNativeTestApplication()
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let gate = GatedJournalStore(directory: directory)
        let model = AppModel(journalStore: gate, settingsStore: SettingsStore(directory: directory),
                             clock: clock, automaticRefresh: false)
        let controller = WindowController(model: model)
        let window = try #require(controller.window); defer { window.orderOut(nil) }
        configure(model); model.startFocus(); model.selectedTab = .settings
        await model.flushPersistence()
        let liveID = model.timer.liveRecord?.id
        gate.blockNextSave(); defer { gate.releaseSave() }
        clock.advance(17); controller.showWindow(nil); requestNativeWindowClose(window)
        #expect(!window.isVisible && !model.timer.isPaused && model.timer.remainingSeconds == 43)
        #expect(model.pendingJournalWrites > 0)
        model.showFocus(); controller.showWindow(nil)
        #expect(window.isVisible && model.selectedTab == .focus && controller.window === window)
        model.pauseTimer(); clock.advance(600); model.refreshTimer()
        #expect(model.timer.isPaused && model.timer.remainingSeconds == 43)
        model.resumeTimer(); clock.advance(1); model.refreshTimer()
        model.repeats.wrappedValue = false
        model.feedbackMessage = "Must not become an implicitly saved draft"
        #expect(!model.timer.isPaused && model.timer.remainingSeconds == 42)
        #expect(!model.journal.configuration.repeats && model.settings.feedbackDraft == .empty)
        gate.releaseSave(); await model.flushPersistence()
        #expect(window.isVisible && model.timer.liveRecord?.id == liveID)
        let saved = JournalStore(directory: directory).load().value
        #expect(saved.activeCheckpoint?.remainingSeconds == 42)
        #expect(saved.activeCheckpoint?.focusRecord?.focusedSeconds == 18)
        #expect(saved.records.isEmpty)
    }

    @Test func testG006_F025HideThenQuitPausesAtQuitInstantAndDrainsWithoutDuplicates() async throws {
        prepareNativeTestApplication()
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let gate = GatedJournalStore(directory: directory)
        let model = AppModel(journalStore: gate, settingsStore: SettingsStore(directory: directory),
                             clock: clock, automaticRefresh: false)
        let controller = WindowController(model: model)
        let window = try #require(controller.window); defer { window.orderOut(nil) }
        configure(model); model.startFocus(); await model.flushPersistence()
        gate.blockNextSave(); defer { gate.releaseSave() }
        clock.advance(17); controller.showWindow(nil); requestNativeWindowClose(window)
        #expect(!window.isVisible && !model.timer.isPaused && model.timer.remainingSeconds == 43)
        clock.advance(58)
        let quitting = Task { await model.prepareForTermination() }
        while !model.isTerminating { await Task.yield() }
        clock.advance(600); model.resumeTimer(); model.refreshTimer()
        gate.releaseSave()
        #expect(await quitting.value)
        #expect(model.isTerminating && model.timer.isPaused && model.timer.remainingSeconds == 45)
        let saved = JournalStore(directory: directory).load().value
        #expect(saved.records.count == 1 && saved.records.first?.focusedSeconds == 60)
        #expect(saved.activeCheckpoint?.phase == .break && saved.activeCheckpoint?.remainingSeconds == 45)
        let restored = makeModel(directory, clock: clock)
        #expect(restored.timer.isRecovered && restored.timer.isPaused && restored.timer.remainingSeconds == 45)
        #expect(restored.timer.state == .break && restored.journal.records == saved.records)
        await restored.flushPersistence()
    }

    @Test(arguments: [0, 1, 2])
    func testF025QuitFailureCancelsAutomaticExitAndRestoresUsablePausedControls(failedStores: Int) async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocked = directory.appendingPathComponent("blocked")
        try Data("blocked".utf8).write(to: blocked)
        let clock = TestTimerClock()
        let model = AppModel(journalStore: JournalStore(directory: failedStores == 1 ? directory : blocked),
                             settingsStore: SettingsStore(directory: failedStores == 0 ? directory : blocked),
                             clock: clock, automaticRefresh: false)
        configure(model); model.startFocus(); clock.advance(17)
        #expect(await model.prepareForTermination() == false)
        #expect(!model.isTerminating)
        #expect(model.timer.isPaused && model.timer.remainingSeconds == 43)
        #expect(model.lifecycleFailureMessage != nil)
        #expect((model.journalFailure != nil) == (failedStores != 1))
        #expect((model.settingsFailure != nil) == (failedStores != 0))
        model.resumeTimer(); clock.advance(1); model.refreshTimer()
        #expect(!model.timer.isPaused && model.timer.remainingSeconds == 42)
        #expect(model.lifecycleFailureMessage?.contains("paused") == false)
        await model.flushPersistence()
    }

    @Test func testG006_G007MinimizeHideAndCloseAllContinueBackgroundTiming() async throws {
        prepareNativeTestApplication()
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock(); let model = makeModel(directory, clock: clock)
        let controller = WindowController(model: model)
        let window = try #require(controller.window); defer { window.orderOut(nil) }
        configure(model); model.startFocus(); controller.showWindow(nil)
        window.miniaturize(nil)
        clock.advance(17); model.persistCommittedState() // Also applicationDidHide / willSleep.
        #expect(!model.timer.isPaused && model.timer.remainingSeconds == 43)
        controller.showWindow(nil); window.orderOut(nil)
        clock.advance(5); model.persistCommittedState()
        #expect(!model.timer.isPaused && model.timer.remainingSeconds == 38)
        controller.showWindow(nil); requestNativeWindowClose(window)
        #expect(!window.isVisible && !model.timer.isPaused && model.timer.remainingSeconds == 38)
        clock.advance(1); model.refreshTimer()
        #expect(!model.timer.isPaused && model.timer.remainingSeconds == 37)
        await model.flushPersistence()
    }

    @Test func testG006_F025AutomaticTickerKeepsCheckpointingWhileWindowIsHidden() async throws {
        prepareNativeTestApplication()
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock()
        let model = AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                             clock: clock, automaticRefresh: true)
        let controller = WindowController(model: model)
        let window = try #require(controller.window); defer { window.orderOut(nil) }
        configure(model); model.startFocus(); controller.showWindow(nil); requestNativeWindowClose(window)
        await model.flushPersistence()
        clock.advance(5)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.timer.remainingSeconds == 60 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!window.isVisible && !model.timer.isPaused && model.timer.remainingSeconds == 55)
        await model.flushPersistence()
        let saved = JournalStore(directory: directory).load().value
        #expect(saved.activeCheckpoint?.remainingSeconds == 55)
        #expect(saved.activeCheckpoint?.focusRecord?.focusedSeconds == 5)
        #expect(saved.records.isEmpty)
        // Explicitly stop the automatic ticker before deleting its SQLite fixture.
        #expect(await model.prepareForTermination())
    }
}
}

/// The underlying store keeps real SQLite transaction behavior. Only the next
/// save is gated to make slow checkpoint/reopen and hide/Quit races deterministic.
private final class GatedJournalStore: JournalPersisting, @unchecked Sendable {
    private let store: JournalStore
    private let lock = NSLock()
    private var shouldBlock = false
    private let release = DispatchSemaphore(value: 0)

    init(directory: URL) { store = JournalStore(directory: directory) }
    func load() -> StoreLoad<JournalDocument> { store.load() }
    func blockNextSave() { lock.lock(); shouldBlock = true; lock.unlock() }
    func releaseSave() { release.signal() }
    func save(_ journal: JournalDocument) -> StoreFailure? {
        lock.lock(); let block = shouldBlock; shouldBlock = false; lock.unlock()
        if block { release.wait() }
        return store.save(journal)
    }
}
