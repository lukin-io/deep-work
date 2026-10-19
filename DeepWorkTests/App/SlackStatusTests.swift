import Foundation
import Testing
import DeepWorkCore
@testable import DeepWorkApp

@MainActor
final class RecordingSlackClient: SlackClientServing {
    var isConfigured = true
    var account: SlackAccount? = SlackAccount(workspaceID: "T1", userID: "U1", workspaceName: "Test", userName: "Tester")
    var remote = SlackProfile(text: "Lunch", emoji: ":sandwich:", expiration: 0)
    var writes: [SlackProfile] = []
    var reads = 0
    var loadFailure = false
    var profileFailure = false
    var setFailure = false
    var acceptBeforeFailure = false
    var disconnectFailure = false
    var flushFailure = false
    var credentialFlushes = 0
    var cancelled = false
    var gate: CheckedContinuation<Void, Never>?
    var holdWrite = false
    var connectError: SlackClientError?

    func loadAccount() async throws -> SlackAccount? {
        if loadFailure { throw SlackClientError.keychainFailure }
        return account
    }
    func connect() async throws -> SlackAccount {
        if let connectError { throw connectError }
        let value = SlackAccount(workspaceID: "T1", userID: "U1", workspaceName: "Test", userName: "Tester")
        account = value
        return value
    }
    func profile() async throws -> SlackProfile {
        reads += 1
        if profileFailure { throw SlackClientError.networkFailure }
        return remote
    }
    func setProfile(_ value: SlackProfile) async throws {
        writes.append(value)
        if holdWrite { await withCheckedContinuation { gate = $0 } }
        if !setFailure || acceptBeforeFailure { remote = value }
        if setFailure { throw SlackClientError.networkFailure }
    }
    func disconnect() async throws {
        if disconnectFailure { throw SlackClientError.keychainFailure }
        account = nil
    }
    func cancelAuthorization() { cancelled = true }
    func flushCredentials() async throws {
        credentialFlushes += 1
        if flushFailure { throw SlackClientError.keychainFailure }
    }
    func release() { holdWrite = false; gate?.resume(); gate = nil }
}

actor RecordingSlackStore: SlackStateStoring {
    var value: SlackDocument
    var writes: [SlackDocument] = []
    var fails = false
    init(_ value: SlackDocument = SlackDocument()) { self.value = value }
    func load() throws -> SlackDocument { value }
    func save(_ document: SlackDocument) throws {
        if fails { throw SlackClientError.serviceUnavailable }
        writes.append(document); value = document
    }
    func setFailure(_ value: Bool) { fails = value }
}

extension NativeApplicationTests {
@Suite(.serialized)
@MainActor
struct SlackStatusTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func ready(_ client: RecordingSlackClient, store: any SlackStateStoring) async -> SlackStatusController {
        let service = SlackStatusController(client: client, store: store, now: { date })
        service.start(); await service.flush()
        return service
    }

    @Test func testF027_F028_F029_AC28FocusPauseTicksBreakAndNextCycle() async throws {
        let client = RecordingSlackClient(); let prior = client.remote
        let store = RecordingSlackStore(); let service = await ready(client, store: store)
        #expect(client.writes.isEmpty && client.reads == 0)
        let cycle = UUID(); service.update(focusCycle: cycle); await service.flush()
        #expect(client.remote == .focus && service.statusText == "❌ Deep WORK, DND")
        #expect(await store.value.ownership?.previous == prior)
        for _ in 0..<20 { service.update(focusCycle: cycle) }
        await service.flush()
        #expect(client.writes.count == 1 && client.reads == 1)
        service.update(focusCycle: nil); await service.flush()
        #expect(client.remote == prior && service.statusText == "Previous status restored.")
        #expect(await store.value.ownership == nil)
        service.update(focusCycle: UUID()); await service.flush()
        #expect(client.writes == [.focus, prior, .focus])
    }

    @Test func testF028_AC28DetectedManualStatusIsNeverReplacedDuringRestore() async throws {
        let client = RecordingSlackClient(); let store = RecordingSlackStore()
        let service = await ready(client, store: store)
        service.update(focusCycle: UUID()); await service.flush()
        let manual = SlackProfile(text: "In a meeting", emoji: ":calendar:", expiration: 0)
        client.remote = manual
        service.update(focusCycle: nil); await service.flush()
        #expect(client.remote == manual && client.writes.count == 1)
        #expect(await store.value.ownership == nil)
        #expect(service.statusText == "Your changed Slack status was kept.")
    }

    @Test func testF028ExpiredPreviousStatusIsClearedInsteadOfRevived() async throws {
        let client = RecordingSlackClient()
        client.remote = SlackProfile(text: "Old meeting", emoji: ":calendar:", expiration: Int(date.timeIntervalSince1970))
        let service = await ready(client, store: RecordingSlackStore())
        service.update(focusCycle: UUID()); await service.flush()
        service.update(focusCycle: nil); await service.flush()
        #expect(client.remote == .empty && service.failureMessage == nil)
    }

    @Test func testF027_F028_AC28ExistingMatchingStatusIsNotOwnedOrRestored() async throws {
        let client = RecordingSlackClient(); client.remote = .focus
        let store = RecordingSlackStore(); let service = await ready(client, store: store)
        service.update(focusCycle: UUID()); await service.flush()
        service.update(focusCycle: nil); await service.flush()
        #expect(client.writes.isEmpty && client.remote == .focus)
        #expect(await store.value.ownership == nil)
    }

    @Test func testF028_AC28WriteAheadReceiptFailurePreventsRemoteMutation() async throws {
        let client = RecordingSlackClient(); let store = RecordingSlackStore()
        let service = await ready(client, store: store)
        await store.setFailure(true)
        service.update(focusCycle: UUID()); await service.flush()
        #expect(client.writes.isEmpty && service.failureMessage != nil)
        await store.setFailure(false); await service.retry()
        #expect(client.remote == .focus && service.failureMessage == nil)
    }

    @Test func testF028_AC28AmbiguousAcceptedSetRetainsReceiptAndRetryDoesNotRepeatWrite() async throws {
        let client = RecordingSlackClient(); let store = RecordingSlackStore()
        let service = await ready(client, store: store)
        client.setFailure = true; client.acceptBeforeFailure = true
        service.update(focusCycle: UUID()); await service.flush()
        #expect(client.remote == .focus && service.failureMessage != nil)
        #expect(await store.value.ownership != nil)
        client.setFailure = false; await service.retry()
        #expect(client.writes.count == 1 && service.failureMessage == nil)
        #expect(service.statusText == "❌ Deep WORK, DND")
    }

    @Test func testF028_AC28RetryKeepsExternalChangeAfterRejectedSet() async throws {
        let client = RecordingSlackClient(); let store = RecordingSlackStore()
        let service = await ready(client, store: store)
        client.setFailure = true; let cycle = UUID()
        service.update(focusCycle: cycle); await service.flush()
        client.setFailure = false
        let manual = SlackProfile(text: "Manual", emoji: "", expiration: 0); client.remote = manual
        await service.retry(); service.update(focusCycle: cycle); await service.flush()
        #expect(client.remote == manual && client.writes.count == 1)
        #expect(await store.value.ownership == nil)
    }

    @Test func testF028_AC28QuitRestoreFailurePreservesReceiptForRetry() async throws {
        let client = RecordingSlackClient(); let prior = client.remote
        let store = RecordingSlackStore(); let service = await ready(client, store: store)
        service.update(focusCycle: UUID()); await service.flush()
        client.profileFailure = true
        #expect(await service.prepareForTermination() != nil)
        #expect(client.cancelled && client.remote == .focus)
        #expect(await store.value.ownership != nil)
        client.profileFailure = false
        #expect(await service.prepareForTermination() == nil)
        #expect(client.remote == prior && !service.hasPendingRestore)
    }

    @Test func testF028_AC28CrashRecoveryUsesRealSQLiteAndRestoresBeforeNewFocus() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkSlack-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = RecordingSlackClient(); let prior = client.remote
        let store = SlackStore(directory: directory)
        let first = await ready(client, store: store)
        first.update(focusCycle: UUID()); await first.flush()
        #expect(try await SlackStore(directory: directory).load().ownership?.previous == prior)
        let second = await ready(client, store: SlackStore(directory: directory))
        #expect(client.remote == prior && !second.hasPendingRestore)
        #expect(second.statusText == "Previous status restored.")
        second.update(focusCycle: UUID()); await second.flush()
        #expect(client.remote == .focus)
    }

    @Test func testF028_AC28MissingAndDifferentAccountCannotRestoreReceipt() async throws {
        for missing in [true, false] {
            let client = RecordingSlackClient()
            let account = try #require(client.account)
            let store = RecordingSlackStore(SlackDocument(ownership: SlackOwnership(account: account, cycleID: UUID(), previous: client.remote)))
            client.remote = .focus
            client.account = missing ? nil : SlackAccount(workspaceID: "T2", userID: "U2", workspaceName: "Other", userName: "Other")
            let service = await ready(client, store: store)
            #expect(service.failureMessage != nil && client.writes.isEmpty)
            #expect(await store.value.ownership != nil)
        }
    }

    @Test func testF028_AC28PhaseChangesWhileWritePendingRestoreLatestIntent() async throws {
        let client = RecordingSlackClient(); let prior = client.remote
        let service = await ready(client, store: RecordingSlackStore())
        client.holdWrite = true; service.update(focusCycle: UUID())
        for _ in 0..<1000 { if client.gate != nil { break }; await Task.yield() }
        #expect(client.gate != nil)
        service.update(focusCycle: nil); client.release(); await service.flush()
        #expect(client.writes == [.focus, prior] && client.remote == prior)
    }

    @Test func testF027_AC28DisconnectRestoresBeforeRemovingAccountAndFailedRemovalRetries() async throws {
        let client = RecordingSlackClient(); let prior = client.remote
        let service = await ready(client, store: RecordingSlackStore())
        service.update(focusCycle: UUID()); await service.flush()
        client.disconnectFailure = true; await service.disconnect()
        #expect(service.account != nil && service.failureMessage != nil && client.remote == prior)
        client.disconnectFailure = false; await service.retry()
        #expect(service.account == nil && client.account == nil && client.remote == prior)
        #expect(client.writes.count == 2) // Retry removal, never reapply focus.
    }

    @Test func testF027_AC28LockedCredentialsWithoutOwnedStatusDoNotPreventQuit() async throws {
        let client = RecordingSlackClient(); client.loadFailure = true
        let service = await ready(client, store: RecordingSlackStore())
        #expect(service.failureMessage != nil)
        #expect(await service.prepareForTermination() == nil)
        #expect(client.writes.isEmpty)
    }

    @Test func testF027_AC28QuitFlushesPendingCredentialsEvenWithoutOwnership() async throws {
        let client = RecordingSlackClient(); let service = await ready(client, store: RecordingSlackStore())
        client.flushFailure = true
        #expect(await service.prepareForTermination() != nil)
        #expect(!service.hasPendingRestore && client.writes.isEmpty && client.credentialFlushes == 1)
        client.flushFailure = false
        #expect(await service.prepareForTermination() == nil)
        #expect(client.credentialFlushes == 2)
    }

    @Test func testF027UnconfiguredDisconnectedAndCancelledAuthorizationNeverClaimSuccess() async throws {
        let client = RecordingSlackClient(); client.account = nil; client.isConfigured = false
        let service = await ready(client, store: RecordingSlackStore())
        service.update(focusCycle: UUID()); await service.flush(); await service.connect()
        #expect(!service.canConnect && client.writes.isEmpty && service.account == nil)
        client.isConfigured = true; client.connectError = .cancelled
        await service.connect()
        #expect(service.failureMessage == nil && service.account == nil)
        client.connectError = nil; await service.connect()
        #expect(service.account != nil && client.remote == .focus)
    }
}
}
