import Foundation

public protocol JournalPersisting {
    func load() -> StoreLoad<JournalDocument>
    @discardableResult func save(_ journal: JournalDocument) -> StoreFailure?
}

public final class JournalStore: JournalPersisting {
    public static let filename = StoreLocation.databaseFilename
    public static let legacyFilename = "deep-work-journal-v1.json"
    private let store: SQLiteDocumentStore<JournalDocument>
    public var fileURL: URL { store.fileURL }

    public init(directory: URL, defaults: JournalDocument = JournalDocument(), legacyDirectory: URL? = nil) {
        store = SQLiteDocumentStore(directory: directory, legacyDirectory: legacyDirectory,
                                    defaultValue: defaults, journalDefaults: defaults,
                                    read: { try $0.readJournal() }, write: { try $0.writeJournal($1) })
    }
    public func load() -> StoreLoad<JournalDocument> { store.load() }
    @discardableResult public func save(_ journal: JournalDocument) -> StoreFailure? { store.save(journal) }
}
