import Foundation
import Testing
@testable import DeepWorkCore

struct PersistenceWorkerTests {
    @Test @MainActor func F025WritesSnapshotsOffMainInOrderAndFlushWaitsForCallbacks() async {
        let observations = PersistenceObservations()
        let worker = PersistenceWorker(journalStore: ObservedJournalStore(observations),
                                       settingsStore: ObservedSettingsStore(observations))
        var callbacks: [String] = []
        var journal = JournalDocument()
        journal.configuration.customFocusMinutes = 1
        worker.enqueueJournal(journal) { failure in
            #expect(Thread.isMainThread)
            #expect(failure == nil)
            callbacks.append("journal 1")
        }
        worker.enqueueSettings(SettingsDocument(launchAtLogin: true)) { failure in
            #expect(Thread.isMainThread)
            #expect(failure == nil)
            callbacks.append("settings true")
        }
        journal.configuration.customFocusMinutes = 2
        worker.enqueueJournal(journal) { failure in
            #expect(failure == nil)
            callbacks.append("journal 2")
        }
        // Value snapshots cannot be changed after submitting them.
        journal.configuration.customFocusMinutes = 3
        await worker.flush()
        #expect(callbacks == ["journal 1", "settings true", "journal 2"])
        #expect(observations.events == callbacks)
        #expect(observations.mainThreadWrites == 0)
    }

    @Test @MainActor func F025SlowWriteDoesNotBlockMainActorAndFailureIsReportedBeforeFlush() async {
        let observations = PersistenceObservations()
        let gate = DispatchSemaphore(value: 0)
        let failure = StoreFailure(operation: .write, fileURL: URL(fileURLWithPath: "/test/DeepWork.sqlite"),
                                   reason: "Injected unavailable storage")
        let worker = PersistenceWorker(journalStore: ObservedJournalStore(observations, gate: gate, failure: failure),
                                       settingsStore: ObservedSettingsStore(observations))
        var reported: StoreFailure?
        worker.enqueueJournal(JournalDocument()) { reported = $0 }
        // This line must run while the persistence queue waits. A synchronous
        // main-actor write would time out in the mock and fail this assertion.
        #expect(observations.gateTimedOut == false)
        gate.signal()
        await worker.flush()
        #expect(reported == failure)
        #expect(observations.gateTimedOut == false)
        #expect(observations.mainThreadWrites == 0)
    }

    @Test @MainActor func F025FlushCommitsLatestCheckpointAndIndependentSettingsToSQLite() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkWorkerTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let journalStore = JournalStore(directory: directory)
        let settingsStore = SettingsStore(directory: directory)
        #expect(journalStore.load().failure == nil)
        #expect(settingsStore.load().failure == nil)
        let worker = PersistenceWorker(journalStore: journalStore, settingsStore: settingsStore)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(17.125)
        let record = SessionRecord(startedAt: start, endedAt: end, plannedFocusMinutes: 1, outcome: .live,
                                   segments: [ActiveSegment(startedAt: start, endedAt: end)])
        let checkpoint = ActiveCheckpoint(phase: .focus, focusMinutes: 1, breakMinutes: 1,
                                          remainingSeconds: 42.875, savedAt: end, focusRecord: record)
        var journal = JournalDocument()
        worker.enqueueJournal(journal)
        let settings = SettingsDocument(feedbackDraft: try FeedbackDraft(message: "Explicitly saved draft").validatedForSaving())
        worker.enqueueSettings(settings)
        journal.activeCheckpoint = checkpoint
        worker.enqueueJournal(journal)
        await worker.flush()
        #expect(JournalStore(directory: directory).load().value == journal)
        #expect(SettingsStore(directory: directory).load().value == settings)
    }
}

/// Test-only instrumentation has its own lock because assertions execute on a
/// different executor from the production persistence queue.
private final class PersistenceObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [String] = []
    private var storedMainThreadWrites = 0
    private var storedGateTimedOut = false
    var events: [String] { lock.withLock { storedEvents } }
    var mainThreadWrites: Int { lock.withLock { storedMainThreadWrites } }
    var gateTimedOut: Bool { lock.withLock { storedGateTimedOut } }
    func record(_ event: String, timedOut: Bool = false) {
        lock.withLock {
            storedEvents.append(event)
            storedMainThreadWrites += Thread.isMainThread ? 1 : 0
            storedGateTimedOut = storedGateTimedOut || timedOut
        }
    }
}

private final class ObservedJournalStore: JournalPersisting {
    let observations: PersistenceObservations
    let gate: DispatchSemaphore?
    let failure: StoreFailure?
    init(_ observations: PersistenceObservations, gate: DispatchSemaphore? = nil, failure: StoreFailure? = nil) {
        self.observations = observations; self.gate = gate; self.failure = failure
    }
    func load() -> StoreLoad<JournalDocument> { StoreLoad(value: JournalDocument()) }
    func save(_ journal: JournalDocument) -> StoreFailure? {
        let timedOut = gate?.wait(timeout: .now() + 2) == .timedOut
        observations.record("journal \(journal.configuration.customFocusMinutes)", timedOut: timedOut)
        return failure
    }
}

private final class ObservedSettingsStore: SettingsPersisting {
    let observations: PersistenceObservations
    init(_ observations: PersistenceObservations) { self.observations = observations }
    func load() -> StoreLoad<SettingsDocument> { StoreLoad(value: SettingsDocument()) }
    func save(_ settings: SettingsDocument) -> StoreFailure? {
        observations.record("settings \(settings.launchAtLogin)")
        return nil
    }
}
