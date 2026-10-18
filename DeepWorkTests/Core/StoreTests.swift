import Foundation
import SQLite3
import Testing
@testable import DeepWorkCore

final class StoreTests {
    let directory: URL
    let start = Date(timeIntervalSince1970: 1_792_300_000.125)

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    @Test func testFreshSQLiteContainsDocumentedDefaultsAndNoExampleRecords() throws {
        let journalStore = JournalStore(directory: directory)
        let journal = journalStore.load()
        let settings = SettingsStore(directory: directory).load()
        #expect(journal.failure == nil)
        #expect(settings.failure == nil)
        #expect(journal.value.records.isEmpty)
        #expect(journal.value.activeCheckpoint == nil)
        #expect(!journal.value.configuration.canStart)
        #expect(journal.value.configuration.repeats)
        #expect(settings.value == SettingsDocument())
        #expect(journalStore.fileURL.lastPathComponent == "DeepWork.sqlite")
        let db = try TestDatabase(journalStore.fileURL)
        #expect(try db.integer("PRAGMA user_version") == 1)
        #expect(try db.text("PRAGMA journal_mode") == "wal")
        #expect(try db.integer("SELECT COUNT(*) FROM session_records") == 0)
        #expect(try db.integer("SELECT COUNT(*) FROM journal_state") == 1)
        #expect(try db.integer("SELECT COUNT(*) FROM settings") == 1)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(JournalStore.legacyFilename).path))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(SettingsStore.legacyFilename).path))
        let header = try Data(contentsOf: journalStore.fileURL).prefix(16)
        #expect(header == Data("SQLite format 3\0".utf8))
    }

    @Test func testJournalRowsRoundTripAbsoluteTimesSegmentsPreferencesAndSchedule() throws {
        var document = journalFixture()
        document.records.append(secondRecord())
        document.configuration = FocusConfiguration(focusSelection: .custom, breakSelection: .preset(20),
                                                    customFocusMinutes: 90, customBreakMinutes: 17, repeats: false)
        document.schedule = WorkSchedule(mode: .rotatingShifts, weekdays: [], workDays: 3, restDays: 2,
                                         firstWorkDay: CivilDate(year: 2026, month: 10, day: 18),
                                         weekStartsOn: .sunday, reportingDayStartMinutes: 240)
        let store = JournalStore(directory: directory)
        #expect(store.save(document) == nil)
        let reopened = JournalStore(directory: directory).load()
        #expect(reopened.failure == nil)
        #expect(reopened.value == document)
        #expect(reopened.value.records[0].focusedSeconds == 60)
        let db = try TestDatabase(store.fileURL)
        #expect(try db.integer("SELECT COUNT(*) FROM session_records") == 2)
        #expect(try db.text("SELECT id FROM session_records WHERE position=0") == document.records[0].id.uuidString)
        let recordJSON = try #require(try JSONSerialization.jsonObject(with: db.blob("SELECT payload FROM session_records WHERE position=0")) as? [String: Any])
        #expect(recordJSON["segments"] != nil)
        #expect(recordJSON["focusedSeconds"] == nil)
        let stateJSON = try #require(try JSONSerialization.jsonObject(with: db.blob("SELECT payload FROM journal_state")) as? [String: Any])
        #expect(stateJSON["records"] == nil)
        #expect(stateJSON["schedule"] != nil)
        #expect(stateJSON["configuration"] != nil)
    }

    @Test func testCheckpointRoundTripAddsNoDowntimeAndHasNoOpenSegment() throws {
        let record = SessionRecord(startedAt: start, endedAt: start.addingTimeInterval(20.125),
                                   plannedFocusMinutes: 1, outcome: .live,
                                   segments: [ActiveSegment(startedAt: start, endedAt: start.addingTimeInterval(20.125))])
        let checkpoint = ActiveCheckpoint(phase: .focus, focusMinutes: 1, breakMinutes: 10,
                                          remainingSeconds: 39.875, savedAt: record.endedAt, focusRecord: record)
        let store = JournalStore(directory: directory)
        #expect(store.save(JournalDocument(activeCheckpoint: checkpoint)) == nil)
        let reopened = JournalStore(directory: directory).load()
        #expect(reopened.failure == nil)
        #expect(reopened.value.activeCheckpoint == checkpoint)
        let db = try TestDatabase(store.fileURL)
        let stateText = String(decoding: try db.blob("SELECT payload FROM journal_state"), as: UTF8.self)
        #expect(!stateText.contains("deadline"))
        #expect(!stateText.contains("openStart"))
        #expect(try db.integer("SELECT COUNT(*) FROM session_records") == 0)
    }

    @Test func testSettingsSavesNeverReplaceHistoryOrImplicitlySaveFormEdits() throws {
        let journalStore = JournalStore(directory: directory)
        let journal = journalFixture()
        #expect(journalStore.save(journal) == nil)
        let db = try TestDatabase(journalStore.fileURL)
        let recordBytes = try db.blob("SELECT payload FROM session_records")
        let stateBytes = try db.blob("SELECT payload FROM journal_state")
        let store = SettingsStore(directory: directory)
        var settings = SettingsDocument(feedbackDraft: try FeedbackDraft(type: .problem, message: "Saved draft").validatedForSaving())
        #expect(store.save(settings) == nil)
        var unsavedForm = settings.feedbackDraft
        unsavedForm.message = "Unsaved edits"
        settings.launchAtLogin = true
        #expect(store.save(settings) == nil)
        #expect(SettingsStore(directory: directory).load().value.feedbackDraft.message == "Saved draft")
        #expect(SettingsStore(directory: directory).load().value.launchAtLogin)
        #expect(try db.blob("SELECT payload FROM session_records") == recordBytes)
        #expect(try db.blob("SELECT payload FROM journal_state") == stateBytes)
        settings.feedbackDraft = try unsavedForm.validatedForSaving()
        #expect(store.save(settings) == nil)
        #expect(SettingsStore(directory: directory).load().value == settings)
    }

    @Test func testPhysicallyMalformedDatabaseIsPreservedAndCannotBeOverwritten() throws {
        let bytes = Data("not a SQLite database containing recoverable user data".utf8)
        let store = JournalStore(directory: directory)
        try bytes.write(to: store.fileURL)
        let loaded = store.load()
        #expect(loaded.failure?.operation == .read)
        #expect(loaded.value.records.isEmpty)
        #expect(store.save(journalFixture()) == loaded.failure)
        #expect(SettingsStore(directory: directory).save(SettingsDocument()) != nil)
        #expect(try Data(contentsOf: store.fileURL) == bytes)
    }

    @Test func testFutureAndUnversionedDatabasesAreNotInitializedOrModified() throws {
        let url = directory.appendingPathComponent(StoreLocation.databaseFilename)
        do {
            let db = try TestDatabase(url, create: true)
            try db.execute("CREATE TABLE future_history(payload TEXT); INSERT INTO future_history VALUES ('preserve'); PRAGMA user_version=99")
        }
        let original = try Data(contentsOf: url)
        #expect(JournalStore(directory: directory).load().failure?.operation == .unsupportedVersion)
        #expect(SettingsStore(directory: directory).save(SettingsDocument())?.operation == .unsupportedVersion)
        #expect(try Data(contentsOf: url) == original)
        do { let db = try TestDatabase(url); try db.execute("PRAGMA user_version=0") }
        let unversioned = try Data(contentsOf: url)
        #expect(JournalStore(directory: directory).load().failure?.operation == .unsupportedVersion)
        #expect(try Data(contentsOf: url) == unversioned)
    }

    @Test func testMalformedSettingsLatchOnlySettingsAndPreserveBadPayload() throws {
        let journal = JournalStore(directory: directory)
        #expect(journal.save(journalFixture()) == nil)
        let db = try TestDatabase(journal.fileURL)
        try db.setBlob(Data([0xFF]), sql: "UPDATE settings SET payload=? WHERE id=1")
        let settings = SettingsStore(directory: directory)
        #expect(settings.load().failure?.operation == .decode)
        #expect(settings.save(SettingsDocument())?.operation == .decode)
        var updated = journal.load().value
        updated.configuration.repeats = false
        #expect(journal.save(updated) == nil)
        #expect(JournalStore(directory: directory).load().value == updated)
        #expect(try db.blob("SELECT payload FROM settings") == Data([0xFF]))
    }

    @Test func testMalformedJournalDoesNotPreventIndependentSettingsSaves() throws {
        let fixture = journalFixture()
        let store = JournalStore(directory: directory)
        #expect(store.save(fixture) == nil)
        let db = try TestDatabase(store.fileURL)
        let record = try db.blob("SELECT payload FROM session_records")
        try db.execute("UPDATE session_records SET id='not-a-uuid'")
        let reopened = JournalStore(directory: directory)
        #expect(reopened.load().failure?.operation == .validation)
        #expect(reopened.save(JournalDocument())?.operation == .validation)
        let settings = SettingsDocument(launchAtLogin: true, feedbackDraft: FeedbackDraft(message: "Still saves"))
        #expect(SettingsStore(directory: directory).save(settings) == nil)
        #expect(SettingsStore(directory: directory).load().value == settings)
        #expect(try db.blob("SELECT payload FROM session_records") == record)
        #expect(try db.text("SELECT id FROM session_records") == "not-a-uuid")
    }

    @Test func testRowIdentifierMustMatchPayloadAndSegmentsMustStayOrdered() throws {
        let fixture = journalFixture()
        let store = JournalStore(directory: directory)
        #expect(store.save(fixture) == nil)
        let db = try TestDatabase(store.fileURL)
        try db.execute("UPDATE session_records SET id='\(UUID().uuidString)'")
        #expect(JournalStore(directory: directory).load().failure?.operation == .validation)
        try db.execute("UPDATE session_records SET id='\(fixture.records[0].id.uuidString)'")
        var badRecord = fixture.records[0]
        badRecord.segments.reverse()
        let badBytes = try encoded(badRecord)
        try db.setBlob(badBytes, sql: "UPDATE session_records SET payload=?")
        let reloaded = JournalStore(directory: directory)
        #expect(reloaded.load().failure?.operation == .validation)
        #expect(reloaded.save(fixture)?.operation == .validation)
        #expect(try db.blob("SELECT payload FROM session_records") == badBytes)
    }

    @Test func testMissingStateAndInvalidRecordPositionAreRejected() throws {
        let store = JournalStore(directory: directory)
        #expect(store.save(journalFixture()) == nil)
        let db = try TestDatabase(store.fileURL)
        try db.execute("UPDATE session_records SET position=7")
        #expect(JournalStore(directory: directory).load().failure?.operation == .validation)
        try db.execute("UPDATE session_records SET position=0.5")
        #expect(JournalStore(directory: directory).load().failure?.operation == .validation)
        try db.execute("UPDATE session_records SET position=0; DELETE FROM journal_state")
        #expect(JournalStore(directory: directory).load().failure?.operation == .validation)
        #expect(SettingsStore(directory: directory).load().failure == nil)
    }

    @Test func testFailedMidTransactionSaveRollsBackRecordsStateAndLeavesSettingsUntouched() throws {
        let store = JournalStore(directory: directory)
        var original = journalFixture()
        original.records.append(secondRecord())
        #expect(store.save(original) == nil)
        let settings = SettingsDocument(launchAtLogin: true, feedbackDraft: FeedbackDraft(message: "Saved feedback"))
        #expect(SettingsStore(directory: directory).save(settings) == nil)
        let db = try TestDatabase(store.fileURL)
        try db.execute("""
            CREATE TRIGGER reject_second_record BEFORE INSERT ON session_records
            WHEN NEW.position=1 BEGIN SELECT RAISE(ABORT, 'injected transaction failure'); END
            """)
        var replacement = original
        replacement.records[0].id = UUID()
        replacement.configuration.repeats = false
        #expect(store.save(replacement)?.operation == .write)
        #expect(JournalStore(directory: directory).load().value == original)
        #expect(SettingsStore(directory: directory).load().value == settings)
        try db.execute("DROP TRIGGER reject_second_record")
        #expect(store.save(replacement)?.operation == .write) // failure remains visible until relaunch
        #expect(JournalStore(directory: directory).load().value == original)
    }

    @Test func testBusyWriterFailsWithinBoundedWaitAndPreservesCommittedData() throws {
        let store = JournalStore(directory: directory)
        let original = journalFixture()
        #expect(store.save(original) == nil)
        let blockingConnection = try TestDatabase(store.fileURL)
        try blockingConnection.execute("BEGIN IMMEDIATE")
        let began = Date()
        let failure = store.save(JournalDocument())
        let waited = Date().timeIntervalSince(began)
        #expect(failure?.operation == .write)
        #expect(waited < 2)
        try blockingConnection.execute("ROLLBACK")
        #expect(JournalStore(directory: directory).load().value == original)
        #expect(store.save(JournalDocument()) == failure)
    }

    @Test func testInvalidWriteCannotReplaceValidSQLiteRows() throws {
        let store = JournalStore(directory: directory)
        let original = journalFixture()
        #expect(store.save(original) == nil)
        var invalid = JournalDocument()
        invalid.schedule.restDays = 0
        #expect(store.save(invalid)?.operation == .validation)
        #expect(JournalStore(directory: directory).load().value == original)
    }

    @Test func testConcurrentJournalAndSettingsStoresKeepBothDomainsComplete() throws {
        let fixture = journalFixture()
        let journal = JournalStore(directory: directory)
        #expect(journal.save(fixture) == nil)
        let failures = FailureCollector()
        DispatchQueue.concurrentPerform(iterations: 24) { iteration in
            if iteration.isMultiple(of: 2) {
                var updated = fixture
                updated.configuration.customFocusMinutes = iteration + 1
                if let failure = JournalStore(directory: directory).save(updated) { failures.add(failure) }
            } else {
                let updated = SettingsDocument(feedbackDraft: FeedbackDraft(message: "Saved draft \(iteration)"))
                if let failure = SettingsStore(directory: directory).save(updated) { failures.add(failure) }
            }
        }
        #expect(failures.values.isEmpty)
        let loaded = JournalStore(directory: directory).load()
        #expect(loaded.failure == nil)
        #expect(loaded.value.records == fixture.records)
        #expect((1...24).contains(loaded.value.configuration.customFocusMinutes))
        let settings = SettingsStore(directory: directory).load()
        #expect(settings.failure == nil)
        #expect(settings.value.feedbackDraft.message.hasPrefix("Saved draft "))
        let db = try TestDatabase(journal.fileURL)
        #expect(try db.text("PRAGMA integrity_check") == "ok")
    }

    @Test func testLegacyJSONMigrationIsLosslessAndRunsOnlyOnce() throws {
        var journal = journalFixture()
        journal.configuration.focusSelection = .preset(90)
        let settings = SettingsDocument(launchAtLogin: true, feedbackDraft: FeedbackDraft(type: .idea, message: "Legacy feedback"))
        let journalBytes = try encoded(journal)
        let settingsBytes = try encoded(settings)
        let legacyJournalURL = directory.appendingPathComponent(JournalStore.legacyFilename)
        let legacySettingsURL = directory.appendingPathComponent(SettingsStore.legacyFilename)
        try journalBytes.write(to: legacyJournalURL)
        try settingsBytes.write(to: legacySettingsURL)
        let store = JournalStore(directory: directory)
        #expect(store.load().failure == nil)
        #expect(store.load().value == journal)
        #expect(SettingsStore(directory: directory).load().value == settings)
        #expect(try Data(contentsOf: legacyJournalURL) == journalBytes)
        #expect(try Data(contentsOf: legacySettingsURL) == settingsBytes)
        var changed = journal
        changed.configuration.repeats = false
        #expect(store.save(changed) == nil)
        try Data("broken legacy after successful migration".utf8).write(to: legacyJournalURL)
        #expect(JournalStore(directory: directory).load().value == changed)
        #expect(SettingsStore(directory: directory).load().value == settings)
    }

    @Test func testMigrationFindsOldDisplayNameDirectoryWithoutWritingIt() throws {
        let legacy = directory.appendingPathComponent("Deep Work", isDirectory: true)
        let canonical = directory.appendingPathComponent("app.deepwork.mac", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let journal = journalFixture()
        let bytes = try encoded(journal)
        let source = legacy.appendingPathComponent(JournalStore.legacyFilename)
        try bytes.write(to: source)
        let loaded = JournalStore(directory: canonical, legacyDirectory: legacy).load()
        #expect(loaded.failure == nil)
        #expect(loaded.value == journal)
        #expect(SettingsStore(directory: canonical, legacyDirectory: legacy).load().value == SettingsDocument())
        #expect(try Data(contentsOf: source) == bytes)
        #expect(!FileManager.default.fileExists(atPath: legacy.appendingPathComponent(StoreLocation.databaseFilename).path))
    }

    @Test func testFailedMigrationPreservesBothSourcesAndCanRetryAfterRepair() throws {
        let journal = journalFixture()
        let journalBytes = try encoded(journal)
        let settingsBytes = Data("malformed settings".utf8)
        let journalURL = directory.appendingPathComponent(JournalStore.legacyFilename)
        let settingsURL = directory.appendingPathComponent(SettingsStore.legacyFilename)
        try journalBytes.write(to: journalURL)
        try settingsBytes.write(to: settingsURL)
        let failed = JournalStore(directory: directory)
        #expect(failed.load().failure?.operation == .decode)
        #expect(!FileManager.default.fileExists(atPath: failed.fileURL.path))
        #expect(try Data(contentsOf: journalURL) == journalBytes)
        #expect(try Data(contentsOf: settingsURL) == settingsBytes)
        #expect(failed.save(JournalDocument())?.operation == .decode)
        try encoded(SettingsDocument()).write(to: settingsURL)
        let retried = JournalStore(directory: directory).load()
        #expect(retried.failure == nil)
        #expect(retried.value == journal)
    }

    @Test func testFutureLegacyVersionCannotBecomeEmptyNativeDatabase() throws {
        let bytes = Data(#"{"version":2,"futureHistory":"preserve"}"#.utf8)
        let source = directory.appendingPathComponent(JournalStore.legacyFilename)
        try bytes.write(to: source)
        let store = SettingsStore(directory: directory)
        #expect(store.save(SettingsDocument())?.operation == .unsupportedVersion)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(try Data(contentsOf: source) == bytes)
    }

    @Test func testReadOnlyDirectoryFailureDoesNotPublishEmptyDatabaseOrLoseLegacyFiles() throws {
        let original = try encoded(journalFixture())
        let source = directory.appendingPathComponent(JournalStore.legacyFilename)
        try original.write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        let store = JournalStore(directory: directory)
        #expect(store.load().failure != nil)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(try Data(contentsOf: source) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [JournalStore.legacyFilename])
    }

    @Test func testInaccessibleLegacyDirectoryCannotBeMistakenForNoSavedData() throws {
        let legacy = directory.appendingPathComponent("legacy", isDirectory: true)
        let canonical = directory.appendingPathComponent("canonical", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        var journal = journalFixture()
        journal.configuration.repeats = false
        let original = try encoded(journal)
        let source = legacy.appendingPathComponent(JournalStore.legacyFilename)
        try original.write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: legacy.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: legacy.path) }
        let store = JournalStore(directory: canonical, legacyDirectory: legacy)
        #expect(store.load().failure?.operation == .read)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: legacy.path)
        #expect(try Data(contentsOf: source) == original)
        let retry = JournalStore(directory: canonical, legacyDirectory: legacy).load()
        #expect(retry.failure == nil)
        #expect(retry.value == journal)
    }

    @Test func testNonDirectoryLegacySourceCannotPublishDefaultDatabase() throws {
        let legacy = directory.appendingPathComponent("legacy")
        let canonical = directory.appendingPathComponent("canonical", isDirectory: true)
        let original = Data("legacy path is a file".utf8)
        try original.write(to: legacy)
        let store = SettingsStore(directory: canonical, legacyDirectory: legacy)
        #expect(store.load().failure?.operation == .read)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(try Data(contentsOf: legacy) == original)
    }

    @Test func testPrivatePermissionsAndBundleIdentifierApplicationSupportLocation() throws {
        let store = JournalStore(directory: directory)
        #expect(store.load().failure == nil)
        let directoryMode = try #require(try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)
        let databaseMode = try #require(try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? NSNumber)
        #expect(directoryMode.intValue == 0o700)
        #expect(databaseMode.intValue == 0o600)
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: false)
        #expect(try StoreLocation.applicationSupportDirectory() == root.appendingPathComponent("app.deepwork.mac", isDirectory: true))
        #expect(try StoreLocation.legacyApplicationSupportDirectory() == root.appendingPathComponent("Deep Work", isDirectory: true))
    }

    private func journalFixture() -> JournalDocument {
        let record = SessionRecord(startedAt: start, endedAt: start.addingTimeInterval(120),
                                   plannedFocusMinutes: 1, outcome: .complete, segments: [
            ActiveSegment(startedAt: start, endedAt: start.addingTimeInterval(30)),
            ActiveSegment(startedAt: start.addingTimeInterval(90), endedAt: start.addingTimeInterval(120))
        ])
        return JournalDocument(records: [record], schedule: WorkSchedule(firstWorkDay: CivilDate(year: 2026, month: 10, day: 18)))
    }

    private func secondRecord() -> SessionRecord {
        let from = start.addingTimeInterval(600)
        return SessionRecord(startedAt: from, endedAt: from.addingTimeInterval(15), plannedFocusMinutes: 60,
                             outcome: .partial, segments: [ActiveSegment(startedAt: from, endedAt: from.addingTimeInterval(15))])
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }
}

private final class FailureCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [StoreFailure] = []
    var values: [StoreFailure] { lock.lock(); defer { lock.unlock() }; return storage }
    func add(_ failure: StoreFailure) { lock.lock(); defer { lock.unlock() }; storage.append(failure) }
}

/// Direct SQLite observations ensure tests verify persisted database rows rather
/// than trusting only the public store's cached values.
private final class TestDatabase {
    private var db: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(_ url: URL, create: Bool = false) throws {
        let flags = SQLITE_OPEN_READWRITE | (create ? SQLITE_OPEN_CREATE : 0)
        let result = sqlite3_open_v2(url.path, &db, flags, nil)
        guard result == SQLITE_OK else { throw TestDatabaseError(code: result) }
    }
    deinit { sqlite3_close_v2(db) }

    func execute(_ sql: String) throws {
        let result = sqlite3_exec(db, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw TestDatabaseError(code: result) }
    }
    func integer(_ sql: String) throws -> Int {
        try statement(sql) { statement in
            try row(statement)
            return Int(sqlite3_column_int64(statement, 0))
        }
    }
    func text(_ sql: String) throws -> String {
        try statement(sql) { statement in
            try row(statement)
            return String(cString: sqlite3_column_text(statement, 0))
        }
    }
    func blob(_ sql: String) throws -> Data {
        try statement(sql) { statement in
            try row(statement)
            return Data(bytes: sqlite3_column_blob(statement, 0), count: Int(sqlite3_column_bytes(statement, 0)))
        }
    }
    func setBlob(_ data: Data, sql: String) throws {
        try statement(sql) { statement in
            let result = data.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32($0.count), Self.transient) }
            guard result == SQLITE_OK else { throw TestDatabaseError(code: result) }
            let step = sqlite3_step(statement)
            guard step == SQLITE_DONE else { throw TestDatabaseError(code: step) }
        }
    }
    private func statement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw TestDatabaseError(code: result) }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }
    private func row(_ statement: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else { throw TestDatabaseError(code: result) }
    }
}

private struct TestDatabaseError: Error { let code: Int32 }
