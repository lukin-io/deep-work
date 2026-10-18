import Foundation

/// Owns the store references after their initial load. Callers must not use
/// those references again: all encoding and disk writes run on this serial
/// queue. Immutable documents cross the queue boundary by value.
///
/// The unchecked conformance is limited to the store handoff. Queue confinement
/// makes the otherwise non-Sendable persistence protocols safe to inject.
public final class PersistenceWorker: @unchecked Sendable {
    private let journalStore: any JournalPersisting
    private let settingsStore: any SettingsPersisting
    private let queue = DispatchQueue(label: "app.deepwork.mac.persistence", qos: .utility)

    public init(journalStore: any JournalPersisting, settingsStore: any SettingsPersisting) {
        self.journalStore = journalStore
        self.settingsStore = settingsStore
    }

    /// Results are delivered on the main actor in the same order as enqueued
    /// writes. A successful callback means the SQLite transaction committed.
    public func enqueueJournal(
        _ document: JournalDocument,
        completion: @escaping @MainActor @Sendable (StoreFailure?) -> Void = { _ in }
    ) {
        queue.async { [self] in
            let failure = journalStore.save(document)
            DispatchQueue.main.async { completion(failure) }
        }
    }

    public func enqueueSettings(
        _ document: SettingsDocument,
        completion: @escaping @MainActor @Sendable (StoreFailure?) -> Void = { _ in }
    ) {
        queue.async { [self] in
            let failure = settingsStore.save(document)
            DispatchQueue.main.async { completion(failure) }
        }
    }

    /// Waits for writes submitted before this call and their main-actor result
    /// callbacks. This suspends the caller; it never blocks the main thread.
    /// Stop producing new checkpoints before flushing for application Quit.
    public func flush() async {
        await withCheckedContinuation { continuation in
            queue.async {
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }
}
