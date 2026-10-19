import Foundation
import Combine
import DeepWorkCore

/// One serialized stream of remote effects, independent of view lifetime.
/// Timer ticks only project state; they never trigger profile API requests.
@MainActor
final class SlackStatusController: ObservableObject {
    @Published private(set) var account: SlackAccount?
    @Published private(set) var isBusy = false
    @Published private(set) var failureMessage: String?
    @Published private(set) var statusText = "Slack is not connected."
    private let client: any SlackClientServing
    private let store: any SlackStateStoring
    private let now: () -> Date
    private var document = SlackDocument()
    private var loadedStore = false
    private var loadedAccount = false
    private var needsRecovery = true
    private var desiredCycle: UUID?
    private var suppressedCycle: UUID?
    private var terminating = false
    private var tail: Task<Void, Never>?
    private var pendingOperations = 0
    private var started = false
    private var disconnectRequested = false

    var isConfigured: Bool { client.isConfigured }
    var hasPendingRestore: Bool { document.ownership != nil }
    var canConnect: Bool { isConfigured && !isBusy && !terminating }

    init(client: any SlackClientServing, store: any SlackStateStoring,
         now: @escaping () -> Date = Date.init) {
        self.client = client; self.store = store; self.now = now
    }

    func start() {
        guard !started else { return }
        started = true
        enqueue { try await self.synchronize() }
    }

    func update(focusCycle: UUID?) {
        guard !terminating, focusCycle != desiredCycle else { return }
        desiredCycle = focusCycle
        enqueue { try await self.synchronize() }
    }

    func connect() async {
        guard canConnect else { return }
        await enqueue {
            try await self.loadStore()
            self.account = try await self.client.connect(expectedAccount: self.document.ownership?.account)
            self.disconnectRequested = false
            self.loadedAccount = true
            self.needsRecovery = true
            self.suppressedCycle = nil
            try await self.synchronize()
        }.value
    }

    func disconnect() async {
        guard !isBusy, !terminating else { return }
        disconnectRequested = true
        await enqueue { try await self.synchronize() }.value
    }

    func retry() async {
        guard !isBusy, !terminating else { return }
        await enqueue { try await self.synchronize() }.value
    }

    /// Quit cancels an open authorization sheet and waits for accepted remote
    /// operations. Failures preserve the receipt and keep Quit cancellable.
    func prepareForTermination() async -> String? {
        terminating = true
        desiredCycle = nil
        client.cancelAuthorization()
        await enqueue {
            try await self.loadStore()
            if self.document.ownership != nil {
                try await self.initialize()
                try await self.restoreOwnedStatus()
            }
            try await self.client.flushCredentials()
        }.value
        return failureMessage
    }

    func cancelTermination() { terminating = false }

    func flush() async { await tail?.value }

    @discardableResult
    private func enqueue(_ operation: @escaping @MainActor () async throws -> Void) -> Task<Void, Never> {
        let previous = tail
        pendingOperations += 1
        isBusy = true
        let task = Task { @MainActor in
            await previous?.value
            self.failureMessage = nil
            do { try await operation() }
            catch {
                if let error = error as? SlackClientError {
                    if error != .cancelled { self.failureMessage = error.localizedDescription }
                } else {
                    self.failureMessage = "Slack could not safely update its saved status. Your timer still works. Retry after fixing storage or reconnecting Slack."
                }
                if self.failureMessage != nil { self.statusText = "Slack needs attention." }
            }
            self.pendingOperations -= 1
            self.isBusy = self.pendingOperations > 0
        }
        tail = task
        return task
    }

    private func loadStore() async throws {
        guard !loadedStore else { return }
        let value = try await store.load()
        try value.validate()
        document = value
        loadedStore = true
    }

    private func initialize() async throws {
        try await loadStore()
        if !loadedAccount {
            account = try await client.loadAccount()
            loadedAccount = true
        }
    }

    private func synchronize() async throws {
        try await initialize()
        if disconnectRequested {
            try await restoreOwnedStatus()
            try await client.disconnect()
            account = nil
            suppressedCycle = nil
            disconnectRequested = false
            statusText = "Slack is not connected."
            return
        }
        if needsRecovery {
            try await restoreOwnedStatus()
            needsRecovery = false
        }
        guard let account else {
            guard document.ownership == nil else { throw SlackClientError.reconnectRequired }
            statusText = "Slack is not connected."
            return
        }
        if let ownership = document.ownership,
           ownership.cycleID != desiredCycle || terminating {
            try await restoreOwnedStatus()
        }
        guard let cycle = desiredCycle, !terminating else {
            if statusText != "Previous status restored." && statusText != "Your changed Slack status was kept." {
                statusText = "Connected. Your Slack status is unchanged."
            }
            return
        }
        guard cycle != suppressedCycle else { return }
        if let ownership = document.ownership {
            guard ownership.account.matches(account) else { throw SlackClientError.reconnectRequired }
            // A failed/ambiguous set keeps its receipt. Read before retrying so
            // an accepted request or external edit cannot be overwritten blindly.
            if statusText == "❌ Deep WORK, DND" { return }
            let current = try await client.profile()
            if current == ownership.applied {
                statusText = "❌ Deep WORK, DND"
                return
            }
            if current != ownership.previous {
                try await clearOwnership()
                suppressedCycle = cycle
                statusText = "Your changed Slack status was kept."
                return
            }
        } else {
            let previous = try await client.profile()
            try previous.validate()
            guard desiredCycle == cycle, !terminating else { return }
            if previous == .focus {
                suppressedCycle = cycle
                statusText = "Your Slack status already matches; it will be kept."
                return
            }
            let receipt = SlackOwnership(account: account, cycleID: cycle, previous: previous)
            let candidate = SlackDocument(ownership: receipt)
            // No remote mutation until the recovery receipt commits to SQLite.
            try await store.save(candidate)
            document = candidate
        }
        guard desiredCycle == cycle, !terminating else {
            try await restoreOwnedStatus()
            return
        }
        try await client.setProfile(.focus)
        statusText = "❌ Deep WORK, DND"
        // A phase may change while the request is in flight. Restore promptly;
        // the following queued projection applies only the latest phase.
        if desiredCycle != cycle || terminating { try await restoreOwnedStatus() }
    }

    private func restoreOwnedStatus() async throws {
        guard let receipt = document.ownership else { return }
        guard let account, receipt.account.matches(account) else { throw SlackClientError.reconnectRequired }
        let current = try await client.profile()
        if current == receipt.applied {
            try await client.setProfile(receipt.previous.restoring(at: now()))
            try await clearOwnership()
            statusText = "Previous status restored."
        } else {
            // Slack has no conditional-write API. Compare immediately before
            // restoring, and preserve every detected external status change.
            try await clearOwnership()
            if current != receipt.previous { suppressedCycle = desiredCycle }
            statusText = current == receipt.previous
                ? "Previous status restored." : "Your changed Slack status was kept."
        }
    }

    private func clearOwnership() async throws {
        let candidate = SlackDocument()
        try await store.save(candidate)
        document = candidate
    }
}
