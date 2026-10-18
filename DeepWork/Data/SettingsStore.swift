import Foundation

public protocol SettingsPersisting {
    func load() -> StoreLoad<SettingsDocument>
    @discardableResult func save(_ settings: SettingsDocument) -> StoreFailure?
}

public final class SettingsStore: SettingsPersisting {
    public static let filename = StoreLocation.databaseFilename
    public static let legacyFilename = "deep-work-settings-v1.json"
    private let store: SQLiteDocumentStore<SettingsDocument>
    public var fileURL: URL { store.fileURL }

    public init(directory: URL, legacyDirectory: URL? = nil) {
        store = SQLiteDocumentStore(directory: directory, legacyDirectory: legacyDirectory,
                                    defaultValue: SettingsDocument(),
                                    read: { try $0.readSettings() }, write: { try $0.writeSettings($1) })
    }
    public func load() -> StoreLoad<SettingsDocument> { store.load() }
    @discardableResult public func save(_ settings: SettingsDocument) -> StoreFailure? { store.save(settings) }
}
