import Foundation

public protocol SlackStateStoring: Sendable {
    func load() async throws -> SlackDocument
    func save(_ document: SlackDocument) async throws
}

/// An actor keeps synchronous SQLite work off the application's main actor.
public actor SlackStore: SlackStateStoring {
    private let store: SQLiteDocumentStore<SlackDocument>

    public init(directory: URL) {
        store = SQLiteDocumentStore(directory: directory, legacyDirectory: nil,
                                    defaultValue: SlackDocument(),
                                    read: { try $0.readSlack() }, write: { try $0.writeSlack($1) })
    }

    public func load() throws -> SlackDocument {
        let result = store.load()
        if let failure = result.failure { throw failure }
        return result.value
    }

    public func save(_ document: SlackDocument) throws {
        if let failure = store.save(document) { throw failure }
    }
}
