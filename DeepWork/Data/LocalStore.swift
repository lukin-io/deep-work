import Foundation
import Darwin
import SQLite3

public struct StoreFailure: Error, Equatable, LocalizedError, Sendable {
    public enum Operation: String, Sendable { case read, decode, validation, unsupportedVersion, write }
    public let operation: Operation
    public let fileURL: URL
    public let reason: String

    public init(operation: Operation, fileURL: URL, reason: String) {
        self.operation = operation; self.fileURL = fileURL; self.reason = reason
    }
    public var errorDescription: String? { reason }
}

public struct StoreLoad<Value> {
    public let value: Value
    public let failure: StoreFailure?
    public init(value: Value, failure: StoreFailure? = nil) { self.value = value; self.failure = failure }
}

public enum StoreLocation {
    public static let databaseFilename = "DeepWork.sqlite"

    public static func applicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        let root = try applicationSupportRoot(fileManager)
        return root.appendingPathComponent("app.deepwork.mac", isDirectory: true)
    }

    public static func legacyApplicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportRoot(fileManager).appendingPathComponent("Deep Work", isDirectory: true)
    }

    private static func applicationSupportRoot(_ fileManager: FileManager) throws -> URL {
        try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                            appropriateFor: nil, create: false)
    }
}

/// A single queue per database coordinates the journal and settings owners in
/// this process. SQLite transactions/busy handling also protect against external
/// connections. No SQLite connection or prepared statement escapes this queue.
private final class DatabaseQueues: @unchecked Sendable {
    static let shared = DatabaseQueues()
    private let lock = NSLock()
    private var queues: [String: DispatchQueue] = [:]

    func queue(for directory: URL) -> DispatchQueue {
        let key = directory.standardizedFileURL.resolvingSymlinksInPath().path
        lock.lock(); defer { lock.unlock() }
        if let queue = queues[key] { return queue }
        let queue = DispatchQueue(label: "app.deepwork.mac.sqlite.\(UUID().uuidString)")
        queues[key] = queue
        return queue
    }
}

/// Failure state is scoped to a logical store: an invalid settings payload must
/// not prevent the journal from being saved. Physical database failures can
/// affect both stores. A failure never replaces existing data with defaults.
final class SQLiteDocumentStore<Document: StoredDocument> {
    let fileURL: URL
    private let database: LocalDatabase
    private let queue: DispatchQueue
    private let read: (SQLiteConnection) throws -> Document
    private let write: (SQLiteConnection, Document) throws -> Void
    private var hasLoaded = false
    private var lastValue: Document
    private var failure: StoreFailure?

    init(directory: URL, legacyDirectory: URL?, defaultValue: Document,
         journalDefaults: JournalDocument = JournalDocument(),
         read: @escaping (SQLiteConnection) throws -> Document,
         write: @escaping (SQLiteConnection, Document) throws -> Void) {
        fileURL = directory.appendingPathComponent(StoreLocation.databaseFilename)
        database = LocalDatabase(directory: directory, legacyDirectory: legacyDirectory, journalDefaults: journalDefaults)
        queue = DatabaseQueues.shared.queue(for: directory)
        lastValue = defaultValue
        self.read = read; self.write = write
    }

    func load() -> StoreLoad<Document> {
        queue.sync {
            loadIfNeeded()
            return StoreLoad(value: lastValue, failure: failure)
        }
    }

    func save(_ document: Document) -> StoreFailure? {
        queue.sync {
            loadIfNeeded()
            guard failure == nil else { return failure }
            do {
                try document.validate()
                try database.withConnection { connection in
                    try connection.transaction(immediate: true) { try write(connection, document) }
                }
                lastValue = document
                return nil
            } catch {
                return latch(error, fallback: .write)
            }
        }
    }

    private func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        do {
            lastValue = try database.withConnection { connection in
                try connection.transaction(immediate: false) { try read(connection) }
            }
        } catch {
            _ = latch(error, fallback: .read)
        }
    }

    @discardableResult
    private func latch(_ error: Error, fallback: StoreFailure.Operation) -> StoreFailure {
        let result = storeFailure(error, at: fileURL, fallback: fallback)
        failure = result
        return result
    }
}

private func storeFailure(_ error: Error, at url: URL, fallback: StoreFailure.Operation) -> StoreFailure {
    if let failure = error as? StoreFailure { return failure }
    if let unsupported = error as? UnsupportedSchemaVersion {
        return StoreFailure(operation: .unsupportedVersion, fileURL: url,
                            reason: "Store version \(unsupported.version) is not supported. Existing data has been preserved.")
    }
    if let validation = error as? ModelValidationError {
        return StoreFailure(operation: .validation, fileURL: url, reason: validation.reason)
    }
    if error is DecodingError {
        return StoreFailure(operation: .decode, fileURL: url,
                            reason: "Stored Deep Work data could not be decoded. Existing data has been preserved.")
    }
    return StoreFailure(operation: fallback, fileURL: url, reason: error.localizedDescription)
}

private final class LocalDatabase {
    let directory: URL
    let fileURL: URL
    let legacyDirectory: URL?
    let journalDefaults: JournalDocument

    init(directory: URL, legacyDirectory: URL?, journalDefaults: JournalDocument) {
        self.directory = directory
        fileURL = directory.appendingPathComponent(StoreLocation.databaseFilename)
        self.legacyDirectory = legacyDirectory
        self.journalDefaults = journalDefaults
    }

    func withConnection<T>(_ body: (SQLiteConnection) throws -> T) throws -> T {
        if try !pathExists(fileURL) { try createDatabase() }
        let connection = try SQLiteConnection(url: fileURL, create: false)
        defer { connection.close() }
        // Do this before WAL configuration or permission changes. Opening an
        // unsupported or malformed database must never initialize/replace it.
        let version = try connection.integer("PRAGMA user_version")
        guard version == 1 || version == 2 else { throw UnsupportedSchemaVersion(version) }
        if version == 1 {
            // Add only the restoration receipt. All original payload bytes stay
            // intact; table creation and version advancement commit together.
            try connection.transaction(immediate: true) {
                try connection.execute("CREATE TABLE slack_state (id INTEGER PRIMARY KEY CHECK(id = 1), payload BLOB NOT NULL)")
                try connection.writeSlack(SlackDocument())
                try connection.execute("PRAGMA user_version=2")
            }
        }
        try restrictPermissions(of: directory, to: 0o700)
        try restrictPermissions(of: fileURL, to: 0o600)
        try connection.configureWAL()
        return try body(connection)
    }

    private func createDatabase() throws {
        // Both old documents are validated before publishing any database. If
        // migration fails, source files remain untouched and the next launch
        // can retry. A successfully published database is the sole source of
        // truth: legacy JSON is never re-imported over subsequent SQLite edits.
        let journal: JournalDocument = try legacyDocument(JournalStore.legacyFilename) ?? journalDefaults
        let settings: SettingsDocument = try legacyDocument(SettingsStore.legacyFilename) ?? SettingsDocument()
        try journal.validate(); try settings.validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try restrictPermissions(of: directory, to: 0o700)
        let temporaryURL = directory.appendingPathComponent(".DeepWork-migration-\(UUID().uuidString).sqlite")
        defer {
            // Only our unpublished temporary database is removed, after close.
            // Never remove a live database's WAL/SHM files independently.
            for suffix in ["", "-journal", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: temporaryURL.path + suffix)
            }
        }
        let connection = try SQLiteConnection(url: temporaryURL, create: true)
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)
            try connection.execute("PRAGMA synchronous=FULL")
            try connection.transaction(immediate: true) {
                try connection.execute("""
                    CREATE TABLE session_records (
                        id TEXT PRIMARY KEY NOT NULL,
                        position INTEGER NOT NULL UNIQUE CHECK(position >= 0),
                        payload BLOB NOT NULL
                    ) WITHOUT ROWID;
                    CREATE TABLE journal_state (
                        id INTEGER PRIMARY KEY CHECK(id = 1),
                        payload BLOB NOT NULL
                    );
                    CREATE TABLE settings (
                        id INTEGER PRIMARY KEY CHECK(id = 1),
                        payload BLOB NOT NULL
                    );
                    CREATE TABLE slack_state (
                        id INTEGER PRIMARY KEY CHECK(id = 1),
                        payload BLOB NOT NULL
                    );
                    """)
                try connection.writeJournal(journal)
                try connection.writeSettings(settings)
                try connection.writeSlack(SlackDocument())
                try connection.execute("PRAGMA user_version=2")
            }
            connection.close()
            // This same-directory rename publishes the fully committed database.
            // FileManager refuses to overwrite an existing destination.
            try FileManager.default.moveItem(at: temporaryURL, to: fileURL)
        } catch {
            connection.close()
            throw error
        }
    }

    private func legacyDocument<T: StoredDocument>(_ filename: String) throws -> T? {
        var candidates = [directory.appendingPathComponent(filename)]
        if let legacyDirectory,
           legacyDirectory.standardizedFileURL != directory.standardizedFileURL {
            candidates.append(legacyDirectory.appendingPathComponent(filename))
        }
        var source: (URL, Data)?
        for url in candidates {
            do {
                let bytes: Data
                do { bytes = try Data(contentsOf: url) }
                catch {
                    // fileExists hides EACCES/ENOTDIR as false. Only an actual
                    // ENOENT is absence; inaccessible or ambiguous legacy data
                    // must prevent publishing defaults as a new source of truth.
                    if try !pathExists(url) { continue }
                    throw error
                }
                if let previous = source, previous.1 != bytes {
                    throw ModelValidationError("Two different legacy \(filename) files exist. Neither has been overwritten.")
                }
                source = (url, bytes)
            } catch {
                throw storeFailure(error, at: url, fallback: .read)
            }
        }
        guard let (url, bytes) = source else { return nil }
        do { return try decodeDocument(T.self, from: bytes) }
        catch { throw storeFailure(error, at: url, fallback: .decode) }
    }

    private func pathExists(_ url: URL) throws -> Bool {
        var information = stat()
        if lstat(url.path, &information) == 0 { return true }
        let code = errno
        if code == ENOENT { return false }
        throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }

    private func restrictPermissions(of url: URL, to maximumMode: Int) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let existing = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? maximumMode
        let restricted = existing & maximumMode
        if restricted != existing {
            try FileManager.default.setAttributes([.posixPermissions: restricted], ofItemAtPath: url.path)
        }
    }
}

private struct SQLiteFailure: Error, LocalizedError {
    let code: Int32
    let message: String
    var errorDescription: String? { "SQLite error \(code): \(message)" }
}

/// Small checked C API wrapper. Statements finalize on every path, transactions
/// roll back after body/commit failures, and parameters are always bound.
final class SQLiteConnection {
    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL, create: Bool) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | (create ? SQLITE_OPEN_CREATE : 0)
        let result = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard result == SQLITE_OK else {
            let failure = error(result)
            close()
            throw failure
        }
        do {
            try check(sqlite3_extended_result_codes(handle, 1))
            try check(sqlite3_busy_timeout(handle, 250))
            try execute("PRAGMA foreign_keys=ON")
        } catch {
            close()
            throw error
        }
    }

    deinit { close() }

    func close() {
        if let handle {
            sqlite3_close_v2(handle)
            self.handle = nil
        }
    }

    func configureWAL() throws {
        let mode = try text("PRAGMA journal_mode=WAL")
        guard mode.lowercased() == "wal" else {
            throw SQLiteFailure(code: SQLITE_ERROR, message: "Write-ahead logging could not be enabled.")
        }
        try execute("PRAGMA synchronous=FULL")
    }

    func transaction<T>(immediate: Bool, _ body: () throws -> T) throws -> T {
        try execute(immediate ? "BEGIN IMMEDIATE" : "BEGIN DEFERRED")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func execute(_ sql: String) throws {
        let result = sqlite3_exec(handle, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw error(result) }
    }

    func integer(_ sql: String) throws -> Int {
        try statement(sql) { statement in
            try row(statement)
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    private func text(_ sql: String) throws -> String {
        try statement(sql) { statement in
            try row(statement)
            guard let value = sqlite3_column_text(statement, 0) else {
                throw SQLiteFailure(code: SQLITE_MISMATCH, message: "Expected a text result.")
            }
            return String(cString: value)
        }
    }

    func readJournal() throws -> JournalDocument {
        let state: JournalState = try singleton("journal_state", as: JournalState.self)
        var records: [SessionRecord] = []
        try statement("SELECT id, position, payload FROM session_records ORDER BY position") { statement in
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { break }
                guard result == SQLITE_ROW else { throw error(result) }
                guard sqlite3_column_type(statement, 0) == SQLITE_TEXT,
                      let rawID = sqlite3_column_text(statement, 0),
                      let id = UUID(uuidString: String(cString: rawID)) else {
                    throw ModelValidationError("A journal row has an invalid session identifier.")
                }
                try require(sqlite3_column_type(statement, 1) == SQLITE_INTEGER &&
                            Int(sqlite3_column_int64(statement, 1)) == records.count,
                            "Stored session ordering is invalid.")
                let record = try decodePayload(SessionRecord.self, from: blob(statement, column: 2))
                try require(record.id == id, "A journal row identifier does not match its record.")
                records.append(record)
            }
        }
        let document = JournalDocument(version: state.version, records: records,
                                       configuration: state.configuration, schedule: state.schedule,
                                       activeCheckpoint: state.activeCheckpoint)
        try document.validate()
        return document
    }

    func writeJournal(_ journal: JournalDocument) throws {
        try journal.validate()
        try execute("DELETE FROM session_records")
        try statement("INSERT INTO session_records(id, position, payload) VALUES (?, ?, ?)") { statement in
            for (position, record) in journal.records.enumerated() {
                try check(sqlite3_bind_text(statement, 1, record.id.uuidString, -1, Self.transient))
                try check(sqlite3_bind_int64(statement, 2, Int64(position)))
                try bind(encodePayload(record), to: statement, index: 3)
                try done(statement)
                try check(sqlite3_reset(statement))
                try check(sqlite3_clear_bindings(statement))
            }
        }
        try writeSingleton("journal_state", payload: encodePayload(JournalState(journal)))
    }

    func readSettings() throws -> SettingsDocument {
        let document: SettingsDocument = try singleton("settings", as: SettingsDocument.self)
        try document.validate()
        return document
    }

    func writeSettings(_ settings: SettingsDocument) throws {
        try settings.validate()
        try writeSingleton("settings", payload: encodePayload(settings))
    }

    func readSlack() throws -> SlackDocument {
        let document: SlackDocument = try singleton("slack_state", as: SlackDocument.self)
        try document.validate()
        return document
    }

    func writeSlack(_ document: SlackDocument) throws {
        try document.validate()
        try writeSingleton("slack_state", payload: encodePayload(document))
    }

    private func singleton<T: Decodable>(_ table: String, as: T.Type) throws -> T {
        try statement("SELECT payload FROM \(table) WHERE id=1") { statement in
            try row(statement)
            return try decodePayload(T.self, from: blob(statement, column: 0))
        }
    }

    private func writeSingleton(_ table: String, payload: Data) throws {
        try statement("INSERT INTO \(table)(id, payload) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload") { statement in
            try bind(payload, to: statement, index: 1)
            try done(statement)
        }
    }

    private func statement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var prepared: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &prepared, nil)
        guard result == SQLITE_OK, let prepared else { throw error(result) }
        defer { sqlite3_finalize(prepared) }
        return try body(prepared)
    }

    private func row(_ statement: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            if result == SQLITE_DONE { throw ModelValidationError("A required SQLite data row is missing.") }
            throw error(result)
        }
    }

    private func done(_ statement: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else { throw error(result) }
    }

    private func check(_ result: Int32) throws {
        guard result == SQLITE_OK else { throw error(result) }
    }

    private func bind(_ bytes: Data, to statement: OpaquePointer, index: Int32) throws {
        try bytes.withUnsafeBytes { raw in
            try check(sqlite3_bind_blob(statement, index, raw.baseAddress, Int32(raw.count), Self.transient))
        }
    }

    private func blob(_ statement: OpaquePointer, column: Int32) throws -> Data {
        let length = Int(sqlite3_column_bytes(statement, column))
        guard length > 0, let value = sqlite3_column_blob(statement, column) else {
            throw ModelValidationError("A stored SQLite payload is empty or missing.")
        }
        return Data(bytes: value, count: length)
    }

    private func error(_ code: Int32) -> SQLiteFailure {
        let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "The database could not be opened."
        return SQLiteFailure(code: code, message: message)
    }
}

private struct JournalState: Codable {
    var version: Int
    var configuration: FocusConfiguration
    var schedule: WorkSchedule
    var activeCheckpoint: ActiveCheckpoint?

    init(_ journal: JournalDocument) {
        version = journal.version; configuration = journal.configuration
        schedule = journal.schedule; activeCheckpoint = journal.activeCheckpoint
    }
}

private struct SchemaHeader: Decodable { let version: Int }

private func encodePayload<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
}

private func decodePayload<T: Decodable>(_ type: T.Type, from bytes: Data) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return try decoder.decode(type, from: bytes)
}

private func decodeDocument<T: StoredDocument>(_ type: T.Type, from bytes: Data) throws -> T {
    let version = try JSONDecoder().decode(SchemaHeader.self, from: bytes).version
    guard version == 1 else { throw UnsupportedSchemaVersion(version) }
    let document = try decodePayload(type, from: bytes)
    try document.validate()
    return document
}
