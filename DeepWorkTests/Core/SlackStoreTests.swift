import Foundation
import Testing
@testable import DeepWorkCore

final class SlackStoreTests {
    let directory: URL
    let start = Date(timeIntervalSince1970: 1_792_300_000.125)

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkSlackStore-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    @Test func testF027_F029SQLiteReceiptSurvivesReopenAndExplicitClearWithoutChangingJournalOrSettings() async throws {
        let journal = journalFixture()
        let settings = settingsFixture()
        #expect(JournalStore(directory: directory).save(journal) == nil)
        #expect(SettingsStore(directory: directory).save(settings) == nil)
        let store = SlackStore(directory: directory)
        #expect(try await store.load() == SlackDocument())
        let receipt = SlackDocument(ownership: ownership())
        try await store.save(receipt)
        #expect(try await SlackStore(directory: directory).load() == receipt)
        let db = try connection()
        defer { db.close() }
        #expect(try db.integer("SELECT COUNT(*) FROM slack_state") == 1)
        #expect(try db.readSlack() == receipt)

        try await store.save(SlackDocument())
        #expect(try await SlackStore(directory: directory).load() == SlackDocument())
        #expect(try db.integer("SELECT COUNT(*) FROM slack_state") == 1)
        #expect(JournalStore(directory: directory).load().value == journal)
        #expect(SettingsStore(directory: directory).load().value == settings)
    }

    @Test func testF025_F027_S021SchemaOneMigrationPreservesOriginalRowsAndCheckpointBytes() async throws {
        let fixture = try createVersionOneDatabase()
        let db = try connection()
        defer { db.close() }
        #expect(try db.integer("PRAGMA user_version") == 1)
        #expect(try db.integer("SELECT COUNT(*) FROM sqlite_master WHERE name='slack_state'") == 0)

        #expect(try await SlackStore(directory: directory).load() == SlackDocument())
        #expect(try db.integer("PRAGMA user_version") == 2)
        try expectOriginalPayloads(fixture, in: db)
        let loadedJournal = JournalStore(directory: directory).load()
        #expect(loadedJournal.failure == nil && loadedJournal.value == fixture.journal)
        #expect(SettingsStore(directory: directory).load().value == fixture.settings)
        #expect(loadedJournal.value.activeCheckpoint?.focusRecord?.segments == fixture.journal.activeCheckpoint?.focusRecord?.segments)
        #expect(loadedJournal.value.activeCheckpoint?.remainingSeconds == 42.875)

        // Reopening all stores must not reinitialize or rewrite prior payloads.
        #expect(try await SlackStore(directory: directory).load() == SlackDocument())
        try expectOriginalPayloads(fixture, in: db)
    }

    @Test func testF027_S021ConflictingMigrationRollsBackVersionAndPreservesDataUntilRepairAndRelaunch() async throws {
        let fixture = try createVersionOneDatabase()
        let db = try connection()
        defer { db.close() }
        let conflict = Data("Preserve this preexisting payload".utf8)
        try db.execute("CREATE TABLE slack_state (id INTEGER PRIMARY KEY, payload BLOB NOT NULL)")
        try db.execute("INSERT INTO slack_state VALUES (1, X'\(hex(conflict))')")
        let store = SlackStore(directory: directory)
        let failedLoad = await failure { _ = try await store.load() }
        #expect(failedLoad?.operation == .read)
        #expect(try db.integer("PRAGMA user_version") == 1)
        #expect(try db.integer("SELECT payload=X'\(hex(conflict))' FROM slack_state WHERE id=1") == 1)
        try expectOriginalPayloads(fixture, in: db)
        let failedSave = await failure { try await store.save(SlackDocument()) }
        #expect(failedSave == failedLoad)
        #expect(try db.integer("PRAGMA user_version") == 1)

        try db.execute("DROP TABLE slack_state")
        // An already failed instance remains visibly failed; a fresh launch
        // retries the migration after the conflicting schema is repaired.
        let latched = await failure { _ = try await store.load() }
        #expect(latched == failedLoad)
        #expect(try await SlackStore(directory: directory).load() == SlackDocument())
        #expect(try db.integer("PRAGMA user_version") == 2)
        try expectOriginalPayloads(fixture, in: db)
        #expect(JournalStore(directory: directory).load().value == fixture.journal)
        #expect(SettingsStore(directory: directory).load().value == fixture.settings)
    }

    @Test func testF027_S021MalformedSlackReceiptIsPreservedWhileJournalAndSettingsRemainWritable() async throws {
        let fixture = try createVersionOneDatabase()
        _ = try await SlackStore(directory: directory).load()
        let db = try connection()
        defer { db.close() }
        let invalid = Data([0xff, 0x00, 0x8f])
        try db.execute("UPDATE slack_state SET payload=X'\(hex(invalid))' WHERE id=1")
        let store = SlackStore(directory: directory)
        let failedLoad = await failure { _ = try await store.load() }
        #expect(failedLoad?.operation == .decode)
        let failedSave = await failure { try await store.save(SlackDocument()) }
        #expect(failedSave == failedLoad)

        var updatedJournal = fixture.journal
        updatedJournal.configuration.repeats = false
        var updatedSettings = fixture.settings
        updatedSettings.feedbackDraft = FeedbackDraft(type: .general, message: "Still save independently")
        #expect(JournalStore(directory: directory).save(updatedJournal) == nil)
        #expect(SettingsStore(directory: directory).save(updatedSettings) == nil)
        #expect(JournalStore(directory: directory).load().value == updatedJournal)
        #expect(SettingsStore(directory: directory).load().value == updatedSettings)
        #expect(try db.integer("SELECT payload=X'\(hex(invalid))' FROM slack_state WHERE id=1") == 1)
    }

    @Test func testF027MissingSlackRowCannotBeReplacedWithAnEmptyReceipt() async throws {
        let store = SlackStore(directory: directory)
        try await store.save(SlackDocument(ownership: ownership()))
        let db = try connection()
        defer { db.close() }
        try db.execute("DELETE FROM slack_state")
        let reopened = SlackStore(directory: directory)
        let failedLoad = await failure { _ = try await reopened.load() }
        #expect(failedLoad?.operation == .validation)
        let failedSave = await failure { try await reopened.save(SlackDocument()) }
        #expect(failedSave == failedLoad)
        #expect(try db.integer("SELECT COUNT(*) FROM slack_state") == 0)
        #expect(JournalStore(directory: directory).load().failure == nil)
        #expect(SettingsStore(directory: directory).load().failure == nil)
    }

    @Test func testF027FutureSlackDocumentVersionPreservesReceiptAndOtherDomains() async throws {
        let fixture = try createVersionOneDatabase()
        _ = try await SlackStore(directory: directory).load()
        let db = try connection()
        defer { db.close() }
        let future = try encoded(SlackDocument(version: 2, ownership: ownership()))
        try db.execute("UPDATE slack_state SET payload=X'\(hex(future))' WHERE id=1")
        let store = SlackStore(directory: directory)
        let failedLoad = await failure { _ = try await store.load() }
        #expect(failedLoad?.operation == .unsupportedVersion)
        let failedSave = await failure { try await store.save(SlackDocument()) }
        #expect(failedSave == failedLoad)
        #expect(try db.integer("SELECT payload=X'\(hex(future))' FROM slack_state WHERE id=1") == 1)
        try expectOriginalPayloads(fixture, in: db)
        #expect(JournalStore(directory: directory).load().value == fixture.journal)
        #expect(SettingsStore(directory: directory).load().value == fixture.settings)
    }

    @Test func testF027FutureDatabaseVersionIsNotMigratedOrOverwritten() async throws {
        _ = try createVersionOneDatabase()
        let db = try connection()
        try db.execute("PRAGMA user_version=99")
        db.close()
        let original = try Data(contentsOf: databaseURL)
        let store = SlackStore(directory: directory)
        let failedLoad = await failure { _ = try await store.load() }
        #expect(failedLoad?.operation == .unsupportedVersion)
        let failedSave = await failure { try await store.save(SlackDocument(ownership: ownership())) }
        #expect(failedSave == failedLoad)
        #expect(try Data(contentsOf: databaseURL) == original)
        #expect(JournalStore(directory: directory).load().failure?.operation == .unsupportedVersion)
        #expect(SettingsStore(directory: directory).load().failure?.operation == .unsupportedVersion)
        #expect(try Data(contentsOf: databaseURL) == original)
    }

    @Test func testF027FailedReceiptWritePreservesCommittedOwnershipAndCanRecoverAfterRelaunch() async throws {
        let store = SlackStore(directory: directory)
        let original = SlackDocument(ownership: ownership())
        try await store.save(original)
        let db = try connection()
        defer { db.close() }
        try db.execute("""
            CREATE TRIGGER reject_slack_update BEFORE UPDATE ON slack_state
            BEGIN SELECT RAISE(ABORT, 'injected receipt failure'); END
            """)
        let failedSave = await failure { try await store.save(SlackDocument()) }
        #expect(failedSave?.operation == .write)
        #expect(try await SlackStore(directory: directory).load() == original)
        #expect(try db.readSlack() == original)
        try db.execute("DROP TRIGGER reject_slack_update")
        let latchedSave = await failure { try await store.save(SlackDocument()) }
        #expect(latchedSave == failedSave)
        let restarted = SlackStore(directory: directory)
        #expect(try await restarted.load() == original)
        try await restarted.save(SlackDocument())
        #expect(try await SlackStore(directory: directory).load() == SlackDocument())
    }

    @Test func testF027InvalidWriteCannotDestroyAValidRestorationReceipt() async throws {
        let store = SlackStore(directory: directory)
        let original = SlackDocument(ownership: ownership())
        try await store.save(original)
        let invalid = SlackDocument(ownership: SlackOwnership(account: account(), cycleID: UUID(),
                                                             previous: SlackProfile(text: "Old", emoji: ":wave:", expiration: -1)))
        let failedSave = await failure { try await store.save(invalid) }
        #expect(failedSave?.operation == .validation)
        #expect(try await SlackStore(directory: directory).load() == original)
    }

    @Test func testF027TypedSlackDocumentsValidateIdentifiersStatusBoundsAndAppliedOwnership() throws {
        try SlackDocument().validate()
        try SlackDocument(ownership: ownership()).validate()
        #expect(throws: UnsupportedSchemaVersion.self) { try SlackDocument(version: 2).validate() }
        for invalidAccount in [
            SlackAccount(workspaceID: "", userID: "U1", workspaceName: "", userName: ""),
            SlackAccount(workspaceID: "T1", userID: "", workspaceName: "", userName: ""),
            SlackAccount(workspaceID: String(repeating: "T", count: 257), userID: "U1", workspaceName: "", userName: "")
        ] {
            #expect(throws: ModelValidationError.self) { try invalidAccount.validate() }
            let document = SlackDocument(ownership: SlackOwnership(account: invalidAccount, cycleID: UUID(), previous: .empty))
            #expect(throws: ModelValidationError.self) { try document.validate() }
        }
        try SlackAccount(workspaceID: String(repeating: "T", count: 256), userID: String(repeating: "U", count: 256),
                         workspaceName: "", userName: "").validate()
        try SlackProfile(text: String(repeating: "😀", count: 2048), emoji: String(repeating: "x", count: 256), expiration: 0).validate()
        for invalidProfile in [
            SlackProfile(text: "", emoji: "", expiration: -1),
            SlackProfile(text: String(repeating: "😀", count: 2049), emoji: "", expiration: 0),
            SlackProfile(text: "", emoji: String(repeating: "x", count: 257), expiration: 0)
        ] {
            #expect(throws: ModelValidationError.self) { try invalidProfile.validate() }
        }
        let unsupportedApplied = SlackDocument(ownership: SlackOwnership(account: account(), cycleID: UUID(),
                                                                         previous: .empty, applied: .empty))
        #expect(throws: ModelValidationError.self) { try unsupportedApplied.validate() }
        #expect(account().matches(SlackAccount(workspaceID: "T1", userID: "U1", workspaceName: "Renamed", userName: "Renamed")))
        #expect(!account().matches(SlackAccount(workspaceID: "T2", userID: "U1", workspaceName: "Workspace", userName: "User")))
        #expect(!account().matches(SlackAccount(workspaceID: "T1", userID: "U2", workspaceName: "Workspace", userName: "User")))
    }

    @Test func testF029RestoreClearsAnExpiredStatusAtExactBoundaryAndKeepsUnexpiredOrPermanentStatus() {
        let previous = SlackProfile(text: "In a meeting", emoji: ":calendar:", expiration: 100)
        #expect(previous.restoring(at: Date(timeIntervalSince1970: 99.999)) == previous)
        #expect(previous.restoring(at: Date(timeIntervalSince1970: 100)) == .empty)
        #expect(previous.restoring(at: Date(timeIntervalSince1970: 100.001)) == .empty)
        let permanent = SlackProfile(text: "Available", emoji: ":wave:", expiration: 0)
        #expect(permanent.restoring(at: Date(timeIntervalSince1970: 1_800_000_000)) == permanent)
        #expect(SlackProfile.empty.restoring(at: Date(timeIntervalSince1970: 100)) == .empty)
    }

    private struct LegacyFixture {
        let journal: JournalDocument
        let settings: SettingsDocument
        let recordPayloads: [Data]
        let journalPayload: Data
        let settingsPayload: Data
    }

    /// Construct the actual prior schema independently of the migrator. Pretty
    /// printed JSON intentionally differs from current canonical serialization,
    /// so equality below detects a migration that decodes and rewrites history.
    private func createVersionOneDatabase() throws -> LegacyFixture {
        let journal = journalFixture()
        let settings = settingsFixture()
        let records = try journal.records.map { try encoded($0) }
        let rawJournal = try JSONSerialization.jsonObject(with: encoded(journal))
        let journalObject = try #require(rawJournal as? [String: Any])
        let state = journalObject.filter { $0.key != "records" }
        let journalBytes = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
        let settingsBytes = try encoded(settings)
        let db = try SQLiteConnection(url: databaseURL, create: true)
        defer { db.close() }
        try db.transaction(immediate: true) {
            try db.execute("""
                CREATE TABLE session_records (id TEXT PRIMARY KEY NOT NULL, position INTEGER NOT NULL UNIQUE CHECK(position >= 0), payload BLOB NOT NULL) WITHOUT ROWID;
                CREATE TABLE journal_state (id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL);
                CREATE TABLE settings (id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL);
                PRAGMA user_version=1;
                """)
            for (position, record) in journal.records.enumerated() {
                try db.execute("INSERT INTO session_records VALUES ('\(record.id.uuidString)', \(position), X'\(hex(records[position]))')")
            }
            try db.execute("INSERT INTO journal_state VALUES (1, X'\(hex(journalBytes))')")
            try db.execute("INSERT INTO settings VALUES (1, X'\(hex(settingsBytes))')")
        }
        return LegacyFixture(journal: journal, settings: settings, recordPayloads: records,
                             journalPayload: journalBytes, settingsPayload: settingsBytes)
    }

    private func expectOriginalPayloads(_ fixture: LegacyFixture, in db: SQLiteConnection) throws {
        #expect(try db.integer("SELECT COUNT(*) FROM session_records") == fixture.recordPayloads.count)
        for (position, bytes) in fixture.recordPayloads.enumerated() {
            #expect(try db.integer("SELECT payload=X'\(hex(bytes))' FROM session_records WHERE position=\(position)") == 1)
        }
        #expect(try db.integer("SELECT payload=X'\(hex(fixture.journalPayload))' FROM journal_state WHERE id=1") == 1)
        #expect(try db.integer("SELECT payload=X'\(hex(fixture.settingsPayload))' FROM settings WHERE id=1") == 1)
    }

    private var databaseURL: URL { directory.appendingPathComponent(StoreLocation.databaseFilename) }
    private func connection() throws -> SQLiteConnection { try SQLiteConnection(url: databaseURL, create: false) }
    private func hex(_ bytes: Data) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    private func journalFixture() -> JournalDocument {
        let completed = SessionRecord(startedAt: start, endedAt: start.addingTimeInterval(90), plannedFocusMinutes: 1,
                                      outcome: .complete, segments: [
            ActiveSegment(startedAt: start, endedAt: start.addingTimeInterval(30)),
            ActiveSegment(startedAt: start.addingTimeInterval(60), endedAt: start.addingTimeInterval(90))
        ])
        let liveStart = start.addingTimeInterval(600)
        let savedAt = liveStart.addingTimeInterval(17.125)
        let live = SessionRecord(startedAt: liveStart, endedAt: savedAt, plannedFocusMinutes: 1, outcome: .live,
                                 segments: [ActiveSegment(startedAt: liveStart, endedAt: savedAt)])
        let checkpoint = ActiveCheckpoint(phase: .focus, focusMinutes: 1, breakMinutes: 10,
                                          remainingSeconds: 42.875, savedAt: savedAt, focusRecord: live)
        var configuration = FocusConfiguration()
        configuration.focusSelection = .preset(60)
        configuration.breakSelection = .preset(10)
        return JournalDocument(records: [completed], configuration: configuration,
                               schedule: WorkSchedule(firstWorkDay: CivilDate(year: 2026, month: 10, day: 18)),
                               activeCheckpoint: checkpoint)
    }

    private func settingsFixture() -> SettingsDocument {
        SettingsDocument(launchAtLogin: true, feedbackDraft: FeedbackDraft(type: .idea, email: "person@example.com", message: "A saved private draft\nwith two lines"))
    }

    private func account() -> SlackAccount {
        SlackAccount(workspaceID: "T1", userID: "U1", workspaceName: "Workspace", userName: "User")
    }

    private func ownership() -> SlackOwnership {
        SlackOwnership(account: account(), cycleID: UUID(), previous: SlackProfile(text: "Previous status", emoji: ":wave:", expiration: 1_900_000_000))
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private func failure(from operation: () async throws -> Void) async -> StoreFailure? {
        do {
            try await operation()
            Issue.record("Expected a visible storage failure")
            return nil
        } catch let failure as StoreFailure {
            return failure
        } catch {
            Issue.record("Unexpected error type: \(error)")
            return nil
        }
    }
}
