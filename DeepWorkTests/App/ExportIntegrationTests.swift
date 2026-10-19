import AppKit
import Foundation
import Testing
import DeepWorkCore
@testable import DeepWorkApp

@MainActor
final class RecordingCSVExporter: CSVFileExporting {
    struct Request { let data: Data; let filename: String }
    var requests: [Request] = []
    var result: CSVFileExportResult = .saved(URL(fileURLWithPath: "/unused-test-destination.csv"))
    var hold = false
    private var pending: CheckedContinuation<CSVFileExportResult, Never>?
    func save(data: Data, suggestedFilename: String) async -> CSVFileExportResult {
        requests.append(Request(data: data, filename: suggestedFilename))
        if hold { return await withCheckedContinuation { pending = $0 } }
        return result
    }
    func finish(_ result: CSVFileExportResult) { pending?.resume(returning: result); pending = nil }
}

extension NativeApplicationTests {
@Suite(.serialized)
@MainActor
struct ExportIntegrationTests {
    private let calendar = ReportingCalendar(timeZone: .gmt)
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkExport-\(UUID())") }
    private func clock() throws -> TestTimerClock {
        let clock = TestTimerClock()
        clock.date = try #require(calendar.parseLocalDateTime("2026-10-19T12:00"))
        return clock
    }
    private func app(_ directory: URL, clock: TestTimerClock, exporter: any CSVFileExporting) -> AppModel {
        AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                 clock: clock, automaticRefresh: false, reportingTimeZone: .gmt, csvFileExporter: exporter)
    }
    private func configure(_ model: AppModel) {
        model.focusSelection.wrappedValue = .custom; model.breakSelection.wrappedValue = .custom
        model.customFocusText = "1"; model.customBreakText = "1"
    }
    private func complete(at start: Date) -> SessionRecord {
        SessionRecord(startedAt: start, endedAt: start + 60, plannedFocusMinutes: 1, outcome: .complete,
                      segments: [ActiveSegment(startedAt: start, endedAt: start + 60)])
    }
    private func rows(_ request: RecordingCSVExporter.Request) -> [[String]] {
        // Integration fixtures contain no embedded line breaks or quotes;
        // escaping and arbitrary fields are independently covered by core tests.
        String(decoding: request.data, as: UTF8.self).components(separatedBy: "\r\n").dropFirst().map {
            String($0.dropFirst().dropLast()).components(separatedBy: "\",\"")
        }
    }
    private func waitForRequest(_ exporter: RecordingCSVExporter) async throws {
        for _ in 0..<500 {
            if !exporter.requests.isEmpty { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        try #require(!exporter.requests.isEmpty, "The export did not reach the injected destination chooser")
    }

    @Test func testJ048_J051_S007_S010_AC19AllPagesAndBothCurrentEntryPointsMatch() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try clock(); let exporter = RecordingCSVExporter()
        let today = (0..<25).map { complete(at: clock.date - Double(($0 + 1) * 120)) }
        let yesterday = complete(at: clock.date - 86_400)
        #expect(JournalStore(directory: directory).save(JournalDocument(records: today + [yesterday])) == nil)
        let model = app(directory, clock: clock, exporter: exporter)
        model.reportPeriod = .day; model.nextSessionPage()
        #expect(model.visibleSessionRows.count == 12 && model.sessionPage == 1)
        #expect(model.reportSnapshot.rows.count == 25)
        await model.exportJournalCSV()
        let journal = try #require(exporter.requests.first)
        #expect(rows(journal).count == 25)
        #expect(rows(journal).reduce(0) { $0 + (Double($1[10]) ?? -1) } == 1_500)
        #expect(rows(journal).allSatisfy { $0[0] == "Journal" && $0[12] == "1" })
        #expect(model.journalExportStatus == "Report exported as CSV.")
        model.selectedTab = .settings; model.exportScope = .current
        await model.exportSettingsCSV()
        #expect(exporter.requests.count == 2)
        #expect(exporter.requests[1].data == journal.data)
        #expect(exporter.requests[1].filename == journal.filename)
        #expect(model.settingsExportStatus == "Your journal exported as CSV.")
        #expect(model.sessionPage == 1)
        model.exportScope = .all
        #expect(model.settingsExportStatus == nil)
        await model.exportSettingsCSV()
        let all = exporter.requests[2]
        #expect(rows(all).count == 26)
        #expect(rows(all).allSatisfy { $0[1].isEmpty && $0[2].isEmpty && $0[10] == $0[11] })
        #expect(all.filename == "deep-work-journal-all-sessions.csv")
        #expect(Set(rows(all).map { $0[5] }) == Set((today + [yesterday]).map { $0.id.uuidString }))
        await model.flushPersistence()
        #expect(JournalStore(directory: directory).load().value.records == today + [yesterday])
    }

    @Test func testJ017_J020_J048_S007_S008_AC21ExamplesAreExplicitAndAllHistoryStaysActual() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try clock(); let exporter = RecordingCSVExporter(); let model = app(directory, clock: clock, exporter: exporter)
        #expect(model.exportScope == .all && model.showingExamples)
        #expect(!model.canExportSettings && model.canExportJournal)
        #expect(model.settingsExportSummary == "Your journal has no sessions yet. Choose Current Journal Report to export the example.")
        await model.exportSettingsCSV(); #expect(exporter.requests.isEmpty)
        model.exportScope = .current
        #expect(model.canExportSettings && model.settingsExportSummary.hasPrefix("Example data ·"))
        await model.exportSettingsCSV()
        let examples = try #require(exporter.requests.first)
        #expect(rows(examples).allSatisfy { $0[0] == "Example" })
        #expect(examples.filename.hasPrefix("deep-work-example-"))
        #expect(model.settingsExportStatus == "Example report exported as CSV.")
        configure(model); model.startFocus(); clock.advance(17); model.pauseTimer()
        model.toggleExamples(); #expect(model.showingExamples)
        model.exportScope = .all
        await model.exportSettingsCSV()
        let all = exporter.requests[1]
        #expect(rows(all).count == 1 && rows(all)[0][0] == "Journal")
        #expect(rows(all)[0][8] == "live" && rows(all)[0][10] == "17" && rows(all)[0][12] == "0")
        #expect(model.timer.isPaused && model.timer.remainingSeconds == 43)
        await model.flushPersistence()
        #expect(JournalStore(directory: directory).load().value.records.isEmpty)
        let restored = app(directory, clock: clock, exporter: RecordingCSVExporter())
        #expect(restored.exportScope == .all)
        await restored.flushPersistence()
    }

    @Test func testS008_S009InvalidAndEmptyReportsCannotOpenSavePanel() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try clock(); let exporter = RecordingCSVExporter(); let model = app(directory, clock: clock, exporter: exporter)
        model.showActualJournal(); model.exportScope = .current
        #expect(model.settingsExportSummary == "Your journal · 0 sessions · 0s of focus in the selected Journal range.")
        #expect(!model.canExportSettings && !model.canExportJournal)
        model.reportPeriod = .range; model.rangeUntilText = "invalid"
        #expect(model.settingsExportSummary == "Choose a valid date range in Journal first.")
        await model.exportJournalCSV(); await model.exportSettingsCSV()
        #expect(exporter.requests.isEmpty)
        #expect(model.settingsExportStatus == nil && model.journalExportStatus == nil)
        configure(model); model.startFocus(); model.exportScope = .all
        #expect(!model.canExportSettings) // Zero focused time is not an export row.
        clock.advance(1); model.refreshTimer()
        #expect(model.canExportSettings) // All history ignores the invalid Journal range.
        await model.exportSettingsCSV(); #expect(exporter.requests.count == 1)
        await model.flushPersistence()
    }

    @Test func testJ053_S008SettingsSummaryRefreshesWhileRunningAndExcludesPauseAndBreak() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try clock(); let exporter = RecordingCSVExporter(); let model = app(directory, clock: clock, exporter: exporter)
        configure(model); model.startFocus(); model.selectedTab = .settings; model.exportScope = .current
        clock.advance(12); model.refreshTimer()
        #expect(model.settingsExportSummary == "Your journal · 1 session · 12s of focus in the selected Journal range.")
        #expect(model.reportSnapshot.focusedSeconds == 12)
        model.pauseTimer(); clock.advance(600); model.refreshTimer()
        #expect(model.reportSnapshot.focusedSeconds == 12)
        model.resumeTimer(); clock.advance(48); model.refreshTimer()
        #expect(model.timer.state == .break && model.reportSnapshot.focusedSeconds == 60)
        clock.advance(10); model.refreshTimer()
        #expect(model.settingsExportSummary.contains("1m of focus"))
        await model.flushPersistence()
    }

    @Test func testJ048_S009_AC09ExportReconcilesExpiredBoundaryExactlyOnce() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try clock(); let exporter = RecordingCSVExporter(); let model = app(directory, clock: clock, exporter: exporter)
        configure(model); model.startFocus(); let id = try #require(model.timer.liveRecord?.id)
        clock.advance(60) // Deliberately omit the UI refresh callback.
        await model.exportSettingsCSV()
        let exported = rows(try #require(exporter.requests.first))
        #expect(exported.count == 1 && exported[0][5] == id.uuidString)
        #expect(exported[0][8] == "complete" && exported[0][10] == "60" && exported[0][12] == "1")
        #expect(model.timer.state == .break && !model.timer.isPaused)
        await model.exportJournalCSV(); #expect(model.journal.records.count == 1)
        await model.flushPersistence()
        #expect(JournalStore(directory: directory).load().value.records.count == 1)
    }

    @Test func testJ048_S009_AC21LiveExportDoesNotPauseOrCompleteAndSnapshotSurvivesDelay() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try clock(); let exporter = RecordingCSVExporter(); exporter.hold = true
        let model = app(directory, clock: clock, exporter: exporter)
        configure(model); model.startFocus(); clock.advance(10)
        let exporting = Task { await model.exportSettingsCSV() }
        try await waitForRequest(exporter)
        #expect(model.isExporting && !model.canExportSettings && !model.canExportJournal)
        #expect(model.settingsExportStatus == nil)
        await model.exportSettingsCSV(); await model.exportJournalCSV()
        #expect(exporter.requests.count == 1)
        clock.advance(15); model.refreshTimer()
        #expect(model.timer.liveRecord?.focusedSeconds == 25 && !model.timer.isPaused)
        #expect(rows(exporter.requests[0])[0][10] == "10")
        #expect(rows(exporter.requests[0])[0][8] == "live" && rows(exporter.requests[0])[0][12] == "0")
        exporter.finish(.saved(URL(fileURLWithPath: "/unused-test-destination.csv")))
        await exporting.value
        #expect(!model.isExporting && model.settingsExportStatus == "Your journal exported as CSV.")
        #expect(model.journal.records.isEmpty && model.timer.remainingSeconds == 35)
        await model.flushPersistence()
    }

    @Test func testJ050_S011_AC23CancelFailureRetryAndScopeChangeCannotClaimWrongSuccess() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try clock(); let exporter = RecordingCSVExporter(); let model = app(directory, clock: clock, exporter: exporter)
        model.exportScope = .current
        exporter.result = .cancelled
        await model.exportSettingsCSV()
        #expect(model.settingsExportStatus == nil && model.settingsExportError == nil)
        exporter.result = .failed("Disk is full.")
        await model.exportSettingsCSV()
        #expect(model.settingsExportStatus == nil && model.settingsExportError == "CSV could not be saved. Disk is full.")
        await model.exportJournalCSV()
        #expect(model.journalExportError == "CSV could not be saved. Disk is full." && model.journalExportStatus == nil)
        exporter.result = .saved(URL(fileURLWithPath: "/unused-test-destination.csv"))
        await model.exportJournalCSV()
        #expect(model.journalExportStatus == "Report exported as CSV." && model.journalExportError == nil)
        exporter.hold = true; exporter.requests.removeAll()
        let exporting = Task { await model.exportSettingsCSV() }
        try await waitForRequest(exporter)
        model.exportScope = .all
        exporter.finish(.saved(URL(fileURLWithPath: "/unused-test-destination.csv")))
        await exporting.value
        #expect(model.settingsExportStatus == nil && model.settingsExportError == nil)
        #expect(model.journal.records.isEmpty)
        await model.flushPersistence()
    }

    @Test func testJ052_S021_AC27RealFailedSQLiteStillAllowsExportAndRetainsState() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        try Data("unavailable directory".utf8).write(to: directory)
        let clock = try clock(); let exporter = RecordingCSVExporter(); let model = app(directory, clock: clock, exporter: exporter)
        configure(model); model.startFocus(); clock.advance(19); model.endSession()
        await model.flushPersistence()
        #expect(model.journalFailure != nil && model.settingsFailure != nil)
        #expect(model.journalStorageMessage == "Saving unavailable · export your journal to keep it")
        await model.exportSettingsCSV()
        #expect(rows(try #require(exporter.requests.first))[0][10] == "19")
        #expect(model.settingsExportStatus == "Your journal exported as CSV.")
        #expect(model.journal.records.count == 1)
        #expect(!(await model.prepareForTermination()))
    }

    @Test func testS009QuitPreventsNewExportAndSavedScopeRemainsTransient() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try clock(); let exporter = RecordingCSVExporter(); let model = app(directory, clock: clock, exporter: exporter)
        model.exportScope = .current
        #expect(await model.prepareForTermination())
        #expect(!model.canExportSettings && !model.canExportJournal)
        await model.exportSettingsCSV(); await model.exportJournalCSV()
        #expect(exporter.requests.isEmpty)
        let restored = app(directory, clock: clock, exporter: RecordingCSVExporter())
        #expect(restored.exportScope == .all)
        await restored.flushPersistence()
    }

    @Test(arguments: [false, true])
    func testS009_AC23QuitDrainsAcceptedCSVWriteAndFailedWriteKeepsAppOpen(fails: Bool) async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try clock(); let writer = HeldExportWriter()
        let exporter = NativeCSVFileExportService(destinationChooser: ConfirmedExportDestination(), writer: writer)
        let model = app(directory, clock: clock, exporter: exporter)
        configure(model); model.startFocus(); clock.advance(17)
        let exporting = Task { await model.exportSettingsCSV() }
        for _ in 0..<500 {
            if await writer.started { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        try #require(await writer.started)
        var quitFinished = false
        let quitting = Task { let saved = await model.prepareForTermination(); quitFinished = true; return saved }
        for _ in 0..<500 {
            if model.timer.isPaused { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(model.timer.isPaused && model.isTerminating)
        #expect(!quitFinished && model.isExporting)
        await writer.finish(fails: fails)
        #expect(await quitting.value == !fails)
        await exporting.value
        #expect(quitFinished && !model.isExporting)
        #expect(model.timer.isPaused && model.timer.remainingSeconds == 43)
        #expect(JournalStore(directory: directory).load().value.activeCheckpoint?.remainingSeconds == 43)
        if fails {
            #expect(!model.isTerminating && model.lifecycleFailureMessage?.contains("CSV export could not be saved") == true)
            #expect(model.settingsExportError != nil && model.canExportSettings)
            // Keeping the app open after failed Quit must permit a fresh Save.
            await writer.allowImmediateSuccess()
            await model.exportSettingsCSV()
            #expect(model.settingsExportStatus == "Your journal exported as CSV." && model.settingsExportError == nil)
            #expect(await model.prepareForTermination())
        } else {
            #expect(model.isTerminating && model.lifecycleFailureMessage == nil)
        }
    }
}
}

@MainActor
private struct ConfirmedExportDestination: CSVSaveDestinationChoosing {
    func chooseDestination(suggestedFilename: String) async throws -> URL? {
        URL(fileURLWithPath: "/unused-held-writer.csv")
    }
}

private actor HeldExportWriter: CSVFileWriting {
    private(set) var started = false
    private var immediatelySucceeds = false
    private var continuation: CheckedContinuation<Void, any Error>?
    func write(_ data: Data, to destination: URL) async throws {
        started = true
        if immediatelySucceeds { return }
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(fails: Bool) {
        if fails { continuation?.resume(throwing: CocoaError(.fileWriteOutOfSpace)) }
        else { continuation?.resume() }
        continuation = nil
    }
    func allowImmediateSuccess() { immediatelySucceeds = true }
}
